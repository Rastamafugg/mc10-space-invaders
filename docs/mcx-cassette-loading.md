# MCX-128 cassette loading and the XRoar memory fault

The cassette-loading memory failure reproduced in the project is an XRoar
emulation defect, not an intended MCX-128 behavior. This conclusion applies
to the observed automatic `-run` path that returned to `$3F3F`; it does not
claim that every MCX BASIC Large-mode program is compatible with stock BASIC
memory conventions.

## Physical behavior

The physical MCX-128 is a memory expansion with an EPROM socket. The supplied
[MCX128 Hardware Info](MCX%20Documentation/MCX128%20Hardware%20Info.pdf)
register map places the loaded program area `$5000-$BEFF` in expansion RAM and
defines `$BF00` and `$BF01` as the bank and ROM-map controls. In map mode `2`
(`M1:M0 = 10`), `$C000-$DFFF` is expansion RAM and `$E000-$FFFF` is the
built-in MC-10 ROM. Therefore the stock MC-10 `CLOADM` destination at `$5000`
remains writable and executable with the expansion attached.

The expansion does not replace the MC-10 cassette loader. The loader is stock
ROM software that receives cassette blocks, writes them through the CPU bus,
and later uses `EXEC` to enter the recorded execution address. An attached
MCX-128 changes which RAM device answers a CPU memory cycle; it does not
change the meaning of a CPU stack read into keyboard data.

MCX BASIC Large mode is a separate compatibility issue. The supplied [MCX Basic
Reference](MCX%20Documentation/MCX%20Basic%20Reference.pdf) allocates a separate
bank for its BASIC workspace and graphics, and
warns that machine code which assumes the standard configuration can fail in
Large mode unless it performs the required bank selection. That is an intended
mode-specific software constraint, not evidence that stock `CLOADM` should
fail in `$5000` expansion RAM.

## XRoar failure mechanism

XRoar's [MCX implementation](https://github.com/stahta01/xroar/blob/master/src/mcx128.c)
creates eight 16 KiB RAM banks and routes CPU cycles through the cartridge
mapping. Its MC-10 auto-keyboard hook intercepts
the stock BASIC input routine and simulates the return from that call. Before
the project patch, the synthetic `RTS` in `mc10_op_rts()` read the two return
address bytes through the base-machine memory callback instead of the attached
MCX cartridge callback.

In the stock-direct map the BASIC stack is in the expansion-RAM region near
`$BE90`. The base callback therefore did not return the stack bytes supplied by
the MCX map. It produced `$3F3F` as the synthetic return address, so the first
queued keyboard character was not followed by the remaining `CLOADM` command.
The unpatched path consequently appeared to remain at the BASIC prompt or at
the cassette search state.

`patches/xroar-mc10-cart-auto-kbd.patch` makes those two synthetic stack reads
ask the cartridge first and fall back to the base machine only when the
cartridge does not select the address. The patched run restored `$F86E`, sent
the queued command completely, advanced the cassette, and reached the loaded
program at `$5000` with the MCX cartridge attached.

This is a defect in the emulator's synthetic input path. It is not a proposed
change to the physical MCX register map. The source patch is intentionally
kept outside this repository's game code because it belongs to XRoar.

## Scope of the evidence

The physical map conclusion is based on the supplied MCX hardware documents,
the MCX Basic Reference, the stock MC-10 loader behavior, and the independent
XRoar MCX source. Physical hardware testing is still required for electrical
timing, reset contents, direct-page selection, and the real EPROM boot path.
The automated project regression checks only the reproducible emulator path:
all eight bank signatures must produce `MCX128 RAM: OK`, and the independent
timer test must produce `TIMER: OK`.
