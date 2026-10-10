#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: verify_apple_zlib_link.sh XCFRAMEWORK" >&2
    exit 2
fi

xcframework=$1
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/libsvga-zlib-link.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/main.swift" <<'SWIFT'
import libsvga

// Zlib-compressed MovieEntity: version 2.0, 320x240, 30 fps, one frame.
let bytes: [UInt8] = [120, 156, 227, 98, 54, 210, 51, 16, 226, 227, 101, 96,
                     88, 224, 44, 202, 192, 80, 224, 44, 33, 167, 192, 8,
                     0, 29, 18, 2, 205]
var movie: OpaquePointer?
let status = bytes.withUnsafeBufferPointer {
    svga_movie_parse($0.baseAddress, $0.count, &movie)
}
precondition(status == SVGA_STATUS_OK)
var info = svga_movie_info_t()
precondition(svga_movie_get_info(movie, &info) == SVGA_STATUS_OK)
precondition(info.frames == 1 && info.fps == 30)
precondition(info.view_box_width == 320 && info.view_box_height == 240)
svga_movie_destroy(movie)
SWIFT

verify_slice() {
    slice=$1
    sdk=$2
    target=$3
    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    # Catch an accidental return to the portable inflater even if linking works.
    nm -u "$xcframework/$slice/libsvga.a" > "$tmp_dir/$slice-symbols.txt"
    grep -q '_inflate$' "$tmp_dir/$slice-symbols.txt"
    # Deliberately omit -lz: the packaged module map must supply it.
    xcrun --sdk "$sdk" swiftc "$tmp_dir/main.swift" \
        -sdk "$sdk_path" -target "$target" \
        -module-cache-path "$tmp_dir/module-cache" \
        -I "$xcframework/$slice/Headers" -L "$xcframework/$slice" \
        -o "$tmp_dir/$slice"
    echo "Swift module autolink passed: $slice"
}

verify_slice macos-arm64 macosx arm64-apple-macos12.0
verify_slice ios-arm64 iphoneos arm64-apple-ios15.0
verify_slice ios-arm64-simulator iphonesimulator arm64-apple-ios15.0-simulator

if [ "$(uname -m)" = arm64 ]; then
    "$tmp_dir/macos-arm64"
    echo "macOS system-zlib parse passed"
fi
