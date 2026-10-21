"""Local-only DINOv2 CLS embeddings with one immutable model identity."""

from pathlib import Path

import numpy as np

from navcore.vision.artifacts import DINO_REVISION
from navcore.vision.images import validate_rgb


class EncoderError(ValueError):
    pass


class DinoEncoder:
    def __init__(self, model_dir: Path, fingerprint: str, device: str = "cpu"):
        import torch
        from transformers import AutoImageProcessor, AutoModel

        if device not in {"cpu", "cuda:0"}:
            raise EncoderError("Unsupported encoder device")
        if device == "cuda:0" and not torch.cuda.is_available():
            raise EncoderError("Configured CUDA device is unavailable")
        if device == "cpu":
            # Measured 8→4 threads: smoke p95 716→230ms; single shared model slot avoids overlap.
            torch.set_num_threads(4)
        self.processor = AutoImageProcessor.from_pretrained(
            str(model_dir),
            revision=DINO_REVISION,
            local_files_only=True,
            trust_remote_code=False,
            use_fast=False,
        )
        self.model = AutoModel.from_pretrained(
            str(model_dir),
            revision=DINO_REVISION,
            local_files_only=True,
            trust_remote_code=False,
            use_safetensors=True,
        ).to(device=device, dtype=torch.float32)
        self.model.eval()
        self.device, self.fingerprint = device, fingerprint

    def encode(self, rgb: np.ndarray) -> np.ndarray:
        import torch

        validate_rgb(rgb)
        inputs = self.processor(images=rgb, return_tensors="pt").to(self.device)
        with torch.inference_mode():
            cls = self.model(**inputs).last_hidden_state[:, 0, :]
            if tuple(cls.shape) != (1, 768):
                raise EncoderError("Unexpected encoder output shape")
            vector = cls[0].detach().to(device="cpu", dtype=torch.float32).numpy().copy()
        norm = float(np.linalg.norm(vector))
        if not np.isfinite(vector).all() or not np.isfinite(norm) or norm <= 1e-12:
            raise EncoderError("Invalid encoder output")
        vector /= np.float32(norm)
        vector.setflags(write=False)
        return vector
