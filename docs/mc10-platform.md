# MC-10 platform baseline

This file is the platform baseline for the project. Addresses marked as implementation facts are taken from the MCX128 Hardware Info document, the current XRoar MC-10/MCX128 implementation, or the MC-10 service-manual memory map. Addresses marked as working assumptions require confirmation against a physical machine.

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

## MCX-128 physical map

The physical register map is documented separately in
[`docs/mcx128-register-map.md`](mcx128-register-map.md). The short form is:

- `$BF00` bit 0 (`P0`) selects the bank group for Page 0, `$0000-$3FFF` and
  `$C000-$FFFF`.
- `$BF00` bit 1 (`P1`) selects the bank group for Page 1, `$4000-$BFFF`.
- `$BF01` bits 0-1 (`M0`/`M1`) select 16K external ROM, 8K RAM plus external
  ROM, 8K RAM plus internal ROM, or 16K RAM.
- `$BF80-$BFFF` remains the base keyboard/VDG/sound I/O region, and the VDG
  reads video RAM from built-in bank 0 regardless of `P1`.

The smoke test sets `P0=1`, selects all-RAM mode, and verifies `$C000`. It does
not set `P1`, because the executable itself is loaded at `$5000` inside the
Page 1 window. XRoar models eight 16K RAM banks and the same P0/P1/map-mode
logic, but reports MC-10 support as unfinished and unsupported. Physical MCX-128
boot also requires an EPROM; the emulator cassette test uses the stock MC-10
ROM alongside the emulated RAM expansion.

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
- Verify P1 switching and `$0014` direct-page selection on physical hardware.
- Confirm the physical EPROM boot path and expanded-bank state during cassette loading.
- Determine whether the final game should use direct screen RAM, ROM character output, or custom semigraphics glyphs.
- Measure the usable frame budget at the MC6803 clock rate before committing to a game architecture.
