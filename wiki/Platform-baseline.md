# Platform Baseline

[Home](Home) · [MAME regression](MAME-regression-path)

## Confirmed baseline

- CPU: Motorola MC6803.
- Video: MC6847 VDG.
- Software screen buffer: `$4000-$41FF`.
- Project executable load address: `$5000`.
- MCX-128 registers: `$BF00` P0, `$BF01` P1 and ROM/RAM map selection.
- Keyboard: active-low eight-column matrix using Port 1 selection and `$BFFF` row reads.
- Initial NTSC model: 228 master-clock periods per line, 262 lines per field, approximately 59.923 Hz, and 14,934 MC6803 E-clock periods per field.

## MCX-128 boundary

P0 selects the bank group for `$0000-$3FFF` and `$C000-$FFFF`. P1 selects the group for `$4000-$BFFF`. The full expansion has eight physical 16 KiB RAM banks, organized by the base and alternate groups used by the emulator implementation.

The project copies the P1 test routine to `$D000` before changing P1 so that the executable at `$5000` remains reachable and the P0 signature at `$C000` remains testable.

See the repository [MCX-128 register map](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/docs/mcx128-register-map.md).

## Timing boundary

No verified connection from MC6847 FS to a periodic MC6803 interrupt source has been identified. The timing calibrator therefore uses MC6803 timer compare interrupts and toggles P2.0 for external comparison with MC6847 FS.

## RAM boundary

The stock MC-10 has 4 KiB of internal RAM on the shared CPU/MC6847 bus. External CPU expansion RAM does not automatically become VDG-visible. XRoar `-ram 8` approximates the published internal 8 KiB modification. MAME `-ramsize 8K` is an emulator approximation, not a physical bus model.
