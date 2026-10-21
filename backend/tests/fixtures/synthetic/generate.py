"""Reproducible synthetic observations; never evidence of real model accuracy."""

import hashlib
import json
from pathlib import Path
from uuid import UUID

import numpy as np


def generate():
    rng = np.random.default_rng(20261021)
    checkpoints, observations, expected = [], [], []
    actions = ("straight", "left", "right", "arrive")
    codes = ("CONTINUE_STRAIGHT", "TURN_LEFT", "TURN_RIGHT", "ARRIVED")
    fingerprint = hashlib.sha256(b"synthetic-encoder-not-a-real-model").hexdigest()
    for index, (action, code) in enumerate(zip(actions, codes, strict=True)):
        basis = np.eye(1, 768, index, dtype=np.float64)[0]
        refs = []
        for ref_index in range(3):
            vector = basis + rng.normal(0, 0.003, 768)
            vector = vector / np.linalg.norm(vector)
            refs.append(
                {
                    "id": str(UUID(int=100 + index * 3 + ref_index)),
                    "embedding": vector.tolist(),
                    "pixel_sha256": hashlib.sha256(f"ref-{index}-{ref_index}".encode()).hexdigest(),
                    "encoder_fingerprint": fingerprint,
                    "source_group": "synthetic-reference",
                }
            )
        checkpoints.append(
            {
                "id": str(UUID(int=10 + index)),
                "seq": index,
                "depart_action": action,
                "landmark": f"Synthetic {index}",
                "references": refs,
            }
        )
        # These expected scores are independent arithmetic, never a call to core matching.
        scores = sorted((ref["embedding"][index] for ref in refs), reverse=True)
        expected_score = (scores[0] + scores[1]) / 2
        for hit in range(3):
            seq = index * 3 + hit + 1
            observations.append(
                {
                    "seq": seq,
                    "capture_ms": seq * 200,
                    "image_hash": hashlib.sha256(f"query-{seq}".encode()).hexdigest(),
                    "embedding": basis.tolist(),
                    "detections": [],
                    "depth": None,
                    "expected_candidate_seq": index,
                    "expected_score": expected_score,
                }
            )
        expected.append(
            {
                "frame_seq": index * 3 + 3,
                "checkpoint": index,
                "code": code,
                "state": "completed" if index == 3 else "navigating",
                "ack_before_next": index < 3,
            }
        )
    route = {
        "id": str(UUID(int=1)),
        "revision": 1,
        "encoder_fingerprint": fingerprint,
        "route_fingerprint": None,
        "checkpoints": checkpoints,
    }
    return route, observations, expected


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    route, observations, expected = generate()
    (root / "route.json").write_text(json.dumps(route, ensure_ascii=False) + "\n")
    for name, values in (("observations.jsonl", observations), ("expected_events.jsonl", expected)):
        (root / name).write_text(
            "".join(json.dumps(value, ensure_ascii=False) + "\n" for value in values)
        )
