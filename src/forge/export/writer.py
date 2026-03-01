"""CSV export — replaces writeTables.m and outputBillInformation.m.

Exports agreement matrices, sponsor matrices, party sub-matrices, and
bill metadata to CSV files compatible with downstream Stata scripts.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd

from forge.config import ISSUE_KEY
from forge.matrices.agreement import MatrixResults

logger = logging.getLogger(__name__)


def write_tables(
    results: MatrixResults,
    outputs_directory: str | Path,
    chamber: str,
    category: int = 0,
) -> None:
    """Export all matrices for one chamber to CSV files.

    Replaces @forge/writeTables.m. Writes chamber, sponsor, committee, party
    sub-matrices, consistency matrix, and seat matrix. File naming follows
    the MATLAB convention: ``{C}_{type}_{category}.csv``.

    Args:
        results: MatrixResults from process_chamber_votes.
        outputs_directory: Directory for CSV files.
        chamber: 'house' or 'senate'.
        category: Issue category number.
    """
    outputs_directory = Path(outputs_directory)
    outputs_directory.mkdir(parents=True, exist_ok=True)

    c = chamber[0].upper()

    def _write(df: pd.DataFrame | None, suffix: str) -> None:
        if df is not None and not df.empty:
            path = outputs_directory / f"{c}_{suffix}_{category}.csv"
            df.to_csv(path)

    # Chamber information
    _write(results.chamber_matrix, "cha_A_matrix")
    _write(results.chamber_votes, "cha_A_votes")
    _write(results.republicans_chamber_votes, "cha_R_votes")
    _write(results.democrats_chamber_votes, "cha_D_votes")

    # Chamber sponsor information
    _write(results.chamber_sponsor_matrix, "cha_A_s_matrix")
    _write(results.chamber_sponsor_votes, "cha_A_s_votes")
    _write(results.republicans_chamber_sponsor, "cha_R_s_votes")
    _write(results.democrats_chamber_sponsor, "cha_D_s_votes")

    # Committee information
    _write(results.committee_matrix, "com_A_matrix")
    _write(results.committee_votes, "com_A_votes")
    _write(results.republicans_committee_votes, "com_R_votes")
    _write(results.democrats_committee_votes, "com_D_votes")

    # Committee sponsor information
    _write(results.committee_sponsor_matrix, "com_A_s_matrix")
    _write(results.committee_sponsor_votes, "com_A_s_votes")
    _write(results.republicans_committee_sponsor, "com_R_s_matrix")
    _write(results.democrats_committee_sponsor, "com_D_s_matrix")

    # Consistency matrix
    if results.consistency_matrix is not None and not results.consistency_matrix.empty:
        if "percentage" in results.consistency_matrix.columns:
            if results.consistency_matrix["percentage"].notna().any():
                _write(results.consistency_matrix, "consistency_matrix")

    # Seat matrix
    _write(results.seat_matrix, "seat_matrix")


def output_bill_information(
    bill_set: dict,
    chamber_bill_ids: list[int],
    chamber: str,
    outputs_directory: str | Path,
    specific_label: str = "Competitive",
    specific_tag: str = "competitive",
    get_sponsor_name=None,
) -> pd.DataFrame | None:
    """Export bill metadata to CSV.

    Replaces @forge/outputBillInformation.m.
    Fixes MATLAB bug: original referenced ``senate_bill_ids`` instead of
    ``chamber_bill_ids`` at line 14.

    Args:
        bill_set: Dict mapping bill_id → Bill objects.
        chamber_bill_ids: List of bill IDs to export.
        chamber: 'house' or 'senate'.
        outputs_directory: Directory for output CSV.
        specific_label: Label for plot titles.
        specific_tag: Tag for file names.
        get_sponsor_name: Optional callable(sponsor_id) → name.

    Returns:
        DataFrame of bill information, or None if empty.
    """
    if not chamber_bill_ids:
        return None

    outputs_directory = Path(outputs_directory)
    outputs_directory.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    for bid in chamber_bill_ids:
        bill = bill_set.get(bid)
        if bill is None:
            continue

        issue_name = ISSUE_KEY.get(int(bill.issue_category), "Unknown") if not (
            isinstance(bill.issue_category, float) and bill.issue_category != bill.issue_category
        ) else "Unknown"

        sponsor_names = ""
        if get_sponsor_name and bill.sponsors:
            names = [get_sponsor_name(s) for s in bill.sponsors]
            sponsor_names = ", ".join(str(n) for n in names if n)

        rows.append({
            "bill_id": bill.bill_id,
            "bill_number": bill.bill_number,
            "title": bill.title,
            "introduced": bill.date_introduced,
            "last_action": bill.date_last_action,
            "issue_id": issue_name,
            "sponsors": sponsor_names,
        })

    if not rows:
        return None

    df = pd.DataFrame(rows)
    df.to_csv(
        outputs_directory / f"{chamber}_{specific_tag}_bills.csv",
        index=False,
    )
    return df
