#!/usr/bin/env python3
"""Run deterministic build checks and an optional WSLg XRoar smoke test."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


WINDOW_RE = re.compile(
    r'^\s*(0x[0-9a-f]+) "XRoar":.*?(\d+)x(\d+)\+[-\d]+\+[-\d]+',
    re.MULTILINE,
)

# The default XRoar MC-10 client window is 640x505. The display starts at
# (62,34); the first glyph starts at (68,70), and cells are 16x29 pixels.
# Resize captures to that reference geometry before checking the alpha screen.
SCREEN_SIZE = (640, 505)
CHAR_X = 68
CHAR_Y = 70
CHAR_WIDTH = 16
CHAR_HEIGHT = 29
GLYPH_WIDTH = 12
GLYPH_HEIGHT = 20

# True means that the corresponding cell must contain a glyph. This checks
# the distinguishing layout of the success strings without relying on OCR.
MCX_OK_PATTERN = (
    True,
    True,
    True,
    True,
    True,
    True,
    False,
    True,
    True,
    True,
    True,
    False,
    True,
    True,
)
TIMER_OK_PATTERN = (
    True,
    True,
    True,
    True,
    True,
    True,
    False,
    True,
    True,
    False,
    False,
    False,
)


class RegressionError(RuntimeError):
    """A check failed with a user-actionable diagnostic."""


@dataclass(frozen=True)
class XWindow:
    window_id: str
    width: int
    height: int


def fail(message: str) -> None:
    raise RegressionError(message)


def parse_map(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    numeric_fields = {"start", "end", "size", "exec"}
    for line in path.read_text(encoding="ascii").splitlines():
        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or key not in numeric_fields:
            continue
        raw_value = raw_value.strip()
        try:
            if raw_value.startswith("$"):
                raw_value = raw_value[1:]
            values[key] = int(raw_value, 10 if key == "size" else 16)
        except ValueError:
            fail(f"invalid map value in {path}: {line}")
    return values


def check_program_artifacts(
    root: Path, build_dir: Path, prefix: str, source_name: str
) -> dict[str, int]:
    binary = build_dir / f"{prefix}.bin"
    cassette = build_dir / f"{prefix}.c10"
    map_file = build_dir / f"{prefix}.map"
    source = root / "src" / source_name
    for path in (binary, cassette, map_file, source):
        if not path.is_file():
            fail(f"missing build artifact or source file: {path}")

    values = parse_map(map_file)
    required_map_values = ("start", "end", "size", "exec")
    missing = [key for key in required_map_values if key not in values]
    if missing:
        fail(f"map is missing fields: {', '.join(missing)}")
    if values["start"] != 0x5000 or values["exec"] != 0x5000:
        fail(
            "program must load and execute at $5000 "
            f"(map has start=${values['start']:04X}, exec=${values['exec']:04X})"
        )
    if values["end"] - values["start"] != values["size"]:
        fail("map end/start/size fields are inconsistent")
    if len(binary.read_bytes()) != values["size"]:
        fail("raw binary length does not match the assembler map")

    subprocess.run(
        [sys.executable, str(root / "scripts" / "verify_c10.py"), str(cassette)],
        cwd=root,
        check=True,
    )
    return values


def check_artifacts(root: Path, build_dir: Path) -> None:
    utility_values = check_program_artifacts(
        root, build_dir, "environment-test", "environment-test.s"
    )
    calibrator_values = check_program_artifacts(
        root, build_dir, "timing-calibrator", "timing-calibrator.s"
    )
    game_values = check_program_artifacts(root, build_dir, "space-invaders", "main.s")

    source = root / "src" / "environment-test.s"
    source_text = source.read_text(encoding="ascii")
    required_source_tokens = (
        "MCX_MAP_ALL_RAM",
        "MCX_MAP_STOCK",
        "MCX_BANK_P0",
        "MCX_BANK_P1",
        "p1_test_start",
        "all_banks_ok",
        "TIMER_PERIOD",
        "TIMER_SAMPLES",
        "timer_compare_test",
        "game_loop_start",
    )
    missing_tokens = [token for token in required_source_tokens if token not in source_text]
    if missing_tokens:
        fail(f"source is missing regression markers: {', '.join(missing_tokens)}")

    # These eight signatures are the runtime proof points for the eight
    # physical 16 KiB RAM pages: four selected by P0 and four by P1.
    signatures = ("#$A0", "#$A3", "#$A4", "#$A7", "#$B1", "#$B2", "#$B5", "#$B6")
    missing_signatures = [signature for signature in signatures if signature not in source_text]
    if missing_signatures:
        fail(f"source is missing MCX bank signatures: {', '.join(missing_signatures)}")

    calibrator_source = root / "src" / "timing-calibrator.s"
    calibrator_text = calibrator_source.read_text(encoding="ascii")
    calibrator_tokens = (
        "CAL_PERIOD_H",
        "CAL_PHASE_H",
        "CAL_EVENTS_H",
        "CAL_MODE",
        "CAL_SWEEP_ACTIVE",
        "CAL_SWEEP_START",
        "CAL_SWEEP_END",
        "CAL_SWEEP_HOLD_FRAMES",
        "CG3_GYBR",
        "BACKGROUND_BYTE",
        "cal_timer_isr",
        "cal_keyboard",
        "cal_draw_rect",
        "cal_drift_tick",
        "cal_sweep_tick",
        "cal_rearm_locked",
        "cal_key_m",
        "cal_key_p",
        "TIMER_OCF_VECTOR",
        "TIMER_PORT2",
        "cal_key_space",
    )
    missing_calibrator_tokens = [
        token for token in calibrator_tokens if token not in calibrator_text
    ]
    if missing_calibrator_tokens:
        fail(
            "timing calibrator source is missing regression markers: "
            + ", ".join(missing_calibrator_tokens)
        )

    mame_harness = root / "scripts" / "mame-calibrator-regression.lua"
    if not mame_harness.is_file():
        fail(f"missing MAME Lua calibrator harness: {mame_harness}")
    mame_harness_text = mame_harness.read_text(encoding="ascii")
    mame_harness_tokens = (
        'keyboard:post_coded("CLOADM{ENTER}")',
        'keyboard:post_coded("EXEC{ENTER}")',
        "cassette:play()",
        "screen:pixels()",
        "screen:pixel(",
        "screen:snapshot(",
        "changed_pixels",
        "PHASE_WAIT_ALPHA",
        "PHASE_WAIT_DRIFT",
        "PHASE_WAIT_SWEEP",
        "PHASE_WAIT_PAUSE",
        "machine:exit()",
        "MC-10 calibrator regression: PASS",
    )
    missing_mame_harness_tokens = [
        token for token in mame_harness_tokens if token not in mame_harness_text
    ]
    if missing_mame_harness_tokens:
        fail(
            "MAME Lua calibrator harness is missing regression markers: "
            + ", ".join(missing_mame_harness_tokens)
        )

    mame_game_harness = root / "scripts" / "mame-game-regression.lua"
    if not mame_game_harness.is_file():
        fail(f"missing MAME Lua game harness: {mame_game_harness}")
    mame_game_harness_text = mame_game_harness.read_text(encoding="ascii")
    mame_game_harness_tokens = (
        'keyboard:post_coded("CLOADM{ENTER}")',
        'keyboard:post_coded("EXEC{ENTER}")',
        "cassette:play()",
        "screen:pixels()",
        "screen:pixel(",
        'screen:snapshot("mame-game-initial.png")',
        'screen:snapshot("mame-game-fired.png")',
        'screen:snapshot("mame-game-collision.png")',
        'screen:snapshot("mame-game-alien-shot.png")',
        'screen:snapshot("mame-game-shield-damage.png")',
        'post_game_key("A",',
        'post_game_key("D",',
        'post_game_key("{SPACE}",',
        "GAME_FRAME",
        "GAME_LIVES",
        "GAME_BULLET_ACTIVE",
        "GAME_BULLET_X",
        "GAME_BULLET_Y",
        "GAME_ALIEN_SHOT_X",
        "GAME_ALIEN_SHOT_Y",
        "GAME_ALIEN_SHOT_TICK",
        "GAME_SHIELDS_ACTIVE",
        "ALIEN_LIVE",
        "game_main_loop_active",
        "program_space:write_u8",
        "LEFT PASS",
        "RIGHT PASS",
        "FIRE PASS",
        "game collision: PASS",
        "ALIEN SHOT PASS",
        "game shield damage: PASS",
        "MC-10 game regression: PASS",
    )
    missing_mame_game_harness_tokens = [
        token for token in mame_game_harness_tokens if token not in mame_game_harness_text
    ]
    if missing_mame_game_harness_tokens:
        fail(
            "MAME Lua game harness is missing regression markers: "
            + ", ".join(missing_mame_game_harness_tokens)
        )

    game_source = root / "src" / "main.s"
    game_text = game_source.read_text(encoding="ascii")
    game_tokens = (
        "CG3_GYBR",
        "SCREEN_BYTES",
        "game_draw_formation",
        "game_draw_shields",
        "game_damage_shield",
        "game_alien_shot_update",
        "game_bonus_update",
        "GAME_SCORE_0",
        "GAME_LIVES",
        "GAME_TICK",
        "TIMER_PHASE",
        "FORMATION_BUSY",
        "FORMATION_OLD_X",
        "FORMATION_NEW_ANIM",
        "game_update_formation_row",
        "BACKGROUND_COLOR",
        "ALIEN_LIVE",
        "$4C00",
        "$4C5A",
    )
    missing_game_tokens = [token for token in game_tokens if token not in game_text]
    if missing_game_tokens:
        fail(f"game source is missing regression markers: {', '.join(missing_game_tokens)}")

    print(
        "regression: build artifacts pass "
        f"(utility ${utility_values['start']:04X}/{utility_values['size']} bytes, "
        f"calibrator ${calibrator_values['start']:04X}/{calibrator_values['size']} bytes, "
        f"game ${game_values['start']:04X}/{game_values['size']} bytes)"
    )
    print("regression: cassette framing pass")
    print("regression: source covers all eight MCX bank signatures")
    print("regression: live timing calibrator markers present")
    print("regression: MAME Lua pixel harness markers present")
    print("regression: MAME Lua game harness markers present")
    print("regression: CG3 game layout and gameplay markers present")


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def list_xroar_windows() -> list[XWindow]:
    try:
        result = subprocess.run(
            ["xwininfo", "-root", "-tree"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        fail("WSLg X11 utility xwininfo is unavailable")
    return [
        XWindow(window_id, int(width), int(height))
        for window_id, width, height in WINDOW_RE.findall(result.stdout)
        if int(width) >= 300 and int(height) >= 200
    ]


def select_xroar_window(before: set[str]) -> XWindow | None:
    windows = list_xroar_windows()
    new_windows = [window for window in windows if window.window_id not in before]
    candidates = new_windows or windows
    if not candidates:
        return None
    return max(candidates, key=lambda window: window.width * window.height)


def capture_window(root: Path, window: XWindow, path: Path) -> None:
    helper = root / "scripts" / "x11_xroar.py"
    result = subprocess.run(
        [
            "python3",
            str(helper),
            "capture",
            window.window_id,
            str(window.width),
            str(window.height),
            str(path),
        ],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"X11 capture failed: {result.stderr.strip() or result.stdout.strip()}")


def is_green(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return green >= 40 and green >= red + 20 and green >= blue + 20


def line_pattern(image: object, row: int, count: int) -> tuple[bool, ...]:
    # The type is kept generic so importing Pillow is isolated to the emulator
    # stage. The object is an Image.Image at runtime.
    pattern: list[bool] = []
    for column in range(count):
        x0 = CHAR_X + column * CHAR_WIDTH
        y0 = CHAR_Y + row * CHAR_HEIGHT
        ink = any(
            is_green(image.getpixel((x, y)))  # type: ignore[attr-defined]
            for x in range(x0, x0 + GLYPH_WIDTH)
            for y in range(y0, y0 + GLYPH_HEIGHT)
        )
        pattern.append(ink)
    return tuple(pattern)


def playfield_cell_count(image: object) -> int:
    """Count occupied character cells in the gameplay area."""
    occupied = 0
    for row in range(5, 14):
        y0 = CHAR_Y + row * CHAR_HEIGHT
        for column in range(32):
            x0 = CHAR_X + column * CHAR_WIDTH
            ink = any(
                is_green(image.getpixel((x, y)))  # type: ignore[attr-defined]
                for x in range(x0, min(x0 + GLYPH_WIDTH, SCREEN_SIZE[0]))
                for y in range(y0, min(y0 + GLYPH_HEIGHT, SCREEN_SIZE[1]))
            )
            occupied += int(ink)
    return occupied


def check_screen(path: Path) -> tuple[bool, bool, bool]:
    try:
        from PIL import Image
    except ImportError:
        fail("WSLg screen checks require Python Pillow in the WSL environment")

    with Image.open(path) as original:
        image = original.convert("RGB")
        if image.size != SCREEN_SIZE:
            resampling = getattr(Image, "Resampling", Image)
            image = image.resize(SCREEN_SIZE, resampling.NEAREST)
        mcx_ok = line_pattern(image, 2, len(MCX_OK_PATTERN)) == MCX_OK_PATTERN
        timer_ok = line_pattern(image, 3, len(TIMER_OK_PATTERN)) == TIMER_OK_PATTERN
        playable_ok = playfield_cell_count(image) >= 6
    return mcx_ok, timer_ok, playable_ok


def run_emulator(root: Path, build_dir: Path, xroar: str, rom: Path, timeout: float) -> None:
    if not Path(xroar).is_file() and not command_exists(xroar):
        fail(f"XRoar executable was not found: {xroar}")
    if not rom.is_file():
        fail(f"MCX ROM was not found: {rom}")
    if not command_exists("xwininfo"):
        fail("WSLg screen check requires xwininfo")
    if not command_exists("python3"):
        fail("WSLg screen check requires python3")

    cassette = build_dir / "environment-test.c10"
    screenshot = build_dir / "regression-screen.png"
    log_path = build_dir / "regression-xroar.log"
    before = {window.window_id for window in list_xroar_windows()}
    command = [
        xroar,
        "-q",
        "-machine",
        "mc10",
        "-cart",
        "mcx128",
        "-cart-rom",
        str(rom),
        "-run",
        str(cassette),
        "-no-tape-fast",
        "-no-ratelimit",
    ]
    print("regression: launching patched XRoar screen test")
    log = log_path.open("w", encoding="utf-8", buffering=1)
    process = subprocess.Popen(
        command,
        cwd=root,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + timeout
        last_state = (False, False, False)
        while time.monotonic() < deadline:
            if process.poll() is not None:
                fail(f"XRoar exited before the expected screen state; see {log_path}")
            window = select_xroar_window(before)
            if window is not None:
                capture_window(root, window, screenshot)
                last_state = check_screen(screenshot)
                if last_state[:2] == (True, True):
                    # The timer status is written immediately before the game
                    # state is initialized. Allow the first complete redraw to
                    # finish before retaining the proof capture.
                    time.sleep(0.75)
                    capture_window(root, window, screenshot)
                    last_state = check_screen(screenshot)
                    if last_state == (True, True, True):
                        print(
                            "regression: XRoar screen pass "
                            "(MCX128 RAM: OK, TIMER: OK, playfield rendered)"
                        )
                        return
            time.sleep(0.25)
        fail(
            "XRoar screen did not reach "
            f"MCX128 RAM: OK and TIMER: OK; last state={last_state}; "
            f"capture={screenshot}; log={log_path}"
        )
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        log.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=None)
    parser.add_argument("--xroar", default=None, help="WSL path to the XRoar executable")
    parser.add_argument("--rom", type=Path, default=None, help="WSL path to an MCX ROM image")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument(
        "--skip-emulator",
        action="store_true",
        help="run build, cassette, and source checks without WSLg",
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    build_dir = args.build_dir or Path(os.environ.get("MC10_BUILD_DIR", root / "build"))
    if not build_dir.is_absolute():
        build_dir = (root / build_dir).resolve()

    try:
        check_artifacts(root, build_dir)
        if args.skip_emulator:
            print("regression: emulator stage skipped")
            return 0

        xroar = args.xroar or os.environ.get("MC10_XROAR") or "/usr/local/bin/xroar"
        rom_value = args.rom or os.environ.get("MC10_MCX_DIRECT_ROM") or os.environ.get("MC10_MCX_ROM")
        if not rom_value:
            fail(
                "MCX runtime stage requires --rom, MC10_MCX_DIRECT_ROM, or "
                "MC10_MCX_ROM"
            )
        rom = Path(rom_value)
        if not rom.is_absolute():
            rom = (root / rom).resolve()
        run_emulator(root, build_dir, xroar, rom, args.timeout)
        return 0
    except RegressionError as exc:
        print(f"regression: FAIL: {exc}", file=sys.stderr)
        return 1
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"regression: FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
