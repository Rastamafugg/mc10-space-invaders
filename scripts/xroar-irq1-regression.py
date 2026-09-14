#!/usr/bin/env python3
"""Run the IRQ1 sanity cassette in XRoar and verify its rendered result."""

from __future__ import annotations

import argparse
import os
import re
import signal
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


SCREEN_SIZE = (640, 505)
CHAR_X = 68
CHAR_Y = 70
CHAR_WIDTH = 16
CHAR_HEIGHT = 29
GLYPH_WIDTH = 12
GLYPH_HEIGHT = 20
WINDOW_RE = re.compile(
    r'^\s*(0x[0-9a-f]+) "XRoar":.*?(\d+)x(\d+)\+[-\d]+\+[-\d]+',
    re.MULTILINE,
)


@dataclass(frozen=True)
class XWindow:
    window_id: str
    width: int
    height: int


class RegressionError(RuntimeError):
    pass


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def fail(message: str) -> None:
    raise RegressionError(message)


def list_xroar_windows() -> list[XWindow]:
    try:
        result = subprocess.run(
            ["xwininfo", "-root", "-tree"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        fail(f"xwininfo is unavailable: {exc}")
    return [
        XWindow(window_id, int(width), int(height))
        for window_id, width, height in WINDOW_RE.findall(result.stdout)
        if int(width) >= 300 and int(height) >= 200
    ]


def select_xroar_window(before: set[str]) -> XWindow | None:
    windows = list_xroar_windows()
    new_windows = [window for window in windows if window.window_id not in before]
    candidates = new_windows or windows
    return max(candidates, key=lambda window: window.width * window.height) if candidates else None


def capture_window(root: Path, window: XWindow, output: Path) -> None:
    result = subprocess.run(
        [
            "python3",
            str(root / "scripts" / "x11_xroar.py"),
            "capture",
            window.window_id,
            str(window.width),
            str(window.height),
            str(output),
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


def cell_mask(image: object, y0: int, column: int) -> frozenset[tuple[int, int]]:
    x0 = CHAR_X + column * CHAR_WIDTH
    return frozenset(
        (x - x0, y - y0)
        for x in range(x0, x0 + GLYPH_WIDTH)
        for y in range(y0, y0 + GLYPH_HEIGHT)
        if is_green(image.getpixel((x, y)))  # type: ignore[attr-defined]
    )


def green_line_starts(image: object) -> list[int]:
    starts: list[int] = []
    active = False
    for y in range(getattr(image, "height")):
        line_has_ink = any(
            is_green(image.getpixel((x, y)))  # type: ignore[attr-defined]
            for x in range(CHAR_X, min(CHAR_X + 32 * CHAR_WIDTH, getattr(image, "width")))
        )
        if line_has_ink and not active:
            starts.append(y)
        active = line_has_ink
    return starts


def line_pattern_at(image: object, y0: int, count: int) -> tuple[bool, ...]:
    return tuple(bool(cell_mask(image, y0, column)) for column in range(count))


def check_screen(path: Path) -> tuple[bool, str]:
    try:
        from PIL import Image
    except ImportError:
        fail("XRoar IRQ1 screen checks require Python Pillow")

    with Image.open(path) as original:
        image = original.convert("RGB")
        if image.size != SCREEN_SIZE:
            resampling = getattr(Image, "Resampling", Image)
            image = image.resize(SCREEN_SIZE, resampling.NEAREST)

        lines = green_line_starts(image)
        inactive_pattern = (True, True, True, True, True, False, True, True, True, True, True, True, True, True)
        count_prefix_pattern = (True, True, True, True, False, True, True, True, True, True, True, False)
        inactive = len(lines) >= 3 and line_pattern_at(image, lines[1], 14) == inactive_pattern
        count_prefix = len(lines) >= 3 and line_pattern_at(image, lines[2], 12) == count_prefix_pattern
        high_count = cell_mask(image, lines[2], 12) if len(lines) >= 3 else frozenset()
        low_count = cell_mask(image, lines[2], 13) if len(lines) >= 3 else frozenset()
        count_zero_pair = bool(high_count) and high_count == low_count

    if inactive and count_prefix and count_zero_pair:
        return True, "IRQ1: INACTIVE, count cells are 00"
    return False, (
        f"lines={lines} inactive={inactive} count_prefix={count_prefix} "
        f"count_zero_pair={count_zero_pair}"
    )


def terminate(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2)


def run(root: Path, build_dir: Path, xroar: str, timeout: float) -> None:
    if not Path(xroar).is_file() and not command_exists(xroar):
        fail(f"XRoar executable was not found: {xroar}")
    if not command_exists("xwininfo"):
        fail("WSLg screen check requires xwininfo")

    cassette = build_dir / "irq1-sanity.c10"
    screenshot = build_dir / "irq1-xroar-screen.png"
    log_path = build_dir / "irq1-xroar.log"
    if not cassette.is_file():
        fail(f"IRQ1 cassette was not found: {cassette}")

    before = {window.window_id for window in list_xroar_windows()}
    command = [
        xroar,
        "-q",
        "-machine",
        "mc10",
        "-run",
        str(cassette),
        "-no-tape-fast",
        "-no-ratelimit",
    ]
    print("XRoar IRQ1: launching bare MC-10 cassette test")
    with log_path.open("w", encoding="utf-8", buffering=1) as log:
        process = subprocess.Popen(
            command,
            cwd=root,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + timeout
            last_reason = "window not found"
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    fail(f"XRoar exited before IRQ1 result; see {log_path}")
                window = select_xroar_window(before)
                if window is not None:
                    try:
                        capture_window(root, window, screenshot)
                    except RegressionError as exc:
                        # WSLg can publish the X11 window before its drawable
                        # has a valid image. Retry the same discovery path.
                        last_reason = str(exc)
                    else:
                        passed, reason = check_screen(screenshot)
                        last_reason = reason
                        if passed:
                            print(f"XRoar IRQ1 sanity: PASS ({reason})")
                            print(f"XRoar IRQ1 capture: {screenshot}")
                            return
                time.sleep(0.25)
            fail(
                "XRoar IRQ1 result was not visible before timeout; "
                f"last={last_reason}; capture={screenshot}; log={log_path}"
            )
        finally:
            terminate(process)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=None)
    parser.add_argument("--xroar", default=None)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    build_dir = args.build_dir or Path(os.environ.get("MC10_BUILD_DIR", root / "build"))
    if not build_dir.is_absolute():
        build_dir = (root / build_dir).resolve()
    xroar = args.xroar or os.environ.get("MC10_XROAR") or "/usr/local/bin/xroar"
    try:
        run(root, build_dir, xroar, args.timeout)
        return 0
    except RegressionError as exc:
        print(f"XRoar IRQ1 sanity: FAIL: {exc}", file=sys.stderr)
        return 1
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"XRoar IRQ1 sanity: FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
