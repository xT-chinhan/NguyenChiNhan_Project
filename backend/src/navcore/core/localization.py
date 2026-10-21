"""Checkpoint scores use every route checkpoint as a visual competitor."""

from math import isfinite, sqrt, sumprod
from numbers import Real
from typing import Iterable, Sequence

from .policy import BASELINE, PolicyConfig
from .types import Action, MatchResult, RouteSnapshot, Vector


def validate_embedding(embedding: Sequence[float]) -> Vector:
    """Accept finite normalized float vectors, including float32 roundoff."""
    if len(embedding) != 768 or getattr(embedding, "shape", (768,)) != (768,):
        raise ValueError("EMBEDDING_SHAPE_INVALID")
    if any(isinstance(value, bool) or not isinstance(value, Real) for value in embedding):
        raise ValueError("EMBEDDING_INVALID")
    values = tuple(float(value) for value in embedding)
    if not all(isfinite(value) for value in values):
        raise ValueError("EMBEDDING_INVALID")
    if abs(sqrt(sumprod(values, values)) - 1.0) > 1e-4:
        raise ValueError("EMBEDDING_NORM_INVALID")
    return values


def match_checkpoint(
    embedding: Sequence[float],
    route: RouteSnapshot,
    allowed_seqs: Iterable[int],
    heading_deg: float | None = None,
    heading_accuracy_deg: float | None = None,
    policy: PolicyConfig = BASELINE,
) -> MatchResult:
    query = validate_embedding(embedding)
    if len(route.checkpoints) < 2:
        raise ValueError("ROUTE_INVALID")
    scores = []
    checkpoints = {checkpoint.seq: checkpoint for checkpoint in route.checkpoints}
    if len(checkpoints) != len(route.checkpoints):
        raise ValueError("ROUTE_INVALID")
    for checkpoint in route.checkpoints:
        if len(checkpoint.references) < 2:
            raise ValueError("ROUTE_INVALID")
        similarities = []
        for reference in checkpoint.references:
            if reference.encoder_fingerprint != route.encoder_fingerprint:
                raise ValueError("MODEL_FINGERPRINT_MISMATCH")
            vector = validate_embedding(reference.embedding)
            similarities.append(max(-1.0, min(1.0, sumprod(query, vector))))
        best = sorted(similarities, reverse=True)[:2]
        scores.append(((best[0] + best[1]) / 2.0, checkpoint.seq))
    scores.sort(reverse=True)
    score, seq = scores[0]
    margin = score - scores[1][0]
    if margin <= 1e-6:
        return MatchResult(None, score, margin, False)
    checkpoint = checkpoints[seq]
    following = checkpoints.get(seq + 1)
    strict = checkpoint.depart_action != Action.STRAIGHT or (
        following is not None and following.depart_action in (Action.LEFT, Action.RIGHT)
    )
    threshold = policy.match_threshold_turn_or_final if strict else policy.match_threshold_straight
    has_heading = (
        checkpoint.heading_deg is not None
        and checkpoint.heading_accuracy_deg is not None
        and heading_deg is not None
        and heading_accuracy_deg is not None
        and 0 <= checkpoint.heading_accuracy_deg <= policy.heading_max_accuracy_deg
        and 0 <= heading_accuracy_deg <= policy.heading_max_accuracy_deg
    )
    heading_matches = False
    if has_heading:
        error = abs((heading_deg - checkpoint.heading_deg + 180) % 360 - 180)
        heading_matches = error <= policy.heading_max_error_deg
    accepted = (
        seq in set(allowed_seqs)
        # Preserve inclusive boundaries after dot products and subtraction roundoff.
        and score + 1e-12 >= threshold
        and margin + 1e-12 >= policy.match_margin
        and (not has_heading or heading_matches)
    )
    return MatchResult(seq, score, margin, accepted, heading_matches)
