"""HTTP API for the Rails app.

POST /v1/recolor with the original photo, a target hex color, an optional
prompt ("the matching workout set"), and optional click points.
"""

import base64
import io
import json

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image, ImageOps, UnidentifiedImageError

from app.colors import RecolorError
from app.pipeline import run

app = FastAPI(title="Morea recolor", docs_url=None, redoc_url=None)
MAX_BYTES = 15 * 1024 * 1024


@app.get("/health")
def health() -> dict:
    return {"ok": True}


def _decode_image(data: bytes) -> np.ndarray:
    if len(data) > MAX_BYTES:
        raise RecolorError("That image is too large to recolor.")
    try:
        pil = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise RecolorError("Could not read that image.") from exc
    rgb = np.array(pil)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


def _decode_mask(data: bytes | None) -> np.ndarray | None:
    if not data:
        return None
    try:
        pil = Image.open(io.BytesIO(data)).convert("L")
    except (UnidentifiedImageError, OSError) as exc:
        raise RecolorError("Could not read the mask.") from exc
    return np.array(pil)


def _parse_points(raw: str, width: int, height: int) -> list[tuple[float, float]]:
    if not raw or not raw.strip():
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RecolorError("Could not read the click points.") from exc
    if not isinstance(parsed, list):
        raise RecolorError("Could not read the click points.")
    points: list[tuple[float, float]] = []
    for item in parsed[:12]:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            continue
        try:
            x_pos, y_pos = float(item[0]), float(item[1])
        except (TypeError, ValueError):
            continue
        if 0 <= x_pos <= 1 and 0 <= y_pos <= 1:
            points.append((x_pos * (width - 1), y_pos * (height - 1)))
    return points


def _png(image: np.ndarray) -> str:
    ok, encoded = cv2.imencode(".png", image)
    if not ok:
        raise RecolorError("Could not encode the recolored image.")
    return base64.b64encode(encoded.tobytes()).decode("ascii")


@app.post("/v1/recolor")
async def recolor_endpoint(
    image: UploadFile = File(...),
    color: str = Form(...),
    prompt: str = Form(""),
    points: str = Form(""),
    mask: UploadFile | None = File(None),
) -> dict:
    data = await image.read(MAX_BYTES + 1)
    mask_bytes = await mask.read(MAX_BYTES + 1) if mask is not None else None
    try:
        bgr = _decode_image(data)
        supplied = _decode_mask(mask_bytes)
        clicked = _parse_points(points, bgr.shape[1], bgr.shape[0])
        output, applied, report = run(
            bgr,
            color,
            prompt=(prompt or "")[:160],
            points=clicked,
            mask=supplied,
        )
    except RecolorError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    mask_u8 = np.rint(np.clip(applied, 0, 1) * 255).astype(np.uint8)
    return {
        "image_png_base64": _png(output),
        "mask_png_base64": _png(mask_u8),
        "report": report,
    }


@app.exception_handler(HTTPException)
async def http_error(_request, exc: HTTPException):
    message = exc.detail if isinstance(exc.detail, str) else "Recolor failed."
    return JSONResponse(status_code=exc.status_code, content={"error": message})
