"""Synchronous vision seam; the runtime owns its single execution slot.

infer(rgb_u8) returns VisionResult with a read-only float32 (768,) embedding,
Detection tuple and per-stage milliseconds. A branch failure raises and produces
no partial result. Call outside the event loop and never overlap calls.
"""

from dataclasses import dataclass
from pathlib import Path
from time import perf_counter

import numpy as np

from navcore.core.policy import BASELINE, PolicyConfig
from navcore.core.types import Detection
from navcore.vision.artifacts import verify_artifacts
from navcore.vision.detector import YoloDetector
from navcore.vision.encoder import DinoEncoder
from navcore.vision.images import validate_rgb


@dataclass(frozen=True)
class VisionResult:
    embedding: np.ndarray
    detections: tuple[Detection, ...]
    timings_ms: dict[str, float]


class VisionPipeline:
    def __init__(self, encoder: DinoEncoder, detector: YoloDetector):
        self.encoder, self.detector = encoder, detector
        self.encoder_fingerprint = encoder.fingerprint

    @classmethod
    def from_model_dir(
        cls, model_dir: Path, device: str = "cpu", policy: PolicyConfig = BASELINE
    ) -> "VisionPipeline":
        artifacts = verify_artifacts(model_dir)
        encoder = DinoEncoder(artifacts.encoder_dir, artifacts.encoder_fingerprint, device)
        detector = YoloDetector(
            artifacts.detector_path, artifacts.labels, policy.detection_confidence_min
        )
        pipeline = cls(encoder, detector)
        rgb = np.zeros((224, 224, 3), dtype=np.uint8)
        rgb.setflags(write=False)
        pipeline.infer(rgb)
        return pipeline

    def encode(self, rgb_u8: np.ndarray) -> np.ndarray:
        return self.encoder.encode(rgb_u8)

    def infer(self, rgb_u8: np.ndarray) -> VisionResult:
        validate_rgb(rgb_u8)
        start = perf_counter()
        embedding = self.encoder.encode(rgb_u8)
        encoded = perf_counter()
        detections = self.detector.detect(rgb_u8)
        done = perf_counter()
        return VisionResult(
            embedding,
            detections,
            {
                "encoder_ms": (encoded - start) * 1000,
                "detector_ms": (done - encoded) * 1000,
                "vision_ms": (done - start) * 1000,
            },
        )
