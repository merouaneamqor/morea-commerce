"""HTTP API for product segmentation and Lab-space recoloring."""

from __future__ import annotations

import cv2
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response

from .recolor import decode_image, decode_mask, encode_png, recolor_lab
from .segment import mask_to_png, segment_garment

app = FastAPI(title="Morea Recolor Service", version="0.1.0")

PRESET_COLORS = {
    "baby_pink": "#F4C2C2",
    "black": "#1A1A1A",
    "taupe": "#8B7D6B",
    "ocean_blue": "#006994",
}


@app.get("/health")
def health():
    return {"ok": True, "presets": PRESET_COLORS}


@app.post("/segment")
async def segment(
    image: UploadFile = File(...),
    exclude_skin: bool = Form(True),
):
    try:
        raw = await image.read()
        bgr = decode_image(raw)
        mask = segment_garment(bgr, exclude_skin=exclude_skin)
        return Response(content=mask_to_png(mask), media_type="image/png")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/recolor")
async def recolor(
    image: UploadFile = File(...),
    hex_color: str = Form(...),
    mask: UploadFile | None = File(None),
    auto_segment: bool = Form(True),
    exclude_skin: bool = Form(True),
    chroma_strength: float = Form(0.88),
):
    try:
        raw = await image.read()
        bgr = decode_image(raw)

        if mask is not None and mask.filename:
            mask_arr = decode_mask(await mask.read())
        elif auto_segment:
            mask_arr = segment_garment(bgr, exclude_skin=exclude_skin)
        else:
            raise HTTPException(status_code=400, detail="Provide a mask or enable auto_segment")

        if mask_arr.shape[:2] != bgr.shape[:2]:
            mask_arr = cv2_resize_mask(mask_arr, bgr.shape[:2])

        out = recolor_lab(bgr, mask_arr, hex_color, chroma_strength=chroma_strength)
        return Response(content=encode_png(out), media_type="image/png")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def cv2_resize_mask(mask, shape_hw):
    h, w = shape_hw
    return cv2.resize(mask, (w, h), interpolation=cv2.INTER_LINEAR)
