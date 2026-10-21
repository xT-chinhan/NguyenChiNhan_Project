from dataclasses import replace
from math import sqrt

import pytest

from navcore.core.localization import match_checkpoint, validate_embedding
from navcore.core.types import Action, Checkpoint, Reference, RouteSnapshot

FINGERPRINT = "a" * 64


def vector(*values):
    return tuple(values) + (0.0,) * (768 - len(values))


def reference(name, embedding):
    return Reference(name, name, embedding, FINGERPRINT)


def route(actions=(Action.STRAIGHT, Action.ARRIVE)):
    return RouteSnapshot(
        "route",
        1,
        FINGERPRINT,
        None,
        tuple(
            Checkpoint(
                str(index),
                index,
                action,
                "checkpoint",
                references=tuple(
                    reference(f"{index}-{ref}", vector(*([0.0] * index + [1.0])))
                    for ref in range(3)
                ),
            )
            for index, action in enumerate(actions)
        ),
    )


def test_top_two_reference_median_is_independent_arithmetic():
    original = route()
    values = (0.99, 0.91, 0.20)
    checkpoint = replace(
        original.checkpoints[0],
        references=tuple(
            reference(str(index), vector(value, 0, sqrt(1 - value * value)))
            for index, value in enumerate(values)
        ),
    )
    result = match_checkpoint(
        vector(1), replace(original, checkpoints=(checkpoint, original.checkpoints[1])), {0}
    )
    assert result.similarity == pytest.approx((0.99 + 0.91) / 2)
    assert result.margin == pytest.approx(0.95)
    assert result.accepted


def test_passed_checkpoint_remains_competitor_and_top_outside_allowed_fails():
    result = match_checkpoint(vector(1), route(), {1})
    assert result.candidate_seq == 0
    assert not result.accepted


def test_tie_is_ambiguous_without_selecting_an_id():
    result = match_checkpoint(vector(1 / sqrt(2), 1 / sqrt(2)), route(), {0, 1})
    assert result.candidate_seq is None
    assert not result.accepted


def test_low_margin_rejected_despite_high_score():
    original = route()
    second = replace(
        original.checkpoints[1],
        references=tuple(
            reference(f"second-{index}", vector(0.99, sqrt(1 - 0.99**2))) for index in range(3)
        ),
    )
    result = match_checkpoint(
        vector(1), replace(original, checkpoints=(original.checkpoints[0], second)), {0}
    )
    assert result.similarity == 1
    assert result.margin == pytest.approx(0.01)
    assert not result.accepted


@pytest.mark.parametrize("margin,accepted", [(0.0399999, False), (0.04, True)])
def test_margin_boundary_is_inclusive_despite_subtraction_roundoff(margin, accepted):
    original = route()
    checkpoints = tuple(
        replace(
            checkpoint,
            references=tuple(
                reference(f"{index}-{number}", vector(score, 0, sqrt(1 - score**2)))
                for number in range(3)
            ),
        )
        for index, (checkpoint, score) in enumerate(
            zip(original.checkpoints, (0.96, 0.96 - margin))
        )
    )
    assert (
        match_checkpoint(vector(1), replace(original, checkpoints=checkpoints), {0}).accepted
        == accepted
    )


@pytest.mark.parametrize("score,accepted", [(0.879, False), (0.88, True)])
def test_straight_threshold_inclusive(score, accepted):
    assert match_checkpoint(vector(score, 0, sqrt(1 - score**2)), route(), {0}).accepted == accepted


@pytest.mark.parametrize("score,accepted", [(0.919, False), (0.92, True)])
def test_checkpoint_immediately_before_turn_uses_strict_threshold(score, accepted):
    original = route((Action.STRAIGHT, Action.LEFT, Action.ARRIVE))
    query = vector(score, 0, 0, sqrt(1 - score**2))
    assert match_checkpoint(query, original, {0}).accepted == accepted


@pytest.mark.parametrize("action", [Action.LEFT, Action.RIGHT, Action.ARRIVE])
def test_turn_and_final_use_strict_threshold(action):
    original = route((action, Action.STRAIGHT))
    assert not match_checkpoint(vector(0.90, 0, sqrt(0.19)), original, {0}).accepted


def test_heading_wrap_accuracy_and_missing_reference_accuracy():
    original = route()
    checkpoint = replace(original.checkpoints[0], heading_deg=1, heading_accuracy_deg=5)
    original = replace(original, checkpoints=(checkpoint, original.checkpoints[1]))
    match = match_checkpoint(vector(1), original, {0}, 359, 5)
    assert match.accepted and match.orientation_verified
    assert not match_checkpoint(vector(1), original, {0}, 181, 5).accepted
    missing = match_checkpoint(vector(1), original, {0})
    assert missing.accepted and not missing.orientation_verified
    inaccurate = match_checkpoint(vector(1), original, {0}, 181, 21)
    assert inaccurate.accepted and not inaccurate.orientation_verified
    original = replace(
        original,
        checkpoints=(replace(checkpoint, heading_accuracy_deg=None), original.checkpoints[1]),
    )
    assert not match_checkpoint(vector(1), original, {0}, 181, 5).orientation_verified


def test_heading_exact_error_and_accuracy_boundaries_are_accepted():
    original = route()
    checkpoint = replace(original.checkpoints[0], heading_deg=1, heading_accuracy_deg=20)
    original = replace(original, checkpoints=(checkpoint, original.checkpoints[1]))
    assert match_checkpoint(vector(1), original, {0}, 26, 20).orientation_verified
    assert not match_checkpoint(vector(1), original, {0}, 26.001, 20).accepted


@pytest.mark.parametrize("embedding", [vector(0), vector(float("nan")), (1.0,), vector(True)])
def test_invalid_embedding_fails_instead_of_fake_score(embedding):
    with pytest.raises(ValueError):
        validate_embedding(embedding)


def test_float32_numpy_encoder_seam_and_wrong_rank():
    numpy = pytest.importorskip("numpy")
    query = numpy.zeros(768, dtype=numpy.float32)
    query[0] = 1
    assert match_checkpoint(query, route(), {0}).accepted
    with pytest.raises(ValueError, match="EMBEDDING_SHAPE_INVALID"):
        validate_embedding(query.reshape(768, 1))


def test_reference_fingerprint_mismatch_never_compares_vectors():
    original = route()
    checkpoint = replace(
        original.checkpoints[0],
        references=(replace(original.checkpoints[0].references[0], encoder_fingerprint="b" * 64),)
        * 3,
    )
    with pytest.raises(ValueError, match="MODEL_FINGERPRINT_MISMATCH"):
        match_checkpoint(
            vector(1), replace(original, checkpoints=(checkpoint, original.checkpoints[1])), {0}
        )
