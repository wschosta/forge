"""Tests for the TF-IDF replacement classifier.

The word-frequency classifier it replaces scores 42.9% on held-out congressional
bills against a 20.9% majority-class floor; this one scores 84.3% on the same
split. These tests cover the contract rather than the accuracy figure — the
number is reported by `forge classify` and recorded in REFACTORING_PLAN.md,
where it can be re-measured, rather than frozen into an assertion that would
break on any corpus change.
"""

from __future__ import annotations

import math
from pathlib import Path

import pytest

from forge.classify.tfidf_classifier import (
    TfidfClassifier,
    load_tfidf_classifier,
    save_tfidf_classifier,
    train_tfidf_classifier,
)


@pytest.fixture(scope="module")
def trained():
    """A small but genuinely separable three-category corpus."""
    agriculture = [
        "A bill concerning farm subsidies and crop insurance",
        "An act to regulate agricultural pesticide use",
        "Relating to livestock grazing on public rangeland",
        "A bill concerning dairy production quotas",
        "An act regulating grain storage facilities",
        "Relating to farm equipment safety standards",
    ]
    education = [
        "A bill concerning public school funding formulas",
        "An act to establish teacher certification standards",
        "Relating to university tuition assistance programs",
        "A bill concerning school district consolidation",
        "An act regulating charter school authorization",
        "Relating to student assessment requirements",
    ]
    health = [
        "A bill concerning hospital licensing requirements",
        "An act to expand medical insurance coverage",
        "Relating to prescription drug pricing",
        "A bill concerning nursing home inspections",
        "An act regulating physician licensing boards",
        "Relating to public health emergency powers",
    ]
    titles = agriculture + education + health
    categories = [1] * len(agriculture) + [4] * len(education) + [8] * len(health)
    return train_tfidf_classifier(titles, categories, test_size=0.25)


class TestTraining:
    def test_produces_a_trained_model(self, trained):
        assert trained.is_trained
        assert trained.n_training_bills == 18

    def test_records_the_categories_it_can_emit(self, trained):
        assert trained.categories == [1, 4, 8]

    def test_reports_a_held_out_accuracy(self, trained):
        assert 0.0 <= trained.accuracy <= 100.0

    def test_refits_on_all_data_after_scoring(self, trained):
        """The split measures accuracy; the shipped model uses every bill.

        Holding data back from the final model would trade real accuracy for a
        number that is only used for reporting.
        """
        assert trained.n_training_bills == 18

    def test_rejects_empty_input(self):
        with pytest.raises(ValueError, match="no training data"):
            train_tfidf_classifier([], [])

    def test_rejects_mismatched_lengths(self):
        with pytest.raises(ValueError, match="parallel"):
            train_tfidf_classifier(["a title", "another"], [1])

    def test_trains_without_holding_out_on_a_tiny_corpus(self):
        """Too little data to score is a warning, not a failure."""
        model = train_tfidf_classifier(
            ["farm bill", "school bill", "farm subsidy", "school funding"], [1, 4, 1, 4]
        )
        assert model.is_trained
        assert model.accuracy == 0.0, "accuracy cannot be measured without a test split"

    def test_handles_a_class_with_a_single_example(self):
        """Stratifying needs two per class; a thin class must not crash training."""
        titles = [f"farm bill number {i}" for i in range(10)]
        titles += [f"school bill number {i}" for i in range(10)]
        titles.append("a lone bill about maritime shipping")
        categories = [1] * 10 + [4] * 10 + [9]
        model = train_tfidf_classifier(titles, categories)
        assert model.is_trained


class TestClassification:
    def test_separates_distinct_subject_matter(self, trained):
        assert trained.classify("A bill concerning crop irrigation on farms") == 1
        assert trained.classify("An act concerning school teacher salaries") == 4

    def test_only_emits_known_categories(self, trained):
        prediction = trained.classify("An act concerning something entirely unfamiliar")
        assert prediction in trained.categories

    def test_empty_title_is_unclassifiable(self, trained):
        assert math.isnan(trained.classify(""))
        assert math.isnan(trained.classify("   "))

    def test_untrained_model_refuses_to_classify(self):
        with pytest.raises(RuntimeError, match="not trained"):
            TfidfClassifier().classify("a bill")


class TestConfidence:
    """The margin is the closest analogue to the old classifier's NaN.

    A linear model always has a best guess, so unfamiliar vocabulary produces a
    confident-looking label rather than an abstention. The decision margin is
    what lets a caller tell the two apart.
    """

    def test_reports_a_margin(self, trained):
        category, margin = trained.classify_with_confidence(
            "A bill concerning crop irrigation on farms"
        )
        assert category in trained.categories
        assert margin >= 0.0

    def test_familiar_text_scores_a_wider_margin_than_gibberish(self, trained):
        _, familiar = trained.classify_with_confidence(
            "A bill concerning school teacher certification"
        )
        _, unfamiliar = trained.classify_with_confidence("zzzz qqqq xxxx")
        assert familiar > unfamiliar

    def test_empty_title_has_no_margin(self, trained):
        category, margin = trained.classify_with_confidence("")
        assert math.isnan(category)
        assert margin == 0.0


class TestPersistence:
    def test_round_trips(self, trained, tmp_path: Path):
        path = tmp_path / "model.pkl"
        save_tfidf_classifier(trained, path)
        loaded = load_tfidf_classifier(path)

        assert loaded is not None
        assert loaded.categories == trained.categories
        assert loaded.accuracy == trained.accuracy
        title = "A bill concerning crop irrigation on farms"
        assert loaded.classify(title) == trained.classify(title)

    def test_creates_missing_directories(self, trained, tmp_path: Path):
        path = tmp_path / "nested" / "deeper" / "model.pkl"
        save_tfidf_classifier(trained, path)
        assert path.exists()

    def test_missing_file_returns_none(self, tmp_path: Path):
        assert load_tfidf_classifier(tmp_path / "absent.pkl") is None

    def test_unreadable_file_returns_none(self, tmp_path: Path):
        """A corrupt model degrades to unclassified bills, not a crash."""
        path = tmp_path / "broken.pkl"
        path.write_text("this is not a pickle")
        assert load_tfidf_classifier(path) is None

    def test_pickle_of_the_wrong_type_returns_none(self, tmp_path: Path):
        import pickle

        path = tmp_path / "wrong.pkl"
        with open(path, "wb") as handle:
            pickle.dump({"not": "a classifier"}, handle)
        assert load_tfidf_classifier(path) is None

    def test_untrained_model_is_not_loaded(self, tmp_path: Path):
        path = tmp_path / "empty.pkl"
        save_tfidf_classifier(TfidfClassifier(), path)
        assert load_tfidf_classifier(path) is None
