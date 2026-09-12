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

## Investigation result

The initial script posted `EXEC{ENTER}` at frame 2400, when the trace showed:

```text
mem5000=0F mem5001=8E tape=36.05/55.77 playing=true
```

The binary had transferred to `$5000`, but the loader had not finished. The command was therefore consumed before BASIC returned to a usable prompt.

The corrected script waited until the tape reached `55.54/55.77` seconds and posted `EXEC{ENTER}` at frame 3568. The trace then showed the cassette stopped, and the resulting snapshot displayed `FS TIMING CALIBRATOR`. This confirms the MAME cassette image and execution handoff.

The calibrator alpha screen uses the title `FS TIMING CALIBRATOR`; it does not display the separate `TIMER: OK` label. Use the environment-test image when that exact status text is required.

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
