"""Which rollcall descriptions count as a final floor passage vote.

This lives in its own module because two independent subsystems need the same
answer: the matrix builder (``matrices.agreement``) decides which votes
contribute to legislator agreement, and the predictor (``predict.bayes``)
decides which vote a bill's outcome is read from. They previously carried
separate copies of the pattern, which silently drifted apart — New York and
Maine were recognised by the matrices and invisible to prediction, so those
states built agreement matrices that no prediction could ever use.

Keeping the definition here, importing nothing from either subsystem, is what
stops that recurring, and ``test_only_one_module_defines_the_passage_vocabulary``
enforces that no other module compiles a passage regex.

**The vocabulary is per state**, because it is per state in fact: ``ENACT-``
exists for Maine alone and ``ON PASSAGE`` for Congress alone. The earlier design
was a single global pattern, which worked only because every extension was
manually measured against all eleven states to prove it changed nothing
elsewhere. That ritual was a convention, and conventions are not enforced — an
unanchored ``BILL PASSED`` added for Ohio would have silently swept in 845
Montana *committee* motions, and only measurement caught it. Scoping terms to
the state that needs them makes the isolation structural instead.

The table is keyed by state here rather than folded into ``config.STATE_PROPERTIES``
so that this module keeps importing nothing: the single-definition property is
the thing that broke last time, and it is worth more than co-locating the two
state tables.
"""

from __future__ import annotations

import hashlib
import re
from functools import cache

#: Terms shared by every state. Both spell the same parliamentary step, and
#: between them they carry Indiana, Oregon, Wisconsin, Montana, California,
#: Vermont, Ohio and (barely) Congress.
SHARED_TERMS: tuple[str, ...] = (
    "THIRD",
    "3RD",
)

#: Terms a particular state needs *in addition* to the shared ones. Every entry
#: was added to fix a state producing empty or partial output, and each is
#: measured: the per-state matcher must reproduce the counts below exactly, which
#: ``tests/test_integration/test_passage_vocabulary.py`` asserts against the
#: committed LegiScan data.
#:
#: Resulting matched-rollcall counts, shared plus state-specific:
#:
#:     IN 3227   OR 2512   WI  856   NY 10127   ME  446
#:     VT  216   MT 4423   OH 2111   CA 16160   US  638
STATE_TERMS: dict[str, tuple[str, ...]] = {
    # All 10,127 New York rollcalls are "Senate/Assembly Floor Vote - Final
    # Passage"; none contains "third", so without this New York produced empty
    # matrices while the run exited successfully.
    "NY": ("FINAL PASSAGE",),

    # Maine's floor sequence is committee report -> passed to be engrossed ->
    # enacted, so its decisive floor vote is enactment rather than anything
    # named "passage". "ENACTMENT" and "ENACT-" are genuinely different strings
    # ("Enactment - Emer" against "Enact-emer 2/3 Elect").
    #
    # Two larger Maine families are deliberately excluded, on the authors'
    # instruction: committee-report acceptance (1,018 rollcalls, "Acc Maj OTP
    # Rep" and the ought-not-to-pass variants) and veto motions (632).
    #
    # Be precise about why, because the obvious reason is wrong. They are *not*
    # committee votes: median participation is 138 in a 154-seat House, so
    # `process_chamber_rollcalls` classifies all 1,018 as chamber votes. This
    # filter overrides that classifier rather than agreeing with it, in a
    # different currency — description text against participation count. The
    # actual judgement is narrower: a vote to accept a report, or to override a
    # veto, asks a different question than a vote on passage.
    "ME": ("FINAL PASSAGE", "ENACTMENT", "ENACT-", "TO BE ENGROSSED"),

    # Vermont's third-reading motion is only the procedural step that advances a
    # bill; "Shall the bill pass?" is the actual passage vote, and was excluded
    # until the authors chose to count both as sequential floor votes.
    "VT": ("SHALL THE BILL PASS",),

    # LegiScan records Ohio Senate passage as "Third Consideration" but House
    # passage as "House - Bill Passed (Vote)" / "House Passed" / "House
    # Favorable Passage", so the shared terms caught one chamber and missed the
    # other: 292 House rollcalls matched against 785 missed.
    #
    # These are anchored to a chamber prefix for a measured reason. An
    # unanchored "BILL PASSED" additionally matched 845 Montana committee
    # motions ("(H) Appropriations Committee Executive Action -- Bill Passed").
    "OH": (
        r"(?:HOUSE|SENATE)\s*-\s*BILL PASSED",
        r"(?:HOUSE|SENATE) FAVORABLE PASSAGE",
        r"(?:HOUSE|SENATE) PASSED\b",
    ),

    # Congress phrases it "On Passage", which no other state uses and which the
    # shared terms miss entirely: without this, US drops from 638 matches to 1.
    "US": ("ON PASSAGE",),
}


def _compile(terms: tuple[str, ...]) -> re.Pattern[str]:
    """Compile an alternation over ``terms``, non-capturing and case-insensitive.

    The group is non-capturing because only match/no-match is ever read, and the
    terms are already regex fragments — Ohio's are deliberately anchored — so
    they are not escaped.
    """
    return re.compile("(?:" + "|".join(terms) + ")", re.IGNORECASE)


@cache
def passage_pattern(state_id: str | None = None) -> re.Pattern[str]:
    """Return the compiled passage pattern for a state.

    Args:
        state_id: Two-letter state code. ``None`` returns the union of every
            state's vocabulary, which is what a caller that does not know its
            state gets; it is the pre-per-state behaviour and is strictly more
            permissive, so it can only over-match, never under-match.

    Returns:
        A compiled, case-insensitive pattern.
    """
    if state_id is None:
        every = SHARED_TERMS + tuple(
            term for terms in STATE_TERMS.values() for term in terms
        )
        return _compile(tuple(dict.fromkeys(every)))

    extra = STATE_TERMS.get(state_id.upper(), ())
    return _compile(tuple(dict.fromkeys(SHARED_TERMS + extra)))


def is_passage_description(description: object, state_id: str | None = None) -> bool:
    """Return whether a rollcall description names a final floor passage vote.

    Handles the two shapes a description arrives in. LegiScan normally supplies
    a string, but a rollcall assembled from multiple source rows can carry a
    list of them, in which case they are joined before matching. Missing
    descriptions are common in the raw data and are simply not passage votes.

    Args:
        description: A rollcall description — a string, a list of strings, or
            None.
        state_id: Two-letter state code. Passing it restricts matching to that
            state's vocabulary; omitting it matches against every state's, which
            is the safe default for callers that lack the context.

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
    return passage_pattern(state_id).search(description) is not None


def _signature() -> str:
    """Digest the whole vocabulary table.

    Cached matrices are only reusable while the vocabulary that produced them is
    unchanged, and editing a term here changes which votes enter every matrix
    without touching any file the cache would otherwise notice. Folding this
    digest into the cache key makes such an edit a cache miss rather than a
    silently stale hit.
    """
    digest = hashlib.sha256()
    digest.update("|".join(SHARED_TERMS).encode())
    for state in sorted(STATE_TERMS):
        digest.update(f"|{state}={'|'.join(STATE_TERMS[state])}".encode())
    return digest.hexdigest()[:16]


#: Short digest of the vocabulary, for cache invalidation. See ``_signature``.
PASSAGE_SIGNATURE = _signature()
