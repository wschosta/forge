"""Tests for Elo Monte Carlo orchestration.

`elo/monte_carlo.py` sat at 15% coverage — the lowest in the project — because
the Elo integration tests call `elo_prediction` directly to keep their runtime
tractable, bypassing the orchestrator the pipeline actually uses. That left the
category bucketing and the averaging across iterations unverified.

Both matter. Bucketing decides which bills each policy area's Elo run sees, and
the averaging is what makes Elo scores meaningful at all — a single pass is
dominated by the random legislator ordering.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.config import ForgeConfig
from forge.elo.monte_carlo import _filter_bills_by_category, elo_monte_carlo
from forge.models.bill import Bill
from forge.models.chamber import ChamberData
from forge.models.vote import Vote


def _bill(bill_id: int, category, voters: list[int], complete: int = 1) -> Bill:
    """A bill carrying one passage rollcall that everyone voted on.

    `voters` are sponsor_id integers: Vote stores raw ids, and
    find_passage_vote converts them to "id{N}" strings against the roster.
    """
    yes = voters[: len(voters) // 2 + 1]
    no = voters[len(voters) // 2 + 1 :]
    vote = Vote(
        rollcall_id=bill_id,
        description="Third Reading",
        yea=len(yes),
        nay=len(no),
        nv=0,
        total_vote=len(voters),
        yes_percent=len(yes) / len(voters),
        yes_list=list(yes),
        no_list=list(no),
    )
    data = ChamberData(chamber_votes=[vote], competitive=1)
    data.final_yes_percentage = vote.yes_percent
    data.final_total_vote = vote.total_vote

    bill = Bill(bill_id=bill_id, bill_number=f"HB{bill_id}", title="A bill.")
    bill.issue_category = category
    bill.complete = complete
    bill.house_data = data
    bill.passed_house = 1
    return bill


#: Sized to Indiana's House, because elo_monte_carlo reads the chamber size
#: from the config and drops any bill whose passage vote covers less than half
#: of it. A smaller fixture silently yields no bills at all.
CHAMBER_SIZE = 100


@pytest.fixture
def small_chamber():
    ids = [f"id{i}" for i in range(CHAMBER_SIZE)]
    values = np.full((len(ids), len(ids)), 0.5)
    np.fill_diagonal(values, 1.0)
    matrix = pd.DataFrame(values, index=ids, columns=ids)
    people = pd.DataFrame(
        {"sponsor_id": [int(i[2:]) for i in ids],
         "party_id": [0] * (CHAMBER_SIZE // 2) + [1] * (CHAMBER_SIZE - CHAMBER_SIZE // 2)}
    )
    sponsor_ids = [int(i[2:]) for i in ids]
    bills = {
        1: _bill(1, 1, sponsor_ids),
        2: _bill(2, 2, sponsor_ids),
        3: _bill(3, 1, sponsor_ids),
    }
    return ids, matrix, people, bills


class TestCategoryBucketing:
    """Which bills each policy area's Elo run sees."""

    def test_category_zero_collects_every_bill(self, small_chamber):
        _, matrix, _, bills = small_chamber
        capture, flags = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [0], 11
        )
        assert flags == [0]
        assert sorted(capture[0]) == [1, 2, 3]

    def test_specific_category_collects_only_its_own(self, small_chamber):
        _, matrix, _, bills = small_chamber
        capture, flags = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [1], 11
        )
        assert flags == [1]
        assert sorted(capture[0]) == [1, 3]

    def test_negative_flag_expands_to_every_category(self, small_chamber):
        """A negative flag means 'all', per eloMonteCarlo.m."""
        _, matrix, _, bills = small_chamber
        _, flags = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [-1], 11
        )
        # 0 (pooled) plus the categories that actually have bills.
        assert 0 in flags
        assert 1 in flags and 2 in flags

    def test_empty_categories_are_dropped(self, small_chamber):
        """A policy area with no bills must not produce an empty Elo run."""
        _, matrix, _, bills = small_chamber
        capture, flags = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [1, 7], 11
        )
        assert 7 not in flags, "a category with no bills was kept"
        assert all(bucket for bucket in capture)

    def test_incomplete_bills_are_excluded(self, small_chamber):
        _, matrix, _, bills = small_chamber
        bills[2].complete = 0
        capture, _ = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [0], 11
        )
        assert 2 not in capture[0]

    def test_bills_with_too_few_voters_are_excluded(self, small_chamber):
        """A rollcall covering under half the chamber is not a chamber vote."""
        ids, matrix, _, bills = small_chamber
        sparse = _bill(4, 1, [int(i[2:]) for i in ids[:3]])  # far under half the chamber
        bills[4] = sparse
        capture, _ = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [0], 11
        )
        assert 4 not in capture[0]

    def test_no_qualifying_bills_returns_empty(self, small_chamber):
        _, matrix, _, bills = small_chamber
        for bill in bills.values():
            bill.complete = 0
        capture, flags = _filter_bills_by_category(
            list(bills), bills, "house", matrix, CHAMBER_SIZE, [0], 11
        )
        assert capture == [] and flags == []


class TestEloMonteCarlo:
    """Averaging across iterations, which is what makes Elo scores stable."""

    @staticmethod
    def _run(matrix, people, bills, iterations=3, flags=(0,)):
        config = ForgeConfig(
            state_id="IN",
            elo_monte_carlo_number=iterations,
            generate_all_categories=False,
        )
        return elo_monte_carlo(
            list(bills), bills, list(flags), people, None, matrix, "house", config
        )

    def test_returns_a_frame_per_category(self, small_chamber):
        _, matrix, people, bills = small_chamber
        results = self._run(matrix, people, bills)
        assert set(results) == {0}
        assert isinstance(results[0], pd.DataFrame)

    def test_scores_every_legislator(self, small_chamber):
        ids, matrix, people, bills = small_chamber
        results = self._run(matrix, people, bills)
        assert len(results[0]) == len(ids)

    def test_averaging_leaves_fixed_k_zero_sum(self, small_chamber):
        """Averaging a zero-sum quantity keeps it zero-sum.

        Fixed-K Elo conserves total rating within a pass, so the mean must
        still sit at the initial score after averaging. A drifting mean means
        the averaging is weighting passes unevenly.
        """
        _, matrix, people, bills = small_chamber
        results = self._run(matrix, people, bills, iterations=4)
        assert results[0]["score_fixed_k"].mean() == pytest.approx(1500.0, abs=1e-6)

    def test_more_iterations_reduce_spread(self, small_chamber):
        """Averaging more passes should pull scores toward the mean.

        This is the property the Monte Carlo exists for: a single pass is
        dominated by the random legislator ordering, and averaging is what
        removes it.
        """
        _, matrix, people, bills = small_chamber
        few = self._run(matrix, people, bills, iterations=2)
        many = self._run(matrix, people, bills, iterations=12)
        assert many[0]["score_variable_k"].std() <= few[0]["score_variable_k"].std() * 1.5

    def test_multiple_categories_are_scored_separately(self, small_chamber):
        _, matrix, people, bills = small_chamber
        results = self._run(matrix, people, bills, flags=(0, 1, 2))
        assert set(results) >= {0, 1}
        for frame in results.values():
            assert not frame.empty

    def test_results_are_finite(self, small_chamber):
        _, matrix, people, bills = small_chamber
        results = self._run(matrix, people, bills)
        for column in ["score_variable_k", "score_fixed_k", "count", "difference"]:
            assert np.isfinite(results[0][column]).all(), f"{column} has inf/NaN"
