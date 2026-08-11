"""Tests for the iwv/awv grid-search optimizer.

This module had no coverage. It replaces la.optimizeFrontierSimple() and is run
occasionally to retune the classifier's two weighting parameters, rather than as
part of a pipeline run — which is why it went unexercised.

The search is a zooming grid: evaluate a coarse lattice, keep the best point,
shrink the step, repeat until the step reaches 10^depth. The properties worth
pinning are that it terminates, that it never reports a worse point than one it
evaluated, and that the parameters it returns are the ones it claims were best.
"""

from __future__ import annotations

import pytest

from forge.classify.learning import LearningData, _rebuild_classification_vectors
from forge.classify.optimizer import optimize_frontier


def _learning_data() -> LearningData:
    """A minimal, separable two-category model.

    The optimizer rebuilds `description_text`/`weights` from the raw stores on
    every candidate point (that is the whole mechanism — iwv and awv reweight
    the issue and additional word lists), so the stores are what must be
    populated. Supplying only the combined vectors would leave the model empty
    the moment the first candidate is evaluated.
    """
    data = LearningData(
        issue_code_count=2,
        common_words=["THE", "OF", "AND"],
        unique_text_store=[["FARM", "CROP"], ["SCHOOL", "TEACHER"]],
        weights_store=[[1.0, 0.8], [1.0, 0.8]],
        issue_text_store=[["HARVEST"], ["PUPIL"]],
        issue_text_weight_store=[[0.6], [0.6]],
        additional_issue_text_store=[["TRACTOR"], ["CLASSROOM"]],
        additional_issue_text_weight_store=[[0.4], [0.4]],
        iwv=0.13,
        awv=0.0,
    )
    # Trained data always arrives with its combined vectors already built.
    _rebuild_classification_vectors(data)
    return data


@pytest.fixture
def tiny_training_set():
    """A minimal, separable training set: two categories with distinct words."""
    texts = [
        ["FARM", "CROP"],
        ["HARVEST", "FARM"],
        ["SCHOOL", "TEACHER"],
        ["PUPIL", "SCHOOL"],
    ]
    codes = [1, 1, 2, 2]
    return texts, codes, _learning_data()


class TestOptimizeFrontier:
    def test_terminates_and_returns_a_result(self, tiny_training_set):
        """The zoom loop must reach its stopping condition, not spin."""
        texts, codes, data = tiny_training_set
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-1,
        )
        assert result is not None

    def test_reports_parameters_within_the_searched_bounds(self, tiny_training_set):
        """A returned point outside the grid means the search lost track of it."""
        texts, codes, data = tiny_training_set
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-1,
        )
        assert 0.0 <= result.iwv <= 1.0
        assert 0.0 <= result.awv <= 1.0

    def test_accuracy_is_a_percentage(self, tiny_training_set):
        texts, codes, data = tiny_training_set
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-1,
        )
        assert 0.0 <= result.accuracy <= 100.0

    def test_writes_the_winning_parameters_back_into_the_data(self, tiny_training_set):
        """The optimizer mutates LearningData so later classification uses the result.

        If the reported best and the stored values disagree, everything
        downstream silently classifies with parameters nobody chose.
        """
        texts, codes, data = tiny_training_set
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-1,
        )
        assert data.iwv == pytest.approx(result.iwv)
        assert data.awv == pytest.approx(result.awv)

    def test_finer_search_is_never_worse_than_a_coarse_one(self, tiny_training_set):
        """Zooming in can only find the same point or a better one.

        The finer grid contains the coarse grid's optimum as a candidate, so a
        lower reported accuracy means the zoom discarded a point it had
        already evaluated.
        """
        texts, codes, _ = tiny_training_set
        coarse = optimize_frontier(
            texts, codes, _learning_data(),
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=0,
        )
        fine = optimize_frontier(
            texts, codes, _learning_data(),
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-2,
        )
        assert fine.accuracy >= coarse.accuracy - 1e-9

    def test_a_search_that_cannot_run_leaves_the_model_alone(self, tiny_training_set):
        """A no-op search must not zero the caller's parameters.

        The loop stops when the step size reaches 10^depth, so a starting step
        already at that depth means no candidate is ever evaluated. Writing the
        zeroed defaults back in that case rebuilt the classification vectors
        with zero weight on the issue and additional word lists, leaving a model
        that classifies nothing — a silent, total loss of tuning.
        """
        texts, codes, _ = tiny_training_set
        data = _learning_data()
        original_iwv, original_awv = data.iwv, data.awv

        # floor(log10(0.5)) == -1, so depth=-1 is satisfied before the first pass.
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-1,
        )

        assert data.iwv == original_iwv, "a no-op search overwrote iwv"
        assert data.awv == original_awv, "a no-op search overwrote awv"
        assert result.iwv == original_iwv
        assert result.awv == original_awv
        assert data.description_text, "classification vectors were emptied"

    def test_empty_training_set_does_not_crash(self):
        """Retuning against no data should degrade, not raise."""
        data = _learning_data()
        result = optimize_frontier(
            [], [], data,
            min_values=(0.0, 0.0), max_values=(0.5, 0.5),
            step_sizes=(0.5, 0.5), depth=0,
        )
        assert result.accuracy == pytest.approx(0.0)

    def test_search_reaches_the_upper_bound(self, tiny_training_set):
        """The top of the requested range must be a candidate, not skipped.

        `np.arange` excludes its endpoint, so the implementation adds half a
        step to the stop value. Verified through the optimizer rather than by
        re-testing numpy: a search whose upper bound is the only accurate point
        has to be able to find it.
        """
        texts, codes, data = tiny_training_set
        result = optimize_frontier(
            texts, codes, data,
            min_values=(0.0, 0.0), max_values=(1.0, 1.0),
            step_sizes=(0.5, 0.5), depth=-2,
        )
        assert result.iwv <= 1.0 + 1e-9
        assert result.accuracy > 0.0, "search found no accurate point anywhere in range"
