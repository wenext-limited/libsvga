#ifndef LIBSVGA_SVGA_H
#define LIBSVGA_SVGA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SVGA_ABI_VERSION 1u
#define SVGA_MAX_VERSION_BYTES 255u

typedef int32_t svga_status_t;

enum {
    SVGA_STATUS_OK = 0,
    SVGA_STATUS_NULL_ARGUMENT = 1,
    SVGA_STATUS_INVALID_ARGUMENT = 2,
    SVGA_STATUS_OUT_OF_MEMORY = 3,
    SVGA_STATUS_UNSUPPORTED = 4,
    SVGA_STATUS_INTERNAL_ERROR = 5,
    SVGA_STATUS_PARSE_ERROR = 6,
    SVGA_STATUS_IO_ERROR = 7,
};

typedef struct svga_movie svga_movie_t;

typedef struct svga_movie_desc {
    uint32_t abi_version;
    float view_box_width;
    float view_box_height;
    int32_t fps;
    int32_t frames;
    uint32_t image_count;
    uint32_t sprite_count;
    uint32_t audio_count;
    /* Optional null-terminated UTF-8 string. Copied by svga_movie_create. */
    const char *version_utf8;
} svga_movie_desc_t;

typedef struct svga_movie_info {
    uint32_t abi_version;
    float view_box_width;
    float view_box_height;
    int32_t fps;
    int32_t frames;
    uint32_t image_count;
    uint32_t sprite_count;
    uint32_t audio_count;
    /* Borrowed from svga_movie_t. Valid until svga_movie_destroy. */
    const char *version_utf8;
} svga_movie_info_t;

typedef struct svga_rect {
    float x;
    float y;
    float width;
    float height;
} svga_rect_t;

typedef struct svga_transform {
    float a;
    float b;
    float c;
    float d;
    float tx;
    float ty;
} svga_transform_t;

typedef struct svga_sprite_info {
    const char *image_key_utf8;
    const char *matte_key_utf8;
    uint32_t frame_count;
    uint8_t is_matte;
    uint8_t has_matte;
} svga_sprite_info_t;

typedef struct svga_frame_info {
    float alpha;
    svga_rect_t layout;
    svga_transform_t transform;
    float nx;
    float ny;
    uint32_t shape_count;
    int32_t first_shape_type;
    uint8_t visible;
    uint8_t is_keep_frame;
    const char *clip_path_utf8;
} svga_frame_info_t;

typedef struct svga_render_command_info {
    uint32_t sprite_index;
    float opacity;
    svga_rect_t bounds;
    svga_transform_t transform;
} svga_render_command_info_t;

typedef struct svga_render_item_info {
    uint32_t sprite_index;
    uint32_t frame_index;
    uint32_t shape_frame_index;
    float opacity;
    svga_rect_t bounds;
    svga_transform_t transform;
    uint8_t is_matte;
    uint8_t has_matte;
    uint8_t has_clip_path;
    uint8_t has_shapes;
} svga_render_item_info_t;

typedef struct svga_render_range {
    size_t start;
    size_t count;
} svga_render_range_t;

enum {
    SVGA_PATH_COMMAND_MOVE = 0,
    SVGA_PATH_COMMAND_LINE = 1,
    SVGA_PATH_COMMAND_QUAD = 2,
    SVGA_PATH_COMMAND_CUBIC = 3,
    SVGA_PATH_COMMAND_CLOSE = 4,
};

typedef struct svga_path_command_info {
    int32_t command_type;
    float p0_x;
    float p0_y;
    float p1_x;
    float p1_y;
    float p2_x;
    float p2_y;
} svga_path_command_info_t;

enum {
    SVGA_ASSET_UNKNOWN = 0,
    SVGA_ASSET_IMAGE_BYTES = 1,
    SVGA_ASSET_FILENAME = 2,
    SVGA_ASSET_AUDIO_BYTES = 3,
};

enum {
    SVGA_SHAPE_UNKNOWN = -1,
    SVGA_SHAPE_PATH = 0,
    SVGA_SHAPE_RECT = 1,
    SVGA_SHAPE_ELLIPSE = 2,
    SVGA_SHAPE_KEEP = 3,
};

typedef struct svga_asset_info {
    const char *key_utf8;
    int32_t kind;
    const uint8_t *bytes;
    size_t byte_count;
    const char *filename_utf8;
} svga_asset_info_t;

typedef struct svga_audio_info {
    const char *audio_key_utf8;
    int32_t start_frame;
    int32_t end_frame;
    int32_t start_time_ms;
    int32_t total_time_ms;
} svga_audio_info_t;

typedef struct svga_color {
    float r;
    float g;
    float b;
    float a;
} svga_color_t;

typedef struct svga_shape_style {
    svga_color_t fill;
    svga_color_t stroke;
    float stroke_width;
    int32_t line_cap;
    int32_t line_join;
    float miter_limit;
    float line_dash_i;
    float line_dash_ii;
    float line_dash_iii;
    uint8_t has_fill;
    uint8_t has_stroke;
} svga_shape_style_t;

typedef struct svga_shape_rect {
    float x;
    float y;
    float width;
    float height;
    float corner_radius;
} svga_shape_rect_t;

typedef struct svga_shape_ellipse {
    float x;
    float y;
    float radius_x;
    float radius_y;
} svga_shape_ellipse_t;

typedef struct svga_shape_info {
    int32_t shape_type;
    const char *path_data_utf8;
    svga_shape_rect_t rect;
    svga_shape_ellipse_t ellipse;
    svga_shape_style_t styles;
    svga_transform_t transform;
    uint8_t has_styles;
    uint8_t has_transform;
} svga_shape_info_t;

uint32_t svga_abi_version(void);
const char *svga_status_message(svga_status_t status);

svga_status_t svga_movie_create(svga_movie_t **out_movie, const svga_movie_desc_t *desc);
void svga_movie_destroy(svga_movie_t *movie);
svga_status_t svga_movie_get_info(const svga_movie_t *movie, svga_movie_info_t *out_info);
svga_status_t svga_movie_get_sprite_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    svga_sprite_info_t *out_info
);
svga_status_t svga_movie_get_sprite_table(
    const svga_movie_t *movie,
    const svga_sprite_info_t **out_sprites,
    size_t *out_count
);
svga_status_t svga_movie_get_frame_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    svga_frame_info_t *out_info
);
svga_status_t svga_movie_get_frame_table(
    const svga_movie_t *movie,
    const svga_frame_info_t **out_frames,
    size_t *out_frame_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);
svga_status_t svga_movie_get_asset_count(const svga_movie_t *movie, uint32_t *out_count);
svga_status_t svga_movie_get_asset_info(
    const svga_movie_t *movie,
    uint32_t asset_index,
    svga_asset_info_t *out_info
);
svga_status_t svga_movie_get_audio_info(
    const svga_movie_t *movie,
    uint32_t audio_index,
    svga_audio_info_t *out_info
);
svga_status_t svga_movie_get_shape_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    uint32_t shape_index,
    svga_shape_info_t *out_info
);
svga_status_t svga_movie_get_shape_table(
    const svga_movie_t *movie,
    const svga_shape_info_t **out_shapes,
    size_t *out_shape_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);
svga_status_t svga_movie_get_frame_clip_path_commands(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    const svga_path_command_info_t **out_commands,
    size_t *out_count
);
svga_status_t svga_movie_get_frame_clip_path_command_table(
    const svga_movie_t *movie,
    const svga_path_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);
svga_status_t svga_movie_get_shape_path_commands(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    uint32_t shape_index,
    const svga_path_command_info_t **out_commands,
    size_t *out_count
);
svga_status_t svga_movie_get_shape_path_command_table(
    const svga_movie_t *movie,
    const svga_path_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);
svga_status_t svga_movie_get_render_commands(
    const svga_movie_t *movie,
    uint32_t frame_index,
    const svga_render_command_info_t **out_commands,
    uint32_t *out_count
);
svga_status_t svga_movie_get_render_items(
    const svga_movie_t *movie,
    uint32_t frame_index,
    const svga_render_item_info_t **out_items,
    uint32_t *out_count
);
svga_status_t svga_movie_get_render_command_table(
    const svga_movie_t *movie,
    const svga_render_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);
svga_status_t svga_movie_get_render_item_table(
    const svga_movie_t *movie,
    const svga_render_item_info_t **out_items,
    size_t *out_item_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

svga_status_t svga_movie_parse(const uint8_t *bytes, size_t byte_count, svga_movie_t **out_movie);
svga_status_t svga_movie_parse_file(const char *path_utf8, svga_movie_t **out_movie);

/* Compatibility aliases for early Swift wrappers. */
static inline svga_status_t svga_movie_decode(
    const uint8_t *bytes,
    size_t byte_count,
    svga_movie_t **out_movie
) {
    return svga_movie_parse(bytes, byte_count, out_movie);
}

static inline void svga_movie_release(svga_movie_t *movie) {
    svga_movie_destroy(movie);
}

static inline const char *svga_error_message(svga_status_t status) {
    return svga_status_message(status);
}

#ifdef __cplusplus
}
#endif

#endif
