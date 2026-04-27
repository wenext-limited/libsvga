#!/bin/sh
set -eu

archive="$1"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/libsvga-rearchive.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"
for member in $(/usr/bin/ar -t "$archive" | grep '\.o$'); do
    /usr/bin/ar -p "$archive" "$member" > "$member"
done
/usr/bin/ar -rcs "$archive" ./*.o
