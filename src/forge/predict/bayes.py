"""Bayesian prediction — replaces predict.updateBayes, predict.getSpecificImpact.

Also contains the shared sponsor-effect and bill-prediction logic that was
duplicated between predictOutcomes.m and eloPrediction.m (~60 lines).
"""

from __future__ import annotations

import re

import numpy as np

from forge.config import create_id_strings, cstr_ainbp

_PASSAGE_PATTERN = re.compile(r"(THIRD|3RD|ON PASSAGE)", re.IGNORECASE)


def get_specific_impact(revealed_preference: int, specific_impact: float) -> float:
    """Clamp and direction-flip an impact value for Bayesian updating.

    Replaces +predict/getSpecificImpact.m.

    Args:
        revealed_preference: 1 for yea, 0 for nay.
        specific_impact: Raw agreement value from the chamber matrix.

    Returns:
        Adjusted impact value in (0, 1). Returns 0.5 for NaN inputs.
    """
    if np.isnan(specific_impact):
        return 0.5

    if revealed_preference == 1:
        if specific_impact == 1.0:
            return 0.999
        if specific_impact == 0.0:
            return 0.001
        return specific_impact
    elif revealed_preference == 0:
        if specific_impact == 0.0:
            return 0.999
        if specific_impact == 1.0:
            return 0.001
        return 1.0 - specific_impact
    else:
        raise ValueError("Non-binary revealed preferences not supported")


def update_bayes(
    revealed_id: str,
    revealed_preference: int,
    t_set_previous_value: np.ndarray,
    chamber_specifics: np.ndarray,
    t_count: int,
    ids: list[str],
    t_final_results: np.ndarray,
) -> tuple[np.ndarray, int, float]:
    """Perform a single Bayesian posterior update for one revealed legislator.

    Replaces +predict/updateBayes.m (vectorized version).

    For each legislator, computes:
        impact = |1 - revealed_preference - agreement(legislator, revealed)|
        P_new = (impact * P_old) / (impact * P_old + (1-impact) * (1-P_old))

    Args:
        revealed_id: The ID string (e.g. 'id123') of the legislator revealing preference.
        revealed_preference: 1 (yea) or 0 (nay).
        t_set_previous_value: Current posterior values for all legislators.
        chamber_specifics: NxN numpy array of agreement values.
        t_count: Current time step counter.
        ids: List of all legislator ID strings.
        t_final_results: Ground-truth final vote outcomes (1/0/NaN).

    Returns:
        Tuple of (updated_values, new_t_count, accuracy_percentage).
    """
    t_count += 1

    # Find the index of the revealed legislator
    matched_ids, _ = cstr_ainbp(ids, [revealed_id])
    if not matched_ids:
        return t_set_previous_value, t_count, 0.0

    matched_idx = matched_ids[0]

    # Build the list of all other legislators
    n = len(ids)
    id_list = [i for i in range(n) if i != matched_idx]

    # Compute impacts for all other legislators
    combined_impact = np.zeros(n)
    combined_impact[id_list] = np.abs(
        1.0 - revealed_preference - chamber_specifics[id_list, matched_idx]
    )

    # Bayesian update: P_new = (impact * P_old) / (impact * P_old + (1-impact) * (1-P_old))
    prev = t_set_previous_value
    numerator = combined_impact * prev
    denominator = combined_impact * prev + (1.0 - combined_impact) * (1.0 - prev)

    # Avoid division by zero
    with np.errstate(divide="ignore", invalid="ignore"):
        t_set_current_value = np.where(denominator != 0, numerator / denominator, prev)

    # Preserve NaN values from previous step
    nan_mask = np.isnan(t_set_current_value)
    t_set_current_value[nan_mask] = t_set_previous_value[nan_mask]

    # Clamp to [0.001, 0.999]
    t_set_current_value[t_set_current_value == 0.0] = 0.001
    t_set_current_value[t_set_current_value == 1.0] = 0.999

    # Set the revealed legislator's value
    t_set_current_value[matched_idx] = abs(revealed_preference - 0.001)

    # Compute accuracy
    t_check = np.round(t_set_current_value) == t_final_results
    incorrect = np.sum(~t_check)
    nan_in_incorrect = np.sum(np.isnan(t_final_results[~t_check]))
    n_known = np.sum(~np.isnan(t_final_results))
    if n_known > 0:
        accuracy = 100.0 * (1.0 - (incorrect - nan_in_incorrect) / n_known)
    else:
        accuracy = 0.0

    return t_set_current_value, t_count, accuracy


# ---------------------------------------------------------------------------
# Shared bill prediction logic (extracted from predictOutcomes + eloPrediction)
# ---------------------------------------------------------------------------

def compute_sponsor_effect(
    sponsor_ids: list[str],
    chamber_sponsor_matrix: np.ndarray | None,
    sponsor_row_names: list[str] | None,
    sponsor_col_names: list[str] | None,
    bayes_initial: float = 0.5,
) -> np.ndarray:
    """Compute the sponsor effect for t1.

    This is the shared logic duplicated in both predictOutcomes.m and
    eloPrediction.m. For each sponsor, computes a Bayesian product of
    sponsor-agreement impacts.

    Args:
        sponsor_ids: List of sponsor ID strings.
        chamber_sponsor_matrix: The sponsor agreement matrix values (numpy array).
        sponsor_row_names: Row names of the sponsor matrix.
        sponsor_col_names: Column names of the sponsor matrix.
        bayes_initial: Prior probability (default 0.5).

    Returns:
        Array of sponsor effect values, one per sponsor_id.
    """
    n_sponsors = len(sponsor_ids)
    sponsor_specific = np.ones(n_sponsors) * bayes_initial

    if chamber_sponsor_matrix is None or sponsor_row_names is None or sponsor_col_names is None:
        return sponsor_specific

    # Find sponsor_ids that exist in the sponsor matrix columns
    match_a, _ = cstr_ainbp(sponsor_ids, sponsor_col_names)
    sponsor_match = [sponsor_ids[i] for i in match_a]

    if not sponsor_match:
        return sponsor_specific

    for i, sid in enumerate(sponsor_ids):
        if sid not in sponsor_row_names:
            continue

        row_idx = sponsor_row_names.index(sid)
        effects = np.zeros(len(sponsor_match))

        for k, sm in enumerate(sponsor_match):
            col_idx = sponsor_col_names.index(sm)
            effects[k] = get_specific_impact(1, chamber_sponsor_matrix[row_idx, col_idx])

        prod_effects = np.prod(effects)
        prod_inv = np.prod(1.0 - effects)
        denom = prod_effects * bayes_initial + prod_inv * (1.0 - bayes_initial)
        if denom != 0:
            sponsor_specific[i] = prod_effects * bayes_initial / denom

    return sponsor_specific


def find_passage_vote(bill, chamber: str, ids: list[str]):
    """Find the passage vote (THIRD/3RD/ON PASSAGE) for a bill.

    Shared helper extracted from the duplicated logic in predictOutcomes.m
    and eloPrediction.m.

    Args:
        bill: A Bill object.
        chamber: 'house' or 'senate'.
        ids: List of valid legislator IDs.

    Returns:
        Tuple of (yes_ids, no_ids, legislator_list) or (None, None, None)
        if no passage vote was found.
    """
    chamber_data = getattr(bill, f"{chamber}_data", None)
    if chamber_data is None:
        return None, None, None

    # Search from last to first for THIRD/3RD/ON PASSAGE vote
    for vote in reversed(chamber_data.chamber_votes):
        desc = vote.description
        if isinstance(desc, list):
            desc = " ".join(str(d) for d in desc)
        if _PASSAGE_PATTERN.search(desc.upper() if desc else ""):
            yes_ids = create_id_strings(vote.yes_list, ids)
            no_ids = create_id_strings(vote.no_list, ids)
            return yes_ids, no_ids, yes_ids + no_ids

    return None, None, None


def predict_bill(
    bill,
    bill_id: int,
    ids: list[str],
    chamber_sponsor_matrix_values: np.ndarray | None,
    sponsor_row_names: list[str] | None,
    sponsor_col_names: list[str] | None,
    chamber_specifics: np.ndarray,
    chamber: str,
    chamber_size: int,
    rng: np.random.Generator | None = None,
    bayes_initial: float = 0.5,
) -> dict | None:
    """Run a single-pass prediction for one bill.

    This is the shared prediction logic extracted from the ~60 duplicated lines
    in predictOutcomes.m and eloPrediction.m. Computes sponsor effect, sets up
    final results, randomizes legislator order, and runs iterative Bayes updates.

    Args:
        bill: A Bill object.
        bill_id: The bill ID.
        ids: List of all legislator ID strings in the chamber matrix.
        chamber_sponsor_matrix_values: Sponsor matrix as numpy array (or None).
        sponsor_row_names: Row names of sponsor matrix.
        sponsor_col_names: Column names of sponsor matrix.
        chamber_specifics: NxN agreement matrix values.
        chamber: 'house' or 'senate'.
        chamber_size: Expected chamber size for minimum-vote check.
        rng: Numpy random generator for shuffling.
        bayes_initial: Prior probability.

    Returns:
        Dict with keys: 'yes_ids', 'no_ids', 'legislator_order', 'direction',
        'accuracies' (per-step), 't1_accuracy', 'final_accuracy',
        'sponsor_values'. Returns None if the bill should be skipped.
    """
    if not bill.complete:
        return None

    # Find passage vote
    yes_ids, no_ids, legislator_list = find_passage_vote(bill, chamber, ids)
    if legislator_list is None or len(legislator_list) < chamber_size * 0.5:
        return None

    # Get sponsor IDs
    sponsor_ids = create_id_strings(bill.sponsors, ids)
    n_sponsors = len(sponsor_ids)

    # Set up final results vector
    n = len(ids)
    t_final_results = np.full(n, np.nan)
    for sid in yes_ids:
        idx_list, _ = cstr_ainbp(ids, [sid])
        for idx in idx_list:
            t_final_results[idx] = 1.0
    for sid in no_ids:
        idx_list, _ = cstr_ainbp(ids, [sid])
        for idx in idx_list:
            t_final_results[idx] = 0.0

    # Sponsor effect (t1)
    if n_sponsors > 1:
        sponsor_values = compute_sponsor_effect(
            sponsor_ids, chamber_sponsor_matrix_values,
            sponsor_row_names, sponsor_col_names, bayes_initial
        )
        t1 = np.ones(n) * bayes_initial
        for i, sid in enumerate(sponsor_ids):
            idx_list, _ = cstr_ainbp(ids, [sid])
            for idx in idx_list:
                t1[idx] = sponsor_values[i]
    else:
        sponsor_values = np.array([bayes_initial])
        t1 = np.ones(n) * bayes_initial

    # Compute t1 accuracy
    t1_check = np.round(t1) == t_final_results
    incorrect = np.sum(~t1_check)
    nan_in_incorrect = np.sum(np.isnan(t_final_results[~t1_check]))
    n_known = np.sum(~np.isnan(t_final_results))
    if n_known > 0:
        t1_accuracy = 100.0 * (1.0 - (incorrect - nan_in_incorrect) / n_known)
    else:
        t1_accuracy = 0.0

    # Randomize legislator order
    if rng is not None:
        perm = rng.permutation(len(legislator_list))
    else:
        perm = np.random.permutation(len(legislator_list))
    legislator_order = [legislator_list[p] for p in perm]

    # Determine direction (1=yes, 0=no) for each legislator
    yes_set = set(yes_ids)
    direction = np.array([1 if lid in yes_set else 0 for lid in legislator_order])

    # Iterative Bayes updates
    accuracies = np.zeros(len(legislator_order) + 1)
    accuracies[0] = t1_accuracy

    t_current_value = t1.copy()
    t_count = 1
    for i, lid in enumerate(legislator_order):
        t_current_value, t_count, acc = update_bayes(
            lid, int(direction[i]), t_current_value, chamber_specifics, t_count, ids, t_final_results
        )
        accuracies[i + 1] = acc

    return {
        "yes_ids": yes_ids,
        "no_ids": no_ids,
        "legislator_order": legislator_order,
        "direction": direction,
        "accuracies": accuracies,
        "t1_accuracy": t1_accuracy,
        "final_accuracy": accuracies[-1],
        "sponsor_values": sponsor_values,
        "n_sponsors": n_sponsors,
        "t_final_values": t_current_value,
    }
