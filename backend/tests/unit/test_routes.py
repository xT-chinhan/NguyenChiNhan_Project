import hashlib
from dataclasses import replace
from math import sqrt

import pytest

from navcore.core.routes import RouteValidationError, validate_route
from navcore.core.types import Action, Checkpoint, Reference, RouteSnapshot

FINGERPRINT = "a" * 64


def basis(index):
    return tuple(float(axis == index) for axis in range(768))


def route():
    checkpoints = tuple(
        Checkpoint(
            f"checkpoint-{index}",
            index,
            Action.ARRIVE if index == 3 else Action.STRAIGHT,
            f"Checkpoint {index}",
            references=tuple(
                Reference(
                    f"reference-{index}-{number}",
                    hashlib.sha256(f"pixels-{index}-{number}".encode()).hexdigest(),
                    basis(index),
                    FINGERPRINT,
                    jpeg_bytes=f"jpeg-{index}-{number}".encode(),
                )
                for number in range(3)
            ),
        )
        for index in range(4)
    )
    return RouteSnapshot("route", 1, FINGERPRINT, None, checkpoints)


def changed_checkpoint(original, checkpoint, index=0):
    checkpoints = list(original.checkpoints)
    checkpoints[index] = checkpoint
    return replace(original, checkpoints=tuple(checkpoints))


def assert_invalid(original, reason):
    with pytest.raises(RouteValidationError) as error:
        validate_route(original, FINGERPRINT)
    assert error.value.code == "ROUTE_INVALID"
    assert reason in [detail["reason"] for detail in error.value.details]


def test_fingerprint_is_deterministic_independent_of_query_order_and_previous_hash():
    original = route()
    fingerprint = validate_route(original, FINGERPRINT, {"name": "Tuyến thử", "map_id": "map"})
    assert len(fingerprint) == 64
    reordered = replace(
        original,
        route_fingerprint="ignored",
        checkpoints=tuple(
            replace(checkpoint, references=checkpoint.references[::-1])
            for checkpoint in original.checkpoints[::-1]
        ),
    )
    assert (
        validate_route(reordered, FINGERPRINT, {"map_id": "map", "name": "Tuyến thử"})
        == fingerprint
    )
    assert validate_route(replace(original, revision=2), FINGERPRINT) != validate_route(
        original, FINGERPRINT
    )


def test_fingerprint_binds_metadata_jpeg_pixels_vectors_and_heading_accuracy():
    original = route()
    baseline = validate_route(original, FINGERPRINT)
    checkpoint = original.checkpoints[0]
    for reference in (
        replace(checkpoint.references[0], jpeg_bytes=b"changed"),
        replace(checkpoint.references[0], pixel_sha256="0" * 64),
        replace(
            checkpoint.references[0], embedding=(0.99, 0, 0, 0, sqrt(1 - 0.99**2)) + (0.0,) * 763
        ),
    ):
        changed = replace(checkpoint, references=(reference, *checkpoint.references[1:]))
        assert validate_route(changed_checkpoint(original, changed), FINGERPRINT) != baseline
    assert (
        validate_route(
            changed_checkpoint(original, replace(checkpoint, heading_accuracy_deg=5)), FINGERPRINT
        )
        != baseline
    )
    assert validate_route(original, FINGERPRINT, {"name": "new"}) != baseline


@pytest.mark.parametrize(
    "case,reason",
    [
        ("count", "checkpoint_count"),
        ("sequence", "checkpoint_sequence"),
        ("early_arrive", "depart_action"),
        ("missing_arrive", "depart_action"),
        ("references", "reference_count"),
        ("duplicate", "duplicate_pixels"),
        ("wrong_dimension", "embedding_invalid"),
        ("nan", "embedding_invalid"),
        ("wrong_norm", "embedding_invalid"),
    ],
)
def test_publish_structural_failures(case, reason):
    original = route()
    checkpoint = original.checkpoints[0]
    if case == "count":
        original = replace(original, checkpoints=original.checkpoints[:1])
    elif case == "sequence":
        original = changed_checkpoint(original, replace(checkpoint, seq=5))
    elif case == "early_arrive":
        original = changed_checkpoint(original, replace(checkpoint, depart_action=Action.ARRIVE))
    elif case == "missing_arrive":
        original = changed_checkpoint(
            original, replace(original.checkpoints[-1], depart_action=Action.LEFT), 3
        )
    elif case == "references":
        original = changed_checkpoint(
            original, replace(checkpoint, references=checkpoint.references[:2])
        )
    elif case == "duplicate":
        reference = replace(
            checkpoint.references[1], pixel_sha256=checkpoint.references[0].pixel_sha256
        )
        original = changed_checkpoint(
            original,
            replace(
                checkpoint,
                references=(checkpoint.references[0], reference, checkpoint.references[2]),
            ),
        )
    else:
        vector = {
            "wrong_dimension": (1.0,),
            "nan": (float("nan"),) + (0.0,) * 767,
            "wrong_norm": (0.5,) + (0.0,) * 767,
        }[case]
        reference = replace(checkpoint.references[0], embedding=vector)
        original = changed_checkpoint(
            original, replace(checkpoint, references=(reference, *checkpoint.references[1:]))
        )
    assert_invalid(original, reason)


def test_cross_checkpoint_duplicate_pixels_rejected():
    original = route()
    checkpoint = original.checkpoints[1]
    reference = replace(
        checkpoint.references[0], pixel_sha256=original.checkpoints[0].references[0].pixel_sha256
    )
    assert_invalid(
        changed_checkpoint(
            original, replace(checkpoint, references=(reference, *checkpoint.references[1:])), 1
        ),
        "duplicate_pixels",
    )


@pytest.mark.parametrize("similarity,ambiguous", [(0.9699, False), (0.97, True)])
def test_ambiguity_checks_every_reference_pair_at_inclusive_boundary(similarity, ambiguous):
    original = route()
    checkpoint = original.checkpoints[1]
    vector = (similarity, sqrt(1 - similarity**2)) + (0.0,) * 766
    reference = replace(checkpoint.references[-1], embedding=vector)
    original = changed_checkpoint(
        original, replace(checkpoint, references=(*checkpoint.references[:2], reference)), 1
    )
    if ambiguous:
        with pytest.raises(RouteValidationError) as error:
            validate_route(original, FINGERPRINT)
        assert error.value.code == "ROUTE_AMBIGUOUS"
        assert error.value.details[0]["seqs"] == [0, 1]
    else:
        validate_route(original, FINGERPRINT)


def test_route_and_reference_encoder_fingerprints_are_checked():
    original = route()
    for changed in (
        replace(original, encoder_fingerprint="b" * 64),
        replace(original, encoder_fingerprint=None),
        changed_checkpoint(
            original,
            replace(
                original.checkpoints[0],
                references=(
                    replace(original.checkpoints[0].references[0], encoder_fingerprint="b" * 64),
                    *original.checkpoints[0].references[1:],
                ),
            ),
        ),
    ):
        with pytest.raises(RouteValidationError) as error:
            validate_route(changed, FINGERPRINT)
        assert error.value.code == "MODEL_FINGERPRINT_MISMATCH"


def test_unbound_draft_cannot_be_published_even_if_current_encoder_is_missing():
    with pytest.raises(RouteValidationError) as error:
        validate_route(replace(route(), encoder_fingerprint=None), None)
    assert error.value.code == "MODEL_FINGERPRINT_MISMATCH"


@pytest.mark.parametrize(
    "name,value",
    [
        ("heading_deg", 360),
        ("heading_deg", float("nan")),
        ("heading_accuracy_deg", 181),
        ("heading_accuracy_deg", True),
    ],
)
def test_publish_rejects_invalid_heading_metadata(name, value):
    original = route()
    checkpoint = replace(original.checkpoints[0], **{name: value})
    assert_invalid(changed_checkpoint(original, checkpoint), name)


def test_checkpoint_and_reference_upper_bounds():
    original = route()
    assert_invalid(
        replace(
            original,
            checkpoints=tuple(
                replace(original.checkpoints[0], id=str(index), seq=index) for index in range(65)
            ),
        ),
        "checkpoint_count",
    )
    checkpoint = original.checkpoints[0]
    checkpoint = replace(
        checkpoint,
        references=tuple(
            replace(
                checkpoint.references[0],
                id=str(index),
                pixel_sha256=hashlib.sha256(str(index).encode()).hexdigest(),
            )
            for index in range(9)
        ),
    )
    assert_invalid(changed_checkpoint(original, checkpoint), "reference_count")


def test_publish_rejects_total_jpeg_bytes_above_route_cap():
    original = route()
    checkpoint = original.checkpoints[0]
    reference = replace(checkpoint.references[0], jpeg_bytes=b"x" * (64 * 1024 * 1024))
    checkpoint = replace(checkpoint, references=(reference, *checkpoint.references[1:]))
    assert_invalid(changed_checkpoint(original, checkpoint), "route_image_bytes")
