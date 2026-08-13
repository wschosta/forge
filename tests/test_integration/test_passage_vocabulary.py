"""Guard the passage-vote description match against per-state vocabulary drift.

A bill whose rollcalls do not match ``_PASSAGE_PATTERN`` is skipped without
comment, so a state whose LegiScan phrasing is unrecognised produces empty
matrices while the run reports success. That failure mode is invisible to the
golden comparisons, which only cover the three states whose vocabulary already
matched.

These tests read the committed LegiScan rollcalls directly, so they assert
against real phrasing rather than fixtures invented to fit the pattern.
"""

from __future__ import annotations

import pytest

from forge.ingest.csv_reader import read_all_csv
from forge.matrices.agreement import _PASSAGE_PATTERN

#: States whose rollcall descriptions must yield at least this many passage
#: matches. The floors are set well below the measured counts so ordinary data
#: refreshes do not trip them, while a pattern change that drops a whole
#: state's vocabulary does.
MINIMUM_MATCHES = {
    "IN": 3000,   # measured 3227 — "Read a third time"
    "OR": 2400,   # measured 2512 — "House/Senate Third Reading"
    "WI": 800,    # measured  856 — "Read a third time and passed"
    "NY": 9000,   # measured 10127 — "Floor Vote - Final Passage"
    "MT": 4000,   # measured 4423
    "OH": 900,    # measured  968
    "CA": 15000,  # measured 16160
    "US": 600,    # measured  638
    "VT": 100,    # measured  135
    "ME": 400,    # measured  446 — enactment + engrossment, see below
}

#: Phrasings drawn verbatim from the committed data, one per distinct style.
REAL_DESCRIPTIONS = [
    ("Assembly: Read a third time and passed", True),
    ("Senate: Read a third time and concurred in", True),
    ("House Third Reading", True),
    ("Senate Floor Vote - Final Passage", True),
    ("Assembly Floor Vote - Final Passage", True),
    ("Enactment", True),
    ("Enactment - Emer", True),
    ("Enact-emer 2/3 Elect", True),
    ("Passage To Be Engrossed", True),
    ("Pass To Be Engrossed As Amend", True),
    ("House Committee Do Pass", False),
    ("Senate Committee Do pass as amended", False),
    # Maine committee-report and veto motions stay out: the first are committee
    # votes, which are excluded for every other state, and the second measure
    # override rather than passage.
    ("Acc Maj Ought Not To Pass Rep RC #30", False),
    ("Acc Maj Otp As Amended Rep RC #119", False),
    ("Accept Min Ontp Rpt RC #106", False),
    ("Veto Override (2/3) RC #12", False),
    ("Reconsideration - Veto RC #398", False),
]


@pytest.mark.parametrize(("description", "expected"), REAL_DESCRIPTIONS)
def test_pattern_classifies_real_descriptions(description: str, expected: bool) -> None:
    """The pattern accepts floor passage votes and rejects committee motions.

    The committee cases matter as much as the passage ones: broadening the
    pattern to a bare ``PASSAGE`` would sweep in "Do Pass" committee motions and
    silently change results for states that currently reproduce MATLAB exactly.
    """
    assert bool(_PASSAGE_PATTERN.search(description.upper())) is expected


@pytest.mark.parametrize("state", sorted(MINIMUM_MATCHES))
def test_state_vocabulary_is_recognised(state: str) -> None:
    """Every state with committed data yields passage votes.

    A zero here means the pipeline will emit empty matrices for that state while
    exiting successfully — the exact failure this module exists to catch.
    """
    rollcalls = read_all_csv("rollcalls", state, "legiscan_data")
    descriptions = rollcalls["description"].dropna().astype(str)

    matches = sum(bool(_PASSAGE_PATTERN.search(d.upper())) for d in descriptions)

    assert matches >= MINIMUM_MATCHES[state], (
        f"{state}: only {matches} of {len(descriptions)} rollcalls match the "
        f"passage pattern (expected at least {MINIMUM_MATCHES[state]}). "
        f"A collapse to zero means every matrix for {state} will be empty."
    )


def test_maine_excludes_committee_reports_and_vetoes() -> None:
    """Maine's scope decision is pinned, because it is a judgement not a fact.

    Maine's floor sequence is committee report → passed to be engrossed →
    enacted, so enactment is its decisive floor vote. Two large families are
    deliberately left out and this test is what stops them drifting back in:

    * committee-report acceptance (~907 rollcalls) — substantively decisive in
      Maine, since accepting an ought-not-to-pass report kills the bill, but
      they are committee votes and every other state excludes those;
    * veto overrides (~620) — a different question than passage.

    Together those are more rollcalls than the passage votes themselves, so
    admitting them by accident would quietly change what Maine's matrices mean.
    """
    rollcalls = read_all_csv("rollcalls", "ME", "legiscan_data")
    descriptions = rollcalls["description"].dropna().astype(str)

    def matched(pattern: str) -> int:
        hits = descriptions[descriptions.str.upper().str.contains(pattern, regex=True)]
        return sum(bool(_PASSAGE_PATTERN.search(d.upper())) for d in hits)

    assert matched(r"OUGHT NOT TO PASS|ONTP") == 0, (
        "Maine ought-not-to-pass committee reports are now being counted as "
        "passage votes. These are committee votes; including them makes Maine "
        "incomparable to the other ten states."
    )
    assert matched(r"\bOTP\b|OTP-A") == 0, (
        "Maine ought-to-pass committee reports are now being counted as passage "
        "votes. See above — committee reports are excluded by design."
    )
    assert matched(r"VETO") == 0, (
        "Maine veto motions are now being counted as passage votes. A veto "
        "override measures a different question than passage."
    )
