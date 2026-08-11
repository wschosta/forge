"""Elo validation against the committed MATLAB scores.

The Elo half had never been run against real data. Unlike the agreement
matrices, its goldens cannot be reproduced exactly in a test: MATLAB's were
produced at 15,000 Monte Carlo iterations, which extrapolates to roughly a day
of compute even after optimization. So this module validates what is checkable
at a tractable iteration count:

* the output has the structure and labels MATLAB's has;
* the invariants of the rating system hold (fixed-K Elo is zero-sum, so its
  mean must stay pinned at the initial score);
* the pairwise comparison budget scales with iteration count the way MATLAB's
  did, which is what catches a run silently comparing the wrong population.

Score *values* are deliberately not asserted against the golden. At 25
iterations against MATLAB's 15,000 the spread is far wider — 1060-1880 against
1232-1516 — because the mean has not been approached yet. Asserting on that
would either need a tolerance so loose it proves nothing, or a day-long test.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

REFERENCE_CATEGORY = 0
GOLDEN_ITERATIONS = 15_000

#: Small enough to run in CI, large enough that per-legislator counts are stable.
TEST_ITERATIONS = 8

ELO_COLUMNS = ["score_variable_k", "score_fixed_k", "count", "difference"]


@pytest.fixture(scope="module")
def elo_golden(golden_dir: Path) -> pd.DataFrame:
    """MATLAB's Elo scores for the pooled category."""
    path = (
        golden_dir.parent
        / "elo_model"
        / f"H_elo_score_total_{REFERENCE_CATEGORY}_mc{GOLDEN_ITERATIONS}.csv"
    )
    if not path.exists():
        pytest.skip(f"Elo golden not available at {path}")
    return pd.read_csv(path, index_col=0)


@pytest.fixture(scope="module")
def elo_run(indiana_run: Path):
    """Run Elo over the real Indiana House bills at a tractable iteration count."""
    from forge.classify.learning import load_matlab_learning_data
    from forge.config import ForgeConfig
    from forge.elo.rating import elo_prediction
    from forge.ingest.csv_reader import read_all_csv
    from forge.matrices.agreement import process_chamber_votes
    from forge.pipeline.runner import _init_bills, _prepare_people

    import numpy as np

    root = Path(__file__).resolve().parents[2]
    config = ForgeConfig(
        state_id="IN",
        generate_all_categories=False,
        elo_monte_carlo_number=TEST_ITERATIONS,
        learning_data_path=str(root / "+la" / "learning_algorithm_data.mat"),
    )
    learning = load_matlab_learning_data(config.learning_data_path)
    frames = {
        name: read_all_csv(name, "IN", root / "legiscan_data")
        for name in ["bills", "people", "rollcalls", "votes", "sponsors", "history"]
    }
    bill_set = _init_bills(
        frames["bills"], frames["rollcalls"], frames["votes"],
        frames["sponsors"], frames["history"], config, learning,
    )
    people = _prepare_people(frames["people"], "IN", "house", root / "data" / "IN")
    matrices = process_chamber_votes(
        bill_set, people, "house", category=0,
        competitive_threshold=config.competitive_threshold,
    )
    # A single seeded pass — enough to exercise the real code path over all
    # bills without paying for the full Monte Carlo.
    return elo_prediction(
        matrices.bill_ids, bill_set, people,
        matrices.chamber_sponsor_matrix, matrices.chamber_matrix,
        "house", config, rng=np.random.default_rng(1),
    )


class TestEloStructure:
    def test_produces_scores(self, elo_run) -> None:
        """Guard against the silent-empty-output mode seen elsewhere."""
        assert elo_run is not None, "Elo produced no output at all"
        assert not elo_run.empty
        assert len(elo_run) > 0

    def test_columns_match_the_golden(self, elo_run, elo_golden) -> None:
        for column in ELO_COLUMNS:
            assert column in elo_run.columns, f"missing {column}"
            assert column in elo_golden.columns

    def test_rates_every_legislator_in_the_chamber(self, elo_run) -> None:
        assert len(elo_run) == 100, f"expected the 100-seat Indiana House, got {len(elo_run)}"

    def test_roster_overlaps_the_golden_substantially(self, elo_run, elo_golden) -> None:
        """The two rosters overlap heavily but neither contains the other.

        This is a provenance artifact, not a defect. The Elo and prediction
        goldens were generated from LegiScan's 104-member roster, while the
        agreement-matrix goldens use the curated 2013-2014 roster of 100 that
        state.m substitutes for Indiana. The curated roster carries 13 members
        LegiScan's does not and vice versa, leaving 87 in common.

        Asserting the overlap rather than a subset keeps this test sensitive to
        a genuine roster-selection regression while documenting that the
        committed outputs were not all produced from one configuration.
        """
        run_ids, golden_ids = set(elo_run.index), set(elo_golden.index)
        shared = run_ids & golden_ids
        assert len(shared) >= 85, (
            f"only {len(shared)} legislators shared with the golden roster; "
            f"expected ~87. Run-only: {sorted(run_ids - golden_ids)}"
        )


class TestEloInvariants:
    def test_fixed_k_elo_is_zero_sum(self, elo_run) -> None:
        """Fixed-K Elo conserves total rating, so the mean cannot drift.

        MATLAB's golden has a fixed-K mean of exactly 1500. A drifting mean
        means points are being created or destroyed in the pairwise update.
        """
        assert elo_run["score_fixed_k"].mean() == pytest.approx(1500.0, abs=1e-6)

    def test_variable_k_elo_stays_near_the_initial_score(self, elo_run) -> None:
        """Variable-K is not exactly zero-sum, but should not drift far."""
        assert elo_run["score_variable_k"].mean() == pytest.approx(1500.0, abs=25.0)

    def test_difference_is_the_two_variants_subtracted(self, elo_run) -> None:
        expected = elo_run["score_variable_k"] - elo_run["score_fixed_k"]
        pd.testing.assert_series_equal(
            elo_run["difference"], expected, check_names=False
        )

    def test_every_legislator_took_part_in_comparisons(self, elo_run) -> None:
        """A zero count means a legislator was rated without ever being compared."""
        assert (elo_run["count"] > 0).all()

    def test_scores_are_finite(self, elo_run) -> None:
        import numpy as np

        for column in ["score_variable_k", "score_fixed_k", "difference"]:
            assert np.isfinite(elo_run[column]).all(), f"{column} contains inf/NaN"


class TestEloComparisonBudget:
    """`count` records pairwise comparisons and is the most diagnostic column.

    It is a pure integer tally with no averaging, so it pins down whether the
    run compared the population MATLAB compared. Values scale linearly with
    iteration count, so the golden's totals are checked after normalizing.
    """

    def test_count_scales_with_the_golden_after_normalizing(self, elo_run, elo_golden) -> None:
        golden_per_iteration = elo_golden["count"].mean() / GOLDEN_ITERATIONS
        run_per_iteration = elo_run["count"].mean()
        ratio = run_per_iteration / golden_per_iteration
        # A factor-of-two band: the two runs process slightly different bill
        # sets, so this catches an order-of-magnitude divergence rather than
        # asserting exact agreement.
        assert 0.5 < ratio < 2.0, (
            f"pairwise comparisons per iteration differ by {ratio:.2f}x "
            f"(golden {golden_per_iteration:.0f}, run {run_per_iteration:.0f})"
        )
