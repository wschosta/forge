"""The matrix cache must never serve a result the inputs no longer justify.

Caching the matrix stage saves a couple of minutes per invocation, which matters
when a long Monte Carlo or Elo run is being resumed repeatedly. But a cache hit
that should have been a miss is worse than no cache at all: it would produce
outputs silently inconsistent with the inputs, and nothing downstream would
notice.

So these tests are mostly about invalidation. The signature covers every input
``process_chamber_votes`` reads, and each test changes exactly one of them and
asserts the signature moves.
"""

from __future__ import annotations

import pandas as pd
import pytest

from forge.config import ForgeConfig
from forge.models.bill import Bill
from forge.models.chamber import ChamberData
from forge.models.vote import Vote
from forge.pipeline.runner import _matrix_signature


@pytest.fixture
def inputs():
    """A minimal but complete set of matrix-stage inputs."""
    people = pd.DataFrame({
        "sponsor_id": [1, 2, 3, 4],
        "party_id": [0, 0, 1, 1],
        "name": [f"Member {i}" for i in range(4)],
    })
    vote = Vote(
        description="Read a third time and passed",
        yes_list=[1, 2], no_list=[3, 4], abstain_list=[],
    )
    bill = Bill(bill_id=1, bill_number="HB1", title="An act")
    bill.issue_category = 1
    bill.sponsors = [1]
    bill.passed_house = 1
    bill.complete = 1
    bill.house_data = ChamberData(chamber_votes=[vote], committee_votes=[])
    bill.house_data.competitive = 1
    return ForgeConfig(state_id="IN"), {1: bill}, people


def signature(config, bill_set, people, chamber="house"):
    return _matrix_signature(config, bill_set, people, chamber)


class TestStability:
    def test_identical_inputs_give_an_identical_signature(self, inputs):
        config, bill_set, people = inputs
        assert signature(config, bill_set, people) == signature(config, bill_set, people)

    def test_chambers_do_not_share_a_signature(self, inputs):
        config, bill_set, people = inputs
        assert signature(config, bill_set, people, "house") != signature(
            config, bill_set, people, "senate"
        )


class TestInvalidation:
    """Each test perturbs exactly one input the matrix stage reads."""

    def test_classifier_change_invalidates(self, inputs):
        """The whole reason Indiana's matrices move; must never be a hit."""
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        config.classifier = "legacy"
        assert signature(config, bill_set, people) != before

    def test_competitive_threshold_change_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        config.competitive_threshold = 0.9
        assert signature(config, bill_set, people) != before

    def test_reclassified_bill_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        bill_set[1].issue_category = 7
        assert signature(config, bill_set, people) != before

    def test_competitiveness_change_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        bill_set[1].house_data.competitive = 0
        assert signature(config, bill_set, people) != before

    def test_roster_change_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        people = people.iloc[:3]
        assert signature(config, bill_set, people) != before

    def test_sponsor_change_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        bill_set[1].sponsors = [1, 2]
        assert signature(config, bill_set, people) != before

    def test_vote_description_change_invalidates(self, inputs):
        """Descriptions decide passage, so an edited one changes the matrix."""
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        bill_set[1].house_data.chamber_votes[0].description = "Committee Do Pass"
        assert signature(config, bill_set, people) != before

    def test_changed_voter_lists_invalidate(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        bill_set[1].house_data.chamber_votes[0].yes_list = [1, 2, 3]
        assert signature(config, bill_set, people) != before

    def test_added_bill_invalidates(self, inputs):
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        extra = Bill(bill_id=2, bill_number="HB2", title="Another act")
        extra.issue_category = 1
        bill_set[2] = extra
        assert signature(config, bill_set, people) != before

    def test_passage_vocabulary_change_invalidates(self, inputs, monkeypatch):
        """Editing the vocabulary changes which votes enter every matrix.

        Nothing on disk changes when a term is added, so without folding the
        vocabulary digest into the key this would be a stale hit — the one
        invalidation case a file-based cache could not catch on its own.
        """
        config, bill_set, people = inputs
        before = signature(config, bill_set, people)
        monkeypatch.setattr("forge.pipeline.runner.PASSAGE_SIGNATURE", "different")
        assert signature(config, bill_set, people) != before


def test_signature_is_cheap_relative_to_what_it_guards(inputs):
    """It runs on every invocation, so it must not become the cost it avoids."""
    import time

    config, _bill_set, people = inputs
    many = {}
    for bill_id in range(2000):
        bill = Bill(bill_id=bill_id, bill_number=f"HB{bill_id}", title="An act")
        bill.issue_category = bill_id % 12
        bill.sponsors = [bill_id % 4 + 1]
        bill.house_data = ChamberData(
            chamber_votes=[Vote(
                description="Read a third time and passed",
                yes_list=[1, 2], no_list=[3, 4], abstain_list=[],
            )],
            committee_votes=[],
        )
        many[bill_id] = bill

    start = time.perf_counter()
    signature(config, many, people)
    elapsed = time.perf_counter() - start

    # Matrix building for a state of this size takes tens of seconds; a second
    # is a generous ceiling that still catches an accidental O(n^2).
    assert elapsed < 1.0, f"signature took {elapsed:.2f}s for 2000 bills"
