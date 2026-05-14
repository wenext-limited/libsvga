#!/bin/sh
set -eu

archive="$1"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/libsvga-rearchive.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
if command -v xcrun >/dev/null 2>&1; then
    ar_tool="$(xcrun --find ar)"
    libtool="$(xcrun --find libtool)"
    ranlib_tool="$(xcrun --find ranlib)"
else
    ar_tool="/usr/bin/ar"
    libtool="/usr/bin/libtool"
    ranlib_tool="/usr/bin/ranlib"
fi

cd "$tmp_dir"
members="$("$ar_tool" -t "$archive" | grep '\.o$' || true)"
if [ -z "$members" ]; then
    exit 0
fi

for member in $members; do
    "$ar_tool" -p "$archive" "$member" > "$member"
done
# Apple libtool writes the padding Xcode expects for 64-bit Mach-O members.
"$libtool" -static -o "$archive" ./*.o
# Older cctools can still leave the symbol table too short; ranlib rewrites it
# with padding that keeps following 64-bit Mach-O members 8-byte aligned.
"$ranlib_tool" "$archive"
