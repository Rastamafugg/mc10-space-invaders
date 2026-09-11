#!/usr/bin/env python3
"""Validate the generated MC-10 cassette framing and XRoar CUE records."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"verify_c10: {message}")


def parse_block(raw: bytes, offset: int) -> tuple[int, int]:
    if raw[offset : offset + 2] != b"\x55\x3c":
        fail(f"block at {offset} has invalid leader or sync")
    block_type = raw[offset + 2]
    length = raw[offset + 3]
    end = offset + 6 + length
    if end > len(raw) or raw[end - 1] != 0x55:
        fail(f"block at {offset} has invalid length or trailing leader")
    payload = raw[offset + 4 : offset + 4 + length]
    checksum = raw[offset + 4 + length]
    expected = (block_type + length + sum(payload)) & 0xFF
    if checksum != expected:
        fail(f"block at {offset} has checksum {checksum:02x}, expected {expected:02x}")
    return block_type, end


def main() -> int:
    path = Path(sys.argv[1])
    image = path.read_bytes()
    cue_start = image.rfind(b"[CUE")
    if cue_start < 0 or image[-4:] != b"CUE]":
        fail("missing CUE trailer")
    if len(image) < cue_start + 12:
        fail("CUE trailer is truncated")
    encoded_start = struct.unpack(">I", image[-8:-4])[0]
    if encoded_start != cue_start:
        fail(f"CUE offset is {encoded_start}, expected {cue_start}")

    raw = image[:cue_start]
    offset = 0
    types: list[int] = []
    while offset < len(raw):
        if raw[offset : offset + 128] != b"\x55" * 128:
            fail(f"missing 128-byte leader at {offset}")
        offset += 128
        block_type, offset = parse_block(raw, offset)
        types.append(block_type)
    if types[:1] != [0x00] or types[-1:] != [0xFF] or 0x01 not in types:
        fail(f"unexpected block type sequence: {types}")

    cue = image[cue_start + 4 : -8]
    saw_timing = False
    data_ranges: list[tuple[int, int]] = []
    cursor = 0
    while cursor < len(cue):
        record_type = cue[cursor]
        cursor += 1
        if cursor >= len(cue):
            fail("truncated CUE record length")
        length = cue[cursor]
        cursor += 1
        payload = cue[cursor : cursor + length]
        cursor += length
        if len(payload) != length:
            fail("truncated CUE record payload")
        if record_type == 0xF0:
            if length != 4 or struct.unpack(">HH", payload) != (1200, 2400):
                fail("unexpected cassette timing record")
            saw_timing = True
        elif record_type == 0x00:
            if length != 2 or struct.unpack(">H", payload)[0] != 500:
                fail("unexpected cassette silence record")
        elif record_type == 0x0D:
            if length != 8:
                fail("unexpected CUE data record length")
            start, end = struct.unpack(">II", payload)
            if not 0 <= start < end <= len(raw):
                fail("CUE data range is outside raw cassette data")
            data_ranges.append((start, end))
        else:
            fail(f"unknown CUE record type {record_type:02x}")
    if not saw_timing or not data_ranges:
        fail("CUE records do not describe timing and data")
    print(f"verify_c10: pass ({len(raw)} raw bytes, {len(types)} blocks, {len(data_ranges)} CUE ranges)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
