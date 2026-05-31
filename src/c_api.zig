const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
const model = @import("model.zig");

pub const abi_version: u32 = 1;

/// ABI status values. Keep these in sync with include/svga.h.
pub const Status = enum(i32) {
    ok = 0,
    null_argument = 1,
    invalid_argument = 2,
    out_of_memory = 3,
    unsupported = 4,
    internal_error = 5,
    parse_error = 6,
    io_error = 7,
};

const MovieHandle = opaque {};

// The C ABI stores one allocator choice in the library. page_allocator avoids
// thread-local allocator assumptions on single-threaded and WASM targets.
const allocator = if (builtin.single_threaded or builtin.target.cpu.arch.isWasm())
    std.heap.page_allocator
else
    std.heap.smp_allocator;

// Freestanding and Emscripten builds are intended to receive bytes from their
// host runtime. The parse_file API reports unsupported instead of pulling in a
// filesystem contract those targets cannot satisfy.
const has_filesystem = switch (builtin.target.os.tag) {
    .freestanding, .emscripten => false,
    else => true,
};

const has_network = switch (builtin.target.os.tag) {
    .freestanding, .wasi, .emscripten => false,
    else => true,
};

pub const MovieDesc = extern struct {
    abi_version: u32,
    view_box_width: f32,
    view_box_height: f32,
    fps: i32,
    frames: i32,
    image_count: u32,
    sprite_count: u32,
    audio_count: u32,
    version_utf8: ?[*:0]const u8,
};

pub const MovieInfo = extern struct {
    abi_version: u32,
    view_box_width: f32,
    view_box_height: f32,
    fps: i32,
    frames: i32,
    image_count: u32,
    sprite_count: u32,
    audio_count: u32,
    version_utf8: ?[*:0]const u8,
};

pub const DownloadOptions = extern struct {
    abi_version: u32,
    max_input_bytes: usize,
};

pub const Rect = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Size2D = extern struct {
    width: f64,
    height: f64,
};

pub const Point2D = extern struct {
    x: f64,
    y: f64,
};

pub const Rect2D = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const MovieLayout = extern struct {
    scale_x: f64,
    scale_y: f64,
    origin: Point2D,
};

pub const FrameRange = extern struct {
    lower_bound: i32,
    upper_bound: i32,
};

pub const PlaybackState = extern struct {
    frame_count: i32,
    fps: i32,
    playback_range: FrameRange,
    elapsed_seconds: f64,
    playback_speed: f64,
    start_frame_offset: i64,
    loop_count: i64,
    reverse: u8,
    fill_mode: i32,
};

pub const PlaybackPosition = extern struct {
    frame_index: i32,
    completed_loop_count: i64,
    did_finish: u8,
};

pub const Transform = extern struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    tx: f32,
    ty: f32,
};

pub const SpriteInfo = model.SpriteRecord;
pub const FrameInfo = model.FrameRecord;

pub const RenderCommandInfo = model.RenderCommand;
pub const RenderItemInfo = model.RenderItem;
pub const RenderRangeInfo = model.RenderRange;
pub const RenderCapabilitiesInfo = model.RenderCapabilities;
pub const PathCommandInfo = model.PathCommand;

pub const AssetInfo = extern struct {
    key_utf8: ?[*:0]const u8,
    kind: i32,
    bytes: ?[*]const u8,
    byte_count: usize,
    filename_utf8: ?[*:0]const u8,
};

pub const AudioInfo = extern struct {
    audio_key_utf8: ?[*:0]const u8,
    start_frame: i32,
    end_frame: i32,
    start_time_ms: i32,
    total_time_ms: i32,
};

pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const ShapeStyle = extern struct {
    fill: Color,
    stroke: Color,
    stroke_width: f32,
    line_cap: i32,
    line_join: i32,
    miter_limit: f32,
    line_dash_i: f32,
    line_dash_ii: f32,
    line_dash_iii: f32,
    has_fill: u8,
    has_stroke: u8,
};

pub const ShapeRect = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    corner_radius: f32,
};

pub const ShapeEllipse = extern struct {
    x: f32,
    y: f32,
    radius_x: f32,
    radius_y: f32,
};

pub const ShapeInfo = model.ShapeRecord;

const ContentMode = enum(i32) {
    fit = 0,
    fill = 1,
    scale_to_fill = 2,
    top = 3,
    bottom = 4,
    left = 5,
    right = 6,
};

const FillMode = enum(i32) {
    current = 0,
    backward = 1,
    forward = 2,
};

export fn svga_abi_version() callconv(.c) u32 {
    return abi_version;
}

export fn svga_status_message(status_code: i32) callconv(.c) [*:0]const u8 {
    return switch (status_code) {
        statusCode(.ok) => "ok",
        statusCode(.null_argument) => "null argument",
        statusCode(.invalid_argument) => "invalid argument",
        statusCode(.out_of_memory) => "out of memory",
        statusCode(.unsupported) => "unsupported",
        statusCode(.internal_error) => "internal error",
        statusCode(.parse_error) => "parse error",
        statusCode(.io_error) => "I/O error",
        else => "unknown status",
    };
}

export fn svga_movie_create(out_movie: ?*?*MovieHandle, desc: ?*const MovieDesc) callconv(.c) i32 {
    const out = out_movie orelse return statusCode(.null_argument);
    out.* = null;

    const movie_desc = desc orelse return statusCode(.null_argument);
    if (movie_desc.abi_version != abi_version) return statusCode(.invalid_argument);

    const movie = allocator.create(model.Movie) catch return statusCode(.out_of_memory);

    movie.* = model.Movie.init(allocator, .{
        .version = versionSlice(movie_desc.version_utf8),
        .view_box_width = movie_desc.view_box_width,
        .view_box_height = movie_desc.view_box_height,
        .fps = movie_desc.fps,
        .frames = movie_desc.frames,
        .image_count = movie_desc.image_count,
        .sprite_count = movie_desc.sprite_count,
        .audio_count = movie_desc.audio_count,
    }) catch |err| {
        allocator.destroy(movie);
        return statusCode(statusFromError(err));
    };

    out.* = handleFromMovie(movie);
    return statusCode(.ok);
}

export fn svga_movie_destroy(movie_handle: ?*MovieHandle) callconv(.c) void {
    const handle = movie_handle orelse return;
    const movie = movieFromHandle(handle);
    core.destroyMovie(allocator, movie);
}

export fn svga_movie_get_info(movie_handle: ?*const MovieHandle, out_info: ?*MovieInfo) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const movie_info = movieFromConstHandle(handle).info();

    info.* = .{
        .abi_version = abi_version,
        .view_box_width = movie_info.view_box_width,
        .view_box_height = movie_info.view_box_height,
        .fps = movie_info.fps,
        .frames = movie_info.frames,
        .image_count = movie_info.image_count,
        .sprite_count = movie_info.sprite_count,
        .audio_count = movie_info.audio_count,
        .version_utf8 = movie_info.version.ptr,
    };
    return statusCode(.ok);
}

export fn svga_movie_get_sprite_info(movie_handle: ?*const MovieHandle, sprite_index: u32, out_info: ?*SpriteInfo) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const sprite_info = movieFromConstHandle(handle).spriteInfo(sprite_index) orelse return statusCode(.invalid_argument);

    info.* = .{
        .image_key_utf8 = sprite_info.image_key.ptr,
        .matte_key_utf8 = sprite_info.matte_key.ptr,
        .frame_count = sprite_info.frame_count,
        .is_matte = if (sprite_info.is_matte) 1 else 0,
        .has_matte = if (sprite_info.has_matte) 1 else 0,
    };
    return statusCode(.ok);
}

export fn svga_movie_get_sprite_table(
    movie_handle: ?*const MovieHandle,
    out_sprites: ?*?[*]const SpriteInfo,
    out_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const sprites_out = out_sprites orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    sprites_out.* = null;
    count_out.* = 0;

    const records = movieFromConstHandle(handle).metadata.sprite_records;
    count_out.* = records.len;
    if (records.len > 0) {
        sprites_out.* = records.ptr;
    }
    return statusCode(.ok);
}

export fn svga_movie_get_frame_info(movie_handle: ?*const MovieHandle, sprite_index: u32, frame_index: u32, out_info: ?*FrameInfo) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const frame_info = movieFromConstHandle(handle).frameInfo(sprite_index, frame_index) orelse return statusCode(.invalid_argument);
    const frame = frame_info.frame;

    info.* = .{
        .alpha = frame.alpha,
        .layout = .{
            .x = frame.layout.x,
            .y = frame.layout.y,
            .width = frame.layout.width,
            .height = frame.layout.height,
        },
        .transform = .{
            .a = frame.transform.a,
            .b = frame.transform.b,
            .c = frame.transform.c,
            .d = frame.transform.d,
            .tx = frame.transform.tx,
            .ty = frame.transform.ty,
        },
        .nx = frame.nx,
        .ny = frame.ny,
        .shape_count = frame.shape_count,
        .first_shape_type = frame.first_shape_type,
        .visible = frame.visible,
        .is_keep_frame = frame.is_keep_frame,
        .clip_path_utf8 = frame_info.clip_path.ptr,
    };
    return statusCode(.ok);
}

export fn svga_movie_get_frame_table(
    movie_handle: ?*const MovieHandle,
    out_frames: ?*?[*]const FrameInfo,
    out_frame_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const frames_out = out_frames orelse return statusCode(.null_argument);
    const frame_count_out = out_frame_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    frames_out.* = null;
    frame_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const metadata = movieFromConstHandle(handle).metadata;
    if (metadata.frame_records.len > 0) {
        frames_out.* = metadata.frame_records.ptr;
    }
    frame_count_out.* = metadata.frame_records.len;
    if (metadata.sprite_frame_ranges.len > 0) {
        ranges_out.* = metadata.sprite_frame_ranges.ptr;
    }
    range_count_out.* = metadata.sprite_frame_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_asset_count(movie_handle: ?*const MovieHandle, out_count: ?*u32) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const count = out_count orelse return statusCode(.null_argument);
    count.* = @intCast(movieFromConstHandle(handle).assets.len);
    return statusCode(.ok);
}

export fn svga_movie_get_asset_info(movie_handle: ?*const MovieHandle, asset_index: u32, out_info: ?*AssetInfo) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const movie = movieFromConstHandle(handle);
    if (asset_index >= movie.assets.len) return statusCode(.invalid_argument);

    const asset = &movie.assets[asset_index];
    info.* = assetInfo(asset);
    return statusCode(.ok);
}

export fn svga_movie_find_asset(
    movie_handle: ?*const MovieHandle,
    key_utf8: ?[*:0]const u8,
    out_info: ?*AssetInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const key_ptr = key_utf8 orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    info.* = emptyAssetInfo();

    const key = std.mem.span(key_ptr);
    const asset = movieFromConstHandle(handle).assetByKey(key) orelse return statusCode(.invalid_argument);
    info.* = assetInfo(asset);
    return statusCode(.ok);
}

export fn svga_movie_resolve_image_asset(
    movie_handle: ?*const MovieHandle,
    image_key_utf8: ?[*:0]const u8,
    out_info: ?*AssetInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const key_ptr = image_key_utf8 orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    info.* = emptyAssetInfo();

    const key = std.mem.span(key_ptr);
    const asset = movieFromConstHandle(handle).resolveImageAsset(key) orelse return statusCode(.invalid_argument);
    info.* = assetInfo(asset);
    return statusCode(.ok);
}

export fn svga_movie_resolve_audio_asset(
    movie_handle: ?*const MovieHandle,
    audio_key_utf8: ?[*:0]const u8,
    out_info: ?*AssetInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const key_ptr = audio_key_utf8 orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    info.* = emptyAssetInfo();

    const key = std.mem.span(key_ptr);
    const asset = movieFromConstHandle(handle).resolveAudioAsset(key) orelse return statusCode(.invalid_argument);
    info.* = assetInfo(asset);
    return statusCode(.ok);
}

export fn svga_movie_get_audio_info(movie_handle: ?*const MovieHandle, audio_index: u32, out_info: ?*AudioInfo) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const movie = movieFromConstHandle(handle);
    if (audio_index >= movie.audios.len) return statusCode(.invalid_argument);

    const audio = &movie.audios[audio_index];
    info.* = .{
        .audio_key_utf8 = audio.audio_key.ptr,
        .start_frame = audio.start_frame,
        .end_frame = audio.end_frame,
        .start_time_ms = audio.start_time_ms,
        .total_time_ms = audio.total_time_ms,
    };
    return statusCode(.ok);
}

export fn svga_movie_get_shape_info(
    movie_handle: ?*const MovieHandle,
    sprite_index: u32,
    frame_index: u32,
    shape_index: u32,
    out_info: ?*ShapeInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const info = out_info orelse return statusCode(.null_argument);
    const movie = movieFromConstHandle(handle);
    if (sprite_index >= movie.sprites.len) return statusCode(.invalid_argument);
    const sprite = &movie.sprites[sprite_index];
    if (frame_index >= sprite.frames.len) return statusCode(.invalid_argument);
    const frame = &sprite.frames[frame_index];
    if (shape_index >= frame.shapes.len) return statusCode(.invalid_argument);

    const shape = &frame.shapes[shape_index];
    info.* = .{
        .shape_type = @intFromEnum(shape.shape_type),
        .path_data_utf8 = shape.path_data.ptr,
        .rect = .{
            .x = shape.rect.x,
            .y = shape.rect.y,
            .width = shape.rect.width,
            .height = shape.rect.height,
            .corner_radius = shape.rect.corner_radius,
        },
        .ellipse = .{
            .x = shape.ellipse.x,
            .y = shape.ellipse.y,
            .radius_x = shape.ellipse.radius_x,
            .radius_y = shape.ellipse.radius_y,
        },
        .styles = .{
            .fill = .{
                .r = shape.styles.fill.r,
                .g = shape.styles.fill.g,
                .b = shape.styles.fill.b,
                .a = shape.styles.fill.a,
            },
            .stroke = .{
                .r = shape.styles.stroke.r,
                .g = shape.styles.stroke.g,
                .b = shape.styles.stroke.b,
                .a = shape.styles.stroke.a,
            },
            .stroke_width = shape.styles.stroke_width,
            .line_cap = shape.styles.line_cap,
            .line_join = shape.styles.line_join,
            .miter_limit = shape.styles.miter_limit,
            .line_dash_i = shape.styles.line_dash_i,
            .line_dash_ii = shape.styles.line_dash_ii,
            .line_dash_iii = shape.styles.line_dash_iii,
            .has_fill = shape.styles.has_fill,
            .has_stroke = shape.styles.has_stroke,
        },
        .transform = .{
            .a = shape.transform.a,
            .b = shape.transform.b,
            .c = shape.transform.c,
            .d = shape.transform.d,
            .tx = shape.transform.tx,
            .ty = shape.transform.ty,
        },
        .has_styles = if (shape.has_styles) 1 else 0,
        .has_transform = if (shape.has_transform) 1 else 0,
    };
    return statusCode(.ok);
}

export fn svga_movie_get_shape_table(
    movie_handle: ?*const MovieHandle,
    out_shapes: ?*?[*]const ShapeInfo,
    out_shape_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const shapes_out = out_shapes orelse return statusCode(.null_argument);
    const shape_count_out = out_shape_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    shapes_out.* = null;
    shape_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const metadata = movieFromConstHandle(handle).metadata;
    if (metadata.shape_records.len > 0) {
        shapes_out.* = metadata.shape_records.ptr;
    }
    shape_count_out.* = metadata.shape_records.len;
    if (metadata.frame_shape_ranges.len > 0) {
        ranges_out.* = metadata.frame_shape_ranges.ptr;
    }
    range_count_out.* = metadata.frame_shape_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_frame_clip_path_commands(
    movie_handle: ?*const MovieHandle,
    sprite_index: u32,
    frame_index: u32,
    out_commands: ?*?[*]const PathCommandInfo,
    out_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    count_out.* = 0;

    const movie = movieFromConstHandle(handle);
    if (sprite_index >= movie.sprites.len) return statusCode(.invalid_argument);
    const sprite = &movie.sprites[sprite_index];
    if (frame_index >= sprite.frames.len) return statusCode(.invalid_argument);

    const metadata = movie.metadata;
    const global_frame_index = metadata.sprite_frame_ranges[sprite_index].start + frame_index;
    if (global_frame_index >= metadata.frame_clip_path_command_ranges.len) return statusCode(.invalid_argument);
    const range = metadata.frame_clip_path_command_ranges[global_frame_index];
    if (range.start > metadata.clip_path_commands.len or range.count > metadata.clip_path_commands.len - range.start) {
        return statusCode(.invalid_argument);
    }
    const commands = metadata.clip_path_commands[range.start .. range.start + range.count];
    count_out.* = commands.len;
    if (commands.len > 0) {
        commands_out.* = commands.ptr;
    }
    return statusCode(.ok);
}

export fn svga_movie_get_frame_clip_path_command_table(
    movie_handle: ?*const MovieHandle,
    out_commands: ?*?[*]const PathCommandInfo,
    out_command_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const command_count_out = out_command_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    command_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const metadata = movieFromConstHandle(handle).metadata;
    if (metadata.clip_path_commands.len > 0) {
        commands_out.* = metadata.clip_path_commands.ptr;
    }
    command_count_out.* = metadata.clip_path_commands.len;
    if (metadata.frame_clip_path_command_ranges.len > 0) {
        ranges_out.* = metadata.frame_clip_path_command_ranges.ptr;
    }
    range_count_out.* = metadata.frame_clip_path_command_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_shape_path_commands(
    movie_handle: ?*const MovieHandle,
    sprite_index: u32,
    frame_index: u32,
    shape_index: u32,
    out_commands: ?*?[*]const PathCommandInfo,
    out_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    count_out.* = 0;

    const movie = movieFromConstHandle(handle);
    if (sprite_index >= movie.sprites.len) return statusCode(.invalid_argument);
    const sprite = &movie.sprites[sprite_index];
    if (frame_index >= sprite.frames.len) return statusCode(.invalid_argument);
    const frame = &sprite.frames[frame_index];
    if (shape_index >= frame.shapes.len) return statusCode(.invalid_argument);

    const metadata = movie.metadata;
    const global_frame_index = metadata.sprite_frame_ranges[sprite_index].start + frame_index;
    if (global_frame_index >= metadata.frame_shape_ranges.len) return statusCode(.invalid_argument);
    const shape_range = metadata.frame_shape_ranges[global_frame_index];
    const global_shape_index = shape_range.start + shape_index;
    if (global_shape_index >= metadata.shape_path_command_ranges.len) return statusCode(.invalid_argument);
    const command_range = metadata.shape_path_command_ranges[global_shape_index];
    if (command_range.start > metadata.shape_path_commands.len or command_range.count > metadata.shape_path_commands.len - command_range.start) {
        return statusCode(.invalid_argument);
    }
    const commands = metadata.shape_path_commands[command_range.start .. command_range.start + command_range.count];
    count_out.* = commands.len;
    if (commands.len > 0) {
        commands_out.* = commands.ptr;
    }
    return statusCode(.ok);
}

export fn svga_movie_get_shape_path_command_table(
    movie_handle: ?*const MovieHandle,
    out_commands: ?*?[*]const PathCommandInfo,
    out_command_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const command_count_out = out_command_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    command_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const metadata = movieFromConstHandle(handle).metadata;
    if (metadata.shape_path_commands.len > 0) {
        commands_out.* = metadata.shape_path_commands.ptr;
    }
    command_count_out.* = metadata.shape_path_commands.len;
    if (metadata.shape_path_command_ranges.len > 0) {
        ranges_out.* = metadata.shape_path_command_ranges.ptr;
    }
    range_count_out.* = metadata.shape_path_command_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_render_commands(
    movie_handle: ?*const MovieHandle,
    frame_index: u32,
    out_commands: ?*?[*]const RenderCommandInfo,
    out_count: ?*u32,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    count_out.* = 0;

    const commands = movieFromConstHandle(handle).renderCommands(frame_index) orelse return statusCode(.invalid_argument);
    count_out.* = @intCast(commands.len);
    if (commands.len > 0) {
        commands_out.* = commands.ptr;
    }
    return statusCode(.ok);
}

export fn svga_movie_get_render_items(
    movie_handle: ?*const MovieHandle,
    frame_index: u32,
    out_items: ?*?[*]const RenderItemInfo,
    out_count: ?*u32,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const items_out = out_items orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    items_out.* = null;
    count_out.* = 0;

    const items = movieFromConstHandle(handle).renderItems(frame_index) orelse return statusCode(.invalid_argument);
    count_out.* = @intCast(items.len);
    if (items.len > 0) {
        items_out.* = items.ptr;
    }
    return statusCode(.ok);
}

export fn svga_movie_get_render_command_table(
    movie_handle: ?*const MovieHandle,
    out_commands: ?*?[*]const RenderCommandInfo,
    out_command_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const commands_out = out_commands orelse return statusCode(.null_argument);
    const command_count_out = out_command_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    commands_out.* = null;
    command_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const movie = movieFromConstHandle(handle);
    if (movie.render_commands.len > 0) {
        commands_out.* = movie.render_commands.ptr;
    }
    command_count_out.* = movie.render_commands.len;
    if (movie.render_frame_ranges.len > 0) {
        ranges_out.* = movie.render_frame_ranges.ptr;
    }
    range_count_out.* = movie.render_frame_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_render_item_table(
    movie_handle: ?*const MovieHandle,
    out_items: ?*?[*]const RenderItemInfo,
    out_item_count: ?*usize,
    out_ranges: ?*?[*]const RenderRangeInfo,
    out_range_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const items_out = out_items orelse return statusCode(.null_argument);
    const item_count_out = out_item_count orelse return statusCode(.null_argument);
    const ranges_out = out_ranges orelse return statusCode(.null_argument);
    const range_count_out = out_range_count orelse return statusCode(.null_argument);

    items_out.* = null;
    item_count_out.* = 0;
    ranges_out.* = null;
    range_count_out.* = 0;

    const movie = movieFromConstHandle(handle);
    if (movie.render_items.len > 0) {
        items_out.* = movie.render_items.ptr;
    }
    item_count_out.* = movie.render_items.len;
    if (movie.render_item_frame_ranges.len > 0) {
        ranges_out.* = movie.render_item_frame_ranges.ptr;
    }
    range_count_out.* = movie.render_item_frame_ranges.len;
    return statusCode(.ok);
}

export fn svga_movie_get_render_capabilities(
    movie_handle: ?*const MovieHandle,
    out_capabilities: ?*RenderCapabilitiesInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const capabilities_out = out_capabilities orelse return statusCode(.null_argument);

    capabilities_out.* = renderCapabilitiesForMovie(movieFromConstHandle(handle));
    return statusCode(.ok);
}

export fn svga_movie_get_frame_render_capabilities(
    movie_handle: ?*const MovieHandle,
    frame_index: u32,
    out_capabilities: ?*RenderCapabilitiesInfo,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const capabilities_out = out_capabilities orelse return statusCode(.null_argument);
    const movie = movieFromConstHandle(handle);
    const items = movie.renderItems(frame_index) orelse return statusCode(.invalid_argument);
    const commands = movie.renderCommands(frame_index) orelse return statusCode(.invalid_argument);

    capabilities_out.* = renderCapabilitiesForItems(items, commands.len);
    return statusCode(.ok);
}

export fn svga_movie_get_visual_frame_table(
    movie_handle: ?*const MovieHandle,
    out_indices: ?*?[*]const u32,
    out_count: ?*usize,
) callconv(.c) i32 {
    const handle = movie_handle orelse return statusCode(.null_argument);
    const indices_out = out_indices orelse return statusCode(.null_argument);
    const count_out = out_count orelse return statusCode(.null_argument);

    indices_out.* = null;
    count_out.* = 0;

    const movie = movieFromConstHandle(handle);
    if (movie.visual_frame_indices.len > 0) {
        indices_out.* = movie.visual_frame_indices.ptr;
    }
    count_out.* = movie.visual_frame_indices.len;
    return statusCode(.ok);
}

export fn svga_movie_parse(bytes: ?[*]const u8, byte_count: usize, out_movie: ?*?*MovieHandle) callconv(.c) i32 {
    const out = out_movie orelse return statusCode(.null_argument);
    out.* = null;

    if (bytes == null and byte_count != 0) return statusCode(.null_argument);
    if (byte_count == 0) return statusCode(.invalid_argument);

    const input = bytes.?[0..byte_count];
    const movie = core.parseMovie(allocator, input) catch |err| return statusCode(statusFromError(err));
    out.* = handleFromMovie(movie);
    return statusCode(.ok);
}

export fn svga_movie_parse_file(path_utf8: ?[*:0]const u8, out_movie: ?*?*MovieHandle) callconv(.c) i32 {
    const out = out_movie orelse return statusCode(.null_argument);
    out.* = null;

    if (!comptime has_filesystem) return statusCode(.unsupported);

    const path_ptr = path_utf8 orelse return statusCode(.null_argument);
    const path = std.mem.span(path_ptr);
    if (path.len == 0) return statusCode(.invalid_argument);

    const movie = core.parseMovieFile(allocator, path, .{}) catch |err| return statusCode(statusFromError(err));
    out.* = handleFromMovie(movie);
    return statusCode(.ok);
}

export fn svga_movie_download(
    url_utf8: ?[*:0]const u8,
    download_options: ?*const DownloadOptions,
    out_movie: ?*?*MovieHandle,
) callconv(.c) i32 {
    const out = out_movie orelse return statusCode(.null_argument);
    out.* = null;

    if (!comptime has_network) return statusCode(.unsupported);

    const url_ptr = url_utf8 orelse return statusCode(.null_argument);
    const url = std.mem.span(url_ptr);
    if (url.len == 0) return statusCode(.invalid_argument);

    var options: core.DownloadOptions = .{};
    if (download_options) |provided| {
        if (provided.abi_version != abi_version) return statusCode(.invalid_argument);
        if (provided.max_input_bytes != 0) {
            options.max_input_bytes = provided.max_input_bytes;
        }
    }

    const movie = core.downloadMovie(allocator, url, options) catch |err| return statusCode(statusFromError(err));
    out.* = handleFromMovie(movie);
    return statusCode(.ok);
}

export fn svga_frame_index_for_time(
    frame_count: i32,
    fps: i32,
    playback_time_seconds: f64,
    out_frame_index: ?*i32,
    out_clamped_time_seconds: ?*f64,
) callconv(.c) i32 {
    const frame_index_out = out_frame_index orelse return statusCode(.null_argument);
    const clamped_time_out = out_clamped_time_seconds orelse return statusCode(.null_argument);
    frame_index_out.* = 0;
    clamped_time_out.* = 0;

    if (frame_count <= 0 or fps <= 0 or !std.math.isFinite(playback_time_seconds)) {
        return statusCode(.invalid_argument);
    }

    const duration = @as(f64, @floatFromInt(frame_count)) / @as(f64, @floatFromInt(fps));
    const clamped_time = @min(@max(playback_time_seconds, 0), duration);
    const raw_frame = flooredNonNegativeI64(clamped_time * @as(f64, @floatFromInt(fps)));
    const last_frame = @as(i64, frame_count - 1);

    frame_index_out.* = @intCast(@min(raw_frame, last_frame));
    clamped_time_out.* = clamped_time;
    return statusCode(.ok);
}

export fn svga_presentation_time_for_frame(
    frame_index: i32,
    fps: i32,
    out_presentation_time_seconds: ?*f64,
) callconv(.c) i32 {
    const time_out = out_presentation_time_seconds orelse return statusCode(.null_argument);
    time_out.* = 0;
    if (frame_index < 0 or fps <= 0) return statusCode(.invalid_argument);
    time_out.* = @as(f64, @floatFromInt(frame_index)) / @as(f64, @floatFromInt(fps));
    return statusCode(.ok);
}

export fn svga_clamp_frame_range(
    range: FrameRange,
    valid_range: FrameRange,
    out_range: ?*FrameRange,
) callconv(.c) i32 {
    const range_out = out_range orelse return statusCode(.null_argument);
    range_out.* = .{ .lower_bound = 0, .upper_bound = 0 };
    if (!isOrderedRange(range) or !isValidFrameRange(valid_range)) {
        return statusCode(.invalid_argument);
    }
    range_out.* = clampFrameRange(range, valid_range);
    return statusCode(.ok);
}

export fn svga_frame_offset_for_frame(
    frame_index: i32,
    range: FrameRange,
    reverse: u8,
    out_offset: ?*i64,
) callconv(.c) i32 {
    const offset_out = out_offset orelse return statusCode(.null_argument);
    offset_out.* = 0;
    if (!rangeContainsFrame(range, frame_index)) {
        return statusCode(.invalid_argument);
    }
    offset_out.* = frameOffsetForFrame(frame_index, range, reverse != 0);
    return statusCode(.ok);
}

export fn svga_frame_index_for_offset(
    offset: i64,
    range: FrameRange,
    reverse: u8,
    out_frame_index: ?*i32,
) callconv(.c) i32 {
    const frame_index_out = out_frame_index orelse return statusCode(.null_argument);
    frame_index_out.* = 0;
    const count = frameRangeCount(range);
    if (!isValidNonEmptyFrameRange(range) or offset < 0 or offset >= count) {
        return statusCode(.invalid_argument);
    }
    frame_index_out.* = frameIndexForOffset(offset, range, reverse != 0);
    return statusCode(.ok);
}

export fn svga_finished_frame_index(
    range: FrameRange,
    reverse: u8,
    fill_mode: i32,
    out_frame_index: ?*i32,
) callconv(.c) i32 {
    const frame_index_out = out_frame_index orelse return statusCode(.null_argument);
    frame_index_out.* = 0;
    const mode = fillModeFromCode(fill_mode) orelse return statusCode(.invalid_argument);
    if (!isValidNonEmptyFrameRange(range)) {
        return statusCode(.invalid_argument);
    }
    frame_index_out.* = finishedFrameIndex(range, reverse != 0, mode);
    return statusCode(.ok);
}

export fn svga_playback_position(
    state_ptr: ?*const PlaybackState,
    out_position: ?*PlaybackPosition,
) callconv(.c) i32 {
    const state = state_ptr orelse return statusCode(.null_argument);
    const position_out = out_position orelse return statusCode(.null_argument);
    const mode = fillModeFromCode(state.fill_mode) orelse return statusCode(.invalid_argument);

    position_out.* = .{
        .frame_index = 0,
        .completed_loop_count = 0,
        .did_finish = 0,
    };

    if (state.frame_count <= 0 or state.fps <= 0) return statusCode(.invalid_argument);
    if (!std.math.isFinite(state.elapsed_seconds) or !std.math.isFinite(state.playback_speed)) {
        return statusCode(.invalid_argument);
    }
    if (!rangeWithinFrameCount(state.playback_range, state.frame_count)) {
        return statusCode(.invalid_argument);
    }

    const effective_speed = @max(state.playback_speed, 0);
    const elapsed_frames = flooredNonNegativeI64(
        @max(state.elapsed_seconds, 0) *
            @as(f64, @floatFromInt(state.fps)) *
            effective_speed,
    );
    const start_offset = @max(state.start_frame_offset, 0);
    const total_offset = saturatingAddI64(start_offset, elapsed_frames);
    const range_frame_count = frameRangeCount(state.playback_range);
    const next_completed_loops = @divTrunc(total_offset, range_frame_count);

    if (state.loop_count > 0 and next_completed_loops >= state.loop_count) {
        position_out.* = .{
            .frame_index = finishedFrameIndex(state.playback_range, state.reverse != 0, mode),
            .completed_loop_count = state.loop_count,
            .did_finish = 1,
        };
        return statusCode(.ok);
    }

    const intra_loop_offset = @mod(total_offset, range_frame_count);
    position_out.* = .{
        .frame_index = frameIndexForOffset(intra_loop_offset, state.playback_range, state.reverse != 0),
        .completed_loop_count = next_completed_loops,
        .did_finish = 0,
    };
    return statusCode(.ok);
}

export fn svga_make_movie_layout(
    movie_size: Size2D,
    viewport_size: Size2D,
    content_mode: i32,
    out_layout: ?*MovieLayout,
) callconv(.c) i32 {
    const layout_out = out_layout orelse return statusCode(.null_argument);
    layout_out.* = zeroMovieLayout();
    const mode = contentModeFromCode(content_mode) orelse return statusCode(.invalid_argument);
    if (!isPositiveFiniteSize(movie_size) or !isPositiveFiniteSize(viewport_size)) {
        return statusCode(.invalid_argument);
    }
    layout_out.* = movieLayout(movie_size, viewport_size, mode);
    return statusCode(.ok);
}

export fn svga_aspect_fit_rect(
    content_size: Size2D,
    bounds: Rect2D,
    out_rect: ?*Rect2D,
) callconv(.c) i32 {
    const rect_out = out_rect orelse return statusCode(.null_argument);
    rect_out.* = zeroRect2D();
    if (!isPositiveFiniteSize(content_size) or !isFiniteRectWithPositiveSize(bounds)) {
        return statusCode(.invalid_argument);
    }
    rect_out.* = aspectFitRect(content_size, bounds);
    return statusCode(.ok);
}

fn versionSlice(version_utf8: ?[*:0]const u8) []const u8 {
    const ptr = version_utf8 orelse return "";
    var len: usize = 0;
    while (len <= model.max_version_bytes) : (len += 1) {
        if (ptr[len] == 0) return ptr[0..len];
    }

    return ptr[0 .. model.max_version_bytes + 1];
}

fn statusCode(status: Status) i32 {
    return @intFromEnum(status);
}

fn statusFromError(err: anyerror) Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidVersion,
        error.InvalidDimensions,
        error.InvalidFps,
        error.InvalidFrames,
        error.InvalidMovieCounts,
        error.InvalidSpriteKey,
        error.InvalidFrameCount,
        error.InvalidUrl,
        error.UnexpectedCharacter,
        error.InvalidFormat,
        error.InvalidPort,
        error.UriMissingHost,
        error.UriHostTooLong,
        error.StreamTooLong,
        => .invalid_argument,
        error.UnsupportedContainer,
        error.UnsupportedZip,
        error.UnsupportedZipMethod,
        error.UnsupportedNetwork,
        error.UnsupportedUriScheme,
        error.UnsupportedCompressionMethod,
        error.HttpContentEncodingUnsupported,
        => .unsupported,
        error.InvalidData,
        error.InvalidWireType,
        error.TruncatedInput,
        error.InvalidZlibStream,
        error.InvalidDeflateStream,
        error.MissingMovieParams,
        error.MissingMovieSpec,
        error.InvalidJson,
        => .parse_error,
        error.FileNotFound,
        error.AccessDenied,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.SymLinkLoop,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.SystemResources,
        error.NoDevice,
        error.DeviceBusy,
        error.FileTooBig,
        error.IsDir,
        error.NotDir,
        error.InputOutput,
        error.HttpStatusError,
        error.ConnectionRefused,
        error.NetworkUnreachable,
        error.ConnectionTimedOut,
        error.ConnectionResetByPeer,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.UnknownHostName,
        error.HostLacksNetworkAddresses,
        error.UnexpectedConnectFailure,
        error.TlsInitializationFailed,
        error.CertificateBundleLoadFailure,
        error.HttpHeadersInvalid,
        error.TooManyHttpRedirects,
        error.RedirectRequiresResend,
        error.HttpRedirectLocationMissing,
        error.HttpRedirectLocationOversize,
        error.HttpRedirectLocationInvalid,
        error.HttpChunkInvalid,
        error.HttpChunkTruncated,
        error.HttpHeadersOversize,
        error.HttpRequestTruncated,
        error.HttpConnectionClosing,
        error.ReadFailed,
        error.WriteFailed,
        error.Unexpected,
        => .io_error,
        else => .internal_error,
    };
}

fn handleFromMovie(movie: *model.Movie) *MovieHandle {
    return @ptrCast(movie);
}

fn movieFromHandle(handle: *MovieHandle) *model.Movie {
    return @as(*model.Movie, @ptrCast(@alignCast(handle)));
}

fn movieFromConstHandle(handle: *const MovieHandle) *const model.Movie {
    return @as(*const model.Movie, @ptrCast(@alignCast(handle)));
}

fn emptyAssetInfo() AssetInfo {
    return .{
        .key_utf8 = null,
        .kind = @intFromEnum(model.AssetKind.unknown),
        .bytes = null,
        .byte_count = 0,
        .filename_utf8 = null,
    };
}

fn assetInfo(asset: *const model.Asset) AssetInfo {
    return .{
        .key_utf8 = asset.key.ptr,
        .kind = @intFromEnum(asset.kind),
        .bytes = if (asset.bytes.len == 0) null else asset.bytes.ptr,
        .byte_count = asset.bytes.len,
        .filename_utf8 = asset.filename.ptr,
    };
}

fn contentModeFromCode(code: i32) ?ContentMode {
    return switch (code) {
        @intFromEnum(ContentMode.fit) => .fit,
        @intFromEnum(ContentMode.fill) => .fill,
        @intFromEnum(ContentMode.scale_to_fill) => .scale_to_fill,
        @intFromEnum(ContentMode.top) => .top,
        @intFromEnum(ContentMode.bottom) => .bottom,
        @intFromEnum(ContentMode.left) => .left,
        @intFromEnum(ContentMode.right) => .right,
        else => null,
    };
}

fn fillModeFromCode(code: i32) ?FillMode {
    return switch (code) {
        @intFromEnum(FillMode.current) => .current,
        @intFromEnum(FillMode.backward) => .backward,
        @intFromEnum(FillMode.forward) => .forward,
        else => null,
    };
}

fn frameRangeCount(range: FrameRange) i64 {
    return @max(@as(i64, range.upper_bound) - @as(i64, range.lower_bound), 0);
}

fn isOrderedRange(range: FrameRange) bool {
    return range.lower_bound <= range.upper_bound;
}

fn isValidFrameRange(range: FrameRange) bool {
    return range.lower_bound >= 0 and isOrderedRange(range);
}

fn isValidNonEmptyFrameRange(range: FrameRange) bool {
    return isValidFrameRange(range) and frameRangeCount(range) > 0;
}

fn rangeWithinFrameCount(range: FrameRange, frame_count: i32) bool {
    return range.lower_bound >= 0 and
        range.upper_bound <= frame_count and
        frameRangeCount(range) > 0;
}

fn rangeContainsFrame(range: FrameRange, frame_index: i32) bool {
    return isValidNonEmptyFrameRange(range) and
        frame_index >= range.lower_bound and
        frame_index < range.upper_bound;
}

fn clampFrameRange(range: FrameRange, valid_range: FrameRange) FrameRange {
    return .{
        .lower_bound = clampI32(range.lower_bound, valid_range.lower_bound, valid_range.upper_bound),
        .upper_bound = clampI32(range.upper_bound, valid_range.lower_bound, valid_range.upper_bound),
    };
}

fn clampI32(value: i32, lower_bound: i32, upper_bound: i32) i32 {
    return @min(@max(value, lower_bound), upper_bound);
}

fn frameOffsetForFrame(frame_index: i32, range: FrameRange, reverse: bool) i64 {
    if (frameRangeCount(range) <= 0) return 0;
    if (reverse) {
        return @max(@as(i64, range.upper_bound) - 1 - @as(i64, frame_index), 0);
    }
    return @max(@as(i64, frame_index) - @as(i64, range.lower_bound), 0);
}

fn frameIndexForOffset(offset: i64, range: FrameRange, reverse: bool) i32 {
    const count = frameRangeCount(range);
    if (count <= 0) return 0;

    const clamped_offset = @min(@max(offset, 0), count - 1);
    if (reverse) {
        return @intCast(@as(i64, range.upper_bound) - 1 - clamped_offset);
    }
    return @intCast(@as(i64, range.lower_bound) + clamped_offset);
}

fn finishedFrameIndex(range: FrameRange, reverse: bool, fill_mode: FillMode) i32 {
    if (frameRangeCount(range) <= 0) return 0;
    return switch (fill_mode) {
        .current => if (reverse) range.lower_bound else range.upper_bound - 1,
        .backward => range.lower_bound,
        .forward => range.upper_bound - 1,
    };
}

fn flooredNonNegativeI64(value: f64) i64 {
    if (!std.math.isFinite(value) or value <= 0) return 0;

    const floored = @floor(value);
    const max_i64_float = @as(f64, @floatFromInt(std.math.maxInt(i64)));
    if (floored >= max_i64_float) return std.math.maxInt(i64);
    return @intFromFloat(floored);
}

fn saturatingAddI64(left: i64, right: i64) i64 {
    if (right > std.math.maxInt(i64) - left) return std.math.maxInt(i64);
    return left + right;
}

fn movieLayout(movie_size: Size2D, viewport_size: Size2D, content_mode: ContentMode) MovieLayout {
    if (!(movie_size.width > 0) or
        !(movie_size.height > 0) or
        !(viewport_size.width > 0) or
        !(viewport_size.height > 0))
    {
        return .{
            .scale_x = 1,
            .scale_y = 1,
            .origin = .{ .x = 0, .y = 0 },
        };
    }

    const scale_x = viewport_size.width / movie_size.width;
    const scale_y = viewport_size.height / movie_size.height;
    if (content_mode == .scale_to_fill) {
        return .{
            .scale_x = scale_x,
            .scale_y = scale_y,
            .origin = .{ .x = 0, .y = 0 },
        };
    }

    const scale = switch (content_mode) {
        .fill => @max(scale_x, scale_y),
        .left, .right => scale_y,
        .top, .bottom => scale_x,
        .fit, .scale_to_fill => @min(scale_x, scale_y),
    };
    const rendered_width = movie_size.width * scale;
    const rendered_height = movie_size.height * scale;
    const origin = switch (content_mode) {
        .top => Point2D{ .x = (viewport_size.width - rendered_width) / 2, .y = 0 },
        .bottom => Point2D{ .x = (viewport_size.width - rendered_width) / 2, .y = viewport_size.height - rendered_height },
        .left => Point2D{ .x = 0, .y = (viewport_size.height - rendered_height) / 2 },
        .right => Point2D{ .x = viewport_size.width - rendered_width, .y = (viewport_size.height - rendered_height) / 2 },
        .fit, .fill, .scale_to_fill => Point2D{
            .x = (viewport_size.width - rendered_width) / 2,
            .y = (viewport_size.height - rendered_height) / 2,
        },
    };

    return .{
        .scale_x = scale,
        .scale_y = scale,
        .origin = origin,
    };
}

fn aspectFitRect(content_size: Size2D, bounds: Rect2D) Rect2D {
    const scale = @min(bounds.width / content_size.width, bounds.height / content_size.height);
    const width = content_size.width * scale;
    const height = content_size.height * scale;
    return .{
        .x = bounds.x + bounds.width / 2 - width / 2,
        .y = bounds.y + bounds.height / 2 - height / 2,
        .width = width,
        .height = height,
    };
}

fn isPositiveFiniteSize(size: Size2D) bool {
    return std.math.isFinite(size.width) and
        std.math.isFinite(size.height) and
        size.width > 0 and
        size.height > 0;
}

fn isFiniteRectWithPositiveSize(rect: Rect2D) bool {
    return std.math.isFinite(rect.x) and
        std.math.isFinite(rect.y) and
        std.math.isFinite(rect.width) and
        std.math.isFinite(rect.height) and
        rect.width > 0 and
        rect.height > 0;
}

fn zeroMovieLayout() MovieLayout {
    return .{
        .scale_x = 0,
        .scale_y = 0,
        .origin = .{ .x = 0, .y = 0 },
    };
}

fn zeroRect2D() Rect2D {
    return .{
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 0,
    };
}

fn renderCapabilitiesForMovie(movie: *const model.Movie) RenderCapabilitiesInfo {
    var required_features: u32 = 0;
    for (movie.render_items) |item| {
        required_features |= renderFeaturesForItem(item);
    }
    if (movie.render_commands.len > 0) {
        required_features |= @intFromEnum(model.RenderFeature.bitmap_quads);
    }

    return renderCapabilities(required_features, movie.render_commands.len);
}

fn renderCapabilitiesForItems(items: []const RenderItemInfo, command_count: usize) RenderCapabilitiesInfo {
    var required_features: u32 = 0;
    for (items) |item| {
        required_features |= renderFeaturesForItem(item);
    }
    if (command_count > 0) {
        required_features |= @intFromEnum(model.RenderFeature.bitmap_quads);
    }

    return renderCapabilities(required_features, command_count);
}

fn renderFeaturesForItem(item: RenderItemInfo) u32 {
    var required_features: u32 = @intFromEnum(model.RenderFeature.bitmap_quads);
    if (item.has_clip_path != 0) {
        required_features |= @intFromEnum(model.RenderFeature.clip_paths);
    }
    if (item.is_matte != 0 or item.has_matte != 0) {
        required_features |= @intFromEnum(model.RenderFeature.mattes);
    }
    if (item.has_shapes != 0) {
        required_features |= @intFromEnum(model.RenderFeature.vector_shapes);
    }
    return required_features;
}

fn renderCapabilities(required_features: u32, command_count: usize) RenderCapabilitiesInfo {
    const unsupported = required_features & ~@as(u32, @intFromEnum(model.RenderFeature.bitmap_quads));
    return .{
        .abi_version = abi_version,
        .required_features = required_features,
        .bitmap_command_count = @intCast(@min(command_count, @as(usize, std.math.maxInt(u32)))),
        .direct_bitmap_compatible = if (unsupported == 0) 1 else 0,
    };
}

test "C API creates and reads a movie handle" {
    var out_movie: ?*MovieHandle = null;
    const desc = MovieDesc{
        .abi_version = abi_version,
        .view_box_width = 100,
        .view_box_height = 50,
        .fps = 20,
        .frames = 40,
        .image_count = 3,
        .sprite_count = 2,
        .audio_count = 1,
        .version_utf8 = "2.0.0",
    };

    try std.testing.expectEqual(statusCode(.ok), svga_movie_create(&out_movie, &desc));
    defer svga_movie_destroy(out_movie);

    var info: MovieInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_info(out_movie, &info));
    try std.testing.expectEqual(abi_version, info.abi_version);
    try std.testing.expectEqual(@as(f32, 100), info.view_box_width);
    try std.testing.expectEqual(@as(f32, 50), info.view_box_height);
    try std.testing.expectEqual(@as(i32, 20), info.fps);
    try std.testing.expectEqual(@as(i32, 40), info.frames);
    try std.testing.expectEqual(@as(u32, 3), info.image_count);
    try std.testing.expectEqual(@as(u32, 2), info.sprite_count);
    try std.testing.expectEqual(@as(u32, 1), info.audio_count);
    try std.testing.expectEqualStrings("2.0.0", std.mem.span(info.version_utf8.?));
}

test "C API exposes parsed assets, audio, and shapes" {
    const proto = [_]u8{
        0x0a, 0x05, '2',  '.',  '1',  '.',  '0',
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c, 0x1a, 0x0d, 0x0a, 0x04, 'h',
        'e',  'r',  'o',  0x12, 0x05, 'h',  'e',
        'r',  'o',  '0',  0x22, 0x18, 0x0a, 0x04,
        'h',  'e',  'r',  'o',  0x12, 0x10, 0x0d,
        0x00, 0x00, 0x80, 0x3f, 0x2a, 0x09, 0x08,
        0x01, 0x1a, 0x05, 0x0d, 0x00, 0x00, 0x20,
        0x41, 0x2a, 0x0a, 0x0a, 0x02, 's',  'e',
        0x10, 0x01, 0x18, 0x02, 0x20, 0x03,
    };

    const zip = try storedZip(std.testing.allocator, "movie.binary", &proto);
    defer std.testing.allocator.free(zip);

    var out_movie: ?*MovieHandle = null;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_parse(zip.ptr, zip.len, &out_movie));
    defer svga_movie_destroy(out_movie);

    var asset_count: u32 = 0;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_asset_count(out_movie, &asset_count));
    try std.testing.expectEqual(@as(u32, 1), asset_count);

    var asset_info: AssetInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_asset_info(out_movie, 0, &asset_info));
    try std.testing.expectEqualStrings("hero", std.mem.span(asset_info.key_utf8.?));
    try std.testing.expectEqual(@intFromEnum(model.AssetKind.filename), asset_info.kind);
    try std.testing.expectEqualStrings("hero0", std.mem.span(asset_info.filename_utf8.?));

    var audio_info: AudioInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_audio_info(out_movie, 0, &audio_info));
    try std.testing.expectEqualStrings("se", std.mem.span(audio_info.audio_key_utf8.?));
    try std.testing.expectEqual(@as(i32, 1), audio_info.start_frame);

    var sprite_table: ?[*]const SpriteInfo = null;
    var sprite_table_count: usize = 0;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_sprite_table(out_movie, &sprite_table, &sprite_table_count));
    try std.testing.expectEqual(@as(usize, 1), sprite_table_count);
    try std.testing.expect(sprite_table != null);
    try std.testing.expectEqualStrings("hero", std.mem.span(sprite_table.?[0].image_key_utf8.?));

    var frame_table: ?[*]const FrameInfo = null;
    var frame_table_count: usize = 0;
    var sprite_frame_ranges: ?[*]const RenderRangeInfo = null;
    var sprite_frame_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_frame_table(
            out_movie,
            &frame_table,
            &frame_table_count,
            &sprite_frame_ranges,
            &sprite_frame_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), frame_table_count);
    try std.testing.expect(frame_table != null);
    try std.testing.expectEqual(@as(usize, 1), sprite_frame_range_count);
    try std.testing.expect(sprite_frame_ranges != null);
    try std.testing.expectEqual(@as(usize, 0), sprite_frame_ranges.?[0].start);
    try std.testing.expectEqual(@as(usize, 1), sprite_frame_ranges.?[0].count);

    var shape_info: ShapeInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_shape_info(out_movie, 0, 0, 0, &shape_info));
    try std.testing.expectEqual(@as(i32, @intFromEnum(model.ShapeType.rect)), shape_info.shape_type);
    try std.testing.expectEqual(@as(f32, 10), shape_info.rect.x);

    var shape_table: ?[*]const ShapeInfo = null;
    var shape_table_count: usize = 0;
    var frame_shape_ranges: ?[*]const RenderRangeInfo = null;
    var frame_shape_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_shape_table(
            out_movie,
            &shape_table,
            &shape_table_count,
            &frame_shape_ranges,
            &frame_shape_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), shape_table_count);
    try std.testing.expect(shape_table != null);
    try std.testing.expectEqual(@as(usize, 1), frame_shape_range_count);
    try std.testing.expect(frame_shape_ranges != null);
    try std.testing.expectEqual(@as(usize, 0), frame_shape_ranges.?[0].start);
    try std.testing.expectEqual(@as(usize, 1), frame_shape_ranges.?[0].count);

    var render_items: ?[*]const RenderItemInfo = null;
    var render_item_count: u32 = 0;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_render_items(out_movie, 0, &render_items, &render_item_count));
    try std.testing.expectEqual(@as(u32, 0), render_item_count);
    try std.testing.expect(render_items == null);

    var command_table: ?[*]const RenderCommandInfo = null;
    var command_count: usize = 999;
    var command_ranges: ?[*]const RenderRangeInfo = null;
    var command_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_render_command_table(
            out_movie,
            &command_table,
            &command_count,
            &command_ranges,
            &command_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), command_count);
    try std.testing.expect(command_table == null);
    try std.testing.expectEqual(@as(usize, 60), command_range_count);
    try std.testing.expect(command_ranges != null);

    var item_table: ?[*]const RenderItemInfo = null;
    var item_count: usize = 999;
    var item_ranges: ?[*]const RenderRangeInfo = null;
    var item_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_render_item_table(
            out_movie,
            &item_table,
            &item_count,
            &item_ranges,
            &item_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), item_count);
    try std.testing.expect(item_table == null);
    try std.testing.expectEqual(@as(usize, 60), item_range_count);
    try std.testing.expect(item_ranges != null);

    var visual_frames: ?[*]const u32 = null;
    var visual_frame_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_visual_frame_table(out_movie, &visual_frames, &visual_frame_count),
    );
    try std.testing.expectEqual(@as(usize, 60), visual_frame_count);
    try std.testing.expect(visual_frames != null);
    try std.testing.expectEqual(@as(u32, 0), visual_frames.?[0]);
    try std.testing.expectEqual(@as(u32, 0), visual_frames.?[59]);
}

test "C API resolves filename assets through portable lookup policy" {
    var movie = try model.Movie.init(std.testing.allocator, .{
        .version = "2.0.0",
        .view_box_width = 100,
        .view_box_height = 100,
        .fps = 20,
        .frames = 1,
        .assets = &.{
            .{
                .key = "avatar",
                .kind = .filename,
                .filename = "avatar_image",
            },
            .{
                .key = "avatar_image.png",
                .kind = .image_bytes,
                .bytes = "png-bytes",
            },
            .{
                .key = "sound",
                .kind = .filename,
                .filename = "sound.mp3",
            },
            .{
                .key = "sound.mp3",
                .kind = .audio_bytes,
                .bytes = "mp3-bytes",
            },
        },
    });
    defer movie.deinit(std.testing.allocator);

    const handle = handleFromMovie(&movie);

    var exact: AssetInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_find_asset(handle, "avatar", &exact));
    try std.testing.expectEqual(@intFromEnum(model.AssetKind.filename), exact.kind);
    try std.testing.expectEqualStrings("avatar_image", std.mem.span(exact.filename_utf8.?));

    var image: AssetInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_resolve_image_asset(handle, "avatar", &image));
    try std.testing.expectEqualStrings("avatar_image.png", std.mem.span(image.key_utf8.?));
    try std.testing.expectEqualStrings("png-bytes", image.bytes.?[0..image.byte_count]);

    var audio: AssetInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_resolve_audio_asset(handle, "sound", &audio));
    try std.testing.expectEqualStrings("sound.mp3", std.mem.span(audio.key_utf8.?));
    try std.testing.expectEqualStrings("mp3-bytes", audio.bytes.?[0..audio.byte_count]);

    var missing: AssetInfo = undefined;
    try std.testing.expectEqual(statusCode(.invalid_argument), svga_movie_find_asset(handle, "missing", &missing));
    try std.testing.expectEqual(@as(?[*:0]const u8, null), missing.key_utf8);
}

test "C API exposes timeline scalar helpers" {
    var frame_index: i32 = -1;
    var clamped_time: f64 = -1;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_frame_index_for_time(60, 30, -0.25, &frame_index, &clamped_time),
    );
    try std.testing.expectEqual(@as(i32, 0), frame_index);
    try std.testing.expectEqual(@as(f64, 0), clamped_time);

    try std.testing.expectEqual(
        statusCode(.ok),
        svga_frame_index_for_time(60, 30, 2.0, &frame_index, &clamped_time),
    );
    try std.testing.expectEqual(@as(i32, 59), frame_index);
    try std.testing.expectEqual(@as(f64, 2), clamped_time);

    var presentation_time: f64 = -1;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_presentation_time_for_frame(15, 30, &presentation_time),
    );
    try std.testing.expectEqual(@as(f64, 0.5), presentation_time);

    var clamped_range: FrameRange = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_clamp_frame_range(
            .{ .lower_bound = -5, .upper_bound = 8 },
            .{ .lower_bound = 2, .upper_bound = 10 },
            &clamped_range,
        ),
    );
    try std.testing.expectEqual(@as(i32, 2), clamped_range.lower_bound);
    try std.testing.expectEqual(@as(i32, 8), clamped_range.upper_bound);

    try std.testing.expectEqual(
        statusCode(.ok),
        svga_clamp_frame_range(
            .{ .lower_bound = 20, .upper_bound = 25 },
            .{ .lower_bound = 2, .upper_bound = 10 },
            &clamped_range,
        ),
    );
    try std.testing.expectEqual(@as(i32, 10), clamped_range.lower_bound);
    try std.testing.expectEqual(@as(i32, 10), clamped_range.upper_bound);

    var offset: i64 = -1;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_frame_offset_for_frame(8, .{ .lower_bound = 4, .upper_bound = 10 }, 1, &offset),
    );
    try std.testing.expectEqual(@as(i64, 1), offset);

    try std.testing.expectEqual(
        statusCode(.ok),
        svga_frame_index_for_offset(2, .{ .lower_bound = 4, .upper_bound = 10 }, 1, &frame_index),
    );
    try std.testing.expectEqual(@as(i32, 7), frame_index);
}

test "C API rejects invalid scalar helper arguments and resets outputs" {
    var range: FrameRange = .{ .lower_bound = 123, .upper_bound = 456 };
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_clamp_frame_range(
            .{ .lower_bound = 5, .upper_bound = 1 },
            .{ .lower_bound = 0, .upper_bound = 10 },
            &range,
        ),
    );
    try std.testing.expectEqual(@as(i32, 0), range.lower_bound);
    try std.testing.expectEqual(@as(i32, 0), range.upper_bound);

    var offset: i64 = 99;
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_frame_offset_for_frame(10, .{ .lower_bound = 4, .upper_bound = 10 }, 0, &offset),
    );
    try std.testing.expectEqual(@as(i64, 0), offset);

    var frame_index: i32 = 99;
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_frame_index_for_offset(6, .{ .lower_bound = 4, .upper_bound = 10 }, 0, &frame_index),
    );
    try std.testing.expectEqual(@as(i32, 0), frame_index);

    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_finished_frame_index(.{ .lower_bound = 4, .upper_bound = 4 }, 0, @intFromEnum(FillMode.current), &frame_index),
    );
    try std.testing.expectEqual(@as(i32, 0), frame_index);

    var layout: MovieLayout = .{
        .scale_x = 3,
        .scale_y = 4,
        .origin = .{ .x = 5, .y = 6 },
    };
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_make_movie_layout(
            .{ .width = 0, .height = 50 },
            .{ .width = 300, .height = 300 },
            @intFromEnum(ContentMode.fit),
            &layout,
        ),
    );
    try std.testing.expectEqual(@as(f64, 0), layout.scale_x);
    try std.testing.expectEqual(@as(f64, 0), layout.scale_y);
    try std.testing.expectEqual(@as(f64, 0), layout.origin.x);
    try std.testing.expectEqual(@as(f64, 0), layout.origin.y);

    var rect: Rect2D = .{ .x = 1, .y = 2, .width = 3, .height = 4 };
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_aspect_fit_rect(
            .{ .width = 200, .height = 100 },
            .{ .x = 0, .y = 0, .width = -1, .height = 50 },
            &rect,
        ),
    );
    try std.testing.expectEqual(@as(f64, 0), rect.x);
    try std.testing.expectEqual(@as(f64, 0), rect.y);
    try std.testing.expectEqual(@as(f64, 0), rect.width);
    try std.testing.expectEqual(@as(f64, 0), rect.height);
}

test "C API computes playback position and layout geometry" {
    var position: PlaybackPosition = undefined;
    const state = PlaybackState{
        .frame_count = 20,
        .fps = 10,
        .playback_range = .{ .lower_bound = 4, .upper_bound = 9 },
        .elapsed_seconds = 0.2,
        .playback_speed = 1,
        .start_frame_offset = 4,
        .loop_count = 2,
        .reverse = 1,
        .fill_mode = @intFromEnum(FillMode.current),
    };
    try std.testing.expectEqual(statusCode(.ok), svga_playback_position(&state, &position));
    try std.testing.expectEqual(@as(i32, 7), position.frame_index);
    try std.testing.expectEqual(@as(i64, 1), position.completed_loop_count);
    try std.testing.expectEqual(@as(u8, 0), position.did_finish);

    var finished = state;
    finished.elapsed_seconds = 1;
    try std.testing.expectEqual(statusCode(.ok), svga_playback_position(&finished, &position));
    try std.testing.expectEqual(@as(i32, 4), position.frame_index);
    try std.testing.expectEqual(@as(i64, 2), position.completed_loop_count);
    try std.testing.expectEqual(@as(u8, 1), position.did_finish);

    var layout: MovieLayout = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_make_movie_layout(
            .{ .width = 100, .height = 50 },
            .{ .width = 300, .height = 300 },
            @intFromEnum(ContentMode.fit),
            &layout,
        ),
    );
    try std.testing.expectEqual(@as(f64, 3), layout.scale_x);
    try std.testing.expectEqual(@as(f64, 3), layout.scale_y);
    try std.testing.expectEqual(@as(f64, 0), layout.origin.x);
    try std.testing.expectEqual(@as(f64, 75), layout.origin.y);

    var rect: Rect2D = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_aspect_fit_rect(
            .{ .width = 200, .height = 100 },
            .{ .x = 10, .y = 20, .width = 100, .height = 100 },
            &rect,
        ),
    );
    try std.testing.expectEqual(@as(f64, 10), rect.x);
    try std.testing.expectEqual(@as(f64, 45), rect.y);
    try std.testing.expectEqual(@as(f64, 100), rect.width);
    try std.testing.expectEqual(@as(f64, 50), rect.height);
}

test "C API exposes parsed path commands" {
    var movie = try model.Movie.init(std.testing.allocator, .{
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
                        .frame = .{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .shape_count = 1,
                            .first_shape_type = @intFromEnum(model.ShapeType.shape),
                            .visible = 1,
                        },
                        .clip_path = "M0 0 L10 0 Z",
                        .shapes = &.{
                            .{
                                .shape_type = .shape,
                                .path_data = "M1 2 C3 4 5 6 7 8",
                            },
                        },
                    },
                },
            },
        },
    });
    defer movie.deinit(std.testing.allocator);

    const handle = handleFromMovie(&movie);
    var clip_commands: ?[*]const PathCommandInfo = null;
    var clip_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_frame_clip_path_commands(handle, 0, 0, &clip_commands, &clip_count),
    );
    try std.testing.expectEqual(@as(usize, 3), clip_count);
    try std.testing.expect(clip_commands != null);
    try std.testing.expectEqual(@as(i32, @intFromEnum(model.PathCommandType.move)), clip_commands.?[0].command_type);
    try std.testing.expectEqual(@as(i32, @intFromEnum(model.PathCommandType.close)), clip_commands.?[2].command_type);

    var clip_table: ?[*]const PathCommandInfo = null;
    var clip_table_count: usize = 0;
    var clip_ranges: ?[*]const RenderRangeInfo = null;
    var clip_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_frame_clip_path_command_table(
            handle,
            &clip_table,
            &clip_table_count,
            &clip_ranges,
            &clip_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 3), clip_table_count);
    try std.testing.expect(clip_table != null);
    try std.testing.expectEqual(@as(usize, 1), clip_range_count);
    try std.testing.expect(clip_ranges != null);
    try std.testing.expectEqual(@as(usize, 0), clip_ranges.?[0].start);
    try std.testing.expectEqual(@as(usize, 3), clip_ranges.?[0].count);

    var shape_commands: ?[*]const PathCommandInfo = null;
    var shape_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_shape_path_commands(handle, 0, 0, 0, &shape_commands, &shape_count),
    );
    try std.testing.expectEqual(@as(usize, 2), shape_count);
    try std.testing.expect(shape_commands != null);
    try std.testing.expectEqual(@as(i32, @intFromEnum(model.PathCommandType.cubic)), shape_commands.?[1].command_type);
    try std.testing.expectEqual(@as(f32, 7), shape_commands.?[1].p2_x);
    try std.testing.expectEqual(@as(f32, 8), shape_commands.?[1].p2_y);

    var shape_table: ?[*]const PathCommandInfo = null;
    var shape_table_count: usize = 0;
    var shape_ranges: ?[*]const RenderRangeInfo = null;
    var shape_range_count: usize = 0;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_shape_path_command_table(
            handle,
            &shape_table,
            &shape_table_count,
            &shape_ranges,
            &shape_range_count,
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), shape_table_count);
    try std.testing.expect(shape_table != null);
    try std.testing.expectEqual(@as(usize, 1), shape_range_count);
    try std.testing.expect(shape_ranges != null);
    try std.testing.expectEqual(@as(usize, 0), shape_ranges.?[0].start);
    try std.testing.expectEqual(@as(usize, 2), shape_ranges.?[0].count);
}

test "C API exposes render capabilities for bitmap and fallback frames" {
    var movie = try model.Movie.init(std.testing.allocator, .{
        .version = "2.0.0",
        .view_box_width = 100,
        .view_box_height = 100,
        .fps = 20,
        .frames = 2,
        .sprite_count = 2,
        .sprites = &.{
            .{
                .image_key = "bitmap",
                .frames = &.{
                    .{
                        .frame = .{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
                            .visible = 1,
                        },
                    },
                    .{
                        .frame = .{
                            .alpha = 1,
                            .layout = .{ .x = 1, .y = 1, .width = 20, .height = 20 },
                            .visible = 1,
                        },
                    },
                },
            },
            .{
                .image_key = "vector",
                .frames = &.{
                    .{
                        .frame = .{
                            .alpha = 0,
                            .layout = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
                            .visible = 0,
                        },
                    },
                    .{
                        .frame = .{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
                            .shape_count = 1,
                            .first_shape_type = @intFromEnum(model.ShapeType.rect),
                            .visible = 1,
                        },
                        .shapes = &.{
                            .{
                                .shape_type = .rect,
                                .rect = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
                            },
                        },
                    },
                },
            },
        },
    });
    defer movie.deinit(std.testing.allocator);

    const handle = handleFromMovie(&movie);

    var frame_zero: RenderCapabilitiesInfo = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_frame_render_capabilities(handle, 0, &frame_zero),
    );
    try std.testing.expectEqual(abi_version, frame_zero.abi_version);
    try std.testing.expectEqual(@as(u32, @intFromEnum(model.RenderFeature.bitmap_quads)), frame_zero.required_features);
    try std.testing.expectEqual(@as(u32, 1), frame_zero.bitmap_command_count);
    try std.testing.expectEqual(@as(u8, 1), frame_zero.direct_bitmap_compatible);

    var frame_one: RenderCapabilitiesInfo = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_frame_render_capabilities(handle, 1, &frame_one),
    );
    try std.testing.expect(frame_one.required_features & @intFromEnum(model.RenderFeature.bitmap_quads) != 0);
    try std.testing.expect(frame_one.required_features & @intFromEnum(model.RenderFeature.vector_shapes) != 0);
    try std.testing.expectEqual(@as(u32, 2), frame_one.bitmap_command_count);
    try std.testing.expectEqual(@as(u8, 0), frame_one.direct_bitmap_compatible);

    var movie_caps: RenderCapabilitiesInfo = undefined;
    try std.testing.expectEqual(
        statusCode(.ok),
        svga_movie_get_render_capabilities(handle, &movie_caps),
    );
    try std.testing.expect(movie_caps.required_features & @intFromEnum(model.RenderFeature.vector_shapes) != 0);
    try std.testing.expectEqual(@as(u32, 3), movie_caps.bitmap_command_count);
    try std.testing.expectEqual(@as(u8, 0), movie_caps.direct_bitmap_compatible);
}

test "C API movie queries are safe for concurrent read-only access" {
    if (builtin.single_threaded) return error.SkipZigTest;

    var movie = try model.Movie.init(std.testing.allocator, .{
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
                        .frame = model.computeFrame(.{
                            .alpha = 1,
                            .layout = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(model.ShapeType.shape),
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
                        .frame = model.computeFrame(.{
                            .alpha = 0.75,
                            .layout = .{ .x = 1, .y = 2, .width = 10, .height = 10 },
                            .first_shape_type = @intFromEnum(model.ShapeType.keep),
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
    defer movie.deinit(std.testing.allocator);

    const handle = handleFromMovie(&movie);
    const worker_count = 4;
    var threads: [worker_count]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |*thread| {
            thread.join();
        }
    }

    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, queryCAbiMovieReadOnlyRepeatedly, .{handle});
        spawned += 1;
    }
    for (&threads) |*thread| {
        thread.join();
    }
}

test "C API parses and destroys independent movies concurrently" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const proto = [_]u8{
        0x0a, 0x05, '2',  '.',  '1',  '.',  '0',
        0x12, 0x0e, 0x0d, 0x00, 0x00, 0xa0, 0x43,
        0x15, 0x00, 0x00, 0x70, 0x43, 0x18, 0x1e,
        0x20, 0x3c,
    };
    const zip = try storedZip(std.testing.allocator, "movie.binary", &proto);
    defer std.testing.allocator.free(zip);

    const worker_count = 4;
    var threads: [worker_count]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |*thread| {
            thread.join();
        }
    }

    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, parseCAbiMovieRepeatedly, .{zip});
        spawned += 1;
    }
    for (&threads) |*thread| {
        thread.join();
    }
}

fn queryCAbiMovieReadOnlyRepeatedly(handle: *const MovieHandle) void {
    var iteration: usize = 0;
    while (iteration < 128) : (iteration += 1) {
        const frame_index: u32 = @intCast(iteration % 2);

        var info: MovieInfo = undefined;
        expectWorkerStatus(svga_movie_get_info(handle, &info), .ok);
        expectWorker(info.frames == 2);
        expectWorker(std.mem.eql(u8, std.mem.span(info.version_utf8.?), "2.0.0"));

        var sprite_info: SpriteInfo = undefined;
        expectWorkerStatus(svga_movie_get_sprite_info(handle, 0, &sprite_info), .ok);
        expectWorker(sprite_info.frame_count == 2);
        expectWorker(std.mem.eql(u8, std.mem.span(sprite_info.image_key_utf8.?), "hero"));

        var render_commands: ?[*]const RenderCommandInfo = null;
        var render_command_count: u32 = 0;
        expectWorkerStatus(
            svga_movie_get_render_commands(handle, frame_index, &render_commands, &render_command_count),
            .ok,
        );
        expectWorker(render_command_count == 1);
        expectWorker(render_commands != null);
        expectWorker(render_commands.?[0].sprite_index == 0);

        var render_items: ?[*]const RenderItemInfo = null;
        var render_item_count: u32 = 0;
        expectWorkerStatus(
            svga_movie_get_render_items(handle, frame_index, &render_items, &render_item_count),
            .ok,
        );
        expectWorker(render_item_count == 1);
        expectWorker(render_items != null);
        expectWorker(render_items.?[0].has_shapes == 1);

        var asset_info: AssetInfo = undefined;
        expectWorkerStatus(svga_movie_resolve_image_asset(handle, "hero", &asset_info), .ok);
        expectWorker(asset_info.bytes != null);
        expectWorker(std.mem.eql(u8, asset_info.bytes.?[0..asset_info.byte_count], "png-bytes"));

        var shape_commands: ?[*]const PathCommandInfo = null;
        var shape_command_count: usize = 0;
        expectWorkerStatus(
            svga_movie_get_shape_path_commands(handle, 0, 0, 0, &shape_commands, &shape_command_count),
            .ok,
        );
        expectWorker(shape_command_count == 2);
        expectWorker(shape_commands != null);

        var capabilities: RenderCapabilitiesInfo = undefined;
        expectWorkerStatus(
            svga_movie_get_frame_render_capabilities(handle, frame_index, &capabilities),
            .ok,
        );
        expectWorker(capabilities.required_features & @intFromEnum(model.RenderFeature.bitmap_quads) != 0);
    }
}

fn parseCAbiMovieRepeatedly(bytes: []const u8) void {
    var iteration: usize = 0;
    while (iteration < 32) : (iteration += 1) {
        var out_movie: ?*MovieHandle = null;
        expectWorkerStatus(svga_movie_parse(bytes.ptr, bytes.len, &out_movie), .ok);

        var info: MovieInfo = undefined;
        expectWorkerStatus(svga_movie_get_info(out_movie, &info), .ok);
        expectWorker(info.frames == 60);

        svga_movie_destroy(out_movie);
    }
}

fn expectWorkerStatus(status: i32, expected: Status) void {
    if (status != statusCode(expected)) @panic("unexpected concurrent worker status");
}

fn expectWorker(condition: bool) void {
    if (!condition) @panic("concurrent worker assertion failed");
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

test "C API parse rejects non-SVGA bytes without creating a handle" {
    const bytes = [_]u8{ 0, 1, 2, 3 };
    var out_movie: ?*MovieHandle = undefined;

    try std.testing.expectEqual(
        statusCode(.parse_error),
        svga_movie_parse(bytes[0..].ptr, bytes.len, &out_movie),
    );
    try std.testing.expect(out_movie == null);
}

test "C API parses a movie from a filesystem path" {
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
    const path_z = try std.testing.allocator.dupeZ(u8, path);
    defer std.testing.allocator.free(path_z);

    var out_movie: ?*MovieHandle = null;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_parse_file(path_z.ptr, &out_movie));
    defer svga_movie_destroy(out_movie);

    var info: MovieInfo = undefined;
    try std.testing.expectEqual(statusCode(.ok), svga_movie_get_info(out_movie, &info));
    try std.testing.expectEqual(@as(i32, 60), info.frames);
}

test "C API downloader validates URL and options before network access" {
    var out_movie: ?*MovieHandle = undefined;

    try std.testing.expectEqual(
        statusCode(.null_argument),
        svga_movie_download(null, null, &out_movie),
    );
    try std.testing.expect(out_movie == null);

    const empty_url = "";
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_movie_download(empty_url, null, &out_movie),
    );
    try std.testing.expect(out_movie == null);

    const url = "https://example.com/file.svga";
    const options = DownloadOptions{
        .abi_version = abi_version + 1,
        .max_input_bytes = 1,
    };
    try std.testing.expectEqual(
        statusCode(.invalid_argument),
        svga_movie_download(url, &options, &out_movie),
    );
    try std.testing.expect(out_movie == null);
}

test "C API status messages tolerate unknown values" {
    try std.testing.expectEqualStrings("unknown status", std.mem.span(svga_status_message(9999)));
}
