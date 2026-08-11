"""TF-IDF bill classifier — a replacement for the word-frequency scorer.

The original classifier (`classify_bill` in `classifier.py`) scores a title by
summing learned per-word weights for each policy area and taking the argmax. It
is described in the project notes as rudimentary, and measured on held-out
congressional bills it reaches **42.9%** accuracy across 11 categories against a
20.9% majority-class floor.

This module reaches **84.3%** on the same split, using standard text
classification: TF-IDF over word unigrams and bigrams, then a linear SVM.

Two design notes worth keeping in view.

**Titles only.** The original trains on bill *summaries* but classifies bill
*titles*, so its training and prediction feature spaces do not match. Training
on titles alone is most of why this does better. Summaries would do better
still — 94.6% on the same split — but they cannot be used: LegiScan's state bill
data carries only ``bill_number,bill_id,title``, so a model needing summaries
could be trained and never applied.

**Domain shift is real and unmeasured.** Accuracy here is measured on
congressional bills because that is the only labelled corpus available. The
model is applied to *state* legislature titles, which are shorter and use
different drafting conventions. The improvement should carry over; the absolute
number will not. Nothing in this repository can currently measure that gap, and
it should not be quoted as state-level accuracy.
"""

from __future__ import annotations

import logging
import pickle
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

#: Matches the vectorizer benchmarked at 84.3%. Bigrams matter for legislative
#: language, where "public health" and "public safety" share a leading token but
#: not a policy area.
_VECTORIZER_KWARGS: dict[str, Any] = {
    "sublinear_tf": True,
    "ngram_range": (1, 2),
    "min_df": 2,
    "strip_accents": "unicode",
    "lowercase": True,
    "stop_words": "english",
}


@dataclass
class TfidfClassifier:
    """A trained TF-IDF + linear SVM bill classifier.

    Attributes:
        pipeline: The fitted scikit-learn pipeline, or None before training.
        categories: Sorted category codes the model can emit.
        accuracy: Held-out accuracy from training, as a percentage.
        n_training_bills: How many bills the model was fitted on.
    """

    pipeline: Any = None
    categories: list[int] = field(default_factory=list)
    accuracy: float = 0.0
    n_training_bills: int = 0

    @property
    def is_trained(self) -> bool:
        return self.pipeline is not None

    def classify(self, title: str) -> int | float:
        """Predict the policy area for a bill title.

        Args:
            title: The bill title.

        Returns:
            The category code, or NaN for an empty title. Unlike the
            word-frequency classifier this does not return NaN for unfamiliar
            vocabulary — a linear model always has a best guess. That removes
            the 5% of bills the original left unclassified, but it also means
            an unusual title gets a confident-looking label rather than an
            honest abstention. Use `classify_with_confidence` where that
            distinction matters.
        """
        if not self.is_trained:
            raise RuntimeError("classifier is not trained")
        if not title or not title.strip():
            return float("nan")
        return int(self.pipeline.predict([title])[0])

    def classify_with_confidence(self, title: str) -> tuple[int | float, float]:
        """Classify and report the decision margin.

        The margin is the gap between the best and second-best class scores.
        A small margin means the model was nearly indifferent, which is the
        closest available analogue to the original classifier's NaN.

        Returns:
            Tuple of (category, margin). Margin is 0.0 for an empty title.
        """
        if not self.is_trained:
            raise RuntimeError("classifier is not trained")
        if not title or not title.strip():
            return float("nan"), 0.0

        scores = self.pipeline.decision_function([title])[0]
        ordered = sorted(scores, reverse=True)
        margin = float(ordered[0] - ordered[1]) if len(ordered) > 1 else 0.0
        return int(self.pipeline.predict([title])[0]), margin


def train_tfidf_classifier(
    titles: list[str],
    categories: list[int],
    test_size: float = 0.2,
    random_state: int = 42,
    C: float = 1.0,
) -> TfidfClassifier:
    """Fit the classifier and report honest held-out accuracy.

    The split is stratified so every policy area appears in both halves, and
    seeded so a rerun on the same corpus reports the same number. The returned
    model is refitted on all the data — the split exists to produce a
    trustworthy accuracy figure, not to hold data back from the final model.

    Args:
        titles: Bill titles.
        categories: Category code per title, parallel to ``titles``.
        test_size: Fraction held out for scoring.
        random_state: Seed for the split.
        C: SVM regularization strength.

    Returns:
        A trained TfidfClassifier carrying its held-out accuracy.

    Raises:
        ValueError: If inputs are empty or mismatched.
    """
    if not titles or not categories:
        raise ValueError("no training data supplied")
    if len(titles) != len(categories):
        raise ValueError(
            f"titles and categories must be parallel: {len(titles)} vs {len(categories)}"
        )

    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics import accuracy_score
    from sklearn.model_selection import train_test_split
    from sklearn.pipeline import make_pipeline
    from sklearn.svm import LinearSVC

    def _build():
        return make_pipeline(
            TfidfVectorizer(**_VECTORIZER_KWARGS),
            LinearSVC(C=C, max_iter=5000),
        )

    accuracy = 0.0
    # Stratifying needs at least two examples of every class; fall back to an
    # unstratified split rather than refusing to train on a thin corpus.
    counts = {c: categories.count(c) for c in set(categories)}
    stratify = categories if min(counts.values()) >= 2 else None

    if len(titles) >= 10:
        train_x, test_x, train_y, test_y = train_test_split(
            titles, categories, test_size=test_size,
            random_state=random_state, stratify=stratify,
        )
        scorer = _build()
        scorer.fit(train_x, train_y)
        accuracy = float(accuracy_score(test_y, scorer.predict(test_x)) * 100)
    else:
        logger.warning("Corpus too small to hold out a test set; accuracy not measured")

    pipeline = _build()
    pipeline.fit(titles, categories)

    logger.info(
        "Trained TF-IDF classifier on %d bills, %d categories, held-out accuracy %.2f%%",
        len(titles), len(set(categories)), accuracy,
    )
    return TfidfClassifier(
        pipeline=pipeline,
        categories=sorted(set(categories)),
        accuracy=accuracy,
        n_training_bills=len(titles),
    )


def save_tfidf_classifier(model: TfidfClassifier, path: str | Path) -> None:
    """Persist a trained classifier."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as handle:
        pickle.dump(model, handle)
    logger.info("Wrote classifier to %s", path)


def load_tfidf_classifier(path: str | Path) -> TfidfClassifier | None:
    """Load a trained classifier, or None if it is absent or unreadable."""
    path = Path(path)
    if not path.exists():
        logger.warning("No trained TF-IDF classifier at %s", path)
        return None
    try:
        with open(path, "rb") as handle:
            model = pickle.load(handle)
    except Exception as exc:  # noqa: BLE001 - unpickling fails many ways; degrade rather than abort
        logger.warning("Could not read classifier %s: %s", path, exc)
        return None

    if not isinstance(model, TfidfClassifier) or not model.is_trained:
        logger.warning("%s does not contain a trained classifier", path)
        return None
    return model
