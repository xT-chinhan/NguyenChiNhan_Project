"""YOLO26 end-to-end ONNX adapter; no runtime Ultralytics import.

Letterbox and coordinate mapping adapted from BlindNav:
https://github.com/Anthonyiswhy/blind_navigation_aid

MIT License
Copyright (c) 2026 Anthonyiswhy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from navcore.core.policy import BASELINE
from navcore.core.types import Detection
from navcore.vision.images import validate_rgb


class DetectorError(ValueError):
    pass


@dataclass(frozen=True)
class Letterbox:
    scale: float
    left: int
    top: int
    width: int
    height: int


def letterbox_resize(rgb: np.ndarray) -> tuple[np.ndarray, Letterbox]:
    validate_rgb(rgb)
    height, width = rgb.shape[:2]
    scale = min(224 / height, 224 / width)
    new_width, new_height = max(1, int(width * scale)), max(1, int(height * scale))
    left, top = (224 - new_width) // 2, (224 - new_height) // 2
    padded = np.full((224, 224, 3), 114, dtype=np.uint8)
    padded[top : top + new_height, left : left + new_width] = cv2.resize(
        rgb, (new_width, new_height), interpolation=cv2.INTER_LINEAR
    )
    tensor = np.ascontiguousarray(padded.transpose(2, 0, 1)[None], dtype=np.float32)
    tensor /= np.float32(255)
    return tensor, Letterbox(scale, left, top, width, height)


def yolo_postprocess(
    output: np.ndarray,
    transform: Letterbox,
    labels: tuple[str, ...],
    confidence_min: float = BASELINE.detection_confidence_min,
) -> tuple[Detection, ...]:
    if (
        not isinstance(output, np.ndarray)
        or output.shape != (1, 300, 6)
        or output.dtype != np.float32
    ):
        raise DetectorError("Unexpected detector output contract")
    if len(labels) != 80 or not 0 < confidence_min <= 1:
        raise DetectorError("Invalid detector configuration")
    detections = []
    for row in output[0]:
        if not np.isfinite(row).all():
            continue
        x1, y1, x2, y2, confidence, class_id = map(float, row)
        if not float(np.float32(confidence_min)) <= confidence <= 1 or not class_id.is_integer():
            continue
        if not 0 <= class_id < 80 or x2 <= x1 or y2 <= y1:
            continue
        x1 = min(max((x1 - transform.left) / transform.scale, 0), transform.width - 1)
        x2 = min(max((x2 - transform.left) / transform.scale, 0), transform.width - 1)
        y1 = min(max((y1 - transform.top) / transform.scale, 0), transform.height - 1)
        y2 = min(max((y2 - transform.top) / transform.scale, 0), transform.height - 1)
        if x2 - x1 < 10 or y2 - y1 < 10:
            continue
        ident = int(class_id)
        detections.append(Detection(ident, labels[ident], (x1, y1, x2, y2), confidence))
    return tuple(detections)


class YoloDetector:
    def __init__(
        self,
        model_path: Path,
        labels: tuple[str, ...],
        confidence_min: float = BASELINE.detection_confidence_min,
    ):
        import onnxruntime as ort

        ort.disable_telemetry_events()
        # Bytes prevent ONNX external-data references from reading sibling files.
        self.session = ort.InferenceSession(
            model_path.read_bytes(), providers=["CPUExecutionProvider"]
        )
        inputs, outputs = self.session.get_inputs(), self.session.get_outputs()
        if (
            len(inputs) != 1
            or len(outputs) != 1
            or inputs[0].shape != [1, 3, 224, 224]
            or outputs[0].shape != [1, 300, 6]
            or inputs[0].type != "tensor(float)"
            or outputs[0].type != "tensor(float)"
        ):
            raise DetectorError("Unexpected detector model contract")
        self.input_name, self.output_name = inputs[0].name, outputs[0].name
        self.labels, self.confidence_min = labels, confidence_min

    def detect(self, rgb: np.ndarray) -> tuple[Detection, ...]:
        tensor, transform = letterbox_resize(rgb)
        output = self.session.run([self.output_name], {self.input_name: tensor})[0]
        return yolo_postprocess(output, transform, self.labels, self.confidence_min)
