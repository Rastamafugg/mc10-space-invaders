# Physical MCX-128 register map

This document records the physical MCX-128 memory expansion behavior used by
the project. Physical facts are taken from Darren Atkinson's `MCX128 Hardware
Info` document, available in the public [MCX Documentation backup](https://hackaday.io/project/203205-mcx12825),
and cross-checked against the [MCX Wares overview](https://mcxwares.blogspot.com/2020/04/mcx128.html)
and XRoar's [MCX-128 implementation](https://github.com/stahta01/xroar/blob/master/src/mcx128.c).

XRoar is an implementation reference, not physical-hardware acceptance. Its
MC-10 support is explicitly marked unfinished and unsupported in
[mc10.c](https://github.com/stahta01/xroar/blob/master/src/mc10.c).

## Registers

| Address | Register | Defined bits | Function |
| --- | --- | --- | --- |
| `$BF00` | RAM Bank Control | D0=`P0`, D1=`P1` | D0 selects the alternate bank group for Page 0; D1 selects the alternate bank group for Page 1. `0` selects the base group; `1` selects the alternate group. |
| `$BF01` | ROM Map Control | D0=`M0`, D1=`M1` | Selects the ROM/RAM mapping for `$C000-$FFFF`. |

Bits D7-D2 are unused or reserved by the physical register definitions and
must not be assigned a software meaning. The canonical register addresses are
`$BF00` and `$BF01`; XRoar additionally models the `$BF00-$BF7F` region as an
even/odd register decode.

## Physical address map

| Range | Physical function |
| --- | --- |
| `$0000-$0003` | MC6803 ports |
| `$0004-$0007` | Expansion RAM |
| `$0008-$000E` | MC6803 status/control registers |
| `$000F` | Expansion RAM |
| `$0010-$0013` | MC6803 UART |
| `$0014` | MC6803 RAM control register |
| `$0015-$001F` | Unused |
| `$0020-$007F` | Expansion RAM |
| `$0080-$00FF` | MC6803 on-chip RAM or expansion RAM, controlled by `$0014` |
| `$0100-$3FFF` | Expansion RAM |
| `$4000-$4FFF` | Built-in MC-10 RAM or expansion RAM |
| `$5000-$BEFF` | Expansion RAM |
| `$BF00` | MCX-128 RAM Bank Control |
| `$BF01` | MCX-128 ROM Map Control |
| `$BF80-$BFFF` | MC-10 keyboard, VDG, and sound I/O |
| `$C000-$DFFF` | EPROM or expansion RAM, depending on map mode |
| `$E000-$FFFF` | Built-in ROM, EPROM, or expansion RAM, depending on map mode |

## Bank selection

The MCX-128 exposes 64 KiB of address space at a time, divided into four
16 KiB CPU windows. The two control bits select between two 32 KiB backing
groups; they do not select one of eight physical banks directly:

| Logical selector window | Address ranges | Controlled by |
| --- | --- | --- |
| Page 0 | `$0000-$3FFF` and `$C000-$FFFF` | `P0`, bit 0 of `$BF00` |
| Page 1 | `$4000-$BFFF` | `P1`, bit 1 of `$BF00` |

Each selector chooses between a base and alternate 32 KiB group. Each group
contains two 16 KiB banks in the corresponding CPU window. The full expansion
therefore contains four 32 KiB groups, or eight 16 KiB RAM banks.

The complete 16 KiB mapping, using the XRoar bank-page numbering, is:

| CPU address window | Selector | Selector `0` | Selector `1` |
| --- | --- | --- | --- |
| `$0000-$3FFF` | `P0` | RAM page 0 | RAM page 4 |
| `$4000-$7FFF` | `P1` | RAM page 1 | RAM page 5 |
| `$8000-$BFFF` | `P1` | RAM page 2 | RAM page 6 |
| `$C000-$FEFF` | `P0` | RAM page 3 | RAM page 7 |

Thus `P0` selects the low and high 16 KiB halves of one 32 KiB logical
window, while `P1` selects the two middle 16 KiB halves. `$FF00-$FFFF` is a
special fixed 256-byte region in 16 KiB all-RAM mode and is not P0-switched.
`$BF80-$BFFF` is also excluded from the `$8000-$BFFF` RAM window because it
is the MC-10 keyboard/VDG/sound I/O region.

There are important exceptions:

- `$BF80-$BFFF` remains the keyboard/VDG/sound I/O region, not banked RAM.
- `$0080-$00FF` uses MC6803 on-chip RAM by default. `$0014` can select expansion
  RAM for that range; when on-chip RAM is enabled, writes can mirror to the
  expansion RAM.
- The stock MC-10 VDG reads video memory from the internal RAM bus, not from
  the MCX expansion bus. A CPU write to `$4000-$41FF` while an MCX page is
  selected can therefore target expansion RAM without updating the displayed
  screen. An 8 KiB internal-RAM modification is a separate motherboard change;
  it is not created by selecting an MCX page.
- In 16 KiB all-RAM mode, `$FF00-$FFFF` is fixed to bank 0. The corresponding
  256 bytes of bank 1 are inaccessible through that range.

## ROM map modes

`$BF01` uses `M0` as bit 0 and `M1` as bit 1.

| M1:M0 | Mode | `$C000-$DFFF` | `$E000-$FFFF` |
| --- | --- | --- | --- |
| `00` | 16 KiB external ROM | External EPROM | External EPROM |
| `01` | 8 KiB RAM / 8 KiB external ROM | Expansion RAM | External EPROM |
| `10` | 8 KiB RAM / 8 KiB internal ROM | Expansion RAM | Built-in MC-10 ROM |
| `11` | 16 KiB RAM | Expansion RAM | Expansion RAM |

Writes in the ROM address region pass through to RAM. The physical hardware
starts in 16 KiB external-ROM mode and therefore requires an EPROM for a
standalone boot. The emulator smoke test intentionally uses the stock MC-10
ROM and attaches the MCX-128 as a RAM expansion.

## Assembly implications

The current program is loaded at `$5000`. It can set `P0=1` and test the P0
windows without remapping its own code because `$5000` is in Page 1 and `P1`
remains zero. Setting `P1=1` in place would remap the code window to the
alternate bank group; the test therefore copies a bank-safe routine to `$D000`
before switching P1.

The smoke test therefore uses this sequence:

1. Write `P0=0`, `P1=0` to `$BF00` and all-RAM mode `11` to `$BF01`.
2. Write signatures to the low and high P0 windows, select `P0=1`, and write
   different signatures to those windows.
3. Re-select `P0=0` and verify the first pair, then select `P0=1` and verify
   the second pair.
4. Copy a bank-safe P1 test routine to `$D000` while `P0=0`; that address is in
   Page 0 and remains executable while P1 changes. `$C000` remains reserved
   for the P0 signature.
5. From `$D000`, write and verify signatures through the P1=0 and P1=1 middle
   window pairs, covering the remaining four 16K banks.
6. Return to `$5000`, then restore `$BF01=0` and `$BF00=0` before normal MC-10
   ROM or video use.

The P1 path, `$0014` direct-page selection, reset contents, and physical
cassette-loader interaction remain hardware-validation items.
