# Timing Calibrator

[Home](Home) · [Build and emulator workflow](Build-and-emulator-workflow) · [MAME regression path](MAME-regression-path)

## Purpose

The timing calibrator helps identify a compare phase that does not visibly
interfere with the MC6847 display update. The MC-10 does not expose MC6847 `FS`
as a verified CPU-readable interrupt source, so the program cannot calculate
the phase automatically. The primary result is an operator-selected period and
phase candidate; hardware validation uses the P2.0 marker and an MC6847 `FS`
probe on a two-channel oscilloscope or logic analyzer.

## Default workflow

Build and start the program with:

```powershell
.\space-invaders.ps1 calibrator
.\space-invaders.ps1 calibrator-run
```

The initial screen is a blue CG3 surface with a full-width green band near the
upper edge. Use `W` to move the band upward and `S` to move it downward. The
manual band wraps: continuing upward from the top offscreen position brings it
back at the bottom, and continuing downward from the bottom offscreen position
brings it back at the top. Move the band through the visible display and just
beyond an edge. The disappearance boundary is the visual candidate for the
render-safe interval.

Press `M` once to enter the alpha panel and record `PERIOD` and `PHASE`. Copy
those values to `TIMER_PERIOD` and `TIMER_PHASE` in `src/main.s`. Press `R` to
re-arm the compare after a large adjustment. `Space` resets the event counter
and the P2.0 marker.

## Controls by mode

| Key | Manual band | Alpha or drift | Phase sweep |
| --- | --- | --- | --- |
| `A` / `D` | Period -/+ 1 E clock | Period -/+ 1 E clock | Box height -/+ 4 CG3 rows |
| `W` / `S` | Move band up/down and adjust phase candidate | Phase -/+ 8 E clocks | Move box bias up/down 4 CG3 rows |
| `R` | Re-arm compare | Re-arm compare | Re-arm compare |
| `Space` | Reset marker/count | Reset marker/count | Reset marker/count |
| `M` | Next mode | Next mode | Return to manual band |
| `P` | No action | No action | Pause or resume sweep |

The mode order is manual band, alpha values, raster drift, and phase sweep.
The default manual mode uses `A` and `D` for timer-period adjustment, which is
reported in the alpha panel and does not visibly resize the band. `P` has no
effect outside phase-sweep mode. Press `M` three times from the default screen
and confirm `MODE: SWEEP` before using `P`, `A`, or `D` for the sweep controls.
Pause with `P` before changing sweep geometry when examining one fixed phase
candidate. In sweep mode, the box height is clamped to 4-48 CG3 rows and its
vertical bias to -96 through +96 rows. The renderer clips rows outside the
96-row logical CG3 surface, so the box can be moved completely offscreen.

## Geometry experiment

The sweep box is a visible red witness on the blue GYBR surface. To estimate
the vertical extent of a usable interval:

1. Press `M` three times from the default screen to enter phase sweep.
2. Press `P` when the box is at the candidate phase to freeze it.
3. Press `A` repeatedly to reduce its height, or `D` repeatedly to increase it.
4. Press `W` and `S` to test the same box at different vertical positions.
5. Press `P` to resume the sweep, or press `M` to return to the manual band.

A height that can be enlarged without visible disruption indicates more
vertical time is available at that phase. Moving the box completely above or
below the visible picture exposes the unrepresented portion of the cycle. If
only one screen position works, the interval is position-dependent. These are
visual diagnostics, not a hardware page flip, FS detector, or automatic vblank
synchronizer.

## Automated check

The permanent MAME Lua harness is
`scripts/mame-calibrator-regression.lua`. It loads the cassette, executes the
calibrator, verifies the manual band, checks alpha, drift, and sweep motion,
pauses the sweep, changes height in both directions, moves the box up and down,
and returns to manual mode. A passing run prints:

```text
MC-10 calibrator regression: PASS
```

Use the command documented in [MAME regression path](MAME-regression-path).
