"""Elo rating system — replaces eloPrediction.m.

Legislators are rated using a chess-style Elo system where "winning" means
having higher prediction accuracy. Two variants: variable-K and fixed-K.

Uses the shared prediction logic from predict.bayes to deduplicate the ~60
lines of code that were copy-pasted from predictOutcomes.m.
"""

from __future__ import annotations

import logging

import numpy as np
import pandas as pd

from forge.config import ForgeConfig, create_id_strings
from forge.predict.bayes import predict_bill, update_bayes

logger = logging.getLogger(__name__)


def elo_prediction(
    bill_ids: list[int],
    bill_set: dict,
    chamber_people: pd.DataFrame,
    chamber_sponsor_matrix: pd.DataFrame | None,
    chamber_matrix: pd.DataFrame,
    chamber: str,
    config: ForgeConfig,
    rng: np.random.Generator | None = None,
) -> pd.DataFrame | None:
    """Run Elo prediction across a set of bills.

    Replaces @forge/eloPrediction.m. Uses the shared prediction logic
    from predict.bayes.predict_bill() instead of duplicating code.

    For each bill:
    1. Compute sponsor effect and Bayesian prediction (shared logic)
    2. Compute per-legislator accuracy
    3. Perform pairwise Elo updates between all legislators

    Args:
        bill_ids: List of bill IDs to process.
        bill_set: Dict mapping bill_id → Bill objects.
        chamber_people: People DataFrame for this chamber.
        chamber_sponsor_matrix: Sponsor agreement DataFrame.
        chamber_matrix: Chamber agreement DataFrame.
        chamber: 'house' or 'senate'.
        config: ForgeConfig with Elo parameters.
        rng: Numpy random generator (if None, creates one per bill).

    Returns:
        DataFrame with Elo scores, or None if no bills processed.
    """
    ids = list(chamber_matrix.index)
    id_to_idx = {lid: i for i, lid in enumerate(ids)}
    chamber_specifics = chamber_matrix.values
    n = len(ids)

    # Get chamber size
    chamber_size = config.house_size if chamber == "house" else config.senate_size

    # Extract sponsor matrix components once (not per bill)
    sponsor_values = None
    sponsor_row_names = None
    sponsor_col_names = None
    if chamber_sponsor_matrix is not None and not chamber_sponsor_matrix.empty:
        sponsor_values = chamber_sponsor_matrix.values
        sponsor_row_names = list(chamber_sponsor_matrix.index)
        sponsor_col_names = list(chamber_sponsor_matrix.columns)

    # Initialize Elo scores
    score_variable_k = np.ones(n) * config.elo_initial_score
    score_fixed_k = np.ones(n) * config.elo_initial_score
    count = np.zeros(n)

    for bill_id in bill_ids:
        bill = bill_set.get(bill_id)
        if bill is None:
            continue

        # Use shared prediction logic
        bill_rng = rng if rng is not None else np.random.default_rng()
        result = predict_bill(
            bill, bill_id, ids,
            sponsor_values, sponsor_row_names, sponsor_col_names,
            chamber_specifics, chamber, chamber_size,
            rng=bill_rng, bayes_initial=config.bayes_initial,
        )

        if result is None:
            continue

        # Get per-legislator accuracy by running iterative updates
        # (matching MATLAB's eloPrediction which calls updateBayes per legislator
        # but only records accuracy, not the updated values)
        legislator_order = result["legislator_order"]
        direction = result["direction"]
        t1 = np.ones(n) * config.bayes_initial

        # Set sponsor effect in t1
        sponsor_ids = create_id_strings(bill.sponsors, ids)
        if result["n_sponsors"] > 1:
            for i, sid in enumerate(sponsor_ids):
                if sid in id_to_idx:
                    t1[id_to_idx[sid]] = result["sponsor_values"][i]

        # Set up final results
        t_final_results = np.full(n, np.nan)
        for sid in result["yes_ids"]:
            if sid in id_to_idx:
                t_final_results[id_to_idx[sid]] = 1.0
        for sid in result["no_ids"]:
            if sid in id_to_idx:
                t_final_results[id_to_idx[sid]] = 0.0

        # Run Bayesian updates to get per-legislator accuracy
        # (MATLAB records accuracy at each step but doesn't update t_current_value in elo)
        accuracy_per_leg = np.zeros(len(legislator_order))
        t_current_value = t1.copy()
        t_count = 1
        for i, lid in enumerate(legislator_order):
            _, _, acc = update_bayes(
                lid, int(direction[i]), t_current_value, chamber_specifics,
                t_count, ids, t_final_results
            )
            accuracy_per_leg[i] = acc

        # Get indices of legislators in the Elo score arrays
        leg_indices = [id_to_idx.get(lid, -1) for lid in legislator_order]

        # Pairwise Elo updates
        local_count = count[leg_indices].copy()
        local_score1 = score_variable_k[leg_indices].copy()
        local_score2 = score_fixed_k[leg_indices].copy()

        # Every pair reads scores that earlier pairs in the same sweep already
        # updated, so this loop is inherently sequential and cannot be
        # vectorized without changing the numbers. What it can avoid is
        # re-resolving the same constants tens of millions of times: the four
        # config attributes below were being looked up on every comparison.
        k_numerator = config.elo_variable_k_numerator
        k_min_count = config.elo_variable_k_min_count
        k_max_count = config.elo_variable_k_max_count
        fixed_k = config.elo_fixed_k

        # Plain Python lists outperform numpy scalars for this access pattern —
        # the loop is millions of single-element reads and writes, where numpy
        # pays boxing cost on every one.
        counts = [float(c) for c in local_count]
        scores_variable = [float(s) for s in local_score1]
        scores_fixed = [float(s) for s in local_score2]
        accuracies = [float(a) for a in accuracy_per_leg]

        n_legs = len(legislator_order)
        for i in range(n_legs):
            accuracy_i = accuracies[i]
            for j in range(i + 1, n_legs):
                counts[i] += 1
                counts[j] += 1

                # Win/loss/draw
                accuracy_j = accuracies[j]
                if accuracy_i > accuracy_j:
                    wa, wb = 1.0, 0.0
                elif accuracy_i == accuracy_j:
                    wa, wb = 0.5, 0.5
                else:
                    wa, wb = 0.0, 1.0

                # Variable-K Elo
                score_i = scores_variable[i]
                score_j = scores_variable[j]
                ea = 1.0 / (1.0 + 10.0 ** ((score_j - score_i) / 400.0))
                eb = 1.0 / (1.0 + 10.0 ** ((score_i - score_j) / 400.0))

                # Clamp the comparison count into [k_min, k_max] to set the
                # K factor. Written as explicit comparisons rather than
                # min()/max() on purpose: profiling this loop found 23.6 million
                # min()/max() calls costing ~7% of total Elo runtime, and
                # removing them is part of the 2.36x speedup measured here.
                # Ruff's PLR1730 suggests reinstating them; do not.
                count_i = counts[i]
                if count_i > k_max_count:  # noqa: PLR1730
                    count_i = k_max_count
                if count_i < k_min_count:  # noqa: PLR1730
                    count_i = k_min_count
                count_j = counts[j]
                if count_j > k_max_count:  # noqa: PLR1730
                    count_j = k_max_count
                if count_j < k_min_count:  # noqa: PLR1730
                    count_j = k_min_count

                scores_variable[i] = score_i + (k_numerator / count_i) * (wa - ea)
                scores_variable[j] = score_j + (k_numerator / count_j) * (wb - eb)

                # Fixed-K Elo
                score_i = scores_fixed[i]
                score_j = scores_fixed[j]
                ea = 1.0 / (1.0 + 10.0 ** ((score_j - score_i) / 400.0))
                eb = 1.0 / (1.0 + 10.0 ** ((score_i - score_j) / 400.0))

                scores_fixed[i] = score_i + fixed_k * (wa - ea)
                scores_fixed[j] = score_j + fixed_k * (wb - eb)

        local_count = counts
        local_score1 = scores_variable
        local_score2 = scores_fixed

        # Write back
        for k, idx in enumerate(leg_indices):
            if idx >= 0:
                count[idx] = local_count[k]
                score_variable_k[idx] = local_score1[k]
                score_fixed_k[idx] = local_score2[k]

    # Build results DataFrame
    elo_score = pd.DataFrame(
        {
            "score_variable_k": score_variable_k,
            "score_fixed_k": score_fixed_k,
            "count": count,
            "difference": score_variable_k - score_fixed_k,
        },
        index=ids,
    )

    return elo_score
