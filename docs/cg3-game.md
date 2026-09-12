# CG3 game layout

The game target is a cassette-loadable MC6803 program at `$5000`. It selects
MC6847 CG3 with `$BFFF=$24`, using the GYBR palette. The display is 128×96
pixels, four colors, two bits per pixel, and occupies `$4000-$4BFF` with 32
bytes per scanline.

## Composition

The playfield is arranged for the MC-10's horizontal monitor presentation:

| Region | CG3 coordinates | Content |
| --- | --- | --- |
| Bonus lane | y=2 | Optional bonus ship crossing the top lane |
| Formation | y=5, 11, 17, 23, 29 | 11 columns: octopus, two crab rows, two squid rows |
| Shields | y=60 | Four seven-row structures |
| Active ship | y=82 | Player-controlled ship |
| Status row | y=90 | Four score digits at the lower left and one ship icon per remaining life at the lower right |

There is no score or status text above the formation. The low-resolution CG3
renderer uses two screen bytes per alien and compact masks derived from the
arcade silhouettes. The four GYBR values used by the game are:

| Value | GYBR color | Usage |
| ---: | --- | --- |
| 0 | green | Background and damaged shield pixels |
| 1 | yellow | Squids, shields, score, and life icons |
| 2 | blue | Crabs and player shots |
| 3 | red | Octopus row, player ship, and alien shots |

The timer compare vector is stored at `$4206-$4208`, which is inside the CG3
display RAM. The initial formation y-coordinate and its six-pixel row spacing
leave that scanline clear. Each update masks interrupts while drawing and
reinstalls the vector after any video-RAM writes.

## Game rules implemented

- A/D moves the active ship within the display bounds.
- Space fires one player shot at a time.
- The formation alternates direction and descends one row at each horizontal
  edge. Its initial movement is deliberately slower than the timer cadence so
  the full formation remains playable on the first wave.
- Player shots remove an alien and add its row value to the decimal score.
- Alien shots fall from the formation. A hit on a lit shield pixel removes a
  small cross-shaped group of pixels, producing a persistent burrow.
- A shot that reaches the player costs one life. A formation descending to the
  player level also costs one life and restarts the formation position.
- The bonus ship periodically crosses the bonus lane and awards 50 points when
  hit.

## Build and run

Build the game cassette with:

```text
bash scripts/build.sh build
```

Run it with the direct MCX-128 ROM path used by the XRoar test setup:

```powershell
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128-stock-direct.rom'
.\space-invaders.ps1 run
```

The utility target remains available for environment validation:

```powershell
.\space-invaders.ps1 utility-run
```

The game does not use the MCX-128 banked RAM. The expansion is used only to
provide the emulator boot and cassette environment; the CG3 frame buffer and
game state remain in the MC-10 address space.
