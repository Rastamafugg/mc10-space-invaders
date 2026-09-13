# Space Invaders for the Tandy MC-10

This wiki is the persistent operational record for the bare-metal MC6803 game project, MC-10 hardware research, and emulator workflows.

## Pages

- [Build and emulator workflow](Build-and-emulator-workflow)
- [Emulator workflows and tool lessons](Emulator-workflows-and-tool-lessons)
- [MC-10 cassette loading](MC-10-cassette-loading)
- [MAME regression path](MAME-regression-path)
- [Timing calibrator](Timing-calibrator)
- [Platform baseline](Platform-baseline)
- [Roadmap](Roadmap)

## Current status

- The project builds MC6803 cassette images at `$5000`.
- MCX-128 bank-map and eight-bank diagnostic code exists.
- The timing calibrator uses MC6803 timer compare events and a P2.0 marker.
- The calibrator defaults to a manual full-width CG3 band; its advanced sweep
  mode supports box-height and vertical-position experiments.
- The MAME 0.289 automated cassette path now waits for the full tape image before posting `EXEC{ENTER}` and reaches the calibrator screen.
- The MAME `environment-test` cassette reaches `TIMER: OK`; the capture also shows the expected `MCX128 ERROR !` on a bare MC-10 configuration.
- Physical MCX-128 behavior and MC6847 FS timing remain hardware-validation items.

## Repository references

- [MCX-128 register map](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/docs/mcx128-register-map.md)
- [MC-10 platform research](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/docs/research.md)
- [Timer-compare procedure](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/docs/timer-compare-test.md)
