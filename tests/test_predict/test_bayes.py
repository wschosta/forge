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


class TestUpdateBayesIdIndex:
    """The prebuilt id_index is a pure speed optimization, not a behaviour change.

    update_bayes runs once per legislator per Monte Carlo iteration — several
    million times in a production run — so the revealed legislator is located
    via a prebuilt dict rather than a linear scan over the ID strings. These
    tests pin the two paths together so the fast path cannot silently drift.
    """

    @staticmethod
    def _fixture(n=12, seed=7):
        rng = np.random.default_rng(seed)
        ids = [f"id{i}" for i in range(n)]
        agreement = rng.random((n, n))
        agreement = (agreement + agreement.T) / 2
        np.fill_diagonal(agreement, 1.0)
        # Real agreement matrices carry NaN where two legislators never co-voted.
        agreement[0, n - 1] = np.nan
        agreement[n - 1, 0] = np.nan
        final = rng.choice([0.0, 1.0, np.nan], size=n)
        previous = np.full(n, 0.5)
        return ids, agreement, final, previous

    def test_index_path_matches_scan_path(self):
        ids, agreement, final, previous = self._fixture()
        index = {lid: i for i, lid in enumerate(ids)}

        for revealed in ids:
            for preference in (0, 1):
                scanned = update_bayes(revealed, preference, previous.copy(), agreement, 1, ids, final)
                indexed = update_bayes(
                    revealed, preference, previous.copy(), agreement, 1, ids, final, id_index=index
                )
                np.testing.assert_array_equal(scanned[0], indexed[0])
                assert scanned[1] == indexed[1]
                assert scanned[2] == indexed[2]

    def test_unknown_legislator_is_a_no_op_on_both_paths(self):
        ids, agreement, final, previous = self._fixture()
        index = {lid: i for i, lid in enumerate(ids)}

        scanned = update_bayes("id999", 1, previous.copy(), agreement, 3, ids, final)
        indexed = update_bayes("id999", 1, previous.copy(), agreement, 3, ids, final, id_index=index)

        np.testing.assert_array_equal(scanned[0], previous)
        np.testing.assert_array_equal(indexed[0], previous)
        assert scanned[1] == indexed[1] == 4
        assert scanned[2] == indexed[2] == 0.0

    def test_revealed_legislator_has_zero_self_impact(self):
        """Computing the whole impact column must still exclude the revealed one."""
        ids, agreement, final, previous = self._fixture()
        index = {lid: i for i, lid in enumerate(ids)}

        updated, _, _ = update_bayes("id3", 1, previous.copy(), agreement, 1, ids, final, id_index=index)
        # The revealed legislator is pinned to its own preference, not updated.
        assert updated[3] == pytest.approx(abs(1 - 0.001))

    def test_accuracy_discounts_legislators_with_no_recorded_vote(self):
        """NaN outcomes must not be counted as mispredictions."""
        ids = ["id0", "id1", "id2"]
        agreement = np.array([[1.0, 0.9, 0.8], [0.9, 1.0, 0.7], [0.8, 0.7, 1.0]])
        previous = np.array([0.5, 0.5, 0.5])
        all_known = np.array([1.0, 1.0, 1.0])
        one_unknown = np.array([1.0, 1.0, np.nan])

        _, _, acc_known = update_bayes("id0", 1, previous.copy(), agreement, 1, ids, all_known)
        _, _, acc_unknown = update_bayes("id0", 1, previous.copy(), agreement, 1, ids, one_unknown)
        assert 0.0 <= acc_known <= 100.0
        assert 0.0 <= acc_unknown <= 100.0


class TestAccuracyDenominator:
    """Accuracy is scaled by the real roster size, not MATLAB's hardcoded 100.

    predictOutcomes.m:149 computes `100*(1-(incorrect-are_nan)/(100-are_nan))`.
    That literal 100 is a stand-in for the number of legislators, and it is only
    correct for a 100-seat chamber. The port divides by the actual roster
    instead, which REFACTORING_PLAN.md lists as an intended fix.

    The consequence is easy to miss and worth stating: for the House the two
    agree exactly, but for every Senate they do not, and not by a little. With
    five mispredictions and no abstentions:

        chamber              MATLAB     port    difference
        House (100 seats)    95.00%   95.00%      0.00 pts
        Indiana Senate (51)  95.00%   90.20%      4.80 pts
        Wisconsin Senate(34) 95.00%   85.29%      9.71 pts
        Oregon Senate (29)   95.00%   82.76%     12.24 pts

    So Senate prediction and Elo accuracy figures are *expected* to disagree
    with the committed MATLAB outputs, independently of every other difference
    documented elsewhere. A future comparison that finds Senate accuracies
    "wrong" should check this first.
    """

    @staticmethod
    def _accuracy(n_legislators: int, n_wrong: int) -> float:
        ids = [f"id{i}" for i in range(n_legislators)]
        agreement = np.full((n_legislators, n_legislators), 0.5)
        np.fill_diagonal(agreement, 1.0)
        # Everyone voted yes; the first n_wrong are predicted no.
        final = np.ones(n_legislators)
        previous = np.concatenate(
            [np.full(n_wrong, 0.1), np.full(n_legislators - n_wrong, 0.9)]
        )
        index = {lid: i for i, lid in enumerate(ids)}
        _, _, accuracy = update_bayes(
            ids[-1], 1, previous, agreement, 1, ids, final, id_index=index
        )
        return accuracy

    def test_scales_by_the_actual_roster_size(self):
        """A 50-seat chamber must not be scored as though it had 100 seats."""
        small = self._accuracy(50, 5)
        large = self._accuracy(100, 5)
        assert small < large, (
            "the same number of mispredictions should cost more in a smaller "
            "chamber; scoring both against 100 would make them equal"
        )

    def test_house_sized_chamber_matches_the_matlab_formula(self):
        """Where MATLAB's hardcoded 100 is correct, the results coincide."""
        accuracy = self._accuracy(100, 5)
        matlab = 100.0 * (1.0 - 5 / 100)
        assert accuracy == pytest.approx(matlab, abs=1e-9)

    def test_senate_sized_chamber_diverges_from_matlab_as_expected(self):
        """Pin the magnitude, so the divergence is never mistaken for a bug."""
        accuracy = self._accuracy(51, 5)
        matlab = 100.0 * (1.0 - 5 / 100)
        assert accuracy == pytest.approx(100.0 * (1.0 - 5 / 51), abs=1e-9)
        assert matlab - accuracy == pytest.approx(4.80, abs=0.05)

    def test_perfect_prediction_is_full_marks_at_any_size(self):
        for size in (29, 51, 100):
            assert self._accuracy(size, 0) == pytest.approx(100.0, abs=1e-9)
