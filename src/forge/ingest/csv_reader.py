"""LegiScan CSV data reader — replaces forge.readAllFilesOfSubject().

Reads CSV files from legiscan_data/{state}/{session}/csv/ directories,
concatenates across sessions, appends a 'year' column, and handles
schema differences between sessions.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

import pandas as pd

logger = logging.getLogger(__name__)

# Session directory pattern: digits-digits_anything  (e.g. "2013-2013_Regular_Session")
_SESSION_DIR_PATTERN = re.compile(r"(\d+)-(\d+)_.*")

# Year extraction: first digits before the hyphen
_YEAR_PATTERN = re.compile(r"^(\d+)-")


def read_all_csv(
    data_type: str,
    state: str,
    legiscan_dir: str | Path = "legiscan_data",
) -> pd.DataFrame:
    """Read and concatenate LegiScan CSV files across all sessions for a state.

    Iterates over session directories in reverse order (matching MATLAB's
    ``length(list):-1:1`` iteration), reads ``{data_type}.csv`` from each,
    appends a ``year`` column, and concatenates. Handles schema differences
    between sessions by filling missing columns with NaN (numeric) or empty
    string (object/string).

    Args:
        data_type: One of 'bills', 'people', 'rollcalls', 'sponsors', 'votes', 'history'.
        state: Two-letter state code (e.g. 'IN').
        legiscan_dir: Path to the legiscan_data directory.

    Returns:
        Concatenated DataFrame with a ``year`` column.

    Raises:
        FileNotFoundError: If the state directory doesn't exist.
        ValueError: If no session directories are found.
    """
    state_dir = Path(legiscan_dir) / state
    if not state_dir.is_dir():
        raise FileNotFoundError(f"State directory not found: {state_dir}")

    # Find session directories matching the expected pattern
    session_dirs = []
    for entry in sorted(state_dir.iterdir()):
        if entry.is_dir() and _SESSION_DIR_PATTERN.match(entry.name):
            session_dirs.append(entry)

    if not session_dirs:
        raise ValueError(f"No session directories found in {state_dir}")

    # MATLAB iterates in reverse order (length(list):-1:1)
    session_dirs = list(reversed(session_dirs))

    frames: list[pd.DataFrame] = []

    for session_dir in session_dirs:
        csv_path = session_dir / "csv" / f"{data_type}.csv"
        if not csv_path.exists():
            logger.warning("CSV file not found: %s", csv_path)
            continue

        df = pd.read_csv(csv_path)
        if df.empty:
            continue

        # Extract year from directory name (digits before the hyphen)
        year_match = _YEAR_PATTERN.match(session_dir.name)
        if year_match:
            df["year"] = int(year_match.group(1))
        else:
            logger.warning("Could not extract year from directory name: %s", session_dir.name)
            continue

        frames.append(df)

    if not frames:
        return pd.DataFrame()

    # Concatenate, handling schema differences.
    # pandas concat handles missing columns by filling with NaN automatically.
    result = pd.concat(frames, ignore_index=True, sort=False)

    return result
