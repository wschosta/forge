"""Tests for the CSV export module."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.export.writer import write_tables, output_bill_information
from forge.matrices.agreement import MatrixResults
from forge.models.bill import Bill


@pytest.fixture
def sample_results():
    ids = ["id1", "id2", "id3"]
    data = np.array([[1.0, 0.8, 0.3], [0.8, 1.0, 0.5], [0.3, 0.5, 1.0]])
    matrix = pd.DataFrame(data, index=ids, columns=ids)
    votes = pd.DataFrame(np.ones((3, 3)), index=ids, columns=ids)

    return MatrixResults(
        chamber_matrix=matrix,
        chamber_votes=votes,
        chamber_sponsor_matrix=matrix.copy(),
        chamber_sponsor_votes=votes.copy(),
        republicans_chamber_votes=matrix.iloc[:2, :2].copy(),
        democrats_chamber_votes=matrix.iloc[2:, 2:].copy(),
        republicans_chamber_sponsor=matrix.iloc[:2, :2].copy(),
        democrats_chamber_sponsor=matrix.iloc[2:, 2:].copy(),
        bill_ids=[1, 2, 3],
    )


class TestWriteTables:
    def test_writes_chamber_csvs(self, tmp_path, sample_results):
        write_tables(sample_results, tmp_path, "house", category=0)
        assert (tmp_path / "H_cha_A_matrix_0.csv").exists()
        assert (tmp_path / "H_cha_A_votes_0.csv").exists()
        assert (tmp_path / "H_cha_R_votes_0.csv").exists()
        assert (tmp_path / "H_cha_D_votes_0.csv").exists()

    def test_writes_sponsor_csvs(self, tmp_path, sample_results):
        write_tables(sample_results, tmp_path, "senate", category=5)
        assert (tmp_path / "S_cha_A_s_matrix_5.csv").exists()

    def test_creates_directory(self, tmp_path, sample_results):
        subdir = tmp_path / "subdir" / "outputs"
        write_tables(sample_results, subdir, "house", category=0)
        assert subdir.exists()
        assert (subdir / "H_cha_A_matrix_0.csv").exists()

    def test_csv_has_row_names(self, tmp_path, sample_results):
        write_tables(sample_results, tmp_path, "house", category=0)
        df = pd.read_csv(tmp_path / "H_cha_A_matrix_0.csv", index_col=0)
        assert "id1" in df.index


class TestOutputBillInformation:
    def test_writes_bill_csv(self, tmp_path):
        bill_set = {
            1: Bill(bill_id=1, bill_number="HB1", title="Test Bill",
                    issue_category=1, sponsors=[100], date_introduced="2020-01-01"),
            2: Bill(bill_id=2, bill_number="HB2", title="Another Bill",
                    issue_category=4, sponsors=[200]),
        }
        result = output_bill_information(
            bill_set, [1, 2], "house", tmp_path,
        )
        assert result is not None
        assert len(result) == 2
        assert (tmp_path / "house_competitive_bills.csv").exists()

    def test_returns_none_for_empty(self, tmp_path):
        result = output_bill_information({}, [], "house", tmp_path)
        assert result is None

    def test_includes_issue_name(self, tmp_path):
        bill_set = {
            1: Bill(bill_id=1, bill_number="HB1", title="Farm Bill",
                    issue_category=1),
        }
        result = output_bill_information(bill_set, [1], "house", tmp_path)
        assert result.iloc[0]["issue_id"] == "Agriculture"
