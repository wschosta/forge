"""Tests for forge.ingest.csv_reader."""

from pathlib import Path

import pandas as pd
import pytest

from forge.ingest.csv_reader import read_all_csv


@pytest.fixture
def legiscan_dir() -> Path:
    return Path("legiscan_data")


class TestReadAllCsv:
    """Tests using real Indiana data."""

    def test_reads_bills(self, legiscan_dir: Path):
        df = read_all_csv("bills", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "bill_id" in df.columns
        assert "bill_number" in df.columns
        assert "title" in df.columns
        assert "year" in df.columns

    def test_reads_people(self, legiscan_dir: Path):
        df = read_all_csv("people", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "sponsor_id" in df.columns
        assert "name" in df.columns
        assert "year" in df.columns

    def test_reads_rollcalls(self, legiscan_dir: Path):
        df = read_all_csv("rollcalls", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "bill_id" in df.columns
        assert "roll_call_id" in df.columns
        assert "yea" in df.columns
        assert "nay" in df.columns

    def test_reads_sponsors(self, legiscan_dir: Path):
        df = read_all_csv("sponsors", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "bill_id" in df.columns
        assert "sponsor_id" in df.columns

    def test_reads_votes(self, legiscan_dir: Path):
        df = read_all_csv("votes", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "roll_call_id" in df.columns
        assert "sponsor_id" in df.columns
        assert "vote" in df.columns

    def test_reads_history(self, legiscan_dir: Path):
        df = read_all_csv("history", "IN", legiscan_dir)
        assert isinstance(df, pd.DataFrame)
        assert len(df) > 0
        assert "bill_id" in df.columns
        assert "date" in df.columns
        assert "action" in df.columns

    def test_year_column_has_valid_values(self, legiscan_dir: Path):
        df = read_all_csv("bills", "IN", legiscan_dir)
        years = df["year"].unique()
        assert all(2000 <= y <= 2030 for y in years)

    def test_multiple_sessions_concatenated(self, legiscan_dir: Path):
        df = read_all_csv("bills", "IN", legiscan_dir)
        years = df["year"].unique()
        assert len(years) > 1, "Should have data from multiple sessions"

    def test_schema_differences_handled(self, legiscan_dir: Path):
        """People CSV schema changes between years (2013 has 2 cols, 2016 has 12)."""
        df = read_all_csv("people", "IN", legiscan_dir)
        # All rows should have at minimum sponsor_id and name
        assert not df["sponsor_id"].isna().all()
        assert not df["name"].isna().all()

    def test_invalid_state_raises(self, legiscan_dir: Path):
        with pytest.raises(FileNotFoundError):
            read_all_csv("bills", "NONEXISTENT", legiscan_dir)

    def test_invalid_directory_raises(self):
        with pytest.raises(FileNotFoundError):
            read_all_csv("bills", "IN", "/nonexistent/path")


class TestDerivedRollcallColumns:
    """The tally columns LegiScan does not ship but every consumer expects.

    ``total_vote`` and ``yes_percent`` are computed in MATLAB immediately after
    the rollcall CSVs are read (forge.m:98-99). The raw schema is
    ``bill_id,roll_call_id,date,description,yea,nay,nv``, so a reader that
    returns the file verbatim leaves the chamber-splitting logic reading a
    column that does not exist.
    """

    def test_derives_total_vote_and_yes_percent(self, legiscan_dir: Path):
        df = read_all_csv("rollcalls", "IN", legiscan_dir)
        assert "total_vote" in df.columns
        assert "yes_percent" in df.columns

    def test_total_vote_excludes_not_voting(self, legiscan_dir: Path):
        """MATLAB sums yea + nay only; 'nv' is deliberately excluded."""
        df = read_all_csv("rollcalls", "IN", legiscan_dir).head(500)
        expected = df["yea"] + df["nay"]
        pd.testing.assert_series_equal(
            df["total_vote"], expected, check_names=False, check_dtype=False
        )

    def test_yes_percent_is_a_fraction_of_recorded_votes(self, legiscan_dir: Path):
        df = read_all_csv("rollcalls", "IN", legiscan_dir)
        recorded = df[df["total_vote"] > 0]
        assert ((recorded["yes_percent"] >= 0) & (recorded["yes_percent"] <= 1)).all()

    def test_unanimous_abstention_yields_nan_not_an_exception(self):
        """A rollcall with no yea or nay must not raise on division by zero.

        MATLAB's ``./`` yields NaN here rather than erroring, and such rollcalls
        do occur; the reader has to match that rather than abort the run.
        """
        from forge.ingest.csv_reader import _derive_rollcall_columns

        df = _derive_rollcall_columns(pd.DataFrame({"yea": [0, 3], "nay": [0, 1]}))
        assert df["total_vote"].tolist() == [0, 4]
        assert pd.isna(df["yes_percent"].iloc[0])
        assert df["yes_percent"].iloc[1] == pytest.approx(0.75)

    def test_non_rollcall_subjects_are_untouched(self, legiscan_dir: Path):
        """Only rollcalls gain the derived columns."""
        df = read_all_csv("bills", "IN", legiscan_dir)
        assert "total_vote" not in df.columns
