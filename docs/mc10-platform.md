# MC-10 platform baseline

This file is the platform baseline for the project. Addresses marked as implementation facts are taken from the current XRoar MC-10/MCX128 implementation or the MC-10 service-manual memory map. Addresses marked as working assumptions require confirmation against a physical machine.

## CPU and video

- CPU: Motorola MC6803. The MC6803 is not instruction-compatible with the 6809 used by the Ladybug template. The bootstrap uses the 6800/6801/6803-capable `crasm` assembler.
- VDG: Motorola MC6847.
- Text display: 32 columns by 16 rows, screen memory `$4000-$41FF`.
- The MC-10 video-mode write is exposed through the `$9000-$BFFF` I/O area. The smoke test uses `$BFFF` with `$20` to select alpha mode, matching the current XRoar implementation's D5-to-GNA mapping.

## Base memory map

| Range | Purpose | Status |
| --- | --- | --- |
| `$0000-$001F` | MC6803 internal I/O registers | service-manual fact |
| `$0080-$00FF` | MC6803 internal RAM / direct page | service-manual fact |
| `$4000-$41FF` | 32×16 screen memory | service-manual and software-reference fact |
| `$4200-$4FFF` | System variables, BASIC workspace, and stack on a 4 KiB machine | software-reference map; exact ownership is runtime-dependent |
| `$5000-$8FFF` | External RAM expansion | service-manual/software-reference map |
| `$9000-$BFFF` | Keyboard and VDG I/O slot | service-manual fact |
| `$C000-$FFFF` | ROM window; the MC-10 firmware uses 8 KiB within the decoded 16 KiB region | service-manual fact |

The initial executable loads at `$5000` so it remains outside the screen, BASIC workspace, and stack regions identified by the reference map.

## MCX-128 working map

The XRoar MCX128 model identifies two cartridge registers:

- `$BF00` — bank register. Bit 0 selects the low 16 KiB bank and bit 1 selects the upper/middle bank group.
- `$BF01` — map-mode register. Values used by the XRoar model are 0 = all ROM, 1 = external ROM plus RAM, 2 = internal ROM plus RAM, and 3 = all RAM.

The model keeps `$BF80-$BFFF` available to the base keyboard/VDG path. The smoke test writes `$03` to `$BF01`, writes `$A5` to `$8000`, verifies it, and restores map mode 0. The game runtime must not assume that this map is safe for code or data until the bank ownership plan is complete.

The MCX-128 provides 128 KiB of banked RAM in eight 16 KiB banks. Its exact physical behavior, reset contents, and interaction with a real MC-10 expansion connector remain hardware-validation items.

## Cassette loading

The generated `.c10` image contains the MC-10 standard sequence:

1. 128 bytes of `$55` leader.
2. Name-file block, type `$02` for machine language, with execution and load addresses.
3. Approximately 500 ms of CUE silence.
4. One or more data blocks, each at most 255 bytes.
5. End-of-file block, type `$FF`.

Each block has the `$55`, `$3C`, type, length, payload, checksum, `$55` framing described by the service manual. `scripts/make_c10.py` adds XRoar CUE records so the gap is represented as silence instead of data bytes.

## Unresolved platform questions

- Confirm the alpha/semigraphics mode values on physical MC-10 hardware.
- Confirm the MCX-128 bank-switch sequence and which expanded banks are visible during cassette loading.
- Determine whether the final game should use direct screen RAM, ROM character output, or custom semigraphics glyphs.
- Measure the usable frame budget at the MC6803 clock rate before committing to a game architecture.
