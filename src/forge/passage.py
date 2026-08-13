"""Which rollcall descriptions count as a final floor passage vote.

This lives in its own module because two independent subsystems need the same
answer: the matrix builder (``matrices.agreement``) decides which votes
contribute to legislator agreement, and the predictor (``predict.bayes``)
decides which vote a bill's outcome is read from. They previously carried
separate copies of the pattern, which silently drifted apart — New York and
Maine were recognised by the matrices and invisible to prediction, so those
states built agreement matrices that no prediction could ever use.

Keeping the definition here, importing nothing from either subsystem, is what
stops that recurring.
"""

from __future__ import annotations

import re

#: Rollcall descriptions that identify a final floor passage vote.
#:
#: MATLAB matched ``THIRD|3RD|ON PASSAGE``, which is the vocabulary LegiScan
#: uses for Wisconsin, Oregon and Indiana ("Read a third time", "Third
#: Reading"). Other states describe the same event differently, and because a
#: bill with no matching rollcall is skipped silently, a state whose phrasing is
#: unrecognised produces empty matrices while reporting success. New York was
#: the clearest case: all 10,127 of its rollcalls are "Senate/Assembly Floor
#: Vote - Final Passage", and every one was discarded because the pattern
#: required the literal "ON PASSAGE".
#:
#: ``FINAL PASSAGE`` is added rather than relaxing the term to a bare
#: ``PASSAGE``. The bare form was measured and would additionally match motions
#: in Oregon (+124), Ohio (+446), California (+574) and Congress (+3) — changing
#: results for states that currently reproduce MATLAB exactly.
#:
#: ``ENACTMENT``, ``ENACT-`` and ``TO BE ENGROSSED`` cover Maine, whose floor
#: sequence is committee report → passed to be engrossed → enacted, so its
#: decisive floor vote is enactment rather than anything called "passage". This
#: takes Maine from 84 matched rollcalls to 446.
#:
#: Two large Maine families are deliberately excluded, on the authors'
#: instruction:
#:
#: * **Committee-report acceptance** (1,018 rollcalls) — "Acc Maj OTP Rep" and
#:   the ought-not-to-pass variants. Accepting an ONTP report is what actually
#:   kills a Maine bill, so these are substantively decisive.
#: * **Veto motions** (632) — "Veto Override (2/3)", "Reconsideration - Veto".
#:   An override measures a different question than passage.
#:
#: Be precise about *why* these are excluded, because the obvious reason is
#: wrong. They are **not** committee votes: their median participation is 138
#: in a 154-seat House, so ``process_chamber_rollcalls`` classifies all 1,018 of
#: them as chamber votes under the 0.75 threshold. This filter therefore
#: overrides that classifier rather than agreeing with it, and it does so in a
#: different currency — description text against participation count.
#:
#: The actual judgement is narrower: a vote to *accept a report*, or to override
#: a veto, asks a different question than a vote on passage. Anyone reconciling
#: these two layers should know they genuinely disagree here, and that the
#: disagreement is deliberate.
#:
#: Every extension so far has been verified state-isolated by measurement: match
#: counts must be unchanged for every state other than the one being fixed.
#: ``tests/test_integration/test_passage_vocabulary.py`` enforces that, and
#: ``CLAUDE.md`` records the coverage audit — including Ohio and Vermont, which
#: are still under-covered and awaiting a scope decision.
#: Every alternative below is load-bearing — dropping any one was measured:
#: ``ON PASSAGE`` alone carries Congress (638 → 1), ``FINAL PASSAGE`` carries
#: New York (10,127 → 0), and ``ENACTMENT``/``ENACT-``/``TO BE ENGROSSED``
#: carry distinct Maine strings ("Enactment - Emer" against "Enact-emer 2/3
#: Elect"). The group is non-capturing because only match/no-match is ever read.
PASSAGE_PATTERN = re.compile(
    r"(?:THIRD|3RD|ON PASSAGE|FINAL PASSAGE|ENACTMENT|ENACT-|TO BE ENGROSSED)",
    re.IGNORECASE,
)


def is_passage_description(description: object) -> bool:
    """Return whether a rollcall description names a final floor passage vote.

    Handles the two shapes a description arrives in. LegiScan normally supplies
    a string, but a rollcall assembled from multiple source rows can carry a
    list of them, in which case they are joined before matching. Missing
    descriptions are common in the raw data and are simply not passage votes.

    Args:
        description: A rollcall description — a string, a list of strings, or
            None.

    Returns:
        True if the description names a passage vote.
    """
    if description is None:
        return False
    if isinstance(description, list):
        description = " ".join(str(part) for part in description)
    elif not isinstance(description, str):
        description = str(description)
    if not description:
        return False
    return PASSAGE_PATTERN.search(description) is not None
