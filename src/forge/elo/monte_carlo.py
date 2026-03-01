"""Elo Monte Carlo orchestrator — replaces eloMonteCarlo.m.

Runs the Elo prediction across multiple random orderings (MC iterations)
and averages the scores. Supports per-category analysis.
"""

from __future__ import annotations

import logging
import re

import numpy as np
import pandas as pd

from forge.config import ForgeConfig, create_id_strings
from forge.elo.rating import elo_prediction

logger = logging.getLogger(__name__)

_PASSAGE_PATTERN = re.compile(r"(THIRD|3RD|ON PASSAGE)", re.IGNORECASE)


def _filter_bills_by_category(
    bill_ids: list[int],
    bill_set: dict,
    chamber: str,
    chamber_matrix: pd.DataFrame,
    chamber_size: int,
    category_flags: list[int],
    issue_code_count: int,
) -> tuple[list[list[int]], list[int]]:
    """Filter bills into category buckets.

    Replaces the first half of eloMonteCarlo.m that assigns bills to categories.

    Args:
        bill_ids: All bill IDs for this chamber.
        bill_set: Dict mapping bill_id → Bill objects.
        chamber: 'house' or 'senate'.
        chamber_matrix: Agreement matrix (for size check).
        chamber_size: Expected chamber size.
        category_flags: List of category codes to include (0 = all).
        issue_code_count: Total number of issue codes.

    Returns:
        Tuple of (category_capture, category_flags_filtered) where
        category_capture[i] is the list of bill IDs for category_flags[i].
    """
    ids = list(chamber_matrix.index)
    chamber_data_attr = f"{chamber}_data"

    # Normalize category flags
    if any(c < 0 for c in category_flags):
        category_flags = list(range(issue_code_count + 1))
    category_flags = sorted(c for c in category_flags if c <= issue_code_count)

    # Initialize category buckets
    category_capture: list[list[int]] = [[] for _ in category_flags]

    for bill_id in bill_ids:
        bill = bill_set.get(bill_id)
        if bill is None or not bill.complete:
            continue

        # Check for passage vote
        chamber_data = getattr(bill, chamber_data_attr, None)
        if chamber_data is None:
            continue

        has_passage = False
        for vote in reversed(chamber_data.chamber_votes):
            desc = vote.description
            if isinstance(desc, list):
                desc = " ".join(str(d) for d in desc)
            if _PASSAGE_PATTERN.search(desc.upper() if desc else ""):
                yes_ids = create_id_strings(vote.yes_list, ids)
                no_ids = create_id_strings(vote.no_list, ids)
                if len(yes_ids) + len(no_ids) >= chamber_size * 0.5:
                    has_passage = True
                break

        if not has_passage:
            continue

        # Assign to matching category buckets
        for i, cat in enumerate(category_flags):
            if cat == 0:
                category_capture[i].append(bill_id)
            elif bill.issue_category == cat:
                category_capture[i].append(bill_id)

    # Remove empty categories
    non_empty = [(cap, flag) for cap, flag in zip(category_capture, category_flags) if cap]
    if non_empty:
        category_capture, category_flags = zip(*non_empty)
        return list(category_capture), list(category_flags)
    return [], []


def elo_monte_carlo(
    bill_ids: list[int],
    bill_set: dict,
    category_flags: list[int],
    chamber_people: pd.DataFrame,
    chamber_sponsor_matrix: pd.DataFrame | None,
    chamber_matrix: pd.DataFrame,
    chamber: str,
    config: ForgeConfig,
    issue_code_count: int = 11,
) -> dict[int, pd.DataFrame]:
    """Run Elo Monte Carlo across categories.

    Replaces @forge/eloMonteCarlo.m. For each category, runs the Elo
    prediction N times with different random seeds and averages the scores.

    Args:
        bill_ids: All bill IDs for this chamber.
        bill_set: Dict mapping bill_id → Bill objects.
        category_flags: Category codes to process (0 = all, negative = all codes).
        chamber_people: People DataFrame for this chamber.
        chamber_sponsor_matrix: Sponsor agreement DataFrame.
        chamber_matrix: Chamber agreement DataFrame.
        chamber: 'house' or 'senate'.
        config: ForgeConfig with MC and Elo parameters.
        issue_code_count: Total number of issue codes.

    Returns:
        Dict mapping category_flag → averaged Elo score DataFrame.
    """
    chamber_size = config.house_size if chamber == "house" else config.senate_size

    # Filter bills into category buckets
    category_capture, filtered_flags = _filter_bills_by_category(
        bill_ids, bill_set, chamber, chamber_matrix, chamber_size,
        category_flags, issue_code_count,
    )

    if not category_capture:
        logger.warning("No valid bills found for any category")
        return {}

    # Log category summary
    logger.info(
        "%s Competitive Bill Impact Analysis - %s - %d MC",
        config.state_id, chamber, config.elo_monte_carlo_number,
    )
    for flag, capture in zip(filtered_flags, category_capture):
        logger.info("Category %d: %d bills", flag, len(capture))

    mc_flag = config.elo_monte_carlo_number > 1
    results: dict[int, pd.DataFrame] = {}

    for cat_idx, cat_flag in enumerate(filtered_flags):
        cat_bill_ids = category_capture[cat_idx]
        logger.info("START Category %d (%d bills)", cat_flag, len(cat_bill_ids))

        # Run MC iterations
        elo_scores: list[pd.DataFrame] = []
        for j in range(config.elo_monte_carlo_number):
            rng = np.random.default_rng(j + 1)  # MATLAB: util.setRandomSeed(j), 1-based
            score = elo_prediction(
                cat_bill_ids, bill_set, chamber_people,
                chamber_sponsor_matrix, chamber_matrix,
                chamber, config, rng=rng,
            )
            if score is not None:
                elo_scores.append(score)

        if not elo_scores:
            logger.warning("No results for category %d", cat_flag)
            continue

        # Average scores across MC iterations
        avg_score = elo_scores[0].copy()
        if len(elo_scores) > 1:
            variable_k_sum = sum(s["score_variable_k"].values for s in elo_scores)
            fixed_k_sum = sum(s["score_fixed_k"].values for s in elo_scores)
            count_sum = sum(s["count"].values for s in elo_scores)

            avg_score["score_variable_k"] = variable_k_sum / len(elo_scores)
            avg_score["score_fixed_k"] = fixed_k_sum / len(elo_scores)
            avg_score["difference"] = avg_score["score_fixed_k"] - avg_score["score_variable_k"]
            avg_score["count"] = count_sum

        results[cat_flag] = avg_score
        logger.info("FINISH Category %d", cat_flag)

    return results
