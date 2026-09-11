# Research and source inventory

## Sources located

- [Current MAME `mc10.cpp`](https://raw.githubusercontent.com/mamedev/mame/master/src/mame/trs/mc10.cpp) independently models the MC-10 keyboard matrix, active-low strobe reads, modifier-key path, MC6803 clock, and 262-line display configuration.
- [Current MAME `mc6847.cpp`](https://github.com/mamedev/mame/blob/master/src/devices/video/mc6847.cpp) documents the 228-master-clock scanline and 262-line field model, including the distinction between the datasheet's 227.5-clock nominal value and the experimentally confirmed emulator value.
- [TRS-80 MC-10 Assembly Language Programming Tutorial](https://studylib.net/doc/27362152/673589727-6803-assembly-language-programming-in-trs80-mc10) is a secondary source that gives direct keyboard-read examples and discusses MC6803 timer interrupts and the lack of an implemented IRQ1 source.
- [MC10 Keyboard Fix](https://lowlevel.ca/2021-04-09-MC10_Keyboard_Fix.html) independently quotes the ROM's modifier-key and debounce sequence.
- [MC6847 datasheet copy](https://people.ece.cornell.edu/land/courses/ece4760/ideas/mc6847.pdf) supplies the nominal NTSC field/scanline specification used to compare against MAME's timing model.
- [Redrawn MC-10 schematic](https://raw.githubusercontent.com/Danjovic/MC-10/main/MC-10%20Schematics.pdf) provides a visual wiring cross-check for the MC6847 `FS`/`HS` signals and the MC6803 interrupt and expansion nets; it is a redrawing, not a Tandy primary document.

- [XRoar manual: Tandy MC-10](https://www.6809.org.uk/xroar/doc/xroar.shtml) documents the `mc10` architecture, the `mcx128` cartridge profile, and `.cas`/`.c10` cassette handling. It also notes that MC-10 cassette emulation defaults to stopped because the machine has no remote motor-control line.
- [MC-10 service manual](https://cdn.hackaday.io/files/1837077859720288/Tandy_MC-10_Service_Manual.pdf) documents the hardware memory map, MC6803/MC6847 system, cassette block format, and the name-file fields used by `CLOADM`.
- [MC-10 review and monitor reference](https://colorcomputerarchive.com/test/repo/MC-10/Documents/Articles/MC-10%20Review%20%28Hot%20CoCo%20Sep%2783%29.pdf) provides a software-oriented memory map and ROM entry-point table, including screen memory at `$4000-$41FF`.
- [MCX-128 hardware documentation backup](https://hackaday.io/project/203205-mcx12825) provides the public download containing `MCX128 Hardware Info.pdf`. That document defines the physical `$BF00`/`$BF01` registers, page grouping, ROM modes, direct-page behavior, and EPROM boot requirement.
- The repository's local [MCX documentation set](MCX%20Documentation/) contains the `MCX128 Hardware Info`, `MCX Basic Reference`, `MCX Filing Protocol`, and `Emcee Server Guide` documents supplied for this project.
- [MCX Wares MCX128 overview](https://mcxwares.blogspot.com/2020/04/mcx128.html) independently identifies the expansion as a 128 KiB RAM and EPROM upgrade for the MC-10/Alice.
- [XRoar `mcx128.c`](https://github.com/stahta01/xroar/blob/master/src/mcx128.c) is an additional MCX-aware source. It implements eight 16 KiB RAM banks, P0/P1 page selection, `$BF00`/`$BF01`, the four map modes, `$BF80-$BFFF` I/O priority, and the fixed `$FF00-$FFFF` exception in all-RAM mode.
- [XRoar `mc10.c`](https://github.com/stahta01/xroar/blob/master/src/mc10.c) is the base-machine implementation. It confirms the MC6803/MC6847 model and explicitly labels MC-10 support unfinished and unsupported.
- [MC-10 ROM disassembly](https://github.com/RevCurtisP/MC10/blob/master/disasm/MC10%20Disassembly.txt) provides additional 6803 source evidence for internal ports, keyboard/VDG reads, and cassette routines. It predates MCX-128 and contains no MCX register definitions.
- [MC10.js](https://github.com/mtinnes/mc-10/blob/master/MC10/MC10.js) is an independent emulator source confirming the base `$4000-$41FF` video area, `$9000-$BFFF` keyboard/VDG region, and MC6803 internal register assumptions. It does not implement the physical MCX-128 map.
- [Zippster Zone: MC-10 8K internal mod](https://thezippsterzone.com/2020/06/12/mc-10-8k-internal-mod/) documents why expansion-port RAM is not VDG-visible and describes the additional internal address gating used for an 8 KiB video-RAM modification.
- [Waveguide: Expanding the TRS-80 MC-10 internal RAM](https://www.waveguide.se/?article=expanding-the-trs-80-mc-10-internal-ram) cross-checks the isolated internal RAM bus, the unused MC6847 address line, and an 8 KiB SRAM replacement approach.
- [PCBWay: MC-10 internal 8 KiB RAM upgrade](https://www.pcbway.com/project/shareproject/Matra_Alice_Tandy_TRS-80_MC-10_Internal_8KB_RAM_Upgrade_c78d2f81.html) identifies the two higher-resolution modes as requiring 6 KiB of video memory and distinguishes the internal upgrade from 4 KiB plus 16 KiB external expansion.
- [Brendan Donahe's experimental internal upgrade video](https://www.youtube.com/watch?v=usIhqL-vmS4) reports a work-in-progress 32 KiB motherboard modification with a checkpoint intended to allow both the MC6803 and MC6847 to access 16 KiB. It is a research lead, not a validated schematic or physical reference.
- [CRASM](https://github.com/colinbourassa/crasm) is the current assembler choice because it supports 6800/6801/6803 directly. [TASM6801](https://github.com/gregdionne/tasm6801) remains a possible alternative and already has MC-10 `.c10` output support.

## Register-map reconciliation

| Source | Confirmed behavior | Limit |
| --- | --- | --- |
| MCX128 Hardware Info | `$BF00` D0=`P0`, D1=`P1`; `$BF01` D0=`M0`, D1=`M1`; Page 0 is `$0000-$3FFF` plus `$C000-$FFFF`; Page 1 is `$4000-$BFFF`; four ROM/RAM modes; eight 16 KiB banks are exposed through two selectable 32 KiB groups | Physical document is the authoritative map used here, but the real board still needs electrical and software validation |
| XRoar `mcx128.c` | Eight 16 KiB RAM banks; P0/P1 select alternate groups, mapping pages 0/3 or 4/7 and 1/2 or 5/6; `$BF80-$BFFF` keeps I/O priority; reset clears selectors and map mode; all-RAM fixes the final 256-byte region | Emulator implementation is not proof of a physical board revision or timing behavior |
| MC-10 ROM disassembly | MC6803 port definitions, `$BFFF` VDG/keyboard access, cassette writer/loader routines | Stock ROM predates MCX-128, so it cannot confirm MCX registers |
| MC-10 ROM disassembly and MAME `mc10.cpp` | Port 1 `$0002` is the active-low eight-column strobe; DDR1 resets to `$FF`; DDR2 resets to `$01`; ordinary keyboard rows are low six bits of the `$BFFF` read and PA6 modifiers are carried on Port 2 bit 1 | `$BFFF` high bits and multiple-column behavior are not a safe software contract; select one column and mask `$3F` |
| MC-10 ROM disassembly | `$F879-$F8CD` scans Break, then eight columns, stores per-column state at `$4231-$4238`, and rereads after the `$421D` delay; the idle loop calls the scanner | `$421D` value `$045E` is a ROM debounce constant, not a physical timing measurement |
| Service manual and MC6847/MAME timing sources | Common `3.579545 MHz` clock, CPU E clock divided by four, VDG/CPU half-cycle sharing, 262-line NTSC field, and MAME's 228-clock line model | `59.923 Hz` and `14,934` E clocks per field are derived estimates pending hardware measurement |
| MC10.js | Independent base-machine video, keyboard/VDG, and internal-register model | No MCX-128 implementation |

The project now treats the hardware document and XRoar implementation as
agreement on the register addresses and bit meanings, while treating the ROM
disassembly and MC10.js as base-machine corroboration only.

## MCX-128 boot selection

The local `MCX Basic Reference` documents the boot behavior separately from the
MCX memory registers. An MCX Basic EPROM presents a software boot menu at
startup with these choices:

| Key | Selection | Project relevance |
| --- | --- | --- |
| `0` | Stock MicroColor Basic | Compatibility option; not the selected project configuration |
| `1` | MCX Basic, standard configuration | Uses the expanded BASIC workspace and five graphics pages |
| `2` | MCX Basic, large configuration | Selected project configuration; uses a separate BASIC workspace bank and eight graphics pages |

The selected option runs a memory test and copies the selected ROM contents
into RAM. The reference documents only a keyboard selection at startup and the
`BREAK` plus `Reset` sequence for returning to the menu. The local hardware
document does not identify a boot DIP switch, persistent selector, or software
setting that skips the menu. The boot menu is therefore an EPROM software
sequence, not a `$BF00`/`$BF01` bank-register mode.

XRoar can load a replacement 16 KiB MCX ROM with `-cart-rom`, so a direct-boot
ROM is technically possible. It must preserve the MCX memory initialization and
selected BASIC-copy path; changing only the displayed menu text is insufficient.
The project does not currently generate or ship such a patched ROM because the
internal startup paths still require validation against the physical module.
An emulator-only patched ROM or a post-selection snapshot remains the correct
future approach. It must not be treated as a physical EPROM image without
separate hardware validation.

XRoar's `-cart-autorun` applies to cartridges that implement their own
autorun behavior, while `-type` injects text into BASIC after ROM startup. The
current XRoar options therefore do not select an MCX boot-menu entry. The
project launcher accepts `MC10_MCX_ROM`; when set, it passes `-cart-rom` and
uses `-load-tape` so that the menu can be answered manually.
The installed WSLg XRoar display has been verified to render the stock BASIC
prompt and the MCX boot menu through an X11 pixel capture. With the supplied
MCX ROM, selecting `[2] MCX BASIC (LARGE)` currently blanks the display during
the memory test and returns to the boot menu, so no MCX BASIC prompt or
full-MCX `TIMER: OK` capture has been accepted yet. The stock no-cartridge
control now produces `MCX128 ERROR`, `TIMER: OK`, and an advancing frame counter,
which verifies cassette execution, timer cadence, and WSLg capture separately.
The reverse-`@` screen is the separate failure mode caused by attaching the MCX
profile without an EPROM image.

## Internal MC6847 RAM and CPU expansion RAM

The memory-size discussion must separate two buses. The service manual
describes two 2 KiB static RAM devices, 4 KiB total, shared by the MC6803 and
MC6847. The expansion connector can add CPU-addressable RAM in the `$4000`
segment, but the stock wiring isolates that RAM from the MC6847. The MC6847
has 13 display address lines, so it can address at most 8 KiB of flat display
RAM. The published 8 KiB internal modifications use the otherwise unavailable
high address line and provide enough memory for the `128x192x4` and
`256x192x2` modes, which each require 6 KiB.

The project currently has no reliable schematic or validated build that
documents a full 16 KiB internal MC6847-RAM implementation. An experimental
upgrade video reports a design intended to make 16 KiB available to both the
MC6803 and MC6847, so the possibility should remain open. However, the MC6847
address bus is only 13 bits; a 16 KiB design cannot be a flat VDG address space
and would require additional bank selection, address multiplexing, or similar
glue logic. Treat the experimental design as unverified until its schematic
and address-selection behavior are available.

The emulator options have different fidelity:

| Configuration | XRoar current source | MAME current source | Physical interpretation |
| --- | --- | --- | --- |
| Stock | `-ram 4` | `-ramsize 4K` | 4 KiB internal CPU/VDG RAM |
| Internal video-RAM mod | `-ram 8`; four 2 KiB `RAM0` banks are used by the VDG callback | `-ramsize 8K`; one flat 8 KiB RAM device is installed at `$4000` and read by the VDG callback | Emulator approximation of the published 8 KiB internal mod |
| 4 KiB plus 16 KiB expansion | `-ram 20`; 4 KiB `RAM0` plus 16 KiB `RAM1` | `-ramsize 20K`; current driver exposes one flat 20 KiB device | CPU expansion; stock physical VDG bus remains 4 KiB |
| MCX-128 | `-cart mcx128`; banked external RAM | Current source has an MCX-128 expansion device, but the installed MAME binary is older | Separate banked expansion; not an internal-RAM upgrade |

In current XRoar, `-ram 16` means 4 KiB internal plus 12 KiB external, not
16 KiB internal. In current MAME, the single flat RAM device makes its larger
options useful for emulator testing but not a faithful model of the physical
internal/external bus separation. The MCX-128 does not remove the need to
model or build the internal 8 KiB modification when higher MC6847 modes are
the target.

## Keyboard scan and frame timing

### Keyboard

The service manual's electrical description is consistent with the ROM and the
current MAME driver: write one zero to a Port 1 column line, leave the other
seven high, then read active-low row state. The current MAME matrix names the
columns PB0-PB7 and ordinary rows PA0-PA5. Control, Break, and Shift occupy PA6
and are exposed through Port 2 bit 1 when their respective columns PB0, PB2,
and PB7 are selected. The ROM reset code writes `$FF` to DDR1, `$01` to DDR2,
and `$01` to Port 2, which is the direct software baseline for a custom scan.

The safe game-level scan contract is therefore:

1. Set DDR1 to `$FF`; preserve the mixed-use Port 2 configuration unless the
   serial/cassette functions are intentionally being replaced.
2. Write one of the active-low masks `$FE`, `$FD`, `$FB`, `$F7`, `$EF`, `$DF`,
   `$BF`, or `$7F` to Port 1.
3. Read `$BFFF`, mask `$3F`, and interpret a zero bit as a pressed PA0-PA5 key.
4. Read Port 2 bit 1 separately for PA6 modifiers when scanning PB0, PB2, or
   PB7.
5. Debounce in software if a key state is used across game updates. The stock
   ROM stores one state byte per column and confirms a changed read after a
   delay.

The physical manual describes `$9000-$BFFF` as the keyboard read/VDG write
segment and uses `$BFFF` as the conventional address. Current MAME maps the
read at `$BFFF`, while XRoar models keyboard reads across the I/O segment, so
`$BFFF` is the correct portability target for this project.

### Frame timing

The MC-10's physical timing source is the 3.579545 MHz color-burst oscillator,
not a separate frame timer. The service manual states that the MC6803 divides
this by four to make E and that the VDG uses the low half of E while the CPU
uses the high half. MAME's current MC-10 driver configures a 3.579545 MHz
MC6803, the same clock for MC6847, a 262-line raster, and 243 visible lines.
MAME's MC6847 implementation documents 228 master clocks per line and 262
lines per field, while noting that the datasheet nominally says 227.5 clocks.

Using the 228-clock implementation gives this initial NTSC budget:

```text
E clock        = 3,579,545 / 4             = 894,886.25 Hz
line period    = 228 / 3,579,545           = 63.695 microseconds
field period   = 262 * 228 / 3,579,545    = 16.688 milliseconds
field rate     = 1 / field period          = 59.923 Hz
E clocks/field = 262 * 228 / 4             = 14,934
```

This is a derived emulator-aligned model. It is not yet a physical
oscilloscope measurement. The MC6847 still generates `FS` at the field boundary;
the unresolved point is whether that signal is routed into a usable MC6803
interrupt on a stock board. The stock ROM does not establish a VDG frame ISR: it
copies immediate-return handlers into `$4200`, polls the keyboard from its idle
loop, and uses the MC6803 output-compare timer for sound timing. XRoar's field
sync callback updates sound and host video presentation; it does not dispatch a
CPU frame handler. A game loop should therefore use an explicit software
cadence or a tested MC6803 timer compare, with physical timing validation before
cycle-critical animation is committed.

## Current decisions

- Use direct MC6803 assembly and a raw binary as the canonical build artifact.
- Use an offline Python converter for the MC-10 cassette container so the program can be assembled by CRASM and loaded by XRoar.
- Target `$5000` for the first executable. This leaves the screen and the documented BASIC workspace below it untouched.
- Treat MCX-128 as a runtime memory provider, not as a cartridge ROM boot image. The stock-machine launcher is the cassette/CPU control; the full emulator test attaches the `mcx128` profile with `-cart mcx128`, supplies its EPROM with `-cart-rom`, and then loads the cassette.
- When testing with the MCX EPROM image, select MCX Basic (Large) with key `2` and use `-load-tape`; do not rely on `-run` to cross the MCX boot menu.
- Test all eight selectable 16 KiB windows with distinct signatures. P0 is tested from `$5000`; a copied routine at `$D000` tests P1 without remapping the active code window.
- Use the [timer-compare cadence test](timer-compare-test.md) as the initial frame-pacing experiment: 14,934 E clocks per predicted field, 60 output compares, and a P2.0 marker for external FS capture.
- After the cadence test passes, use the same MC6803 OCF schedule as the initial game-loop driver; keep the ISR short and queue frame work for the foreground loop.

## Emulator comparison

XRoar remains the default development runner because its current source has a
dedicated MCX-128 implementation, its manual documents the built-in `mcx128`
profile, and its `-run` path attaches `.c10` images and types `CLOADM`. The MC-10
ROM then requires `EXEC` after the load completes. The source still labels
MC-10 support unfinished and unsupported, so it is not sufficient as the only
validation target.

Current [MAME MC-10 source](https://github.com/mamedev/mame/blob/master/src/mame/trs/mc10.cpp)
also exposes an `ext` expansion slot, and its dedicated
[MCX-128 device](https://github.com/mamedev/mame/blob/master/src/devices/bus/mc10/mcx128.cpp)
implements 128 KiB of RAM, 16 KiB of ROM, `$BF00`/`$BF01` control registers,
and the four map modes. A recent build can be evaluated with the equivalent
shape:

```text
mame mc10 -ext mcx128 -cass build/space-invaders.c10
```

The installed MAME binary is version 0.220 and does not expose the MCX-128
slot; use a current MAME build for this comparison. MAME is the recommended
independent cross-check, not a replacement for XRoar in the project launcher.

Other options are less suitable for this assembly project. The
[Virtual MC-10 MCX Basic notes](https://colorcomputerarchive.com/repo/MC-10/Bios/MCX%20Basic/Read%20Me.pdf)
describe broad MCX Basic compatibility, but the emulator is an older
Windows-oriented tool and is not a source-level hardware reference. The
[MC-10 JavaScript emulator](https://github.com/mtinnes/mc-10) is useful for
browser-based base-machine checks, but does not implement MCX-128 banking. The
[MicroDS emulator](https://github.com/wavemotion-dave/MicroDS) has optional
MCX-128 support, but its own notes describe the larger banked model as partial;
it is a useful secondary check rather than the primary development target.

## Open research items

- Establish a source and license policy before copying external source into this repository.
- Verify P1 switching, `$0014` direct-page selection, reset contents, and the physical EPROM boot path against a real MCX-128.
- Validate the keyboard matrix and modifier-key polarity against a physical MC-10, including the Port 2 bit-1 path.
- Measure MC6847 field sync and MC6803 timer-compare behavior on physical hardware using the [timer-compare procedure](timer-compare-test.md); use the 228-clock model as the emulator baseline.
- Compare XRoar's current MC-10 implementation with physical schematics as additional details emerge. XRoar itself labels MC-10 support unfinished and unsupported, so emulator success is not hardware acceptance.
