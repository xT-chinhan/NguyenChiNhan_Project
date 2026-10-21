import json
import math
from pathlib import Path

import pytest

from navcore.core.policy import PolicyConfig

ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "synthetic"


def test_synthetic_vectors_independent_expected_scores_and_timeline():
    route = json.loads((ROOT / "route.json").read_text())
    observations = [
        json.loads(line) for line in (ROOT / "observations.jsonl").read_text().splitlines()
    ]
    events = [
        json.loads(line) for line in (ROOT / "expected_events.jsonl").read_text().splitlines()
    ]
    assert len(route["checkpoints"]) == 4 and len(observations) == 12
    assert [e["frame_seq"] for e in events] == [3, 6, 9, 12]
    hashes = set()
    for point in route["checkpoints"]:
        assert len(point["references"]) == 3
        for ref in point["references"]:
            vector = ref["embedding"]
            assert len(vector) == 768
            assert math.sqrt(sum(value * value for value in vector)) == pytest.approx(1)
            hashes.add(ref["pixel_sha256"])
    assert len(hashes) == 12
    for query in observations:
        scores = []
        for point in route["checkpoints"]:
            similarities = sorted(
                (
                    sum(a * b for a, b in zip(query["embedding"], ref["embedding"], strict=True))
                    for ref in point["references"]
                ),
                reverse=True,
            )
            scores.append(sum(similarities[:2]) / 2)
        assert scores.index(max(scores)) == query["expected_candidate_seq"]
        assert max(scores) == pytest.approx(query["expected_score"])
        assert max(scores) >= 0.92 and sorted(scores)[-1] - sorted(scores)[-2] >= 0.04


@pytest.mark.parametrize(
    "changes",
    [{"request_deadline_ms": math.nan}, {"waypoint_confirm_hits": 2.1}, {"match_margin": math.inf}],
)
def test_policy_rejects_non_finite_or_fractional_count(changes):
    with pytest.raises(ValueError):
        PolicyConfig(**changes)
