import os
from pathlib import Path

import numpy as np
import pytest

from navcore.vision.pipeline import VisionPipeline

pytestmark = pytest.mark.model


def test_real_pipeline_warmup_and_combined_result():
    root = Path(os.environ.get("NAV_MODEL_DIR", Path(__file__).resolve().parents[2] / "models"))
    if not (root / "manifest.json").exists():
        pytest.skip("BLOCKED_MODEL: verified local model artifacts are absent")
    pipeline = VisionPipeline.from_model_dir(root, device="cpu")
    rgb = np.random.default_rng(2).integers(0, 256, size=(224, 320, 3), dtype=np.uint8)
    rgb.setflags(write=False)
    result = pipeline.infer(rgb)
    assert result.embedding.shape == (768,) and np.isfinite(result.embedding).all()
    assert len(pipeline.encoder_fingerprint) == 64
    assert isinstance(result.detections, tuple)
    assert all(value >= 0 for value in result.timings_ms.values())
    assert result.timings_ms["vision_ms"] >= result.timings_ms["encoder_ms"]
