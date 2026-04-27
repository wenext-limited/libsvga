const std = @import("std");
const core = @import("core.zig");
const model = @import("model.zig");

pub const abi_version: u32 = 1;

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
const allocator = std.heap.smp_allocator;

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

pub const Rect = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
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
    info.* = .{
        .key_utf8 = asset.key.ptr,
        .kind = @intFromEnum(asset.kind),
        .bytes = if (asset.bytes.len == 0) null else asset.bytes.ptr,
        .byte_count = asset.bytes.len,
        .filename_utf8 = asset.filename.ptr,
    };
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

    const path_ptr = path_utf8 orelse return statusCode(.null_argument);
    const path = std.mem.span(path_ptr);
    if (path.len == 0) return statusCode(.invalid_argument);

    const movie = core.parseMovieFile(allocator, path, .{}) catch |err| return statusCode(statusFromError(err));
    out.* = handleFromMovie(movie);
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
        => .invalid_argument,
        error.UnsupportedContainer,
        error.UnsupportedZip,
        error.UnsupportedZipMethod,
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

test "C API status messages tolerate unknown values" {
    try std.testing.expectEqualStrings("unknown status", std.mem.span(svga_status_message(9999)));
}
