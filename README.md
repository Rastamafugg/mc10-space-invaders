# Space Invaders for the Tandy MC-10

This repository is the initial bare-metal assembly project for a Space Invaders game targeting the Tandy MC-10. It uses the Motorola MC6803 CPU, the MC6847 video display generator, and the MCX-128 memory expansion when running under XRoar.

The project layout follows the `E:\projects\ladybug` assembly-project pattern, but the CoCo 3/GIME assumptions are intentionally removed. The first milestone is a cassette-loaded executable that proves the MC6803 assembler path, MC-10 screen output, and MCX-128 register/RAM access.

## Requirements

- WSL with the `crasm` cross-assembler, which supports MC6803, and Python 3. Ubuntu provides it as the `crasm` package. Set `MC10_ASM=/path/to/crasm` when it is not in `PATH`, or run `bash scripts/bootstrap_crasm.sh` to extract the package into the ignored `.tools` directory without root access.
- XRoar with MC-10 support and an available `mc10.rom` firmware image.
- Python 3 for cassette-image generation.

An MCX-128 EPROM image is required for the physical module and for an XRoar
run that exercises the MCX Basic boot menu. Do not commit that image. Set
`MC10_MCX_ROM` to its Windows or WSL path when using it with the launcher.
The repository also provides an emulator-only direct-boot patch for the
supported MCX BASIC 2.1 dump; it generates a separate ROM and never modifies
the source image.

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

Without an MCX EPROM path, the launcher runs a stock-machine cassette control
using the equivalent XRoar command:

```text
xroar -machine mc10 -run build/space-invaders.c10
```

`-cart mcx128` selects and attaches the built-in MCX-128 cartridge profile. An
MCX-128 cartridge without `-cart-rom` starts with an unpopulated external ROM
slot; under XRoar this produces the reverse-`@` screen rather than a usable
boot. The launcher therefore omits the cartridge unless `MC10_MCX_ROM` is
supplied. The stock-machine run is a cassette/CPU control test and is expected
to report `MCX128 ERROR` because no MCX bank hardware is attached. It now
continues to the independent timer diagnostic, so `TIMER: OK` in this mode
validates cassette execution and timer cadence only, not MCX banking.

Do not treat the generic RAM-size options as interchangeable physical upgrades.
The stock MC-10 has 4 KiB of internal RAM on the shared CPU/MC6847 bus. The
external expansion bus adds CPU-visible RAM, but does not automatically add
address space to the stock MC6847 video bus. XRoar models `-ram 8` as 8 KiB of
internal RAM and its VDG fetch path reads that RAM, making it the closest
emulator profile for the published 8 KiB internal modification. XRoar's
`-ram 16` and `-ram 20` retain 4 KiB internal RAM and add external RAM; `-ram
20` is the usual 4 KiB plus 16 KiB expansion configuration. MAME's `-ramsize`
choices are documented separately in [the platform research](docs/research.md)
because its current MC-10 driver presents one flat RAM device to the CPU and
MC6847 rather than modeling the physical bus split. The MCX-128 remains a
separate banked expansion.

With `-load-tape`, MC-10 cassette emulation starts paused because the real
machine has no remote motor-control line. XRoar's `-run` path queues `CLOADM`
and uses its MC-10 ROM hook to activate Play automatically; the command may no
longer be visible once submitted. The MCX-128 is only the RAM expansion in the
full MCX setup. See [the exact cassette sequence](docs/timer-compare-test.md#exact-xroar-cassette-sequence) for the manual path.

When `MC10_MCX_ROM` is set, the launcher uses `-load-tape` instead of `-run`.
The MCX EPROM presents its boot menu before BASIC is available, so select
`[2] MCX BASIC (LARGE)` first. Then enter `CLOADM`, start the cassette manually,
and enter `EXEC` after the load completes. The complete sequence is documented
in [the timer-compare procedure](docs/timer-compare-test.md#mcx-128-boot-selection).

For the XRoar-only direct path, generate a patched copy from the original ROM
and point the launcher at that copy:

```text
wsl python3 scripts/patch_mcx128_rom.py \
  --input /home/USER/.xroar/roms/mcx128bas.rom \
  --output build/mcx128bas-large-direct.rom
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128bas-large-direct.rom'
.\space-invaders.ps1 run
```

The patch forces the firmware's internal selector value for `[2] MCX BASIC
(LARGE)`, but retains the firmware memory test and ROM-copy initialization.
`MC10_MCX_DIRECT_ROM` makes the launcher use `-load-tape` and queue `CLOADM`.
After the prompt, open XRoar cassette controls with `Ctrl+T`, press `Play`,
wait for the tape to stop, and enter `EXEC`. XRoar's generic `-run` path queues
`CLOADM:EXEC`, which MCX BASIC reports as a syntax error. This image is for
emulation only and must not be programmed into a physical MCX EPROM.

The installed WSLg XRoar build renders the MCX boot menu, but the large-mode
selection currently returns to that menu after its blank memory-test interval.
That behavior applies to the original EPROM image. The generated
`MC10_MCX_DIRECT_ROM` image reaches the MCX BASIC prompt without menu input;
see [the direct-boot procedure](docs/mcx-direct-boot.md).

To isolate stock MC-10 BASIC cassette behavior while retaining the MCX
cartridge mapping, generate the stock-mode diagnostic image:

```text
wsl python3 scripts/patch_mcx128_rom.py \
  --input build/mcx128.rom \
  --output build/mcx128-stock-direct.rom \
  --mode stock
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128-stock-direct.rom'
$env:MC10_MCX_DIRECT_MODE = 'stock'
.\space-invaders.ps1 run
```

This emulator-only image forces `P0=0`, `P1=0`, and `$BF01=2`, then enters the
host stock MC-10 ROM at `$F72E`. It bypasses the physical MCX boot menu and
must not be programmed into an EPROM. Stock mode defaults to the manual
`CLOADM`, cassette `Play`, and `EXEC` sequence because the installed XRoar
binary bypasses the MCX cartridge during its auto-keyboard return hook. The
source fix and optional automatic path are documented in [the XRoar
auto-keyboard notes](docs/xroar-auto-keyboard.md).

Use `.\space-invaders.ps1 check` to validate tool and source prerequisites without launching the emulator. Use `.\space-invaders.ps1 clean` to remove generated artifacts.

## Current test program

`src/main.s` initializes the MC-10 alpha video mode, clears the 32×16 screen, writes a title and status line, switches MCX-128 to all-RAM mode, verifies distinct signatures through all eight selectable 16 KiB RAM windows, restores the normal map, runs the MC6803 timer-compare cadence test, and enters a timer-driven game-loop scaffold. The timer test reports `TIMER: OK` after 60 predicted MC6847 fields and toggles P2.0 for comparison with physical MC6847 FS timing. The scaffold consumes one queued tick per compare and increments a four-digit frame counter. See [the timer-compare procedure](docs/timer-compare-test.md). It is a loader/platform smoke test, not the game implementation.

## Project knowledge

- [MC-10 platform notes](docs/mc10-platform.md)
- [Physical MCX-128 register map](docs/mcx128-register-map.md)
- [XRoar MCX BASIC (LARGE) direct boot](docs/mcx-direct-boot.md)
- [Research and open questions](docs/research.md)
- [Build workflow](wiki/internal/build-workflow.html)
- [Roadmap](wiki/internal/roadmap.html)

The platform notes distinguish facts confirmed by schematics/manuals or the XRoar implementation from assumptions that require physical hardware or further source analysis.
