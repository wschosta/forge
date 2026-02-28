"""Frontier optimizer for iwv/awv parameters — replaces +la/optimizeFrontierSimple.m.

Performs iterative grid search to find the optimal issue word value (iwv)
and additional word value (awv) parameters for bill classification accuracy.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

from forge.classify.classifier import classify_bill
from forge.classify.learning import LearningData, _rebuild_classification_vectors

logger = logging.getLogger(__name__)


@dataclass
class OptimizationResult:
    """Result of the frontier optimization."""

    accuracy: float
    iwv: float
    awv: float


def optimize_frontier(
    materials_parsed_texts: list[list[str]],
    materials_codes: list[int],
    data: LearningData,
    min_values: tuple[float, float] = (0.0, 0.0),
    max_values: tuple[float, float] = (5.0, 5.0),
    step_sizes: tuple[float, float] = (0.25, 0.25),
    depth: int = -5,
    step_multiplier: float = 0.5,
) -> OptimizationResult:
    """Find optimal iwv/awv parameters via iterative grid search.

    Replaces la.optimizeFrontierSimple(). Starts with a coarse grid,
    finds the best point, then zooms in with finer step sizes until
    the step size reaches ``10^depth``.

    Args:
        materials_parsed_texts: Pre-tokenized text for each training bill.
        materials_codes: Known correct category codes.
        data: LearningData (will be modified with optimal iwv/awv).
        min_values: (iwv_min, awv_min) starting bounds.
        max_values: (iwv_max, awv_max) starting bounds.
        step_sizes: (iwv_step, awv_step) starting step sizes.
        depth: Log10 floor of minimum step size (stopping condition).
        step_multiplier: Step size reduction factor per iteration.

    Returns:
        OptimizationResult with the best accuracy and parameters.
    """
    iwv_min, awv_min = min_values
    iwv_max, awv_max = max_values
    iwv_step, awv_step = step_sizes

    best_accuracy = 0.0
    best_iwv = 0.0
    best_awv = 0.0

    iteration = 0
    while any(
        np.floor(np.log10(s)) != depth for s in [iwv_step, awv_step] if s > 0
    ):
        iwv_array = np.arange(iwv_min, iwv_max + iwv_step / 2, iwv_step)
        awv_array = np.arange(awv_min, awv_max + awv_step / 2, awv_step)

        if len(iwv_array) == 0 or len(awv_array) == 0:
            break

        accuracy_grid = np.full((len(iwv_array), len(awv_array)), np.nan)

        for i, iwv_val in enumerate(iwv_array):
            for j, awv_val in enumerate(awv_array):
                # Update data with new iwv/awv values
                data.iwv = float(iwv_val)
                data.awv = float(awv_val)
                _rebuild_classification_vectors(data)

                # Classify all bills and compute accuracy
                correct = 0
                total = 0
                for text_tokens, actual_code in zip(materials_parsed_texts, materials_codes):
                    predicted, _ = classify_bill(text_tokens, data)
                    total += 1
                    if not np.isnan(predicted) and int(predicted) == actual_code:
                        correct += 1

                accuracy = (correct / total * 100) if total > 0 else 0.0
                accuracy_grid[i, j] = accuracy

                logger.debug("iwv=%.4f awv=%.4f accuracy=%.4f%%", iwv_val, awv_val, accuracy)

        # Find best in this grid
        best_idx = np.unravel_index(np.nanargmax(accuracy_grid), accuracy_grid.shape)
        grid_best_accuracy = accuracy_grid[best_idx]

        if grid_best_accuracy > best_accuracy:
            best_accuracy = grid_best_accuracy
            best_iwv = float(iwv_array[best_idx[0]])
            best_awv = float(awv_array[best_idx[1]])

        # Zoom in around the best point
        if iteration > 0 or True:
            iwv_center = float(iwv_array[best_idx[0]])
            awv_center = float(awv_array[best_idx[1]])
            iwv_min = max(0.0, iwv_center - iwv_step)
            iwv_max = max(0.0, iwv_center + iwv_step)
            awv_min = max(0.0, awv_center - awv_step)
            awv_max = max(0.0, awv_center + awv_step)

        iwv_step *= step_multiplier
        awv_step *= step_multiplier
        iteration += 1

        logger.info(
            "Iteration %d: best=%.4f%% iwv=%.4f awv=%.4f step=%.6f",
            iteration, best_accuracy, best_iwv, best_awv, iwv_step,
        )

    # Set the data to the best values
    data.iwv = best_iwv
    data.awv = best_awv
    _rebuild_classification_vectors(data)

    return OptimizationResult(accuracy=best_accuracy, iwv=best_iwv, awv=best_awv)
