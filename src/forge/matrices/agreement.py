"""Agreement matrix builder — replaces processChamberVotes.m, addVotes, cleanVotes, normalizeVotes.

Builds NxN legislator agreement matrices from rollcall votes, sponsorship data,
and party membership. Handles cleaning, normalization, and party-based sub-matrix extraction.
"""

from __future__ import annotations

import logging
import math
import re
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from forge.config import create_id_strings, cstr_ainbp

logger = logging.getLogger(__name__)


@dataclass
class MatrixResults:
    """All matrices produced by process_chamber_votes for one chamber + category."""

    chamber_matrix: pd.DataFrame | None = None
    chamber_votes: pd.DataFrame | None = None
    chamber_sponsor_matrix: pd.DataFrame | None = None
    chamber_sponsor_votes: pd.DataFrame | None = None
    committee_matrix: pd.DataFrame | None = None
    committee_votes: pd.DataFrame | None = None
    committee_sponsor_matrix: pd.DataFrame | None = None
    committee_sponsor_votes: pd.DataFrame | None = None
    consistency_matrix: pd.DataFrame | None = None
    bill_ids: list[int] = field(default_factory=list)
    republicans_chamber_votes: pd.DataFrame | None = None
    democrats_chamber_votes: pd.DataFrame | None = None
    republicans_chamber_sponsor: pd.DataFrame | None = None
    democrats_chamber_sponsor: pd.DataFrame | None = None
    republicans_committee_votes: pd.DataFrame | None = None
    democrats_committee_votes: pd.DataFrame | None = None
    republicans_committee_sponsor: pd.DataFrame | None = None
    democrats_committee_sponsor: pd.DataFrame | None = None
    seat_matrix: pd.DataFrame | None = None


def _create_nan_table(ids: list[str]) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Create a pair of NaN-initialized square DataFrames with given row/column names.

    Replaces util.createTable(ids, ids, 'NaN').
    """
    n = len(ids)
    data = np.full((n, n), np.nan)
    matrix = pd.DataFrame(data, index=ids, columns=ids)
    votes = pd.DataFrame(data.copy(), index=ids, columns=ids)
    return matrix, votes


def _create_zero_table(ids: list[str], columns: list[str]) -> pd.DataFrame:
    """Create a zero-initialized DataFrame.

    Replaces util.createTable(ids, cols, 'zero').
    """
    data = np.zeros((len(ids), len(columns)))
    return pd.DataFrame(data, index=ids, columns=columns)


def add_votes(
    vote_matrix: pd.DataFrame,
    row_ids: list[str],
    column_ids: list[str],
    value: float = 1.0,
) -> pd.DataFrame:
    """Add votes to the agreement matrix.

    Replaces forge.addVotes(). For each cell (row, col):
    - If NaN, sets it to ``value``
    - If not NaN, adds ``value`` to the existing value

    Args:
        vote_matrix: The NxN matrix to update.
        row_ids: Row labels to update.
        column_ids: Column labels to update.
        value: Value to add (1 for agreement, 0 for disagreement).

    Returns:
        Updated vote_matrix (modified in-place and returned).
    """
    if not row_ids or not column_ids:
        return vote_matrix

    # Filter to IDs that actually exist in the matrix
    valid_rows = [r for r in row_ids if r in vote_matrix.index]
    valid_cols = [c for c in column_ids if c in vote_matrix.columns]

    if not valid_rows or not valid_cols:
        return vote_matrix

    # Get the sub-matrix (copy to avoid read-only issues)
    sub = vote_matrix.loc[valid_rows, valid_cols].values.copy()
    mask_nan = np.isnan(sub)

    # Where NaN, set to value; where not NaN, add value
    sub[mask_nan] = value
    sub[~mask_nan] += value

    vote_matrix.loc[valid_rows, valid_cols] = sub
    return vote_matrix


def clean_votes(
    people_matrix: pd.DataFrame,
    possible_votes: pd.DataFrame,
    show_warnings: bool = False,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Remove legislators with all-NaN rows/columns.

    Replaces forge.cleanVotes().

    Args:
        people_matrix: Agreement (or sponsor) matrix.
        possible_votes: Corresponding vote-count matrix.
        show_warnings: If True, log warnings for removed legislators.

    Returns:
        Tuple of (cleaned_matrix, cleaned_votes).
    """
    if people_matrix is None or people_matrix.empty or possible_votes is None or possible_votes.empty:
        if show_warnings:
            logger.warning("Empty matrix passed to clean_votes")
        return people_matrix, possible_votes

    # Find legislators where ALL values are NaN
    to_drop: list[str] = []
    for name in list(people_matrix.index):
        if people_matrix.loc[name].isna().all() or possible_votes.loc[name].isna().all():
            to_drop.append(name)
            if show_warnings:
                logger.warning("No votes recorded for %s", name)

    if to_drop:
        people_matrix = people_matrix.drop(index=to_drop, columns=to_drop)
        possible_votes = possible_votes.drop(index=to_drop, columns=to_drop)

    return people_matrix, possible_votes


def clean_sponsor_votes(
    people_matrix: pd.DataFrame,
    possible_votes: pd.DataFrame,
    sponsorship_counts: pd.DataFrame,
    show_warnings: bool = False,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Remove sponsors below the threshold and all-NaN legislators.

    Replaces forge.cleanSponsorVotes(). First calls clean_votes, then removes
    sponsors with count below ``mean - std/2``.

    Args:
        people_matrix: Sponsor agreement matrix.
        possible_votes: Corresponding vote-count matrix.
        sponsorship_counts: DataFrame with 'count' column indexed by legislator ID.
        show_warnings: If True, log warnings for removed legislators.

    Returns:
        Tuple of (cleaned_matrix, cleaned_votes).
    """
    if people_matrix is None or people_matrix.empty or possible_votes is None or possible_votes.empty:
        if show_warnings:
            logger.warning("Empty sponsor matrix")
        return people_matrix, possible_votes

    # First, clean NaN rows
    people_matrix, possible_votes = clean_votes(people_matrix, possible_votes, show_warnings)

    if people_matrix.empty:
        return people_matrix, possible_votes

    # Compute sponsor filter: mean - std/2
    counts = sponsorship_counts["count"]
    sponsor_filter = counts.mean() - counts.std() / 2

    # Remove sponsors below threshold (only columns, matching MATLAB behavior)
    to_drop: list[str] = []
    for name in list(people_matrix.columns):
        if name in sponsorship_counts.index and sponsorship_counts.loc[name, "count"] < sponsor_filter:
            to_drop.append(name)
            if show_warnings:
                logger.warning(
                    "%s did not meet the vote threshold with only %d",
                    name,
                    sponsorship_counts.loc[name, "count"],
                )

    if to_drop:
        # Remove columns (MATLAB removes variable names, which are columns)
        people_matrix = people_matrix.drop(columns=[c for c in to_drop if c in people_matrix.columns])
        possible_votes = possible_votes.drop(columns=[c for c in to_drop if c in possible_votes.columns])

    return people_matrix, possible_votes


def normalize_votes(
    people_matrix: pd.DataFrame,
    vote_matrix: pd.DataFrame,
) -> pd.DataFrame:
    """Element-wise divide agreement by possible votes.

    Replaces forge.normalizeVotes().

    Args:
        people_matrix: Agreement/sponsor matrix.
        vote_matrix: Possible votes matrix (same shape).

    Returns:
        Normalized matrix where each cell = agreement / possible_votes.
    """
    if people_matrix is None or people_matrix.empty or vote_matrix is None or vote_matrix.empty:
        return people_matrix

    result = people_matrix.copy()
    result.iloc[:, :] = people_matrix.values / vote_matrix.values
    return result


def _process_parties(
    people: pd.DataFrame,
    show_warnings: bool = False,
) -> tuple[list[str], list[str]]:
    """Split people into Republican and Democrat ID lists.

    Replaces forge.processParties().

    Args:
        people: People DataFrame with 'sponsor_id' and 'party_id' columns.
        show_warnings: If True, log warnings for non-standard party IDs.

    Returns:
        Tuple of (republican_ids, democrat_ids) in 'id{N}' format.
    """
    republican_ids = create_id_strings(people.loc[people["party_id"] == 1, "sponsor_id"].tolist())
    democrat_ids = create_id_strings(people.loc[people["party_id"] == 0, "sponsor_id"].tolist())

    if show_warnings:
        bad = people[~people["party_id"].isin([0, 1])]
        for _, row in bad.iterrows():
            logger.warning("Incorrect party ID for id%s", row["sponsor_id"])

    return republican_ids, democrat_ids


def _extract_party_submatrix(
    matrix: pd.DataFrame | None,
    party_ids: list[str],
) -> pd.DataFrame | None:
    """Extract a party-specific sub-matrix using CStrAinBP logic.

    Args:
        matrix: Full chamber or sponsor matrix.
        party_ids: List of legislator IDs for one party.

    Returns:
        Sub-matrix or None if the input matrix is None/empty.
    """
    if matrix is None or matrix.empty:
        return None

    row_matches, _ = cstr_ainbp(list(matrix.index), party_ids)
    col_matches, _ = cstr_ainbp(list(matrix.columns), party_ids)

    if not row_matches or not col_matches:
        return None

    row_labels = [matrix.index[i] for i in row_matches]
    col_labels = [matrix.columns[i] for i in col_matches]

    return matrix.loc[row_labels, col_labels]


_PASSAGE_PATTERN = re.compile(r"(THIRD|3RD|ON PASSAGE)", re.IGNORECASE)


def process_chamber_votes(
    bill_set: dict,
    people: pd.DataFrame,
    chamber: str,
    category: int | list[int] = 0,
    competitive_threshold: float = 0.85,
    show_warnings: bool = False,
) -> MatrixResults:
    """Build all agreement and sponsor matrices for one chamber.

    Replaces @forge/processChamberVotes.m — the most complex function in the
    MATLAB codebase. Iterates over all bills, filters by category and
    competitiveness, builds agreement matrices from "THIRD/3RD/ON PASSAGE"
    votes, then cleans, normalizes, and splits by party.

    Args:
        bill_set: Dictionary mapping bill_id → Bill objects.
        people: People DataFrame with 'sponsor_id' and 'party_id' columns.
        chamber: 'house' or 'senate'.
        category: Issue category to filter by (0 = all categories 1-11).
        competitive_threshold: Threshold for competitive votes (default 0.85).
        show_warnings: If True, log warnings.

    Returns:
        MatrixResults with all computed matrices.
    """
    chamber_data_attr = f"{chamber}_data"

    # Determine categories to include
    if isinstance(category, int):
        categories = list(range(1, 12)) if category == 0 else [category]
    else:
        categories = list(category)

    # Create ID strings from people
    ids = create_id_strings(people["sponsor_id"].tolist())
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate legislator IDs detected")

    # Initialize NaN matrices
    chamber_matrix, chamber_votes_mat = _create_nan_table(ids)
    chamber_sponsor_matrix, chamber_sponsor_votes = _create_nan_table(ids)

    # Sponsorship counts
    sponsorship_counts = _create_zero_table(ids, ["count"])

    # Consistency matrix
    consistency_matrix = _create_zero_table(ids, ["consistency", "opportunity"])

    # Track processed bill IDs
    bill_ids: list[int] = []

    for bill_id, bill in bill_set.items():
        # Filter by category
        if not any(bill.issue_category == cat for cat in categories):
            if not (isinstance(bill.issue_category, float) and math.isnan(bill.issue_category)):
                continue
            else:
                continue

        # Check passage status and competitiveness
        passed_attr = f"passed_{chamber}"
        bill_chamber_data = getattr(bill, chamber_data_attr, None)
        passed_val = getattr(bill, passed_attr, -1)

        if passed_val < 0 or bill_chamber_data is None or not bill_chamber_data.competitive:
            continue

        # Sponsor information
        sponsor_ids = create_id_strings(bill.sponsors, ids)

        # Increment sponsorship counts
        for sid in sponsor_ids:
            if sid in sponsorship_counts.index:
                sponsorship_counts.loc[sid, "count"] += 1

        # Committee votes are disabled in MATLAB (commented out) — set to empty
        # but keep structure for future re-enablement

        # Chamber votes processing
        is_chamber_votes = False
        yes_ids: list[str] = []
        no_ids: list[str] = []

        for vote in bill_chamber_data.chamber_votes:
            # Filter for THIRD/3RD/ON PASSAGE votes
            desc = vote.description
            if isinstance(desc, list):
                desc = " ".join(str(d) for d in desc)
            if not _PASSAGE_PATTERN.search(desc.upper() if desc else ""):
                continue

            # Get voter IDs filtered to known legislators
            yes_ids = create_id_strings(vote.yes_list, ids)
            no_ids = create_id_strings(vote.no_list, ids)

            # Agreement: same-vote pairs get 1, different-vote pairs get 0
            chamber_matrix = add_votes(chamber_matrix, yes_ids, yes_ids)
            chamber_matrix = add_votes(chamber_matrix, no_ids, no_ids)
            chamber_matrix = add_votes(chamber_matrix, yes_ids, no_ids, value=0.0)
            chamber_matrix = add_votes(chamber_matrix, no_ids, yes_ids, value=0.0)

            # Possible votes: all voting pairs
            all_voting = yes_ids + no_ids
            chamber_votes_mat = add_votes(chamber_votes_mat, all_voting, all_voting)

            is_chamber_votes = True

        if is_chamber_votes:
            # Sponsor information using last chamber vote's yes/no IDs
            chamber_sponsor_matrix = add_votes(chamber_sponsor_matrix, sponsor_ids, yes_ids)
            chamber_sponsor_matrix = add_votes(chamber_sponsor_matrix, sponsor_ids, no_ids, value=0.0)
            chamber_sponsor_votes = add_votes(chamber_sponsor_votes, sponsor_ids, yes_ids + no_ids)

            # Track bill (committee processing is disabled but bill counts if chamber votes exist)
            bill_ids.append(bill_id)

    logger.info("Chamber vote processing complete! %d bills processed", len(bill_ids))

    # Clean votes of non-sufficient legislators
    chamber_matrix, chamber_votes_mat = clean_votes(chamber_matrix, chamber_votes_mat, show_warnings)
    chamber_sponsor_matrix, chamber_sponsor_votes = clean_sponsor_votes(
        chamber_sponsor_matrix, chamber_sponsor_votes, sponsorship_counts, show_warnings
    )

    # Normalize
    chamber_matrix = normalize_votes(chamber_matrix, chamber_votes_mat)
    chamber_sponsor_matrix = normalize_votes(chamber_sponsor_matrix, chamber_sponsor_votes)

    # Consistency percentage
    consistency_matrix["percentage"] = consistency_matrix["consistency"] / consistency_matrix["opportunity"].replace(0, np.nan)

    # Party splitting
    republican_ids, democrat_ids = _process_parties(people, show_warnings)

    results = MatrixResults(
        chamber_matrix=chamber_matrix,
        chamber_votes=chamber_votes_mat,
        chamber_sponsor_matrix=chamber_sponsor_matrix,
        chamber_sponsor_votes=chamber_sponsor_votes,
        committee_matrix=None,
        committee_votes=None,
        committee_sponsor_matrix=None,
        committee_sponsor_votes=None,
        consistency_matrix=consistency_matrix,
        bill_ids=bill_ids,
        republicans_chamber_votes=_extract_party_submatrix(chamber_matrix, republican_ids),
        democrats_chamber_votes=_extract_party_submatrix(chamber_matrix, democrat_ids),
        republicans_chamber_sponsor=_extract_party_submatrix(chamber_sponsor_matrix, republican_ids),
        democrats_chamber_sponsor=_extract_party_submatrix(chamber_sponsor_matrix, democrat_ids),
        republicans_committee_votes=None,
        democrats_committee_votes=None,
        republicans_committee_sponsor=None,
        democrats_committee_sponsor=None,
        seat_matrix=None,
    )

    # Seat proximity (if seat data exists)
    if "SEATROW" in people.columns and "SEATCOLUMN" in people.columns:
        from forge.matrices.proximity import compute_seat_proximity

        results.seat_matrix = compute_seat_proximity(people)

    return results
