#!/usr/bin/env python3
"""Convert an Intel HEX image into a dense raw binary and a small map file."""

from __future__ import annotations

import argparse
from pathlib import Path


def decode(path: Path) -> tuple[dict[int, int], int | None]:
    memory: dict[int, int] = {}
    start_address: int | None = None
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"line {line_number}: not an Intel HEX record")
        record = bytes.fromhex(line[1:])
        if len(record) < 5:
            raise ValueError(f"line {line_number}: short Intel HEX record")
        length = record[0]
        address = (record[1] << 8) | record[2]
        record_type = record[3]
        data = record[4 : 4 + length]
        if len(data) != length or (sum(record) & 0xFF):
            raise ValueError(f"line {line_number}: invalid Intel HEX checksum or length")
        if record_type == 0x00:
            memory.update({address + offset: value for offset, value in enumerate(data)})
        elif record_type == 0x01:
            break
        elif record_type == 0x03 and len(data) == 4:
            start_address = (data[0] << 8) | data[1]
        elif record_type == 0x05 and len(data) == 4:
            start_address = int.from_bytes(data, "big")
    if not memory:
        raise ValueError("Intel HEX image contains no data records")
    return memory, start_address


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--map", required=True, type=Path)
    args = parser.parse_args()

    memory, start_address = decode(args.input)
    first = min(memory)
    last = max(memory)
    if any(address not in memory for address in range(first, last + 1)):
        raise SystemExit("hex_to_raw: input contains a sparse address range")
    binary = bytes(memory[address] for address in range(first, last + 1))
    args.output.write_bytes(binary)
    args.map.write_text(
        f"assembler=crasm\nstart=${first:04X}\nend=${last + 1:04X}\n"
        f"size={len(binary)}\nexec=${(start_address if start_address is not None else first):04X}\n"
    )
    print(f"hex_to_raw: ${first:04X}-${last:04X} -> {len(binary)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

