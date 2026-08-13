"""Learning table generation — replaces +la/generateLearningTable.m and +la/loadLearnedMaterials.m.

Builds per-category word frequency tables from parsed congressional bill data
to train the bill classification system.
"""

from __future__ import annotations

import logging
import pickle
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from forge.classify.text_cleanup import cleanup_text
from forge.config import CONCISE_RECODE

logger = logging.getLogger(__name__)


# Additional manually-chosen "boost" words per category (32 granular categories)
# These are from la.main() in MATLAB
ADDITIONAL_ISSUE_WORDS: dict[int, str] = {
    1: "Tomato corn",
    2: "Cat dog",
    3: "Military troops",
    4: "Movie award",
    5: "black white",
    6: "trade rights",
    7: "government representative",
    8: "police riot",
    9: "econometrics financing",
    10: "school academy",
    11: "fema hurricane",
    12: "power electricity",
    13: "pristine clean",
    14: "children babies",
    15: "feduciary stock",
    16: "world global",
    17: "politics republic",
    18: "medicine hospital",
    19: "neighborhood village",
    20: "migrant visa",
    21: "realism liberalism",
    22: "work jobs",
    23: "tort reform",
    24: "indian born",
    25: "park mine",
    26: "tech",
    27: "historical anthropology",
    28: "benefits handouts",
    29: "fun football",
    30: "taxes tax",
    31: "roads highways",
    32: "river lake",
}


@dataclass
class LearningData:
    """Storage for trained learning algorithm data.

    Replaces the MATLAB ``data_storage`` struct. Contains all the information
    needed to classify new bills without retraining.
    """

    cut_off: int = 3001
    common_words: list[str] = field(default_factory=list)
    master_issue_codes: dict[int, str] = field(default_factory=dict)
    additional_issue_codes: dict[int, str] = field(default_factory=dict)
    issue_code_count: int = 0
    iwv: float = 0.13
    awv: float = 0.0

    # Per-category data (indexed by 0-based position, keyed by category number in dicts)
    description_text: list[list[str]] = field(default_factory=list)
    weights: list[list[float]] = field(default_factory=list)

    # Raw stores (kept for optimizer)
    unique_text_store: list[list[str]] = field(default_factory=list)
    weights_store: list[list[float]] = field(default_factory=list)
    issue_text_store: list[list[str]] = field(default_factory=list)
    issue_text_weight_store: list[list[float]] = field(default_factory=list)
    additional_issue_text_store: list[list[str]] = field(default_factory=list)
    additional_issue_text_weight_store: list[list[float]] = field(default_factory=list)


@dataclass
class LearningMaterials:
    """Parsed and preprocessed bill data for training/evaluation."""

    bill_titles: list[str] = field(default_factory=list)
    unified_texts: list[str] = field(default_factory=list)
    issue_codes: list[int] = field(default_factory=list)
    concise_codes: list[int] = field(default_factory=list)
    parsed_texts: list[list[str]] = field(default_factory=list)
    parsed_titles: list[list[str]] = field(default_factory=list)


def build_concise_code_map() -> dict[int, int]:
    """Build a mapping from granular (1-32) to concise (1-11) category codes."""
    mapping: dict[int, int] = {}
    for concise_idx, granular_group in enumerate(CONCISE_RECODE, start=1):
        for granular_code in granular_group:
            mapping[granular_code] = concise_idx
    return mapping


def generate_learning_table(
    materials: LearningMaterials,
    common_words: list[str],
    issue_codes_map: dict[int, str],
    additional_issue_codes_map: dict[int, str],
    concise_flag: bool,
    iwv: float = 0.13,
    awv: float = 0.0,
    cut_off: int = 3001,
) -> LearningData:
    """Build the learning table from preprocessed training materials.

    Replaces la.generateLearningTable(). For each issue category:
    1. Aggregate all cleaned text from bills in that category
    2. Count word frequencies, normalize by bill count
    3. Truncate to top ``cut_off`` words
    4. Add issue-name words (weighted by iwv) and additional words (weighted by awv)

    Args:
        materials: Preprocessed bill data.
        common_words: Stop word list.
        issue_codes_map: Map from category number to category name.
        additional_issue_codes_map: Map from category number to additional boost words.
        concise_flag: If True, use concise codes; otherwise use granular codes.
        iwv: Issue word value weight.
        awv: Additional word value weight.
        cut_off: Maximum words per category.

    Returns:
        LearningData with all trained parameters.
    """
    if concise_flag:
        code_array = materials.concise_codes
    else:
        code_array = materials.issue_codes

    unique_codes = sorted(set(code_array))
    n_codes = len(unique_codes)

    data = LearningData(
        cut_off=cut_off,
        common_words=common_words,
        master_issue_codes=issue_codes_map,
        additional_issue_codes=additional_issue_codes_map,
        issue_code_count=n_codes,
        iwv=iwv,
        awv=awv,
    )

    # Initialize per-category storage
    data.unique_text_store = [[] for _ in range(n_codes)]
    data.weights_store = [[] for _ in range(n_codes)]
    data.issue_text_store = [[] for _ in range(n_codes)]
    data.issue_text_weight_store = [[] for _ in range(n_codes)]
    data.additional_issue_text_store = [[] for _ in range(n_codes)]
    data.additional_issue_text_weight_store = [[] for _ in range(n_codes)]
    data.description_text = [[] for _ in range(n_codes)]
    data.weights = [[] for _ in range(n_codes)]

    for idx, code in enumerate(unique_codes):
        # Count bills in this category
        bill_count = sum(1 for c in code_array if c == code)
        if bill_count == 0:
            continue

        # Count word frequencies directly from bills in this category
        counts: Counter[str] = Counter(
            token
            for i, c in enumerate(code_array)
            if c == code
            for token in materials.parsed_texts[i]
        )

        # Clean and process issue code name text
        issue_name = issue_codes_map.get(code, "")
        issue_text, issue_text_weight = cleanup_text(issue_name, common_words)

        # Clean and process additional issue text
        additional_text_raw = additional_issue_codes_map.get(code, "")
        additional_text, additional_text_weight = cleanup_text(additional_text_raw, common_words)
        # Sort by frequency descending (matching MATLAB's sort(count, 'descend'))
        sorted_words = sorted(counts.keys(), key=lambda w: counts[w], reverse=True)
        sorted_counts = [counts[w] for w in sorted_words]

        # Normalize by bill count
        weights_raw = [c / bill_count for c in sorted_counts]

        # Truncate to cut_off
        unique_text = sorted_words[:cut_off]
        cat_weights = weights_raw[:cut_off]

        # Store raw data
        data.unique_text_store[idx] = unique_text
        data.weights_store[idx] = cat_weights
        data.issue_text_store[idx] = issue_text
        data.issue_text_weight_store[idx] = issue_text_weight
        # Additional: include top 5 words from unique_text (matching MATLAB line 101)
        top5_text = unique_text[:5]
        top5_weights = cat_weights[:5]
        data.additional_issue_text_store[idx] = additional_text + top5_text
        data.additional_issue_text_weight_store[idx] = additional_text_weight + top5_weights

    # Build combined description_text and weights for classification
    _rebuild_classification_vectors(data, unique_codes)

    return data


def _rebuild_classification_vectors(data: LearningData, unique_codes: list[int] | None = None) -> None:
    """Rebuild the combined description_text and weights arrays from raw stores.

    This matches the MATLAB loop at generateLearningTable.m lines 119-131,
    which combines unique_text + issue_text + additional_text with appropriate
    iwv/awv weighting.
    """
    n = len(data.unique_text_store)
    data.description_text = [[] for _ in range(n)]
    data.weights = [[] for _ in range(n)]

    for k in range(n):
        # Combine: unique_text + issue_text + additional_issue_text
        data.description_text[k] = (
            data.unique_text_store[k]
            + data.issue_text_store[k]
            + data.additional_issue_text_store[k]
        )
        # Combine weights: base_weights + issue_weights*iwv + additional_weights*awv
        combined_weights = list(data.weights_store[k])
        combined_weights.extend(w * data.iwv for w in data.issue_text_weight_store[k])
        combined_weights.extend(w * data.awv for w in data.additional_issue_text_weight_store[k])
        data.weights[k] = combined_weights


def save_learning_data(data: LearningData, path: str | Path) -> None:
    """Save trained learning data to a pickle file."""
    with open(path, "wb") as f:
        pickle.dump(data, f)


def load_learning_data(path: str | Path) -> LearningData | None:
    """Load trained learning data from a pickle file.

    Returns None if the file doesn't exist.
    """
    p = Path(path)
    if not p.exists():
        return None
    with open(p, "rb") as f:
        return pickle.load(f)


def _mat_cell_to_str_list(value: Any) -> list[str]:
    """Coerce a MATLAB cell array of char to a list of Python strings."""
    if value is None:
        return []
    return [str(v) for v in np.atleast_1d(value).ravel().tolist()]


def _mat_cell_to_float_list(value: Any) -> list[float]:
    """Coerce a MATLAB numeric array to a list of Python floats."""
    if value is None:
        return []
    return [float(v) for v in np.atleast_1d(value).ravel().tolist()]


def _mat_nested(value: Any, converter: Any) -> list[list[Any]]:
    """Coerce a MATLAB cell-of-cells into a list of lists via ``converter``."""
    if value is None:
        return []
    return [converter(entry) for entry in np.atleast_1d(value).ravel().tolist()]


def load_matlab_learning_data(path: str | Path) -> LearningData | None:
    """Load the MATLAB-trained classifier from ``+la/learning_algorithm_data.mat``.

    The classifier was trained once in MATLAB and its output committed as a
    ``.mat`` file; retraining from the congressional XML is a separate, much
    more expensive operation. Loading the existing model lets the Python
    pipeline classify bills with the exact weights the MATLAB results were
    produced from, which is what makes golden-file comparison meaningful.

    ``master_issue_codes``/``additional_issue_codes`` are MATLAB
    ``containers.Map`` objects, which serialize as opaque blobs that scipy
    cannot unpack. They hold display labels only and play no part in
    classification, so they are skipped rather than reconstructed.

    Args:
        path: Path to the ``.mat`` file.

    Returns:
        Populated LearningData, or None if the file is absent or unreadable.
    """
    p = Path(path)
    if not p.exists():
        logger.warning("MATLAB learning data not found: %s", p)
        return None

    try:
        import scipy.io as sio

        mat = sio.loadmat(str(p), squeeze_me=True, struct_as_record=False)
    except Exception as exc:  # noqa: BLE001 - scipy raises many types on a malformed .mat; the classifier is optional, so degrade rather than abort
        logger.warning("Could not read MATLAB learning data %s: %s", p, exc)
        return None

    store = mat.get("data_storage")
    if store is None:
        logger.warning("No 'data_storage' struct in %s", p)
        return None

    data = LearningData(
        cut_off=int(getattr(store, "cut_off", 3001)),
        common_words=_mat_cell_to_str_list(getattr(store, "common_words", None)),
        issue_code_count=int(getattr(store, "issue_code_count", 0)),
        iwv=float(getattr(store, "iwv", 0.13)),
        awv=float(getattr(store, "awv", 0.0)),
        description_text=_mat_nested(getattr(store, "description_text", None), _mat_cell_to_str_list),
        weights=_mat_nested(getattr(store, "weights", None), _mat_cell_to_float_list),
    )

    logger.info(
        "Loaded MATLAB classifier from %s: %d categories, iwv=%s, awv=%s",
        p, data.issue_code_count, data.iwv, data.awv,
    )
    return data
