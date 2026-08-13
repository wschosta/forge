"""Tests for loading the MATLAB-trained classifier.

The classifier was trained once in MATLAB and its weights committed as
``+la/learning_algorithm_data.mat``. Those exact weights are what the committed
MATLAB outputs were produced from, so being able to load them is what makes the
golden-file comparison a like-for-like test rather than a comparison of two
differently-trained models.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from forge.classify.classifier import classify_bill
from forge.classify.learning import load_matlab_learning_data

MATLAB_CLASSIFIER = Path("+la") / "learning_algorithm_data.mat"


@pytest.fixture(scope="module")
def learning_data():
    if not MATLAB_CLASSIFIER.exists():
        pytest.skip(f"MATLAB classifier not available at {MATLAB_CLASSIFIER}")
    data = load_matlab_learning_data(MATLAB_CLASSIFIER)
    if data is None:
        pytest.skip("MATLAB classifier could not be loaded")
    return data


class TestLoadMatlabLearningData:
    def test_returns_none_for_missing_file(self, tmp_path: Path):
        assert load_matlab_learning_data(tmp_path / "nope.mat") is None

    def test_returns_none_for_unreadable_file(self, tmp_path: Path):
        """A corrupt .mat degrades to an unclassified run, not a crash."""
        bogus = tmp_path / "bogus.mat"
        bogus.write_text("this is not a MAT-file")
        assert load_matlab_learning_data(bogus) is None

    def test_loads_the_eleven_concise_categories(self, learning_data):
        assert learning_data.issue_code_count == 11

    def test_word_vectors_align_with_their_weights(self, learning_data):
        """Each category's vocabulary and weight vector must be parallel arrays.

        classify_bill indexes into weights using positions found in
        description_text, so any length mismatch silently mis-scores a category.
        """
        assert len(learning_data.description_text) == learning_data.issue_code_count
        assert len(learning_data.weights) == learning_data.issue_code_count
        for words, weights in zip(learning_data.description_text, learning_data.weights):
            assert len(words) == len(weights)
            assert len(words) > 0

    def test_carries_the_trained_hyperparameters(self, learning_data):
        """iwv/awv come from the trained file, not the config defaults.

        The committed model was trained at iwv=0.125, which differs from the
        0.13 default in ForgeConfig; loading must not silently substitute one
        for the other.
        """
        assert learning_data.iwv == pytest.approx(0.125)
        assert learning_data.awv == pytest.approx(0.0)

    def test_loads_the_stopword_list(self, learning_data):
        assert len(learning_data.common_words) > 1000
        assert all(isinstance(w, str) for w in learning_data.common_words[:50])


class TestClassifyWithMatlabModel:
    """Spot-checks that the loaded weights actually discriminate.

    These assert the classifier is not degenerate — that it separates obviously
    different subject matter — without pinning exact category numbers beyond
    the few that are unambiguous.
    """

    def test_distinguishes_unrelated_subjects(self, learning_data):
        agriculture = classify_bill("An act concerning agriculture and food safety.", learning_data)[0]
        education = classify_bill("A bill relating to public school education funding.", learning_data)[0]
        assert agriculture != education

    def test_assigns_categories_in_range(self, learning_data):
        titles = [
            "Budget bill.",
            "An act concerning agriculture and food safety.",
            "A bill relating to public school education funding.",
            "An act concerning health insurance coverage.",
        ]
        for title in titles:
            category, _ = classify_bill(title, learning_data)
            assert 1 <= category <= learning_data.issue_code_count

    def test_empty_title_is_unclassifiable(self, learning_data):
        import math

        category, _ = classify_bill("", learning_data)
        assert math.isnan(category)

    def test_title_of_only_stopwords_is_unclassifiable(self, learning_data):
        import math

        category, _ = classify_bill("the of and to a an", learning_data)
        assert math.isnan(category)
