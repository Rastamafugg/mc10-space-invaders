# CG3 game layout

The game target is a cassette-loadable MC6803 program at `$5000`. It selects
MC6847 CG3 with `$BFFF=$24`, using the GYBR palette. The display is 128×96
pixels, four colors, two bits per pixel, and occupies `$4000-$4BFF` with 32
bytes per scanline.

## Composition

The playfield is arranged for the MC-10's horizontal monitor presentation:

| Region | CG3 coordinates | Content |
| --- | --- | --- |
| Bonus lane | y=1 | Optional bonus ship crossing the top lane |
| Formation | y=4, 11, 18, 25, 32 | 11 columns: smaller pointy red octopuses, two green crab rows, two yellow squid rows |
| Shields | y=70 | Four seven-row structures, close to the player |
| Active ship | y=82 | Player-controlled ship |
| Status row | y=90 | Four score digits at the lower left and one ship icon per remaining life at the lower right |

There is no score or status text above the formation. The low-resolution CG3
renderer uses pixel-packed eight-pixel silhouettes. Each alien has a ten-pixel
horizontal pitch, leaving two pixels between columns, and successive rows are
seven pixels apart. The blue playfield is the GYBR blue value. The four GYBR
values used by the game are:

| Value | GYBR color | Usage |
| ---: | --- | --- |
| 0 | green | Middle alien rows |
| 1 | yellow | Squids, shields, score, life icons, and player shots |
| 2 | blue | Background and damaged shield pixels |
| 3 | red | Octopus row, player ship, and alien shots |

The timer compare vector is stored at `$4206-$4208`, which is inside the CG3
display RAM. The initial formation y-coordinate and its seven-pixel row spacing
leave that scanline clear. Each update masks interrupts while drawing and
reinstalls the vector after any video-RAM writes.

## MCX-128 staging and frame transfer

The documented MCX-128 map can provide a CPU-side shadow surface without
changing the VDG's visible RAM. With Page 1 selected to its base group, reserve
`$6000-$6BFF` for a complete 3 KiB CG3 frame. `$6000` is in the external RAM
window, while the visible CG3 surface remains the internal `$4000-$4BFF` RAM
seen by the MC6847. The P1 selector must remain unchanged while the copy runs.

This is not a hardware page flip. The MC6847 has no display-start register, and
the VDG does not scan the MCX expansion RAM. A complete frame would still have
to be copied from `$6000` to `$4000`.

The MC6847 datasheet defines the low FS interval as the period from the end of
active display to the trailing edge of vertical sync. The timing model used by
the project is 32 scanlines, or `32 * 228 / 3,579,545 = 2.036 ms`, equivalent
to about 1,824 MC6803 E-clock periods. That interval is safe for direct display
RAM access, but it is far too short for a 3,072-byte 6803 copy. It is also not
currently delivered as a CPU interrupt on the stock MC-10 wiring or by XRoar.

The practical options are:

1. Render a complete next frame in `$6000`, then copy only changed scanline
   spans or rectangular dirty regions to `$4000` over successive fields.
2. Keep the current direct renderer and update only the moving objects. This
   already avoids redrawing the persistent formation on every compare event.
3. If a physical FS-to-IRQ/NMI connection is later verified or added, use it as
   the start marker for small dirty-region copies. It will not make a complete
   CG3 frame copy atomic.

The current game uses the second option. A horizontal formation move is
represented as five row regions. On each compare event, one row is erased at
the previous formation position and redrawn at the new position. The row's
four or five occupied scanlines are touched; blank scanlines, shields, status,
and the other formation rows are skipped. This reduces each movement update to
approximately one fifth of a full-formation redraw. The tradeoff is that a
formation translation can be visibly skewed for up to five fields while its
rows are being updated.

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

The game does not currently use the MCX-128 banked RAM for rendering. The
expansion provides the emulator boot and cassette environment; the CG3 frame
buffer and game state remain in the MC-10 address space. `$6000-$6BFF` is
reserved as a future shadow-frame experiment, not an enabled runtime buffer.
