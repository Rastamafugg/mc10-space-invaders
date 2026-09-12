# Build and Emulator Workflow

[Home](Home) · [Emulator lessons](Emulator-workflows-and-tool-lessons) · [Cassette loading](MC-10-cassette-loading)

## Build commands

From PowerShell:

```powershell
.\space-invaders.ps1 build
.\space-invaders.ps1 run
.\space-invaders.ps1 check
```

Separate diagnostic targets are available:

```powershell
.\space-invaders.ps1 utility
.\space-invaders.ps1 utility-run
.\space-invaders.ps1 calibrator
.\space-invaders.ps1 calibrator-run
python scripts/regression.py --skip-emulator
```

The build uses CRASM for MC6803 assembly and `scripts/make_c10.py` for MC-10 cassette framing. Generated binaries and cassette images are under `build/`.

## XRoar

Stock-machine loader path:

```text
xroar -machine mc10 -run build/space-invaders.c10
```

Manual MCX-128 path:

```text
xroar -machine mc10 -cart mcx128 -cart-rom build/mcx128.rom \
  -load-tape build/space-invaders.c10
```

Select `2`, MCX BASIC (LARGE), then use the [manual cassette sequence](MC-10-cassette-loading). `MC10_MCX_DIRECT_ROM` is an emulator-only patched-ROM path and must not be programmed into physical hardware.

## MAME

MAME 0.289 provides the independent MC-10 path:

```text
mame.exe mc10 -ramsize 20K -cass build\timing-calibrator.c10
```

The MCX-128 slot is selected with `-ext mcx128`. The reusable Lua automation is [in the repository](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/scripts/mame-cassette-autoplay.lua), and the complete setup is documented in [MAME regression path](MAME-regression-path).
