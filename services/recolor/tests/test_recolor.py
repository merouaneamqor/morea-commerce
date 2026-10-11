"""Unit tests for Lab recoloring (no rembg)."""

import numpy as np
import cv2

from app.recolor import recolor_lab


def test_recolor_preserves_outside_mask():
    image = np.zeros((40, 40, 3), dtype=np.uint8)
    image[:, :] = (30, 120, 200)  # BGR background
    mask = np.zeros((40, 40), dtype=np.uint8)
    mask[10:30, 10:30] = 255

    out = recolor_lab(image, mask, "#FF00FF")
    assert np.allclose(out[0, 0], image[0, 0])
    assert not np.allclose(out[20, 20], image[20, 20])
