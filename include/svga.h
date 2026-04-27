#ifndef LIBSVGA_SVGA_H
#define LIBSVGA_SVGA_H

/**
 * @file svga.h
 *
 * C ABI for libsvga.
 *
 * libsvga parses SVGA animation files into immutable, renderer-friendly movie
 * metadata. The API is designed for Swift, Objective-C, Kotlin/JNI, C/C++, and
 * WebAssembly bindings:
 *
 * - Create a movie with svga_movie_parse(), svga_movie_parse_file(),
 *   svga_movie_download(), or svga_movie_create().
 * - Query metadata, assets, timeline state, and precomputed render tables.
 * - Release the movie with svga_movie_destroy().
 *
 * Ownership rules:
 *
 * - svga_movie_t owns every pointer returned by query functions.
 * - Returned strings, byte slices, and table pointers are borrowed and remain
 *   valid until svga_movie_destroy(movie).
 * - Do not free returned pointers yourself.
 * - Every out pointer is reset to NULL or zero on entry where that makes sense,
 *   so callers can safely inspect outputs after non-OK status values.
 *
 * Threading:
 *
 * - A parsed movie is immutable. Concurrent read-only queries are safe as long
 *   as another thread does not destroy the movie at the same time.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** ABI version implemented by this header and library. */
#define SVGA_ABI_VERSION 1u

/** Maximum non-NUL bytes accepted in an SVGA version string. */
#define SVGA_MAX_VERSION_BYTES 255u

/** Status code returned by all fallible APIs. */
typedef int32_t svga_status_t;

/** Common status values. Convert to text with svga_status_message(). */
enum {
    /** Operation completed successfully. */
    SVGA_STATUS_OK = 0,
    /** A required pointer argument was NULL. */
    SVGA_STATUS_NULL_ARGUMENT = 1,
    /** An argument value was outside the accepted range. */
    SVGA_STATUS_INVALID_ARGUMENT = 2,
    /** Allocation failed. */
    SVGA_STATUS_OUT_OF_MEMORY = 3,
    /** The requested container, feature, or platform path is unsupported. */
    SVGA_STATUS_UNSUPPORTED = 4,
    /** Unexpected internal failure. */
    SVGA_STATUS_INTERNAL_ERROR = 5,
    /** Input bytes looked like SVGA but could not be parsed. */
    SVGA_STATUS_PARSE_ERROR = 6,
    /** Filesystem read failed. */
    SVGA_STATUS_IO_ERROR = 7,
};

/** Opaque parsed movie handle. Destroy with svga_movie_destroy(). */
typedef struct svga_movie svga_movie_t;

/* Movie metadata and common geometry. */

/** Input descriptor for manually creating a minimal movie. */
typedef struct svga_movie_desc {
    /** Must be SVGA_ABI_VERSION. */
    uint32_t abi_version;
    /** SVGA viewBox width in source units. Must be positive. */
    float view_box_width;
    /** SVGA viewBox height in source units. Must be positive. */
    float view_box_height;
    /** Frames per second. Must be positive. */
    int32_t fps;
    /** Total frame count. Must be non-negative. */
    int32_t frames;
    /** Declared image count from the source movie. */
    uint32_t image_count;
    /** Declared sprite count from the source movie. */
    uint32_t sprite_count;
    /** Declared audio count from the source movie. */
    uint32_t audio_count;
    /** Optional NUL-terminated UTF-8 string. Copied by svga_movie_create(). */
    const char *version_utf8;
} svga_movie_desc_t;

/** Basic movie metadata returned by svga_movie_get_info(). */
typedef struct svga_movie_info {
    /** ABI version used to fill this struct. */
    uint32_t abi_version;
    /** SVGA viewBox width in source units. */
    float view_box_width;
    /** SVGA viewBox height in source units. */
    float view_box_height;
    /** Frames per second. */
    int32_t fps;
    /** Total frame count. */
    int32_t frames;
    /** Number of image assets declared by the movie metadata. */
    uint32_t image_count;
    /** Number of sprites declared by the movie metadata. */
    uint32_t sprite_count;
    /** Number of audio entries declared by the movie metadata. */
    uint32_t audio_count;
    /** Borrowed NUL-terminated UTF-8 string. Valid until movie destruction. */
    const char *version_utf8;
} svga_movie_info_t;

/** Options for svga_movie_download(). */
typedef struct svga_download_options {
    /** Must be SVGA_ABI_VERSION. */
    uint32_t abi_version;
    /**
     * Maximum response bytes accepted before parsing.
     *
     * Use zero for the library default.
     */
    size_t max_input_bytes;
} svga_download_options_t;

/** Float rectangle in SVGA source units. */
typedef struct svga_rect {
    float x;
    float y;
    float width;
    float height;
} svga_rect_t;

/** Double-precision size used by layout helpers. */
typedef struct svga_size2d {
    double width;
    double height;
} svga_size2d_t;

/** Double-precision point used by layout helpers. */
typedef struct svga_point2d {
    double x;
    double y;
} svga_point2d_t;

/** Double-precision rectangle used by layout helpers. */
typedef struct svga_rect2d {
    double x;
    double y;
    double width;
    double height;
} svga_rect2d_t;

/** Scale and origin needed to place a movie in a viewport. */
typedef struct svga_movie_layout {
    double scale_x;
    double scale_y;
    svga_point2d_t origin;
} svga_movie_layout_t;

/** Half-open frame range: [lower_bound, upper_bound). */
typedef struct svga_frame_range {
    int32_t lower_bound;
    int32_t upper_bound;
} svga_frame_range_t;

/** Playback inputs for svga_playback_position(). */
typedef struct svga_playback_state {
    int32_t frame_count;
    int32_t fps;
    /** Playback frame range, half-open: [lower_bound, upper_bound). */
    svga_frame_range_t playback_range;
    /** Elapsed playback time in seconds. Negative values are clamped to zero. */
    double elapsed_seconds;
    /** Playback speed multiplier. Negative values are treated as zero. */
    double playback_speed;
    /** Starting offset into playback_range, in frames. */
    int64_t start_frame_offset;
    /** Number of loops. Use 0 for infinite looping. */
    int64_t loop_count;
    /** Non-zero plays the range in reverse. */
    uint8_t reverse;
    /** One of SVGA_FILL_MODE_*. */
    int32_t fill_mode;
} svga_playback_state_t;

/** Playback result from svga_playback_position(). */
typedef struct svga_playback_position {
    int32_t frame_index;
    int64_t completed_loop_count;
    uint8_t did_finish;
} svga_playback_position_t;

/** 2D affine transform matching SVGA's a,b,c,d,tx,ty matrix fields. */
typedef struct svga_transform {
    float a;
    float b;
    float c;
    float d;
    float tx;
    float ty;
} svga_transform_t;

/* Parsed movie tables and renderer-facing records. */

/** Sprite-level metadata. Strings are borrowed from svga_movie_t. */
typedef struct svga_sprite_info {
    const char *image_key_utf8;
    const char *matte_key_utf8;
    uint32_t frame_count;
    uint8_t is_matte;
    uint8_t has_matte;
} svga_sprite_info_t;

/** Per-sprite-frame metadata. clip_path_utf8 is borrowed from svga_movie_t. */
typedef struct svga_frame_info {
    float alpha;
    svga_rect_t layout;
    svga_transform_t transform;
    float nx;
    float ny;
    uint32_t shape_count;
    /** First shape type for quick feature detection. One of SVGA_SHAPE_*. */
    int32_t first_shape_type;
    uint8_t visible;
    uint8_t is_keep_frame;
    const char *clip_path_utf8;
} svga_frame_info_t;

/**
 * Fast bitmap draw command for a visual frame.
 *
 * This command is enough for renderers that only need bitmap quads. Use
 * svga_movie_get_frame_render_capabilities() before relying on command-only
 * rendering.
 */
typedef struct svga_render_command_info {
    uint32_t sprite_index;
    float opacity;
    svga_rect_t bounds;
    svga_transform_t transform;
} svga_render_command_info_t;

/**
 * Rich render item for a visual frame.
 *
 * This includes the source sprite frame and feature flags, making it suitable
 * for renderers that need mattes, clip paths, or vector shapes.
 */
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

/**
 * Slice into a flat table.
 *
 * For table APIs, range i describes records for frame i or owner i, depending
 * on the API name. The records live in the companion table returned by the same
 * function.
 */
typedef struct svga_render_range {
    size_t start;
    size_t count;
} svga_render_range_t;

/** Feature bits reported by svga_render_capabilities_t.required_features. */
enum {
    SVGA_RENDER_FEATURE_BITMAP_QUADS = 1u << 0,
    SVGA_RENDER_FEATURE_CLIP_PATHS = 1u << 1,
    SVGA_RENDER_FEATURE_MATTES = 1u << 2,
    SVGA_RENDER_FEATURE_VECTOR_SHAPES = 1u << 3,
};

/** Summary of renderer features required for a movie or frame. */
typedef struct svga_render_capabilities {
    uint32_t abi_version;
    /** OR-ed SVGA_RENDER_FEATURE_* bits. */
    uint32_t required_features;
    /** Number of bitmap commands available for direct bitmap rendering. */
    uint32_t bitmap_command_count;
    /** Non-zero when bitmap commands are sufficient for visually correct output. */
    uint8_t direct_bitmap_compatible;
} svga_render_capabilities_t;

/** Path command type values used by svga_path_command_info_t. */
enum {
    SVGA_PATH_COMMAND_MOVE = 0,
    SVGA_PATH_COMMAND_LINE = 1,
    SVGA_PATH_COMMAND_QUAD = 2,
    SVGA_PATH_COMMAND_CUBIC = 3,
    SVGA_PATH_COMMAND_CLOSE = 4,
};

/** One parsed SVG path command. Only the points required by command_type are valid. */
typedef struct svga_path_command_info {
    int32_t command_type;
    float p0_x;
    float p0_y;
    float p1_x;
    float p1_y;
    float p2_x;
    float p2_y;
} svga_path_command_info_t;

/** Asset kind values used by svga_asset_info_t.kind. */
enum {
    SVGA_ASSET_UNKNOWN = 0,
    SVGA_ASSET_IMAGE_BYTES = 1,
    SVGA_ASSET_FILENAME = 2,
    SVGA_ASSET_AUDIO_BYTES = 3,
};

/** Shape type values used by svga_shape_info_t.shape_type. */
enum {
    SVGA_SHAPE_UNKNOWN = -1,
    SVGA_SHAPE_PATH = 0,
    SVGA_SHAPE_RECT = 1,
    SVGA_SHAPE_ELLIPSE = 2,
    SVGA_SHAPE_KEEP = 3,
};

/** Content mode values used by svga_make_movie_layout(). */
enum {
    SVGA_CONTENT_MODE_FIT = 0,
    SVGA_CONTENT_MODE_FILL = 1,
    SVGA_CONTENT_MODE_SCALE_TO_FILL = 2,
    SVGA_CONTENT_MODE_TOP = 3,
    SVGA_CONTENT_MODE_BOTTOM = 4,
    SVGA_CONTENT_MODE_LEFT = 5,
    SVGA_CONTENT_MODE_RIGHT = 6,
};

/** Fill mode values used by svga_playback_position(). */
enum {
    SVGA_FILL_MODE_CURRENT = 0,
    SVGA_FILL_MODE_BACKWARD = 1,
    SVGA_FILL_MODE_FORWARD = 2,
};

/** Asset metadata. Strings and byte slices are borrowed from svga_movie_t. */
typedef struct svga_asset_info {
    const char *key_utf8;
    /** One of SVGA_ASSET_*. */
    int32_t kind;
    /** Borrowed asset bytes when kind is IMAGE_BYTES or AUDIO_BYTES. */
    const uint8_t *bytes;
    size_t byte_count;
    /** Borrowed filename when kind is FILENAME. */
    const char *filename_utf8;
} svga_asset_info_t;

/** Audio timing metadata. Strings are borrowed from svga_movie_t. */
typedef struct svga_audio_info {
    const char *audio_key_utf8;
    int32_t start_frame;
    int32_t end_frame;
    int32_t start_time_ms;
    int32_t total_time_ms;
} svga_audio_info_t;

/** RGBA color, each channel normally in 0...1. */
typedef struct svga_color {
    float r;
    float g;
    float b;
    float a;
} svga_color_t;

/** Fill and stroke style for vector shapes. */
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

/** Rectangle shape arguments. */
typedef struct svga_shape_rect {
    float x;
    float y;
    float width;
    float height;
    float corner_radius;
} svga_shape_rect_t;

/** Ellipse shape arguments. */
typedef struct svga_shape_ellipse {
    float x;
    float y;
    float radius_x;
    float radius_y;
} svga_shape_ellipse_t;

/** Shape metadata. path_data_utf8 is borrowed from svga_movie_t. */
typedef struct svga_shape_info {
    /** One of SVGA_SHAPE_*. */
    int32_t shape_type;
    const char *path_data_utf8;
    svga_shape_rect_t rect;
    svga_shape_ellipse_t ellipse;
    svga_shape_style_t styles;
    svga_transform_t transform;
    uint8_t has_styles;
    uint8_t has_transform;
} svga_shape_info_t;

/* Library identity and movie lifecycle. */

/**
 * Returns SVGA_ABI_VERSION from the linked library.
 *
 * @return ABI version implemented by the linked library.
 */
uint32_t svga_abi_version(void);

/**
 * Returns a static English message for a status code.
 *
 * @param status Status code returned by a libsvga API.
 * @return Borrowed static NUL-terminated string. Never returns NULL.
 */
const char *svga_status_message(svga_status_t status);

/**
 * Creates a minimal movie from caller-provided metadata.
 *
 * This is useful for tests and wrappers that need a valid empty handle. For
 * normal SVGA files, use svga_movie_parse() or svga_movie_parse_file().
 *
 * @param out_movie Receives the created movie handle on success. Must not be NULL.
 * @param desc Movie metadata descriptor. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise a validation or allocation status.
 */
svga_status_t svga_movie_create(svga_movie_t **out_movie, const svga_movie_desc_t *desc);

/**
 * Destroys a movie returned by this API.
 *
 * @param movie Movie handle to destroy. May be NULL.
 */
void svga_movie_destroy(svga_movie_t *movie);

/**
 * Copies basic movie metadata into out_info.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_info Receives borrowed movie metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_info(const svga_movie_t *movie, svga_movie_info_t *out_info);

/* Metadata lookup and borrowed table APIs. */

/**
 * Copies metadata for one sprite by index.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param sprite_index Zero-based sprite index.
 * @param out_info Receives borrowed sprite metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when the index is out of range.
 */
svga_status_t svga_movie_get_sprite_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    svga_sprite_info_t *out_info
);

/**
 * Returns the borrowed flat sprite table.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_sprites Receives a borrowed pointer to sprite records, or NULL when empty.
 * @param out_count Receives the number of sprite records.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_sprite_table(
    const svga_movie_t *movie,
    const svga_sprite_info_t **out_sprites,
    size_t *out_count
);

/**
 * Copies metadata for one frame within one sprite.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param sprite_index Zero-based sprite index.
 * @param frame_index Zero-based frame index inside the sprite.
 * @param out_info Receives borrowed frame metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when an index is out of range.
 */
svga_status_t svga_movie_get_frame_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    svga_frame_info_t *out_info
);

/**
 * Returns the borrowed flat frame table and sprite-to-frame ranges.
 *
 * Range i describes the frames for sprite i.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_frames Receives a borrowed pointer to frame records, or NULL when empty.
 * @param out_frame_count Receives the number of frame records.
 * @param out_ranges Receives a borrowed pointer to sprite-to-frame ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_frame_table(
    const svga_movie_t *movie,
    const svga_frame_info_t **out_frames,
    size_t *out_frame_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns the number of assets stored in the movie.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_count Receives the asset count.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_asset_count(const svga_movie_t *movie, uint32_t *out_count);

/**
 * Copies metadata for one asset by index.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param asset_index Zero-based asset index.
 * @param out_info Receives borrowed asset metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when the index is out of range.
 */
svga_status_t svga_movie_get_asset_info(
    const svga_movie_t *movie,
    uint32_t asset_index,
    svga_asset_info_t *out_info
);

/**
 * Finds an asset by exact key.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param key_utf8 NUL-terminated UTF-8 asset key. Must not be NULL or empty.
 * @param out_info Receives borrowed asset metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when no asset matches.
 */
svga_status_t svga_movie_find_asset(
    const svga_movie_t *movie,
    const char *key_utf8,
    svga_asset_info_t *out_info
);

/**
 * Resolves an image asset by SVGA image key.
 *
 * Filename indirections are followed using libsvga's portable lookup policy,
 * including the common "name" -> "name.png" case.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param image_key_utf8 NUL-terminated UTF-8 image key from a sprite. Must not be NULL or empty.
 * @param out_info Receives borrowed resolved asset metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when no image asset resolves.
 */
svga_status_t svga_movie_resolve_image_asset(
    const svga_movie_t *movie,
    const char *image_key_utf8,
    svga_asset_info_t *out_info
);

/**
 * Resolves an audio asset by SVGA audio key, following filename indirections.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param audio_key_utf8 NUL-terminated UTF-8 audio key. Must not be NULL or empty.
 * @param out_info Receives borrowed resolved asset metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when no audio asset resolves.
 */
svga_status_t svga_movie_resolve_audio_asset(
    const svga_movie_t *movie,
    const char *audio_key_utf8,
    svga_asset_info_t *out_info
);

/**
 * Copies metadata for one audio entry by index.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param audio_index Zero-based audio index.
 * @param out_info Receives borrowed audio metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when the index is out of range.
 */
svga_status_t svga_movie_get_audio_info(
    const svga_movie_t *movie,
    uint32_t audio_index,
    svga_audio_info_t *out_info
);

/**
 * Copies metadata for one shape in one sprite frame.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param sprite_index Zero-based sprite index.
 * @param frame_index Zero-based frame index inside the sprite.
 * @param shape_index Zero-based shape index inside the frame.
 * @param out_info Receives borrowed shape metadata. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when an index is out of range.
 */
svga_status_t svga_movie_get_shape_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    uint32_t shape_index,
    svga_shape_info_t *out_info
);

/**
 * Returns the borrowed flat shape table and frame-to-shape ranges.
 *
 * Range i describes the shapes for frame table entry i.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_shapes Receives a borrowed pointer to shape records, or NULL when empty.
 * @param out_shape_count Receives the number of shape records.
 * @param out_ranges Receives a borrowed pointer to frame-to-shape ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_shape_table(
    const svga_movie_t *movie,
    const svga_shape_info_t **out_shapes,
    size_t *out_shape_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns parsed path commands for a frame clip path.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param sprite_index Zero-based sprite index.
 * @param frame_index Zero-based frame index inside the sprite.
 * @param out_commands Receives a borrowed pointer to path commands, or NULL when empty.
 * @param out_count Receives the command count.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when an index is out of range.
 */
svga_status_t svga_movie_get_frame_clip_path_commands(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    const svga_path_command_info_t **out_commands,
    size_t *out_count
);

/**
 * Returns the borrowed flat clip-path command table and frame-to-command ranges.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_commands Receives a borrowed pointer to path commands, or NULL when empty.
 * @param out_command_count Receives the number of path commands.
 * @param out_ranges Receives a borrowed pointer to frame-to-command ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_frame_clip_path_command_table(
    const svga_movie_t *movie,
    const svga_path_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns parsed path commands for one vector path shape.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param sprite_index Zero-based sprite index.
 * @param frame_index Zero-based frame index inside the sprite.
 * @param shape_index Zero-based shape index inside the frame.
 * @param out_commands Receives a borrowed pointer to path commands, or NULL when empty.
 * @param out_count Receives the command count.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when an index is out of range.
 */
svga_status_t svga_movie_get_shape_path_commands(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    uint32_t shape_index,
    const svga_path_command_info_t **out_commands,
    size_t *out_count
);

/**
 * Returns the borrowed flat shape-path command table and shape-to-command ranges.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_commands Receives a borrowed pointer to path commands, or NULL when empty.
 * @param out_command_count Receives the number of path commands.
 * @param out_ranges Receives a borrowed pointer to shape-to-command ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_shape_path_command_table(
    const svga_movie_t *movie,
    const svga_path_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns bitmap render commands for one visual frame.
 *
 * Use svga_movie_get_frame_render_capabilities() to determine whether these
 * commands are sufficient for complete rendering.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param frame_index Zero-based timeline frame index.
 * @param out_commands Receives a borrowed pointer to render commands, or NULL when empty.
 * @param out_count Receives the render command count.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when frame_index is out of range.
 */
svga_status_t svga_movie_get_render_commands(
    const svga_movie_t *movie,
    uint32_t frame_index,
    const svga_render_command_info_t **out_commands,
    uint32_t *out_count
);

/**
 * Returns rich render items for one visual frame.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param frame_index Zero-based timeline frame index.
 * @param out_items Receives a borrowed pointer to render items, or NULL when empty.
 * @param out_count Receives the render item count.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when frame_index is out of range.
 */
svga_status_t svga_movie_get_render_items(
    const svga_movie_t *movie,
    uint32_t frame_index,
    const svga_render_item_info_t **out_items,
    uint32_t *out_count
);

/**
 * Returns all bitmap render commands plus frame-to-command ranges.
 *
 * Range i describes commands for visual frame i.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_commands Receives a borrowed pointer to render commands, or NULL when empty.
 * @param out_command_count Receives the number of render commands.
 * @param out_ranges Receives a borrowed pointer to frame-to-command ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_render_command_table(
    const svga_movie_t *movie,
    const svga_render_command_info_t **out_commands,
    size_t *out_command_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns all rich render items plus frame-to-item ranges.
 *
 * Range i describes items for visual frame i.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_items Receives a borrowed pointer to render items, or NULL when empty.
 * @param out_item_count Receives the number of render items.
 * @param out_ranges Receives a borrowed pointer to frame-to-item ranges, or NULL when empty.
 * @param out_range_count Receives the number of ranges.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_render_item_table(
    const svga_movie_t *movie,
    const svga_render_item_info_t **out_items,
    size_t *out_item_count,
    const svga_render_range_t **out_ranges,
    size_t *out_range_count
);

/**
 * Returns aggregate renderer capabilities for the whole movie.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_capabilities Receives feature bits and bitmap command count. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_render_capabilities(
    const svga_movie_t *movie,
    svga_render_capabilities_t *out_capabilities
);

/**
 * Returns renderer capabilities for one visual frame.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param frame_index Zero-based timeline frame index.
 * @param out_capabilities Receives feature bits and bitmap command count. Must not be NULL.
 * @return SVGA_STATUS_OK on success, or SVGA_STATUS_INVALID_ARGUMENT when frame_index is out of range.
 */
svga_status_t svga_movie_get_frame_render_capabilities(
    const svga_movie_t *movie,
    uint32_t frame_index,
    svga_render_capabilities_t *out_capabilities
);

/**
 * Returns the visual-frame table.
 *
 * Entry i maps timeline frame i to the previous frame that contains visual
 * content. Renderers can use this to skip rebuilding identical empty frames.
 *
 * @param movie Movie handle returned by libsvga. Must not be NULL.
 * @param out_indices Receives a borrowed pointer to frame indices, or NULL when empty.
 * @param out_count Receives the number of entries.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_movie_get_visual_frame_table(
    const svga_movie_t *movie,
    const uint32_t **out_indices,
    size_t *out_count
);

/* Parsing APIs. */

/**
 * Parses SVGA bytes from memory.
 *
 * Supports ZIP SVGA packages and zlib-compressed movie.binary payloads. On
 * success, out_movie receives a new handle that must be destroyed.
 *
 * @param bytes Pointer to SVGA bytes. Must not be NULL when byte_count is non-zero.
 * @param byte_count Number of bytes available at bytes. Must be greater than zero.
 * @param out_movie Receives a new movie handle on success. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise parse, validation, or allocation status.
 */
svga_status_t svga_movie_parse(const uint8_t *bytes, size_t byte_count, svga_movie_t **out_movie);

/**
 * Parses an SVGA file from a UTF-8 filesystem path.
 *
 * Some targets, such as freestanding WASM and Emscripten builds, do not expose
 * filesystem access through this ABI and return SVGA_STATUS_UNSUPPORTED. Use
 * svga_movie_parse() with bytes on those targets.
 *
 * @param path_utf8 NUL-terminated UTF-8 path to an SVGA file. Must not be NULL or empty.
 * @param out_movie Receives a new movie handle on success. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise IO, parse, validation, or unsupported status.
 */
svga_status_t svga_movie_parse_file(const char *path_utf8, svga_movie_t **out_movie);

/**
 * Downloads an SVGA URL into memory and parses the downloaded bytes.
 *
 * This is a convenience API for the direct URL -> bytes -> parser path. It
 * does not write the response to disk, and it does not implement filesystem
 * cache policy. Some targets, such as freestanding WASM and Emscripten builds,
 * do not expose network access through this ABI and return
 * SVGA_STATUS_UNSUPPORTED.
 *
 * @param url_utf8 NUL-terminated UTF-8 http/https URL. Must not be NULL or empty.
 * @param options Optional download limits. May be NULL for defaults.
 * @param out_movie Receives a new movie handle on success. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise network, parse, validation, or unsupported status.
 */
svga_status_t svga_movie_download(
    const char *url_utf8,
    const svga_download_options_t *options,
    svga_movie_t **out_movie
);

/* Playback and layout helpers. */

/**
 * Converts playback time to a clamped frame index.
 *
 * @param frame_count Total number of frames. Must be positive.
 * @param fps Frames per second. Must be positive.
 * @param playback_time_seconds Playback time in seconds. Must be finite.
 * @param out_frame_index Receives the clamped frame index. Must not be NULL.
 * @param out_clamped_time_seconds Receives the clamped playback time. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_frame_index_for_time(
    int32_t frame_count,
    int32_t fps,
    double playback_time_seconds,
    int32_t *out_frame_index,
    double *out_clamped_time_seconds
);

/**
 * Converts a frame index to presentation time in seconds.
 *
 * @param frame_index Zero-based frame index. Must be non-negative.
 * @param fps Frames per second. Must be positive.
 * @param out_presentation_time_seconds Receives frame_index / fps. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_presentation_time_for_frame(
    int32_t frame_index,
    int32_t fps,
    double *out_presentation_time_seconds
);

/**
 * Intersects range with valid_range. Both ranges are half-open.
 *
 * @param range Requested frame range.
 * @param valid_range Valid frame range to clamp against.
 * @param out_range Receives the clamped range. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_clamp_frame_range(
    svga_frame_range_t range,
    svga_frame_range_t valid_range,
    svga_frame_range_t *out_range
);

/**
 * Converts a frame index into an offset inside a playback range.
 *
 * @param frame_index Frame index to locate.
 * @param range Half-open playback range.
 * @param reverse Non-zero treats playback as reverse.
 * @param out_offset Receives the offset inside the range. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_frame_offset_for_frame(
    int32_t frame_index,
    svga_frame_range_t range,
    uint8_t reverse,
    int64_t *out_offset
);

/**
 * Converts an offset inside a playback range back to a frame index.
 *
 * @param offset Offset inside the playback range.
 * @param range Half-open playback range.
 * @param reverse Non-zero treats playback as reverse.
 * @param out_frame_index Receives the computed frame index. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise an argument status.
 */
svga_status_t svga_frame_index_for_offset(
    int64_t offset,
    svga_frame_range_t range,
    uint8_t reverse,
    int32_t *out_frame_index
);

/**
 * Returns the frame to display after playback finishes for a fill mode.
 *
 * @param range Half-open playback range.
 * @param reverse Non-zero treats playback as reverse.
 * @param fill_mode One of SVGA_FILL_MODE_*.
 * @param out_frame_index Receives the finished frame index. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_finished_frame_index(
    svga_frame_range_t range,
    uint8_t reverse,
    int32_t fill_mode,
    int32_t *out_frame_index
);

/**
 * Computes playback position from time, range, loops, direction, and fill mode.
 *
 * @param state Playback state inputs. Must not be NULL.
 * @param out_position Receives the frame, completed loops, and finish flag. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_playback_position(
    const svga_playback_state_t *state,
    svga_playback_position_t *out_position
);

/**
 * Computes scale and origin for placing a movie in a viewport.
 *
 * @param movie_size Source movie size. Width and height must be positive.
 * @param viewport_size Destination viewport size. Width and height must be positive.
 * @param content_mode One of SVGA_CONTENT_MODE_*.
 * @param out_layout Receives scale and origin. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_make_movie_layout(
    svga_size2d_t movie_size,
    svga_size2d_t viewport_size,
    int32_t content_mode,
    svga_movie_layout_t *out_layout
);

/**
 * Computes an aspect-fit rectangle for content inside bounds.
 *
 * @param content_size Source content size. Width and height must be positive.
 * @param bounds Destination bounds.
 * @param out_rect Receives the aspect-fit rectangle. Must not be NULL.
 * @return SVGA_STATUS_OK on success, otherwise SVGA_STATUS_INVALID_ARGUMENT.
 */
svga_status_t svga_aspect_fit_rect(
    svga_size2d_t content_size,
    svga_rect2d_t bounds,
    svga_rect2d_t *out_rect
);

/* Compatibility aliases for early Swift wrappers. Prefer the canonical names. */
/**
 * Compatibility alias for svga_movie_parse().
 *
 * @param bytes Pointer to SVGA bytes.
 * @param byte_count Number of bytes available at bytes.
 * @param out_movie Receives a new movie handle on success.
 * @return Same status values as svga_movie_parse().
 */
static inline svga_status_t svga_movie_decode(
    const uint8_t *bytes,
    size_t byte_count,
    svga_movie_t **out_movie
) {
    return svga_movie_parse(bytes, byte_count, out_movie);
}

/**
 * Compatibility alias for svga_movie_destroy().
 *
 * @param movie Movie handle to destroy. May be NULL.
 */
static inline void svga_movie_release(svga_movie_t *movie) {
    svga_movie_destroy(movie);
}

/**
 * Compatibility alias for svga_status_message().
 *
 * @param status Status code returned by a libsvga API.
 * @return Borrowed static NUL-terminated string.
 */
static inline const char *svga_error_message(svga_status_t status) {
    return svga_status_message(status);
}

#ifdef __cplusplus
}
#endif

#endif
