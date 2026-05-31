const std = @import("std");
const builtin = @import("builtin");
const model = @import("model.zig");
const parser = @import("parser.zig");

pub const default_max_input_bytes: usize = 64 * 1024 * 1024;
pub const default_max_output_bytes: usize = parser.default_max_output_bytes;

/// Parser memory limits. `max_output_bytes` caps decompressed zlib/ZIP payloads.
pub const ParseOptions = struct {
    max_output_bytes: usize = default_max_output_bytes,
};

const has_network = switch (builtin.target.os.tag) {
    .freestanding, .wasi, .emscripten => false,
    else => true,
};

/// Filesystem parser limits. The default is intentionally high enough for
/// production SVGA files while still preventing accidental unbounded reads.
pub const ParseFileOptions = struct {
    max_input_bytes: usize = default_max_input_bytes,
    max_output_bytes: usize = default_max_output_bytes,
};

/// Download parser limits. The default matches ParseFileOptions so every
/// byte-source convenience API has the same memory ceiling.
pub const DownloadOptions = struct {
    max_input_bytes: usize = default_max_input_bytes,
    max_output_bytes: usize = default_max_output_bytes,
};

/// Parse SVGA bytes into an owned, immutable Movie.
///
/// The returned pointer must be released with destroyMovie() using the same
/// allocator. Supported inputs are ZIP SVGA packages and zlib-compressed
/// movie.binary payloads.
pub fn parseMovie(allocator: std.mem.Allocator, bytes: []const u8) !*model.Movie {
    return parseMovieWithOptions(allocator, bytes, .{});
}

/// Parse SVGA bytes with explicit parser limits.
pub fn parseMovieWithOptions(allocator: std.mem.Allocator, bytes: []const u8, options: ParseOptions) !*model.Movie {
    var parsed = try parser.parseMovieMetadataWithOptions(allocator, bytes, .{
        .max_output_bytes = options.max_output_bytes,
    });
    defer parsed.deinit(allocator);

    const movie = try allocator.create(model.Movie);
    errdefer allocator.destroy(movie);

    movie.* = try model.Movie.init(allocator, parsed.spec);
    return movie;
}

/// Read a file from the current working directory and parse it as SVGA bytes.
pub fn parseMovieFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    options: ParseFileOptions,
) !*model.Movie {
    const input = try std.fs.cwd().readFileAlloc(allocator, path, options.max_input_bytes);
    defer allocator.free(input);

    return parseMovieWithOptions(allocator, input, .{
        .max_output_bytes = options.max_output_bytes,
    });
}

/// Download SVGA bytes into memory and parse them without touching disk.
///
/// This helper intentionally owns only the fetch-to-bytes step. Filesystem
/// caches, custom headers, authentication, and platform session policy remain
/// responsibilities of higher-level integrations.
pub fn downloadMovie(
    allocator: std.mem.Allocator,
    url: []const u8,
    options: DownloadOptions,
) !*model.Movie {
    const input = try downloadBytes(allocator, url, options);
    defer allocator.free(input);

    return parseMovieWithOptions(allocator, input, .{
        .max_output_bytes = options.max_output_bytes,
    });
}

/// Download URL bytes into an owned buffer. The caller owns the returned slice.
pub fn downloadBytes(
    allocator: std.mem.Allocator,
    url: []const u8,
    options: DownloadOptions,
) ![]u8 {
    if (url.len == 0) return error.InvalidUrl;
    if (options.max_input_bytes == 0) return error.StreamTooLong;
    if (!comptime has_network) return error.UnsupportedNetwork;

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var body = LimitedDownloadBody.init(allocator, options.max_input_bytes);
    defer body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
        .keep_alive = false,
    }) catch |err| switch (err) {
        error.WriteFailed => if (body.too_long) return error.StreamTooLong else return error.OutOfMemory,
        else => |e| return e,
    };

    if (result.status.class() != .success) return error.HttpStatusError;
    return body.toOwnedSlice();
}

/// Destroy a Movie allocated by parseMovie(), parseMovieFile(), or callers that
/// directly allocate and initialize model.Movie.
pub fn destroyMovie(allocator: std.mem.Allocator, movie: *model.Movie) void {
    movie.deinit(allocator);
    allocator.destroy(movie);
}

const LimitedDownloadBody = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    max_bytes: usize,
    too_long: bool = false,
    writer: std.Io.Writer,

    fn init(allocator: std.mem.Allocator, max_bytes: usize) LimitedDownloadBody {
        return .{
            .allocator = allocator,
            .bytes = .empty,
            .max_bytes = max_bytes,
            .writer = .{
                .buffer = &.{},
                .vtable = &.{
                    .drain = drain,
                },
            },
        };
    }

    fn deinit(self: *LimitedDownloadBody) void {
        self.bytes.deinit(self.allocator);
    }

    fn toOwnedSlice(self: *LimitedDownloadBody) ![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }

    fn drain(
        writer: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const self: *LimitedDownloadBody = @fieldParentPtr("writer", writer);
        var consumed: usize = 0;

        if (writer.end > 0) {
            try self.append(writer.buffer[0..writer.end]);
            writer.end = 0;
        }

        for (data[0 .. data.len - 1]) |bytes| {
            try self.append(bytes);
            consumed += bytes.len;
        }

        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            try self.append(pattern);
            consumed += pattern.len;
        }

        return consumed;
    }

    fn append(self: *LimitedDownloadBody, bytes: []const u8) std.Io.Writer.Error!void {
        if (bytes.len > self.max_bytes - self.bytes.items.len) {
            self.too_long = true;
            return error.WriteFailed;
        }
        self.bytes.appendSlice(self.allocator, bytes) catch return error.WriteFailed;
    }
};

test "core parses and destroys a movie from bytes" {
    const proto = [_]u8{
        0x0a, 0x05, '2',  '.',  '1',  '.',  '0',
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c,
    };

    const zip = try storedZip(std.testing.allocator, "movie.binary", &proto);
    defer std.testing.allocator.free(zip);

    const movie = try parseMovie(std.testing.allocator, zip);
    defer destroyMovie(std.testing.allocator, movie);

    const info = movie.info();
    try std.testing.expectEqual(@as(f32, 320), info.view_box_width);
    try std.testing.expectEqual(@as(f32, 240), info.view_box_height);
    try std.testing.expectEqual(@as(i32, 30), info.fps);
    try std.testing.expectEqual(@as(i32, 60), info.frames);
}

test "core parses and destroys a movie from a filesystem path" {
    const proto = [_]u8{
        0x0a, 0x05, '2',  '.',  '1',  '.',  '0',
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c,
    };

    const zip = try storedZip(std.testing.allocator, "movie.binary", &proto);
    defer std.testing.allocator.free(zip);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "fixture.svga", .data = zip });
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "fixture.svga");
    defer std.testing.allocator.free(path);

    const movie = try parseMovieFile(std.testing.allocator, path, .{});
    defer destroyMovie(std.testing.allocator, movie);

    try std.testing.expectEqual(@as(i32, 60), movie.frames);
}

test "core download rejects empty URLs before network access" {
    try std.testing.expectError(
        error.InvalidUrl,
        downloadBytes(std.testing.allocator, "", .{}),
    );
}

test "download body enforces byte limit while streaming" {
    var body = LimitedDownloadBody.init(std.testing.allocator, 3);
    defer body.deinit();

    try body.writer.writeAll("abc");
    try std.testing.expectError(error.WriteFailed, body.writer.writeAll("d"));
    try std.testing.expect(body.too_long);
}

fn storedZip(test_allocator: std.mem.Allocator, name: []const u8, data: []const u8) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(test_allocator);

    try bytes.resize(test_allocator, 30 + name.len + data.len);
    @memset(bytes.items, 0);

    std.mem.writeInt(u32, bytes.items[0..4], 0x04034b50, .little);
    std.mem.writeInt(u32, bytes.items[18..22], @intCast(data.len), .little);
    std.mem.writeInt(u32, bytes.items[22..26], @intCast(data.len), .little);
    std.mem.writeInt(u16, bytes.items[26..28], @intCast(name.len), .little);
    @memcpy(bytes.items[30 .. 30 + name.len], name);
    @memcpy(bytes.items[30 + name.len ..], data);

    return bytes.toOwnedSlice(test_allocator);
}
