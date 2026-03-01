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
    n_mc = accuracy_list.shape[1] if accuracy_list.ndim > 1 else 1

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

        for leg_id in unique_legislators:
            # For each legislator, compute their score across all iterations
            mask = (leg_array == leg_id)  # (n_iters, n_legs_per_iter)

            # Delta score weighted by placement
            delta_score = specific_delta * mask
            placement = np.sum(mask[:, :len(placement_points)] * placement_points, axis=1)

            # Score = sum of (delta_score * placement) / (1 - starting_accuracy)
            starting_acc = specific_accuracy[:, 0]
            denom = 1.0 - starting_acc
            denom[denom == 0] = 1.0  # avoid division by zero

            score = np.sum(delta_score @ placement_points) / np.mean(denom) if denom.mean() != 0 else 0.0

            # Simpler faithful port: replicate MATLAB's exact computation
            leg_score = 0.0
            for j in range(n_iters):
                delta_row = specific_delta[j] * mask[j]
                place_row = mask[j, :len(placement_points)].astype(float) * placement_points
                contribution = np.dot(delta_row, place_row)
                denom_j = 1.0 - specific_accuracy[j, 0]
                if denom_j != 0:
                    leg_score += contribution / denom_j

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
    max_results = agg["results"].abs().max()
    if max_results > 0:
        agg["results"] = agg["results"] / max_results

    return agg
