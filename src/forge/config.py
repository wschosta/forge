"""Configuration constants, state properties, and shared utilities for Forge.

This module replaces:
- @state/state_properties.m (chamber sizes)
- forge.m PARTY_KEY, VOTE_KEY constants
- state.m ISSUE_KEY constant
- +util/createIDstrings.m
- +util/CStrAinBP.mexw64 (case-sensitive string matching)
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


# ---------------------------------------------------------------------------
# State chamber sizes — replaces @state/state_properties.m
# Keys: two-letter state code
# Values: (senate_size, house_size)
# Ranked by Squire legislative professionalism index
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class StateChambers:
    """Chamber sizes for a state legislature."""

    senate_size: int
    house_size: int
    squire_rank: int | None = None


STATE_PROPERTIES: dict[str, StateChambers] = {
    "CA": StateChambers(senate_size=40, house_size=88, squire_rank=1),
    "NY": StateChambers(senate_size=63, house_size=150, squire_rank=2),
    "WI": StateChambers(senate_size=33, house_size=99, squire_rank=3),
    "OH": StateChambers(senate_size=33, house_size=99, squire_rank=7),
    "OR": StateChambers(senate_size=30, house_size=60, squire_rank=25),
    "VT": StateChambers(senate_size=30, house_size=150, squire_rank=26),
    "KY": StateChambers(senate_size=38, house_size=100, squire_rank=27),
    "IN": StateChambers(senate_size=50, house_size=100, squire_rank=41),
    "ME": StateChambers(senate_size=35, house_size=154, squire_rank=42),
    "MT": StateChambers(senate_size=50, house_size=100, squire_rank=43),
    "US": StateChambers(senate_size=100, house_size=435),
}


# ---------------------------------------------------------------------------
# Party mapping — replaces forge.m PARTY_KEY
#
# LegiScan uses: 1=Democrat, 2=Republican
# MATLAB code subtracts 1 to get: 0=Democrat, 1=Republican
# We keep the adjusted values (0-indexed) as the canonical form.
# ---------------------------------------------------------------------------

PARTY_ID_TO_NAME: dict[int, str] = {
    0: "Democrat",
    1: "Republican",
    2: "Independent",
}

PARTY_NAME_TO_ID: dict[str, int] = {v: k for k, v in PARTY_ID_TO_NAME.items()}


# ---------------------------------------------------------------------------
# Vote type mapping — replaces forge.m VOTE_KEY
# ---------------------------------------------------------------------------

VOTE_ID_TO_NAME: dict[int, str] = {
    1: "yea",
    2: "nay",
    3: "absent",
    4: "no vote",
}

VOTE_NAME_TO_ID: dict[str, int] = {v: k for k, v in VOTE_ID_TO_NAME.items()}


# ---------------------------------------------------------------------------
# Issue category mapping — replaces state.m ISSUE_KEY (16 concise categories)
# ---------------------------------------------------------------------------

ISSUE_KEY: dict[int, str] = {
    1: "Agriculture",
    2: "Commerce, Business, Economic Development",
    3: "Courts & Judicial",
    4: "Education",
    5: "Elections & Apportionment",
    6: "Employment & Labor",
    7: "Environment & Natural Resources",
    8: "Family, Children, Human Affairs & Public Health",
    9: "Banks & Financial Institutions",
    10: "Insurance",
    11: "Government & Regulatory Reform",
    12: "Local Government",
    13: "Roads & Transportation",
    14: "Utilities, Energy & Telecommunications",
    15: "Ways & Means, Appropriations",
    16: "Other",
}

# Concise recoding: maps 32 granular categories → 11 concise groups
# Each list element is a list of granular category IDs that map to concise category (1-indexed)
CONCISE_RECODE: list[list[int]] = [
    [1, 2],
    [9, 15, 30],
    [25, 32, 13],
    [26, 10],
    [5, 24, 28],
    [7, 17],
    [4, 27, 29],
    [19, 12, 31],
    [3, 6, 8, 11, 23],
    [16, 20, 21],
    [14, 18, 22],
]


# ---------------------------------------------------------------------------
# Default parameters — replaces hardcoded values across multiple .m files
# ---------------------------------------------------------------------------

@dataclass
class ForgeConfig:
    """All configurable parameters for a Forge pipeline run."""

    state_id: str
    reprocess: bool = False
    recompute: bool = False
    generate_outputs: bool = False
    predict_montecarlo: bool = False
    recompute_montecarlo: bool = False
    predict_elo: bool = False
    recompute_elo: bool = False
    show_warnings: bool = False
    generate_all_categories: bool = True

    # Monte Carlo iterations
    monte_carlo_number: int = 16_000
    elo_monte_carlo_number: int = 15_000

    # Thresholds
    committee_threshold: float = 0.75
    competitive_threshold: float = 0.85
    bayes_initial: float = 0.5

    # Learning algorithm
    cut_off: int = 3001
    iwv: float = 0.13
    awv: float = 0.0

    # Elo
    elo_initial_score: int = 1500
    elo_fixed_k: int = 16
    elo_variable_k_numerator: int = 8000
    elo_variable_k_min_count: int = 200
    elo_variable_k_max_count: int = 800

    # Data reading mode
    json_read: bool = False

    @property
    def senate_size(self) -> int:
        return STATE_PROPERTIES[self.state_id].senate_size

    @property
    def house_size(self) -> int:
        return STATE_PROPERTIES[self.state_id].house_size


# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

def create_id_strings(sponsor_ids: Sequence[int], filter_ids: Sequence[str] | None = None) -> list[str]:
    """Convert numeric sponsor IDs to 'id{N}' string format.

    Replaces +util/createIDstrings.m.

    Args:
        sponsor_ids: Numeric sponsor IDs.
        filter_ids: If provided, only return IDs that appear in this list.

    Returns:
        List of string IDs in 'id{N}' format.
    """
    ids = [f"id{x}" for x in sponsor_ids]
    if filter_ids is not None:
        filter_set = set(filter_ids)
        ids = [x for x in ids if x in filter_set]
    return ids


def cstr_ainbp(a: Sequence[str], b: Sequence[str]) -> tuple[list[int], list[int]]:
    """Find indices of elements in A that appear in B, and their positions in B.

    Replaces +util/CStrAinBP.mexw64 — a case-sensitive string matching MEX binary
    used in ~30 call sites throughout the MATLAB codebase.

    Behavior:
        For each element in A, if it also appears in B, record both indices.
        If an element appears multiple times in B, only the first occurrence is matched.
        Comparison is case-sensitive.

    Args:
        a: First sequence of strings (the "haystack" being indexed).
        b: Second sequence of strings (the "needles" to look for).

    Returns:
        Tuple of (a_indices, b_indices) where:
            a_indices[i] is the index in A of the i-th match
            b_indices[i] is the index in B of the i-th match

    Examples:
        >>> cstr_ainbp(["x", "y", "z"], ["y", "z", "w"])
        ([1, 2], [0, 1])
        >>> cstr_ainbp(["a", "b", "c"], ["d", "e"])
        ([], [])
        >>> cstr_ainbp([], ["a"])
        ([], [])
    """
    # Build lookup from B values to their first index
    b_index: dict[str, int] = {}
    for i, val in enumerate(b):
        if val not in b_index:
            b_index[val] = i

    a_indices: list[int] = []
    b_indices: list[int] = []
    for i, val in enumerate(a):
        if val in b_index:
            a_indices.append(i)
            b_indices.append(b_index[val])

    return a_indices, b_indices
