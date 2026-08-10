"""Tests for per-legislator impact scoring.

This module had no test coverage, which is how an inverted normalization
survived: the impact scores are the pipeline's headline per-legislator output,
and getting their *sign* wrong reverses the ranking without changing anything
structural about the table.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.predict.impact import process_legislator_impacts


def _mc_inputs(n_bills=3, n_mc=4, n_legs=5, seed=3, step_sign=0):
    """Build Monte Carlo outputs shaped the way run_monte_carlo returns them.

    ``step_sign`` forces the per-step accuracy deltas negative (-1), positive
    (+1), or leaves them mixed (0). Real runs land in a regime where every
    aggregated raw score is negative, which is what makes the signed-maximum
    normalization flip the whole column positive; forcing the sign lets that
    regime be tested deterministically.
    """
    rng = np.random.default_rng(seed)
    bill_ids = list(range(100, 100 + n_bills))
    accuracy_list = rng.uniform(60, 99, size=(n_bills, n_mc))
    accuracy_delta = rng.uniform(-5, 5, size=(n_bills, n_mc))
    legislators_list = [[list(rng.permutation(n_legs)) for _ in range(n_mc)] for _ in range(n_bills)]

    def steps():
        if step_sign < 0:
            return -rng.uniform(0.5, 2.0, size=n_legs)
        if step_sign > 0:
            return rng.uniform(0.5, 2.0, size=n_legs)
        return rng.uniform(-2, 2, size=n_legs)

    accuracy_steps_list = [[steps() for _ in range(n_mc)] for _ in range(n_bills)]
    return accuracy_list, accuracy_delta, legislators_list, accuracy_steps_list, bill_ids


class TestResultsNormalization:
    """`results` is normalized by the SIGNED maximum, per processLegislatorImpacts.m:81.

    Raw impact scores come out negative in practice, so dividing by the signed
    maximum — the least-negative value — flips the column positive and maps the
    most-negative raw score to +1.0. Using an absolute maximum instead leaves
    the column negative and sends that legislator to -1.0, inverting the impact
    ranking against every committed MATLAB output.
    """

    def test_the_former_maximum_normalizes_to_exactly_one(self):
        """Dividing by the signed maximum pins that element at 1.0.

        Other elements may exceed 1.0 when the divisor is negative — that is
        the sign flip in action, not a bug.
        """
        table = process_legislator_impacts(*_mc_inputs())
        assert table is not None
        assert np.isclose(table["results"], 1.0).sum() == 1

    def test_results_are_positive_when_raw_scores_are_negative(self):
        """The regime real runs land in: every raw score negative.

        Indiana's committed golden has all-positive `results` precisely because
        its raw scores are all negative and the signed maximum flips them. An
        absolute-maximum normalization would leave this column negative and
        reverse the ranking.
        """
        table = process_legislator_impacts(*_mc_inputs(step_sign=-1))
        assert table is not None
        assert (table["results"] > 0).all(), (
            f"impact scores came out negative: {table['results'].round(3).tolist()}"
        )

    def test_ranking_matches_the_committed_golden_direction(self):
        """The highest-impact legislator must score high, not low.

        This is the defect this replaced, stated in terms of the artifact that
        exposed it: Indiana's golden runs 0.028 to 1.000, all positive. An
        absolute-maximum divisor produced -1.000 to -0.026 — same magnitudes,
        reversed order — so a rank correlation against the golden came out
        negative.
        """
        table = process_legislator_impacts(*_mc_inputs(step_sign=-1))
        assert table is not None
        assert table["results"].min() > 0
        assert table["results"].idxmax() is not None
        # The element that was least-negative before normalization is now the
        # smallest positive, and the most-negative is the largest.
        assert table["results"].max() >= 1.0

    def test_ranking_is_stable_under_rescaling(self):
        """Normalization must reorder nothing — it only sets the scale."""
        inputs = _mc_inputs()
        table = process_legislator_impacts(*inputs)
        scaled = list(inputs)
        scaled[3] = [[step * 10.0 for step in bill] for bill in inputs[3]]
        rescaled = process_legislator_impacts(*scaled)

        assert table is not None and rescaled is not None
        order = table.sort_values("results")["legislator_id"].tolist()
        rescaled_order = rescaled.sort_values("results")["legislator_id"].tolist()
        assert order == rescaled_order


class TestCoverage:
    """`coverage` is the share of processed bills a legislator appeared in."""

    def test_coverage_is_a_fraction_of_bills(self):
        table = process_legislator_impacts(*_mc_inputs(n_bills=3))
        assert table is not None
        assert ((table["coverage"] > 0) & (table["coverage"] <= 1)).all()

    def test_full_participation_gives_coverage_of_one(self):
        """Every legislator appears in every bill in this fixture."""
        table = process_legislator_impacts(*_mc_inputs(n_bills=4, n_legs=5))
        assert table is not None
        assert table["coverage"].max() == pytest.approx(1.0)


class TestDegenerateInputs:
    def test_empty_inputs_return_none(self):
        assert process_legislator_impacts(np.array([]), np.array([]), [], [], []) is None

    def test_no_legislators_returns_none(self):
        accuracy_list, accuracy_delta, _, steps, bill_ids = _mc_inputs()
        assert process_legislator_impacts(accuracy_list, accuracy_delta, [], steps, bill_ids) is None

    def test_zero_maximum_does_not_divide(self):
        """A degenerate all-zero column must not produce inf/NaN."""
        accuracy_list, accuracy_delta, legislators, steps, bill_ids = _mc_inputs()
        zeroed = [[np.zeros_like(s) for s in bill] for bill in steps]
        table = process_legislator_impacts(accuracy_list, accuracy_delta, legislators, zeroed, bill_ids)
        assert table is not None
        assert np.isfinite(table["results"]).all()


class TestTableShape:
    def test_one_row_per_unique_legislator(self):
        table = process_legislator_impacts(*_mc_inputs(n_legs=6))
        assert table is not None
        assert len(table) == table["legislator_id"].nunique()

    def test_expected_columns(self):
        table = process_legislator_impacts(*_mc_inputs())
        assert table is not None
        assert list(table.columns) == ["legislator_id", "coverage", "results"]


class TestResultsCsv:
    """The impact table has to reach disk; computing it is not enough.

    montecarloPrediction.m:20 writes it, and the committed
    H_prediction_model_results_m*.csv files are that write. The Python port
    computed the table, returned it, and left the outputs directory empty.
    """

    @staticmethod
    def _write(tmp_path, chamber="house", mc=50):
        from forge.predict.monte_carlo import _write_results_table

        table = pd.DataFrame(
            {"legislator_id": [5482, 5483], "coverage": [0.9, 0.8], "results": [1.0, 0.4]}
        )
        people = pd.DataFrame({"sponsor_id": [5482, 5483], "name": ["Scott Pelath", "Eric Koch"]})
        return _write_results_table(table, people, chamber, mc, str(tmp_path)), table

    def test_writes_matlab_named_file(self, tmp_path):
        path, _ = self._write(tmp_path)
        assert path is not None
        assert path.name == "H_prediction_model_results_m50.csv"
        assert path.exists()

    def test_columns_match_the_golden_layout(self, tmp_path):
        path, _ = self._write(tmp_path)
        written = pd.read_csv(path)
        assert list(written.columns) == [
            "master_unique_legislators", "sponsor_names", "coverage", "results",
        ]

    def test_resolves_legislator_names(self, tmp_path):
        path, _ = self._write(tmp_path)
        written = pd.read_csv(path)
        assert written["sponsor_names"].tolist() == ["Scott Pelath", "Eric Koch"]

    def test_unknown_legislator_keeps_its_row(self, tmp_path):
        """A missing name must not silently drop the impact score."""
        from forge.predict.monte_carlo import _write_results_table

        table = pd.DataFrame({"legislator_id": [1], "coverage": [0.5], "results": [1.0]})
        people = pd.DataFrame({"sponsor_id": [999], "name": ["Someone Else"]})
        path = _write_results_table(table, people, "senate", 10, str(tmp_path))
        written = pd.read_csv(path)
        assert len(written) == 1
        assert pd.isna(written["sponsor_names"].iloc[0]) or written["sponsor_names"].iloc[0] == ""

    def test_senate_gets_its_own_prefix(self, tmp_path):
        path, _ = self._write(tmp_path, chamber="senate", mc=16000)
        assert path.name == "S_prediction_model_results_m16000.csv"

    def test_no_directory_writes_nothing(self):
        from forge.predict.monte_carlo import _write_results_table

        table = pd.DataFrame({"legislator_id": [1], "coverage": [1.0], "results": [1.0]})
        assert _write_results_table(table, pd.DataFrame(), "house", 10, None) is None
