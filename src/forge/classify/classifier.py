"""Bill classifier — replaces +la/classifyBill.m and +la/processAlgorithm.m.

Classifies bills into policy categories based on word-frequency matching
against a trained learning table.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass

import numpy as np

from forge.classify.learning import LearningData
from forge.classify.text_cleanup import cleanup_text
from forge.config import cstr_ainbp

logger = logging.getLogger(__name__)


def classify_bill(
    bill_text: str | list[str],
    data: LearningData,
) -> tuple[int | float, list[float]]:
    """Classify a single bill based on its title/text.

    Replaces la.classifyBill(). Cleans the input text, then scores it against
    each category's learned word vectors by summing the products of learned
    weights and title word weights.

    Note: The MATLAB code had a bug at line 13 referencing ``text`` instead of
    ``clean_title``. This is fixed here.

    Args:
        bill_text: Bill title/text as a string or pre-tokenized list.
        data: Trained learning data.

    Returns:
        Tuple of (category_code, match_scores) where:
            category_code: The predicted category (1-indexed), or NaN if unclassifiable.
            match_scores: Per-category match scores.
    """
    n_categories = data.issue_code_count
    matches = [0.0] * n_categories

    # Clean the input text
    clean_tokens, token_weights = cleanup_text(bill_text, data.common_words)

    # Bug fix: MATLAB checked `isempty(text)` but should check `isempty(clean_title)`
    if not clean_tokens or all(w == 0 for w in token_weights):
        return float("nan"), matches

    for j in range(n_categories):
        if not data.description_text[j]:
            continue

        # Find tokens from the description that appear in the cleaned input
        # cstr_ainbp(description_text, clean_tokens) returns:
        #   (indices in description_text, indices in clean_tokens)
        desc_indices, token_indices = cstr_ainbp(data.description_text[j], clean_tokens)

        if desc_indices:
            # Sum the products: learned_weight[desc_idx] * input_weight[token_idx]
            score = sum(
                data.weights[j][di] * token_weights[ti]
                for di, ti in zip(desc_indices, token_indices)
            )
            matches[j] = score

    # Return the highest-scoring category
    if all(m == 0 for m in matches):
        return float("nan"), matches

    best_idx = int(np.argmax(matches))
    # Category codes are 1-indexed
    return best_idx + 1, matches


@dataclass
class ClassificationResult:
    """Results from batch bill classification."""

    predictions: list[int | float]  # Predicted category per bill
    correct: int = 0
    total: int = 0
    accuracy: float = 0.0


def process_all_bills(
    parsed_texts: list[list[str]],
    actual_codes: list[int],
    data: LearningData,
    concise_flag: bool,
) -> ClassificationResult:
    """Classify all bills and compute accuracy against known labels.

    Replaces la.processAlgorithm().

    Args:
        parsed_texts: Pre-tokenized text for each bill.
        actual_codes: Known correct category codes.
        data: Trained learning data.
        concise_flag: If True, compare against concise codes.

    Returns:
        ClassificationResult with predictions and accuracy statistics.
    """
    predictions: list[int | float] = []

    for text_tokens in parsed_texts:
        predicted, _ = classify_bill(text_tokens, data)
        predictions.append(predicted)

    # Compute accuracy
    correct = 0
    total = 0
    for pred, actual in zip(predictions, actual_codes):
        total += 1
        if not math.isnan(pred) and int(pred) == actual:
            correct += 1

    accuracy = (correct / total * 100) if total > 0 else 0.0

    return ClassificationResult(
        predictions=predictions,
        correct=correct,
        total=total,
        accuracy=accuracy,
    )


def generate_adjacency_matrix(
    actual_codes: list[int],
    predicted_codes: list[int | float],
) -> list[list[int]]:
    """Generate a confusion matrix between actual and predicted categories.

    Replaces la.generateAdjacencyMatrix().

    Args:
        actual_codes: Known correct category codes (1-indexed).
        predicted_codes: Predicted category codes (1-indexed, may contain NaN).

    Returns:
        2D list where [i][j] = count of bills with actual category i+1
        predicted as category j+1.
    """
    n_actual = max(actual_codes) if actual_codes else 0
    n_pred = max(int(p) for p in predicted_codes if not math.isnan(p)) if predicted_codes else 0
    size = max(n_actual, n_pred)

    matrix = [[0] * size for _ in range(size)]
    for actual, predicted in zip(actual_codes, predicted_codes):
        if math.isnan(predicted):
            continue
        row = actual - 1
        col = int(predicted) - 1
        if 0 <= row < size and 0 <= col < size:
            matrix[row][col] += 1

    return matrix
