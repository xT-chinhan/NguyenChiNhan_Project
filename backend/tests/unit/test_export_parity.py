import numpy as np
import pytest

from navcore.cli.export_parity import compare_predictions


def predictions():
    data = np.zeros((1, 300, 6), dtype=np.float32)
    data[0, :, :4] = np.arange(1200).reshape(300, 4)
    data[0, :, 4] = np.linspace(0.1, 0.9, 300)
    data[0, :, 5] = np.arange(300) % 80
    return data


def test_export_comparison_is_one_to_one_and_order_independent():
    data = predictions()
    result = compare_predictions(data, data[:, ::-1, :].copy())
    assert result["matched_rows"] == 300 and result["cutoff_tied_rows"] == 0


def test_only_final_score_ties_can_change_selected_anchor():
    data = predictions()
    tied = data.copy()
    tied[0, 0, :4] += 100
    assert compare_predictions(data, tied)["cutoff_tied_rows"] == 1
    wrong = data.copy()
    wrong[0, 25, :4] += 100
    with pytest.raises(ValueError, match="above top-k"):
        compare_predictions(data, wrong)


def test_missing_duplicate_and_wrong_class_above_cutoff_fail():
    data = predictions()
    for index, field in ((25, 5), (25, 0)):
        changed = data.copy()
        changed[0, index, field] += 2
        with pytest.raises(ValueError):
            compare_predictions(data, changed)
    duplicated = data.copy()
    duplicated[0, 20] = duplicated[0, 21]
    with pytest.raises((ValueError, AssertionError)):
        compare_predictions(data, duplicated)


def test_cutoff_ties_cannot_make_parity_vacuous():
    left = predictions()
    left[:, :, 4] = 0.5
    right = left.copy()
    right[:, :, :4] += 10000
    with pytest.raises(ValueError, match="at most one"):
        compare_predictions(left, right)
