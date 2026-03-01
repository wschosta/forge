"""Campaign finance data processing and merging — replaces +finance/process.m and mergeData.m.

Aggregates campaign finance data by legislator and joins it with Elo score CSVs.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

import pandas as pd

from forge.config import cstr_ainbp

logger = logging.getLogger(__name__)


def _build_full_name(row: pd.Series) -> str:
    """Build a standardized full name from legislator name columns.

    Replaces the name-construction loop duplicated across mergeData.m,
    mergeShorMcCarty.m, and mergeSeniority.m.

    Format: ``LASTNAME SUFFIX, FIRST MIDDLE (NICKNAME)``

    Args:
        row: DataFrame row with last_name, first_name, middle_name, suffix, nickname.

    Returns:
        Uppercased, period-stripped full name.
    """
    merged = str(row.get("last_name", ""))

    suffix = row.get("suffix", "")
    if pd.notna(suffix) and str(suffix).strip():
        merged = f"{merged} {suffix}, {row.get('first_name', '')}"
    else:
        merged = f"{merged}, {row.get('first_name', '')}"

    middle = row.get("middle_name", "")
    if pd.notna(middle) and str(middle).strip():
        merged = f"{merged} {middle}"

    nickname = row.get("nickname", "")
    if pd.notna(nickname) and str(nickname).strip():
        merged = f"{merged} ({nickname})"

    # Uppercase and remove periods
    merged = re.sub(r"\.", "", merged).upper()
    return merged


def process_finance(
    state: str,
    finance_dir: str | Path = "finance_data",
) -> pd.DataFrame:
    """Aggregate campaign finance data by legislator.

    Replaces +finance/process.m. Reads the reduced finance spreadsheet,
    aggregates numeric columns by legislator name, and writes merged output.

    Args:
        state: Two-letter state code.
        finance_dir: Path to the finance_data directory.

    Returns:
        Aggregated DataFrame with one row per legislator.
    """
    finance_dir = Path(finance_dir)
    state_data = pd.read_excel(finance_dir / f"{state}_reduced.xlsx")

    names = state_data["name"].unique()
    rows: list[pd.Series] = []

    for name in names:
        matches = state_data[state_data["name"] == name]
        basis = matches.iloc[0].copy()

        # Sum numeric columns (columns 5+ in MATLAB, 0-indexed)
        numeric_cols = matches.select_dtypes(include="number").columns
        for col in numeric_cols:
            basis[col] = matches[col].sum()

        basis["year_count"] = len(matches)
        rows.append(basis)

    compiled = pd.DataFrame(rows)
    compiled.to_csv(finance_dir / f"{state}_merged_data.csv", index=False)
    return compiled


def merge_finance_data(
    state: str,
    data_dir: str | Path = "data",
    finance_dir: str | Path = "finance_data",
) -> None:
    """Join campaign finance data with Elo score CSVs by name.

    Replaces +finance/mergeData.m.

    Args:
        state: Two-letter state code.
        data_dir: Path to the data directory.
        finance_dir: Path to the finance_data directory.
    """
    finance_dir = Path(finance_dir)
    data_dir = Path(data_dir)

    merged_data = pd.read_csv(finance_dir / f"{state}_merged_data.csv")
    if "full_name" not in merged_data.columns:
        merged_data["full_name"] = merged_data.iloc[:, 0]

    # Drop unnecessary columns if they exist
    for col in ["year", "district"]:
        if col in merged_data.columns:
            merged_data = merged_data.drop(columns=[col])

    # Find Elo score CSVs
    elo_dir = data_dir / state / "elo_model"
    mc_dir = elo_dir / "MC"

    output_dir = data_dir / state / "merged_data"
    output_dir.mkdir(parents=True, exist_ok=True)

    file_locations = []
    if elo_dir.exists():
        file_locations.extend(elo_dir.glob("*.csv"))
    if mc_dir.exists():
        file_locations.extend(mc_dir.glob("*.csv"))

    logger.info("Finance data merge for %s: %d files", state, len(file_locations))

    for filepath in file_locations:
        read_file = pd.read_csv(filepath)

        # Build full names from legislator data
        if "last_name" in read_file.columns:
            read_file["full_name"] = read_file.apply(_build_full_name, axis=1)

            # Match by full_name
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
                    suffixes=("", "_finance"),
                )
                total_merge.to_csv(output_dir / filepath.name, index=False)
