import os
from pathlib import Path

import numpy as np
import pytest

from navcore.vision.artifacts import verify_artifacts
from navcore.vision.detector import YoloDetector

pytestmark = pytest.mark.model


def test_real_detector_contract_and_smoke():
    root = Path(os.environ.get("NAV_MODEL_DIR", Path(__file__).resolve().parents[2] / "models"))
    if not (root / "manifest.json").exists():
        pytest.skip("BLOCKED_MODEL: verified local model artifacts are absent")
    artifacts = verify_artifacts(root)
    detector = YoloDetector(artifacts.detector_path, artifacts.labels)
    rgb = np.random.default_rng(1).integers(0, 256, size=(320, 640, 3), dtype=np.uint8)
    rgb.setflags(write=False)
    detections = detector.detect(rgb)
    for detection in detections:
        assert 0 <= detection.class_id <= 79 and 0.38 <= detection.confidence <= 1
        x1, y1, x2, y2 = detection.bbox
        assert 0 <= x1 < x2 <= 639 and 0 <= y1 < y2 <= 319
        assert x2 - x1 >= 10 and y2 - y1 >= 10
