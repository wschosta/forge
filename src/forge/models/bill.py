"""Bill data model — replaces +util/+templates/getBillTemplate.m."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from forge.models.chamber import ChamberData


@dataclass
class Bill:
    """Represents a single legislative bill and its associated data.

    Fields mirror the MATLAB struct created by getBillTemplate() plus the
    additional fields set during forge.init() processing.
    """

    bill_id: int = 0
    bill_number: str = ""
    title: str = ""
    issue_category: float = float("nan")  # NaN if unclassifiable
    sponsors: list[int] = field(default_factory=list)
    date_introduced: str = ""
    date_last_action: str = ""
    history: pd.DataFrame | None = None

    # Chamber-specific data
    house_data: ChamberData | None = None
    senate_data: ChamberData | None = None

    # Passage status: -1 = no data, 0 = failed, 1 = passed
    passed_house: int = -1
    passed_senate: int = -1
    passed_both: int = -1

    # Flags
    competitive: int = 0
    complete: int = 0
