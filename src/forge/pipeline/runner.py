"""Pipeline orchestrator — replaces state.m:run().

Runs the full Forge analysis pipeline for a given state:
1. Ingest LegiScan CSV data
2. Classify bills using the learning algorithm
3. Build agreement matrices per chamber and category
4. Export CSVs and generate plots
5. Run Monte Carlo predictions (optional)
6. Run Elo ratings (optional)
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from pathlib import Path

import pandas as pd

from forge.classify.classifier import classify_bill
from forge.classify.learning import load_matlab_learning_data
from forge.classify.tfidf_classifier import load_tfidf_classifier
from forge.config import ForgeConfig
from forge.ingest.csv_reader import read_all_csv
from forge.matrices.agreement import process_chamber_votes
from forge.matrices.rollcalls import process_chamber_rollcalls
from forge.models.bill import Bill

logger = logging.getLogger(__name__)


#: Curated roster MATLAB substitutes for LegiScan's people table for the
#: Indiana House (state.m:153-158). Relative to the state's data directory.
INDIANA_HOUSE_ROSTER = Path("undergrad") / "people_2013-2014.xlsx"


def _load_indiana_house_people(state_dir: Path) -> pd.DataFrame | None:
    """Load the hand-curated Indiana House roster MATLAB uses instead of LegiScan.

    Indiana is special-cased in state.m: rather than selecting House members
    from LegiScan's people table, MATLAB reads a curated spreadsheet of the
    2013-2014 chamber. LegiScan's own 2016 roster carries 104 members for a
    100-seat chamber (mid-term replacements are listed alongside the members
    they replaced), so the curated file is what the committed MATLAB House
    outputs were actually built from.

    Unlike the LegiScan path, ``party_id`` here is already 0/1, so it must not
    be decremented again.

    Args:
        state_dir: The state's data directory (e.g. ``data/IN``).

    Returns:
        The roster sorted by party, or None if the file is missing/unreadable.
    """
    roster_path = state_dir / INDIANA_HOUSE_ROSTER
    if not roster_path.exists():
        logger.warning("Indiana House roster not found at %s; falling back to LegiScan", roster_path)
        return None

    try:
        people = pd.read_excel(roster_path)
    except Exception as exc:  # noqa: BLE001 - openpyxl raises many types on a malformed workbook; fall back to LegiScan rather than abort
        logger.warning("Could not read Indiana House roster %s: %s", roster_path, exc)
        return None

    logger.info("Using curated Indiana House roster (%d members) from %s", len(people), roster_path.name)
    return people.sort_values("party_id").reset_index(drop=True)


def _prepare_people(
    people_df: pd.DataFrame,
    state_id: str,
    chamber: str,
    state_dir: Path | None = None,
) -> pd.DataFrame | None:
    """Filter people to a specific chamber and adjust party IDs.

    Replaces the people-selection logic in state.m:run().

    Args:
        people_df: Raw people DataFrame from LegiScan.
        state_id: Two-letter state code.
        chamber: 'house' or 'senate'.
        state_dir: The state's data directory, needed only to locate Indiana's
            curated House roster.

    Returns:
        Filtered people DataFrame for the specified chamber, or None.
    """
    if state_id == "IN" and chamber == "house" and state_dir is not None:
        roster = _load_indiana_house_people(state_dir)
        if roster is not None:
            return roster

    required_cols = {"year", "role_id", "party_id"}
    if not required_cols.issubset(set(people_df.columns)):
        logger.warning("People DataFrame missing required columns: %s", required_cols - set(people_df.columns))
        return None

    # Use the maximum year
    year_select = people_df["year"].max()

    # Adjust party_id: LegiScan uses 1=Dem, 2=Rep; MATLAB subtracts 1
    people = people_df.copy()
    people["party_id"] = people["party_id"] - 1
    people = people.sort_values("party_id")

    # Filter by year and chamber
    select = people[people["year"] == year_select]
    role_id = 1 if chamber == "house" else 2
    chamber_people = select[select["role_id"] == role_id]

    if chamber_people.empty:
        logger.warning("No %s legislators found for year %d", chamber, year_select)
        return None

    return chamber_people.reset_index(drop=True)


def _resolve_classifier(config: ForgeConfig) -> Callable[[str], int | float] | None:
    """Return a title → category function for the configured classifier.

    Choosing between them is a scientific decision, not a detail: the legacy
    scorer leaves roughly 5% of bills unclassified, and those bills are absent
    from every category-filtered matrix as a result. The TF-IDF model always
    produces a category, so switching changes which bills are analysed at all.

    Falls back to the legacy classifier when ``"tfidf"`` is requested but no
    trained model is present, so a fresh checkout still runs — loudly, because
    silently analysing a different set of bills than intended is worse than a
    warning.

    Args:
        config: Pipeline configuration.

    Returns:
        A callable taking a bill title and returning a category code (or NaN),
        or None when no classifier could be loaded at all.
    """
    if config.classifier == "tfidf":
        model = load_tfidf_classifier(config.tfidf_classifier_path)
        if model is not None:
            logger.info(
                "Classifying with the TF-IDF model (%.1f%% held-out accuracy, %d bills)",
                model.accuracy, model.n_training_bills,
            )
            return model.classify
        logger.warning(
            "classifier='tfidf' but no trained model at %s — falling back to the "
            "legacy word-frequency classifier. Run `forge classify` to train one. "
            "Results will differ from a TF-IDF run.",
            config.tfidf_classifier_path,
        )
    elif config.classifier != "legacy":
        raise ValueError(
            f"Unknown classifier {config.classifier!r}; expected 'tfidf' or 'legacy'"
        )

    learning_data = load_matlab_learning_data(config.learning_data_path)
    if learning_data is None:
        logger.warning(
            "No trained classifier available — bills will be unclassified and "
            "all category-filtered matrices will come out empty."
        )
        return None

    logger.info("Classifying with the legacy word-frequency classifier")
    return lambda title: classify_bill(title, learning_data)[0]


def _init_bills(
    bills_df: pd.DataFrame,
    rollcalls_df: pd.DataFrame,
    votes_df: pd.DataFrame,
    sponsors_df: pd.DataFrame,
    history_df: pd.DataFrame | None,
    config: ForgeConfig,
    classify_fn: Callable[[str], int | float] | None = None,
) -> dict[int, Bill]:
    """Initialize bill objects from raw DataFrames.

    Replaces forge.init() + readAllInfo() + addVotes().

    Args:
        bills_df: Bills DataFrame.
        rollcalls_df: Rollcalls DataFrame.
        votes_df: Votes DataFrame.
        sponsors_df: Sponsors DataFrame.
        history_df: History DataFrame (optional).
        config: ForgeConfig.
        classify_fn: Title → category function. When None, bills keep an
            ``issue_category`` of NaN and every category filter downstream
            excludes them — matching MATLAB's ``learning_algorithm_exist``
            guard at forge.m:133.

    Returns:
        Dict mapping bill_id → Bill objects.
    """
    bill_set: dict[int, Bill] = {}

    # Pre-group by bill_id for O(1) lookup instead of O(N) filtering per bill
    sponsors_by_bill = (
        sponsors_df.groupby("bill_id") if sponsors_df is not None and not sponsors_df.empty else {}
    )
    rollcalls_by_bill = rollcalls_df.groupby("bill_id")

    for _, row in bills_df.iterrows():
        bill_id = int(row["bill_id"])
        bill = Bill(
            bill_id=bill_id,
            bill_number=str(row.get("bill_number", "")),
            title=str(row.get("title", "")),
        )

        # Classify the bill by policy area (forge.m:133-136). Every downstream
        # matrix is filtered by issue_category, so skipping this leaves the
        # whole pipeline with nothing to aggregate.
        if classify_fn is not None:
            bill.issue_category = classify_fn(bill.title)

        # Sponsors
        if sponsors_by_bill and "sponsor_id" in sponsors_df.columns:
            try:
                bill_sponsors = sponsors_by_bill.get_group(bill_id)
                bill.sponsors = bill_sponsors["sponsor_id"].tolist()
            except KeyError:
                pass

        # Rollcalls and votes for each chamber, in chronological order.
        #
        # The sort is load-bearing (forge.m:147). A bill's outcome is taken from
        # its *last* chamber vote, and LegiScan orders rollcalls by
        # roll_call_id, which is not chronological once a bill has votes
        # recorded across more than one session file. Without sorting, "last"
        # can be a committee vote or an early reading rather than the final
        # passage vote, which changes the recorded yes-percentage and with it
        # whether the bill counts as competitive at all.
        try:
            bill_rollcalls = rollcalls_by_bill.get_group(bill_id)
            if "date" in bill_rollcalls.columns:
                bill_rollcalls = bill_rollcalls.sort_values("date", kind="stable")
        except KeyError:
            bill_rollcalls = rollcalls_df.iloc[0:0]  # empty DataFrame

        if not bill_rollcalls.empty:
            # Senate
            senate_threshold = config.senate_size * config.committee_threshold
            senate_rolls = bill_rollcalls[bill_rollcalls["total_vote"] <= config.senate_size * 1.5]
            if not senate_rolls.empty:
                bill.senate_data = process_chamber_rollcalls(
                    senate_rolls, votes_df, senate_threshold
                )

            # House
            house_threshold = config.house_size * config.committee_threshold
            house_rolls = bill_rollcalls[bill_rollcalls["total_vote"] > config.senate_size * 1.5]
            if house_rolls.empty:
                house_rolls = bill_rollcalls
            if not house_rolls.empty:
                bill.house_data = process_chamber_rollcalls(
                    house_rolls, votes_df, house_threshold
                )

            # Passage and completeness flags
            for ch in ["house", "senate"]:
                ch_data = getattr(bill, f"{ch}_data")
                if ch_data and ch_data.chamber_votes:
                    pct = ch_data.final_yes_percentage
                    if pct >= 0:
                        setattr(bill, f"passed_{ch}", 1 if pct > 0.5 else 0)
                        # Competitive means the vote was close in *either*
                        # direction, so MATLAB brackets it on both sides
                        # (forge.m:156-157): (1 - threshold) < pct < threshold.
                        # Testing only the upper bound would also admit bills
                        # that failed near-unanimously, which are just as
                        # lopsided as the ones the threshold exists to exclude.
                        ch_data.competitive = int(
                            (1 - config.competitive_threshold) < pct < config.competitive_threshold
                        )

            if bill.passed_house >= 0 or bill.passed_senate >= 0:
                bill.complete = 1

        bill_set[bill_id] = bill

    return bill_set


def run_pipeline(
    config: ForgeConfig,
    legiscan_dir: str | Path = "legiscan_data",
    data_dir: str | Path = "data",
) -> dict:
    """Run the full Forge analysis pipeline for a state.

    Replaces state.m:run().

    Args:
        config: ForgeConfig with all parameters.
        legiscan_dir: Path to legiscan_data directory.
        data_dir: Base path for output data directory.

    Returns:
        Dict with all results: bill_set, matrix_results, prediction results, etc.
    """
    state = config.state_id
    legiscan_dir = Path(legiscan_dir)
    data_dir = Path(data_dir)

    # Output directories
    state_dir = data_dir / state
    outputs_dir = state_dir / "outputs"
    prediction_dir = state_dir / "prediction_model"
    elo_dir = state_dir / "elo_model"
    histogram_dir = outputs_dir / "histograms"

    for d in [state_dir, outputs_dir, prediction_dir, elo_dir, histogram_dir]:
        d.mkdir(parents=True, exist_ok=True)

    logger.info("Starting pipeline for %s", state)

    # Step 1: Ingest data
    logger.info("Reading LegiScan data...")
    bills_df = read_all_csv("bills", state, legiscan_dir)
    people_df = read_all_csv("people", state, legiscan_dir)
    rollcalls_df = read_all_csv("rollcalls", state, legiscan_dir)
    votes_df = read_all_csv("votes", state, legiscan_dir)
    sponsors_df = read_all_csv("sponsors", state, legiscan_dir)

    history_df = None
    try:
        history_df = read_all_csv("history", state, legiscan_dir)
    except Exception:
        pass

    # Step 2: Load the configured classifier (state.m:123 → la.loadLearnedMaterials)
    classify_fn = _resolve_classifier(config)

    # Step 3: Initialize bill objects
    logger.info("Initializing %d bills...", len(bills_df))
    bill_set = _init_bills(
        bills_df, rollcalls_df, votes_df, sponsors_df, history_df, config, classify_fn
    )
    logger.info("Bill set: %d bills", len(bill_set))

    # Step 3: Process each chamber
    results_all: dict = {
        "bill_set": bill_set,
        "house": {},
        "senate": {},
    }

    for chamber in ["house", "senate"]:
        chamber_people = _prepare_people(people_df, state, chamber, state_dir)
        if chamber_people is None:
            logger.info("No %s people found, skipping", chamber)
            continue

        logger.info("Processing %s (%d legislators)...", chamber, len(chamber_people))

        # Categories to process (0 = all, then 1-11)
        categories = list(range(12)) if config.generate_all_categories else [0]

        for category in categories:
            logger.info("  Category %d...", category)

            # Build matrices
            matrix_results = process_chamber_votes(
                bill_set, chamber_people, chamber,
                category=category,
                competitive_threshold=config.competitive_threshold,
                show_warnings=config.show_warnings,
            )

            # Export CSVs
            from forge.export.writer import write_tables
            write_tables(matrix_results, outputs_dir, chamber, category)

            # Generate plots (if outputs requested)
            if config.generate_outputs:
                from forge.viz.plots import plot_runner
                plot_runner(
                    matrix_results, outputs_dir,
                    str(histogram_dir) if config.generate_outputs else None,
                    chamber.capitalize(), category, config.show_warnings,
                )

            # Store results for category 0
            if category == 0:
                results_all[chamber]["matrix_results"] = matrix_results
                results_all[chamber]["people"] = chamber_people
                results_all[chamber]["bill_ids"] = matrix_results.bill_ids

        # Monte Carlo prediction
        if config.predict_montecarlo and chamber in results_all and "matrix_results" in results_all[chamber]:
            logger.info("Running Monte Carlo prediction for %s...", chamber)
            from forge.predict.monte_carlo import monte_carlo_prediction

            mr = results_all[chamber]["matrix_results"]
            mc_results = monte_carlo_prediction(
                mr.bill_ids, bill_set, chamber_people,
                mr.chamber_sponsor_matrix, mr.chamber_matrix,
                chamber, getattr(config, f"{chamber}_size"),
                config.monte_carlo_number,
                str(prediction_dir), str(outputs_dir),
                config.recompute_montecarlo,
            )
            results_all[chamber]["mc_results"] = mc_results

            # Boxplots
            if mc_results["bill_ids"] and config.generate_outputs:
                from forge.viz.plots import plot_prediction_boxplots
                plot_prediction_boxplots(
                    mc_results["accuracy_list"], mc_results["accuracy_delta"],
                    mc_results["bill_ids"], outputs_dir, chamber.capitalize(),
                    config.monte_carlo_number,
                )

        # Elo prediction
        if config.predict_elo and chamber in results_all and "matrix_results" in results_all[chamber]:
            logger.info("Running Elo prediction for %s...", chamber)
            from forge.elo.monte_carlo import elo_monte_carlo

            mr = results_all[chamber]["matrix_results"]
            elo_results = elo_monte_carlo(
                mr.bill_ids, bill_set, [-1],
                chamber_people, mr.chamber_sponsor_matrix, mr.chamber_matrix,
                chamber, config,
            )
            results_all[chamber]["elo_results"] = elo_results

            # Write Elo CSVs
            for cat_flag, elo_df in elo_results.items():
                elo_df.to_csv(
                    elo_dir / f"{chamber[0].upper()}_elo_score_total_{cat_flag}_mc{config.elo_monte_carlo_number}.csv"
                )

    logger.info("Pipeline complete for %s", state)
    return results_all
