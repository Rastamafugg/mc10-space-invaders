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
`RTI`; the test temporarily replaces it and restores normal timer state before
returning to the idle loop. The screen displays `TIMER: WAIT`, then `TIMER:
OK` after all 60 events, or `TIMER: FAIL` if the interrupt does not complete
within the timeout.

## Physical measurement

1. Build and load `build/space-invaders.c10` with the normal MC-10/XRoar
   workflow, or load the binary on a physical MC-10.
2. Confirm that the display changes from `TIMER: WAIT` to `TIMER: OK`.
3. Probe the MC6847 `FS` output and the P2.0 marker with a two-channel
   oscilloscope or logic analyzer. The MC6847 datasheet identifies `FS` as
   the field-sync output; use the [MC-10 schematic](https://raw.githubusercontent.com/Danjovic/MC-10/main/MC-10%20Schematics.pdf)
   to locate the corresponding pin or test point.
4. Measure the marker period and its phase relative to `FS`. P2.0 toggles on
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
