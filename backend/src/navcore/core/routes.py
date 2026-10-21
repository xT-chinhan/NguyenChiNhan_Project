"""Pure publish checks; storage owns draft/immutability, map FKs and locks."""

import hashlib
import json
import struct
from itertools import combinations
from math import isfinite, sumprod
from numbers import Real
from typing import Mapping

from .localization import validate_embedding
from .policy import BASELINE, PolicyConfig
from .types import Action, RouteSnapshot


class RouteValidationError(ValueError):
    def __init__(self, code: str, details: list[dict]) -> None:
        super().__init__(code)
        self.code = code
        self.details = details


def validate_route(
    route: RouteSnapshot,
    encoder_fingerprint: str,
    metadata: Mapping | None = None,
    policy: PolicyConfig = BASELINE,
) -> str:
    """Validate a draft snapshot and return its canonical SHA-256 fingerprint.

    Metadata supplies route name/map/endpoints not carried by RouteSnapshot.
    The caller must enforce current-model identity, draft state and DB constraints
    under its publish transaction; this function checks the supplied fingerprint.
    """
    if (
        not encoder_fingerprint
        or not route.encoder_fingerprint
        or route.encoder_fingerprint != encoder_fingerprint
    ):
        raise RouteValidationError("MODEL_FINGERPRINT_MISMATCH", [{"reason": "route_encoder"}])
    checkpoints = sorted(route.checkpoints, key=lambda checkpoint: checkpoint.seq)
    errors = []
    if not 2 <= len(checkpoints) <= 64:
        errors.append({"reason": "checkpoint_count"})
    if [checkpoint.seq for checkpoint in checkpoints] != list(range(len(checkpoints))):
        errors.append({"reason": "checkpoint_sequence"})
    pixels: set[str] = set()
    encoded_size = 0
    vectors = {}
    canonical_checkpoints = []
    for index, checkpoint in enumerate(checkpoints):
        detail = {"checkpoint_id": checkpoint.id, "seq": checkpoint.seq}
        final = index == len(checkpoints) - 1
        if (checkpoint.depart_action == Action.ARRIVE) != final:
            errors.append({**detail, "reason": "depart_action"})
        if checkpoint.depart_action not in tuple(Action):
            errors.append({**detail, "reason": "depart_action"})
        for name, upper in (("heading_deg", 360), ("heading_accuracy_deg", 180)):
            value = getattr(checkpoint, name)
            if value is not None and (
                isinstance(value, bool)
                or not isinstance(value, Real)
                or not isfinite(value)
                or not 0 <= value <= upper
                or (name == "heading_deg" and value == 360)
            ):
                errors.append({**detail, "reason": name})
        if not 3 <= len(checkpoint.references) <= 8:
            errors.append({**detail, "reason": "reference_count"})
        references = []
        vectors[checkpoint.id] = []
        for reference in sorted(checkpoint.references, key=lambda reference: reference.id):
            if reference.pixel_sha256 in pixels:
                errors.append({**detail, "reason": "duplicate_pixels"})
            pixels.add(reference.pixel_sha256)
            if reference.encoder_fingerprint != encoder_fingerprint:
                raise RouteValidationError("MODEL_FINGERPRINT_MISMATCH", [detail])
            encoded_size += len(reference.jpeg_bytes)
            try:
                vector = validate_embedding(reference.embedding)
                vector_bytes = struct.pack("<768f", *vector)
                vectors[checkpoint.id].append(vector)
            except (ValueError, TypeError, OverflowError):
                errors.append({**detail, "reason": "embedding_invalid"})
                continue
            references.append(
                {
                    "id": reference.id,
                    "pixel_sha256": reference.pixel_sha256,
                    "source_group": reference.source_group,
                    "jpeg_sha256": hashlib.sha256(reference.jpeg_bytes).hexdigest(),
                    "embedding_sha256": hashlib.sha256(vector_bytes).hexdigest(),
                    "encoder_fingerprint": reference.encoder_fingerprint,
                }
            )
        canonical_checkpoints.append(
            {
                "id": checkpoint.id,
                "seq": checkpoint.seq,
                "depart_action": checkpoint.depart_action,
                "landmark": checkpoint.landmark,
                "heading_deg": checkpoint.heading_deg,
                "heading_accuracy_deg": checkpoint.heading_accuracy_deg,
                "references": references,
            }
        )
    if encoded_size > 64 * 1024 * 1024:
        errors.append({"reason": "route_image_bytes"})
    if errors:
        raise RouteValidationError("ROUTE_INVALID", errors)
    ambiguous = []
    for first, second in combinations(checkpoints, 2):
        maximum = max(sumprod(a, b) for a in vectors[first.id] for b in vectors[second.id])
        if maximum >= policy.reference_ambiguity_limit:
            ambiguous.append(
                {
                    "checkpoint_ids": [first.id, second.id],
                    "seqs": [first.seq, second.seq],
                    "max_cosine": maximum,
                }
            )
    if ambiguous:
        raise RouteValidationError("ROUTE_AMBIGUOUS", ambiguous)
    document = {
        "schema_version": 1,
        "id": route.id,
        "revision": route.revision,
        "encoder_fingerprint": encoder_fingerprint,
        "metadata": dict(metadata or {}),
        "checkpoints": canonical_checkpoints,
    }
    serialized = json.dumps(
        document, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()
