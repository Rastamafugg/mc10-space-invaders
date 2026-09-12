# Roadmap

[Home](Home) · [Platform baseline](Platform-baseline)

## Completed or implemented

- MC6803 assembly and MC-10 cassette-image build path.
- MCX-128 register-map research and eight-bank diagnostic coverage.
- Timer-compare cadence test and P2.0 marker.
- CG3 GYBR rendering and initial playable game scaffolding.
- XRoar cassette-control documentation.
- MAME 0.289 cassette automation and corrected end-of-tape `EXEC` handoff.

## Next validation items

- Capture the environment-test screen with the exact `TIMER: OK` status under MAME.
- Automate MCX BASIC (LARGE) boot-menu selection in an independent emulator.
- Compare MAME and XRoar MCX-128 bank behavior against the physical module.
- Measure MC6847 FS against the P2.0 timer marker on hardware.
- Replace diagnostic scaffolding with the full CG3 game loop after timing and memory assumptions are stable.

## Open constraints

- The MC-10 has no verified VDG-to-CPU frame interrupt.
- Full-frame double buffering is not available in the visible MC6847 RAM at the target layout; region or row updates remain the practical strategy.
- Emulator RAM-size switches must not be treated as proof of physical internal-RAM modifications.
