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
}

#: Phrasings drawn verbatim from the committed data, one per distinct style.
REAL_DESCRIPTIONS = [
    ("Assembly: Read a third time and passed", True),
    ("Senate: Read a third time and concurred in", True),
    ("House Third Reading", True),
    ("Senate Floor Vote - Final Passage", True),
    ("Assembly Floor Vote - Final Passage", True),
    ("House Committee Do Pass", False),
    ("Senate Committee Do pass as amended", False),
    ("Acc Maj Ought Not To Pass Rep RC #30", False),
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


def test_maine_vocabulary_remains_largely_unrecognised() -> None:
    """Maine is a known gap, recorded here so it is not mistaken for working.

    Maine records passage through parliamentary abbreviations — "Acc Maj OTP
    Rep" for accepting a majority ought-to-pass report — which the pattern does
    not model. It yields a small number of matches, enough to produce non-empty
    output, which makes the gap easy to miss. Deciding which Maine motions
    constitute the passage vote is a domain judgement for the authors; this test
    documents the status quo and will fail if someone changes it, prompting the
    floor above to be updated deliberately.
    """
    rollcalls = read_all_csv("rollcalls", "ME", "legiscan_data")
    descriptions = rollcalls["description"].dropna().astype(str)

    matches = sum(bool(_PASSAGE_PATTERN.search(d.upper())) for d in descriptions)

    assert 0 < matches < 0.1 * len(descriptions), (
        f"Maine now matches {matches} of {len(descriptions)} rollcalls. If the "
        f"vocabulary was deliberately extended, update this test and regenerate "
        f"Maine's baseline outputs."
    )
