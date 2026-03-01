"""Tests for the rollcall processing module."""

from __future__ import annotations

import pandas as pd
import pytest

from forge.matrices.rollcalls import add_rollcall_votes, process_chamber_rollcalls


@pytest.fixture
def sample_rollcalls():
    """Create a sample rollcalls DataFrame."""
    return pd.DataFrame({
        "roll_call_id": [1001, 1002, 1003],
        "description": ["Committee Vote", "Third Reading", "Amendment"],
        "date": ["2020-01-01", "2020-01-02", "2020-01-03"],
        "yea": [5, 55, 10],
        "nay": [3, 40, 8],
        "nv": [0, 5, 2],
        "total_vote": [8, 95, 18],
        "yes_percent": [5 / 8, 55 / 95, 10 / 18],
    })


@pytest.fixture
def sample_votes():
    """Create a sample votes DataFrame matching the rollcalls."""
    return pd.DataFrame({
        "roll_call_id": [1001, 1001, 1002, 1002, 1002, 1003],
        "sponsor_id": [100, 200, 100, 200, 300, 100],
        "vote": [1, 2, 1, 1, 2, 3],  # yea=1, nay=2, absent=3
    })


class TestAddRollcallVotes:
    def test_basic(self, sample_rollcalls, sample_votes):
        vote = add_rollcall_votes(sample_rollcalls.iloc[0], sample_votes)
        assert vote.rollcall_id == 1001
        assert vote.yea == 5
        assert vote.nay == 3
        assert 100 in vote.yes_list
        assert 200 in vote.no_list

    def test_second_rollcall(self, sample_rollcalls, sample_votes):
        vote = add_rollcall_votes(sample_rollcalls.iloc[1], sample_votes)
        assert vote.rollcall_id == 1002
        # Both 100 and 200 voted yea, 300 voted nay
        assert 100 in vote.yes_list
        assert 200 in vote.yes_list
        assert 300 in vote.no_list

    def test_abstain(self, sample_rollcalls, sample_votes):
        vote = add_rollcall_votes(sample_rollcalls.iloc[2], sample_votes)
        assert 100 in vote.abstain_list


class TestProcessChamberRollcalls:
    def test_separates_committee_and_chamber(self, sample_rollcalls, sample_votes):
        # Committee threshold at 50 total votes
        cd = process_chamber_rollcalls(sample_rollcalls, sample_votes, 50.0)

        # Roll call 1001 (total=8) and 1003 (total=18) → committee
        assert len(cd.committee_votes) == 2
        # Roll call 1002 (total=95) → chamber
        assert len(cd.chamber_votes) == 1

    def test_final_vote_stats(self, sample_rollcalls, sample_votes):
        cd = process_chamber_rollcalls(sample_rollcalls, sample_votes, 50.0)
        assert cd.final_yea == 55
        assert cd.final_nay == 40
        assert cd.final_total_vote == 95
        assert cd.final_yes_percentage == pytest.approx(55 / 95)

    def test_all_committee(self, sample_rollcalls, sample_votes):
        # Threshold higher than all votes
        cd = process_chamber_rollcalls(sample_rollcalls, sample_votes, 200.0)
        assert len(cd.committee_votes) == 3
        assert len(cd.chamber_votes) == 0
        assert cd.final_yes_percentage == -1.0

    def test_all_chamber(self, sample_rollcalls, sample_votes):
        # Threshold lower than all votes
        cd = process_chamber_rollcalls(sample_rollcalls, sample_votes, 1.0)
        assert len(cd.committee_votes) == 0
        assert len(cd.chamber_votes) == 3
