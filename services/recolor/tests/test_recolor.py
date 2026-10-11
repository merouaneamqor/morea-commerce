import io

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.colors import normalize_hex
from app.composite import composite
from app.main import app
from app.pipeline import run, scale_points
from app.recolor import recolor_image
from app.segment import prompt_region


def _hue(pixel_bgr: np.ndarray) -> float:
    lab = cv2.cvtColor(pixel_bgr.reshape(1, 1, 3), cv2.COLOR_BGR2LAB).astype(np.float32)[0, 0]
    return float(np.arctan2(lab[2] - 128.0, lab[1] - 128.0))


def _angular(a: float, b: float) -> float:
    return abs(float(np.arctan2(np.sin(a - b), np.cos(a - b))))


def studio_photo() -> np.ndarray:
    image = np.full((400, 300, 3), (210, 210, 210), np.uint8)
    image[80:200, 0:40] = (40, 140, 40)  # plant touching the left edge
    image[40:78, 120:180] = (30, 30, 30)  # hair
    cv2.ellipse(image, (150, 112), (28, 36), 0, 0, 360, (180, 200, 230), -1)
    cv2.circle(image, (88, 228), 12, (170, 190, 225), -1)
    cv2.circle(image, (214, 228), 12, (170, 190, 225), -1)
    image[150:230, 110:190] = (150, 140, 220)  # pink top, distinct from skin
    image[150:230, 110:140] = (115, 105, 175)  # fold
    image[175:190, 140:155] = (20, 220, 240)  # yellow logo
    image[250:340, 120:185] = (90, 45, 30)  # navy leggings
    image[250:340, 120:145] = (55, 28, 18)  # fold
    return image


def test_composite_uses_the_mask_and_keeps_exact_originals():
    original = np.zeros((2, 2, 3), np.uint8)
    original[0, 0] = (10, 20, 30)
    original[0, 1] = (1, 2, 3)
    original[1, 0] = (40, 50, 60)
    original[1, 1] = (7, 8, 9)
    recolored = np.full_like(original, 200)
    mask = np.array([[0, 1], [0.5, 0]], np.float32)

    out = composite(original, recolored, mask)

    assert np.array_equal(out[0, 0], original[0, 0])
    assert np.array_equal(out[1, 1], original[1, 1])
    assert np.array_equal(out[0, 1], recolored[0, 1])
    expected = np.rint(original[1, 0].astype(np.float32) * 0.5 + 200 * 0.5).astype(np.uint8)
    assert np.array_equal(out[1, 0], expected)


def test_chromatic_recolor_keeps_lightness_and_moves_hue():
    image = np.full((80, 80, 3), (220, 220, 220), np.uint8)
    image[20:60, 20:60] = (180, 180, 210)
    image[20:60, 20:35] = (120, 120, 150)
    mask = np.zeros((80, 80), np.float32)
    mask[20:60, 20:60] = 1

    out, applied = recolor_image(image, mask, "#1F4E79")

    assert np.array_equal(out[0, 0], image[0, 0])
    assert np.all(applied[0] == 0)
    before = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
    after = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32)
    # The fold stays darker than the lit face of the cloth.
    assert after[30, 25, 0] < after[30, 50, 0]
    corr = np.corrcoef(before[20:60, 20:60, 0].ravel(), after[20:60, 20:60, 0].ravel())[0, 1]
    assert corr > 0.95
    assert _angular(_hue(out[30, 50]), _hue(np.array([121, 78, 31], np.uint8))) < 0.35


def test_black_recolor_darkens_but_keeps_the_fold():
    image = np.full((80, 80, 3), (230, 230, 230), np.uint8)
    image[20:60, 20:60] = (200, 200, 200)
    image[20:60, 20:35] = (150, 150, 150)
    mask = np.zeros((80, 80), np.float32)
    mask[20:60, 20:60] = 1

    out, _applied = recolor_image(image, mask, "#1A1716")

    assert np.array_equal(out[5, 5], image[5, 5])
    assert out[30, 50].mean() < 80
    assert out[30, 25].mean() < out[30, 50].mean()


def test_logo_keeps_its_hue():
    image = np.full((90, 90, 3), (200, 200, 200), np.uint8)
    image[15:75, 15:75] = (140, 150, 210)
    logo = (20, 220, 240)
    image[40:55, 40:55] = logo
    mask = np.zeros((90, 90), np.float32)
    mask[15:75, 15:75] = 1

    out, _applied = recolor_image(image, mask, "#1F4E79")
    target = np.array([121, 78, 31], np.uint8)

    assert _angular(_hue(out[47, 47]), _hue(np.array(logo, np.uint8))) < _angular(_hue(out[47, 47]), _hue(target))
    assert _angular(_hue(out[25, 60]), _hue(target)) < 0.45


def test_studio_photo_recolors_the_set_and_leaves_the_scene():
    image = studio_photo()
    output, mask, report = run(image, "#1F4E79", prompt="the matching workout set")

    assert report["outside_mask_unchanged"] is True
    assert report["outside_max_abs_diff"] == 0
    assert report["skin_pixels_changed"] == 0
    assert report["prompt_region"] == "all"
    assert np.array_equal(output[10, 10], image[10, 10])  # backdrop
    assert np.array_equal(output[140, 10], image[140, 10])  # plant
    assert np.array_equal(output[112, 150], image[112, 150])  # face
    assert np.array_equal(output[55, 150], image[55, 150])  # hair
    assert mask[180, 165] > 0.8  # top
    assert mask[300, 160] > 0.8  # leggings
    assert report["lightness_correlation"] > 0.9
    target = np.array([121, 78, 31], np.uint8)
    assert _angular(_hue(output[165, 170]), _hue(target)) < 0.45
    assert _angular(_hue(output[182, 147]), _hue(image[182, 147])) < 0.5


def test_prompt_and_click_can_limit_the_garment():
    image = studio_photo()
    _top, top_mask, top_report = run(image, "#F4C2C2", prompt="the top")
    assert top_report["prompt_region"] == "upper"
    assert top_mask[180, 165] > 0.8
    assert top_mask[300, 160] == 0

    _clicked, click_mask, _report = run(image, "#F4C2C2", prompt="the matching workout set", points=[(165, 180)])
    assert click_mask[180, 165] > 0.8
    assert click_mask[300, 160] == 0


def test_scale_points_when_the_photo_is_shrunk():
    assert scale_points([(100, 40)], (80, 200, 3), (40, 100, 3)) == [(50.0, 20.0)]
    assert scale_points([], (80, 200), (40, 100)) == []
    assert scale_points([(3, 4)], (10, 10), (10, 10)) == [(3, 4)]


def test_prompt_regions():
    assert prompt_region("the matching workout set") == "all"
    assert prompt_region("the top") == "upper"
    assert prompt_region("leggings") == "lower"
    assert prompt_region("") == "all"


def test_blank_backdrop_is_rejected():
    with pytest.raises(Exception, match="Could not find the product"):
        run(np.full((80, 80, 3), 180, np.uint8), "#1F4E79")


def test_token_guards_recolor_but_not_health(monkeypatch):
    monkeypatch.setenv("RECOLOR_TOKEN", "secret")
    client = TestClient(app)
    assert client.get("/health").status_code == 200

    png = io.BytesIO()
    Image.new("RGB", (8, 8), (180, 180, 180)).save(png, format="PNG")
    files = {"image": ("blank.png", png.getvalue(), "image/png")}
    denied = client.post("/v1/recolor", files=files, data={"color": "#111111"})
    assert denied.status_code == 401

    allowed = client.post(
        "/v1/recolor",
        headers={"Authorization": "Bearer secret"},
        files=files,
        data={"color": "nope"},
    )
    assert allowed.status_code == 422


def test_http_rejects_a_bad_color():
    client = TestClient(app)
    png = io.BytesIO()
    Image.new("RGB", (8, 8), (180, 180, 180)).save(png, format="PNG")
    response = client.post(
        "/v1/recolor",
        files={"image": ("blank.png", png.getvalue(), "image/png")},
        data={"color": "nope"},
    )
    assert response.status_code == 422
    assert "hex" in response.json()["error"].lower()


def test_hex_normalization():
    assert normalize_hex("1f4e79") == "#1F4E79"
    with pytest.raises(Exception):
        normalize_hex("blue")


def test_http_recolor_round_trip():
    rgb = cv2.cvtColor(studio_photo(), cv2.COLOR_BGR2RGB)
    buf = io.BytesIO()
    Image.fromarray(rgb).save(buf, format="PNG")
    client = TestClient(app)
    response = client.post(
        "/v1/recolor",
        files={"image": ("look.png", buf.getvalue(), "image/png")},
        data={"color": "#9A8B7A", "prompt": "the matching workout set", "points": "[]"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["report"]["outside_mask_unchanged"] is True
    assert body["report"]["target_hex"] == "#9A8B7A"
    png = base64_image(body["image_png_base64"])
    assert png.shape[0] == 400


def base64_image(payload: str) -> np.ndarray:
    import base64

    raw = base64.b64decode(payload)
    array = np.frombuffer(raw, np.uint8)
    decoded = cv2.imdecode(array, cv2.IMREAD_COLOR)
    assert decoded is not None
    return decoded
