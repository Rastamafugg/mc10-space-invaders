# Space Invaders for the Tandy MC-10

This repository is the initial bare-metal assembly project for a Space Invaders game targeting the Tandy MC-10. It uses the Motorola MC6803 CPU, the MC6847 video display generator, and the MCX-128 memory expansion when running under XRoar.

The project layout follows the `E:\projects\ladybug` assembly-project pattern, but the CoCo 3/GIME assumptions are intentionally removed. The first milestone is a cassette-loaded executable that proves the MC6803 assembler path, MC-10 screen output, and MCX-128 register/RAM access.

## Requirements

- WSL with the `crasm` cross-assembler, which supports MC6803, and Python 3. Ubuntu provides it as the `crasm` package. Set `MC10_ASM=/path/to/crasm` when it is not in `PATH`, or run `bash scripts/bootstrap_crasm.sh` to extract the package into the ignored `.tools` directory without root access.
- XRoar with MC-10 support and an available `mc10.rom` firmware image.
- Python 3 for cassette-image generation.

The template checkout contains XRoar at `/usr/local/bin/xroar`; its lwtools assembler targets 6809/6309 and is not used for MC-10 assembly.

## Build and run

From PowerShell:

```powershell
.\space-invaders.ps1 build
.\space-invaders.ps1 run
```

The build emits:

- `build/space-invaders.bin` — raw MC6803 program.
- `build/space-invaders.c10` — MC-10 cassette image with name, data, checksum, leader, and CUE gap records.
- `build/space-invaders.lst` and `build/space-invaders.map` — assembler diagnostics.

The launcher runs the equivalent XRoar command:

```text
xroar -machine mc10 -cart mcx128 -run build/space-invaders.c10
```

`-cart mcx128` selects and attaches the built-in MCX-128 cartridge profile. The
physical expansion boots in external-ROM mode and requires a suitable EPROM;
the XRoar cassette test uses the stock MC-10 ROM plus the emulated MCX-128 RAM.

MC-10 cassette emulation starts paused because the real machine has no remote motor-control line. XRoar's `-run` path attaches the cassette and types `CLOADM`; start the tape, then type `EXEC` after the load completes. If using the graphical controls manually, start the tape after the load command appears.

Use `.\space-invaders.ps1 check` to validate tool and source prerequisites without launching the emulator. Use `.\space-invaders.ps1 clean` to remove generated artifacts.

## Current test program

`src/main.s` initializes the MC-10 alpha video mode, clears the 32×16 screen, writes a title and status line, switches MCX-128 to all-RAM mode, verifies distinct signatures through all eight selectable 16 KiB RAM windows, restores the normal map, runs the MC6803 timer-compare cadence test, and enters a timer-driven game-loop scaffold. The timer test reports `TIMER: OK` after 60 predicted MC6847 fields and toggles P2.0 for comparison with physical MC6847 FS timing. The scaffold consumes one queued tick per compare and increments a four-digit frame counter. See [the timer-compare procedure](docs/timer-compare-test.md). It is a loader/platform smoke test, not the game implementation.

## Project knowledge

- [MC-10 platform notes](docs/mc10-platform.md)
- [Physical MCX-128 register map](docs/mcx128-register-map.md)
- [Research and open questions](docs/research.md)
- [Build workflow](wiki/internal/build-workflow.html)
- [Roadmap](wiki/internal/roadmap.html)

The platform notes distinguish facts confirmed by schematics/manuals or the XRoar implementation from assumptions that require physical hardware or further source analysis.
