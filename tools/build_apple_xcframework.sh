#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
libsvga_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
workspace_root="$(CDPATH= cd -- "$libsvga_root/.." && pwd)"

output="${1:-$workspace_root/SVGAPlayerSwift/Binaries/libsvga-static.xcframework}"
build_root="${LIBSVGA_APPLE_BUILD_DIR:-$libsvga_root/zig-out/apple}"
cache_dir="${ZIG_GLOBAL_CACHE_DIR:-/tmp/zig-global-cache}"
optimize="${LIBSVGA_OPTIMIZE:-ReleaseFast}"
macos_min_version="${MACOS_MIN_VERSION:-10.15}"
ios_min_version="${IOS_MIN_VERSION:-13.0}"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
iphonesimulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

build_slice() {
    name="$1"
    target="$2"
    sdk="$3"
    prefix="$build_root/$name"

    rm -rf "$prefix"
    cd "$libsvga_root"
    ZIG_GLOBAL_CACHE_DIR="$cache_dir" zig build \
        -Dtarget="$target" \
        -Doptimize="$optimize" \
        --search-prefix "$sdk/usr" \
        -p "$prefix"
    cp "$libsvga_root/include/module.modulemap" "$prefix/include/module.modulemap"
}

mkdir -p "$build_root"

build_slice "macos-arm64" "aarch64-macos.$macos_min_version" "$macos_sdk"
build_slice "ios-arm64" "aarch64-ios.$ios_min_version" "$iphoneos_sdk"
build_slice "ios-simulator-arm64" "aarch64-ios.$ios_min_version-simulator" "$iphonesimulator_sdk"

rm -rf "$output"
mkdir -p "$(dirname -- "$output")"
xcodebuild -create-xcframework \
    -library "$build_root/macos-arm64/lib/libsvga.a" \
    -headers "$build_root/macos-arm64/include" \
    -library "$build_root/ios-arm64/lib/libsvga.a" \
    -headers "$build_root/ios-arm64/include" \
    -library "$build_root/ios-simulator-arm64/lib/libsvga.a" \
    -headers "$build_root/ios-simulator-arm64/include" \
    -output "$output"
