# libsvga

`libsvga` is the Zig core for a new SVGA implementation. It owns platform-neutral
SVGA parsing and timeline data, while platform packages such as Swift own UI,
image decoding, animation clocks, audio, and rendering.

The current milestone targets parser parity with SVGAPlayer-iOS for non-UI
code. `libsvga` parses plain zlib/protobuf SVGA 2.x files, zip archives with
`movie.binary`, and legacy zip archives with `movie.spec` JSON into normalized
movie and timeline data:

- SVGA version
- view box width and height
- FPS
- frame count
- image, sprite, asset, and audio counts
- filename assets, embedded image bytes, embedded audio bytes, and zip payloads
- sprite image/matte keys
- audio timing records
- frame alpha, layout, transform, clip path, and shape counts
- full vector shape records: path, rect, ellipse, keep, styles, and transform
- precomputed frame visibility and transformed `nx`/`ny` minima
- first-shape `keep` markers for vector frame caching
- asset-key resolution helpers, including filename indirection and `.png`
  fallback used by SVGA packages
- scalar playback and layout helpers for frame/time mapping, loop ranges, and
  viewport placement

Bitmap decoding, audio playback, layer construction, and animation clocks remain
platform/UI responsibilities.

## Build

Zig 0.15.2 is currently used.

```sh
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache zig build test
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache zig build
```

The build produces:

- `zig-out/lib/libsvga.a`
- `zig-out/include/svga.h`
- `zig-out/bin/svga_probe`

By default, builds use Zig's portable `std.compress.flate` inflater for SVGA
zlib and ZIP/deflate payloads, so release artifacts do not need a target `libz`
at link time. Pass `-Dsystem-zlib=true` to use the platform zlib instead.

On Darwin targets, `zig build` re-archives the installed static library with
Apple `libtool` so SwiftPM/Xcode's linker accepts `zig-out/lib/libsvga.a`.

## Release Packages

Build release archives with:

```sh
zig build package-release -Doptimize=ReleaseFast -Drelease-version=0.1.0
```

The package step produces:

- Android static library tarballs
- WASM static library tarballs
- `libsvga-apple-xcframework-<version>.tar.gz`
- `libsvga-static-<version>.xcframework.zip`

The `.xcframework.zip` puts `libsvga-static.xcframework` at the zip root so
SwiftPM can reference it with a binary target URL. The current XCFramework
contains macOS `arm64`, iOS device `arm64`, and iOS simulator `arm64` slices.

## C ABI

Zig consumers should import the package module and use the native core API:

```zig
const libsvga = @import("libsvga");

const movie = try libsvga.parseMovieFile(allocator, path, .{});
defer libsvga.destroyMovie(allocator, movie);

const remote_movie = try libsvga.downloadMovie(allocator, "https://example.com/anim.svga", .{});
defer libsvga.destroyMovie(allocator, remote_movie);
```

The public C ABI is declared in `include/svga.h`.

The core API uses opaque handles and explicit ownership:

```c
svga_status_t svga_movie_parse(
    const uint8_t *bytes,
    size_t byte_count,
    svga_movie_t **out_movie
);

svga_status_t svga_movie_parse_file(
    const char *path_utf8,
    svga_movie_t **out_movie
);

svga_status_t svga_movie_download(
    const char *url_utf8,
    const svga_download_options_t *options,
    svga_movie_t **out_movie
);

svga_status_t svga_movie_get_info(
    const svga_movie_t *movie,
    svga_movie_info_t *out_info
);

svga_status_t svga_movie_get_sprite_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    svga_sprite_info_t *out_info
);

svga_status_t svga_movie_get_frame_info(
    const svga_movie_t *movie,
    uint32_t sprite_index,
    uint32_t frame_index,
    svga_frame_info_t *out_info
);

svga_status_t svga_movie_get_asset_count(
    const svga_movie_t *movie,
    uint32_t *out_count
);

svga_status_t svga_movie_get_asset_info(
    const svga_movie_t *movie,
    uint32_t asset_index,
    svga_asset_info_t *out_info
);

svga_status_t svga_movie_find_asset(
    const svga_movie_t *movie,
    const char *key_utf8,
    svga_asset_info_t *out_info
);

svga_status_t svga_movie_resolve_image_asset(
    const svga_movie_t *movie,
    const char *image_key_utf8,
    svga_asset_info_t *out_info
);

svga_status_t svga_movie_resolve_audio_asset(
    const svga_movie_t *movie,
    const char *audio_key_utf8,
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

void svga_movie_destroy(svga_movie_t *movie);
```

Strings and byte buffers returned through info structs are borrowed from the
movie handle and remain valid until `svga_movie_destroy`.
`svga_movie_parse_file` reads local filesystem paths in Zig before parsing, so
platform bindings do not need to materialize an intermediate byte buffer when
they already have a file URL.
`svga_movie_download` downloads an HTTP/HTTPS response into a bounded memory
buffer and then calls the same byte parser. It does not write the response to
disk; platform layers should still own cache policy, custom headers, and
session/authentication behavior.

Missing asset keys return `SVGA_STATUS_INVALID_ARGUMENT` and clear the output
record. Resolved image/audio asset helpers preserve SVGAPlayerSwift's filename
policy: exact key lookup first; filename assets resolve to `name.png` and then
`name`, unless the filename already ends in `.png`.

The C ABI also exposes platform-neutral scalar helpers for:

- frame/time conversion
- playback range clamping, reverse offsets, loop completion, and fill-frame
  selection
- movie-to-viewport layout and aspect-fit rectangles

## Probe Tool

`svga_probe` parses one or more `.svga` files and prints movie metadata.

```sh
zig-out/bin/svga_probe path/to/file.svga
```

The parser-parity fixture runs currently pass:

- archived SVGAPlayer-iOS samples: `ok=10 failed=0`
- private production `.svga` resources: `ok=175 failed=0`

The standalone benchmark compares `libsvga` against the archived
SVGAPlayer-iOS parser on private fixtures. A recent `ITERATIONS=3` run:

- `zig/libsvga`: `754048.4 ns_per_parse`
- `objc/SVGAPlayer-iOS`: `2463912.8 ns_per_parse`

## Design Boundary

`libsvga` should own:

- container detection
- optional direct HTTP/HTTPS download-to-memory parsing
- zlib/zip decode
- protobuf and legacy JSON parsing
- normalized movie, sprite, frame, shape, audio, and asset records
- scalar frame/timeline lookup helpers
- asset indirection policy and viewport layout math

Platform layers should own:

- network session policy, request headers, authentication, and filesystem cache
  policy
- `UIImage`/`CGImage`/bitmap decode
- `CALayer`, `CAShapeLayer`, SwiftUI, or Android rendering
- audio playback
- dynamic text/image/drawing replacement
