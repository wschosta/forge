"""Visualization — replaces +plot/generatePlots.m, generateHistograms.m, plotRunner.m.

Generates 3D surface plots, flat heatmaps, per-legislator histograms,
and Monte Carlo boxplots using matplotlib/seaborn.
"""

from __future__ import annotations

import logging
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

from forge.config import cstr_ainbp

logger = logging.getLogger(__name__)


def generate_plots(
    people_matrix: pd.DataFrame | None,
    outputs_directory: str | Path,
    histogram_directory: str | Path | None,
    chamber: str,
    specific_label: str,
    x_label: str = "Legislators",
    y_label: str = "Legislators",
    z_label: str = "Agreement Score",
    tag: str = "cha_A_0",
    show_warnings: bool = False,
) -> None:
    """Generate 3D surface + flat heatmap for an agreement matrix.

    Replaces +plot/generatePlots.m.

    Args:
        people_matrix: NxN DataFrame of agreement scores.
        outputs_directory: Directory for saving PNG files.
        histogram_directory: Directory for histograms (None to skip).
        chamber: 'House' or 'Senate'.
        specific_label: Label like '', 'Republicans', 'Democrats', 'Sponsorship'.
        x_label: X-axis label.
        y_label: Y-axis label.
        z_label: Z-axis label.
        tag: File name tag (e.g. 'cha_A_0').
        show_warnings: If True, log warnings for empty matrices.
    """
    if people_matrix is None or people_matrix.empty or people_matrix.shape[0] < 2:
        if show_warnings:
            logger.warning("Empty Matrix %s %s", chamber, specific_label)
        return

    outputs_directory = Path(outputs_directory)
    outputs_directory.mkdir(parents=True, exist_ok=True)

    data = people_matrix.values
    prefix = chamber[0].upper()
    title_str = f"{chamber} {specific_label}".strip()

    # 3D surface plot
    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection="3d")
    x_grid, y_grid = np.meshgrid(range(data.shape[1]), range(data.shape[0]))
    ax.plot_surface(x_grid, y_grid, data, cmap="jet", vmin=0, vmax=1)
    ax.set_title(title_str)
    ax.set_xlabel(x_label)
    ax.set_ylabel(y_label)
    ax.set_zlabel(z_label)
    fig.savefig(outputs_directory / f"{prefix}_{tag}.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Flat heatmap
    fig, ax = plt.subplots(figsize=(10, 8))
    sns.heatmap(data, vmin=0, vmax=1, cmap="jet", ax=ax, square=True)
    ax.set_title(title_str)
    ax.set_xlabel(x_label)
    ax.set_ylabel(y_label)
    fig.savefig(outputs_directory / f"{prefix}_{tag}_flat.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Histograms
    if histogram_directory is not None:
        histogram_directory = Path(histogram_directory)
        histogram_directory.mkdir(parents=True, exist_ok=True)
        generate_histograms(people_matrix, histogram_directory, chamber, specific_label, tag)


def generate_histograms(
    people_matrix: pd.DataFrame,
    save_directory: str | Path,
    chamber: str,
    specific_label: str,
    tag: str,
) -> None:
    """Create per-legislator agreement histograms.

    Replaces +plot/generateHistograms.m.

    Args:
        people_matrix: NxN agreement DataFrame.
        save_directory: Directory for saving histogram PNGs.
        chamber: 'House' or 'Senate'.
        specific_label: Extra label string.
        tag: File name tag.
    """
    save_directory = Path(save_directory)
    prefix = chamber[0].upper()

    rows = list(people_matrix.index)
    cols = list(people_matrix.columns)
    r_i, c_i = cstr_ainbp(rows, cols)

    # Extract diagonal (matching legislators) and set to NaN in matrix
    matrix_copy = people_matrix.copy()
    secondary_plot = []
    for ri, ci in zip(r_i, c_i):
        val = matrix_copy.iloc[ri, ci]
        if not np.isnan(val):
            secondary_plot.append(val)
        matrix_copy.iloc[ri, ci] = np.nan

    # Non-matching values
    main_plot = matrix_copy.values.flatten()
    main_plot = main_plot[~np.isnan(main_plot)]

    # Histogram for non-matching legislators
    if len(main_plot) > 1:
        fig, ax = plt.subplots(figsize=(8, 6))
        ax.hist(main_plot, bins=30, density=True, alpha=0.7, edgecolor="black")
        ax.set_title(f"{chamber} {specific_label} histogram with non-matching legislators")
        ax.set_xlabel("Agreement")
        ax.set_ylabel("Frequency")
        ax.set_xlim(0, 1)
        ax.grid(True, alpha=0.3)
        fig.savefig(save_directory / f"{prefix}_{tag}_histogram_all.png", dpi=150, bbox_inches="tight")
        plt.close(fig)

    # Histogram for matching legislators (self-consistency)
    if len(secondary_plot) > 1:
        fig, ax = plt.subplots(figsize=(8, 6))
        ax.hist(secondary_plot, bins=30, density=True, alpha=0.7, edgecolor="black")
        ax.set_title(f"{chamber} {specific_label} histogram with matching legislators")
        ax.set_xlabel("Agreement")
        ax.set_ylabel("Frequency")
        ax.set_xlim(0, 1)
        ax.grid(True, alpha=0.3)
        fig.savefig(save_directory / f"{prefix}_{tag}_histogram_match.png", dpi=150, bbox_inches="tight")
        plt.close(fig)


def plot_runner(
    results,
    outputs_directory: str | Path,
    histogram_directory: str | Path | None,
    chamber: str,
    category: int = 0,
    show_warnings: bool = False,
) -> None:
    """Generate all plots for one chamber.

    Replaces +plot/plotRunner.m. Orchestrates surface, heatmap, and histogram
    generation for chamber votes, sponsor data, and party sub-matrices.

    Args:
        results: MatrixResults object from process_chamber_votes.
        outputs_directory: Directory for output PNGs.
        histogram_directory: Directory for histogram PNGs (None to skip).
        chamber: 'House' or 'Senate'.
        category: Issue category number.
        show_warnings: If True, log warnings.
    """
    cat_str = str(category)

    # Chamber vote data
    generate_plots(results.chamber_matrix, outputs_directory, histogram_directory,
                   chamber, "", tag=f"cha_A_{cat_str}", show_warnings=show_warnings)
    generate_plots(results.republicans_chamber_votes, outputs_directory, histogram_directory,
                   chamber, "Republicans", tag=f"cha_R_{cat_str}", show_warnings=show_warnings)
    generate_plots(results.democrats_chamber_votes, outputs_directory, histogram_directory,
                   chamber, "Democrats", tag=f"cha_D_{cat_str}", show_warnings=show_warnings)

    # Chamber sponsorship data
    generate_plots(results.chamber_sponsor_matrix, outputs_directory, histogram_directory,
                   chamber, "Sponsorship", x_label="Sponsors", z_label="Sponsorship Score",
                   tag=f"cha_A_s_{cat_str}", show_warnings=show_warnings)
    generate_plots(results.republicans_chamber_sponsor, outputs_directory, histogram_directory,
                   chamber, "Republican Sponsorship", x_label="Sponsors", z_label="Sponsorship Score",
                   tag=f"cha_R_s_{cat_str}", show_warnings=show_warnings)
    generate_plots(results.democrats_chamber_sponsor, outputs_directory, histogram_directory,
                   chamber, "Democrat Sponsorship", x_label="Sponsors", z_label="Sponsorship Score",
                   tag=f"cha_D_s_{cat_str}", show_warnings=show_warnings)


def plot_prediction_boxplots(
    accuracy_list: np.ndarray,
    accuracy_delta: np.ndarray,
    bill_ids: list[int],
    outputs_directory: str | Path,
    chamber: str,
    monte_carlo_number: int,
) -> None:
    """Generate Monte Carlo prediction boxplots.

    Replaces the boxplot generation in runMonteCarlo.m.

    Args:
        accuracy_list: (n_bills, n_mc) array of accuracies.
        accuracy_delta: (n_bills, n_mc) array of accuracy deltas.
        bill_ids: Bill IDs for x-axis labels.
        outputs_directory: Directory for saving PNGs.
        chamber: 'House' or 'Senate'.
        monte_carlo_number: MC iteration count (for filename).
    """
    outputs_directory = Path(outputs_directory)
    outputs_directory.mkdir(parents=True, exist_ok=True)
    prefix = chamber[0].upper()

    if accuracy_list.size == 0:
        return

    # Per-bill accuracy boxplot
    fig, ax = plt.subplots(figsize=(12, 6))
    ax.boxplot(accuracy_list.T, tick_labels=[str(b) for b in bill_ids])
    ax.set_title(f"{chamber} Prediction Boxplot")
    ax.set_xlabel("Bills")
    ax.set_ylabel("Accuracy")
    plt.xticks(rotation=90, fontsize=6)
    fig.savefig(outputs_directory / f"{prefix}_prediction_boxplot_m{monte_carlo_number}.png",
                dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Per-bill delta boxplot
    fig, ax = plt.subplots(figsize=(12, 6))
    ax.boxplot(accuracy_delta.T, tick_labels=[str(b) for b in bill_ids])
    ax.set_title(f"{chamber} Prediction Boxplot - Delta")
    ax.set_xlabel("Bills")
    ax.set_ylabel("Change in Accuracy")
    plt.xticks(rotation=90, fontsize=6)
    fig.savefig(outputs_directory / f"{prefix}_prediction_delta_boxplot_m{monte_carlo_number}.png",
                dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Total accuracy boxplot (all bills combined)
    fig, ax = plt.subplots(figsize=(8, 6))
    ax.boxplot(accuracy_list.flatten())
    ax.set_title(f"{chamber} Total Prediction Boxplot")
    ax.set_xlabel("All Bills")
    ax.set_ylabel("Accuracy")
    fig.savefig(outputs_directory / f"{prefix}_prediction_total_boxplot_m{monte_carlo_number}.png",
                dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Total delta boxplot
    fig, ax = plt.subplots(figsize=(8, 6))
    ax.boxplot(accuracy_delta.flatten())
    ax.set_title(f"{chamber} Total Prediction Boxplot - Delta")
    ax.set_xlabel("All Bills")
    ax.set_ylabel("Change in Accuracy")
    fig.savefig(outputs_directory / f"{prefix}_prediction_total_delta_boxplot_m{monte_carlo_number}.png",
                dpi=150, bbox_inches="tight")
    plt.close(fig)
