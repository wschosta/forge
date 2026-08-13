"""Checkpoint/resume must be exact, not approximate.

A resumable long run is only useful if resuming produces the same answer as
running straight through. These tests interrupt a run and compare the resumed
result against an uninterrupted one element by element, so "it survived a
restart" is never mistaken for "it survived a restart and is still correct".
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.checkpoint import CHECKPOINT_FORMAT, Checkpoint
from forge.config import ForgeConfig
from forge.elo.monte_carlo import elo_monte_carlo
from forge.models.bill import Bill
from forge.models.chamber import ChamberData
from forge.models.vote import Vote
from forge.predict.monte_carlo import run_monte_carlo


class TestCheckpointStore:
    """The store itself: durability and refusal to misread."""

    def test_round_trips_a_value(self, tmp_path):
        store = Checkpoint(tmp_path)
        store.save("a", {"x": np.arange(3)})
        assert store.load("a")["x"].tolist() == [0, 1, 2]

    def test_disabled_store_is_a_no_op(self):
        store = Checkpoint(None)
        assert not store.enabled
        store.save("a", 1)
        assert store.load("a") is None
        assert store.keys() == []

    def test_missing_key_is_none(self, tmp_path):
        assert Checkpoint(tmp_path).load("nope") is None

    def test_truncated_file_is_ignored_rather_than_raising(self, tmp_path):
        """A process killed mid-write must not poison the next run."""
        store = Checkpoint(tmp_path)
        store.save("a", {"x": 1})
        (tmp_path / "a.pkl").write_bytes(b"\x80\x04\x95truncated")
        assert store.load("a") is None

    def test_stale_format_is_ignored(self, tmp_path):
        """Resuming from a different payload shape would corrupt results."""
        import pickle

        with (tmp_path / "a.pkl").open("wb") as handle:
            pickle.dump({"format": CHECKPOINT_FORMAT - 1, "value": {"x": 1}}, handle)
        assert Checkpoint(tmp_path).load("a") is None

    def test_save_is_atomic_leaving_no_partial_file(self, tmp_path):
        store = Checkpoint(tmp_path)
        store.save("a", {"x": list(range(1000))})
        assert not list(tmp_path.glob("*.tmp"))
        assert store.keys() == ["a"]

    def test_clear_removes_everything(self, tmp_path):
        store = Checkpoint(tmp_path)
        store.save("a", 1)
        store.save("b", 2)
        store.clear()
        assert store.keys() == []

    def test_key_cannot_escape_the_directory(self, tmp_path):
        store = Checkpoint(tmp_path / "inner")
        store.save("../escape", 1)
        assert not (tmp_path / "escape.pkl").exists()
        assert store.load("../escape") == 1


#: Matches ForgeConfig(state_id="IN").house_size. The Elo category filter
#: discards any bill whose passage vote drew fewer than half the chamber, so a
#: fixture smaller than the configured chamber is silently filtered out
#: entirely — which makes tests pass vacuously rather than fail loudly.
CHAMBER_SIZE = 100


@pytest.fixture
def tiny_chamber():
    """A full-size chamber with three competitive bills.

    Sized to the Indiana House because that is what ``ForgeConfig`` reports; it
    still runs in milliseconds at these bill and iteration counts.
    """
    ids = [f"id{i}" for i in range(CHAMBER_SIZE)]
    half = CHAMBER_SIZE // 2
    people = pd.DataFrame({
        "sponsor_id": list(range(CHAMBER_SIZE)),
        "party_id": [0] * half + [1] * (CHAMBER_SIZE - half),
        "name": [f"Member {i}" for i in range(CHAMBER_SIZE)],
    })

    rng = np.random.default_rng(7)
    raw = rng.uniform(0.3, 0.9, size=(CHAMBER_SIZE, CHAMBER_SIZE))
    symmetric = (raw + raw.T) / 2
    np.fill_diagonal(symmetric, 1.0)
    agreement = pd.DataFrame(symmetric, index=ids, columns=ids)
    sponsor = agreement.copy()

    bill_set = {}
    for n, bid in enumerate((101, 102, 103)):
        # Vary the split per bill so the three are not interchangeable.
        cut = half + (n - 1) * 5
        yes = list(range(cut))
        no = [i for i in range(CHAMBER_SIZE) if i not in set(yes)]
        vote = Vote(
            description="Read a third time and passed",
            yes_list=yes, no_list=no, abstain_list=[],
        )
        bill = Bill(bill_id=bid, bill_number=f"HB{bid}", title="An act")
        bill.issue_category = 1
        bill.sponsors = [n]
        bill.passed_house = 1
        bill.complete = 1  # required by the Elo category filter
        bill.house_data = ChamberData(chamber_votes=[vote], committee_votes=[])
        bill.house_data.competitive = 1
        bill_set[bid] = bill

    return {"ids": [101, 102, 103], "bill_set": bill_set, "people": people,
            "agreement": agreement, "sponsor": sponsor}


def _run_mc(tiny, checkpoint=None, bill_ids=None):
    return run_monte_carlo(
        bill_ids if bill_ids is not None else tiny["ids"],
        tiny["bill_set"], tiny["people"], tiny["sponsor"], tiny["agreement"],
        "house", CHAMBER_SIZE, monte_carlo_number=5, checkpoint=checkpoint,
    )


class TestMonteCarloResume:
    def test_resumed_run_matches_an_uninterrupted_one(self, tiny_chamber, tmp_path):
        """The claim the whole feature rests on."""
        reference = _run_mc(tiny_chamber)

        # Interrupt: process only the first bill, then resume with all three.
        store = Checkpoint(tmp_path)
        _run_mc(tiny_chamber, checkpoint=store, bill_ids=tiny_chamber["ids"][:1])
        assert len(store.keys()) == 1, "the partial run should have banked one bill"

        resumed = _run_mc(tiny_chamber, checkpoint=store)

        assert resumed["bill_ids"] == reference["bill_ids"]
        np.testing.assert_array_equal(resumed["accuracy_list"], reference["accuracy_list"])
        np.testing.assert_array_equal(resumed["accuracy_delta"], reference["accuracy_delta"])
        assert resumed["legislators_list"] == reference["legislators_list"]

    def test_second_run_recomputes_nothing(self, tiny_chamber, tmp_path):
        """A fully checkpointed run must not re-enter the expensive path."""
        store = Checkpoint(tmp_path)
        _run_mc(tiny_chamber, checkpoint=store)

        import forge.predict.monte_carlo as mc

        calls = []
        original = mc.predict_outcomes
        mc.predict_outcomes = lambda *a, **k: calls.append(1) or original(*a, **k)
        try:
            _run_mc(tiny_chamber, checkpoint=store)
        finally:
            mc.predict_outcomes = original

        assert calls == [], "every bill should have come from the checkpoint"

    def test_without_a_checkpoint_nothing_is_written(self, tiny_chamber, tmp_path):
        _run_mc(tiny_chamber, checkpoint=Checkpoint(None))
        assert list(tmp_path.iterdir()) == []


class TestEloResume:
    def _config(self, iterations):
        return ForgeConfig(state_id="IN", elo_monte_carlo_number=iterations)

    def _run(self, tiny, config, checkpoint=None, every=1):
        return elo_monte_carlo(
            tiny["ids"], tiny["bill_set"], [1], tiny["people"],
            tiny["sponsor"], tiny["agreement"], "house", config,
            checkpoint=checkpoint, checkpoint_every=every,
        )

    def test_resumed_run_matches_an_uninterrupted_one(self, tiny_chamber, tmp_path):
        """Iteration j is seeded with j+1, so partial sums must carry exactly."""
        reference = self._run(tiny_chamber, self._config(6))

        # Genuinely interrupt the run: blow up partway through iteration 3, the
        # way a killed process would, leaving whatever the checkpoint had banked.
        import forge.elo.monte_carlo as elo_mc

        original = elo_mc.elo_prediction
        calls = {"n": 0}

        def explode_after_two(*args, **kwargs):
            if calls["n"] >= 2:
                raise KeyboardInterrupt("simulated kill")
            calls["n"] += 1
            return original(*args, **kwargs)

        store = Checkpoint(tmp_path)
        elo_mc.elo_prediction = explode_after_two
        try:
            with pytest.raises(KeyboardInterrupt):
                self._run(tiny_chamber, self._config(6), checkpoint=store, every=1)
        finally:
            elo_mc.elo_prediction = original

        state = store.load("elo_house_m6_cat1")
        assert state is not None, "the interrupted run should have banked progress"
        assert state["completed"] == 2, "it should have banked exactly the finished iterations"

        resumed = self._run(tiny_chamber, self._config(6), checkpoint=store, every=1)

        assert set(resumed) == set(reference)
        for cat, frame in reference.items():
            pd.testing.assert_frame_equal(resumed[cat], frame)

    def test_completed_categories_are_not_recomputed(self, tiny_chamber, tmp_path):
        store = Checkpoint(tmp_path)
        first = self._run(tiny_chamber, self._config(4), checkpoint=store, every=1)

        # Guard against the vacuous pass: if the category filter rejected every
        # bill, the loop never runs and "nothing was recomputed" is trivially
        # true. Assert the first run actually did the work.
        assert first, "the first run must produce results for this test to mean anything"
        state = store.load("elo_house_m4_cat1")
        assert state is not None and state["completed"] == 4

        import forge.elo.monte_carlo as elo_mc

        calls = []
        original = elo_mc.elo_prediction
        elo_mc.elo_prediction = lambda *a, **k: calls.append(1) or original(*a, **k)
        try:
            second = self._run(tiny_chamber, self._config(4), checkpoint=store, every=1)
        finally:
            elo_mc.elo_prediction = original

        assert calls == [], "a completed category should replay from the checkpoint"
        for cat, frame in first.items():
            pd.testing.assert_frame_equal(second[cat], frame)
