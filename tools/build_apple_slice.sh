#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: build_apple_slice.sh ZIG SDK [BUILD_OPTIONS...]" >&2
    exit 2
fi

# Resolve the SDK only when an Apple packaging step actually runs. A normal
# portable build must not require Xcode or invoke SDK discovery.
zig_exe=$1
sdk_name=$2
shift 2

sdk_path=$(xcrun --sdk "$sdk_name" --show-sdk-path)
exec "$zig_exe" build --sysroot "$sdk_path" "$@"
