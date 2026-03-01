"""Seniority data merging — replaces +util/mergeSeniority.m.

Joins seniority (terms served) data with existing merged data CSVs
by legislator name matching.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd

from forge.config import cstr_ainbp
from forge.merge.finance import _build_full_name

logger = logging.getLogger(__name__)


def merge_seniority(
    state: str,
    data_dir: str | Path = "data",
    finance_dir: str | Path = "finance_data",
) -> None:
    """Join seniority data with merged data CSVs.

    Replaces +util/mergeSeniority.m.

    Args:
        state: Two-letter state code.
        data_dir: Path to the data directory.
        finance_dir: Path to the finance_data directory.

    Raises:
        FileNotFoundError: If merged_data directory doesn't exist.
    """
    finance_dir = Path(finance_dir)
    data_dir = Path(data_dir)

    merged_data = pd.read_csv(finance_dir / f"seniority_data_{state}.csv")
    merged_data["full_name"] = merged_data.get("candidate", merged_data.iloc[:, 0])
    merged_data["terms_served"] = merged_data.get("cumulative", 0)

    # Drop unnecessary columns
    for col in ["candidate", "cumulative", "chamb", "thirdparty", "democratic", "republican"]:
        if col in merged_data.columns:
            merged_data = merged_data.drop(columns=[col])

    # Keep only the most recent entry per candidate
    if "election_year" in merged_data.columns:
        merged_data = merged_data.sort_values("election_year")
        merged_data = merged_data.drop_duplicates(subset="full_name", keep="last")
        merged_data = merged_data.drop(columns=["election_year"])

    merge_data_directory = data_dir / state / "merged_data"
    if not merge_data_directory.is_dir():
        raise FileNotFoundError(
            f"Merged data directory not found: {merge_data_directory}. "
            "Run finance.merge_finance_data first!"
        )

    for filepath in merge_data_directory.glob("*.csv"):
        read_file = pd.read_csv(filepath)

        if "last_name" in read_file.columns:
            read_file["full_name"] = read_file.apply(_build_full_name, axis=1)

            a_idx, _ = cstr_ainbp(
                merged_data["full_name"].tolist(),
                read_file["full_name"].tolist(),
            )
            b_idx, _ = cstr_ainbp(
                read_file["full_name"].tolist(),
                merged_data["full_name"].tolist(),
            )

            if a_idx and b_idx:
                total_merge = read_file.iloc[b_idx].merge(
                    merged_data.iloc[a_idx],
                    on="full_name",
                    how="inner",
                    suffixes=("", "_seniority"),
                )
                total_merge.to_csv(filepath, index=False)

    logger.info("Seniority merge complete for %s", state)
