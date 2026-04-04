"""Shor-McCarty ideology score merging — replaces +util/mergeShorMcCarty.m.

Joins Shor-McCarty ideology scores with existing merged data CSVs by
legislator name matching.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd

from forge.merge.finance import _merge_attribute_data

logger = logging.getLogger(__name__)


def merge_shor_mccarty(
    state: str,
    data_dir: str | Path = "data",
    shor_mccarty_dir: str | Path = "shor_mccarty",
) -> None:
    """Join Shor-McCarty ideology scores with merged data CSVs.

    Replaces +util/mergeShorMcCarty.m.

    Args:
        state: Two-letter state code.
        data_dir: Path to the data directory.
        shor_mccarty_dir: Path to the shor_mccarty directory.

    Raises:
        FileNotFoundError: If merged_data directory doesn't exist.
    """
    shor_mccarty_dir = Path(shor_mccarty_dir)
    data_dir = Path(data_dir)

    merged_data = pd.read_csv(shor_mccarty_dir / f"shor_mccarty_{state}.csv")
    merged_data["full_name"] = merged_data.get("name", merged_data.iloc[:, 0])
    for col in ["party", "name"]:
        if col in merged_data.columns:
            merged_data = merged_data.drop(columns=[col])

    merge_data_directory = data_dir / state / "merged_data"
    if not merge_data_directory.is_dir():
        raise FileNotFoundError(
            f"Merged data directory not found: {merge_data_directory}. "
            "Run finance.merge_finance_data first!"
        )

    _merge_attribute_data(merged_data, merge_data_directory, "_shor")
    logger.info("Shor-McCarty merge complete for %s", state)
