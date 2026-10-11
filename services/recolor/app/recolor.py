"""Material-aware recolor in Lab.

Lightness stays with the photograph for chromatic dyes (baby pink, taupe,
ocean blue), so folds, seams, and highlights survive. Near-neutral targets
such as black also move the average lightness, while local shading stays.

A logo keeps its color when its hue disagrees with the cloth around it.
"""

import cv2
import numpy as np

from app.colors import target_lab
from app.composite import composite


def _angular_delta(angles: np.ndarray, center: np.ndarray | float) -> np.ndarray:
    return np.abs(np.arctan2(np.sin(angles - center), np.cos(angles - center)))


def _detail_keep(a: np.ndarray, b: np.ndarray, chroma: np.ndarray, hard: np.ndarray) -> np.ndarray:
    """0 keeps the new dye. Values near 1 keep a logo that disagrees with the cloth around it."""
    keep = np.zeros(a.shape, dtype=np.float32)
    if hard.sum() < 10:
        return keep
    filled_a = a.copy()
    filled_b = b.copy()
    filled_a[~hard] = float(np.median(a[hard]))
    filled_b[~hard] = float(np.median(b[hard]))
    # A wide median so a logo is compared with the cloth around it, not with itself.
    kernel = int(round(min(a.shape) * 0.07))
    kernel = min(81, max(31, kernel))
    if kernel % 2 == 0:
        kernel += 1
    blur_a = cv2.medianBlur(np.clip(filled_a, 0, 255).astype(np.uint8), kernel).astype(np.float32)
    blur_b = cv2.medianBlur(np.clip(filled_b, 0, 255).astype(np.uint8), kernel).astype(np.float32)
    hue = np.arctan2(b - 128.0, a - 128.0)
    local = np.arctan2(blur_b - 128.0, blur_a - 128.0)
    delta = _angular_delta(hue, local)
    hue_gate = np.clip((delta - 0.35) / 0.45, 0, 1)
    chroma_gate = np.clip((chroma - 16.0) / 24.0, 0, 1)
    keep = hue_gate * chroma_gate * 0.92
    keep[~hard] = 0
    return keep.astype(np.float32)


def recolor_pixels(image_bgr: np.ndarray, mask: np.ndarray, hex_color: str) -> np.ndarray:
    """Return a full-frame recolor. Callers composite with the mask."""
    lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    lightness, a_channel, b_channel = cv2.split(lab)
    hard = mask >= 0.5
    if hard.sum() < 10:
        return image_bgr.copy()

    source_a = a_channel - 128.0
    source_b = b_channel - 128.0
    chroma = np.hypot(source_a, source_b)
    median_l = float(np.median(lightness[hard]))
    median_c = float(np.median(chroma[hard]))

    target = target_lab(hex_color)
    target_l, target_a, target_b = (float(target[0]), float(target[1]) - 128.0, float(target[2]) - 128.0)
    target_c = float(np.hypot(target_a, target_b))

    if target_c < 12:
        # Black, white, and other neutrals cannot be reached by hue alone.
        deviation = lightness - median_l
        new_l = np.clip(target_l + deviation * 0.62, 0, 255)
    else:
        new_l = lightness

    # Specular highlights are bright and already colorless. Fabric color is not.
    specular = np.clip((lightness - 200.0) / 40.0, 0, 1) * np.clip((18.0 - chroma) / 18.0, 0, 1)
    variation = chroma - median_c
    new_c = np.clip(target_c * (1 - 0.92 * specular) + variation * 0.15, 0, 135)
    if target_c < 1:
        new_a = np.zeros_like(source_a)
        new_b = np.zeros_like(source_b)
    else:
        new_a = target_a / target_c * new_c
        new_b = target_b / target_c * new_c

    keep = _detail_keep(a_channel, b_channel, chroma, hard)
    out_l = lightness * keep + new_l * (1 - keep)
    out_a = a_channel * keep + (new_a + 128.0) * (1 - keep)
    out_b = b_channel * keep + (new_b + 128.0) * (1 - keep)
    out_lab = cv2.merge([out_l, out_a, out_b]).clip(0, 255).astype(np.uint8)
    return cv2.cvtColor(out_lab, cv2.COLOR_LAB2BGR)


def recolor_image(image_bgr: np.ndarray, mask: np.ndarray, hex_color: str, skin: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Recolor masked pixels and composite them onto an untouched original."""
    applied = np.clip(mask.astype(np.float32), 0, 1)
    if skin is not None:
        applied[skin] = 0
    dyed = recolor_pixels(image_bgr, applied, hex_color)
    return composite(image_bgr, dyed, applied), applied
