#!/usr/bin/env python3
"""Repair BSD ar archives so 64-bit Mach-O member payloads are 8-byte aligned."""

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


def format_extended_name_size(size: int) -> bytes:
    value = f"#1/{size}".encode("ascii")
    if len(value) > 16:
        raise SystemExit("extended archive member name is too large")
    return value.ljust(16)


def format_size(size: int) -> bytes:
    value = str(size).encode("ascii")
    if len(value) > 10:
        raise SystemExit("archive member is too large")
    return value.rjust(10)


def regular_member_name(name_field: bytes) -> bytes:
    name = name_field.rstrip()
    if name.endswith(b"/"):
        name = name[:-1]
    if not name:
        raise SystemExit("cannot convert empty archive member name")
    return name + b"\0"


def repair_archive(data: bytes) -> bytes:
    if not data.startswith(ARCHIVE_MAGIC):
        raise SystemExit("not a BSD ar archive")

    output = bytearray(ARCHIVE_MAGIC)
    offset = len(ARCHIVE_MAGIC)

    while offset < len(data):
        header = bytearray(data[offset : offset + HEADER_SIZE])
        if len(header) != HEADER_SIZE or header[58:60] != b"`\n":
            raise SystemExit(f"invalid archive member header at offset {offset}")

        size = parse_size(header, offset)
        member_start = offset + HEADER_SIZE
        member_end = member_start + size
        member = bytearray(data[member_start:member_end])
        if len(member) != size:
            raise SystemExit(f"truncated archive member at offset {offset}")

        name_field = bytes(header[:16])
        extended_name_len = 0
        payload = member
        payload_offset = len(output) + HEADER_SIZE

        if name_field.startswith(b"#1/"):
            extended_name_len = int(name_field[3:].decode("ascii").strip())
            payload = member[extended_name_len:]
            payload_offset += extended_name_len

            if bytes(payload[:4]) in MACHO64_MAGICS and payload_offset % 8:
                padding = (-payload_offset) % 8
                extended_name_len += padding
                header[:16] = format_extended_name_size(extended_name_len)
                header[48:58] = format_size(size + padding)
                member = (
                    member[: extended_name_len - padding]
                    + bytearray(padding)
                    + payload
                )
        elif bytes(payload[:4]) in MACHO64_MAGICS and payload_offset % 8:
            name = regular_member_name(name_field)
            padding = (-(len(output) + HEADER_SIZE + len(name))) % 8
            extended_name_len = len(name) + padding
            header[:16] = format_extended_name_size(extended_name_len)
            header[48:58] = format_size(size + extended_name_len)
            member = name + bytearray(padding) + payload

        output.extend(header)
        output.extend(member)
        if len(output) % 2:
            output.append(0x0A)

        offset = member_end
        if offset % 2:
            offset += 1

    return bytes(output)


def verify_archive(data: bytes) -> None:
    offset = len(ARCHIVE_MAGIC)
    while offset < len(data):
        header = data[offset : offset + HEADER_SIZE]
        size = parse_size(header, offset)
        name_field = header[:16]
        member_start = offset + HEADER_SIZE
        payload_offset = member_start

        if name_field.startswith(b"#1/"):
            payload_offset += int(name_field[3:].decode("ascii").strip())

        if data[payload_offset : payload_offset + 4] in MACHO64_MAGICS:
            if payload_offset % 8:
                raise SystemExit(
                    f"64-bit Mach-O member at offset {payload_offset} is not 8-byte aligned"
                )

        offset = member_start + size
        if offset % 2:
            offset += 1


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: align_macho_archive.py ARCHIVE")

    archive = Path(sys.argv[1])
    repaired = repair_archive(archive.read_bytes())
    verify_archive(repaired)
    archive.write_bytes(repaired)


if __name__ == "__main__":
    main()
