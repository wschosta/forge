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
from forge.passage import STATE_TERMS, is_passage_description

#: Exact matched-rollcall counts per state. Unlike the floors below these are
#: equalities, because they are what proves the per-state vocabulary is a
#: refactor and not a change: every count here is what the previous single
#: global pattern produced.
EXACT_MATCHES = {
    "IN": 3227, "OR": 2512, "WI": 856, "NY": 10127, "ME": 446,
    "VT": 216, "MT": 4423, "OH": 2111, "CA": 16160, "US": 638,
}

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
    "OH": 2000,   # measured 2111 — "Third Consideration" plus House passage
    "CA": 15000,  # measured 16160
    "US": 600,    # measured  638
    "VT": 200,    # measured  216 — third reading plus "Shall the bill pass?"
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
    ("House Favorable Passage", True),
    ("House - Bill Passed (Vote)", True),
    ("Senate Passed", True),
    ("Shall the bill pass?", True),
    ("Shall the bill pass in concurrence with proposal of amendment?", True),
    # Committee motions must stay out for every state: broadening the pattern to
    # a bare PASSAGE would sweep in "Do Pass" and silently change results for
    # the states that currently reproduce MATLAB exactly.
    ("House Committee Do Pass", False),
    ("Senate Committee Do pass as amended", False),
    # Ohio's terms are anchored to a chamber prefix precisely so this Montana
    # committee motion cannot match. An unanchored "BILL PASSED" swept in 845 of
    # these.
    ("(H) Appropriations Committee Executive Action -- Bill Passed", False),
    ("(H) Judiciary Committee Executive Action--Bill Passed as Amended", False),
]


def _descriptions(state: str) -> pd.Series:
    """Return every non-null rollcall description for a state, as strings."""
    rollcalls = read_all_csv("rollcalls", state, "legiscan_data")
    return rollcalls["description"].dropna().astype(str)


@pytest.mark.parametrize("state", sorted(EXACT_MATCHES))
def test_state_vocabulary_matches_exactly_what_the_global_pattern_did(state: str) -> None:
    """Scoping terms per state must not change any state's result.

    This is the property that makes the per-state table a refactor rather than a
    scientific change. Each count is what the previous single global pattern
    produced; if scoping Ohio's terms to Ohio quietly cost some other state a
    vote, or cost Ohio one, it shows up here as an inequality rather than as a
    silently different matrix months later.
    """
    matches = sum(is_passage_description(d, state) for d in _descriptions(state))

    assert matches == EXACT_MATCHES[state], (
        f"{state}: per-state matching yields {matches}, but the global pattern "
        f"yielded {EXACT_MATCHES[state]}. The per-state split was supposed to be "
        f"result-neutral."
    )


@pytest.mark.parametrize("state", sorted(EXACT_MATCHES))
def test_restricting_to_one_state_never_loses_a_match(state: str) -> None:
    """A state's own vocabulary must find everything the union finds, for it.

    The union of every state's terms is strictly more permissive, so it can only
    ever match more. Equality here is what says the extra terms in the union are
    genuinely irrelevant to this state — i.e. that no state is quietly relying on
    another's vocabulary.
    """
    descriptions = _descriptions(state)
    scoped = sum(is_passage_description(d, state) for d in descriptions)
    union = sum(is_passage_description(d) for d in descriptions)

    assert scoped == union, (
        f"{state}: scoped matching found {scoped} but the union found {union}. "
        f"{state} is relying on another state's terms, which means the table "
        f"assigns them to the wrong state."
    )


def test_every_state_specific_term_is_used_by_its_state() -> None:
    """A term scoped to a state must actually match something there.

    A term that matches nothing is either misspelled or left over from a
    vocabulary that has since changed, and in both cases it is misleading — it
    documents a phrasing the state does not use.
    """
    unused: list[str] = []
    for state, terms in STATE_TERMS.items():
        if state not in EXACT_MATCHES:
            continue  # no committed rollcall data to check against
        descriptions = _descriptions(state)
        for term in terms:
            pattern = re.compile(term, re.IGNORECASE)
            if not any(pattern.search(d) for d in descriptions):
                unused.append(f"{state}:{term}")

    assert not unused, f"these state-specific terms match nothing in their state: {unused}"


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
