#!/usr/bin/env python3
"""Create a standard MC-10 cassette image from a raw executable."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def parse_number(value: str) -> int:
    return int(value, 0)


def block(block_type: int, payload: bytes) -> bytes:
    if not 0 <= block_type <= 0xFF:
        raise ValueError("block type is outside the byte range")
    if len(payload) > 0xFF:
        raise ValueError("cassette block payload exceeds 255 bytes")
    checksum = (block_type + len(payload) + sum(payload)) & 0xFF
    return bytes((0x55, 0x3C, block_type, len(payload))) + payload + bytes((checksum, 0x55))


def add_cue_data(cue: bytearray, start: int, end: int) -> None:
    cue.extend((0x0D, 0x08))
    cue.extend(struct.pack(">II", start, end))


def add_cue_silence(cue: bytearray, milliseconds: int) -> None:
    if not 0 <= milliseconds <= 0xFFFF:
        raise ValueError("silence duration is outside the CUE format range")
    cue.extend((0x00, 0x02))
    cue.extend(struct.pack(">H", milliseconds))


def build_image(program: bytes, name: str, load_address: int, exec_address: int) -> bytes:
    if not 0 <= load_address <= 0xFFFF or not 0 <= exec_address <= 0xFFFF:
        raise ValueError("load and execution addresses must be 16-bit values")
    if not 1 <= len(name) <= 8:
        raise ValueError("cassette name must contain 1 to 8 characters")

    encoded_name = name.upper().encode("ascii")
    if any(byte < 0x20 or byte > 0x7E for byte in encoded_name):
        raise ValueError("cassette name must contain printable ASCII characters")
    filename = encoded_name.ljust(8, b" ")
    name_payload = (
        filename
        + bytes((0x02, 0x00, 0xFF))
        + struct.pack(">HH", exec_address, load_address)
    )

    segments: list[bytes] = []
    segments.append(bytes((0x55,)) * 128 + block(0x00, name_payload))
    for offset in range(0, len(program), 0xFF):
        segments.append(bytes((0x55,)) * 128 + block(0x01, program[offset : offset + 0xFF]))
    segments.append(bytes((0x55,)) * 128 + block(0xFF, b""))

    raw = bytearray()
    ranges: list[tuple[int, int]] = []
    for segment in segments:
        start = len(raw)
        raw.extend(segment)
        ranges.append((start, len(raw)))

    cue = bytearray(b"[CUE")
    # MC-10 service documentation describes 1200 Hz zeroes and 2400 Hz ones.
    cue.extend((0xF0, 0x04))
    cue.extend(struct.pack(">HH", 1200, 2400))
    for index, (start, end) in enumerate(ranges):
        add_cue_data(cue, start, end)
        if index + 1 < len(ranges):
            add_cue_silence(cue, 500)
    cue_start = len(raw)
    cue.extend(struct.pack(">I", cue_start))
    cue.extend(b"CUE]")
    return bytes(raw) + bytes(cue)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--load-address", required=True, type=parse_number)
    parser.add_argument("--exec-address", required=True, type=parse_number)
    args = parser.parse_args()

    program = args.input.read_bytes()
    if not program:
        raise SystemExit("make_c10: input program is empty")
    image = build_image(program, args.name, args.load_address, args.exec_address)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    print(
        f"make_c10: {len(program)} program bytes -> "
        f"{len(image)} cassette bytes ({args.output})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

