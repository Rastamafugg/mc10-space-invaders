# MC6847 field-cadence timer test

The diagnostic in `src/main.s` measures whether an MC6803 output-compare
schedule can reproduce the initial MC6847 NTSC field budget. It does not claim
that the MC6847 `FS` output is connected to a CPU interrupt. The CPU generates
the test events, and an external capture compares those events with `FS`.

## Timing model

The project uses the current [MAME MC6847 timing model](https://github.com/mamedev/mame/blob/master/src/devices/video/mc6847.cpp): 228 master-clock
periods per scanline and 262 scanlines per field. The [MC-10 service
manual](https://cdn.hackaday.io/files/1837077859720288/Tandy_MC-10_Service_Manual.pdf)
documents the 3.579545 MHz oscillator and the MC6803 divide-by-four E clock.
The resulting timer interval is:

```text
3,579,545 / 4       = 894,886.25 E clocks/second
262 * 228 / 4       = 14,934 E clocks/field
14,934              = $3A56
```

The test collects 60 compare events, representing approximately one second
at 59.923 Hz. The interval is added to the previous compare value rather than
the current counter, preserving phase across counter wrap and interrupt
latency.

## MC6803 setup

The test follows the MC6803 timer definitions in the [MC6803
datasheet](https://cdn.hackaday.io/files/1776067598695104/6803_datasheet.pdf)
and performs the following hardware operations:

| Address | Operation |
| --- | --- |
| `$4206-$4208` | Install an extended jump to the test OCF handler. |
| `$0008` | Read TCSR to acknowledge a pending OCF, then write `$08` to enable EOCI. |
| `$0009-$000A` | Read the free-running counter. |
| `$000B-$000C` | Write the next compare value. |
| `$0001` | Set Port 2 direction with only P2.0 as an output. |
| `$0003` | Toggle P2.0 once per compare event. |

P2.1 is left as an input because it is part of the MC-10 modifier-key path.
P2.0 is shared with the cassette/RS-232 output circuitry on the physical
machine, so do not connect active cassette or serial equipment while using the
marker.

The stock ROM's RAM-resident output-compare vector is normally an immediate
`RTI`; the test claims that private vector for the diagnostic and subsequent
game-loop scaffold. The screen displays `TIMER: WAIT`, then `TIMER: OK` after
all 60 events, or `TIMER: FAIL` if the interrupt does not complete within the
timeout. After `TIMER: OK`, the program re-arms the same interval and enters
the game-loop scaffold, where the `FRAME: 0000` counter advances once per
queued timer event.

The interrupt handler remains short: it schedules the next compare, toggles
P2.0, and either counts diagnostic events or increments the pending-tick byte.
The foreground loop consumes pending ticks and calls `game_update`, which is
the insertion point for input, simulation, collision, and rendering code.

## Physical measurement

### Exact XRoar cassette sequence

The MCX-128 is a RAM expansion. It does not load or execute cassette data. In
the project configuration, XRoar boots the stock MC-10 ROM and attaches the
MCX-128 RAM profile, so the MC-10 cassette commands remain part of the load
sequence.

### MCX-128 boot selection

The supplied [MCX Basic Reference](MCX%20Documentation/MCX%20Basic%20Reference.pdf)
states that an MCX Basic EPROM presents a boot menu at startup. The menu offers
stock MicroColor Basic, standard MCX Basic, and large MCX Basic. Pressing the
selected menu key starts a memory test and copies the selected ROM contents into
RAM. For this project, select `[0] MICROCOLOR BASIC`: the program is a machine-
language test that expects the stock MC-10 screen and workspace arrangement.

The supplied [MCX128 Hardware Info](MCX%20Documentation/MCX128%20Hardware%20Info.pdf)
documents software control for the RAM-bank and ROM-map registers, but does not
document a boot switch, persistent boot selection, or an alternate hardware boot
mode. The documented way to show the menu again without power-cycling is to hold
`BREAK` while pressing and releasing `Reset`.

XRoar's `-run` feature automatically types the cassette load command. That is
appropriate for the stock ROM path, but it is not reliable when an MCX EPROM is
present because the boot menu must be answered first. Use `-load-tape` for the
MCX EPROM path:

```text
xroar -machine mc10 -cart mcx128 \
  -cart-rom build/mcx128.rom \
  -load-tape build/space-invaders.c10
```

Select option `0`, wait for the MicroColor BASIC `OK` prompt, and continue with
the cassette sequence below.

XRoar can technically accept an emulator-only replacement with `-cart-rom` if
the MCX boot code is patched to select one entry. A valid patch must retain the
memory-test and ROM-copy initialization path. The project does not currently
ship a patch generator because its internal startup paths still require
validation against the physical module. A post-selection snapshot is the
safer repeatable shortcut until that validation is complete.

From PowerShell, use the project launcher:

```text
.\space-invaders.ps1 build
.\space-invaders.ps1 run
```

The launcher runs:

```text
xroar -machine mc10 -cart mcx128 -run build/space-invaders.c10
```

### Base-machine RAM alternatives

The internal MC6847 RAM and external CPU expansion are separate hardware
cases. Use XRoar `-ram 8` when approximating the published 8 KiB internal RAM
modification. Use `-ram 20` when testing the stock 4 KiB internal RAM plus a
16 KiB external pack; this does not make that external RAM part of the stock
MC6847 video bus. XRoar `-ram 16` means 4 KiB internal plus 12 KiB external,
not 16 KiB internal.

Current MAME exposes `-ramsize 4K`, `8K`, `20K`, and `32K`. Its MC-10 driver
installs one flat RAM device at `$4000` and supplies that device to the MC6847,
so `8K` is a useful emulator approximation of an 8 KiB internal mod, while
the larger settings should not be read as physical internal/external bus
models. MCX-128 remains a separate cartridge configuration.

To use the MCX boot-ROM image in XRoar, set the optional path before launching:

```powershell
$env:MC10_MCX_ROM = 'E:\path\to\mcx128.rom'
.\space-invaders.ps1 run
```

With that variable set, the launcher passes `-cart-rom` and `-load-tape`, then
waits for the manual boot-menu selection described above.

XRoar's `-run` option attaches the `.c10` image and types `CLOADM` for a
machine-code image. The MC-10 has no remote cassette motor-control line, so
the tape starts paused. Complete the load as follows:

1. Focus the emulated MC-10 display and wait for the `CLOADM` command to
   appear, then press `Enter` if XRoar has not already done so.
2. Press `Ctrl+T` to open XRoar's cassette-controls window.
3. Select the `Input` tab, verify that `SPACEINV` is the selected tape, and
   press `Play` once. `Pause` becomes enabled while the tape is running.
4. Close the cassette-controls window if required, return focus to the MC-10,
   and wait for the load to finish and the `OK` prompt to appear.
5. Type `EXEC` and press `Enter` to start the loaded program.

For a fully manual command-line setup, replace `-run` with `-load-tape`:

```text
xroar -machine mc10 -cart mcx128 -load-tape build/space-invaders.c10
```

Then type `CLOADM`, press `Enter`, open cassette controls with `Ctrl+T`, press
`Play`, wait for `OK`, and type `EXEC` followed by `Enter`. `-load-tape` only
attaches the image; it does not enter the load command. Do not press `Reset`
between entering `CLOADM` and starting the tape.

After execution starts, confirm that the display changes from `TIMER: WAIT` to
`TIMER: OK`, then that the `FRAME: 0000` counter advances.

For a physical MC-10, use the equivalent keyboard and cassette-player
actions: enter `CLOADM`, press `Enter`, start the cassette manually, wait for
`OK`, then enter `EXEC` and press `Enter`.

### Physical signal capture

1. Probe the MC6847 `FS` output and the P2.0 marker with a two-channel
   oscilloscope or logic analyzer. The MC6847 datasheet identifies `FS` as
   the field-sync output; use the [MC-10 schematic](https://raw.githubusercontent.com/Danjovic/MC-10/main/MC-10%20Schematics.pdf)
   to locate the corresponding pin or test point.
2. Measure the marker period and its phase relative to `FS`. P2.0 toggles on
   every timer event, so each rising edge spans two predicted fields. Compare
   the marker's rising or falling edge to the same edge of `FS` over the full
   60-event run.

Interpretation:

- `TIMER: FAIL` indicates that the timer compare interrupt path, vector, or
  emulator/hardware timer behavior is not working as expected.
- `TIMER: OK` with a stable marker-to-`FS` relationship supports the 14,934
  E-clock field model and provides a usable game-loop cadence.
- `TIMER: OK` with measurable drift indicates that the 228-clock line model,
  oscillator frequency, or assumed `FS` edge relationship needs adjustment.

The screen result alone verifies only that 60 timer compares occurred. It
cannot verify absolute `FS` phase because the stock MC-10 software-visible
sources do not expose `FS` as a CPU-readable input or verified IRQ/NMI source.

## Emulator limitation

Current XRoar invokes an MC-10 VDG field-sync callback for sound and host video
presentation, not a CPU interrupt. Current MAME likewise configures the MC6847
and MC6803 clocks but does not show an `FS`-to-CPU interrupt connection in the
MC-10 machine configuration. The timer test is therefore an emulator-aligned
cadence test plus a physical signal-capture test, not an emulated direct FS
interrupt test.
