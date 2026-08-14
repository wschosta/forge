"""Elo Monte Carlo orchestrator — replaces eloMonteCarlo.m.

Runs the Elo prediction across multiple random orderings (MC iterations)
and averages the scores. Supports per-category analysis.
"""

from __future__ import annotations

import logging

import numpy as np
import pandas as pd

from forge.checkpoint import Checkpoint
from forge.config import ForgeConfig
from forge.elo.rating import elo_prediction
from forge.predict.bayes import find_passage_vote

logger = logging.getLogger(__name__)


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

        # Check for passage vote using shared helper
        _yes_ids, _no_ids, legislator_list = find_passage_vote(bill, chamber, ids)
        if legislator_list is None or len(legislator_list) < chamber_size * 0.5:
            continue

        # Assign to matching category buckets
        for i, cat in enumerate(category_flags):
            if cat == 0 or bill.issue_category == cat:
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
    checkpoint: Checkpoint | None = None,
    checkpoint_every: int = 100,
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
        checkpoint: Optional store of per-category running sums. When supplied,
            a category resumes at the iteration it reached rather than
            restarting. Exact, because iteration ``j`` is seeded with ``j + 1``.
        checkpoint_every: Iterations between saves. The default trades at most
            100 iterations of lost work against writing a few kilobytes; there
            is no benefit to saving after every one.

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

    results: dict[int, pd.DataFrame] = {}

    for cat_idx, cat_flag in enumerate(filtered_flags):
        cat_bill_ids = category_capture[cat_idx]
        logger.info("START Category %d (%d bills)", cat_flag, len(cat_bill_ids))

        # Iteration j is seeded with j + 1 rather than drawn from a continuing
        # stream, so it yields the same numbers regardless of when it runs. That
        # is what lets a resumed run carry accumulated sums forward and still
        # match an uninterrupted one exactly.
        key = f"elo_{chamber}_m{config.elo_monte_carlo_number}_cat{cat_flag}"
        state = checkpoint.load(key) if checkpoint else None

        if state is not None:
            template = state["template"]
            variable_k_sum = state["variable_k_sum"]
            fixed_k_sum = state["fixed_k_sum"]
            count_sum = state["count_sum"]
            completed = state["completed"]
            contributing = state["contributing"]
            logger.info(
                "Category %d: resuming at iteration %d/%d",
                cat_flag, completed, config.elo_monte_carlo_number,
            )
        else:
            template = None
            variable_k_sum = fixed_k_sum = count_sum = None
            completed = 0
            contributing = 0

        for j in range(completed, config.elo_monte_carlo_number):
            rng = np.random.default_rng(j + 1)  # MATLAB: util.setRandomSeed(j), 1-based
            score = elo_prediction(
                cat_bill_ids, bill_set, chamber_people,
                chamber_sponsor_matrix, chamber_matrix,
                chamber, config, rng=rng,
            )
            if score is not None:
                if template is None:
                    template = score.copy()
                    variable_k_sum = score["score_variable_k"].values.copy()
                    fixed_k_sum = score["score_fixed_k"].values.copy()
                    count_sum = score["count"].values.copy()
                else:
                    variable_k_sum = variable_k_sum + score["score_variable_k"].values
                    fixed_k_sum = fixed_k_sum + score["score_fixed_k"].values
                    count_sum = count_sum + score["count"].values
                contributing += 1

            if checkpoint and (j + 1) % checkpoint_every == 0:
                checkpoint.save(key, {
                    "template": template,
                    "variable_k_sum": variable_k_sum,
                    "fixed_k_sum": fixed_k_sum,
                    "count_sum": count_sum,
                    "completed": j + 1,
                    "contributing": contributing,
                })

        if template is None or not contributing:
            logger.warning("No results for category %d", cat_flag)
            continue

        avg_score = template.copy()
        if contributing > 1:
            avg_score["score_variable_k"] = variable_k_sum / contributing
            avg_score["score_fixed_k"] = fixed_k_sum / contributing
            avg_score["difference"] = avg_score["score_fixed_k"] - avg_score["score_variable_k"]
            avg_score["count"] = count_sum

        results[cat_flag] = avg_score
        if checkpoint:
            checkpoint.save(key, {
                "template": template,
                "variable_k_sum": variable_k_sum,
                "fixed_k_sum": fixed_k_sum,
                "count_sum": count_sum,
                "completed": config.elo_monte_carlo_number,
                "contributing": contributing,
            })
        logger.info("FINISH Category %d", cat_flag)

    return results
