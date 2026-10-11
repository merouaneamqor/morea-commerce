"""Hex colors and their OpenCV Lab values."""

import cv2
import numpy as np

HEX = __import__("re").compile(r"^#?[0-9A-Fa-f]{6}$")


class RecolorError(ValueError):
    """A request the service can explain to the merchant."""


def normalize_hex(value: str) -> str:
    raw = (value or "").strip()
    if not HEX.match(raw):
        raise RecolorError("Enter a color as a hex value, for example #F4C2C2.")
    digits = raw[1:] if raw.startswith("#") else raw
    return f"#{digits.upper()}"


def hex_to_bgr(value: str) -> tuple[int, int, int]:
    digits = normalize_hex(value)[1:]
    red, green, blue = int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16)
    return blue, green, red


def target_lab(value: str) -> np.ndarray:
    pixel = np.array([[list(hex_to_bgr(value))]], dtype=np.uint8)
    return cv2.cvtColor(pixel, cv2.COLOR_BGR2LAB).astype(np.float32)[0, 0]
