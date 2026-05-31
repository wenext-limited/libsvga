const std = @import("std");
const builtin = @import("builtin");
const svg_path = @import("svg_path.zig");

pub const max_version_bytes = 255;
pub const max_asset_count = 4096;
pub const max_sprite_count = 4096;
pub const max_audio_count = 4096;
pub const max_movie_frame_count = 10_000;
pub const max_total_sprite_frames = 100_000;
pub const max_total_shapes = 100_000;
pub const max_total_path_commands = 1_000_000;

/// Borrowed movie description produced by the parser before ownership is moved
/// into Movie. Slices in this struct are valid as long as the parser arena lives.
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

/// Stable high-level metadata exposed by both Zig and C APIs.
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

pub const PathCommand = svg_path.Command;
pub const PathCommandType = svg_path.CommandType;

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

pub const SpriteRecord = extern struct {
    image_key_utf8: ?[*:0]const u8 = null,
    matte_key_utf8: ?[*:0]const u8 = null,
    frame_count: u32 = 0,
    is_matte: u8 = 0,
    has_matte: u8 = 0,
};

pub const FrameInfo = struct {
    frame: Frame,
    clip_path: [:0]const u8,
};

pub const FrameRecord = extern struct {
    alpha: f32 = 0,
    layout: Layout = .{},
    transform: Transform = .{},
    nx: f32 = 0,
    ny: f32 = 0,
    shape_count: u32 = 0,
    first_shape_type: i32 = @intFromEnum(ShapeType.unknown),
    visible: u8 = 0,
    is_keep_frame: u8 = 0,
    clip_path_utf8: ?[*:0]const u8 = null,
};

pub const RenderCommand = extern struct {
    sprite_index: u32 = 0,
    opacity: f32 = 0,
    bounds: Layout = .{},
    transform: Transform = .{},
};

pub const RenderItem = extern struct {
    sprite_index: u32 = 0,
    frame_index: u32 = 0,
    shape_frame_index: u32 = 0,
    opacity: f32 = 0,
    bounds: Layout = .{},
    transform: Transform = .{},
    is_matte: u8 = 0,
    has_matte: u8 = 0,
    has_clip_path: u8 = 0,
    has_shapes: u8 = 0,
};

pub const RenderRange = extern struct {
    start: usize = 0,
    count: usize = 0,
};

pub const RenderFeature = enum(u32) {
    bitmap_quads = 1 << 0,
    clip_paths = 1 << 1,
    mattes = 1 << 2,
    vector_shapes = 1 << 3,
};

pub const RenderCapabilities = extern struct {
    abi_version: u32 = 0,
    required_features: u32 = 0,
    bitmap_command_count: u32 = 0,
    direct_bitmap_compatible: u8 = 0,
};

pub const ShapeRecord = extern struct {
    shape_type: i32 = @intFromEnum(ShapeType.unknown),
    path_data_utf8: ?[*:0]const u8 = null,
    rect: RectArgs = .{},
    ellipse: EllipseArgs = .{},
    styles: ShapeStyle = .{},
    transform: Transform = .{},
    has_styles: u8 = 0,
    has_transform: u8 = 0,
};

pub const MetadataTables = struct {
    // Flat tables keep the C ABI cheap: wrappers can pass borrowed pointers to
    // renderers without allocating per sprite or per frame.
    sprite_records: []SpriteRecord,
    frame_records: []FrameRecord,
    sprite_frame_ranges: []RenderRange,
    shape_records: []ShapeRecord,
    frame_shape_ranges: []RenderRange,
    clip_path_commands: []PathCommand,
    frame_clip_path_command_ranges: []RenderRange,
    shape_path_commands: []PathCommand,
    shape_path_command_ranges: []RenderRange,

    fn deinit(self: MetadataTables, allocator: std.mem.Allocator) void {
        allocator.free(self.sprite_records);
        allocator.free(self.frame_records);
        allocator.free(self.sprite_frame_ranges);
        allocator.free(self.shape_records);
        allocator.free(self.frame_shape_ranges);
        allocator.free(self.clip_path_commands);
        allocator.free(self.frame_clip_path_command_ranges);
        allocator.free(self.shape_path_commands);
        allocator.free(self.shape_path_command_ranges);
    }
};

const RenderData = struct {
    commands: []RenderCommand,
    command_ranges: []RenderRange,
    items: []RenderItem,
    item_ranges: []RenderRange,

    fn deinit(self: RenderData, allocator: std.mem.Allocator) void {
        allocator.free(self.commands);
        allocator.free(self.command_ranges);
        allocator.free(self.items);
        allocator.free(self.item_ranges);
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
    InvalidShapeCount,
    InvalidPathCommandCount,
};

pub const Movie = struct {
    /// Owned, NUL-terminated version string for direct C ABI borrowing.
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
    metadata: MetadataTables,
    render_commands: []RenderCommand,
    render_frame_ranges: []RenderRange,
    render_items: []RenderItem,
    render_item_frame_ranges: []RenderRange,
    visual_frame_indices: []u32,

    /// Validate and copy a parser MovieSpec into an owned immutable Movie.
    ///
    /// The parser uses arenas for speed; Movie.init performs the ownership
    /// boundary, building stable NUL-terminated strings and flattened render
    /// tables for C/Swift/Android/Web callers.
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

        const metadata = try buildMetadataTables(allocator, sprites);
        errdefer metadata.deinit(allocator);

        const render_data = try buildRenderData(allocator, sprites, spec.frames);
        errdefer render_data.deinit(allocator);
        const visual_frame_indices = try buildVisualFrameIndices(
            allocator,
            render_data.items,
            render_data.item_ranges,
        );
        errdefer allocator.free(visual_frame_indices);

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
            .metadata = metadata,
            .render_commands = render_data.commands,
            .render_frame_ranges = render_data.command_ranges,
            .render_items = render_data.items,
            .render_item_frame_ranges = render_data.item_ranges,
            .visual_frame_indices = visual_frame_indices,
        };
    }

    /// Release all owned tables, strings, assets, sprites, and audio metadata.
    pub fn deinit(self: *Movie, allocator: std.mem.Allocator) void {
        self.metadata.deinit(allocator);
        allocator.free(self.render_commands);
        allocator.free(self.render_frame_ranges);
        allocator.free(self.render_items);
        allocator.free(self.render_item_frame_ranges);
        allocator.free(self.visual_frame_indices);
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

    /// Return the compact metadata view used by the public API.
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

    /// Return sprite metadata for an index, or null when out of range.
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

    /// Return frame metadata for a sprite/frame pair, or null when out of range.
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

    /// Return bitmap render commands for one timeline frame.
    pub fn renderCommands(self: *const Movie, frame_index: usize) ?[]const RenderCommand {
        if (frame_index >= self.render_frame_ranges.len) return null;
        const range = self.render_frame_ranges[frame_index];
        return self.render_commands[range.start .. range.start + range.count];
    }

    /// Return rich render items for one timeline frame.
    pub fn renderItems(self: *const Movie, frame_index: usize) ?[]const RenderItem {
        if (frame_index >= self.render_item_frame_ranges.len) return null;
        const range = self.render_item_frame_ranges[frame_index];
        return self.render_items[range.start .. range.start + range.count];
    }

    /// Map a timeline frame to the latest frame that has visual content.
    pub fn visualFrameIndex(self: *const Movie, frame_index: usize) ?u32 {
        if (frame_index >= self.visual_frame_indices.len) return null;
        return self.visual_frame_indices[frame_index];
    }

    /// Find an asset by exact key.
    pub fn assetByKey(self: *const Movie, key: []const u8) ?*const Asset {
        for (self.assets) |*asset| {
            if (std.mem.eql(u8, asset.key, key)) return asset;
        }
        return null;
    }

    /// Resolve a sprite image key to actual image bytes when the SVGA package
    /// stores filename indirections instead of direct bytes.
    pub fn resolveImageAsset(self: *const Movie, image_key: []const u8) ?*const Asset {
        const asset = self.assetByKey(image_key) orelse return null;
        return self.resolveFilenameAsset(asset) orelse asset;
    }

    /// Resolve an audio key, following filename indirections when present.
    pub fn resolveAudioAsset(self: *const Movie, audio_key: []const u8) ?*const Asset {
        const asset = self.assetByKey(audio_key) orelse return null;
        if (asset.kind != .filename) return asset;
        return self.resolveFilenameAsset(asset) orelse asset;
    }

    fn resolveFilenameAsset(self: *const Movie, asset: *const Asset) ?*const Asset {
        if (asset.kind != .filename or asset.filename.len == 0) return null;
        if (std.mem.endsWith(u8, asset.filename, ".png")) {
            return self.assetByKeyWithBytes(asset.filename);
        }

        return self.assetByKeyWithAppendedPng(asset.filename) orelse
            self.assetByKeyWithBytes(asset.filename);
    }

    fn assetByKeyWithBytes(self: *const Movie, key: []const u8) ?*const Asset {
        const asset = self.assetByKey(key) orelse return null;
        return if (asset.bytes.len > 0) asset else null;
    }

    fn assetByKeyWithAppendedPng(self: *const Movie, key_prefix: []const u8) ?*const Asset {
        if (key_prefix.len > std.math.maxInt(usize) - 4) return null;
        for (self.assets) |*asset| {
            if (asset.key.len != key_prefix.len + 4) continue;
            if (!std.mem.startsWith(u8, asset.key, key_prefix)) continue;
            if (!std.mem.endsWith(u8, asset.key, ".png")) continue;
            return if (asset.bytes.len > 0) asset else null;
        }
        return null;
    }
};

pub const Asset = struct {
    key: [:0]u8,
    kind: AssetKind,
    bytes: []u8,
    filename: [:0]u8,

    pub fn init(allocator: std.mem.Allocator, spec: AssetSpec) !Asset {
        const key = try allocator.dupeZ(u8, spec.key);
        errdefer allocator.free(key);
        const bytes = try allocator.dupe(u8, spec.bytes);
        errdefer allocator.free(bytes);
        const filename = try allocator.dupeZ(u8, spec.filename);
        errdefer allocator.free(filename);

        return .{
            .key = key,
            .kind = spec.kind,
            .bytes = bytes,
            .filename = filename,
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

        const image_key = try allocator.dupeZ(u8, spec.image_key);
        errdefer allocator.free(image_key);
        const matte_key = try allocator.dupeZ(u8, spec.matte_key);
        errdefer allocator.free(matte_key);

        return .{ .image_key = image_key, .matte_key = matte_key, .frames = frames };
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

    pub fn isKeepFrame(self: *const OwnedFrame) bool {
        return self.frame.is_keep_frame != 0 or self.frame.first_shape_type == @intFromEnum(ShapeType.keep);
    }

    pub fn hasDrawableShapes(self: *const OwnedFrame) bool {
        for (self.shapes) |shape| {
            if (shape.shape_type != .keep and shape.shape_type != .unknown) return true;
        }
        return false;
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

fn buildMetadataTables(allocator: std.mem.Allocator, sprites: []const Sprite) !MetadataTables {
    var frame_total: usize = 0;
    var shape_total: usize = 0;

    for (sprites) |sprite| {
        frame_total = std.math.add(usize, frame_total, sprite.frames.len) catch return error.InvalidFrameCount;
        if (frame_total > max_total_sprite_frames) return error.InvalidFrameCount;
        for (sprite.frames) |frame| {
            shape_total = std.math.add(usize, shape_total, frame.shapes.len) catch return error.InvalidShapeCount;
            if (shape_total > max_total_shapes) return error.InvalidShapeCount;
        }
    }

    var sprite_records = try allocator.alloc(SpriteRecord, sprites.len);
    errdefer allocator.free(sprite_records);
    var frame_records = try allocator.alloc(FrameRecord, frame_total);
    errdefer allocator.free(frame_records);
    var sprite_frame_ranges = try allocator.alloc(RenderRange, sprites.len);
    errdefer allocator.free(sprite_frame_ranges);
    var shape_records = try allocator.alloc(ShapeRecord, shape_total);
    errdefer allocator.free(shape_records);
    var frame_shape_ranges = try allocator.alloc(RenderRange, frame_total);
    errdefer allocator.free(frame_shape_ranges);
    var frame_clip_path_command_ranges = try allocator.alloc(RenderRange, frame_total);
    errdefer allocator.free(frame_clip_path_command_ranges);
    var shape_path_command_ranges = try allocator.alloc(RenderRange, shape_total);
    errdefer allocator.free(shape_path_command_ranges);

    var clip_path_commands: std.ArrayList(PathCommand) = .empty;
    defer clip_path_commands.deinit(allocator);
    var shape_path_commands: std.ArrayList(PathCommand) = .empty;
    defer shape_path_commands.deinit(allocator);

    var frame_index: usize = 0;
    var shape_index: usize = 0;

    for (sprites, 0..) |sprite, sprite_index| {
        sprite_records[sprite_index] = spriteRecord(sprite);
        sprite_frame_ranges[sprite_index] = .{
            .start = frame_index,
            .count = sprite.frames.len,
        };

        for (sprite.frames) |frame| {
            frame_records[frame_index] = frameRecord(frame);
            frame_shape_ranges[frame_index] = .{
                .start = shape_index,
                .count = frame.shapes.len,
            };

            const clip_path_command_start = clip_path_commands.items.len;
            const clip_path_command_count = count: {
                const parsed_clip_path_commands = try svg_path.parse(allocator, frame.clip_path);
                defer allocator.free(parsed_clip_path_commands);
                try appendPathCommands(allocator, &clip_path_commands, parsed_clip_path_commands);
                break :count parsed_clip_path_commands.len;
            };
            frame_clip_path_command_ranges[frame_index] = .{
                .start = clip_path_command_start,
                .count = clip_path_command_count,
            };

            for (frame.shapes) |shape| {
                shape_records[shape_index] = shapeRecord(shape);

                const shape_path_command_start = shape_path_commands.items.len;
                const shape_path_command_count = count: {
                    if (shape.shape_type != .shape) break :count 0;
                    const parsed_shape_path_commands = try svg_path.parse(allocator, shape.path_data);
                    defer allocator.free(parsed_shape_path_commands);
                    try appendPathCommands(allocator, &shape_path_commands, parsed_shape_path_commands);
                    break :count parsed_shape_path_commands.len;
                };
                shape_path_command_ranges[shape_index] = .{
                    .start = shape_path_command_start,
                    .count = shape_path_command_count,
                };
                shape_index += 1;
            }

            frame_index += 1;
        }
    }

    const clip_path_command_slice = try clip_path_commands.toOwnedSlice(allocator);
    errdefer allocator.free(clip_path_command_slice);
    const shape_path_command_slice = try shape_path_commands.toOwnedSlice(allocator);
    errdefer allocator.free(shape_path_command_slice);

    return .{
        .sprite_records = sprite_records,
        .frame_records = frame_records,
        .sprite_frame_ranges = sprite_frame_ranges,
        .shape_records = shape_records,
        .frame_shape_ranges = frame_shape_ranges,
        .clip_path_commands = clip_path_command_slice,
        .frame_clip_path_command_ranges = frame_clip_path_command_ranges,
        .shape_path_commands = shape_path_command_slice,
        .shape_path_command_ranges = shape_path_command_ranges,
    };
}

fn appendPathCommands(
    allocator: std.mem.Allocator,
    commands: *std.ArrayList(PathCommand),
    additional_commands: []const PathCommand,
) !void {
    if (additional_commands.len > max_total_path_commands) return error.InvalidPathCommandCount;
    const next_count = std.math.add(usize, commands.items.len, additional_commands.len) catch return error.InvalidPathCommandCount;
    if (next_count > max_total_path_commands) return error.InvalidPathCommandCount;
    try commands.appendSlice(allocator, additional_commands);
}

fn spriteRecord(sprite: Sprite) SpriteRecord {
    return .{
        .image_key_utf8 = sprite.image_key.ptr,
        .matte_key_utf8 = sprite.matte_key.ptr,
        .frame_count = @intCast(sprite.frames.len),
        .is_matte = if (sprite.isMatte()) 1 else 0,
        .has_matte = if (sprite.matte_key.len > 0) 1 else 0,
    };
}

fn frameRecord(frame: OwnedFrame) FrameRecord {
    return .{
        .alpha = frame.frame.alpha,
        .layout = frame.frame.layout,
        .transform = frame.frame.transform,
        .nx = frame.frame.nx,
        .ny = frame.frame.ny,
        .shape_count = frame.frame.shape_count,
        .first_shape_type = frame.frame.first_shape_type,
        .visible = frame.frame.visible,
        .is_keep_frame = frame.frame.is_keep_frame,
        .clip_path_utf8 = frame.clip_path.ptr,
    };
}

fn shapeRecord(shape: Shape) ShapeRecord {
    return .{
        .shape_type = @intFromEnum(shape.shape_type),
        .path_data_utf8 = shape.path_data.ptr,
        .rect = shape.rect,
        .ellipse = shape.ellipse,
        .styles = shape.styles,
        .transform = shape.transform,
        .has_styles = if (shape.has_styles) 1 else 0,
        .has_transform = if (shape.has_transform) 1 else 0,
    };
}

fn buildRenderData(allocator: std.mem.Allocator, sprites: []const Sprite, frame_count_value: i32) !RenderData {
    const frame_count: usize = @intCast(frame_count_value);
    var command_counts = try allocator.alloc(usize, frame_count);
    defer allocator.free(command_counts);
    @memset(command_counts, 0);
    var item_counts = try allocator.alloc(usize, frame_count);
    defer allocator.free(item_counts);
    @memset(item_counts, 0);

    for (sprites, 0..) |sprite, sprite_index| {
        var shape_frame_index: usize = 0;
        for (sprite.frames[0..@min(frame_count, sprite.frames.len)], 0..) |owned_frame, frame_index| {
            if (!owned_frame.isKeepFrame()) {
                shape_frame_index = frame_index;
            }
            if (renderCommandForFrame(sprite_index, owned_frame.frame) != null) {
                command_counts[frame_index] += 1;
            }
            if (renderItemForFrame(&sprite, sprite_index, frame_index, shape_frame_index) != null) {
                item_counts[frame_index] += 1;
            }
        }
    }

    var command_ranges = try allocator.alloc(RenderRange, frame_count);
    errdefer allocator.free(command_ranges);
    var item_ranges = try allocator.alloc(RenderRange, frame_count);
    errdefer allocator.free(item_ranges);

    var command_total: usize = 0;
    for (command_counts, 0..) |count, frame_index| {
        command_ranges[frame_index] = .{
            .start = command_total,
            .count = count,
        };
        command_total = std.math.add(usize, command_total, count) catch return error.InvalidFrameCount;
    }
    var item_total: usize = 0;
    for (item_counts, 0..) |count, frame_index| {
        item_ranges[frame_index] = .{
            .start = item_total,
            .count = count,
        };
        item_total = std.math.add(usize, item_total, count) catch return error.InvalidFrameCount;
    }

    var commands = try allocator.alloc(RenderCommand, command_total);
    errdefer allocator.free(commands);
    var items = try allocator.alloc(RenderItem, item_total);
    errdefer allocator.free(items);

    for (command_ranges, 0..) |range, frame_index| {
        command_counts[frame_index] = range.start;
    }
    for (item_ranges, 0..) |range, frame_index| {
        item_counts[frame_index] = range.start;
    }

    for (sprites, 0..) |sprite, sprite_index| {
        var shape_frame_index: usize = 0;
        for (sprite.frames[0..@min(frame_count, sprite.frames.len)], 0..) |owned_frame, frame_index| {
            if (!owned_frame.isKeepFrame()) {
                shape_frame_index = frame_index;
            }
            const command = renderCommandForFrame(sprite_index, owned_frame.frame) orelse continue;
            const command_index = command_counts[frame_index];
            commands[command_index] = command;
            command_counts[frame_index] += 1;

            const item = renderItemForFrame(&sprite, sprite_index, frame_index, shape_frame_index) orelse continue;
            const item_index = item_counts[frame_index];
            items[item_index] = item;
            item_counts[frame_index] += 1;
        }
    }

    return .{
        .commands = commands,
        .command_ranges = command_ranges,
        .items = items,
        .item_ranges = item_ranges,
    };
}

fn renderCommandForFrame(sprite_index: usize, frame: Frame) ?RenderCommand {
    if (frame.visible == 0 or !std.math.isFinite(frame.alpha) or frame.alpha <= 0) return null;
    if (!layoutIsFinite(frame.layout) or frame.layout.width <= 0 or frame.layout.height <= 0) return null;
    if (!transformIsFinite(frame.transform)) return null;

    return .{
        .sprite_index = @intCast(sprite_index),
        .opacity = frame.alpha,
        .bounds = frame.layout,
        .transform = frame.transform,
    };
}

fn layoutIsFinite(layout: Layout) bool {
    return std.math.isFinite(layout.x) and
        std.math.isFinite(layout.y) and
        std.math.isFinite(layout.width) and
        std.math.isFinite(layout.height);
}

fn transformIsFinite(transform: Transform) bool {
    return std.math.isFinite(transform.a) and
        std.math.isFinite(transform.b) and
        std.math.isFinite(transform.c) and
        std.math.isFinite(transform.d) and
        std.math.isFinite(transform.tx) and
        std.math.isFinite(transform.ty);
}

fn renderItemForFrame(sprite: *const Sprite, sprite_index: usize, frame_index: usize, shape_frame_index: usize) ?RenderItem {
    if (frame_index >= sprite.frames.len) return null;
    const owned_frame = &sprite.frames[frame_index];
    const command = renderCommandForFrame(sprite_index, owned_frame.frame) orelse return null;
    const shape_frame = &sprite.frames[@min(shape_frame_index, sprite.frames.len - 1)];

    return .{
        .sprite_index = command.sprite_index,
        .frame_index = @intCast(frame_index),
        .shape_frame_index = @intCast(shape_frame_index),
        .opacity = command.opacity,
        .bounds = command.bounds,
        .transform = command.transform,
        .is_matte = if (sprite.isMatte()) 1 else 0,
        .has_matte = if (sprite.matte_key.len > 0) 1 else 0,
        .has_clip_path = if (owned_frame.clip_path.len > 0) 1 else 0,
        .has_shapes = if (shape_frame.hasDrawableShapes()) 1 else 0,
    };
}

fn buildVisualFrameIndices(
    allocator: std.mem.Allocator,
    items: []const RenderItem,
    ranges: []const RenderRange,
) ![]u32 {
    var indices = try allocator.alloc(u32, ranges.len);
    errdefer allocator.free(indices);

    for (ranges, 0..) |range, frame_index| {
        const current = items[range.start .. range.start + range.count];
        if (frame_index > 0) {
            const previous_range = ranges[frame_index - 1];
            const previous = items[previous_range.start .. previous_range.start + previous_range.count];
            if (renderItemSlicesEqual(current, previous)) {
                indices[frame_index] = indices[frame_index - 1];
                continue;
            }
        }
        indices[frame_index] = @intCast(frame_index);
    }

    return indices;
}

fn renderItemSlicesEqual(left: []const RenderItem, right: []const RenderItem) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_item, right_item| {
        if (!renderItemsEqual(left_item, right_item)) return false;
    }
    return true;
}

fn renderItemsEqual(left: RenderItem, right: RenderItem) bool {
    return left.sprite_index == right.sprite_index and
        f32BitsEqual(left.opacity, right.opacity) and
        layoutsEqual(left.bounds, right.bounds) and
        transformsEqual(left.transform, right.transform) and
        left.is_matte == right.is_matte and
        left.has_matte == right.has_matte and
        left.has_clip_path == right.has_clip_path and
        left.has_shapes == right.has_shapes and
        (left.has_clip_path == 0 or left.frame_index == right.frame_index) and
        (left.has_shapes == 0 or left.shape_frame_index == right.shape_frame_index);
}

fn layoutsEqual(left: Layout, right: Layout) bool {
    return f32BitsEqual(left.x, right.x) and
        f32BitsEqual(left.y, right.y) and
        f32BitsEqual(left.width, right.width) and
        f32BitsEqual(left.height, right.height);
}

fn transformsEqual(left: Transform, right: Transform) bool {
    return f32BitsEqual(left.a, right.a) and
        f32BitsEqual(left.b, right.b) and
        f32BitsEqual(left.c, right.c) and
        f32BitsEqual(left.d, right.d) and
        f32BitsEqual(left.tx, right.tx) and
        f32BitsEqual(left.ty, right.ty);
}

fn f32BitsEqual(left: f32, right: f32) bool {
    return @as(u32, @bitCast(left)) == @as(u32, @bitCast(right));
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
    if (spec.frames <= 0 or spec.frames > max_movie_frame_count) return error.InvalidFrames;
    if (spec.sprites.len != 0 and spec.sprite_count != spec.sprites.len) return error.InvalidMovieCounts;
    if (spec.sprite_count > max_sprite_count) return error.InvalidMovieCounts;
    if (spec.image_count > max_asset_count) return error.InvalidMovieCounts;
    if (spec.audio_count > max_audio_count) return error.InvalidMovieCounts;
    if (spec.sprites.len > max_sprite_count) return error.InvalidMovieCounts;
    if (spec.assets.len > max_asset_count) return error.InvalidMovieCounts;
    if (spec.audios.len > max_audio_count) return error.InvalidMovieCounts;
    var total_frame_count: usize = 0;
    var total_shape_count: usize = 0;
    for (spec.sprites) |sprite| {
        if (sprite.frames.len > max_total_sprite_frames) return error.InvalidFrameCount;
        total_frame_count = std.math.add(usize, total_frame_count, sprite.frames.len) catch return error.InvalidFrameCount;
        if (total_frame_count > max_total_sprite_frames) return error.InvalidFrameCount;
        for (sprite.frames) |frame| {
            if (frame.shapes.len > max_total_shapes) return error.InvalidShapeCount;
            total_shape_count = std.math.add(usize, total_shape_count, frame.shapes.len) catch return error.InvalidShapeCount;
            if (total_shape_count > max_total_shapes) return error.InvalidShapeCount;
        }
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

    const items = movie.renderItems(0).?;
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqual(@as(u32, 0), items[0].sprite_index);
    try std.testing.expectEqual(@as(u32, 0), items[0].frame_index);
    try std.testing.expectEqual(@as(u32, 0), items[0].shape_frame_index);
    try std.testing.expectEqual(@as(u8, 0), items[0].is_matte);
    try std.testing.expectEqual(@as(u8, 0), items[0].has_matte);
}

test "asset init cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, assetInitAllocationFailure, .{});
}

fn assetInitAllocationFailure(allocator: std.mem.Allocator) !void {
    var asset = try Asset.init(allocator, .{
        .key = "hero",
        .kind = .image_bytes,
        .bytes = "png-bytes",
        .filename = "hero.png",
    });
    defer asset.deinit(allocator);
}

test "sprite init cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, spriteInitAllocationFailure, .{});
}

fn spriteInitAllocationFailure(allocator: std.mem.Allocator) !void {
    var sprite = try Sprite.init(allocator, .{
        .image_key = "hero",
        .matte_key = "hero.matte",
    });
    defer sprite.deinit(allocator);
}

test "render items resolve keep-frame shape source once" {
    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 2,
        .sprite_count = 1,
        .sprites = &.{
            .{
                .image_key = "shape_host",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(ShapeType.rect),
                            .shape_count = 1,
                        }),
                        .shapes = &.{
                            .{
                                .shape_type = .rect,
                                .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            },
                        },
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 1, .y = 2, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(ShapeType.keep),
                            .shape_count = 1,
                        }),
                        .shapes = &.{
                            .{ .shape_type = .keep },
                        },
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    const frame_zero_items = movie.renderItems(0).?;
    try std.testing.expectEqual(@as(usize, 1), frame_zero_items.len);
    try std.testing.expectEqual(@as(u32, 0), frame_zero_items[0].shape_frame_index);
    try std.testing.expectEqual(@as(u8, 1), frame_zero_items[0].has_shapes);

    const keep_items = movie.renderItems(1).?;
    try std.testing.expectEqual(@as(usize, 1), keep_items.len);
    try std.testing.expectEqual(@as(u32, 1), keep_items[0].frame_index);
    try std.testing.expectEqual(@as(u32, 0), keep_items[0].shape_frame_index);
    try std.testing.expectEqual(@as(u8, 1), keep_items[0].has_shapes);
}

test "visual frame indices alias adjacent identical static frames" {
    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 3,
        .sprite_count = 1,
        .sprites = &.{
            .{
                .image_key = "image_0",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                        }),
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                        }),
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 5, .y = 0, .width = 10, .height = 10 },
                        }),
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 0), movie.visualFrameIndex(0).?);
    try std.testing.expectEqual(@as(u32, 0), movie.visualFrameIndex(1).?);
    try std.testing.expectEqual(@as(u32, 2), movie.visualFrameIndex(2).?);
}

test "render tables skip non-finite frame geometry" {
    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 3,
        .sprite_count = 1,
        .sprites = &.{
            .{
                .image_key = "image_0",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                        }),
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = std.math.nan(f32), .height = 10 },
                        }),
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .transform = .{ .a = std.math.inf(f32), .d = 1 },
                        }),
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), movie.renderCommands(0).?.len);
    try std.testing.expectEqual(@as(usize, 0), movie.renderCommands(1).?.len);
    try std.testing.expectEqual(@as(usize, 0), movie.renderCommands(2).?.len);
    try std.testing.expectEqual(@as(usize, 1), movie.renderItems(0).?.len);
    try std.testing.expectEqual(@as(usize, 0), movie.renderItems(1).?.len);
    try std.testing.expectEqual(@as(usize, 0), movie.renderItems(2).?.len);
}

test "movie owns parsed path commands for clips and path shapes" {
    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 1,
        .sprite_count = 1,
        .sprites = &.{
            .{
                .image_key = "vector",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(ShapeType.shape),
                            .shape_count = 1,
                        }),
                        .clip_path = "M0 0 L10 0 L10 10 Z",
                        .shapes = &.{
                            .{
                                .shape_type = .shape,
                                .path_data = "M1 2 h3 v4 z",
                            },
                        },
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), movie.metadata.sprite_records.len);
    try std.testing.expectEqual(@as(usize, 1), movie.metadata.frame_records.len);
    try std.testing.expectEqual(@as(usize, 1), movie.metadata.shape_records.len);
    try std.testing.expectEqual(@as(usize, 4), movie.metadata.clip_path_commands.len);
    try std.testing.expectEqual(@as(usize, 4), movie.metadata.shape_path_commands.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(PathCommandType.move)), movie.metadata.clip_path_commands[0].command_type);
    try std.testing.expectEqual(@as(i32, @intFromEnum(PathCommandType.close)), movie.metadata.clip_path_commands[3].command_type);
    try std.testing.expectEqual(@as(i32, @intFromEnum(PathCommandType.move)), movie.metadata.shape_path_commands[0].command_type);
    try std.testing.expectEqual(@as(f32, 4), movie.metadata.shape_path_commands[1].p0_x);
    try std.testing.expectEqual(@as(f32, 2), movie.metadata.shape_path_commands[1].p0_y);
    try std.testing.expectEqual(@as(f32, 4), movie.metadata.shape_path_commands[2].p0_x);
    try std.testing.expectEqual(@as(f32, 6), movie.metadata.shape_path_commands[2].p0_y);
    try std.testing.expectEqual(@as(usize, 0), movie.metadata.sprite_frame_ranges[0].start);
    try std.testing.expectEqual(@as(usize, 1), movie.metadata.sprite_frame_ranges[0].count);
    try std.testing.expectEqual(@as(usize, 0), movie.metadata.frame_shape_ranges[0].start);
    try std.testing.expectEqual(@as(usize, 1), movie.metadata.frame_shape_ranges[0].count);
}

test "movie supports concurrent read-only access" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var movie = try Movie.init(allocator, .{
        .version = "2.0.0",
        .view_box_width = 320,
        .view_box_height = 240,
        .fps = 30,
        .frames = 2,
        .assets = &.{
            .{
                .key = "hero",
                .kind = .filename,
                .filename = "hero.png",
            },
            .{
                .key = "hero.png",
                .kind = .image_bytes,
                .bytes = "png-bytes",
            },
        },
        .sprite_count = 1,
        .sprites = &.{
            .{
                .image_key = "hero",
                .frames = &.{
                    .{
                        .frame = computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(ShapeType.shape),
                            .shape_count = 1,
                        }),
                        .clip_path = "M0 0 L10 0 Z",
                        .shapes = &.{
                            .{
                                .shape_type = .shape,
                                .path_data = "M1 2 L3 4",
                            },
                        },
                    },
                    .{
                        .frame = computeFrame(.{
                            .alpha = 0.75,
                            .layout = .{ .x = 1, .y = 2, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(ShapeType.keep),
                            .shape_count = 1,
                        }),
                        .shapes = &.{
                            .{ .shape_type = .keep },
                        },
                    },
                },
            },
        },
    });
    defer movie.deinit(allocator);

    const worker_count = 4;
    var threads: [worker_count]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |*thread| {
            thread.join();
        }
    }

    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, queryMovieReadOnlyRepeatedly, .{&movie});
        spawned += 1;
    }
    for (&threads) |*thread| {
        thread.join();
    }
}

fn queryMovieReadOnlyRepeatedly(movie: *const Movie) void {
    var iteration: usize = 0;
    while (iteration < 128) : (iteration += 1) {
        const frame_index = iteration % 2;

        const info = movie.info();
        assertWorker(std.mem.eql(u8, info.version, "2.0.0"));
        assertWorker(info.frames == 2);

        const sprite = movie.spriteInfo(0) orelse @panic("missing sprite");
        assertWorker(std.mem.eql(u8, sprite.image_key, "hero"));
        assertWorker(sprite.frame_count == 2);

        const frame = movie.frameInfo(0, frame_index) orelse @panic("missing frame");
        assertWorker(frame.frame.visible == 1);

        const commands = movie.renderCommands(frame_index) orelse @panic("missing commands");
        assertWorker(commands.len == 1);
        assertWorker(commands[0].sprite_index == 0);

        const items = movie.renderItems(frame_index) orelse @panic("missing items");
        assertWorker(items.len == 1);
        assertWorker(items[0].has_shapes == 1);

        const asset = movie.resolveImageAsset("hero") orelse @panic("missing image asset");
        assertWorker(std.mem.eql(u8, asset.bytes, "png-bytes"));

        assertWorker(movie.metadata.sprite_records.len == 1);
        assertWorker(movie.metadata.frame_records.len == 2);
        assertWorker(movie.metadata.clip_path_commands.len == 3);
        assertWorker(movie.metadata.shape_path_commands.len == 2);
        assertWorker(movie.visualFrameIndex(frame_index) != null);
    }
}

fn assertWorker(condition: bool) void {
    if (!condition) @panic("concurrent read assertion failed");
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
