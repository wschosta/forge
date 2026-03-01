"""Tests for Bayesian prediction module."""

from __future__ import annotations

import numpy as np
import pytest

from forge.predict.bayes import (
    compute_sponsor_effect,
    get_specific_impact,
    update_bayes,
)


class TestGetSpecificImpact:
    """Tests for get_specific_impact()."""

    def test_yea_high_consistency(self):
        assert get_specific_impact(1, 1.0) == 0.999

    def test_yea_low_consistency(self):
        assert get_specific_impact(1, 0.0) == 0.001

    def test_yea_mid_value(self):
        assert get_specific_impact(1, 0.7) == 0.7

    def test_nay_low_consistency(self):
        # voted no, low agreement → high impact
        assert get_specific_impact(0, 0.0) == 0.999

    def test_nay_high_consistency(self):
        # voted no, high agreement → low impact
        assert get_specific_impact(0, 1.0) == 0.001

    def test_nay_mid_value(self):
        # voted no, flip the value
        assert get_specific_impact(0, 0.3) == pytest.approx(0.7)

    def test_nan_returns_half(self):
        assert get_specific_impact(1, float("nan")) == 0.5
        assert get_specific_impact(0, float("nan")) == 0.5

    def test_invalid_preference_raises(self):
        with pytest.raises(ValueError, match="Non-binary"):
            get_specific_impact(2, 0.5)


class TestUpdateBayes:
    """Tests for update_bayes()."""

    @pytest.fixture
    def basic_setup(self):
        """Simple 3-legislator setup."""
        ids = ["id1", "id2", "id3"]
        # Agreement matrix: id1-id2 agree 80%, id1-id3 agree 20%, id2-id3 agree 50%
        chamber = np.array([
            [1.0, 0.8, 0.2],
            [0.8, 1.0, 0.5],
            [0.2, 0.5, 1.0],
        ])
        t_prev = np.array([0.5, 0.5, 0.5])
        t_final = np.array([1.0, 1.0, 0.0])
        return ids, chamber, t_prev, t_final

    def test_increments_t_count(self, basic_setup):
        ids, chamber, t_prev, t_final = basic_setup
        _, t_count, _ = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)
        assert t_count == 1

    def test_revealed_legislator_gets_set(self, basic_setup):
        ids, chamber, t_prev, t_final = basic_setup
        result, _, _ = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)
        assert result[0] == pytest.approx(0.999)  # abs(1 - 0.001)

    def test_revealed_no_legislator_gets_set(self, basic_setup):
        ids, chamber, t_prev, t_final = basic_setup
        result, _, _ = update_bayes("id3", 0, t_prev.copy(), chamber, 0, ids, t_final)
        assert result[2] == pytest.approx(0.001)  # abs(0 - 0.001)

    def test_clamping(self, basic_setup):
        ids, chamber, t_prev, t_final = basic_setup
        result, _, _ = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)
        assert all(0.001 <= v <= 0.999 for v in result)

    def test_accuracy_computed(self, basic_setup):
        ids, chamber, t_prev, t_final = basic_setup
        _, _, accuracy = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)
        assert isinstance(accuracy, float)

    def test_nan_preserved(self):
        ids = ["id1", "id2"]
        chamber = np.array([[1.0, 0.5], [0.5, 1.0]])
        t_prev = np.array([0.5, np.nan])
        t_final = np.array([1.0, np.nan])
        result, _, _ = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)
        # id2 should still be updated (it's in the impact list)
        # NaN in t_prev should get updated
        assert not np.isnan(result[0])

    def test_unknown_id_returns_unchanged(self):
        ids = ["id1", "id2"]
        chamber = np.array([[1.0, 0.5], [0.5, 1.0]])
        t_prev = np.array([0.5, 0.5])
        t_final = np.array([1.0, 0.0])
        result, _, _ = update_bayes("id99", 1, t_prev.copy(), chamber, 0, ids, t_final)
        np.testing.assert_array_equal(result, t_prev)

    def test_bayesian_formula_specific_case(self):
        """Verify the Bayesian update formula on a hand-computed case."""
        ids = ["id1", "id2"]
        # id1 and id2 agree 80% of the time
        chamber = np.array([[1.0, 0.8], [0.8, 1.0]])
        t_prev = np.array([0.5, 0.5])
        t_final = np.array([1.0, 1.0])

        result, _, _ = update_bayes("id1", 1, t_prev.copy(), chamber, 0, ids, t_final)

        # For id2: impact = |1 - 1 - 0.8| = 0.8
        # P_new = (0.8 * 0.5) / (0.8 * 0.5 + 0.2 * 0.5) = 0.4 / 0.5 = 0.8
        assert result[1] == pytest.approx(0.8)


class TestComputeSponsorEffect:
    def test_single_sponsor(self):
        result = compute_sponsor_effect(
            ["id1"], None, None, None, 0.5
        )
        assert result[0] == pytest.approx(0.5)

    def test_empty_sponsor(self):
        result = compute_sponsor_effect([], None, None, None, 0.5)
        assert len(result) == 0

    def test_with_matrix(self):
        sponsor_matrix = np.array([[0.7, 0.3], [0.3, 0.7]])
        row_names = ["id1", "id2"]
        col_names = ["id1", "id2"]
        result = compute_sponsor_effect(
            ["id1", "id2"], sponsor_matrix, row_names, col_names, 0.5
        )
        assert len(result) == 2
        # Values should be between 0 and 1
        assert all(0 <= v <= 1 for v in result)
