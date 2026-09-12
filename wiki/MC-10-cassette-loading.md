# MC-10 Cassette Loading

[Home](Home) · [Build workflow](Build-and-emulator-workflow) · [MAME regression](MAME-regression-path)

## Stage meanings

1. `CLOADM` enters the machine-language cassette loader.
2. Playback supplies the audio data. A visible `S` means the loader is searching.
3. After transfer, BASIC displays the file name and returns to `OK`.
4. `EXEC` enters the loaded image, normally at `$5000` for this project.

## Manual XRoar sequence

```text
xroar -machine mc10 -load-tape build/timing-calibrator.c10
```

1. Focus the MC-10 display.
2. Type `CLOADM` and press Return.
3. Press `Ctrl+T` to open cassette controls.
4. Select the input tape and press `Play` once while the loader shows its search state.
5. Wait for the tape to stop and BASIC to return to `OK`.
6. Type `EXEC` and press Return.

Do not press Reset between `CLOADM` and Play. Do not start playback before entering `CLOADM`.

## MCX BASIC sequence

The MCX-128 EPROM presents a boot menu before BASIC is available. Select `2`, MCX BASIC (LARGE), and wait for the memory test and ROM-copy operation to finish. Then use the same `CLOADM`, Play, wait for `OK`, and `EXEC` sequence.

The MCX-128 supplies firmware and memory mapping. It does not load or execute cassette data itself.

## MAME sequence

```text
mame.exe mc10 -ramsize 20K -cass build\timing-calibrator.c10
```

Enter `CLOADM`, press Return, press MAME's default `F2` tape-play key, wait for `OK`, then enter `EXEC` and press Return. `Shift+F2` stops the tape.

The automated equivalent is [scripts/mame-cassette-autoplay.lua](https://github.com/Rastamafugg/mc10-space-invaders/blob/main/scripts/mame-cassette-autoplay.lua). It uses `post_coded` with `{ENTER}`, `cassette:play()`, cassette-position detection, `EXEC{ENTER}`, and the MC-10 screen snapshot API.

## Failure diagnosis

| Display or behavior | Likely cause |
| --- | --- |
| Reverse `@` screen | MCX cartridge profile is attached without a valid MCX ROM |
| No cursor or BASIC prompt | Firmware is still in boot or memory-test code, or an incompatible direct ROM was selected |
| `S` remains indefinitely | Playback was not started correctly or the image/audio path is incompatible |
| File name and `OK`, but no program screen | `EXEC` was not entered, was entered while the loader was still active, or was not accepted |
| `MCX128 ERROR` followed by timer output | The program executed without MCX bank registers; this validates cassette execution, not MCX banking |
