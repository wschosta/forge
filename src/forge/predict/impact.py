"""Legislator impact scoring — replaces processLegislatorImpacts.m.

Computes per-legislator impact scores from Monte Carlo prediction results
using placement-weighted accuracy deltas.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def process_legislator_impacts(
    accuracy_list: np.ndarray,
    accuracy_delta: np.ndarray,
    legislators_list: list[list[list[int]]],
    accuracy_steps_list: list[list[np.ndarray]],
    bill_ids: list[int],
) -> pd.DataFrame | None:
    """Compute per-legislator impact scores from MC prediction results.

    Replaces @forge/processLegislatorImpacts.m.

    For each bill, computes a placement-weighted accuracy delta score for each
    legislator across all MC iterations, then aggregates across bills.

    Args:
        accuracy_list: (n_bills, n_mc) array of final accuracies.
        accuracy_delta: (n_bills, n_mc) array of accuracy deltas.
        legislators_list: Per-bill list of per-MC-iteration legislator ID lists.
        accuracy_steps_list: Per-bill list of per-MC-iteration step-delta arrays.
        bill_ids: List of bill IDs that were processed.

    Returns:
        DataFrame with columns: legislator_id, coverage, results (normalized).
        Returns None if inputs are empty.
    """
    if not legislators_list or not accuracy_steps_list or accuracy_list.size == 0:
        return None

    master_list: list[tuple[int, float]] = []

    n_bills = len(legislators_list)

    for i in range(n_bills):
        bill_legislators = legislators_list[i]  # list of MC iterations
        bill_steps = accuracy_steps_list[i]  # list of step-delta arrays

        if not bill_legislators or not bill_steps:
            continue

        # Build matrices for this bill
        n_iters = len(bill_legislators)
        n_legs_per_iter = len(bill_legislators[0]) if bill_legislators else 0

        if n_legs_per_iter == 0:
            continue

        # specific_delta_list: (n_iters, n_legs_per_iter) — accuracy delta at each step
        specific_delta = np.zeros((n_iters, n_legs_per_iter))
        # specific_accuracy_list: (n_iters, n_legs_per_iter+1)
        specific_accuracy = np.zeros((n_iters, n_legs_per_iter + 1))

        for j in range(n_iters):
            # Starting accuracy = final - delta
            starting_acc = accuracy_list[i, j] - accuracy_delta[i, j]
            specific_accuracy[j, 0] = starting_acc

            steps = bill_steps[j]
            for k in range(min(len(steps), n_legs_per_iter)):
                specific_accuracy[j, k + 1] = specific_accuracy[j, k] + steps[k]
                specific_delta[j, k] = steps[k]

        # Convert bill_legislators to a numpy array for vectorized operations
        leg_array = np.array(bill_legislators)  # (n_iters, n_legs_per_iter)

        # Placement points: linearly spaced from 100 to 1
        placement_points = np.linspace(100, 1, n_legs_per_iter)

        unique_legislators = np.unique(leg_array)

        # Denominator: how much accuracy was left to gain from the starting
        # point (processLegislatorImpacts.m:66, `1 - specific_accuracy_list(1,1)`).
        #
        # Accuracies are carried through the Monte Carlo as percentages, so
        # `1 - accuracy` on the raw value gives roughly -46 rather than the
        # ~0.53 headroom the expression is reaching for. That sign is what
        # inverted every impact score: a positive numerator over a negative
        # denominator made every score negative, and normalizing negatives by
        # their maximum then produced an unbounded column instead of the
        # golden's [0, 1]. Scaling to a fraction restores both.
        #
        # MATLAB takes the starting accuracy of *iteration 1* and reuses it for
        # every iteration, rather than each iteration's own. That looks like an
        # indexing slip, but it is the arithmetic the committed results were
        # produced with, so it is reproduced here.
        baseline_accuracy = specific_accuracy[0, 0] / 100.0
        denominator = 1.0 - baseline_accuracy
        if denominator == 0:
            continue

        for leg_id in unique_legislators:
            mask = leg_array == leg_id  # (n_iters, n_legs_per_iter)

            # Placement weight is summed over *all* iterations before being
            # applied, so a legislator repeatedly drawn into an influential
            # position is weighted by how often that happened, not just by the
            # position itself (processLegislatorImpacts.m:65).
            placement = mask[:, : len(placement_points)].sum(axis=0) * placement_points
            leg_score = float(((specific_delta * mask) @ placement).sum() / denominator)

            master_list.append((int(leg_id), leg_score))

    if not master_list:
        return None

    # Aggregate across bills: sum scores per unique legislator
    master_df = pd.DataFrame(master_list, columns=["legislator_id", "score"])
    agg = master_df.groupby("legislator_id").agg(
        coverage=("score", "count"),
        results=("score", "sum"),
    ).reset_index()

    # Normalize
    agg["coverage"] = agg["coverage"] / len(bill_ids)

    # Divide by the maximum, matching processLegislatorImpacts.m:81.
    #
    # With the accuracy denominator read as a fraction (see above), scores in
    # a normal run are positive and this bounds the column to (0, 1] — the
    # shape every committed MATLAB output has. A run whose accuracy falls on
    # average produces negative scores, and dividing those by their
    # least-negative element leaves values above 1.0; that is a property of
    # normalizing by a signed maximum rather than a defect.
    max_results = agg["results"].max()
    if max_results != 0:
        agg["results"] = agg["results"] / max_results

    return agg
