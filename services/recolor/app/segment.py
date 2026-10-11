"""Separate the garment from the studio.

The mask is built from the photograph itself: backdrop connected to the
frame, skin, and a small cap of hair above the face. A text prompt can
keep the whole set or only the top or bottom. Click points keep the piece
under the cursor.

This is the deterministic segmenter the MVP runs. A detector such as
Grounding DINO plus SAM 2 can replace `segment_product` later; recoloring
and compositing do not change.
"""

import re

import cv2
import numpy as np

UPPER_WORDS = ("top", "bra", "shirt", "jacket", "hoodie", "crop", "haut", "sleeve")
LOWER_WORDS = ("bottom", "legging", "pant", "short", "skirt", "bas", "trouser")
ALL_WORDS = ("set", "outfit", "workout", "ensemble", "matching", "sportswear", "coord")


def prompt_region(prompt: str) -> str:
    text = (prompt or "").lower()

    def mentioned(words: tuple[str, ...]) -> bool:
        return any(re.search(rf"\b{re.escape(word)}", text) for word in words)

    upper, lower, whole = mentioned(UPPER_WORDS), mentioned(LOWER_WORDS), mentioned(ALL_WORDS)
    if whole or (upper and lower) or not (upper or lower):
        return "all"
    return "upper" if upper else "lower"


def skin_mask(image_bgr: np.ndarray) -> np.ndarray:
    ycrcb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2YCrCb)
    _y, cr, cb = cv2.split(ycrcb)
    hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    hue, sat, value = cv2.split(hsv)
    in_ycrcb = (cr >= 135) & (cr <= 180) & (cb >= 85) & (cb <= 135) & (_y >= 60)
    # Hue stays in the red-orange skin range, so saturated pinks are not skin.
    in_hsv = (hue <= 22) & (sat >= 30) & (sat <= 160) & (value >= 70)
    return in_ycrcb & in_hsv


def _background_mask(image_bgr: np.ndarray) -> np.ndarray:
    height, width = image_bgr.shape[:2]
    lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    ring_w = max(3, int(round(min(height, width) * 0.04)))
    ring = np.zeros((height, width), dtype=bool)
    ring[:ring_w, :] = True
    ring[-ring_w:, :] = True
    ring[:, :ring_w] = True
    ring[:, -ring_w:] = True

    median = np.median(lab[ring], axis=0)
    dist = np.sqrt(
        ((lab[:, :, 0] - median[0]) * 0.55) ** 2
        + (lab[:, :, 1] - median[1]) ** 2
        + (lab[:, :, 2] - median[2]) ** 2
    )
    # Median and MAD ignore props sitting on the frame, so a plant in the
    # corner does not pull the backdrop threshold out to the garment.
    border_dist = dist[ring]
    center = float(np.median(border_dist))
    mad = float(np.median(np.abs(border_dist - center)))
    if mad < 1.5:
        threshold = 24.0
    else:
        threshold = float(np.clip(center + 8 * mad, 20, 42))
    similar = dist <= threshold
    count, labels = cv2.connectedComponents(similar.astype(np.uint8), connectivity=8)
    if count <= 1:
        return np.zeros((height, width), dtype=bool)
    border_labels = set(np.unique(labels[ring]).tolist()) - {0}
    if not border_labels:
        return np.zeros((height, width), dtype=bool)
    return np.isin(labels, list(border_labels))


def _largest_component(mask: np.ndarray, min_area: int) -> np.ndarray | None:
    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    best = None
    best_area = 0
    for index in range(1, count):
        area = int(stats[index, cv2.CC_STAT_AREA])
        if area >= min_area and area > best_area:
            best = labels == index
            best_area = area
    return best


def _hair_mask(image_bgr: np.ndarray, foreground: np.ndarray, skin: np.ndarray) -> np.ndarray:
    """A small dark cap above the face. A large head covering stays in the product."""
    empty = np.zeros(foreground.shape, dtype=bool)
    if not np.any(foreground) or not np.any(skin):
        return empty

    rows = np.where(foreground)[0]
    top, bottom = int(rows.min()), int(rows.max())
    face_limit = top + int(0.55 * (bottom - top + 1))
    upper_skin = skin.copy()
    upper_skin[face_limit:, :] = False
    face = _largest_component(upper_skin, min_area=30)
    if face is None:
        return empty

    face_rows, face_cols = np.where(face)
    face_top, face_bottom = int(face_rows.min()), int(face_rows.max())
    face_left, face_right = int(face_cols.min()), int(face_cols.max())
    face_h = max(1, face_bottom - face_top + 1)
    face_w = max(1, face_right - face_left + 1)
    height, width = foreground.shape
    y_lo = max(0, face_top - int(face_h * 1.4))
    y_hi = min(height, face_top + int(face_h * 0.45))
    x_lo = max(0, face_left - int(face_w * 0.6))
    x_hi = min(width, face_right + int(face_w * 0.6) + 1)

    lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    chroma = np.hypot(lab[:, :, 1] - 128.0, lab[:, :, 2] - 128.0)
    dark = (lab[:, :, 0] < 75) & (chroma < 18)
    window = np.zeros_like(foreground)
    window[y_lo:y_hi, x_lo:x_hi] = True
    hair = foreground & dark & ~skin & window
    # A modest head covering is much larger than the face; leave it to be recolored.
    if hair.sum() > 1.8 * face.sum():
        return empty
    return hair


def _close_and_open(mask: np.ndarray) -> np.ndarray:
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    as_bytes = mask.astype(np.uint8) * 255
    closed = cv2.morphologyEx(as_bytes, cv2.MORPH_CLOSE, kernel)
    opened = cv2.morphologyEx(closed, cv2.MORPH_OPEN, kernel)
    return opened > 0


def _drop_edge_props(mask: np.ndarray) -> np.ndarray:
    """Props touching the frame and sitting in a corner are not the garment."""
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    height, width = mask.shape
    min_area = max(80, int(0.004 * height * width))
    keep = np.zeros_like(mask)
    for index in range(1, count):
        area = int(stats[index, cv2.CC_STAT_AREA])
        if area < min_area:
            continue
        left = int(stats[index, cv2.CC_STAT_LEFT])
        top = int(stats[index, cv2.CC_STAT_TOP])
        touches = (
            left <= 1
            or top <= 1
            or left + int(stats[index, cv2.CC_STAT_WIDTH]) >= width - 1
            or top + int(stats[index, cv2.CC_STAT_HEIGHT]) >= height - 1
        )
        cx, cy = centroids[index]
        peripheral = cx < width * 0.16 or cx > width * 0.84 or cy < height * 0.12 or cy > height * 0.88
        if touches and peripheral:
            continue
        keep[labels == index] = True
    return keep


def _select_region(mask: np.ndarray, region: str) -> np.ndarray:
    if region == "all" or not np.any(mask):
        return mask
    rows = np.where(mask)[0]
    span = float(rows.max() - rows.min())
    mid = float(rows.min() + rows.max()) / 2
    count, labels, _stats, centroids = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    keep = np.zeros_like(mask)
    slack = span * 0.08
    for index in range(1, count):
        cy = float(centroids[index][1])
        if region == "upper" and cy <= mid + slack:
            keep[labels == index] = True
        elif region == "lower" and cy >= mid - slack:
            keep[labels == index] = True
    return keep


def _keep_near_points(mask: np.ndarray, points: list[tuple[float, float]]) -> tuple[np.ndarray, bool]:
    if not points or not np.any(mask):
        return mask, False
    _count, labels = cv2.connectedComponents(mask.astype(np.uint8), connectivity=8)
    height, width = mask.shape
    diag = float(np.hypot(height, width))
    chosen: set[int] = set()
    labeled_rows, labeled_cols = np.where(labels > 0)
    for x_pos, y_pos in points:
        col = int(round(min(max(x_pos, 0), width - 1)))
        row = int(round(min(max(y_pos, 0), height - 1)))
        label = int(labels[row, col])
        if label:
            chosen.add(label)
            continue
        if labeled_rows.size == 0:
            continue
        distance = (labeled_cols - col) ** 2 + (labeled_rows - row) ** 2
        nearest = int(np.argmin(distance))
        if distance[nearest] <= (0.04 * diag) ** 2:
            chosen.add(int(labels[labeled_rows[nearest], labeled_cols[nearest]]))
    if not chosen:
        return mask, True
    return np.isin(labels, list(chosen)), False


def feather(binary: np.ndarray, radius: float) -> np.ndarray:
    mask_u8 = (binary.astype(np.uint8)) * 255
    dist_in = cv2.distanceTransform(mask_u8, cv2.DIST_L2, 3)
    dist_out = cv2.distanceTransform(255 - mask_u8, cv2.DIST_L2, 3)
    soft = np.clip(0.5 + (dist_in - dist_out) / (2.0 * max(radius, 0.5)), 0, 1).astype(np.float32)
    soft[dist_out >= radius] = 0
    soft[dist_in >= radius] = 1
    return soft


def segment_product(image_bgr: np.ndarray, prompt: str = "", points: list[tuple[float, float]] | None = None) -> tuple[np.ndarray, dict]:
    skin = skin_mask(image_bgr)
    foreground = ~_background_mask(image_bgr)
    hair = _hair_mask(image_bgr, foreground, skin)
    clothing = _close_and_open(foreground & ~skin & ~hair)
    clothing = _drop_edge_props(clothing)
    region = prompt_region(prompt)
    clothing = _select_region(clothing, region)
    missed = False
    if points:
        clothing, missed = _keep_near_points(clothing, points)

    height, width = image_bgr.shape[:2]
    radius = float(np.clip(min(height, width) * 0.003, 1.25, 6))
    soft = feather(clothing, radius)
    soft[skin] = 0
    info = {
        "segmenter": "studio",
        "prompt_region": region,
        "points_missed": missed,
        "masked_fraction": round(float((soft >= 0.5).mean()), 4),
    }
    return soft, info
