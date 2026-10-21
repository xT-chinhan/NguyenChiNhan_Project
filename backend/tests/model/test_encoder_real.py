"""A real model is required: absence is an explicit skip, never a fake pass."""

import os
from pathlib import Path

import numpy as np
import pytest

from navcore.vision.artifacts import verify_artifacts
from navcore.vision.encoder import DinoEncoder

pytestmark = pytest.mark.model


def test_real_encoder_cls_normalized_and_repeatable():
    root = Path(os.environ.get("NAV_MODEL_DIR", Path(__file__).resolve().parents[2] / "models"))
    if not (root / "manifest.json").exists():
        pytest.skip("BLOCKED_MODEL: verified local model artifacts are absent")
    artifacts = verify_artifacts(root)
    encoder = DinoEncoder(artifacts.encoder_dir, artifacts.encoder_fingerprint, "cpu")
    rgb = np.random.default_rng(0).integers(0, 256, size=(224, 224, 3), dtype=np.uint8)
    rgb.setflags(write=False)
    first, second = encoder.encode(rgb), encoder.encode(rgb)
    assert first.shape == (768,) and first.dtype == np.float32
    assert np.isfinite(first).all() and not first.flags.writeable
    assert float(np.linalg.norm(first)) == pytest.approx(1, abs=1e-6)
    assert float(np.dot(first, second)) == pytest.approx(1, abs=1e-5)
