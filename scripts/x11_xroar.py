#!/usr/bin/env python3
"""Minimal X11 control and capture helper for WSLg XRoar."""

import argparse
import ctypes
import os
import time
from ctypes import POINTER, Structure, byref, c_int, c_uint, c_ulong, c_void_p

from PIL import Image


class XImage(Structure):
    _fields_ = [
        ("width", c_int),
        ("height", c_int),
        ("xoffset", c_int),
        ("format", c_int),
        ("data", c_void_p),
        ("byte_order", c_int),
        ("bitmap_unit", c_int),
        ("bitmap_bit_order", c_int),
        ("bitmap_pad", c_int),
        ("depth", c_int),
        ("bytes_per_line", c_int),
        ("bits_per_pixel", c_int),
        ("red_mask", c_ulong),
        ("green_mask", c_ulong),
        ("blue_mask", c_ulong),
        ("obdata", c_void_p),
        ("funcs", c_void_p),
    ]


class X11:
    XK_SHIFT_L = 0xFFE1
    XK_CONTROL_L = 0xFFE3
    XK_ALT_L = 0xFFE9
    XK_RETURN = 0xFF0D

    def __init__(self):
        self.lib = ctypes.CDLL("libX11.so.6")
        self.xtest = ctypes.CDLL("libXtst.so.6")
        self.lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.lib.XOpenDisplay.restype = c_void_p
        self.dpy = self.lib.XOpenDisplay(os.environ.get("DISPLAY", ":0").encode())
        if not self.dpy:
            raise RuntimeError("XOpenDisplay failed")
        self.lib.XKeysymToKeycode.argtypes = [c_void_p, c_ulong]
        self.lib.XKeysymToKeycode.restype = ctypes.c_ubyte
        self.lib.XSetInputFocus.argtypes = [c_void_p, c_ulong, c_int, c_ulong]
        self.lib.XWarpPointer.argtypes = [c_void_p, c_ulong, c_ulong, c_int, c_int, c_uint, c_uint, c_int, c_int]
        self.lib.XFlush.argtypes = [c_void_p]
        self.lib.XInternAtom.argtypes = [c_void_p, ctypes.c_char_p, c_int]
        self.lib.XInternAtom.restype = c_ulong
        self.lib.XSendEvent.argtypes = [c_void_p, c_ulong, c_int, c_ulong, c_void_p]
        self.lib.XDefaultRootWindow.argtypes = [c_void_p]
        self.lib.XDefaultRootWindow.restype = c_ulong
        self.lib.XRaiseWindow.argtypes = [c_void_p, c_ulong]
        self.xtest.XTestFakeKeyEvent.argtypes = [c_void_p, ctypes.c_ubyte, c_int, c_ulong]
        self.xtest.XTestFakeButtonEvent.argtypes = [c_void_p, ctypes.c_uint, c_int, c_ulong]
        self.lib.XGetImage.argtypes = [c_void_p, c_ulong, c_int, c_int, c_uint, c_uint, c_ulong, c_int]
        self.lib.XGetImage.restype = POINTER(XImage)
        self.lib.XGetPixel.argtypes = [POINTER(XImage), c_int, c_int]
        self.lib.XGetPixel.restype = c_ulong

    def keycode(self, keysym):
        return self.lib.XKeysymToKeycode(self.dpy, keysym)

    def key(self, keysym, down=True):
        self.xtest.XTestFakeKeyEvent(self.dpy, self.keycode(keysym), int(down), 0)

    def text(self, value):
        for char in value:
            keysym = ord(char.lower()) if char.isalpha() else ord(char)
            self.key(keysym, True)
            time.sleep(0.03)
            self.key(keysym, False)
            time.sleep(0.03)
        self.key(self.XK_RETURN, True)
        self.key(self.XK_RETURN, False)
        self.lib.XFlush(self.dpy)

    def focus(self, window):
        self.lib.XSetInputFocus(self.dpy, window, 2, 0)
        self.lib.XFlush(self.dpy)

    def click_relative(self, window, x, y):
        self.lib.XWarpPointer(self.dpy, 0, window, 0, 0, 0, 0, x, y)
        self.xtest.XTestFakeButtonEvent(self.dpy, 1, 1, 0)
        self.xtest.XTestFakeButtonEvent(self.dpy, 1, 0, 0)
        self.lib.XFlush(self.dpy)

    def capture(self, window, width, height, path):
        image = self.lib.XGetImage(self.dpy, window, 0, 0, width, height, 0xFFFFFFFF, 2)
        if not image:
            raise RuntimeError("XGetImage failed")
        output = Image.new("RGB", (width, height))
        pixels = output.load()
        for y in range(height):
            for x in range(width):
                value = self.lib.XGetPixel(image, x, y)
                pixels[x, y] = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        output.save(path)

    def close(self, window):
        class XClientMessageEvent(Structure):
            _fields_ = [
                ("type", c_int),
                ("serial", c_ulong),
                ("send_event", c_int),
                ("display", c_void_p),
                ("window", c_ulong),
                ("message_type", c_ulong),
                ("format", c_int),
                ("data", c_ulong * 5),
            ]

        wm_protocols = self.lib.XInternAtom(self.dpy, b"WM_PROTOCOLS", 0)
        wm_delete = self.lib.XInternAtom(self.dpy, b"WM_DELETE_WINDOW", 0)
        event = XClientMessageEvent(
            33, 0, 1, self.dpy, window, wm_protocols, 32,
            (wm_delete, 0, 0, 0, 0),
        )
        self.lib.XSendEvent(self.dpy, window, 0, 0, byref(event))
        self.lib.XFlush(self.dpy)

    def activate(self, window):
        class XClientMessageEvent(Structure):
            _fields_ = [
                ("type", c_int),
                ("serial", c_ulong),
                ("send_event", c_int),
                ("display", c_void_p),
                ("window", c_ulong),
                ("message_type", c_ulong),
                ("format", c_int),
                ("data", c_ulong * 5),
            ]

        root = self.lib.XDefaultRootWindow(self.dpy)
        active_atom = self.lib.XInternAtom(self.dpy, b"_NET_ACTIVE_WINDOW", 0)
        event = XClientMessageEvent(
            33, 0, 1, self.dpy, window, active_atom, 32,
            (1, 0, window, 0, 0),
        )
        self.lib.XSendEvent(self.dpy, root, 0x00000001 | 0x00000002, 0, byref(event))
        self.lib.XRaiseWindow(self.dpy, window)
        self.lib.XSetInputFocus(self.dpy, window, 2, 0)
        self.lib.XFlush(self.dpy)


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    click = subparsers.add_parser("click")
    click.add_argument("window", type=lambda value: int(value, 0))
    click.add_argument("x", type=int)
    click.add_argument("y", type=int)

    type_command = subparsers.add_parser("type")
    type_command.add_argument("window", type=lambda value: int(value, 0))
    type_command.add_argument("text")

    hotkey = subparsers.add_parser("hotkey")
    hotkey.add_argument("window", type=lambda value: int(value, 0))
    hotkey.add_argument("modifier")
    hotkey.add_argument("key")

    combo = subparsers.add_parser("combo")
    combo.add_argument("window", type=lambda value: int(value, 0))
    combo.add_argument("modifiers", help="comma-separated modifier names")
    combo.add_argument("key")

    press = subparsers.add_parser("press")
    press.add_argument("window", type=lambda value: int(value, 0))
    press.add_argument("key")

    hold = subparsers.add_parser("hold")
    hold.add_argument("window", type=lambda value: int(value, 0))
    hold.add_argument("key")
    hold.add_argument("duration_ms", type=int)

    capture = subparsers.add_parser("capture")
    capture.add_argument("window", type=lambda value: int(value, 0))
    capture.add_argument("width", type=int)
    capture.add_argument("height", type=int)
    capture.add_argument("path")

    close = subparsers.add_parser("close")
    close.add_argument("window", type=lambda value: int(value, 0))

    activate = subparsers.add_parser("activate")
    activate.add_argument("window", type=lambda value: int(value, 0))

    args = parser.parse_args()
    x11 = X11()
    if args.command == "click":
        x11.click_relative(args.window, args.x, args.y)
    elif args.command == "type":
        x11.focus(args.window)
        time.sleep(0.2)
        x11.text(args.text)
    elif args.command == "hotkey":
        x11.focus(args.window)
        modifier = getattr(x11, "XK_" + args.modifier.upper() + "_L")
        x11.key(modifier, True)
        keysyms = {"return": x11.XK_RETURN, "f4": 0xFFC1, "escape": 0xFF1B}
        keysym = keysyms[args.key.lower()] if args.key.lower() in keysyms else ord(args.key.lower())
        x11.key(keysym, True)
        x11.key(keysym, False)
        x11.key(modifier, False)
        x11.lib.XFlush(x11.dpy)
    elif args.command == "combo":
        x11.focus(args.window)
        modifiers = [
            getattr(x11, "XK_" + modifier.strip().upper() + "_L")
            for modifier in args.modifiers.split(",")
        ]
        for modifier in modifiers:
            x11.key(modifier, True)
        keysyms = {"return": x11.XK_RETURN, "f4": 0xFFC1, "escape": 0xFF1B}
        keysym = keysyms[args.key.lower()] if args.key.lower() in keysyms else ord(args.key.lower())
        x11.key(keysym, True)
        x11.key(keysym, False)
        for modifier in reversed(modifiers):
            x11.key(modifier, False)
        x11.lib.XFlush(x11.dpy)
    elif args.command == "press":
        keysyms = {
            "return": x11.XK_RETURN,
            "escape": 0xFF1B,
            "f4": 0xFFC1,
            "space": 0x0020,
        }
        keysym = keysyms[args.key.lower()] if args.key.lower() in keysyms else ord(args.key.lower())
        x11.focus(args.window)
        x11.key(keysym, True)
        x11.key(keysym, False)
        x11.lib.XFlush(x11.dpy)
    elif args.command == "hold":
        keysyms = {"return": x11.XK_RETURN, "escape": 0xFF1B, "f4": 0xFFC1, "space": 0x0020}
        keysym = keysyms[args.key.lower()] if args.key.lower() in keysyms else ord(args.key.lower())
        x11.focus(args.window)
        x11.key(keysym, True)
        time.sleep(max(args.duration_ms, 1) / 1000.0)
        x11.key(keysym, False)
        x11.lib.XFlush(x11.dpy)
    elif args.command == "close":
        x11.close(args.window)
    elif args.command == "activate":
        x11.activate(args.window)
    else:
        x11.capture(args.window, args.width, args.height, args.path)
    print("ok")


if __name__ == "__main__":
    main()
