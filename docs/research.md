# Research and source inventory

## Sources located

- [XRoar manual: Tandy MC-10](https://www.6809.org.uk/xroar/doc/xroar.shtml) documents the `mc10` architecture, the `mcx128` cartridge profile, and `.cas`/`.c10` cassette handling. It also notes that MC-10 cassette emulation defaults to stopped because the machine has no remote motor-control line.
- [MC-10 service manual](https://cdn.hackaday.io/files/1837077859720288/Tandy_MC-10_Service_Manual.pdf) documents the hardware memory map, MC6803/MC6847 system, cassette block format, and the name-file fields used by `CLOADM`.
- [MC-10 review and monitor reference](https://colorcomputerarchive.com/test/repo/MC-10/Documents/Articles/MC-10%20Review%20%28Hot%20CoCo%20Sep%2783%29.pdf) provides a software-oriented memory map and ROM entry-point table, including screen memory at `$4000-$41FF`.
- [MCX-128 hardware documentation backup](https://hackaday.io/project/203205-mcx12825) provides the public download containing `MCX128 Hardware Info.pdf`. That document defines the physical `$BF00`/`$BF01` registers, page grouping, ROM modes, direct-page behavior, and EPROM boot requirement.
- [MCX Wares MCX128 overview](https://mcxwares.blogspot.com/2020/04/mcx128.html) independently identifies the expansion as a 128 KiB RAM and EPROM upgrade for the MC-10/Alice.
- [XRoar `mcx128.c`](https://github.com/stahta01/xroar/blob/master/src/mcx128.c) is an additional MCX-aware source. It implements eight 16 KiB RAM banks, P0/P1 page selection, `$BF00`/`$BF01`, the four map modes, `$BF80-$BFFF` I/O priority, and the fixed `$FF00-$FFFF` exception in all-RAM mode.
- [XRoar `mc10.c`](https://github.com/stahta01/xroar/blob/master/src/mc10.c) is the base-machine implementation. It confirms the MC6803/MC6847 model and explicitly labels MC-10 support unfinished and unsupported.
- [MC-10 ROM disassembly](https://github.com/RevCurtisP/MC10/blob/master/disasm/MC10%20Disassembly.txt) provides additional 6803 source evidence for internal ports, keyboard/VDG reads, and cassette routines. It predates MCX-128 and contains no MCX register definitions.
- [MC10.js](https://github.com/mtinnes/mc-10/blob/master/MC10/MC10.js) is an independent emulator source confirming the base `$4000-$41FF` video area, `$9000-$BFFF` keyboard/VDG region, and MC6803 internal register assumptions. It does not implement the physical MCX-128 map.
- [CRASM](https://github.com/colinbourassa/crasm) is the current assembler choice because it supports 6800/6801/6803 directly. [TASM6801](https://github.com/gregdionne/tasm6801) remains a possible alternative and already has MC-10 `.c10` output support.

## Register-map reconciliation

| Source | Confirmed behavior | Limit |
| --- | --- | --- |
| MCX128 Hardware Info | `$BF00` D0=`P0`, D1=`P1`; `$BF01` D0=`M0`, D1=`M1`; Page 0 is `$0000-$3FFF` plus `$C000-$FFFF`; Page 1 is `$4000-$BFFF`; four ROM/RAM modes; eight 16 KiB banks are exposed through two selectable 32 KiB groups | Physical document is the authoritative map used here, but the real board still needs electrical and software validation |
| XRoar `mcx128.c` | Eight 16 KiB RAM banks; P0/P1 select alternate groups, mapping pages 0/3 or 4/7 and 1/2 or 5/6; `$BF80-$BFFF` keeps I/O priority; reset clears selectors and map mode; all-RAM fixes the final 256-byte region | Emulator implementation is not proof of a physical board revision or timing behavior |
| MC-10 ROM disassembly | MC6803 port definitions, `$BFFF` VDG/keyboard access, cassette writer/loader routines | Stock ROM predates MCX-128, so it cannot confirm MCX registers |
| MC10.js | Independent base-machine video, keyboard/VDG, and internal-register model | No MCX-128 implementation |

The project now treats the hardware document and XRoar implementation as
agreement on the register addresses and bit meanings, while treating the ROM
disassembly and MC10.js as base-machine corroboration only.

## Current decisions

- Use direct MC6803 assembly and a raw binary as the canonical build artifact.
- Use an offline Python converter for the MC-10 cassette container so the program can be assembled by CRASM and loaded by XRoar.
- Target `$5000` for the first executable. This leaves the screen and the documented BASIC workspace below it untouched.
- Treat MCX-128 as a runtime memory provider, not as a cartridge ROM boot image. The emulator test attaches the `mcx128` profile with `-cart mcx128`, then loads the cassette using the stock MC-10 ROM.
- Test all eight selectable 16 KiB windows with distinct signatures. P0 is tested from `$5000`; a copied routine at `$D000` tests P1 without remapping the active code window.

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
- Locate surviving MC-10 assembly sources or monitor code that demonstrate timing, keyboard matrix scanning, and semigraphics rendering.
- Compare XRoar's current MC-10 implementation with physical schematics as additional details emerge. XRoar itself labels MC-10 support unfinished and unsupported, so emulator success is not hardware acceptance.
