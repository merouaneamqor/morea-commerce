"""I_out = (1 - M) I_original + M I_recolored.

Pixels where the mask is 0 are copied from the original, so the backdrop,
skin, and anything else outside the product stay byte-for-byte identical.
"""

import numpy as np


def composite(original: np.ndarray, recolored: np.ndarray, mask: np.ndarray) -> np.ndarray:
    if original.shape != recolored.shape:
        raise ValueError("Original and recolored images must match.")
    if mask.shape[:2] != original.shape[:2] or mask.ndim != 2:
        raise ValueError("Mask must be a single channel the size of the image.")

    alpha = np.clip(mask.astype(np.float32), 0, 1)
    out = original.copy()
    hard = alpha >= 1
    soft = (alpha > 0) & ~hard
    if np.any(hard):
        out[hard] = recolored[hard]
    if np.any(soft):
        weight = alpha[soft, None]
        mixed = original[soft].astype(np.float32) * (1 - weight) + recolored[soft].astype(np.float32) * weight
        out[soft] = np.rint(np.clip(mixed, 0, 255)).astype(np.uint8)
    return out
