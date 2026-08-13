"""Bayesian prediction — replaces predict.updateBayes, predict.getSpecificImpact.

Also contains the shared sponsor-effect and bill-prediction logic that was
duplicated between predictOutcomes.m and eloPrediction.m (~60 lines).
"""

from __future__ import annotations

import numpy as np

from forge.config import create_id_strings, cstr_ainbp
from forge.passage import is_passage_description


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
    id_index: dict[str, int] | None = None,
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
        id_index: Optional prebuilt ``{id_string: position}`` map. Supplying it
            replaces a linear scan over ``ids`` with a dict lookup; results are
            identical either way.

    Returns:
        Tuple of (updated_values, new_t_count, accuracy_percentage).
    """
    t_count += 1

    # Find the index of the revealed legislator. This runs once per legislator
    # per Monte Carlo iteration — on the order of millions of times in a full
    # run — so callers in the hot path pass a prebuilt index rather than paying
    # for a linear scan over the ID strings every time.
    if id_index is not None:
        matched_idx = id_index.get(revealed_id, -1)
        if matched_idx < 0:
            return t_set_previous_value, t_count, 0.0
    else:
        matched_ids, _ = cstr_ainbp(ids, [revealed_id])
        if not matched_ids:
            return t_set_previous_value, t_count, 0.0
        matched_idx = matched_ids[0]

    # Impact of the revealed preference on every other legislator. Computing
    # the whole column and zeroing the revealed legislator is equivalent to
    # excluding it via an index list, and avoids rebuilding an N-1 element
    # Python list on every call.
    combined_impact = np.abs(
        1.0 - revealed_preference - chamber_specifics[:, matched_idx]
    )
    combined_impact[matched_idx] = 0.0

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

    # Compute accuracy. ndarray methods are used in preference to the np.*
    # wrappers throughout: they skip numpy's dispatch layer, which dominates
    # the cost at these array sizes (~100 elements).
    wrong = t_set_current_value.round() != t_final_results
    final_nan = np.isnan(t_final_results)
    incorrect = wrong.sum()
    # A legislator with no recorded vote compares unequal to NaN and so lands
    # in `wrong`; those are discounted rather than counted as mispredictions.
    nan_in_incorrect = (wrong & final_nan).sum()

    # Divide by the legislators who actually cast a recorded vote, not by a
    # constant. MATLAB divided by a literal 100 (predictOutcomes.m), which is
    # only correct for a 100-seat chamber — right for the Indiana House and
    # wrong everywhere else; Oregon's 29-seat Senate differs by 12.24 points.
    # There is deliberately no compatibility mode (see CLAUDE.md). The 100.0
    # below is a percent conversion and nothing else.
    n_known = t_final_results.size - final_nan.sum()
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

    # Search from last to first for the passage vote. This must use the same
    # definition as the matrix builder: when the two drifted apart, New York and
    # Maine were recognised by `process_chamber_votes` and invisible here, so
    # both states built agreement matrices that no prediction could ever use.
    for vote in reversed(chamber_data.chamber_votes):
        if is_passage_description(vote.description):
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

    # Build ID→index lookup for O(1) access
    id_to_idx = {lid: i for i, lid in enumerate(ids)}

    # Set up final results vector
    n = len(ids)
    t_final_results = np.full(n, np.nan)
    for sid in yes_ids:
        if sid in id_to_idx:
            t_final_results[id_to_idx[sid]] = 1.0
    for sid in no_ids:
        if sid in id_to_idx:
            t_final_results[id_to_idx[sid]] = 0.0

    # Sponsor effect (t1)
    if n_sponsors > 1:
        sponsor_values = compute_sponsor_effect(
            sponsor_ids, chamber_sponsor_matrix_values,
            sponsor_row_names, sponsor_col_names, bayes_initial
        )
        t1 = np.ones(n) * bayes_initial
        for i, sid in enumerate(sponsor_ids):
            if sid in id_to_idx:
                t1[id_to_idx[sid]] = sponsor_values[i]
    else:
        sponsor_values = np.array([bayes_initial])
        t1 = np.ones(n) * bayes_initial

    # Compute t1 accuracy
    # Same accuracy definition as update_bayes — scaled by the legislators who
    # actually voted, not MATLAB's literal 100. See the note there.
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
            lid, int(direction[i]), t_current_value, chamber_specifics, t_count, ids,
            t_final_results, id_index=id_to_idx,
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
