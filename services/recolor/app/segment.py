"""Garment-oriented segmentation for lifestyle product photos (MVP, CPU-friendly)."""

from __future__ import annotations

import cv2
import numpy as np
from PIL import Image
from rembg import remove


def _skin_mask_bgr(image_bgr: np.ndarray) -> np.ndarray:
    """Rough skin exclusion so rembg foreground can be narrowed to clothing."""
    ycrcb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2YCrCb)
    cr, cb = ycrcb[:, :, 1], ycrcb[:, :, 2]
    skin = (cr >= 133) & (cr <= 173) & (cb >= 77) & (cb <= 127)

    hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]
    skin |= (h <= 25) & (s >= 30) & (s <= 180) & (v >= 60)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    skin_u8 = (skin.astype(np.uint8) * 255)
    skin_u8 = cv2.morphologyEx(skin_u8, cv2.MORPH_CLOSE, kernel, iterations=1)
    skin_u8 = cv2.morphologyEx(skin_u8, cv2.MORPH_OPEN, kernel, iterations=1)
    return skin_u8


def _foreground_alpha(image_bgr: np.ndarray) -> np.ndarray:
    pil = Image.fromarray(cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB))
    out = remove(pil)
    if out.mode != "RGBA":
        out = out.convert("RGBA")
    alpha = np.array(out)[:, :, 3]
    return alpha


def segment_garment(image_bgr: np.ndarray, *, exclude_skin: bool = True) -> np.ndarray:
    """
    Build a soft garment mask: rembg foreground minus skin (and similar tones).

    For isolated product shots, rembg alone is usually enough; for on-model shots,
    skin exclusion keeps faces and limbs out of the recolor region.
    """
    alpha = _foreground_alpha(image_bgr)
    mask = (alpha > 32).astype(np.uint8) * 255

    if exclude_skin:
        skin = _skin_mask_bgr(image_bgr)
        mask = cv2.bitwise_and(mask, cv2.bitwise_not(skin))

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    return mask


def mask_from_bytes(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, dtype=np.uint8)
    mask = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if mask is None:
        raise ValueError("Could not decode mask")
    return mask


def mask_to_png(mask: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".png", mask)
    if not ok:
        raise RuntimeError("Failed to encode mask PNG")
    return buf.tobytes()
