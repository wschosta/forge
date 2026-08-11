"""Tests for the finance merge module."""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from forge.merge.finance import _build_full_name


class TestBuildFullName:
    def test_basic_name(self):
        row = pd.Series({
            "last_name": "Smith",
            "first_name": "John",
            "middle_name": "",
            "suffix": "",
            "nickname": "",
        })
        result = _build_full_name(row)
        assert result == "SMITH, JOHN"

    def test_with_suffix(self):
        row = pd.Series({
            "last_name": "Smith",
            "first_name": "John",
            "middle_name": "",
            "suffix": "Jr",
            "nickname": "",
        })
        result = _build_full_name(row)
        assert result == "SMITH JR, JOHN"

    def test_with_middle_name(self):
        row = pd.Series({
            "last_name": "Smith",
            "first_name": "John",
            "middle_name": "Michael",
            "suffix": "",
            "nickname": "",
        })
        result = _build_full_name(row)
        assert result == "SMITH, JOHN MICHAEL"

    def test_with_nickname(self):
        row = pd.Series({
            "last_name": "Smith",
            "first_name": "Robert",
            "middle_name": "",
            "suffix": "",
            "nickname": "Bob",
        })
        result = _build_full_name(row)
        assert result == "SMITH, ROBERT (BOB)"

    def test_full_name_with_all_parts(self):
        row = pd.Series({
            "last_name": "Johnson",
            "first_name": "William",
            "middle_name": "James",
            "suffix": "III",
            "nickname": "Bill",
        })
        result = _build_full_name(row)
        assert result == "JOHNSON III, WILLIAM JAMES (BILL)"

    def test_strips_periods(self):
        row = pd.Series({
            "last_name": "St. James",
            "first_name": "J.",
            "middle_name": "",
            "suffix": "Jr.",
            "nickname": "",
        })
        result = _build_full_name(row)
        assert "." not in result

    def test_nan_fields_handled(self):
        row = pd.Series({
            "last_name": "Doe",
            "first_name": "Jane",
            "middle_name": float("nan"),
            "suffix": float("nan"),
            "nickname": float("nan"),
        })
        result = _build_full_name(row)
        assert result == "DOE, JANE"


class TestProcessFinance:
    """Aggregating campaign finance records to one row per legislator.

    Replaces +finance/process.m. Contributions arrive as one row per filing
    period, so the whole point is summing them per person; getting that wrong
    understates or double-counts money raised.
    """

    @staticmethod
    def _write_reduced(finance_dir: Path, rows: list[dict]) -> None:
        finance_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(rows).to_excel(finance_dir / "IN_reduced.xlsx", index=False)

    def test_one_row_per_legislator(self, tmp_path: Path):
        from forge.merge.finance import process_finance

        self._write_reduced(tmp_path, [
            {"name": "SMITH, JOHN", "year": 2012, "raised": 100.0},
            {"name": "SMITH, JOHN", "year": 2014, "raised": 250.0},
            {"name": "JONES, MARY", "year": 2014, "raised": 400.0},
        ])
        result = process_finance("IN", finance_dir=tmp_path)
        assert len(result) == 2

    def test_numeric_columns_are_summed(self, tmp_path: Path):
        from forge.merge.finance import process_finance

        self._write_reduced(tmp_path, [
            {"name": "SMITH, JOHN", "year": 2012, "raised": 100.0},
            {"name": "SMITH, JOHN", "year": 2014, "raised": 250.0},
        ])
        result = process_finance("IN", finance_dir=tmp_path)
        assert result.loc[result["name"] == "SMITH, JOHN", "raised"].iloc[0] == 350.0

    def test_year_count_records_filings_collapsed(self, tmp_path: Path):
        """year_count is how many rows were folded into each legislator."""
        from forge.merge.finance import process_finance

        self._write_reduced(tmp_path, [
            {"name": "SMITH, JOHN", "year": 2012, "raised": 100.0},
            {"name": "SMITH, JOHN", "year": 2014, "raised": 250.0},
            {"name": "JONES, MARY", "year": 2014, "raised": 400.0},
        ])
        result = process_finance("IN", finance_dir=tmp_path)
        assert result.loc[result["name"] == "SMITH, JOHN", "year_count"].iloc[0] == 2
        assert result.loc[result["name"] == "JONES, MARY", "year_count"].iloc[0] == 1

    def test_writes_the_merged_csv(self, tmp_path: Path):
        """The CSV is the input merge_finance_data later reads."""
        from forge.merge.finance import process_finance

        self._write_reduced(tmp_path, [{"name": "SMITH, JOHN", "year": 2012, "raised": 100.0}])
        process_finance("IN", finance_dir=tmp_path)
        assert (tmp_path / "IN_merged_data.csv").exists()

    def test_single_filing_is_left_intact(self, tmp_path: Path):
        from forge.merge.finance import process_finance

        self._write_reduced(tmp_path, [{"name": "SMITH, JOHN", "year": 2012, "raised": 100.0}])
        result = process_finance("IN", finance_dir=tmp_path)
        assert len(result) == 1
        assert result["raised"].iloc[0] == 100.0


class TestMergeFinanceData:
    """Joining aggregated finance onto the Elo outputs.

    Unlike the ideology and seniority merges, which update files in place, this
    one *creates* data/{STATE}/merged_data/ and writes the joined results there.
    That directory is the input the other two then update, which is why they
    fail with "Run finance.merge_finance_data first!" when it is absent.
    """

    @staticmethod
    def _setup(tmp_path: Path, elo_rows: list[dict]):
        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame([
            {"name": "SMITH, JOHN", "raised": 350.0, "year_count": 2},
            {"name": "JONES, MARY", "raised": 400.0, "year_count": 1},
        ]).to_csv(finance_dir / "IN_merged_data.csv", index=False)

        elo_dir = tmp_path / "data" / "IN" / "elo_model"
        elo_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(elo_rows).to_csv(elo_dir / "H_elo_score_0.csv", index=False)
        return finance_dir, elo_dir

    def test_joins_finance_onto_matching_legislators(self, tmp_path: Path):
        from forge.merge.finance import merge_finance_data

        finance_dir, _ = self._setup(tmp_path, [
            {"last_name": "Smith", "first_name": "John", "score_variable_k": 1500},
            {"last_name": "Jones", "first_name": "Mary", "score_variable_k": 1400},
        ])
        merge_finance_data("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

        written = tmp_path / "data" / "IN" / "merged_data" / "H_elo_score_0.csv"
        assert written.exists(), "the join produced no merged_data output"
        result = pd.read_csv(written)
        assert "raised" in result.columns, "finance columns were not joined on"
        assert len(result) == 2

    def test_leaves_files_without_names_alone(self, tmp_path: Path):
        """Only name-keyed outputs participate in the join."""
        from forge.merge.finance import merge_finance_data

        finance_dir, elo_dir = self._setup(tmp_path, [{"bill_id": 1, "value": 2}])
        source = elo_dir / "H_elo_score_0.csv"
        before = source.read_text()

        merge_finance_data("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

        assert source.read_text() == before, "a name-less file was rewritten"
        written = tmp_path / "data" / "IN" / "merged_data" / "H_elo_score_0.csv"
        assert not written.exists(), "a name-less file should produce no merge output"

    def test_case_mismatch_joins_nothing(self, tmp_path: Path):
        """Same case-sensitivity inherited from MATLAB as the other merges.

        _build_full_name uppercases its side; the finance side is used as
        written. A lower-case source silently joins zero rows.
        """
        from forge.merge.finance import merge_finance_data

        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame([{"name": "Smith, John", "raised": 350.0}]).to_csv(
            finance_dir / "IN_merged_data.csv", index=False
        )
        elo_dir = tmp_path / "data" / "IN" / "elo_model"
        elo_dir.mkdir(parents=True, exist_ok=True)
        pd.DataFrame([{"last_name": "Smith", "first_name": "John", "score": 1}]).to_csv(
            elo_dir / "H_elo_score_0.csv", index=False
        )

        merge_finance_data("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

        written = tmp_path / "data" / "IN" / "merged_data" / "H_elo_score_0.csv"
        assert not written.exists(), (
            "a case mismatch joined rows it should not have; both implementations "
            "match names case-sensitively"
        )

    def test_missing_finance_csv_raises(self, tmp_path: Path):
        """process_finance has to run first; the failure should say so."""
        from forge.merge.finance import merge_finance_data

        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir(parents=True, exist_ok=True)
        with pytest.raises((FileNotFoundError, OSError)):
            merge_finance_data("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)
