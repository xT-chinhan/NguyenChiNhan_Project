"""Fast mode: detector only, no route or reference data. One frame in, one alert out."""

import asyncio

import cv2
import numpy as np
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, RedirectResponse

from navcore.api.mobile import ASSETS, HEADERS
from navcore.vision.artifacts import verify_artifacts
from navcore.vision.detector import YoloDetector

router = APIRouter()
MAX_BODY = 400 * 1024
_lock = asyncio.Lock()
_detector: YoloDetector | None = None

VI = {
    "person": "người",
    "bicycle": "xe đạp",
    "car": "ô tô",
    "motorcycle": "xe máy",
    "bus": "xe buýt",
    "truck": "xe tải",
    "traffic light": "đèn giao thông",
    "fire hydrant": "trụ nước",
    "stop sign": "biển dừng",
    "bench": "ghế băng",
    "dog": "con chó",
    "cat": "con mèo",
    "backpack": "ba lô",
    "umbrella": "cây dù",
    "handbag": "túi xách",
    "suitcase": "vali",
    "bottle": "chai",
    "cup": "cái ly",
    "chair": "ghế",
    "couch": "ghế sofa",
    "potted plant": "chậu cây",
    "bed": "giường",
    "dining table": "bàn",
    "toilet": "bồn cầu",
    "tv": "ti vi",
    "laptop": "máy tính",
    "refrigerator": "tủ lạnh",
    "sink": "bồn rửa",
    "oven": "lò",
    "microwave": "lò vi sóng",
    "book": "sách",
    "clock": "đồng hồ",
    "vase": "bình hoa",
    "cell phone": "điện thoại",
    "keyboard": "bàn phím",
    "mouse": "con chuột",
    "skateboard": "ván trượt",
    "sports ball": "quả bóng",
    "parking meter": "cột đỗ xe",
    "bird": "con chim",
}
SIDE = {"left": "bên trái", "right": "bên phải", "center": "phía trước"}


def _get_detector(request: Request) -> YoloDetector:
    global _detector
    if _detector is None:
        artifacts = verify_artifacts(request.app.state.settings.model_dir)
        # Own ONNX session: never waits on the session model worker.
        _detector = YoloDetector(artifacts.detector_path, artifacts.labels, 0.35)
    return _detector


def guide(objects: list[dict]) -> dict | None:
    """Pick one spoken alert. Box height/area stands in for distance (RGB only)."""
    if not objects:
        return None
    load = {"left": 0.0, "center": 0.0, "right": 0.0}
    for o in objects:
        load[o["zone"]] += o["area"]
    ahead = [o for o in objects if o["zone"] == "center"]
    near_ahead = [o for o in ahead if o["near"]]
    if near_ahead:
        o = max(near_ahead, key=lambda o: o["area"])
        free = min(("left", "right"), key=lambda z: load[z])
        if load[free] > 0.25:
            text = f"Dừng lại! {o['name'].capitalize()} ngay phía trước. Hai bên đều bị chắn."
        else:
            text = f"Dừng lại! {o['name'].capitalize()} ngay phía trước. Né sang {SIDE[free][4:]}."
        return {"level": "stop", "text": text, "key": f"stop:{o['label']}:{free}"}
    if ahead:
        o = max(ahead, key=lambda o: o["area"])
        return {"level": "warn", "text": f"Có {o['name']} phía trước.", "key": f"warn:{o['label']}"}
    near_side = [o for o in objects if o["near"]]
    if near_side:
        o = max(near_side, key=lambda o: o["area"])
        text = f"{o['name'].capitalize()} sát {SIDE[o['zone']]}."
        return {"level": "side", "text": text, "key": f"side:{o['label']}:{o['zone']}"}
    o = max(objects, key=lambda o: o["area"])
    text = f"Có {o['name']} {SIDE[o['zone']]}."
    return {"level": "info", "text": text, "key": f"info:{o['label']}:{o['zone']}"}


def describe(detections, width: int, height: int) -> list[dict]:
    objects = []
    for d in detections:
        x1, y1, x2, y2 = d.bbox
        nx1, nx2, ny1, ny2 = x1 / width, x2 / width, y1 / height, y2 / height
        h, area = ny2 - ny1, (nx2 - nx1) * (ny2 - ny1)
        if area < 0.01:
            continue
        # Center zone = box covers a good part of the middle third (walking path).
        overlap = max(0.0, min(nx2, 0.67) - max(nx1, 0.33)) / 0.34
        cx = (nx1 + nx2) / 2
        zone = "center" if overlap >= 0.5 else ("left" if cx < 0.5 else "right")
        objects.append(
            {
                "label": d.class_name,
                "name": VI.get(d.class_name, "vật cản"),
                "confidence": round(d.confidence, 2),
                "box": [round(nx1, 3), round(ny1, 3), round(nx2, 3), round(ny2, 3)],
                "zone": zone,
                "area": round(area, 3),
                "near": h >= 0.55 or area >= 0.22 or ny2 >= 0.95 and h >= 0.35,
            }
        )
    return objects


FAST_DIR = ASSETS / "fast"
FAST_FILES = {
    "app.js": "text/javascript",
    "app.css": "text/css",
    "sw.js": "text/javascript",
    "manifest.webmanifest": "application/manifest+json",
    "icon-192.png": "image/png",
    "icon-512.png": "image/png",
    "ort.wasm.min.mjs": "text/javascript",
    "ort-wasm-simd-threaded.mjs": "text/javascript",
    "ort-wasm-simd-threaded.wasm": "application/wasm",
    "model.onnx": "application/octet-stream",
    "depth.onnx": "application/octet-stream",
}
FAST_HEADERS = {
    **HEADERS,
    "Cache-Control": "no-cache",
    # Cross-origin isolation enables multi-threaded WebAssembly inference.
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    # On-device inference needs WebAssembly compilation.
    "Content-Security-Policy": "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; "
    "worker-src 'self' blob:; style-src 'self'; connect-src 'self'; media-src 'self' blob:; "
    "img-src 'self' data: blob:; manifest-src 'self'; object-src 'none'; base-uri 'none'; "
    "frame-ancestors 'none'",
}


@router.get("/fast", include_in_schema=False)
async def fast_redirect():
    return RedirectResponse("/fast/", status_code=308)


@router.get("/fast/", include_in_schema=False)
async def fast_page():
    return FileResponse(FAST_DIR / "index.html", headers=FAST_HEADERS, media_type="text/html")


@router.get("/fast/{name}", include_in_schema=False)
async def fast_asset(name: str):
    if name not in FAST_FILES:
        raise HTTPException(404)
    return FileResponse(FAST_DIR / name, headers=FAST_HEADERS, media_type=FAST_FILES[name])


@router.post("/v1/fast/detect")
async def fast_detect(request: Request):
    body = await request.body()
    if not body or len(body) > MAX_BODY:
        raise HTTPException(413)
    if _lock.locked():
        raise HTTPException(429)
    async with _lock:
        rgb = cv2.imdecode(np.frombuffer(body, np.uint8), cv2.IMREAD_COLOR)
        if rgb is None or min(rgb.shape[:2]) < 32:
            raise HTTPException(400)
        scale = 640 / max(rgb.shape[:2])
        if scale < 1:
            rgb = cv2.resize(rgb, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        rgb = np.ascontiguousarray(rgb[:, :, ::-1])
        detector = _get_detector(request)
        detections = await asyncio.to_thread(detector.detect, rgb)
    objects = describe(detections, rgb.shape[1], rgb.shape[0])
    return {"objects": objects, "alert": guide(objects)}
