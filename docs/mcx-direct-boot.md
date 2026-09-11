# XRoar direct boot for MCX BASIC (LARGE)

The physical MCX-128 EPROM presents a three-choice boot menu. The project
target is menu item `[2] MCX BASIC (LARGE)`. XRoar's MCX firmware path can
render the menu but, with the installed WSLg build, selecting item `2` returns
to the menu after the firmware's memory-test interval.

The emulator-only workaround is a generated copy of the supported MCX BASIC
2.1 ROM. `scripts/patch_mcx128_rom.py` checks the input size, SHA-256, and boot
selector signature before changing 21 bytes at file offset `$008D`, which is
CPU address `$C08D` while the ROM is mapped at `$C000`.

The replacement bytes are:

```text
CC FE 10 97 02 86 01 20 0C 01 01 01 01 01 01 01 01
01 01 01 01 01 01 01 01 01 01 01 01
```

This preserves the original `LDD #$FE10` and `STAA $02` Port 2 setup, then
performs `LDAA #$01` and `BRA $C0A2`, followed by unused `NOP` bytes. The MCX
firmware's internal values are not the printed menu numbers:

| Menu item | Firmware selector value | Result |
| --- | ---: | --- |
| `[0] MICROCOLOR BASIC` | `2` | Stock MicroColor BASIC |
| `[1] MCX BASIC` | `0` | Standard MCX BASIC |
| `[2] MCX BASIC (LARGE)` | `1` | Large MCX BASIC |

The branch rejoins the original common path at `$C0A2`, so the firmware still
performs its RAM test, copies the selected BASIC image to RAM, initializes the
MCX registers, and enters the normal BASIC warm start. The patch bypasses only
the keyboard polling loop while retaining the port setup that precedes it.

## Generate

Do not commit the original or generated ROM images. In WSL:

```text
cd /mnt/e/projects/mc10-space-invaders
python3 scripts/patch_mcx128_rom.py \
  --input /home/USER/.xroar/roms/mcx128bas.rom \
  --output build/mcx128bas-large-direct.rom
```

The script currently accepts the MCX BASIC 2.1 dump with SHA-256
`2f442cd17fe90769c4edf77f3c7a323e30281339d84f45a0c5b6acaf3f6a2958`. A
different ROM revision must be reverse-engineered before it is patched.

## Run

From PowerShell:

```powershell
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128bas-large-direct.rom'
.\space-invaders.ps1 run
```

The launcher passes `-cart mcx128`, `-cart-rom`, `-load-tape`, and a queued
`CLOADM` command. After the direct ROM reaches the BASIC prompt, open XRoar's
cassette controls with `Ctrl+T`, press `Play`, wait for the tape to stop, and
enter `EXEC`. The direct boot and cassette transfer were captured under WSLg
as `MCX BASIC 2.1`, `BUILT MAR 18, 2011`, and `OK`, without sending a menu key.
XRoar's generic `-run` path is not used here because its `CLOADM:EXEC` command
is rejected by MCX BASIC.

The generated image is intentionally emulator-only. It must not be programmed
into an EPROM or used as evidence that the physical MCX-128 boot path has been
modified.
