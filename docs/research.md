# Research and source inventory

## Sources located

- [XRoar manual: Tandy MC-10](https://www.6809.org.uk/xroar/doc/xroar.shtml) documents the `mc10` architecture, the `mcx128` cartridge profile, and `.cas`/`.c10` cassette handling. It also notes that MC-10 cassette emulation defaults to stopped because the machine has no remote motor-control line.
- [MC-10 service manual](https://colorcomputerarchive.com/repo/MC-10/Documents/Manuals/Hardware/MC-10%20Service%20Manual/ServiceManual.pdf) documents the hardware memory map, MC6803/MC6847 system, cassette block format, and the name-file fields used by `CLOADM`.
- [MC-10 review and monitor reference](https://colorcomputerarchive.com/test/repo/MC-10/Documents/Articles/MC-10%20Review%20%28Hot%20CoCo%20Sep%2783%29.pdf) provides a software-oriented memory map and ROM entry-point table, including screen memory at `$4000-$41FF`.
- [MCX-128 hardware overview](https://thezippsterzone.com/2018/05/08/mcx-128/) describes the modern 128 KiB MC-10 memory expansion and links to its hardware information.
- [MC-10 ROM disassembly](https://github.com/RevCurtisP/MC10/blob/master/disasm/MC10%20Disassembly.txt) is a candidate source for ROM routines and keyboard/cassette behavior. It is not yet imported because its assembly correctness and licensing status require review.
- [CRASM](https://github.com/colinbourassa/crasm) is the current assembler choice because it supports 6800/6801/6803 directly. [TASM6801](https://github.com/gregdionne/tasm6801) remains a possible alternative and already has MC-10 `.c10` output support.

## Current decisions

- Use direct MC6803 assembly and a raw binary as the canonical build artifact.
- Use an offline Python converter for the MC-10 cassette container so the program can be assembled by CRASM and loaded by XRoar.
- Target `$5000` for the first executable. This leaves the screen and the documented BASIC workspace below it untouched.
- Treat MCX-128 as a runtime memory provider, not as a cartridge ROM boot image. The initial test only proves the register and all-RAM path.

## Open research items

- Import and cross-check the MC-10 ROM disassembly against the service-manual ROM entry table.
- Locate surviving MC-10 assembly sources or monitor code that demonstrate timing, keyboard matrix scanning, and semigraphics rendering.
- Establish a source and license policy before copying external source into this repository.
- Compare XRoar's current MC-10 implementation with the physical schematics. XRoar itself labels MC-10 support unfinished and unsupported, so emulator success is not hardware acceptance.
