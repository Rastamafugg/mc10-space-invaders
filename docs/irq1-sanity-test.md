# MC-10 IRQ1 sanity test

The IRQ1 diagnostic is a cassette-loadable MC6803 program at `$5000`. It is
separate from the MCX-128 bank test and does not require an MCX ROM.

## What it tests

The program selects stock MC-10 alpha video mode, installs a `JMP` to its
handler at the RAM IRQ1 vector `$420C`, clears its counter, disables the
MC6803 timer interrupt enables, executes `CLI`, and waits through multiple
video fields. It then executes `SEI`, latches the result, and displays the
handler count.

The handler increments `$00E0` and returns with `RTI`. The other diagnostic
bytes are `$00E1` (`DONE`) and `$00E2` (`STATUS`):

| Status | Meaning |
| --- | --- |
| `$00` | Observation is still running |
| `$01` | Complete, IRQ1 count is zero |
| `$02` | Complete, IRQ1 was accepted at least once |

The expected display is:

```text
IRQ1: INACTIVE
IRQ1 COUNT: 00
```

`ACTIVE` or a nonzero count means the CPU accepted an IRQ1 while `CLI` was in
effect. The test disables timer interrupt enables before `CLI`, so a positive
count is not attributable to the MC6803 output-compare timer.

## XRoar

Build and run the visible stock-machine path:

```powershell
.\space-invaders.ps1 irq1
.\space-invaders.ps1 irq1-run
```

For an automated WSLg capture:

```powershell
.\space-invaders.ps1 irq1-test
```

The runner uses XRoar's bare `mc10` and `-run` cassette path. It captures the
client through `xwininfo` and `scripts/x11_xroar.py`, then locates the green
text rows rather than assuming a fixed client height. This handles both the
current `640x480` XRoar client and the older `640x505` geometry.

## MAME

Build the image, then run the permanent Lua harness:

```powershell
.\space-invaders.ps1 irq1
$mc10Mame = 'E:\tools\mame0289-bin\mame.exe'
$mc10RomPath = 'E:\projects\ladybug\web\docker\roms;E:\tools\mame0289-bin\roms'
& $mc10Mame mc10 -noreadconfig -skip_gameinfo -ramsize 20K -rompath $mc10RomPath `
  -cass 'E:\projects\mc10-space-invaders\build\irq1-sanity.c10' `
  -autoboot_delay 2 `
  -autoboot_script 'E:\projects\mc10-space-invaders\scripts\mame-irq1-regression.lua' `
  -seconds_to_run 120 `
  -snapshot_directory 'E:\projects\mc10-space-invaders\build\mame-snapshots' `
  -window -nothrottle
```

The Lua harness posts `CLOADM{ENTER}`, starts playback, waits for the actual
cassette end, stops the tape, posts `EXEC{ENTER}`, waits for `$00E1`, reads
`$00E0-$00E2`, and saves `mame-irq1-sanity.png`. It reports `PASS` only for
`count=00`, `status=01`, and `done=01`.

## Interpretation

The result is a CPU-visible emulator statement: neither tested emulator
asserted an IRQ1 that the MC6803 accepted during the observation window. It is
not a complete physical wiring proof. A real board test would use the same
cassette image and observe whether the count changes, while separately
measuring the MC6847 `FS` pin and the CPU IRQ1 pin with a logic analyzer.

This distinction matters because a video `FS` waveform can exist without
being routed to a CPU interrupt input, and an interrupt input can remain
inactive if its source is not connected or not asserted. The diagnostic
establishes the baseline behavior needed before treating `FS` as a game-loop
synchronization source.
