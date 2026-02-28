"""LegiScan JSON data reader — replaces forge.readAllInfo().

Reads JSON files from legiscan_data/{state}/{session}/bill/, /vote/, /people/
directories and builds dict structures keyed by ID.

Note: No JSON data currently exists in the repository (only CSV), but this
reader is ported for completeness since the MATLAB code supports it.
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_SESSION_DIR_PATTERN = re.compile(r"(\d+)-(\d+)_.*")
_YEAR_PATTERN = re.compile(r"^(\d+)")


def _read_json_file(path: Path) -> dict[str, Any]:
    """Read a single JSON file, returning the inner object.

    LegiScan JSON files have a single top-level key wrapping the actual data.
    This mirrors +util/readJSON.m which unwraps the first field.
    """
    with open(path) as f:
        data = json.load(f)

    # Unwrap the first (only) top-level key
    if isinstance(data, dict) and len(data) == 1:
        return next(iter(data.values()))
    return data


def _flatten_list_field(obj: dict, field: str) -> list:
    """Flatten a field that may be a list of dicts or a single dict."""
    val = obj.get(field)
    if val is None:
        return []
    if isinstance(val, list):
        return val
    return [val]


def read_all_json(
    state: str,
    legiscan_dir: str | Path = "legiscan_data",
) -> tuple[dict[int, Any], dict[int, Any], dict[int, Any]]:
    """Read all LegiScan JSON data for a state.

    Args:
        state: Two-letter state code.
        legiscan_dir: Path to the legiscan_data directory.

    Returns:
        Tuple of (bills, votes, people) dicts, each keyed by their respective IDs.
    """
    state_dir = Path(legiscan_dir) / state
    if not state_dir.is_dir():
        raise FileNotFoundError(f"State directory not found: {state_dir}")

    bills: dict[int, Any] = {}
    votes: dict[int, Any] = {}
    people: dict[int, Any] = {}

    for session_dir in sorted(state_dir.iterdir()):
        if not session_dir.is_dir() or not _SESSION_DIR_PATTERN.match(session_dir.name):
            continue

        year_match = _YEAR_PATTERN.match(session_dir.name)
        year = int(year_match.group(1)) if year_match else 0

        # --- Bills ---
        bill_dir = session_dir / "bill"
        if bill_dir.is_dir():
            for json_file in sorted(bill_dir.glob("*.json")):
                try:
                    bill = _read_json_file(json_file)
                except (json.JSONDecodeError, OSError) as e:
                    logger.warning("Failed to read %s: %s", json_file, e)
                    continue

                # Flatten nested list fields (matching MATLAB: tmp.history = [tmp.history{:}])
                for field in ("history", "sponsors", "sasts", "subjects", "texts", "votes", "amendments", "supplements", "calendar", "committee"):
                    bill[field] = _flatten_list_field(bill, field)

                bill["passed_house"] = -1
                bill["passed_senate"] = -1

                # Process vote rollcalls for this bill
                house_data = []
                senate_data = []
                vote_master = []

                for vote_ref in bill.get("votes", []):
                    roll_call_id = vote_ref.get("roll_call_id")
                    if not roll_call_id:
                        continue

                    vote_path = session_dir / "vote" / f"{roll_call_id}.json"
                    if not vote_path.exists():
                        continue

                    try:
                        vote_data = _read_json_file(vote_path)
                    except (json.JSONDecodeError, OSError):
                        continue

                    desc = vote_data.get("desc", "")
                    if desc:
                        if desc[0] == "H":
                            house_data.append(vote_data)
                        elif desc[0] == "S":
                            senate_data.append(vote_data)

                        if re.search(r"(THIRD|3RD)", desc.upper()):
                            yea = vote_data.get("yea", 0)
                            nay = vote_data.get("nay", 0)
                            total = yea + nay
                            if desc[0] == "H":
                                bill["passed_house"] = vote_data.get("passed", 0)
                                bill["house_percent"] = yea / total if total > 0 else 0
                            elif desc[0] == "S":
                                bill["passed_senate"] = vote_data.get("passed", 0)
                                bill["senate_percent"] = yea / total if total > 0 else 0

                    vote_master.append(vote_data)

                bill["rollcall"] = vote_master
                bill["house_data"] = house_data
                bill["senate_data"] = senate_data

                if bill["passed_senate"] != -1 and bill["passed_house"] != -1:
                    bill["passed_both"] = int(bool(bill["passed_senate"]) and bool(bill["passed_house"]))

                bill["complete"] = bool(bill.get("committee")) and bool(bill.get("sponsors")) and bool(bill.get("subjects"))

                bill_id = bill.get("bill_id")
                if bill_id is not None:
                    bills[int(bill_id)] = bill

        # --- Votes ---
        vote_dir = session_dir / "vote"
        if vote_dir.is_dir():
            for json_file in sorted(vote_dir.glob("*.json")):
                try:
                    vote = _read_json_file(json_file)
                except (json.JSONDecodeError, OSError):
                    continue
                rcid = vote.get("roll_call_id")
                if rcid is not None:
                    votes[int(rcid)] = vote

        # --- People ---
        people_dir = session_dir / "people"
        if people_dir.is_dir():
            for json_file in sorted(people_dir.glob("*.json")):
                try:
                    person = _read_json_file(json_file)
                except (json.JSONDecodeError, OSError):
                    continue
                pid = person.get("people_id")
                if pid is None:
                    continue
                pid = int(pid)
                if pid in people:
                    # Update last_year for returning legislators
                    people[pid]["last_year"] = year
                else:
                    person["first_year"] = year
                    person["last_year"] = year
                    people[pid] = person

    return bills, votes, people
