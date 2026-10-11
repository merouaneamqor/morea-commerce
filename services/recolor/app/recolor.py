"""Material-aware recoloring in Lab space with soft-mask compositing."""

from __future__ import annotations

import numpy as np
import cv2


def _parse_hex(hex_color: str) -> tuple[int, int, int]:
    raw = hex_color.strip().lstrip("#")
    if len(raw) == 3:
        raw = "".join(c * 2 for c in raw)
    if len(raw) != 6:
        raise ValueError(f"Invalid hex color: {hex_color}")
    r = int(raw[0:2], 16)
    g = int(raw[2:4], 16)
    b = int(raw[4:6], 16)
    return b, g, r  # BGR for OpenCV


def soften_mask(mask: np.ndarray, blur_radius: float = 3.0) -> np.ndarray:
    m = mask.astype(np.float32)
    if m.max() > 1.0:
        m /= 255.0
    if blur_radius > 0:
        m = cv2.GaussianBlur(m, (0, 0), blur_radius)
    return np.clip(m, 0.0, 1.0)


def recolor_lab(
    image_bgr: np.ndarray,
    mask: np.ndarray,
    hex_color: str,
    *,
    chroma_strength: float = 0.88,
    lightness_blend: float = 0.12,
) -> np.ndarray:
    """
    Shift hue/chroma inside the mask while preserving fabric texture via the L channel.

    Composites as: out = (1 - M) * original + M * recolored
    """
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("image must be BGR with 3 channels")

    m = soften_mask(mask)
    target_bgr = np.uint8([[_parse_hex(hex_color)]])
    target_lab = cv2.cvtColor(target_bgr, cv2.COLOR_BGR2LAB)[0, 0].astype(np.float32)

    lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    recolored = lab.copy()

    for channel in (1, 2):
        recolored[:, :, channel] = (
            lab[:, :, channel] * (1.0 - m * chroma_strength) + target_lab[channel] * (m * chroma_strength)
        )

    target_l = float(target_lab[0])
    recolored[:, :, 0] = lab[:, :, 0] * (1.0 - m * lightness_blend) + target_l * (m * lightness_blend)

    recolored_bgr = cv2.cvtColor(np.clip(recolored, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)

    m3 = m[:, :, np.newaxis]
    original = image_bgr.astype(np.float32)
    blended = original * (1.0 - m3) + recolored_bgr.astype(np.float32) * m3
    return np.clip(blended, 0, 255).astype(np.uint8)


def encode_png(image_bgr: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".png", image_bgr)
    if not ok:
        raise RuntimeError("Failed to encode PNG")
    return buf.tobytes()


def decode_image(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, dtype=np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Could not decode image")
    return image


def decode_mask(data: bytes) -> np.ndarray:
    arr = np.frombuffer(data, dtype=np.uint8)
    mask = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if mask is None:
        raise ValueError("Could not decode mask")
    return mask
