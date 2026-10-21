"""Compare NMS-free top-k sets without relying on unstable tie ordering."""

import numpy as np


def compare_predictions(expected, actual, *, rtol=1e-3, atol=1e-3, cutoff_tie_atol=1e-6):
    if expected.shape != (1, 300, 6) or actual.shape != expected.shape:
        raise ValueError("Export prediction shape mismatch")
    if not np.isfinite(expected).all() or not np.isfinite(actual).all():
        raise ValueError("Non-finite export prediction")
    left, right = expected[0], actual[0]
    np.testing.assert_allclose(np.sort(left[:, 4]), np.sort(right[:, 4]), rtol=rtol, atol=atol)
    edges = np.all(np.isclose(left[:, None, :], right[None, :, :], rtol=rtol, atol=atol), axis=2)
    # A categorical class may never be admitted through numeric relative tolerance.
    edges &= left[:, None, 5] == right[None, :, 5]
    matched = {}

    def assign(index, seen):
        for other in np.flatnonzero(edges[index]):
            if other in seen:
                continue
            seen.add(other)
            if other not in matched or assign(matched[other], seen):
                matched[other] = index
                return True
        return False

    for index in range(300):
        assign(index, set())
    left_unmatched = sorted(set(range(300)) - set(matched.values()))
    right_unmatched = sorted(set(range(300)) - set(matched))
    if len(left_unmatched) > 1:
        raise ValueError("Export parity permits at most one tied cutoff selection")
    cutoff = max(float(left[:, 4].min()), float(right[:, 4].min()))
    # Top-k may select a different anchor only at its final score tie, never above it.
    for rows, indices in ((left, left_unmatched), (right, right_unmatched)):
        if indices and np.any(np.abs(rows[indices, 4] - cutoff) > cutoff_tie_atol):
            raise ValueError("Export prediction differs above top-k cutoff tie")
    maximum = max(
        (float(np.max(np.abs(left[i] - right[j]))) for j, i in matched.items()), default=0.0
    )
    return {
        "passed": True,
        "rtol": rtol,
        "atol": atol,
        "cutoff_tie_atol": cutoff_tie_atol,
        "matched_rows": len(matched),
        "cutoff_tied_rows": len(left_unmatched),
        "max_abs_error": maximum,
        "criterion": "one-to-one-unordered-topk-with-cutoff-score-ties",
    }
