# Emulator Workflows and Tool Lessons

[Home](Home) · [Build workflow](Build-and-emulator-workflow) · [MAME regression](MAME-regression-path)

## Tool roles

| Tool | Use | Limit |
| --- | --- | --- |
| XRoar | Interactive MC-10 and MCX-128 cassette testing; WSLg X11 capture | MC-10 support is unfinished and MCX BASIC startup can require manual input |
| MAME 0.289 | Independent MC-10 driver, `.c10` loading, MCX-128 slot, Lua automation | Its default RAM model is flat CPU/VDG RAM, not a physical internal/external bus model |
| PowerShell | Windows build launcher and process control | Argument quoting and control characters must be verified separately |
| Computer use | Interactive display and keyboard control when an app is exposed | The active CU runtime can report no native apps even when a Windows emulator window exists |

## Return-character lesson

MAME's `-autoboot_command` requires an actual Return character. The literal text `\n` does not submit Return.

In PowerShell:

```powershell
# Actual line feed in a double-quoted PowerShell string
$returnCommand = "CLOADM`n"

# Literal backslash and letter n. This does not submit Return.
$literalCommand = 'CLOADM\n'
```

The robust project path uses MAME's Lua natural keyboard API instead:

```lua
keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
keyboard:post_coded("EXEC{ENTER}")
```

`{ENTER}` is MAME's emulated Return key code. It is not the text sequence `\n`.

## Cassette lesson

Loading has three separate actions:

1. Enter `CLOADM`.
2. Start playback while the loader is searching.
3. Enter `EXEC` only after the cassette transfer has returned to BASIC.

Starting playback early consumes the leader and data before the loader is ready. In the MAME run, the image length was 55.77 seconds. Posting `EXEC` at tape position 36.05 seconds left the CPU in the loader path. Waiting until position 55.54 seconds allowed the command to execute.

The Lua helper retains its frame-notifier subscription globally. A notifier stored only in a local variable can be garbage-collected after an autoboot script returns.

## WSLg and computer-use lesson

WSLg X11 windows can be inspected with `xwininfo` and the repository's X11 capture path. That does not guarantee exposure through computer use. A native MAME process had a valid window title and responsive state while the CU inventory returned `apps: []`.

Use emulator-owned snapshots for native MAME and X11 capture for WSLg XRoar. Do not infer display state from process existence alone.

## Official references

- [MAME releases](https://github.com/mamedev/mame/releases)
- [MAME command-line reference](https://docs.mamedev.org/commandline/commandline-all.html)
- [MAME Lua natural keyboard reference](https://docs.mamedev.org/luascript/ref-input.html)
- [MAME Lua cassette and screen reference](https://docs.mamedev.org/luascript/ref-devices.html)
