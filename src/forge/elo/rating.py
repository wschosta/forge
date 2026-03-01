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

from forge.config import ForgeConfig, create_id_strings, cstr_ainbp
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
    chamber_specifics = chamber_matrix.values
    n = len(ids)

    # Get chamber size
    chamber_size = config.house_size if chamber == "house" else config.senate_size

    # Sponsor matrix values
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
                idx_list, _ = cstr_ainbp(ids, [sid])
                for idx in idx_list:
                    t1[idx] = result["sponsor_values"][i]

        # Set up final results
        t_final_results = np.full(n, np.nan)
        for sid in result["yes_ids"]:
            idx_list, _ = cstr_ainbp(ids, [sid])
            for idx in idx_list:
                t_final_results[idx] = 1.0
        for sid in result["no_ids"]:
            idx_list, _ = cstr_ainbp(ids, [sid])
            for idx in idx_list:
                t_final_results[idx] = 0.0

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
        leg_indices = []
        for lid in legislator_order:
            idx_list, _ = cstr_ainbp(ids, [lid])
            leg_indices.append(idx_list[0] if idx_list else -1)

        # Pairwise Elo updates
        local_count = count[leg_indices].copy()
        local_score1 = score_variable_k[leg_indices].copy()
        local_score2 = score_fixed_k[leg_indices].copy()

        n_legs = len(legislator_order)
        for i in range(n_legs):
            for j in range(i + 1, n_legs):
                local_count[i] += 1
                local_count[j] += 1

                # Win/loss/draw
                if accuracy_per_leg[i] > accuracy_per_leg[j]:
                    wa, wb = 1.0, 0.0
                elif accuracy_per_leg[i] == accuracy_per_leg[j]:
                    wa, wb = 0.5, 0.5
                else:
                    wa, wb = 0.0, 1.0

                # Variable-K Elo
                ea = 1.0 / (1.0 + 10.0 ** ((local_score1[j] - local_score1[i]) / 400.0))
                eb = 1.0 / (1.0 + 10.0 ** ((local_score1[i] - local_score1[j]) / 400.0))

                ka = config.elo_variable_k_numerator / max(
                    config.elo_variable_k_min_count,
                    min(local_count[i], config.elo_variable_k_max_count),
                )
                kb = config.elo_variable_k_numerator / max(
                    config.elo_variable_k_min_count,
                    min(local_count[j], config.elo_variable_k_max_count),
                )

                local_score1[i] += ka * (wa - ea)
                local_score1[j] += kb * (wb - eb)

                # Fixed-K Elo
                ea = 1.0 / (1.0 + 10.0 ** ((local_score2[j] - local_score2[i]) / 400.0))
                eb = 1.0 / (1.0 + 10.0 ** ((local_score2[i] - local_score2[j]) / 400.0))

                local_score2[i] += config.elo_fixed_k * (wa - ea)
                local_score2[j] += config.elo_fixed_k * (wb - eb)

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
