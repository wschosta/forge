"""Tests for the LegiScan JSON reader.

This module had no coverage. It is the alternative ingestion path to the CSV
reader (`ForgeConfig.json_read`), and no JSON data is committed to the
repository — every state ships CSVs only — so it has never run against real
input either. These tests build LegiScan's documented JSON shapes.

The reader's two non-obvious behaviours are worth pinning: LegiScan wraps every
payload in a single top-level key that has to be unwrapped, and fields that hold
one item arrive as a bare object rather than a one-element list.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.ingest.json_reader import _flatten_list_field, _read_json_file, read_all_json


class TestReadJsonFile:
    """LegiScan payloads are wrapped in a single top-level key.

    Mirrors +util/readJSON.m, which unwraps the first field.
    """

    def test_unwraps_the_single_top_level_key(self, tmp_path: Path):
        path = tmp_path / "bill.json"
        path.write_text(json.dumps({"bill": {"bill_id": 42, "title": "A bill"}}))
        assert _read_json_file(path) == {"bill_id": 42, "title": "A bill"}

    def test_leaves_multi_key_objects_alone(self, tmp_path: Path):
        """Only a single wrapping key is unwrapped; two keys means real data."""
        payload = {"bill_id": 42, "title": "A bill"}
        path = tmp_path / "bill.json"
        path.write_text(json.dumps(payload))
        assert _read_json_file(path) == payload

    def test_propagates_malformed_json(self, tmp_path: Path):
        """Callers catch JSONDecodeError to skip a file; it must reach them."""
        path = tmp_path / "broken.json"
        path.write_text("{not json")
        with pytest.raises(json.JSONDecodeError):
            _read_json_file(path)


class TestFlattenListField:
    """Single-item fields arrive unwrapped and must still iterate as lists.

    Mirrors MATLAB's ``tmp.history = [tmp.history{:}]``. Downstream code loops
    over these fields, so a bare dict would iterate over its keys instead of
    yielding one record — silently wrong rather than an error.
    """

    def test_list_passes_through(self):
        assert _flatten_list_field({"history": [{"a": 1}, {"a": 2}]}, "history") == [
            {"a": 1},
            {"a": 2},
        ]

    def test_single_object_becomes_a_one_element_list(self):
        assert _flatten_list_field({"history": {"a": 1}}, "history") == [{"a": 1}]

    def test_missing_field_becomes_empty(self):
        assert _flatten_list_field({}, "history") == []

    def test_null_field_becomes_empty(self):
        assert _flatten_list_field({"history": None}, "history") == []


class TestReadAllJson:
    def test_missing_state_directory_raises(self, tmp_path: Path):
        with pytest.raises(FileNotFoundError, match="State directory not found"):
            read_all_json("ZZ", legiscan_dir=tmp_path)

    def test_returns_three_collections(self, tmp_path: Path):
        state_dir = tmp_path / "IN" / "2013-2013_Regular_Session"
        (state_dir / "bill").mkdir(parents=True)
        (state_dir / "bill" / "1.json").write_text(
            json.dumps({"bill": {"bill_id": 1, "bill_number": "HB1", "title": "A bill"}})
        )

        bills, votes, people = read_all_json("IN", legiscan_dir=tmp_path)
        assert isinstance(bills, dict)
        assert isinstance(votes, dict)
        assert isinstance(people, dict)

    def test_ignores_directories_that_are_not_sessions(self, tmp_path: Path):
        """Only directories matching the session naming pattern are read."""
        state_dir = tmp_path / "IN"
        (state_dir / "notes").mkdir(parents=True)
        (state_dir / "notes" / "bill").mkdir()
        (state_dir / "notes" / "bill" / "1.json").write_text(
            json.dumps({"bill": {"bill_id": 999, "title": "Should be ignored"}})
        )

        bills, _, _ = read_all_json("IN", legiscan_dir=tmp_path)
        assert 999 not in bills

    def test_unreadable_bill_is_skipped_not_fatal(self, tmp_path: Path):
        """One corrupt file must not abandon the whole session."""
        state_dir = tmp_path / "IN" / "2013-2013_Regular_Session"
        (state_dir / "bill").mkdir(parents=True)
        (state_dir / "bill" / "broken.json").write_text("{not json")
        (state_dir / "bill" / "good.json").write_text(
            json.dumps({"bill": {"bill_id": 7, "bill_number": "HB7", "title": "Fine"}})
        )

        bills, _, _ = read_all_json("IN", legiscan_dir=tmp_path)
        assert 7 in bills, "a corrupt sibling file lost the readable bill"

    def test_vote_referenced_but_absent_is_tolerated(self, tmp_path: Path):
        """Bills reference rollcalls by id; the file may not have been fetched."""
        state_dir = tmp_path / "IN" / "2013-2013_Regular_Session"
        (state_dir / "bill").mkdir(parents=True)
        (state_dir / "bill" / "1.json").write_text(
            json.dumps(
                {
                    "bill": {
                        "bill_id": 1,
                        "bill_number": "HB1",
                        "title": "A bill",
                        "votes": [{"roll_call_id": 12345}],
                    }
                }
            )
        )

        bills, _, _ = read_all_json("IN", legiscan_dir=tmp_path)
        assert isinstance(bills, dict)
