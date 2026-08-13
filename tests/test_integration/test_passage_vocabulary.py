"""Guard the passage-vote description match against per-state vocabulary drift.

A bill whose rollcalls are not recognised as passage votes is skipped without
comment, so a state whose LegiScan phrasing is unrecognised produces empty
matrices while the run reports success. That failure mode is invisible to the
golden comparisons, which only cover the three states whose vocabulary already
matched.

These tests read the committed LegiScan rollcalls directly, so they assert
against real phrasing rather than fixtures invented to fit the pattern.

The rationale for each alternative — and for what is deliberately excluded —
lives in ``forge.passage``; this module enforces it.
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd
import pytest

import forge
from forge.ingest.csv_reader import read_all_csv
from forge.passage import is_passage_description

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

#: Phrasings drawn verbatim from the committed data, one per pattern branch.
#: Broader corpus-level assertions live in the tests below; these name the
#: vocabulary so a reader can see what each branch is for.
REAL_DESCRIPTIONS = [
    ("Assembly: Read a third time and passed", True),
    ("House Third Reading", True),
    ("Senate Floor Vote - Final Passage", True),
    ("On Passage", True),
    ("Enactment", True),
    ("Enact-emer 2/3 Elect", True),
    ("Passage To Be Engrossed", True),
    # Committee motions must stay out for every state: broadening the pattern to
    # a bare PASSAGE would sweep in "Do Pass" and silently change results for
    # the states that currently reproduce MATLAB exactly.
    ("House Committee Do Pass", False),
    ("Senate Committee Do pass as amended", False),
]


def _descriptions(state: str) -> pd.Series:
    """Return every non-null rollcall description for a state, as strings."""
    rollcalls = read_all_csv("rollcalls", state, "legiscan_data")
    return rollcalls["description"].dropna().astype(str)


def test_only_one_module_defines_the_passage_vocabulary() -> None:
    """No subsystem may carry its own copy of the pattern.

    This is the guard that was missing. The matrix builder and the predictor
    each held a private ``_PASSAGE_PATTERN``; when the matrix copy gained
    ``FINAL PASSAGE`` and later Maine's terms, the predictor's copy did not
    follow. New York and Maine then built agreement matrices that no prediction
    or Elo run could consume, and every existing test stayed green because they
    all imported the matrix copy.

    A design whose correctness depends on there being exactly one definition
    needs something that actually checks there is exactly one.
    """
    source_root = Path(forge.__file__).parent
    offenders = [
        path.relative_to(source_root)
        for path in source_root.rglob("*.py")
        if path.name != "passage.py" and re.search(
            r"re\.compile\([^)]*(?:THIRD|3RD|PASSAGE|ENACT)", path.read_text(), re.IGNORECASE
        )
    ]

    assert not offenders, (
        f"these modules compile their own passage pattern instead of importing "
        f"from forge.passage: {offenders}. Two definitions drift apart silently "
        f"— that is exactly how New York and Maine broke."
    )


@pytest.mark.parametrize(("description", "expected"), REAL_DESCRIPTIONS)
def test_pattern_classifies_real_descriptions(description: str, expected: bool) -> None:
    """Each pattern branch accepts its own vocabulary and rejects committee motions."""
    assert is_passage_description(description) is expected


@pytest.mark.parametrize("state", sorted(MINIMUM_MATCHES))
def test_state_vocabulary_is_recognised(state: str) -> None:
    """Every state with committed data yields passage votes.

    A zero here means the pipeline will emit empty matrices for that state while
    exiting successfully — the exact failure this module exists to catch.
    """
    descriptions = _descriptions(state)

    matches = sum(is_passage_description(d) for d in descriptions)

    assert matches >= MINIMUM_MATCHES[state], (
        f"{state}: only {matches} of {len(descriptions)} rollcalls match the "
        f"passage pattern (expected at least {MINIMUM_MATCHES[state]}). "
        f"A collapse to zero means every matrix for {state} will be empty."
    )


def test_maine_excludes_committee_reports_and_vetoes() -> None:
    """Maine's scope decision is pinned, because it is a judgement not a fact.

    Maine's floor sequence is committee report → passed to be engrossed →
    enacted, so enactment is its decisive floor vote. Two large families are
    deliberately left out — 1,650 rollcalls between them, more than the 446
    passage votes themselves — so admitting them by accident would quietly
    change what Maine's matrices mean.

    Note what the exclusion is *not*. These are not committee votes: their
    median participation is 138 in a 154-seat House, so the chamber/committee
    classifier counts every one as a chamber vote. The judgement is narrower —
    a vote to accept a report, or to override a veto, asks a different question
    than a vote on passage. See ``forge.passage``.
    """
    descriptions = _descriptions("ME")

    def matched(pattern: str) -> int:
        return sum(
            1
            for d in descriptions
            if re.search(pattern, d, re.IGNORECASE) and is_passage_description(d)
        )

    assert matched(r"OUGHT NOT TO PASS|ONTP") == 0, (
        "Maine ought-not-to-pass report motions are now counted as passage "
        "votes. Accepting an ONTP report kills the bill, but it asks a "
        "different question than passage."
    )
    assert matched(r"\bOTP\b|OTP-A") == 0, (
        "Maine ought-to-pass report motions are now counted as passage votes. "
        "See above — report acceptance is excluded by design."
    )
    assert matched(r"VETO") == 0, (
        "Maine veto motions are now counted as passage votes. An override "
        "measures a different question than passage."
    )
