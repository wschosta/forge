"""Monte Carlo prediction — replaces predictOutcomes.m, runMonteCarlo.m, montecarloPrediction.m.

Runs the Bayesian prediction system across multiple random legislator orderings
to produce robust accuracy estimates.
"""

from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import pandas as pd

from forge.predict.bayes import predict_bill

logger = logging.getLogger(__name__)


def predict_outcomes(
    bill,
    bill_id: int,
    ids: list[str],
    chamber_sponsor_matrix: pd.DataFrame | None,
    chamber_specifics: np.ndarray,
    chamber: str,
    chamber_size: int,
    monte_carlo_number: int = 1,
    bayes_initial: float = 0.5,
) -> dict | None:
    """Predict outcomes for a specific bill with Monte Carlo iterations.

    Replaces @forge/predictOutcomes.m.

    Args:
        bill: A Bill object.
        bill_id: The bill ID.
        ids: List of legislator ID strings.
        chamber_sponsor_matrix: Sponsor agreement DataFrame (or None).
        chamber_specifics: NxN agreement numpy array.
        chamber: 'house' or 'senate'.
        chamber_size: Expected chamber size.
        monte_carlo_number: Number of MC iterations (1 for single pass).
        bayes_initial: Prior probability.

    Returns:
        Dict with keys: 'accuracy_list' (2 x MC array: [accuracy; delta]),
        'legislators_list' (list of legislator ID arrays per iteration),
        'accuracy_steps_list' (list of step-delta arrays per iteration),
        'n_sponsors', 'n_committee'. Returns None if bill is skipped.
    """
    sponsor_values = None
    sponsor_row_names = None
    sponsor_col_names = None
    if chamber_sponsor_matrix is not None and not chamber_sponsor_matrix.empty:
        sponsor_values = chamber_sponsor_matrix.values
        sponsor_row_names = list(chamber_sponsor_matrix.index)
        sponsor_col_names = list(chamber_sponsor_matrix.columns)

    accuracy_list = np.zeros((2, monte_carlo_number))
    legislators_list: list[list[int]] = []
    accuracy_steps_list: list[np.ndarray] = []

    for j in range(monte_carlo_number):
        rng = np.random.default_rng(j + 1)  # Seed with j+1 (MATLAB uses seed = j, 1-based)

        result = predict_bill(
            bill, bill_id, ids,
            sponsor_values, sponsor_row_names, sponsor_col_names,
            chamber_specifics, chamber, chamber_size,
            rng=rng, bayes_initial=bayes_initial,
        )

        if result is None:
            return None

        accuracy = result["final_accuracy"]
        t1_accuracy = result["t1_accuracy"]

        accuracy_list[0, j] = accuracy
        accuracy_list[1, j] = accuracy - t1_accuracy

        # Convert legislator IDs to numeric (strip 'id' prefix)
        leg_ids = [int(lid.replace("id", "")) for lid in result["legislator_order"]]
        legislators_list.append(leg_ids)

        # Compute step deltas
        accuracies = result["accuracies"]
        steps_delta = np.diff(accuracies)
        accuracy_steps_list.append(steps_delta)

    return {
        "accuracy_list": accuracy_list,
        "legislators_list": legislators_list,
        "accuracy_steps_list": accuracy_steps_list,
        "n_sponsors": result["n_sponsors"],
        "n_committee": 0,
    }


def run_monte_carlo(
    bill_ids: list[int],
    bill_set: dict,
    chamber_people: pd.DataFrame,
    chamber_sponsor_matrix: pd.DataFrame | None,
    chamber_matrix: pd.DataFrame,
    chamber: str,
    chamber_size: int,
    monte_carlo_number: int,
    bayes_initial: float = 0.5,
) -> dict:
    """Run Monte Carlo prediction across all bills.

    Replaces @forge/runMonteCarlo.m (without the plotting).

    Args:
        bill_ids: List of bill IDs to process.
        bill_set: Dict mapping bill_id → Bill objects.
        chamber_people: People DataFrame for this chamber.
        chamber_sponsor_matrix: Sponsor agreement DataFrame.
        chamber_matrix: Agreement DataFrame.
        chamber: 'house' or 'senate'.
        chamber_size: Expected chamber size.
        monte_carlo_number: Number of MC iterations.
        bayes_initial: Prior probability.

    Returns:
        Dict with keys: 'accuracy_list' (bills x MC), 'accuracy_delta' (bills x MC),
        'legislators_list' (list per bill), 'accuracy_steps_list' (list of lists),
        'bill_ids' (list of bills that were actually processed).
    """
    ids = list(chamber_matrix.index)
    chamber_specifics = chamber_matrix.values

    result_accuracy: list[np.ndarray] = []
    result_delta: list[np.ndarray] = []
    result_legislators: list[list[list[int]]] = []
    result_steps: list[list[np.ndarray]] = []
    result_bill_ids: list[int] = []

    for bill_id in bill_ids:
        bill = bill_set.get(bill_id)
        if bill is None:
            continue

        out = predict_outcomes(
            bill, bill_id, ids,
            chamber_sponsor_matrix, chamber_specifics,
            chamber, chamber_size, monte_carlo_number, bayes_initial,
        )

        if out is None:
            continue

        result_accuracy.append(out["accuracy_list"][0])
        result_delta.append(out["accuracy_list"][1])
        result_legislators.append(out["legislators_list"])
        result_steps.append(out["accuracy_steps_list"])
        result_bill_ids.append(bill_id)

        logger.info("Bill %d processed (%d/%d)", bill_id, len(result_bill_ids), len(bill_ids))

    if not result_accuracy:
        return {
            "accuracy_list": np.array([]),
            "accuracy_delta": np.array([]),
            "legislators_list": [],
            "accuracy_steps_list": [],
            "bill_ids": [],
        }

    return {
        "accuracy_list": np.array(result_accuracy),
        "accuracy_delta": np.array(result_delta),
        "legislators_list": result_legislators,
        "accuracy_steps_list": result_steps,
        "bill_ids": result_bill_ids,
    }


def monte_carlo_prediction(
    bill_ids: list[int],
    bill_set: dict,
    chamber_people: pd.DataFrame,
    chamber_sponsor_matrix: pd.DataFrame | None,
    chamber_matrix: pd.DataFrame,
    chamber: str,
    chamber_size: int,
    monte_carlo_number: int,
    prediction_directory: str | None = None,
    outputs_directory: str | None = None,
    recompute: bool = True,
    bayes_initial: float = 0.5,
) -> dict:
    """Top-level Monte Carlo prediction entry point with caching.

    Replaces @forge/montecarloPrediction.m.

    Args:
        bill_ids: List of bill IDs to process.
        bill_set: Dict mapping bill_id → Bill objects.
        chamber_people: People DataFrame for this chamber.
        chamber_sponsor_matrix: Sponsor agreement DataFrame.
        chamber_matrix: Agreement DataFrame.
        chamber: 'house' or 'senate'.
        chamber_size: Expected chamber size.
        monte_carlo_number: Number of MC iterations.
        prediction_directory: Directory for saving prediction models.
        outputs_directory: Directory for saving results CSVs.
        recompute: If True, always recompute. If False, use cache.
        bayes_initial: Prior probability.

    Returns:
        Dict from run_monte_carlo with added 'results_table' from impact analysis.
    """
    # TODO: Add caching support (check for existing .pkl files)

    mc_results = run_monte_carlo(
        bill_ids, bill_set, chamber_people,
        chamber_sponsor_matrix, chamber_matrix,
        chamber, chamber_size, monte_carlo_number, bayes_initial,
    )

    # Process legislator impacts
    if mc_results["bill_ids"]:
        from forge.predict.impact import process_legislator_impacts

        results_table = process_legislator_impacts(
            mc_results["accuracy_list"],
            mc_results["accuracy_delta"],
            mc_results["legislators_list"],
            mc_results["accuracy_steps_list"],
            mc_results["bill_ids"],
        )
        mc_results["results_table"] = results_table
        _write_results_table(
            results_table, chamber_people, chamber, monte_carlo_number, outputs_directory
        )
    else:
        mc_results["results_table"] = None

    return mc_results


def _write_results_table(
    results_table: pd.DataFrame | None,
    chamber_people: pd.DataFrame,
    chamber: str,
    monte_carlo_number: int,
    outputs_directory: str | None,
) -> Path | None:
    """Write the per-legislator impact table as MATLAB's results CSV.

    Mirrors montecarloPrediction.m:20. Without this the Monte Carlo run
    computes the impact table, returns it, and leaves nothing on disk — the
    outputs directory ends up empty even though the run reported success.

    Column names and order follow the committed MATLAB outputs:
    ``master_unique_legislators, sponsor_names, coverage, results``. Names are
    resolved from the chamber roster the way getSponsorName.m does; a
    legislator absent from the roster gets an empty name rather than dropping
    the row, so the table stays aligned with the impact scores.

    Args:
        results_table: Per-legislator impact scores, or None.
        chamber_people: Roster used for the run, supplying id → name.
        chamber: 'house' or 'senate'; its initial prefixes the filename.
        monte_carlo_number: Iteration count, recorded in the filename.
        outputs_directory: Destination directory; no file is written if None.

    Returns:
        The path written, or None if there was nothing to write.
    """
    if results_table is None or results_table.empty or outputs_directory is None:
        return None

    table = results_table.rename(columns={"legislator_id": "master_unique_legislators"})

    names: dict[int, str] = {}
    if {"sponsor_id", "name"}.issubset(chamber_people.columns):
        names = {
            int(sid): str(name)
            for sid, name in zip(chamber_people["sponsor_id"], chamber_people["name"])
        }
    table["sponsor_names"] = [names.get(int(i), "") for i in table["master_unique_legislators"]]

    columns = ["master_unique_legislators", "sponsor_names", "coverage", "results"]
    table = table[[c for c in columns if c in table.columns]]

    directory = Path(outputs_directory)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{chamber[0].upper()}_prediction_model_results_m{monte_carlo_number}.csv"
    table.to_csv(path, index=False)
    logger.info("Wrote prediction results: %s (%d legislators)", path, len(table))
    return path
