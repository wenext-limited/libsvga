const std = @import("std");

pub const max_version_bytes = 255;

pub const MovieSpec = struct {
    version: []const u8 = "",
    view_box_width: f32,
    view_box_height: f32,
    fps: i32,
    frames: i32,
    image_count: u32 = 0,
    sprite_count: u32 = 0,
    audio_count: u32 = 0,
    assets: []const AssetSpec = &.{},
    sprites: []const SpriteSpec = &.{},
    audios: []const AudioSpec = &.{},
};

pub const MovieInfo = struct {
    version: [:0]const u8,
    view_box_width: f32,
    view_box_height: f32,
    fps: i32,
    frames: i32,
    image_count: u32,
    sprite_count: u32,
    audio_count: u32,
};

pub const Layout = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

pub const Transform = extern struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,
};

pub const ShapeType = enum(i32) {
    unknown = -1,
    shape = 0,
    rect = 1,
    ellipse = 2,
    keep = 3,
};

pub const AssetKind = enum(i32) {
    unknown = 0,
    image_bytes = 1,
    filename = 2,
    audio_bytes = 3,
};

pub const AssetSpec = struct {
    key: []const u8 = "",
    kind: AssetKind = .unknown,
    bytes: []const u8 = "",
    filename: []const u8 = "",
};

pub const AudioSpec = struct {
    audio_key: []const u8 = "",
    start_frame: i32 = 0,
    end_frame: i32 = 0,
    start_time_ms: i32 = 0,
    total_time_ms: i32 = 0,
};

pub const Color = extern struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub const ShapeStyle = extern struct {
    fill: Color = .{},
    stroke: Color = .{},
    stroke_width: f32 = 0,
    line_cap: i32 = 0,
    line_join: i32 = 0,
    miter_limit: f32 = 0,
    line_dash_i: f32 = 0,
    line_dash_ii: f32 = 0,
    line_dash_iii: f32 = 0,
    has_fill: u8 = 0,
    has_stroke: u8 = 0,
};

pub const RectArgs = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    corner_radius: f32 = 0,
};

pub const EllipseArgs = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    radius_x: f32 = 0,
    radius_y: f32 = 0,
};

pub const ShapeSpec = struct {
    shape_type: ShapeType = .unknown,
    path_data: []const u8 = "",
    rect: RectArgs = .{},
    ellipse: EllipseArgs = .{},
    styles: ShapeStyle = .{},
    transform: Transform = .{},
    has_styles: bool = false,
    has_transform: bool = false,
};

pub const Frame = extern struct {
    alpha: f32 = 0,
    layout: Layout = .{},
    transform: Transform = .{},
    nx: f32 = 0,
    ny: f32 = 0,
    shape_count: u32 = 0,
    first_shape_type: i32 = @intFromEnum(ShapeType.unknown),
    visible: u8 = 0,
    is_keep_frame: u8 = 0,
};

pub const FrameSpec = struct {
    frame: Frame = .{},
    clip_path: []const u8 = "",
    shapes: []const ShapeSpec = &.{},
};

pub const SpriteSpec = struct {
    image_key: []const u8 = "",
    matte_key: []const u8 = "",
    frames: []const FrameSpec = &.{},
};

pub const SpriteInfo = struct {
    image_key: [:0]const u8,
    matte_key: [:0]const u8,
    frame_count: u32,
    is_matte: bool,
    has_matte: bool,
};

pub const FrameInfo = struct {
    frame: Frame,
    clip_path: [:0]const u8,
};

pub const RenderCommand = extern struct {
    sprite_index: u32 = 0,
    opacity: f32 = 0,
    bounds: Layout = .{},
    transform: Transform = .{},
};

const RenderCommandRange = struct {
    start: usize = 0,
    count: usize = 0,
};

const RenderData = struct {
    commands: []RenderCommand,
    ranges: []RenderCommandRange,

    fn deinit(self: RenderData, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
        allocator.free(self.ranges);
    }
};

pub const ValidationError = error{
    InvalidVersion,
    InvalidDimensions,
    InvalidFps,
    InvalidFrames,
    InvalidMovieCounts,
    InvalidSpriteKey,
    InvalidFrameCount,
};

pub const Movie = struct {
    version: [:0]u8,
    view_box_width: f32,
    view_box_height: f32,
    fps: i32,
    frames: i32,
    image_count: u32,
    sprite_count: u32,
    audio_count: u32,
    assets: []Asset,
    sprites: []Sprite,
    audios: []Audio,
    render_commands: []RenderCommand,
    render_frame_ranges: []RenderCommandRange,

    pub fn init(allocator: std.mem.Allocator, spec: MovieSpec) !Movie {
        try validateSpec(spec);

        var assets = try allocator.alloc(Asset, spec.assets.len);
        errdefer allocator.free(assets);
        var initialized_assets: usize = 0;
        errdefer {
            for (assets[0..initialized_assets]) |*asset| {
                asset.deinit(allocator);
            }
        }
        for (spec.assets, 0..) |asset_spec, index| {
            assets[index] = try Asset.init(allocator, asset_spec);
            initialized_assets += 1;
        }

        var sprites = try allocator.alloc(Sprite, spec.sprites.len);
        errdefer allocator.free(sprites);
        var initialized_sprites: usize = 0;
        errdefer {
            for (sprites[0..initialized_sprites]) |*sprite| {
                sprite.deinit(allocator);
            }
        }
        for (spec.sprites, 0..) |sprite_spec, index| {
            sprites[index] = try Sprite.init(allocator, sprite_spec);
            initialized_sprites += 1;
        }

        var audios = try allocator.alloc(Audio, spec.audios.len);
        errdefer allocator.free(audios);
        var initialized_audios: usize = 0;
        errdefer {
            for (audios[0..initialized_audios]) |*audio| {
                audio.deinit(allocator);
            }
        }
        for (spec.audios, 0..) |audio_spec, index| {
            audios[index] = try Audio.init(allocator, audio_spec);
            initialized_audios += 1;
        }

        const render_data = try buildRenderData(allocator, sprites, spec.frames);
        errdefer render_data.deinit(allocator);

        return .{
            .version = try allocator.dupeZ(u8, spec.version),
            .view_box_width = spec.view_box_width,
            .view_box_height = spec.view_box_height,
            .fps = spec.fps,
            .frames = spec.frames,
            .image_count = spec.image_count,
            .sprite_count = spec.sprite_count,
            .audio_count = spec.audio_count,
            .assets = assets,
            .sprites = sprites,
            .audios = audios,
            .render_commands = render_data.commands,
            .render_frame_ranges = render_data.ranges,
        };
    }

    pub fn deinit(self: *Movie, allocator: std.mem.Allocator) void {
        allocator.free(self.render_commands);
        allocator.free(self.render_frame_ranges);
        for (self.assets) |*asset| {
            asset.deinit(allocator);
        }
        allocator.free(self.assets);
        for (self.sprites) |*sprite| {
            sprite.deinit(allocator);
        }
        allocator.free(self.sprites);
        for (self.audios) |*audio| {
            audio.deinit(allocator);
        }
        allocator.free(self.audios);
        allocator.free(self.version);
        self.* = undefined;
    }

    pub fn info(self: *const Movie) MovieInfo {
        return .{
            .version = self.version,
            .view_box_width = self.view_box_width,
            .view_box_height = self.view_box_height,
            .fps = self.fps,
            .frames = self.frames,
            .image_count = self.image_count,
            .sprite_count = self.sprite_count,
            .audio_count = self.audio_count,
        };
    }

    pub fn spriteInfo(self: *const Movie, index: usize) ?SpriteInfo {
        if (index >= self.sprites.len) return null;
        const sprite = &self.sprites[index];
        return .{
            .image_key = sprite.image_key,
            .matte_key = sprite.matte_key,
            .frame_count = @intCast(sprite.frames.len),
            .is_matte = sprite.isMatte(),
            .has_matte = sprite.matte_key.len > 0,
        };
    }

    pub fn frameInfo(self: *const Movie, sprite_index: usize, frame_index: usize) ?FrameInfo {
        if (sprite_index >= self.sprites.len) return null;
        const sprite = &self.sprites[sprite_index];
        if (frame_index >= sprite.frames.len) return null;
        const frame = &sprite.frames[frame_index];
        return .{
            .frame = frame.frame,
            .clip_path = frame.clip_path,
        };
    }

    pub fn renderCommands(self: *const Movie, frame_index: usize) ?[]const RenderCommand {
        if (frame_index >= self.render_frame_ranges.len) return null;
        const range = self.render_frame_ranges[frame_index];
        return self.render_commands[range.start .. range.start + range.count];
    }
};

pub const Asset = struct {
    key: [:0]u8,
    kind: AssetKind,
    bytes: []u8,
    filename: [:0]u8,

    pub fn init(allocator: std.mem.Allocator, spec: AssetSpec) !Asset {
        return .{
            .key = try allocator.dupeZ(u8, spec.key),
            .kind = spec.kind,
            .bytes = try allocator.dupe(u8, spec.bytes),
            .filename = try allocator.dupeZ(u8, spec.filename),
        };
    }

    pub fn deinit(self: *Asset, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.bytes);
        allocator.free(self.filename);
        self.* = undefined;
    }
};

pub const Audio = struct {
    audio_key: [:0]u8,
    start_frame: i32,
    end_frame: i32,
    start_time_ms: i32,
    total_time_ms: i32,

    pub fn init(allocator: std.mem.Allocator, spec: AudioSpec) !Audio {
        return .{
            .audio_key = try allocator.dupeZ(u8, spec.audio_key),
            .start_frame = spec.start_frame,
            .end_frame = spec.end_frame,
            .start_time_ms = spec.start_time_ms,
            .total_time_ms = spec.total_time_ms,
        };
    }

    pub fn deinit(self: *Audio, allocator: std.mem.Allocator) void {
        allocator.free(self.audio_key);
        self.* = undefined;
    }
};

pub const Sprite = struct {
    image_key: [:0]u8,
    matte_key: [:0]u8,
    frames: []OwnedFrame,

    pub fn init(allocator: std.mem.Allocator, spec: SpriteSpec) !Sprite {
        if (std.mem.indexOfScalar(u8, spec.image_key, 0) != null) return error.InvalidSpriteKey;
        if (std.mem.indexOfScalar(u8, spec.matte_key, 0) != null) return error.InvalidSpriteKey;

        var frames = try allocator.alloc(OwnedFrame, spec.frames.len);
        errdefer allocator.free(frames);
        var initialized_frames: usize = 0;
        errdefer {
            for (frames[0..initialized_frames]) |*frame| {
                frame.deinit(allocator);
            }
        }
        for (spec.frames, 0..) |frame_spec, index| {
            frames[index] = try OwnedFrame.init(allocator, frame_spec);
            initialized_frames += 1;
        }

        return .{
            .image_key = try allocator.dupeZ(u8, spec.image_key),
            .matte_key = try allocator.dupeZ(u8, spec.matte_key),
            .frames = frames,
        };
    }

    pub fn deinit(self: *Sprite, allocator: std.mem.Allocator) void {
        for (self.frames) |*frame| {
            frame.deinit(allocator);
        }
        allocator.free(self.frames);
        allocator.free(self.image_key);
        allocator.free(self.matte_key);
        self.* = undefined;
    }

    pub fn isMatte(self: *const Sprite) bool {
        return std.mem.endsWith(u8, self.image_key, ".matte");
    }
};

pub const OwnedFrame = struct {
    frame: Frame,
    clip_path: [:0]u8,
    shapes: []Shape,

    pub fn init(allocator: std.mem.Allocator, spec: FrameSpec) !OwnedFrame {
        var shapes = try allocator.alloc(Shape, spec.shapes.len);
        errdefer allocator.free(shapes);
        var initialized_shapes: usize = 0;
        errdefer {
            for (shapes[0..initialized_shapes]) |*shape| {
                shape.deinit(allocator);
            }
        }
        for (spec.shapes, 0..) |shape_spec, index| {
            shapes[index] = try Shape.init(allocator, shape_spec);
            initialized_shapes += 1;
        }

        return .{
            .frame = spec.frame,
            .clip_path = try allocator.dupeZ(u8, spec.clip_path),
            .shapes = shapes,
        };
    }

    pub fn deinit(self: *OwnedFrame, allocator: std.mem.Allocator) void {
        for (self.shapes) |*shape| {
            shape.deinit(allocator);
        }
        allocator.free(self.shapes);
        allocator.free(self.clip_path);
        self.* = undefined;
    }
};

pub const Shape = struct {
    shape_type: ShapeType,
    path_data: [:0]u8,
    rect: RectArgs,
    ellipse: EllipseArgs,
    styles: ShapeStyle,
    transform: Transform,
    has_styles: bool,
    has_transform: bool,

    pub fn init(allocator: std.mem.Allocator, spec: ShapeSpec) !Shape {
        return .{
            .shape_type = spec.shape_type,
            .path_data = try allocator.dupeZ(u8, spec.path_data),
            .rect = spec.rect,
            .ellipse = spec.ellipse,
            .styles = spec.styles,
            .transform = spec.transform,
            .has_styles = spec.has_styles,
            .has_transform = spec.has_transform,
        };
    }

    pub fn deinit(self: *Shape, allocator: std.mem.Allocator) void {
        allocator.free(self.path_data);
        self.* = undefined;
    }
};

fn buildRenderData(allocator: std.mem.Allocator, sprites: []const Sprite, frame_count_value: i32) !RenderData {
    const frame_count: usize = @intCast(frame_count_value);
    var command_counts = try allocator.alloc(usize, frame_count);
    defer allocator.free(command_counts);
    @memset(command_counts, 0);

    for (sprites, 0..) |sprite, sprite_index| {
        for (sprite.frames[0..@min(frame_count, sprite.frames.len)], 0..) |owned_frame, frame_index| {
            if (renderCommandForFrame(sprite_index, owned_frame.frame) != null) {
                command_counts[frame_index] += 1;
            }
        }
    }

    var ranges = try allocator.alloc(RenderCommandRange, frame_count);
    errdefer allocator.free(ranges);

    var command_total: usize = 0;
    for (command_counts, 0..) |count, frame_index| {
        ranges[frame_index] = .{
            .start = command_total,
            .count = count,
        };
        command_total += count;
    }

    var commands = try allocator.alloc(RenderCommand, command_total);
    errdefer allocator.free(commands);

    for (ranges, 0..) |range, frame_index| {
        command_counts[frame_index] = range.start;
    }

    for (sprites, 0..) |sprite, sprite_index| {
        for (sprite.frames[0..@min(frame_count, sprite.frames.len)], 0..) |owned_frame, frame_index| {
            const command = renderCommandForFrame(sprite_index, owned_frame.frame) orelse continue;
            const command_index = command_counts[frame_index];
            commands[command_index] = command;
            command_counts[frame_index] += 1;
        }
    }

    return .{
        .commands = commands,
        .ranges = ranges,
    };
}

fn renderCommandForFrame(sprite_index: usize, frame: Frame) ?RenderCommand {
    if (frame.visible == 0 or frame.alpha <= 0) return null;
    if (frame.layout.width <= 0 or frame.layout.height <= 0) return null;

    return .{
        .sprite_index = @intCast(sprite_index),
        .opacity = frame.alpha,
        .bounds = frame.layout,
        .transform = frame.transform,
    };
}

pub fn validateSpec(spec: MovieSpec) ValidationError!void {
    if (spec.version.len > max_version_bytes) return error.InvalidVersion;
    if (std.mem.indexOfScalar(u8, spec.version, 0) != null) return error.InvalidVersion;

    if (!std.math.isFinite(spec.view_box_width) or spec.view_box_width <= 0) {
        return error.InvalidDimensions;
    }
    if (!std.math.isFinite(spec.view_box_height) or spec.view_box_height <= 0) {
        return error.InvalidDimensions;
    }

    if (spec.fps <= 0) return error.InvalidFps;
    if (spec.frames <= 0) return error.InvalidFrames;
    if (spec.sprites.len != 0 and spec.sprite_count != spec.sprites.len) return error.InvalidMovieCounts;
    if (spec.sprites.len > std.math.maxInt(u32)) return error.InvalidMovieCounts;
    if (spec.assets.len > std.math.maxInt(u32)) return error.InvalidMovieCounts;
    if (spec.audios.len > std.math.maxInt(u32)) return error.InvalidMovieCounts;
    for (spec.sprites) |sprite| {
        if (sprite.frames.len > std.math.maxInt(u32)) return error.InvalidFrameCount;
    }
}

pub fn isDocumentedFps(fps: i32) bool {
    return switch (fps) {
        1, 2, 3, 5, 6, 10, 12, 15, 20, 30, 60 => true,
        else => false,
    };
}

test "movie metadata can be validated and owned" {
    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 90,
        .image_count = 2,
        .sprite_count = 1,
        .audio_count = 0,
        .sprites = &.{
            .{
                .image_key = "image_0",
                .matte_key = "",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 10, .y = 20, .width = 30, .height = 40 },
                            .transform = .{},
                        }),
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    const movie_info = movie.info();
    try std.testing.expectEqualStrings("2.0.0", movie_info.version);
    try std.testing.expectEqual(@as(f32, 320), movie_info.view_box_width);
    try std.testing.expectEqual(@as(f32, 240), movie_info.view_box_height);
    try std.testing.expectEqual(@as(i32, 30), movie_info.fps);
    try std.testing.expectEqual(@as(i32, 90), movie_info.frames);
    try std.testing.expectEqual(@as(u32, 2), movie_info.image_count);
    try std.testing.expectEqual(@as(u32, 1), movie_info.sprite_count);
    try std.testing.expectEqual(@as(u32, 0), movie_info.audio_count);

    const sprite_info = movie.spriteInfo(0).?;
    try std.testing.expectEqualStrings("image_0", sprite_info.image_key);
    try std.testing.expectEqual(@as(u32, 1), sprite_info.frame_count);

    const frame_info = movie.frameInfo(0, 0).?;
    try std.testing.expectEqual(@as(f32, 1), frame_info.frame.alpha);
    try std.testing.expectEqual(@as(f32, 10), frame_info.frame.nx);
    try std.testing.expectEqual(@as(f32, 20), frame_info.frame.ny);

    const commands = movie.renderCommands(0).?;
    try std.testing.expectEqual(@as(usize, 1), commands.len);
    try std.testing.expectEqual(@as(u32, 0), commands[0].sprite_index);
    try std.testing.expectEqual(@as(f32, 1), commands[0].opacity);
    try std.testing.expectEqual(@as(f32, 10), commands[0].bounds.x);
    try std.testing.expectEqual(@as(f32, 30), commands[0].bounds.width);
}

test "movie metadata accepts positive fps outside documented player values" {
    try validateSpec(.{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 7,
        .frames = 90,
    });
}

test "movie metadata rejects zero fps" {
    try std.testing.expectError(error.InvalidFps, validateSpec(.{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 0,
        .frames = 90,
    }));
}

pub fn computeFrame(input: Frame) Frame {
    var frame = input;
    const layout = frame.layout;
    const transform = frame.transform;

    const llx = transform.a * layout.x + transform.c * layout.y + transform.tx;
    const lrx = transform.a * (layout.x + layout.width) + transform.c * layout.y + transform.tx;
    const lbx = transform.a * layout.x + transform.c * (layout.y + layout.height) + transform.tx;
    const rbx = transform.a * (layout.x + layout.width) + transform.c * (layout.y + layout.height) + transform.tx;

    const lly = transform.b * layout.x + transform.d * layout.y + transform.ty;
    const lry = transform.b * (layout.x + layout.width) + transform.d * layout.y + transform.ty;
    const lby = transform.b * layout.x + transform.d * (layout.y + layout.height) + transform.ty;
    const rby = transform.b * (layout.x + layout.width) + transform.d * (layout.y + layout.height) + transform.ty;

    frame.nx = @min(@min(lbx, rbx), @min(llx, lrx));
    frame.ny = @min(@min(lby, rby), @min(lly, lry));
    frame.visible = if (frame.alpha > 0) 1 else 0;
    frame.is_keep_frame = if (frame.first_shape_type == @intFromEnum(ShapeType.keep)) 1 else 0;
    return frame;
}

test "frame geometry precomputes transformed minima and visibility" {
    const frame = computeFrame(.{
        .alpha = 0.5,
        .layout = .{ .x = 10, .y = 20, .width = 30, .height = 40 },
        .transform = .{ .a = 1, .b = 0, .c = 0, .d = 1, .tx = 5, .ty = 7 },
    });

    try std.testing.expectEqual(@as(f32, 15), frame.nx);
    try std.testing.expectEqual(@as(f32, 27), frame.ny);
    try std.testing.expectEqual(@as(u8, 1), frame.visible);
}
