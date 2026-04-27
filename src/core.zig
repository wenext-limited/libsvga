const std = @import("std");
const model = @import("model.zig");
const parser = @import("parser.zig");

pub const default_max_input_bytes: usize = 256 * 1024 * 1024;

pub const ParseFileOptions = struct {
    max_input_bytes: usize = default_max_input_bytes,
};

pub fn parseMovie(allocator: std.mem.Allocator, bytes: []const u8) !*model.Movie {
    var parsed = try parser.parseMovieMetadata(allocator, bytes);
    defer parsed.deinit(allocator);

    const movie = try allocator.create(model.Movie);
    errdefer allocator.destroy(movie);

    movie.* = try model.Movie.init(allocator, parsed.spec);
    return movie;
}

pub fn parseMovieFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    options: ParseFileOptions,
) !*model.Movie {
    const input = try std.fs.cwd().readFileAlloc(allocator, path, options.max_input_bytes);
    defer allocator.free(input);

    return parseMovie(allocator, input);
}

pub fn destroyMovie(allocator: std.mem.Allocator, movie: *model.Movie) void {
    movie.deinit(allocator);
    allocator.destroy(movie);
}

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
