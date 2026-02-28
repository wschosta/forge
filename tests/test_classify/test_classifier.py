"""Tests for forge.classify.classifier."""

import math

from forge.classify.classifier import classify_bill, generate_adjacency_matrix
from forge.classify.learning import LearningData


def _make_simple_learning_data() -> LearningData:
    """Create a minimal LearningData for testing with 3 categories."""
    data = LearningData(
        cut_off=100,
        common_words=["the", "of", "to", "and", "a"],
        master_issue_codes={1: "Agriculture", 2: "Education", 3: "Health"},
        additional_issue_codes={1: "", 2: "", 3: ""},
        issue_code_count=3,
        iwv=0.13,
        awv=0.0,
        description_text=[
            ["FARM", "CROP", "AGRICULTURE", "CORN", "WHEAT", "LIVESTOCK"],
            ["SCHOOL", "EDUCATION", "STUDENT", "TEACHER", "CLASSROOM"],
            ["HOSPITAL", "HEALTH", "MEDICINE", "DOCTOR", "PATIENT"],
        ],
        weights=[
            [2.0, 1.5, 1.0, 0.8, 0.7, 0.5],
            [2.0, 1.5, 1.0, 0.8, 0.7],
            [2.0, 1.5, 1.0, 0.8, 0.7],
        ],
        unique_text_store=[[], [], []],
        weights_store=[[], [], []],
        issue_text_store=[[], [], []],
        issue_text_weight_store=[[0.0], [0.0], [0.0]],
        additional_issue_text_store=[[], [], []],
        additional_issue_text_weight_store=[[0.0], [0.0], [0.0]],
    )
    return data


class TestClassifyBill:
    def test_classifies_agriculture_bill(self):
        data = _make_simple_learning_data()
        category, matches = classify_bill("Farm crop wheat production", data)
        assert category == 1  # Agriculture

    def test_classifies_education_bill(self):
        data = _make_simple_learning_data()
        category, matches = classify_bill("School student education program", data)
        assert category == 2  # Education

    def test_classifies_health_bill(self):
        data = _make_simple_learning_data()
        category, matches = classify_bill("Hospital patient health care medicine", data)
        assert category == 3  # Health

    def test_returns_nan_for_empty_text(self):
        data = _make_simple_learning_data()
        category, _ = classify_bill("", data)
        assert math.isnan(category)

    def test_returns_nan_for_no_matches(self):
        data = _make_simple_learning_data()
        category, _ = classify_bill("xyz qqq zzz", data)
        assert math.isnan(category)

    def test_returns_match_scores(self):
        data = _make_simple_learning_data()
        _, matches = classify_bill("Farm crop", data)
        assert len(matches) == 3
        assert matches[0] > 0  # Agriculture should have positive score
        assert matches[0] > matches[1]  # Agriculture > Education

    def test_accepts_pretokenized_list(self):
        data = _make_simple_learning_data()
        category, _ = classify_bill(["FARM", "CROP", "WHEAT"], data)
        assert category == 1


class TestGenerateAdjacencyMatrix:
    def test_basic(self):
        actual = [1, 1, 2, 2, 3]
        predicted = [1, 2, 2, 2, 3]
        matrix = generate_adjacency_matrix(actual, predicted)
        assert matrix[0][0] == 1  # 1 correct for cat 1
        assert matrix[0][1] == 1  # 1 cat-1 predicted as cat-2
        assert matrix[1][1] == 2  # 2 correct for cat 2
        assert matrix[2][2] == 1  # 1 correct for cat 3

    def test_handles_nan_predictions(self):
        actual = [1, 2]
        predicted = [float("nan"), 2]
        matrix = generate_adjacency_matrix(actual, predicted)
        assert matrix[1][1] == 1
        assert matrix[0][0] == 0  # NaN prediction not counted

    def test_empty_input(self):
        matrix = generate_adjacency_matrix([], [])
        assert matrix == []
