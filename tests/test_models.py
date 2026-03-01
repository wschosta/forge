"""Tests for forge.models — Bill, Vote, ChamberData data models."""

import math

from forge.models import Bill, ChamberData, Vote


class TestVote:
    def test_default_construction(self):
        v = Vote()
        assert v.rollcall_id == 0
        assert v.description == ""
        assert v.yea == 0
        assert v.nay == 0
        assert v.yes_list == []
        assert v.no_list == []
        assert v.abstain_list == []

    def test_construction_with_values(self):
        v = Vote(
            rollcall_id=12345,
            description="Third Reading",
            date="2024-01-15",
            yea=55,
            nay=44,
            nv=1,
            total_vote=99,
            yes_percent=55 / 99,
            yes_list=[100, 200, 300],
            no_list=[400, 500],
            abstain_list=[600],
        )
        assert v.rollcall_id == 12345
        assert v.yea == 55
        assert v.nay == 44
        assert len(v.yes_list) == 3
        assert len(v.no_list) == 2

    def test_lists_are_independent(self):
        """Each Vote instance should have its own lists."""
        v1 = Vote()
        v2 = Vote()
        v1.yes_list.append(999)
        assert v2.yes_list == []


class TestChamberData:
    def test_default_construction(self):
        cd = ChamberData()
        assert cd.committee_votes == []
        assert cd.chamber_votes == []
        assert cd.final_yes_percentage == -1.0
        assert cd.competitive == 0

    def test_with_votes(self):
        v1 = Vote(rollcall_id=1, yea=60, nay=40, total_vote=100, yes_percent=0.6)
        v2 = Vote(rollcall_id=2, yea=55, nay=45, total_vote=100, yes_percent=0.55)
        cd = ChamberData(
            chamber_votes=[v1, v2],
            final_yea=55,
            final_nay=45,
            final_total_vote=100,
            final_yes_percentage=0.55,
            competitive=1,
        )
        assert len(cd.chamber_votes) == 2
        assert cd.final_yes_percentage == 0.55
        assert cd.competitive == 1


class TestBill:
    def test_default_construction(self):
        b = Bill()
        assert b.bill_id == 0
        assert b.title == ""
        assert math.isnan(b.issue_category)
        assert b.sponsors == []
        assert b.passed_house == -1
        assert b.passed_senate == -1
        assert b.passed_both == -1
        assert b.competitive == 0
        assert b.complete == 0
        assert b.house_data is None
        assert b.senate_data is None

    def test_construction_with_chamber_data(self):
        house = ChamberData(final_yes_percentage=0.6, competitive=1)
        senate = ChamberData(final_yes_percentage=0.7, competitive=0)
        b = Bill(
            bill_id=42,
            bill_number="HB1234",
            title="An act concerning widgets",
            issue_category=4,
            sponsors=[100, 200],
            house_data=house,
            senate_data=senate,
            passed_house=1,
            passed_senate=1,
            passed_both=1,
            competitive=1,
            complete=1,
        )
        assert b.bill_id == 42
        assert b.issue_category == 4
        assert b.house_data.final_yes_percentage == 0.6
        assert b.passed_both == 1

    def test_sponsors_list_independent(self):
        b1 = Bill()
        b2 = Bill()
        b1.sponsors.append(999)
        assert b2.sponsors == []
