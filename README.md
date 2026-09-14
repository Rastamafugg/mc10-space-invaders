# Space Invaders for the Tandy MC-10

This repository is the initial bare-metal assembly project for a Space Invaders game targeting the Tandy MC-10. It uses the Motorola MC6803 CPU, the MC6847 video display generator, and the MCX-128 memory expansion when running under XRoar.

The project layout follows the `E:\projects\ladybug` assembly-project pattern, but the CoCo 3/GIME assumptions are intentionally removed. The first milestone is a cassette-loaded executable that proves the MC6803 assembler path, MC-10 screen output, and MCX-128 register/RAM access.

Persistent operational notes are in the [project wiki](wiki/Home.md), including
the XRoar and MAME cassette sequences, WSLg/CU limitations, and command-injection
lessons discovered during emulator testing.

## Requirements

- WSL with the `crasm` cross-assembler, which supports MC6803, and Python 3. Ubuntu provides it as the `crasm` package. Set `MC10_ASM=/path/to/crasm` when it is not in `PATH`, or run `bash scripts/bootstrap_crasm.sh` to extract the package into the ignored `.tools` directory without root access.
- XRoar with MC-10 support and an available `mc10.rom` firmware image.
- MAME 0.289 or newer for the permanent Lua cassette and pixel harness. The
  verified local binary is MAME 0.289.
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

The diagnostic utility is a separate target:

```powershell
.\space-invaders.ps1 utility
.\space-invaders.ps1 utility-run
```

The live field-timing calibrator is also separate:

```powershell
.\space-invaders.ps1 calibrator
.\space-invaders.ps1 calibrator-run
```

It displays the compare period, signed phase, and event count in its alpha
diagnostic mode, and toggles P2.0 for external comparison with MC6847 FS. It
does not require an MCX-128 ROM. The default screen is a blue CG3 surface with
a full-width green band. Use `W`/`S` to move that band through the display and
off an edge, then use the alpha panel to read the candidate phase. `M` cycles
manual band, alpha values, raster drift, and phase sweep. In phase-sweep mode,
`P` pauses or resumes the candidate scan; while paused, `A`/`D` changes the red
box height and `W`/`S` moves it vertically.
See [the calibrator procedure](docs/timer-compare-test.md#live-timing-calibrator)
and its [visual-witness section](docs/timer-compare-test.md#visual-witnesses).

The IRQ1 sanity image is a separate bare-MC-10 cassette test:

```powershell
.\space-invaders.ps1 irq1
.\space-invaders.ps1 irq1-run
```

It installs an IRQ1 handler at the MC-10 RAM vector `$420C`, disables all
MC6803 timer interrupt enables, enables CPU interrupts, and observes the
counter for multiple video fields. The expected screen is `IRQ1: INACTIVE`
with `IRQ1 COUNT: 00`. The automated WSLg check is:

```powershell
.\space-invaders.ps1 irq1-test
```

This check uses the stock MC-10 XRoar path and does not attach an MCX
cartridge. MAME verification uses the permanent Lua harness described in
[the IRQ1 test procedure](docs/irq1-sanity-test.md).

The MAME harness has a PowerShell launcher:

```powershell
.\mame-irq1-test.ps1
```

Use `-MamePath`, `-RomPath`, `-SecondsToRun`, or `-SkipBuild` to override its
defaults.

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

## Automated regression checks

The test command rebuilds the cassette, validates its framing, checks the
`$5000` load/execute contract, verifies that the source still contains the
eight MCX bank signatures, and runs the full MCX diagnostic under WSLg. The
emulator stage captures the XRoar display and requires both `MCX128 RAM: OK`
and `TIMER: OK`; the first status is the runtime result of all eight 16 KiB
bank tests, not a static claim about the cartridge.

Set the patched XRoar and emulator-only stock direct ROM paths, then run:

```powershell
$env:MC10_XROAR = '/mnt/e/projects/mc10-space-invaders/build/xroar-clean/src/xroar'
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128-stock-direct.rom'
.\space-invaders.ps1 test
```

The last capture is retained as `build/regression-screen.png` and the XRoar
output as `build/regression-xroar.log` when troubleshooting. On a machine
without WSLg, run the portable stages with:

```text
python3 scripts/regression.py --skip-emulator
```

### IRQ1 sanity harness

The IRQ1 cassette is checked independently because it does not require MCX
bank hardware or a direct-boot ROM. MAME reads the handler counter, completion
flag, and status byte from emulated RAM, then saves
`build/mame-snapshots/mame-irq1-sanity.png`. XRoar is checked by the
`irq1-test` mode, which captures the screen and verifies the inactive status
and matching zero-count glyphs.

The expected result in both emulators is:

```text
IRQ1: INACTIVE
IRQ1 COUNT: 00
```

`IRQ1: ACTIVE` or a nonzero count means that the CPU accepted an IRQ1 during
the observation window. A zero count proves that the configured emulator path
did not assert a CPU-visible IRQ1; it is not, by itself, an electrical proof
about every physical MC-10 or MCX-128 revision.

### MAME Lua calibrator harness

The repository includes `scripts/mame-calibrator-regression.lua`, a permanent
MAME-side test for the cassette-loaded timing calibrator. It posts the MC-10
loader commands, starts the mounted cassette, waits for the complete transfer,
posts `EXEC`, verifies the default manual band, cycles alpha, raster-drift, and
phase-sweep modes, and checks the rendered pixels after each transition. It
also compares two frames for motion, compares two paused frames for zero
change, verifies sweep-box height decrease/increase, vertical movement, both
off-screen directions, and the final return to manual mode.

Build the calibrator, then run the harness from PowerShell. The ROM path below
uses the MC-10 ROM supplied by the template checkout and the MAME ROM directory:

```powershell
.\space-invaders.ps1 calibrator
$mc10Mame = 'E:\tools\mame0289-bin\mame.exe'
$mc10RomPath = 'E:\projects\ladybug\web\docker\roms;E:\tools\mame0289-bin\roms'
& $mc10Mame mc10 -noreadconfig -ramsize 20K -rompath $mc10RomPath `
  -cass 'E:\projects\mc10-space-invaders\build\timing-calibrator.c10' `
  -autoboot_delay 2 `
  -autoboot_script 'E:\projects\mc10-space-invaders\scripts\mame-calibrator-regression.lua' `
  -seconds_to_run 120 `
  -snapshot_directory 'E:\projects\mc10-space-invaders\build\mame-snapshots' `
  -window -nothrottle
```

The expected terminal result is `MC-10 calibrator regression: PASS`. The
harness writes `mame-calibrator-manual-first.png`,
`mame-calibrator-manual-second.png`, `mame-calibrator-alpha.png`,
`mame-calibrator-drift-first.png`, `mame-calibrator-drift-second.png`,
`mame-calibrator-sweep-first.png`, `mame-calibrator-sweep-second.png`,
`mame-calibrator-paused-first.png`, `mame-calibrator-paused-second.png`,
`mame-calibrator-sweep-height-small.png`,
`mame-calibrator-sweep-height-large.png`, `mame-calibrator-sweep-move-up.png`,
`mame-calibrator-sweep-move-down.png`, and `mame-calibrator-return-manual.png`
under
`build/mame-snapshots/`. Pixel classification covers the full MAME capture,
but render thresholds are applied to the active 256x192 MC-10 video region;
the surrounding MAME border is not counted as video evidence. The harness
uses MAME's `{ENTER}` and `{P}` key codes. The manual-band check also verifies
that repeated `W` presses wrap from the top offscreen position to the bottom
and reappear. In sweep mode, pause with `P` before using `A`/`D` to resize the
box or `W`/`S` to move it. The harness also writes
`mame-calibrator-sweep-offscreen-bottom.png` and
`mame-calibrator-sweep-offscreen-top.png` after verifying that the box can
leave the video surface without writing red pixels. Literal text such as `\n` or
`SPACE` is not substituted for those emulated keys.

This is an emulator-render regression, not proof of physical MC6847 `FS`
phase. For the distinction between timer cadence, rendered pixels, and a
physical signal measurement, see [the timer-compare procedure](docs/timer-compare-test.md#mame-lua-pixel-harness).

### MAME Lua game harness

The game-specific harness is `scripts/mame-game-regression.lua`. It uses the
same cassette and `EXEC` sequence, then waits until the program is executing
its game loop. It reads the initialized game state and analyzes the rendered
screen, checking the zero score, three lives, player and formation positions,
all 55 live alien entries, active shields, blue CG3 background, five colored
alien rows, shield structures, player ship, and bottom HUD. It saves the proof
images as `build/mame-snapshots/mame-game-initial.png`,
`mame-game-fired.png`, `mame-game-collision.png`, `mame-game-alien-shot.png`,
`mame-game-shield-damage.png`, `mame-game-player-hit.png`,
`mame-game-descent-shield-clear.png`,
`mame-game-formation-player-collision.png`, `mame-game-over.png`, and
`mame-game-restart.png`. It then posts A and D key events, verifies player
movement, posts `{SPACE}`, verifies the bullet launch state, and waits for that
bullet to remove a live alien and increase the score. It then verifies a
naturally activated alien shot and uses deterministic MAME memory fixtures for
shield damage, player damage, formation descent, formation/player collision,
and final-life game over. The game-over fixture checks rendered red title and
yellow restart-instruction pixels, posts `{SPACE}`, and verifies that the game
returns to three lives, zero score, active shields, the player ship, and no
active projectiles. A successful run prints movement, firing, alien-shot,
collision, shield-damage, player-damage, formation-descent, shield-clear,
game-over-screen, game-restart, and `MC-10 game regression: PASS` markers.

The player-hit check seeds an alien projectile at the player for one normal
update and requires lives to change from 3 to 2 while the player and formation
reset. The descent check seeds the formation at right-edge `X=14`, `Y=19`,
with its movement tick at `0F`; the next normal update must descend to `Y=20`,
reverse direction, deactivate shields, and clear the complete shield region.
The formation/player collision check then seeds the left-edge formation at
`Y=31`; its next descent to `Y=38` must reduce lives from 2 to 1 and reset the
player and formation. Repeating that collision with the final life must set
`GAME_OVER=1` and leave the game frame counter stable. The harness then checks
the visible red `GAME OVER` title and yellow `PRESS SPACE TO RESTART` text,
posts Space, and verifies that initialization restores three lives, zero score,
the player and shields, and no active projectiles.

Run it after rebuilding the game:

```powershell
.\space-invaders.ps1 build
$mc10Mame = 'E:\tools\mame0289-bin\mame.exe'
$mc10RomPath = 'E:\projects\ladybug\web\docker\roms;E:\tools\mame0289-bin\roms'
& $mc10Mame mc10 -noreadconfig -ramsize 20K -rompath $mc10RomPath `
  -cass 'E:\projects\mc10-space-invaders\build\space-invaders.c10' `
  -autoboot_delay 2 `
  -autoboot_script 'E:\projects\mc10-space-invaders\scripts\mame-game-regression.lua' `
  -seconds_to_run 180 `
  -snapshot_directory 'E:\projects\mc10-space-invaders\build\mame-snapshots' `
  -window -nothrottle
```

The harness checks the active 256x192 MC-10 video surface in MAME's 372x243
capture and ignores the surrounding border. It validates the opening game
render after initialization has reached the main loop and exercises one
keyboard-controlled gameplay path plus deterministic collision fixtures. The
game-over screen replaces the playfield with a red `GAME OVER` title and a
yellow `PRESS SPACE TO RESTART` instruction. While latched in game over, only
Space is scanned; the first detected press calls the normal initialization path
and latches the key until release so a held Space cannot immediately fire.
The game workspace is at `$4C00-$4C5A`, immediately after
the visible `$4000-$4BFF` CG3 surface, because `$0100-$015A` is not portable
MC-10 RAM in MAME.

### Manual MAME play

Use `mame-manual-play.ps1` for an interactive session. It builds the current
game cassette unless `-SkipBuild` is supplied, mounts it in MAME, posts
`CLOADM{ENTER}`, starts the cassette, waits for the actual end of the image plus
30 emulated frames, posts `EXEC{ENTER}`, and leaves MAME open. MAME runs at the
requested accelerated load speed, which defaults to 4x, then the Lua script
restores normal-speed throttling when the game loop reaches `$502C-$503B`.

```powershell
.\mame-manual-play.ps1
```

The main parameters are `-LoadSpeed 4`, `-MamePath`, `-RomPath`, and
`-SkipBuild`. The defaults use `E:\tools\mame0289-bin\mame.exe` and the local
ROM directories used by this project; set `MC10_MAME` and
`MC10_MAME_ROMPATH` for another installation. During play, `A` and `D` move,
Space fires, and Space restarts after game over. The loader must wait for the
current cassette's end position; posting `EXEC` at a shorter fixed timeout
leaves the MC-10 in its cassette search state.

## Current test program

`src/main.s` is the CG3 game target. It selects 128×96 two-bit graphics with
the GYBR palette, draws the arcade-style alien formation, preserves damaged
shields, scans A/D and Space, moves the player, fires one shot at a time,
advances the formation, launches alien shots, awards score, and displays
remaining ships at the bottom right. The score is at the bottom left, with no
status text above the aliens. The prior MCX-128 bank and timer diagnostic is
retained as `src/environment-test.s` and built with the `utility` target. See
[the CG3 game layout](docs/cg3-game.md) and [the timer-compare procedure](docs/timer-compare-test.md).

## Project knowledge

- [MC-10 platform notes](docs/mc10-platform.md)
- [Physical MCX-128 register map](docs/mcx128-register-map.md)
- [MCX-128 cassette-loading fault analysis](docs/mcx-cassette-loading.md)
- [XRoar MCX BASIC (LARGE) direct boot](docs/mcx-direct-boot.md)
- [Research and open questions](docs/research.md)
- [Build workflow](wiki/Build-and-emulator-workflow.md)
- [Roadmap](wiki/Roadmap.md)

The platform notes distinguish facts confirmed by schematics/manuals or the XRoar implementation from assumptions that require physical hardware or further source analysis.
