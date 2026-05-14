#!/usr/bin/env python3
"""Verify 64-bit Mach-O members in a BSD ar archive are 8-byte aligned."""

from __future__ import annotations

import sys
from pathlib import Path


ARCHIVE_MAGIC = b"!<arch>\n"
HEADER_SIZE = 60
MACHO64_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"}


def parse_size(header: bytes, offset: int) -> int:
    try:
        return int(header[48:58].decode("ascii").strip())
    except ValueError as exc:
        raise SystemExit(f"invalid archive member size at offset {offset}") from exc


def verify_archive(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(ARCHIVE_MAGIC):
        raise SystemExit(f"{path}: not a BSD ar archive")

    offset = len(ARCHIVE_MAGIC)
    while offset < len(data):
        header = data[offset : offset + HEADER_SIZE]
        if len(header) != HEADER_SIZE or header[58:60] != b"`\n":
            raise SystemExit(f"{path}: invalid archive member header at offset {offset}")

        size = parse_size(header, offset)
        member_start = offset + HEADER_SIZE
        member_end = member_start + size
        if member_end > len(data):
            raise SystemExit(f"{path}: truncated archive member at offset {offset}")

        payload_offset = member_start
        name_field = header[:16]
        if name_field.startswith(b"#1/"):
            name_length = int(name_field[3:].decode("ascii").strip())
            payload_offset += name_length

        if data[payload_offset : payload_offset + 4] in MACHO64_MAGICS:
            if payload_offset % 8 != 0:
                raise SystemExit(
                    f"{path}: 64-bit Mach-O member payload at offset "
                    f"{payload_offset} is not 8-byte aligned"
                )

        offset = member_end
        if offset % 2:
            offset += 1


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: verify_macho_archive_alignment.py ARCHIVE...")

    for archive in sys.argv[1:]:
        verify_archive(Path(archive))


if __name__ == "__main__":
    main()
