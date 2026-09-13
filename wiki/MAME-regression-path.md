# MAME Regression Path

[Home](Home) · [Emulator lessons](Emulator-workflows-and-tool-lessons) · [Cassette loading](MC-10-cassette-loading)

## Why MAME was upgraded

The installed MAME 0.220 driver did not expose an MCX-128 slot and rejected the project's `.c10` cassette image. MAME 0.289 exposes the MC-10 `mcx128` cartridge slot, accepts `.c10`, and exposes 4K, 8K, 20K, and 32K RAM selections.

Use the official [MAME releases](https://github.com/mamedev/mame/releases) page for current binaries. The local verification binary was MAME 0.289.

## ROM and cartridge setup

```text
mame.exe -listroms mc10 -rompath E:\path\to\roms
mame.exe -verifyroms mc10 -rompath E:\path\to\roms
mame.exe mc10 -ext mcx128 -rompath E:\path\to\roms
```

The MCX firmware must be in a recognized set directory, for example `roms\mcx128\mcx128bas.rom`. The correct slot option is `-ext mcx128`; `-slot ext=mcx128` is not valid for this driver.

## Automated timing-test command

```text
mame.exe mc10 -noreadconfig -ramsize 20K \
  -rompath "E:\path\to\ladybug\roms;E:\path\to\mame\roms" \
  -cass "E:\path\to\build\timing-calibrator.c10" \
  -autoboot_delay 2 \
  -autoboot_script "E:\path\to\scripts\mame-cassette-autoplay.lua" \
  -seconds_to_run 90 \
  -snapshot_directory "E:\path\to\build\mame-snapshots"
```

The script posts `CLOADM{ENTER}`, starts the cassette, waits for the cassette position to reach the image end, posts `EXEC{ENTER}`, and saves a PNG snapshot.

## Permanent calibrator pixel harness

The repository also includes `scripts/mame-calibrator-regression.lua`. It runs
the same cassette transfer, then verifies the timing calibrator's rendered
state machine instead of stopping at the first alpha-panel snapshot. The
harness checks alpha mode, raster-drift mode, phase-sweep mode, pause/resume,
and the return to alpha. It compares rendered pixel buffers to require motion
in both active modes and zero change while the sweep is paused.

```text
mame.exe mc10 -noreadconfig -ramsize 20K \
  -rompath "E:\path\to\ladybug\roms;E:\path\to\mame\roms" \
  -cass "E:\path\to\build\timing-calibrator.c10" \
  -autoboot_delay 2 \
  -autoboot_script "E:\path\to\scripts\mame-calibrator-regression.lua" \
  -seconds_to_run 120 \
  -snapshot_directory "E:\path\to\build\mame-snapshots" \
  -window -nothrottle
```

The expected result is `MC-10 calibrator regression: PASS`. The eight PNG
captures are named `mame-calibrator-alpha.png`,
`mame-calibrator-drift-first.png`, `mame-calibrator-drift-second.png`,
`mame-calibrator-sweep-first.png`, `mame-calibrator-sweep-second.png`,
`mame-calibrator-paused-first.png`, `mame-calibrator-paused-second.png`, and
`mame-calibrator-return-alpha.png`. The current MAME screen API
reports a 372x243 image for this machine; the harness applies color thresholds
to the active 256x192 MC-10 surface and does not count the MAME border as
video evidence. This is a rendered-emulator regression, not a measurement of
the physical MC6847 `FS` signal.

## Space Invaders initial-screen harness

The game-specific harness is `scripts/mame-game-regression.lua`. It loads
`space-invaders.c10`, waits for the cassette to finish, posts `EXEC{ENTER}`
and waits until the game main loop is active. It then checks game state and
pixels for the opening screen: zero score, three lives, 55 live aliens,
shields, the blue CG3 surface, five colored alien rows, the player ship, and
the bottom HUD. It then posts `A`, `D`, and `{SPACE}` through MAME's natural
keyboard interface, verifies player movement and bullet launch, and waits for
the launched bullet to remove one alien and increase the score. It verifies a
natural alien-shot activation, then seeds a second active shot immediately
above a known lit shield pixel through MAME program-space writes. The normal
alien-shot update must deactivate that shot and reduce the shield pixel count.
It then seeds an alien shot at the player and requires the normal player-hit
path to reduce lives from 3 to 2 and reset the player and formation. Finally,
it seeds the formation at right-edge `X=14`, `Y=19`, with tick `0F`; the normal
edge update must descend to `Y=20`, reverse direction, clear the shield-active
flag, and erase the complete shield region.
It then seeds the left-edge formation at `Y=31`; its next descent to `Y=38`
must exercise the formation/player collision path and reduce lives from 2 to 1.
Repeating that descent with the final life must set `GAME_OVER=1` and leave
the game frame counter stable.

```text
mame.exe mc10 -noreadconfig -ramsize 20K \
  -rompath "E:\path\to\ladybug\roms;E:\path\to\mame\roms" \
  -cass "E:\path\to\build\space-invaders.c10" \
  -autoboot_delay 2 \
  -autoboot_script "E:\path\to\scripts\mame-game-regression.lua" \
  -seconds_to_run 150 \
  -snapshot_directory "E:\path\to\build\mame-snapshots" \
  -window -nothrottle
```

The expected result is `MC-10 game regression: PASS`, with
`mame-game-initial.png`, `mame-game-fired.png`, `mame-game-collision.png`,
`mame-game-alien-shot.png`, and `mame-game-shield-damage.png` in the snapshot
`mame-game-alien-shot.png`, `mame-game-shield-damage.png`,
`mame-game-player-hit.png`, and `mame-game-descent-shield-clear.png` in the
`mame-game-formation-player-collision.png`, and `mame-game-over.png` in the
snapshot directory. The harness analyzes the
active 256x192 surface inside MAME's 372x243 screen capture and ignores the
border. It verifies a deterministic opening render and one keyboard-controlled
gameplay path plus deterministic collision fixtures, not all later gameplay
rules or physical MC6847 `FS` phase.

The game workspace is `$4C00-$4C5A`, after the visible `$4000-$4BFF` CG3
surface. The relocation is necessary because MAME does not provide portable
RAM for the prior `$0100-$015A` workspace range.

## Investigation result

The initial script posted `EXEC{ENTER}` at frame 2400, when the trace showed:

```text
mem5000=0F mem5001=8E tape=36.05/55.77 playing=true
```

The binary had transferred to `$5000`, but the loader had not finished. The command was therefore consumed before BASIC returned to a usable prompt.

The corrected script waited until the tape reached `55.54/55.77` seconds and posted `EXEC{ENTER}` at frame 3568. The trace then showed the cassette stopped, and the resulting snapshot displayed `FS TIMING CALIBRATOR`. This confirms the MAME cassette image and execution handoff.

The calibrator alpha screen uses the title `FS TIMING CALIBRATOR`; it does not display the separate `TIMER: OK` label. Use the environment-test image when that exact status text is required.

The verified environment-test capture is `build/mame-snapshots/environment-mame289.png`. It shows `MCX128 ERROR !` followed by `TIMER: OK`, confirming that the program continues past the expected absent-MCX diagnostic and completes the timer test.

## Expected evidence

- Log contains `CLOADM{ENTER}`, cassette playback, and `EXEC{ENTER}`.
- `$5000` contains the assembled program bytes after transfer.
- CPU leaves the BASIC loader path after the end-of-tape handoff.
- Snapshot shows the program screen rather than only the cassette file name and `OK`.

## RAM-model boundary

MAME's `-ramsize 8K` approximates the piggybacked internal 8 KiB modification because the current MC-10 driver presents one flat RAM device to the CPU and MC6847. It does not prove that physical expansion RAM is on the VDG bus. Use the MCX cartridge configuration separately for eight banked 16 KiB external CPU windows.

## Source references

- [MC-10 driver](https://github.com/mamedev/mame/blob/master/src/mame/trs/mc10.cpp)
- [MCX-128 device](https://github.com/mamedev/mame/blob/master/src/devices/bus/mc10/mcx128.cpp)
- [Lua memory reference](https://docs.mamedev.org/luascript/ref-mem.html)
