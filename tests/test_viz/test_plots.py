"""Tests for the visualization module."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.viz.plots import generate_plots, generate_histograms, plot_prediction_boxplots


@pytest.fixture
def sample_matrix():
    ids = ["id1", "id2", "id3"]
    data = np.array([[1.0, 0.8, 0.3], [0.8, 1.0, 0.5], [0.3, 0.5, 1.0]])
    return pd.DataFrame(data, index=ids, columns=ids)


class TestGeneratePlots:
    def test_creates_surface_and_flat_files(self, tmp_path, sample_matrix):
        generate_plots(
            sample_matrix, tmp_path, None,
            "House", "", tag="cha_A_0",
        )
        assert (tmp_path / "H_cha_A_0.png").exists()
        assert (tmp_path / "H_cha_A_0_flat.png").exists()

    def test_creates_histograms_when_dir_given(self, tmp_path, sample_matrix):
        hist_dir = tmp_path / "histograms"
        generate_plots(
            sample_matrix, tmp_path, str(hist_dir),
            "House", "Test", tag="test_0",
        )
        assert hist_dir.exists()

    def test_skips_empty_matrix(self, tmp_path):
        generate_plots(None, tmp_path, None, "House", "", tag="empty")
        assert not list(tmp_path.glob("*.png"))

    def test_skips_small_matrix(self, tmp_path):
        tiny = pd.DataFrame({"id1": [1.0]}, index=["id1"])
        generate_plots(tiny, tmp_path, None, "House", "", tag="tiny")
        assert not list(tmp_path.glob("*.png"))


class TestGenerateHistograms:
    def test_creates_histogram_files(self, tmp_path, sample_matrix):
        generate_histograms(sample_matrix, tmp_path, "House", "Test", "cha_A_0")
        pngs = list(tmp_path.glob("*.png"))
        assert len(pngs) >= 1


class TestPlotPredictionBoxplots:
    def test_creates_boxplot_files(self, tmp_path):
        accuracy = np.random.rand(3, 10) * 100
        delta = np.random.rand(3, 10) * 10
        bill_ids = [101, 102, 103]
        plot_prediction_boxplots(accuracy, delta, bill_ids, tmp_path, "House", 10)
        pngs = list(tmp_path.glob("*.png"))
        assert len(pngs) == 4

    def test_skips_empty_data(self, tmp_path):
        plot_prediction_boxplots(np.array([]), np.array([]), [], tmp_path, "House", 10)
        assert not list(tmp_path.glob("*.png"))
