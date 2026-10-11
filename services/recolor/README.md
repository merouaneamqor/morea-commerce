# Recolor inference service

MVP stack for e-commerce product color variants:

1. **Segment** — `rembg` foreground mask with optional skin exclusion (keeps face/hands out of the garment region on lifestyle shots).
2. **Recolor** — OpenCV Lab transform: preserve lightness/texture, shift chroma toward the target hex.
3. **Composite** — soft mask blend so pixels outside the product are identical to the original.

Future upgrades (not in this MVP): Grounding DINO text prompts, SAM 2 click/point masks, FLUX inpainting for edge cleanup.

## API

- `GET /health`
- `POST /segment` — multipart `image`
- `POST /recolor` — multipart `image`, form `hex_color`, optional `mask`, `auto_segment=true`

## Run locally

```bash
docker compose up recolor
# or
cd services/recolor && pip install -r requirements.txt && uvicorn app.main:app --reload --port 8088
```

Rails uses `RECOLOR_SERVICE_URL` (default in Docker Compose: `http://recolor:8080`).
