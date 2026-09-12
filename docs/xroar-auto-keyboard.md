# XRoar MC-10 cartridge auto-keyboard fix

The stock-mode direct ROM exposes the host MC-10 BASIC ROM while retaining the
MCX-128 cartridge. XRoar's normal `-type` and `-run` paths initially failed in
that configuration even though the BASIC prompt was visible.

## Cause

XRoar implements the MC-10 auto-keyboard hook at BASIC address `$F883`. The
hook supplies a character and simulates the return from the intercepted call
with `mc10_op_rts()`. Before this fix, `mc10_op_rts()` read the synthetic stack
return address through `m->read_byte()`. That base-machine read bypasses an
attached MC-10 cartridge.

With the MCX-128 map selected by the stock-mode handoff, the BASIC stack is in
external RAM near `$BE90`. The base-machine read therefore returned the
keyboard-bus value instead of the external-RAM byte. The simulated return
changed the PC from `$F86E` to `$3F3F`, so only the first queued character was
attempted. This also explains why the bare stock MC-10 path worked.

## Patch

`patches/xroar-mc10-cart-auto-kbd.patch` targets XRoar commit
`0265c83e5fb4a737749662356b24c99a9147d363`. It adds a stack-byte helper that
asks the cartridge to service each read first and falls back to the base
machine only when the cartridge does not select the address.

The patch applies to a clean checkout. If the checkout uses CRLF line endings,
use Git's whitespace-tolerant mode:

```text
git apply --ignore-whitespace patches/xroar-mc10-cart-auto-kbd.patch
git apply --ignore-whitespace patches/xroar-gtk3-menu-resource.patch
```

Build XRoar using its normal project instructions, then point the launcher at
the patched executable. The launcher expects `MC10_XROAR` to be visible inside
WSL, for example `/home/user/src/xroar/src/xroar`.

```powershell
$env:MC10_XROAR = '/home/user/src/xroar/src/xroar'
$env:MC10_XROAR_MC10_CART_PATCHED = '1'
$env:MC10_MCX_DIRECT_ROM = 'E:\projects\mc10-space-invaders\build\mcx128-stock-direct.rom'
$env:MC10_MCX_DIRECT_MODE = 'stock'
.\space-invaders.ps1 run
```

With the marker set, the launcher uses XRoar's `-run` path. XRoar queues the
MC-10 load command, starts the attached cassette at the MC-10 loader hook, and
the test program reaches `$5000`. Without the marker, the launcher retains the
manual `-load-tape` path so an unpatched XRoar cannot silently lose the queued
command.

## Validation

The patched XRoar trace showed twelve queued keyboard events for
`Ctrl+U CLOADM:EXEC`, and every simulated return restored PC `$F86E`. The
cassette input then advanced and execution reached `$5000` with the MCX-128
cartridge attached. The same test with the original XRoar binary stopped after
the first event with a synthetic return PC of `$3F3F`.

This fixes XRoar's synthetic stack read. The WSLg package also exposed a
separate GTK3 resource issue: its loader skips the first XML tag, but the
packaged `menu.ui` did not have an XML declaration. Apply
`patches/xroar-gtk3-menu-resource.patch` to add that declaration. With that
patch, `Ctrl+T` opens the cassette-controls window and the attached tape can
be started with `Play`.

The two patches are independent. The auto-keyboard patch is required for the
automatic `-run` path; the GTK3 patch is required only when the build needs
the WSLg cassette-controls dialog for manual loading.

## WSLg manual-path check

With both patches applied, `Ctrl+T` opened `XRoar · Cassette tapes`, displayed
`build/space-invaders.c10`, and the `Play` button advanced the tape position.
The X11 test helper generated valid X11 key events, but those events did not
appear in the MC-10 BASIC input line, so a manual `CLOADM` transfer was not
claimed as complete. The patched automatic path is the reproducible WSLg
verification until keyboard input is fixed separately.
