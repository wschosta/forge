"""Tests for Monte Carlo prediction module."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.models.bill import Bill
from forge.models.chamber import ChamberData
from forge.models.vote import Vote
from forge.predict.monte_carlo import predict_outcomes, run_monte_carlo


def _make_test_bill(
    bill_id: int = 1,
    yes_list: list[int] | None = None,
    no_list: list[int] | None = None,
    sponsors: list[int] | None = None,
    competitive: int = 1,
    complete: int = 1,
) -> Bill:
    """Create a test bill with chamber data for house."""
    if yes_list is None:
        yes_list = [101, 102, 103]
    if no_list is None:
        no_list = [201, 202]
    if sponsors is None:
        sponsors = [101]

    vote = Vote(
        rollcall_id=1,
        description="Third Reading",
        date="2020-01-01",
        yea=len(yes_list),
        nay=len(no_list),
        nv=0,
        total_vote=len(yes_list) + len(no_list),
        yes_percent=len(yes_list) / (len(yes_list) + len(no_list)),
        yes_list=yes_list,
        no_list=no_list,
    )

    house_data = ChamberData(
        chamber_votes=[vote],
        final_yes_percentage=vote.yes_percent,
        competitive=competitive,
    )

    return Bill(
        bill_id=bill_id,
        bill_number=f"HB{bill_id}",
        title="Test Bill",
        issue_category=1,
        sponsors=sponsors,
        house_data=house_data,
        passed_house=1,
        competitive=competitive,
        complete=complete,
    )


@pytest.fixture
def test_ids():
    return ["id101", "id102", "id103", "id201", "id202"]


@pytest.fixture
def test_chamber_matrix(test_ids):
    """5x5 agreement matrix."""
    n = len(test_ids)
    # Create a realistic-ish agreement matrix
    data = np.full((n, n), 0.5)
    # Same-party agreement higher
    data[0:3, 0:3] = 0.8  # yes-voters agree
    data[3:5, 3:5] = 0.8  # no-voters agree
    data[0:3, 3:5] = 0.2  # cross-party disagreement
    data[3:5, 0:3] = 0.2
    np.fill_diagonal(data, 1.0)
    return pd.DataFrame(data, index=test_ids, columns=test_ids)


@pytest.fixture
def test_sponsor_matrix(test_ids):
    """5x5 sponsor matrix."""
    n = len(test_ids)
    data = np.full((n, n), 0.5)
    return pd.DataFrame(data, index=test_ids, columns=test_ids)


class TestPredictOutcomes:
    def test_returns_none_for_incomplete_bill(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        bill = _make_test_bill(complete=0)
        result = predict_outcomes(
            bill, 1, test_ids, test_sponsor_matrix,
            test_chamber_matrix.values, "house", 100, monte_carlo_number=1,
        )
        assert result is None

    def test_single_iteration(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        bill = _make_test_bill()
        result = predict_outcomes(
            bill, 1, test_ids, test_sponsor_matrix,
            test_chamber_matrix.values, "house", 5,
            monte_carlo_number=1,
        )
        assert result is not None
        assert result["accuracy_list"].shape == (2, 1)
        assert len(result["legislators_list"]) == 1
        assert len(result["accuracy_steps_list"]) == 1

    def test_multiple_iterations(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        bill = _make_test_bill()
        result = predict_outcomes(
            bill, 1, test_ids, test_sponsor_matrix,
            test_chamber_matrix.values, "house", 5,
            monte_carlo_number=10,
        )
        assert result is not None
        assert result["accuracy_list"].shape == (2, 10)
        assert len(result["legislators_list"]) == 10

    def test_accuracy_in_range(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        bill = _make_test_bill()
        result = predict_outcomes(
            bill, 1, test_ids, test_sponsor_matrix,
            test_chamber_matrix.values, "house", 5,
            monte_carlo_number=5,
        )
        # Accuracies should be percentages
        assert all(0 <= a <= 100 for a in result["accuracy_list"][0])


class TestRunMonteCarlo:
    def test_basic(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        bill = _make_test_bill(bill_id=1)
        bill_set = {1: bill}

        people = pd.DataFrame({
            "sponsor_id": [101, 102, 103, 201, 202],
            "party_id": [1, 1, 1, 0, 0],
        })

        result = run_monte_carlo(
            bill_ids=[1],
            bill_set=bill_set,
            chamber_people=people,
            chamber_sponsor_matrix=test_sponsor_matrix,
            chamber_matrix=test_chamber_matrix,
            chamber="house",
            chamber_size=5,
            monte_carlo_number=3,
        )
        assert len(result["bill_ids"]) == 1
        assert result["accuracy_list"].shape == (1, 3)

    def test_empty_bill_set(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        people = pd.DataFrame({
            "sponsor_id": [101, 102, 103, 201, 202],
            "party_id": [1, 1, 1, 0, 0],
        })
        result = run_monte_carlo(
            bill_ids=[],
            bill_set={},
            chamber_people=people,
            chamber_sponsor_matrix=test_sponsor_matrix,
            chamber_matrix=test_chamber_matrix,
            chamber="house",
            chamber_size=5,
            monte_carlo_number=3,
        )
        assert len(result["bill_ids"]) == 0

    def test_skips_incomplete_bills(self, test_ids, test_chamber_matrix, test_sponsor_matrix):
        incomplete = _make_test_bill(bill_id=1, complete=0)
        complete = _make_test_bill(bill_id=2, complete=1)
        bill_set = {1: incomplete, 2: complete}

        people = pd.DataFrame({
            "sponsor_id": [101, 102, 103, 201, 202],
            "party_id": [1, 1, 1, 0, 0],
        })

        result = run_monte_carlo(
            bill_ids=[1, 2],
            bill_set=bill_set,
            chamber_people=people,
            chamber_sponsor_matrix=test_sponsor_matrix,
            chamber_matrix=test_chamber_matrix,
            chamber="house",
            chamber_size=5,
            monte_carlo_number=2,
        )
        # Only bill 2 should be processed
        assert result["bill_ids"] == [2]
