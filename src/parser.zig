const std = @import("std");
const build_options = @import("build_options");
const model = @import("model.zig");
const flate = std.compress.flate;
const zlib = if (build_options.use_system_zlib) @cImport({
    @cInclude("zlib.h");
}) else struct {};

pub const ParseError = error{
    UnsupportedContainer,
    UnsupportedZip,
    UnsupportedZipMethod,
    InvalidData,
    InvalidWireType,
    TruncatedInput,
    InvalidZlibStream,
    InvalidDeflateStream,
    MissingMovieParams,
    MissingMovieSpec,
    InvalidJson,
} || std.mem.Allocator.Error;

const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    start_group = 3,
    end_group = 4,
    fixed32 = 5,
};

const MovieParams = struct {
    view_box_width: f32 = 100,
    view_box_height: f32 = 100,
    fps: i32 = 20,
    frames: i32 = 0,
    seen: bool = false,
};

pub const MovieMetadata = struct {
    spec: model.MovieSpec,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *MovieMetadata, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn parseMovieMetadata(allocator: std.mem.Allocator, bytes: []const u8) ParseError!MovieMetadata {
    if (bytes.len < 2) return error.InvalidData;

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    if (isZip(bytes)) {
        return .{
            .spec = try parseZipPackage(arena.allocator(), bytes),
            .arena = arena,
        };
    }
    if (!isZlibStream(bytes)) return error.InvalidData;

    const inflated = try inflateZlib(allocator, bytes);
    defer allocator.free(inflated);

    return .{
        .spec = try parseMovieProto(arena.allocator(), inflated),
        .arena = arena,
    };
}

pub fn isZip(bytes: []const u8) bool {
    return bytes.len >= 2 and bytes[0] == 'P' and bytes[1] == 'K';
}

fn isZlibStream(bytes: []const u8) bool {
    if (bytes.len < 2) return false;
    const cmf = bytes[0];
    const flg = bytes[1];
    const compression_method = cmf & 0x0f;
    const compression_info = cmf >> 4;
    const header = (@as(u16, cmf) << 8) | flg;

    return compression_method == 8 and
        compression_info <= 7 and
        (flg & 0x20) == 0 and
        header % 31 == 0;
}

pub fn parseMovieProto(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.MovieSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var version: []const u8 = "";
    var params = MovieParams{};
    var assets: std.ArrayList(model.AssetSpec) = .empty;
    var sprites: std.ArrayList(model.SpriteSpec) = .empty;
    var audios: std.ArrayList(model.AudioSpec) = .empty;

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => version = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            2 => {
                const params_bytes = try reader.readLengthDelimited(tag.wire_type);
                params = try parseMovieParams(params_bytes);
            },
            3 => {
                const asset_bytes = try reader.readLengthDelimited(tag.wire_type);
                try assets.append(allocator, try parseAssetMapEntry(allocator, asset_bytes));
            },
            4 => {
                const sprite_bytes = try reader.readLengthDelimited(tag.wire_type);
                try sprites.append(allocator, try parseSprite(allocator, sprite_bytes));
            },
            5 => {
                const audio_bytes = try reader.readLengthDelimited(tag.wire_type);
                try audios.append(allocator, try parseAudio(allocator, audio_bytes));
            },
            else => try reader.skip(tag.wire_type),
        }
    }

    if (!params.seen) return error.MissingMovieParams;

    return .{
        .version = version,
        .view_box_width = params.view_box_width,
        .view_box_height = params.view_box_height,
        .fps = params.fps,
        .frames = params.frames,
        .image_count = @intCast(assets.items.len),
        .sprite_count = @intCast(sprites.items.len),
        .audio_count = @intCast(audios.items.len),
        .assets = try assets.toOwnedSlice(allocator),
        .sprites = try sprites.toOwnedSlice(allocator),
        .audios = try audios.toOwnedSlice(allocator),
    };
}

fn parseAssetMapEntry(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.AssetSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var key: []const u8 = "";
    var value: []const u8 = "";

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => key = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            2 => value = try reader.readLengthDelimited(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    if (std.unicode.utf8ValidateSlice(value)) {
        return .{
            .key = key,
            .kind = .filename,
            .filename = try allocator.dupe(u8, value),
        };
    }

    const owned_bytes = try allocator.dupe(u8, value);
    return .{
        .key = key,
        .kind = if (isMp3Data(value)) .audio_bytes else .image_bytes,
        .bytes = owned_bytes,
    };
}

fn parseAudio(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.AudioSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var audio = model.AudioSpec{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => audio.audio_key = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            2 => audio.start_frame = try readInt32(&reader, tag.wire_type),
            3 => audio.end_frame = try readInt32(&reader, tag.wire_type),
            4 => audio.start_time_ms = try readInt32(&reader, tag.wire_type),
            5 => audio.total_time_ms = try readInt32(&reader, tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return audio;
}

fn parseMovieParams(bytes: []const u8) ParseError!MovieParams {
    var reader = ProtoReader{ .bytes = bytes };
    var params = MovieParams{ .seen = true };

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => params.view_box_width = try reader.readFixed32Float(tag.wire_type),
            2 => params.view_box_height = try reader.readFixed32Float(tag.wire_type),
            3 => params.fps = try readInt32(&reader, tag.wire_type),
            4 => params.frames = try readInt32(&reader, tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return params;
}

fn parseSprite(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.SpriteSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var image_key: []const u8 = "";
    var matte_key: []const u8 = "";
    var frames: std.ArrayList(model.FrameSpec) = .empty;

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => image_key = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            2 => {
                const frame_bytes = try reader.readLengthDelimited(tag.wire_type);
                try frames.append(allocator, try parseFrame(allocator, frame_bytes));
            },
            3 => matte_key = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            else => try reader.skip(tag.wire_type),
        }
    }

    return .{
        .image_key = image_key,
        .matte_key = matte_key,
        .frames = try frames.toOwnedSlice(allocator),
    };
}

fn parseFrame(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.FrameSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var frame = model.Frame{};
    var clip_path: []const u8 = "";
    var shapes: std.ArrayList(model.ShapeSpec) = .empty;

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => frame.alpha = try reader.readFixed32Float(tag.wire_type),
            2 => frame.layout = try parseLayout(try reader.readLengthDelimited(tag.wire_type)),
            3 => frame.transform = try parseTransform(try reader.readLengthDelimited(tag.wire_type)),
            4 => clip_path = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            5 => {
                const shape_bytes = try reader.readLengthDelimited(tag.wire_type);
                const shape = try parseShape(allocator, shape_bytes);
                if (frame.shape_count == 0) frame.first_shape_type = @intFromEnum(shape.shape_type);
                frame.shape_count += 1;
                try shapes.append(allocator, shape);
            },
            else => try reader.skip(tag.wire_type),
        }
    }

    frame = model.computeFrame(frame);
    return .{
        .frame = frame,
        .clip_path = clip_path,
        .shapes = try shapes.toOwnedSlice(allocator),
    };
}

fn parseLayout(bytes: []const u8) ParseError!model.Layout {
    var reader = ProtoReader{ .bytes = bytes };
    var layout = model.Layout{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => layout.x = try reader.readFixed32Float(tag.wire_type),
            2 => layout.y = try reader.readFixed32Float(tag.wire_type),
            3 => layout.width = try reader.readFixed32Float(tag.wire_type),
            4 => layout.height = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return layout;
}

fn parseTransform(bytes: []const u8) ParseError!model.Transform {
    var reader = ProtoReader{ .bytes = bytes };
    var transform = model.Transform{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => transform.a = try reader.readFixed32Float(tag.wire_type),
            2 => transform.b = try reader.readFixed32Float(tag.wire_type),
            3 => transform.c = try reader.readFixed32Float(tag.wire_type),
            4 => transform.d = try reader.readFixed32Float(tag.wire_type),
            5 => transform.tx = try reader.readFixed32Float(tag.wire_type),
            6 => transform.ty = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return transform;
}

fn parseShape(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.ShapeSpec {
    var reader = ProtoReader{ .bytes = bytes };
    var shape = model.ShapeSpec{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => {
                const raw = try reader.readVarintFor(tag.wire_type);
                shape.shape_type = shapeTypeFromRaw(raw);
            },
            2 => shape.path_data = try parseShapeArgs(allocator, try reader.readLengthDelimited(tag.wire_type)),
            3 => shape.rect = try parseRectArgs(try reader.readLengthDelimited(tag.wire_type)),
            4 => shape.ellipse = try parseEllipseArgs(try reader.readLengthDelimited(tag.wire_type)),
            10 => {
                shape.styles = try parseShapeStyle(try reader.readLengthDelimited(tag.wire_type));
                shape.has_styles = true;
            },
            11 => {
                shape.transform = try parseTransform(try reader.readLengthDelimited(tag.wire_type));
                shape.has_transform = true;
            },
            else => try reader.skip(tag.wire_type),
        }
    }

    return shape;
}

fn parseShapeArgs(allocator: std.mem.Allocator, bytes: []const u8) ParseError![]const u8 {
    var reader = ProtoReader{ .bytes = bytes };
    var path_data: []const u8 = "";

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => path_data = try allocator.dupe(u8, try reader.readLengthDelimited(tag.wire_type)),
            else => try reader.skip(tag.wire_type),
        }
    }

    return path_data;
}

fn parseRectArgs(bytes: []const u8) ParseError!model.RectArgs {
    var reader = ProtoReader{ .bytes = bytes };
    var rect = model.RectArgs{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => rect.x = try reader.readFixed32Float(tag.wire_type),
            2 => rect.y = try reader.readFixed32Float(tag.wire_type),
            3 => rect.width = try reader.readFixed32Float(tag.wire_type),
            4 => rect.height = try reader.readFixed32Float(tag.wire_type),
            5 => rect.corner_radius = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return rect;
}

fn parseEllipseArgs(bytes: []const u8) ParseError!model.EllipseArgs {
    var reader = ProtoReader{ .bytes = bytes };
    var ellipse = model.EllipseArgs{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => ellipse.x = try reader.readFixed32Float(tag.wire_type),
            2 => ellipse.y = try reader.readFixed32Float(tag.wire_type),
            3 => ellipse.radius_x = try reader.readFixed32Float(tag.wire_type),
            4 => ellipse.radius_y = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return ellipse;
}

fn parseShapeStyle(bytes: []const u8) ParseError!model.ShapeStyle {
    var reader = ProtoReader{ .bytes = bytes };
    var style = model.ShapeStyle{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => {
                style.fill = try parseColor(try reader.readLengthDelimited(tag.wire_type));
                style.has_fill = 1;
            },
            2 => {
                style.stroke = try parseColor(try reader.readLengthDelimited(tag.wire_type));
                style.has_stroke = 1;
            },
            3 => style.stroke_width = try reader.readFixed32Float(tag.wire_type),
            4 => style.line_cap = try readInt32(&reader, tag.wire_type),
            5 => style.line_join = try readInt32(&reader, tag.wire_type),
            6 => style.miter_limit = try reader.readFixed32Float(tag.wire_type),
            7 => style.line_dash_i = try reader.readFixed32Float(tag.wire_type),
            8 => style.line_dash_ii = try reader.readFixed32Float(tag.wire_type),
            9 => style.line_dash_iii = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return style;
}

fn parseColor(bytes: []const u8) ParseError!model.Color {
    var reader = ProtoReader{ .bytes = bytes };
    var color = model.Color{};

    while (!reader.isDone()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => color.r = try reader.readFixed32Float(tag.wire_type),
            2 => color.g = try reader.readFixed32Float(tag.wire_type),
            3 => color.b = try reader.readFixed32Float(tag.wire_type),
            4 => color.a = try reader.readFixed32Float(tag.wire_type),
            else => try reader.skip(tag.wire_type),
        }
    }

    return color;
}

fn shapeTypeFromRaw(raw: u64) model.ShapeType {
    return switch (raw) {
        0 => .shape,
        1 => .rect,
        2 => .ellipse,
        3 => .keep,
        else => .unknown,
    };
}

fn readInt32(reader: *ProtoReader, wire_type: WireType) ParseError!i32 {
    const raw = try reader.readVarintFor(wire_type);
    if (raw > 0x7fffffff) return error.InvalidData;
    return @intCast(raw);
}

fn parseZipPackage(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.MovieSpec {
    const entries = try parseZipEntries(allocator, bytes);
    var movie_binary: ?[]const u8 = null;
    var movie_spec: ?[]const u8 = null;

    for (entries) |entry| {
        const name = normalizedZipName(entry.name);
        if (std.mem.eql(u8, name, "movie.binary")) {
            movie_binary = entry.data;
        } else if (std.mem.eql(u8, name, "movie.spec")) {
            movie_spec = entry.data;
        }
    }

    var spec = if (movie_binary) |proto_bytes|
        try parseMovieProto(allocator, proto_bytes)
    else if (movie_spec) |json_bytes|
        try parseLegacyJsonMovie(allocator, json_bytes)
    else
        return error.MissingMovieSpec;

    try appendZipFileAssets(allocator, &spec, entries);
    return spec;
}

const ZipEntry = struct {
    name: []const u8,
    data: []const u8,
};

fn parseZipEntries(allocator: std.mem.Allocator, bytes: []const u8) ParseError![]ZipEntry {
    if (findEndOfCentralDirectory(bytes)) |eocd| {
        return parseCentralDirectoryEntries(allocator, bytes, eocd);
    }

    return parseLocalZipEntries(allocator, bytes);
}

const EndOfCentralDirectory = struct {
    directory_offset: usize,
    directory_size: usize,
};

fn findEndOfCentralDirectory(bytes: []const u8) ?EndOfCentralDirectory {
    if (bytes.len < 22) return null;

    const max_comment_len = @min(bytes.len - 22, 0xffff);
    var distance_from_end: usize = 0;
    while (distance_from_end <= max_comment_len) : (distance_from_end += 1) {
        const index = bytes.len - 22 - distance_from_end;
        if (std.mem.readInt(u32, bytes[index..][0..4], .little) != 0x06054b50) continue;

        const comment_len = std.mem.readInt(u16, bytes[index + 20 ..][0..2], .little);
        if (@as(usize, comment_len) != distance_from_end) continue;

        const directory_size = std.mem.readInt(u32, bytes[index + 12 ..][0..4], .little);
        const directory_offset = std.mem.readInt(u32, bytes[index + 16 ..][0..4], .little);
        return .{
            .directory_offset = @intCast(directory_offset),
            .directory_size = @intCast(directory_size),
        };
    }

    return null;
}

fn parseCentralDirectoryEntries(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    eocd: EndOfCentralDirectory,
) ParseError![]ZipEntry {
    if (eocd.directory_offset > bytes.len) return error.TruncatedInput;
    if (eocd.directory_size > bytes.len - eocd.directory_offset) return error.TruncatedInput;

    var entries: std.ArrayList(ZipEntry) = .empty;
    var index = eocd.directory_offset;
    const directory_end = eocd.directory_offset + eocd.directory_size;

    while (index < directory_end) {
        if (directory_end - index < 46) return error.TruncatedInput;
        const signature = std.mem.readInt(u32, bytes[index..][0..4], .little);
        if (signature != 0x02014b50) return error.InvalidData;

        const method = std.mem.readInt(u16, bytes[index + 10 ..][0..2], .little);
        const compressed_size = std.mem.readInt(u32, bytes[index + 20 ..][0..4], .little);
        const uncompressed_size = std.mem.readInt(u32, bytes[index + 24 ..][0..4], .little);
        const name_len = std.mem.readInt(u16, bytes[index + 28 ..][0..2], .little);
        const extra_len = std.mem.readInt(u16, bytes[index + 30 ..][0..2], .little);
        const comment_len = std.mem.readInt(u16, bytes[index + 32 ..][0..2], .little);
        const local_header_offset = std.mem.readInt(u32, bytes[index + 42 ..][0..4], .little);

        const name_start = index + 46;
        const next_index = name_start + @as(usize, name_len) + @as(usize, extra_len) + @as(usize, comment_len);
        if (next_index > directory_end) return error.TruncatedInput;

        const local_index: usize = @intCast(local_header_offset);
        if (local_index + 30 > bytes.len) return error.TruncatedInput;
        if (std.mem.readInt(u32, bytes[local_index..][0..4], .little) != 0x04034b50) return error.InvalidData;

        const local_name_len = std.mem.readInt(u16, bytes[local_index + 26 ..][0..2], .little);
        const local_extra_len = std.mem.readInt(u16, bytes[local_index + 28 ..][0..2], .little);
        const data_start = local_index + 30 + @as(usize, local_name_len) + @as(usize, local_extra_len);
        if (data_start > bytes.len) return error.TruncatedInput;
        if (@as(usize, compressed_size) > bytes.len - data_start) return error.TruncatedInput;
        const data_end = data_start + @as(usize, compressed_size);

        const name = try allocator.dupe(u8, bytes[name_start .. name_start + name_len]);
        const compressed = bytes[data_start..data_end];
        const data = switch (method) {
            0 => try allocator.dupe(u8, compressed),
            8 => try inflateRawDeflate(allocator, compressed, uncompressed_size),
            else => return error.UnsupportedZipMethod,
        };

        try entries.append(allocator, .{ .name = name, .data = data });
        index = next_index;
    }

    return entries.toOwnedSlice(allocator);
}

fn parseLocalZipEntries(allocator: std.mem.Allocator, bytes: []const u8) ParseError![]ZipEntry {
    var entries: std.ArrayList(ZipEntry) = .empty;
    var index: usize = 0;
    var saw_local_header = false;

    while (index + 4 <= bytes.len) {
        const signature = std.mem.readInt(u32, bytes[index..][0..4], .little);
        switch (signature) {
            0x04034b50 => {},
            0x02014b50, 0x06054b50 => break,
            else => {
                if (!saw_local_header) return error.InvalidData;
                break;
            },
        }

        saw_local_header = true;
        if (bytes.len - index < 30) return error.TruncatedInput;

        const flags = std.mem.readInt(u16, bytes[index + 6 ..][0..2], .little);
        const method = std.mem.readInt(u16, bytes[index + 8 ..][0..2], .little);
        const compressed_size = std.mem.readInt(u32, bytes[index + 18 ..][0..4], .little);
        const uncompressed_size = std.mem.readInt(u32, bytes[index + 22 ..][0..4], .little);
        const name_len = std.mem.readInt(u16, bytes[index + 26 ..][0..2], .little);
        const extra_len = std.mem.readInt(u16, bytes[index + 28 ..][0..2], .little);

        if ((flags & 0x0008) != 0) return error.UnsupportedZip;

        const name_start = index + 30;
        const data_start = name_start + @as(usize, name_len) + @as(usize, extra_len);
        if (data_start > bytes.len) return error.TruncatedInput;
        if (@as(usize, compressed_size) > bytes.len - data_start) return error.TruncatedInput;
        const data_end = data_start + @as(usize, compressed_size);

        const name = try allocator.dupe(u8, bytes[name_start .. name_start + name_len]);
        const compressed = bytes[data_start..data_end];
        const data = switch (method) {
            0 => try allocator.dupe(u8, compressed),
            8 => try inflateRawDeflate(allocator, compressed, uncompressed_size),
            else => return error.UnsupportedZipMethod,
        };

        try entries.append(allocator, .{ .name = name, .data = data });
        index = data_end;
    }

    if (!saw_local_header) return error.InvalidData;
    return entries.toOwnedSlice(allocator);
}

fn appendZipFileAssets(allocator: std.mem.Allocator, spec: *model.MovieSpec, entries: []const ZipEntry) ParseError!void {
    var assets: std.ArrayList(model.AssetSpec) = .empty;
    try assets.appendSlice(allocator, spec.assets);

    for (entries) |entry| {
        const name = normalizedZipName(entry.name);
        if (name.len == 0 or std.mem.endsWith(u8, name, "/")) continue;
        if (std.mem.eql(u8, name, "movie.binary") or std.mem.eql(u8, name, "movie.spec")) continue;

        try assets.append(allocator, .{
            .key = name,
            .kind = if (isMp3Data(entry.data)) .audio_bytes else .image_bytes,
            .bytes = entry.data,
        });
    }

    spec.assets = try assets.toOwnedSlice(allocator);
}

fn normalizedZipName(name: []const u8) []const u8 {
    var result = name;
    while (std.mem.startsWith(u8, result, "./")) {
        result = result[2..];
    }
    while (std.mem.startsWith(u8, result, "/")) {
        result = result[1..];
    }
    return result;
}

fn inflateRawDeflate(allocator: std.mem.Allocator, bytes: []const u8, expected_size: u32) ParseError![]u8 {
    if (!comptime build_options.use_system_zlib) {
        return inflateWithStdFlate(
            allocator,
            bytes,
            .raw,
            if (expected_size > 0) @intCast(expected_size) else @max(bytes.len * 3 + 4096, 4096),
            error.InvalidDeflateStream,
        );
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    stream.next_in = @constCast(bytes.ptr);
    stream.avail_in = @intCast(bytes.len);

    if (zlib.inflateInit2_(&stream, -15, zlib.ZLIB_VERSION, @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return error.InvalidDeflateStream;
    }
    defer _ = zlib.inflateEnd(&stream);

    const initial_capacity: usize = if (expected_size > 0) @intCast(expected_size) else @max(bytes.len * 3 + 4096, 4096);
    try output.resize(allocator, initial_capacity);

    while (true) {
        const total_out: usize = @intCast(stream.total_out);
        if (total_out == output.items.len) {
            try output.resize(allocator, output.items.len * 2);
        }
        stream.next_out = output.items.ptr + total_out;
        stream.avail_out = @intCast(output.items.len - total_out);

        const status = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        switch (status) {
            zlib.Z_STREAM_END => {
                try output.resize(allocator, @intCast(stream.total_out));
                return output.toOwnedSlice(allocator);
            },
            zlib.Z_OK => continue,
            else => return error.InvalidDeflateStream,
        }
    }
}

fn parseLegacyJsonMovie(allocator: std.mem.Allocator, bytes: []const u8) ParseError!model.MovieSpec {
    var root = std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{}) catch return error.InvalidJson;
    const root_object = jsonObject(&root) orelse return error.InvalidJson;

    var version: []const u8 = "";
    if (root_object.getPtr("ver")) |value| {
        version = jsonString(value) orelse "";
    }

    var params = MovieParams{ .seen = true };
    if (root_object.getPtr("movie")) |movie_value| {
        if (jsonObject(movie_value)) |movie_object| {
            if (movie_object.getPtr("viewBox")) |view_box_value| {
                if (jsonObject(view_box_value)) |view_box| {
                    if (view_box.getPtr("width")) |value| params.view_box_width = jsonFloat(value) orelse params.view_box_width;
                    if (view_box.getPtr("height")) |value| params.view_box_height = jsonFloat(value) orelse params.view_box_height;
                }
            }
            if (movie_object.getPtr("fps")) |value| params.fps = jsonInt(value) orelse params.fps;
            if (movie_object.getPtr("frames")) |value| params.frames = jsonInt(value) orelse params.frames;
        }
    }

    var assets: std.ArrayList(model.AssetSpec) = .empty;
    if (root_object.getPtr("images")) |images_value| {
        if (jsonObject(images_value)) |images| {
            var it = images.iterator();
            while (it.next()) |entry| {
                if (jsonString(entry.value_ptr)) |filename| {
                    try assets.append(allocator, .{
                        .key = entry.key_ptr.*,
                        .kind = .filename,
                        .filename = filename,
                    });
                }
            }
        }
    }

    var sprites: std.ArrayList(model.SpriteSpec) = .empty;
    if (root_object.getPtr("sprites")) |sprites_value| {
        if (jsonArray(sprites_value)) |json_sprites| {
            for (json_sprites) |*sprite_value| {
                if (jsonObject(sprite_value)) |sprite_object| {
                    if (sprite_object.getPtr("imageKey")) |image_key_value| {
                        const frames_value = sprite_object.getPtr("frames") orelse continue;
                        const image_key = jsonString(image_key_value) orelse continue;
                        try sprites.append(allocator, try parseJsonSprite(allocator, image_key, sprite_object, frames_value));
                    }
                }
            }
        }
    }

    return .{
        .version = version,
        .view_box_width = params.view_box_width,
        .view_box_height = params.view_box_height,
        .fps = params.fps,
        .frames = params.frames,
        .image_count = @intCast(assets.items.len),
        .sprite_count = @intCast(sprites.items.len),
        .audio_count = 0,
        .assets = try assets.toOwnedSlice(allocator),
        .sprites = try sprites.toOwnedSlice(allocator),
    };
}

fn parseJsonSprite(
    allocator: std.mem.Allocator,
    image_key: []const u8,
    sprite_object: *const std.json.ObjectMap,
    frames_value: *const std.json.Value,
) ParseError!model.SpriteSpec {
    var frames: std.ArrayList(model.FrameSpec) = .empty;

    if (jsonArray(frames_value)) |json_frames| {
        for (json_frames) |*frame_value| {
            if (jsonObject(frame_value)) |frame_object| {
                try frames.append(allocator, try parseJsonFrame(allocator, frame_object));
            }
        }
    }

    var matte_key: []const u8 = "";
    if (sprite_object.getPtr("matteKey")) |matte_key_value| {
        matte_key = jsonString(matte_key_value) orelse "";
    }

    return .{
        .image_key = image_key,
        .matte_key = matte_key,
        .frames = try frames.toOwnedSlice(allocator),
    };
}

fn parseJsonFrame(allocator: std.mem.Allocator, frame_object: *const std.json.ObjectMap) ParseError!model.FrameSpec {
    var frame = model.Frame{};
    var clip_path: []const u8 = "";
    var shapes: std.ArrayList(model.ShapeSpec) = .empty;

    if (frame_object.getPtr("alpha")) |value| frame.alpha = jsonFloat(value) orelse frame.alpha;
    if (frame_object.getPtr("layout")) |value| frame.layout = parseJsonLayout(value) orelse frame.layout;
    if (frame_object.getPtr("transform")) |value| frame.transform = parseJsonTransform(value) orelse frame.transform;
    if (frame_object.getPtr("clipPath")) |value| clip_path = jsonString(value) orelse clip_path;

    if (frame_object.getPtr("shapes")) |shapes_value| {
        if (jsonArray(shapes_value)) |json_shapes| {
            for (json_shapes) |*shape_value| {
                if (jsonObject(shape_value)) |shape_object| {
                    const shape = parseJsonShape(shape_object);
                    if (frame.shape_count == 0) frame.first_shape_type = @intFromEnum(shape.shape_type);
                    frame.shape_count += 1;
                    try shapes.append(allocator, shape);
                }
            }
        }
    }

    frame = model.computeFrame(frame);
    return .{
        .frame = frame,
        .clip_path = clip_path,
        .shapes = try shapes.toOwnedSlice(allocator),
    };
}

fn parseJsonShape(shape_object: *const std.json.ObjectMap) model.ShapeSpec {
    var shape = model.ShapeSpec{};

    if (shape_object.getPtr("type")) |value| {
        if (jsonString(value)) |shape_type| {
            if (std.mem.eql(u8, shape_type, "shape")) {
                shape.shape_type = .shape;
            } else if (std.mem.eql(u8, shape_type, "rect")) {
                shape.shape_type = .rect;
            } else if (std.mem.eql(u8, shape_type, "ellipse")) {
                shape.shape_type = .ellipse;
            } else if (std.mem.eql(u8, shape_type, "keep")) {
                shape.shape_type = .keep;
            }
        }
    }

    if (shape_object.getPtr("args")) |args_value| {
        if (jsonObject(args_value)) |args| {
            switch (shape.shape_type) {
                .shape => {
                    if (args.getPtr("d")) |value| shape.path_data = jsonString(value) orelse "";
                },
                .rect => shape.rect = parseJsonRectArgs(args),
                .ellipse => shape.ellipse = parseJsonEllipseArgs(args),
                .unknown, .keep => {},
            }
        }
    }

    if (shape_object.getPtr("styles")) |styles_value| {
        if (jsonObject(styles_value)) |styles| {
            shape.styles = parseJsonShapeStyle(styles);
            shape.has_styles = true;
        }
    }
    if (shape_object.getPtr("transform")) |transform_value| {
        if (parseJsonTransform(transform_value)) |transform| {
            shape.transform = transform;
            shape.has_transform = true;
        }
    }

    return shape;
}

fn parseJsonLayout(value: *const std.json.Value) ?model.Layout {
    const object = jsonObject(value) orelse return null;
    return .{
        .x = jsonFloat(object.getPtr("x") orelse return null) orelse return null,
        .y = jsonFloat(object.getPtr("y") orelse return null) orelse return null,
        .width = jsonFloat(object.getPtr("width") orelse return null) orelse return null,
        .height = jsonFloat(object.getPtr("height") orelse return null) orelse return null,
    };
}

fn parseJsonTransform(value: *const std.json.Value) ?model.Transform {
    const object = jsonObject(value) orelse return null;
    return .{
        .a = jsonFloat(object.getPtr("a") orelse return null) orelse return null,
        .b = jsonFloat(object.getPtr("b") orelse return null) orelse return null,
        .c = jsonFloat(object.getPtr("c") orelse return null) orelse return null,
        .d = jsonFloat(object.getPtr("d") orelse return null) orelse return null,
        .tx = jsonFloat(object.getPtr("tx") orelse return null) orelse return null,
        .ty = jsonFloat(object.getPtr("ty") orelse return null) orelse return null,
    };
}

fn parseJsonRectArgs(object: *const std.json.ObjectMap) model.RectArgs {
    return .{
        .x = jsonFloat(object.getPtr("x") orelse return .{}) orelse 0,
        .y = jsonFloat(object.getPtr("y") orelse return .{}) orelse 0,
        .width = jsonFloat(object.getPtr("width") orelse return .{}) orelse 0,
        .height = jsonFloat(object.getPtr("height") orelse return .{}) orelse 0,
        .corner_radius = jsonFloat(object.getPtr("cornerRadius") orelse return .{}) orelse 0,
    };
}

fn parseJsonEllipseArgs(object: *const std.json.ObjectMap) model.EllipseArgs {
    return .{
        .x = jsonFloat(object.getPtr("x") orelse return .{}) orelse 0,
        .y = jsonFloat(object.getPtr("y") orelse return .{}) orelse 0,
        .radius_x = jsonFloat(object.getPtr("radiusX") orelse return .{}) orelse 0,
        .radius_y = jsonFloat(object.getPtr("radiusY") orelse return .{}) orelse 0,
    };
}

fn parseJsonShapeStyle(object: *const std.json.ObjectMap) model.ShapeStyle {
    var style = model.ShapeStyle{};

    if (object.getPtr("fill")) |value| {
        if (parseJsonColorArray(value)) |color| {
            style.fill = color;
            style.has_fill = 1;
        }
    }
    if (object.getPtr("stroke")) |value| {
        if (parseJsonColorArray(value)) |color| {
            style.stroke = color;
            style.has_stroke = 1;
        }
    }
    if (object.getPtr("strokeWidth")) |value| style.stroke_width = jsonFloat(value) orelse style.stroke_width;
    if (object.getPtr("lineCap")) |value| {
        if (jsonString(value)) |line_cap| style.line_cap = lineCapFromString(line_cap);
    }
    if (object.getPtr("lineJoin")) |value| {
        if (jsonString(value)) |line_join| style.line_join = lineJoinFromString(line_join);
    }
    if (object.getPtr("miterLimit")) |value| style.miter_limit = jsonFloat(value) orelse style.miter_limit;
    if (object.getPtr("lineDash")) |value| {
        if (jsonArray(value)) |line_dash| {
            if (line_dash.len == 3) {
                style.line_dash_i = jsonFloat(&line_dash[0]) orelse style.line_dash_i;
                style.line_dash_ii = jsonFloat(&line_dash[1]) orelse style.line_dash_ii;
                style.line_dash_iii = jsonFloat(&line_dash[2]) orelse style.line_dash_iii;
            }
        }
    }

    return style;
}

fn parseJsonColorArray(value: *const std.json.Value) ?model.Color {
    const items = jsonArray(value) orelse return null;
    if (items.len != 4) return null;
    return .{
        .r = jsonFloat(&items[0]) orelse return null,
        .g = jsonFloat(&items[1]) orelse return null,
        .b = jsonFloat(&items[2]) orelse return null,
        .a = jsonFloat(&items[3]) orelse return null,
    };
}

fn jsonObject(value: *const std.json.Value) ?*const std.json.ObjectMap {
    return switch (value.*) {
        .object => |*object| object,
        else => null,
    };
}

fn jsonArray(value: *const std.json.Value) ?[]const std.json.Value {
    return switch (value.*) {
        .array => |array| array.items,
        else => null,
    };
}

fn jsonString(value: *const std.json.Value) ?[]const u8 {
    return switch (value.*) {
        .string => |string| string,
        else => null,
    };
}

fn jsonFloat(value: *const std.json.Value) ?f32 {
    return switch (value.*) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| @floatCast(float),
        .number_string => |string| std.fmt.parseFloat(f32, string) catch null,
        else => null,
    };
}

fn jsonInt(value: *const std.json.Value) ?i32 {
    return switch (value.*) {
        .integer => |integer| int64ToI32(integer),
        .float => |float| floatToI32(float),
        .number_string => |string| std.fmt.parseInt(i32, string, 10) catch null,
        else => null,
    };
}

fn int64ToI32(value: i64) ?i32 {
    if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intCast(value);
}

fn floatToI32(value: f64) ?i32 {
    if (!std.math.isFinite(value)) return null;
    if (value < @as(f64, @floatFromInt(std.math.minInt(i32)))) return null;
    if (value > @as(f64, @floatFromInt(std.math.maxInt(i32)))) return null;
    return @intFromFloat(value);
}

fn lineCapFromString(value: []const u8) i32 {
    if (std.mem.eql(u8, value, "round")) return 1;
    if (std.mem.eql(u8, value, "square")) return 2;
    return 0;
}

fn lineJoinFromString(value: []const u8) i32 {
    if (std.mem.eql(u8, value, "round")) return 1;
    if (std.mem.eql(u8, value, "bevel")) return 2;
    return 0;
}

fn isMp3Data(bytes: []const u8) bool {
    return std.mem.startsWith(u8, bytes, "ID3");
}

fn inflateZlib(allocator: std.mem.Allocator, bytes: []const u8) ParseError![]u8 {
    if (!comptime build_options.use_system_zlib) {
        return inflateWithStdFlate(
            allocator,
            bytes,
            .zlib,
            @max(bytes.len * 3 + 4096, 4096),
            error.InvalidZlibStream,
        );
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var stream: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
    stream.next_in = @constCast(bytes.ptr);
    stream.avail_in = @intCast(bytes.len);

    if (zlib.inflateInit_(&stream, zlib.ZLIB_VERSION, @sizeOf(zlib.z_stream)) != zlib.Z_OK) {
        return error.InvalidZlibStream;
    }
    defer _ = zlib.inflateEnd(&stream);

    const initial_capacity = @max(bytes.len * 3 + 4096, 4096);
    try output.resize(allocator, initial_capacity);

    while (true) {
        const total_out: usize = @intCast(stream.total_out);
        if (total_out == output.items.len) {
            try output.resize(allocator, output.items.len * 2);
        }
        stream.next_out = output.items.ptr + total_out;
        stream.avail_out = @intCast(output.items.len - total_out);

        const status = zlib.inflate(&stream, zlib.Z_NO_FLUSH);
        switch (status) {
            zlib.Z_STREAM_END => {
                try output.resize(allocator, @intCast(stream.total_out));
                return output.toOwnedSlice(allocator);
            },
            zlib.Z_OK => continue,
            else => return error.InvalidZlibStream,
        }
    }
}

fn inflateWithStdFlate(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    container: flate.Container,
    initial_capacity: usize,
    invalid_error: ParseError,
) ParseError![]u8 {
    var input: std.Io.Reader = .fixed(bytes);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, initial_capacity);

    var window: [flate.max_window_len]u8 = undefined;
    var decompress: flate.Decompress = .init(&input, container, &window);
    decompress.reader.appendRemainingUnlimited(allocator, &output) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => return invalid_error,
    };

    return output.toOwnedSlice(allocator);
}

const Tag = struct {
    field_number: u32,
    wire_type: WireType,
};

const ProtoReader = struct {
    bytes: []const u8,
    index: usize = 0,

    fn isDone(self: *const ProtoReader) bool {
        return self.index >= self.bytes.len;
    }

    fn readTag(self: *ProtoReader) ParseError!Tag {
        const raw = try self.readVarint();
        const wire_int = raw & 0x7;
        if (wire_int == 3 or wire_int == 4 or wire_int > 5) return error.InvalidWireType;
        const field_number = raw >> 3;
        if (field_number == 0 or field_number > std.math.maxInt(u32)) return error.InvalidData;
        return .{
            .field_number = @intCast(field_number),
            .wire_type = @enumFromInt(@as(u3, @intCast(wire_int))),
        };
    }

    fn readLengthDelimited(self: *ProtoReader, wire_type: WireType) ParseError![]const u8 {
        if (wire_type != .length_delimited) return error.InvalidWireType;
        const len: usize = @intCast(try self.readVarint());
        if (len > self.bytes.len - self.index) return error.TruncatedInput;
        const start = self.index;
        self.index += len;
        return self.bytes[start..self.index];
    }

    fn readFixed32Float(self: *ProtoReader, wire_type: WireType) ParseError!f32 {
        if (wire_type != .fixed32) return error.InvalidWireType;
        if (self.bytes.len - self.index < 4) return error.TruncatedInput;
        const raw = std.mem.readInt(u32, self.bytes[self.index..][0..4], .little);
        self.index += 4;
        return @bitCast(raw);
    }

    fn readVarintFor(self: *ProtoReader, wire_type: WireType) ParseError!u64 {
        if (wire_type != .varint) return error.InvalidWireType;
        return self.readVarint();
    }

    fn skip(self: *ProtoReader, wire_type: WireType) ParseError!void {
        switch (wire_type) {
            .varint => _ = try self.readVarint(),
            .fixed64 => {
                if (self.bytes.len - self.index < 8) return error.TruncatedInput;
                self.index += 8;
            },
            .length_delimited => _ = try self.readLengthDelimited(.length_delimited),
            .fixed32 => {
                if (self.bytes.len - self.index < 4) return error.TruncatedInput;
                self.index += 4;
            },
            .start_group, .end_group => return error.InvalidWireType,
        }
    }

    fn readVarint(self: *ProtoReader) ParseError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        while (shift < 64) : (shift += 7) {
            if (self.index >= self.bytes.len) return error.TruncatedInput;
            const byte = self.bytes[self.index];
            self.index += 1;
            result |= (@as(u64, byte & 0x7f) << shift);
            if ((byte & 0x80) == 0) return result;
        }
        return error.InvalidData;
    }
};

test "metadata parser rejects bytes that cannot be zip or zlib" {
    const bytes = [_]u8{ 0, 1, 2, 3 };
    try std.testing.expectError(error.InvalidData, parseMovieMetadata(std.testing.allocator, &bytes));
}

test "protobuf metadata parser reads movie params and counts repeated fields" {
    const proto = [_]u8{
        0x0a, 0x05, '2',  '.',  '0',  '.',  '0',
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c, 0x1a, 0x00, 0x1a, 0x00, 0x22,
        0x00, 0x2a, 0x00,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const spec = try parseMovieProto(arena.allocator(), &proto);
    try std.testing.expectEqualStrings("2.0.0", spec.version);
    try std.testing.expectEqual(@as(f32, 320), spec.view_box_width);
    try std.testing.expectEqual(@as(f32, 240), spec.view_box_height);
    try std.testing.expectEqual(@as(i32, 30), spec.fps);
    try std.testing.expectEqual(@as(i32, 60), spec.frames);
    try std.testing.expectEqual(@as(u32, 2), spec.image_count);
    try std.testing.expectEqual(@as(u32, 1), spec.sprite_count);
    try std.testing.expectEqual(@as(u32, 1), spec.audio_count);
}

test "protobuf parser reads sprite frame geometry and keep shape marker" {
    const proto = [_]u8{
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c, 0x22, 0x4a, 0x0a, 0x07, 'a',
        'v',  'a',  't',  'a',  'r',  's',  0x12,
        0x3f, 0x0d, 0x00, 0x00, 0x80, 0x3f, 0x12,
        0x14, 0x0d, 0x00, 0x00, 0x20, 0x41, 0x15,
        0x00, 0x00, 0xa0, 0x41, 0x1d, 0x00, 0x00,
        0xf0, 0x41, 0x25, 0x00, 0x00, 0x20, 0x42,
        0x1a, 0x1e, 0x0d, 0x00, 0x00, 0x80, 0x3f,
        0x15, 0x00, 0x00, 0x00, 0x00, 0x1d, 0x00,
        0x00, 0x00, 0x00, 0x25, 0x00, 0x00, 0x80,
        0x3f, 0x2d, 0x00, 0x00, 0xa0, 0x40, 0x35,
        0x00, 0x00, 0xe0, 0x40, 0x2a, 0x02, 0x08,
        0x03,
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const spec = try parseMovieProto(arena.allocator(), &proto);
    try std.testing.expectEqual(@as(u32, 1), spec.sprite_count);
    try std.testing.expectEqualStrings("avatars", spec.sprites[0].image_key);
    try std.testing.expectEqual(@as(usize, 1), spec.sprites[0].frames.len);

    const frame = spec.sprites[0].frames[0].frame;
    try std.testing.expectEqual(@as(f32, 1), frame.alpha);
    try std.testing.expectEqual(@as(f32, 15), frame.nx);
    try std.testing.expectEqual(@as(f32, 27), frame.ny);
    try std.testing.expectEqual(@as(u32, 1), frame.shape_count);
    try std.testing.expectEqual(@as(i32, @intFromEnum(model.ShapeType.keep)), frame.first_shape_type);
    try std.testing.expectEqual(@as(u8, 1), frame.is_keep_frame);
}
