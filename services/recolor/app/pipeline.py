"""Upload → segment → recolor the garment → composite → check the scene."""

import os

import cv2
import numpy as np

from app.colors import RecolorError, normalize_hex
from app.recolor import recolor_image
from app.segment import feather, segment_product, skin_mask

MAX_EDGE = int(os.environ.get("RECOLOR_MAX_EDGE", "2000"))


def scale_points(points: list[tuple[float, float]] | None, source_shape: tuple[int, ...], dest_shape: tuple[int, ...]) -> list[tuple[float, float]]:
    """Keep click points on the garment after the working image is resized."""
    if not points:
        return []
    if source_shape[:2] == dest_shape[:2]:
        return list(points)
    scale_y = dest_shape[0] / source_shape[0]
    scale_x = dest_shape[1] / source_shape[1]
    return [(x * scale_x, y * scale_y) for x, y in points]


def limit_edge(image: np.ndarray, max_edge: int = MAX_EDGE) -> np.ndarray:
    height, width = image.shape[:2]
    edge = max(height, width)
    if edge <= max_edge:
        return image
    scale = max_edge / edge
    size = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
    return cv2.resize(image, size, interpolation=cv2.INTER_AREA)


def _prepare_mask(mask: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    channel = mask[:, :, 0] if mask.ndim == 3 else mask
    if channel.shape[:2] != shape:
        channel = cv2.resize(channel, (shape[1], shape[0]), interpolation=cv2.INTER_LINEAR)
    values = channel.astype(np.float32)
    if values.max() > 1:
        values = values / 255.0
    binary = values >= 0.5
    radius = float(np.clip(min(shape) * 0.003, 1.25, 6))
    return feather(binary, radius)


def _lightness_correlation(original: np.ndarray, output: np.ndarray, mask: np.ndarray) -> float | None:
    hard = mask >= 0.5
    if int(hard.sum()) < 20:
        return None
    before = cv2.cvtColor(original, cv2.COLOR_BGR2LAB)[:, :, 0][hard].astype(np.float32)
    after = cv2.cvtColor(output, cv2.COLOR_BGR2LAB)[:, :, 0][hard].astype(np.float32)
    if float(before.std()) < 1 or float(after.std()) < 1:
        return 1.0
    corr = float(np.corrcoef(before, after)[0, 1])
    if np.isnan(corr):
        return None
    return round(corr, 4)


def _summary(masked_fraction: float, unchanged: bool) -> str:
    percent = int(round(masked_fraction * 100))
    scene = (
        "Background, skin, and everything outside the product are unchanged."
        if unchanged
        else "Some pixels outside the product changed. Preview again before saving."
    )
    return f"Product mask covers {percent}% of the photo. {scene}"


def run(
    image_bgr: np.ndarray,
    hex_color: str,
    prompt: str = "",
    points: list[tuple[float, float]] | None = None,
    mask: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, dict]:
    color = normalize_hex(hex_color)
    image = limit_edge(image_bgr)
    clicked = scale_points(points, image_bgr.shape, image.shape)
    skin = skin_mask(image)
    if mask is None:
        soft, info = segment_product(image, prompt=prompt, points=clicked)
    else:
        soft = _prepare_mask(mask, image.shape[:2])
        soft[skin] = 0
        info = {
            "segmenter": "mask",
            "prompt_region": "mask",
            "points_missed": False,
            "masked_fraction": round(float((soft >= 0.5).mean()), 4),
        }

    if info["masked_fraction"] < 0.005:
        raise RecolorError(
            "Could not find the product. Click the garment, or use a photo where it stands apart from the backdrop."
        )

    output, applied = recolor_image(image, soft, color, skin=skin)
    outside = applied <= 0
    if np.any(outside):
        diff = np.abs(image[outside].astype(np.int16) - output[outside].astype(np.int16))
        max_diff = int(diff.max())
    else:
        max_diff = 0
    skin_changed = 0
    if np.any(skin):
        changed = np.any(image[skin].astype(np.int16) != output[skin].astype(np.int16), axis=1)
        skin_changed = int(changed.sum())

    unchanged = max_diff == 0 and skin_changed == 0
    report = {
        **info,
        "target_hex": color,
        "outside_mask_unchanged": unchanged,
        "outside_max_abs_diff": max_diff,
        "skin_pixels_changed": skin_changed,
        "lightness_correlation": _lightness_correlation(image, output, applied),
        "summary": _summary(info["masked_fraction"], unchanged),
    }
    return output, applied, report
