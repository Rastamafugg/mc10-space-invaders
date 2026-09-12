#!/usr/bin/env python3
"""Create an XRoar-only MCX direct-boot ROM image.

The input is the unmodified 16 KiB MCX BASIC 2.1 EPROM dump. The output is
not suitable for programming a physical EPROM. The default ``large`` mode
bypasses the keyboard menu while retaining the MCX firmware RAM test and
ROM-copy path. The ``stock`` mode installs a diagnostic handoff to the host
MC-10 ROM after selecting the post-menu stock map.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


ROM_SIZE = 0x4000
KNOWN_SHA256 = "2f442cd17fe90769c4edf77f3c7a323e30281339d84f45a0c5b6acaf3f6a2958"

# The MCX ROM is mapped at $C000. At $C08D the normal firmware polls the
# keyboard and leaves the selected menu value in A. Preserve the original
# Port 2 setup, then replace that poll with A=1 and branch to the common
# copy/initialisation path at $C0A2. In the firmware's selector, 0=standard
# MCX BASIC, 1=large MCX BASIC, and 2=stock MicroColor BASIC. The remaining
# bytes are NOPs in the unused poll span.
PATCH_OFFSET = 0x008D
ORIGINAL = bytes.fromhex(
    "CC FE 10 97 02 0D 4C F5 BF FF 27 05 79 00 02 25 F5 81 02 2C EB"
)
PATCHED = bytes.fromhex("CC FE 10 97 02 86 01 20 0C") + bytes([0x01]) * 12

# The stock-mode diagnostic cannot use the MCX firmware's normal copy path in
# the current XRoar MCX implementation. Start from the external EPROM reset
# vector, copy a small handoff into external RAM at $D020, select M=2, and
# continue at the stock MC-10 reset entry in the internal ROM. The copied
# handoff is required because $D000-$DFFF changes from EPROM to RAM when M=2.
STOCK_BOOTSTRAP_OFFSET = 0x1000  # $D000
STOCK_TARGET_OFFSET = 0x1020  # $D020
STOCK_RESET_VECTOR_OFFSET = 0x3FFE  # $FFFE
STOCK_BOOTSTRAP = bytes.fromhex(
    "8E D0 1F CE D0 20 C6 0D 32 A7 00 08 5A 26 F9 7E D0 20"
)
STOCK_TARGET = bytes.fromhex(
    "86 00 B7 BF 00 86 02 B7 BF 01 7E F7 2E"
)


def _validate_input(raw: bytes) -> None:
    if len(raw) != ROM_SIZE:
        raise ValueError(f"input must be exactly {ROM_SIZE} bytes, got {len(raw)}")

    digest = hashlib.sha256(raw).hexdigest()
    if digest != KNOWN_SHA256:
        raise ValueError(
            "input is not the supported MCX BASIC 2.1 ROM dump "
            f"(sha256 {KNOWN_SHA256}, got {digest})"
        )


def patch_image(raw: bytes, mode: str = "large") -> bytes:
    _validate_input(raw)

    if mode == "stock":
        image = bytearray(raw)
        image[STOCK_BOOTSTRAP_OFFSET : STOCK_BOOTSTRAP_OFFSET + len(STOCK_BOOTSTRAP)] = STOCK_BOOTSTRAP
        image[STOCK_TARGET_OFFSET : STOCK_TARGET_OFFSET + len(STOCK_TARGET)] = STOCK_TARGET
        image[STOCK_RESET_VECTOR_OFFSET : STOCK_RESET_VECTOR_OFFSET + 2] = bytes.fromhex("D0 00")
        return bytes(image)

    if mode != "large":
        raise ValueError(f"unsupported boot mode: {mode}")

    current = raw[PATCH_OFFSET : PATCH_OFFSET + len(ORIGINAL)]
    if current != ORIGINAL:
        raise ValueError("input ROM does not contain the expected boot selector")

    image = bytearray(raw)
    image[PATCH_OFFSET : PATCH_OFFSET + len(PATCHED)] = PATCHED
    return bytes(image)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="original 16 KiB ROM")
    parser.add_argument("--output", required=True, type=Path, help="generated XRoar ROM")
    parser.add_argument(
        "--mode",
        choices=("large", "stock"),
        default="large",
        help="direct-boot target: MCX BASIC (LARGE) or stock MC-10 BASIC",
    )
    args = parser.parse_args()

    try:
        output = patch_image(args.input.read_bytes(), args.mode)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"patch_mcx128_rom: {exc}") from exc

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    print(
        f"patch_mcx128_rom: {args.mode} direct-boot image written "
        f"to {args.output} ({len(output)} bytes)"
    )
    print(f"patch_mcx128_rom: output sha256 {hashlib.sha256(output).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
