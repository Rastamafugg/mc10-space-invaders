# MC-10 platform baseline

This file is the platform baseline for the project. Addresses marked as implementation facts are taken from the MCX128 Hardware Info document, the current XRoar MC-10/MCX128 implementation, or the MC-10 service-manual memory map. Addresses marked as working assumptions require confirmation against a physical machine.

## CPU and video

- CPU: Motorola MC6803. The MC6803 is not instruction-compatible with the 6809 used by the Ladybug template. The bootstrap uses the 6800/6801/6803-capable `crasm` assembler.
- VDG: Motorola MC6847.
- Text display: 32 columns by 16 rows, screen memory `$4000-$41FF`.
- The MC-10 video-mode write is exposed through the `$9000-$BFFF` I/O area. The smoke test uses `$BFFF` with `$20` to select alpha mode, matching the current XRoar implementation's D5-to-GNA mapping.

## Internal video RAM versus expansion RAM

The stock machine has two 2 KiB static RAM devices, for 4 KiB total. They are
on the internal RAM bus shared by the MC6803 and MC6847. The MC6847 receives
its display addresses through that bus; the RAM supplied through the MC-10
expansion connector is a separate CPU address-space resource and is not
automatically visible to the VDG. This is why a normal 4 KiB plus 16 KiB
expansion can provide CPU workspace without enabling the MC6847's two higher
resolution colour modes.

Published 8 KiB internal modifications add the missing MC6847 address bit and
another 4 KiB of RAM, commonly by replacing or piggybacking the original RAM
and changing the address gating. This supplies the 6 KiB required by the
`128x192x4` and `256x192x2` modes. The MC6847 has 13 display address lines, so
its flat display address space is at most 8 KiB.

No reliable schematic or validated build in the project currently documents a
16 KiB internal MC6847-RAM implementation. A [2023 experimental internal
upgrade project](https://www.youtube.com/watch?v=usIhqL-vmS4) reports a
checkpoint intended to make 16 KiB available to both the MC6803 and MC6847, but
it is not yet a hardware reference for this project. Because the MC6847 has
only 13 display address lines, such a design cannot be a flat 16 KiB VDG
address space; it must add bank selection, address multiplexing, or equivalent
glue logic. The documented 8 KiB modification and the MCX-128 expansion are
therefore separate, confirmed hardware cases.

## Keyboard scanning

The keyboard is an active-low matrix. Port 1 supplies eight column/strobe
outputs and the keyboard returns six ordinary row bits through the `$9000-$BFFF`
read slot. The three modifier keys that occupy the seventh row are returned on
Port 2 bit 1 instead of the ordinary row read. The service manual describes the
electrical scan rule; the current [MAME MC-10 driver](https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/mc10.cpp)
and the [stock ROM disassembly](https://raw.githubusercontent.com/RevCurtisP/MC10/master/disasm/MC10%20Disassembly.txt)
provide the matrix and software details.

| MC6803 register | Address | Use | Reset/reference value |
| --- | ---: | --- | ---: |
| DDR1 | `$0000` | Port 1 direction; keyboard strobe lines | `$FF` |
| DDR2 | `$0001` | Port 2 direction; bit 0 output, keyboard/miscellaneous inputs | `$01` |
| PORT1 | `$0002` | Active-low column select | one low bit |
| PORT2 | `$0003` | Port 2 input; bit 1 carries PA6 modifier state | `$01` written at reset |

Use one low bit in `PORT1` at a time: `$FE`, `$FD`, `$FB`, `$F7`, `$EF`,
`$DF`, `$BF`, and `$7F` select PB0 through PB7. Read `$BFFF` and mask with
`$3F`; a cleared bit means that the corresponding PA0-PA5 row is pressed.
Read `PORT2` and test bit 1 separately for Control, Break, and Shift. The
physical manual recommends one selected column. MAME additionally models the
electrical result of multiple selected columns as an AND, but that is not a
software contract to depend on.

The matrix reproduced by the current MAME source is:

| Row | PB0 | PB1 | PB2 | PB3 | PB4 | PB5 | PB6 | PB7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PA6 | Ctrl | — | Break | — | — | — | — | Shift |
| PA5 | 8 | 9 | `:` | `;` | `,` | `-` | `.` | `/` |
| PA4 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| PA3 | X | Y | Z | — | — | — | Enter | Space |
| PA2 | P | Q | R | S | T | U | V | W |
| PA1 | H | I | J | K | L | M | N | O |
| PA0 | `@` | A | B | C | D | E | F | G |

The ROM routine at `$F879-$F8CD` checks Break first, scans all eight columns,
stores one byte per column at `$4231-$4238`, and performs a second read after
the `$421D` debounce delay before accepting a change. The initial ROM value is
`$045E`; it is a software debounce constant, not a measured keyboard response
time. The ROM's idle loop polls this routine, so a game can use a smaller
purpose-built scan when it only needs directional or fire keys.

## Frame timing and CPU synchronization

The service manual identifies a common `3.579545 MHz` oscillator, divides it by
four for the MC6803 E clock, and states that the VDG owns the low half of E while
the CPU uses the high half. The MC6847 datasheet describes a 262-line NTSC
field. Current [MAME MC6847 timing code](https://github.com/mamedev/mame/blob/master/src/devices/video/mc6847.cpp)
uses 228 master-clock periods per line based on the datasheet and hardware
experimentation; its [MC-10 driver](https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/mc10.cpp)
configures the same crystal, a 262-line raster, and 243 visible lines.

| Quantity | Calculation | Initial NTSC model |
| --- | --- | ---: |
| MC6803 E clock | `3,579,545 / 4` | `894,886.25 Hz` |
| Horizontal period | `228 / 3,579,545` | `63.695 µs` |
| Field period | `262 × 228 / 3,579,545` | `16.688 ms` |
| Field rate | inverse field period | `59.923 Hz` |
| E-clock periods per field | `262 × 228 / 4` | `14,934` |

These are derived budget figures, not a claim that the physical machine has
been measured. The datasheet gives 227.5 clocks as a nominal scanline, while
the current MAME implementation documents 228 as the experimentally confirmed
value. Use 228 for emulator pacing and retain a physical capture or oscilloscope
check as the acceptance test.

The MC6847 does have an `FS` field-sync output. In this document, “no VDG-to-CPU
frame interrupt” means that no verified connection from `FS` to an MC6803 IRQ or
NMI source has been identified in the sources reviewed. The ROM initializes the
copied interrupt entries at `$4200` to return immediately,
uses the MC6803 output-compare timer for sound timing, and polls the keyboard in
its idle path. XRoar's MC-10 implementation receives VDG field-sync callbacks
for sound and video presentation, not as a CPU interrupt. Therefore the game
loop should initially use an explicit software cadence or a tested MC6803 timer
compare; it should not assume that MC6847 field sync invokes a handler.

The current executable includes a [timer-compare cadence test](timer-compare-test.md).
It schedules 60 output compares at `$3A56` E clocks, displays the result, and
toggles P2.0 for external comparison with the MC6847 `FS` signal. On success,
the same compare schedule is re-armed and drives the game-loop scaffold one
queued update per predicted field. This verifies timer-driven cadence, while an
oscilloscope or logic analyzer is still required to verify the phase relationship
to physical `FS`.

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

- `$BF00` bit 0 (`P0`) selects between two 32K bank groups for Page 0,
  `$0000-$3FFF` and `$C000-$FFFF`.
- `$BF00` bit 1 (`P1`) selects between two 32K bank groups for Page 1,
  `$4000-$BFFF`.
- Under XRoar's internal bank-page numbering, the four visible 16K CPU
  windows map to eight physical 16K banks: P0 uses banks 0/4 and 3/7, while
  P1 uses banks 1/5 and 2/6. Other emulators may number the backing pages
  differently; the software contract is the P0/P1 window behavior.
- `$BF01` bits 0-1 (`M0`/`M1`) select 16K external ROM, 8K RAM plus external
  ROM, 8K RAM plus internal ROM, or 16K RAM.
- `$BF80-$BFFF` remains the base keyboard/VDG/sound I/O region. On the physical
  stock machine, the VDG reads the internal RAM bus; changing an MCX CPU-bank
  selector does not by itself make external expansion RAM VDG-visible.

The smoke test selects all-RAM mode and verifies distinct signatures through
the four P0/P1 window pairs, covering all eight selectable 16K RAM banks. The
P1 portion is copied to `$D000` before P1 is changed, because the executable
itself is loaded at `$5000` inside the Page 1 window. XRoar models eight 16K
RAM banks and the same P0/P1/map-mode logic, but reports MC-10 support as
unfinished and unsupported. Physical MCX-128 boot also requires an EPROM; the
emulator cassette test uses the stock MC-10 ROM alongside the emulated RAM
expansion. In current XRoar, the MC-10 VDG callback reads `RAM0`, while the
MCX external memory is `RAM1`; therefore `-ram 8` is an emulator approximation
of the internal 8 KiB modification, whereas `-ram 20` is the stock 4 KiB
internal plus 16 KiB external arrangement.

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
- Validate the keyboard matrix polarity and modifier-key path on physical hardware.
- Measure frame-sync and timer-compare behavior on physical hardware using the [timer-compare procedure](timer-compare-test.md); the figures above are the initial NTSC timing model.
