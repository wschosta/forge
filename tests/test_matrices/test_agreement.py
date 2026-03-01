"""Tests for the agreement matrix module."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd
import pytest

from forge.matrices.agreement import (
    add_votes,
    clean_sponsor_votes,
    clean_votes,
    normalize_votes,
    _create_nan_table,
    _create_zero_table,
    _extract_party_submatrix,
    _process_parties,
)


class TestCreateNanTable:
    def test_square_shape(self):
        matrix, votes = _create_nan_table(["id1", "id2", "id3"])
        assert matrix.shape == (3, 3)
        assert votes.shape == (3, 3)

    def test_all_nan(self):
        matrix, votes = _create_nan_table(["id1", "id2"])
        assert matrix.isna().all().all()
        assert votes.isna().all().all()

    def test_correct_labels(self):
        ids = ["id10", "id20"]
        matrix, _ = _create_nan_table(ids)
        assert list(matrix.index) == ids
        assert list(matrix.columns) == ids

    def test_independent_copies(self):
        matrix, votes = _create_nan_table(["id1"])
        matrix.iloc[0, 0] = 5.0
        assert np.isnan(votes.iloc[0, 0])


class TestCreateZeroTable:
    def test_shape(self):
        df = _create_zero_table(["id1", "id2"], ["count"])
        assert df.shape == (2, 1)
        assert (df.values == 0).all()

    def test_multi_column(self):
        df = _create_zero_table(["id1"], ["a", "b", "c"])
        assert df.shape == (1, 3)


class TestAddVotes:
    def test_nan_to_value(self):
        matrix, _ = _create_nan_table(["id1", "id2"])
        result = add_votes(matrix, ["id1"], ["id2"])
        assert result.loc["id1", "id2"] == 1.0

    def test_increments_existing(self):
        matrix, _ = _create_nan_table(["id1", "id2"])
        matrix = add_votes(matrix, ["id1"], ["id2"])
        matrix = add_votes(matrix, ["id1"], ["id2"])
        assert result_val(matrix, "id1", "id2") == 2.0

    def test_value_zero_for_disagreement(self):
        matrix, _ = _create_nan_table(["id1", "id2"])
        matrix = add_votes(matrix, ["id1"], ["id2"], value=0.0)
        assert result_val(matrix, "id1", "id2") == 0.0

    def test_empty_rows_no_change(self):
        matrix, _ = _create_nan_table(["id1", "id2"])
        result = add_votes(matrix, [], ["id2"])
        assert result.isna().all().all()

    def test_empty_cols_no_change(self):
        matrix, _ = _create_nan_table(["id1", "id2"])
        result = add_votes(matrix, ["id1"], [])
        assert result.isna().all().all()

    def test_multiple_rows_and_cols(self):
        ids = ["id1", "id2", "id3"]
        matrix, _ = _create_nan_table(ids)
        matrix = add_votes(matrix, ["id1", "id2"], ["id1", "id2"])
        # Should set (id1,id1), (id1,id2), (id2,id1), (id2,id2)
        assert result_val(matrix, "id1", "id1") == 1.0
        assert result_val(matrix, "id1", "id2") == 1.0
        assert result_val(matrix, "id2", "id1") == 1.0
        assert result_val(matrix, "id2", "id2") == 1.0
        assert np.isnan(result_val(matrix, "id3", "id3"))

    def test_agreement_disagreement_pattern(self):
        """Test the actual agreement pattern: yes-yes=1, yes-no=0, then normalize."""
        ids = ["id1", "id2", "id3"]
        matrix, _ = _create_nan_table(ids)
        votes_mat, _ = _create_nan_table(ids)

        yes_ids = ["id1", "id2"]
        no_ids = ["id3"]

        # Agreement
        matrix = add_votes(matrix, yes_ids, yes_ids)
        matrix = add_votes(matrix, no_ids, no_ids)
        matrix = add_votes(matrix, yes_ids, no_ids, value=0.0)
        matrix = add_votes(matrix, no_ids, yes_ids, value=0.0)

        # Possible votes
        all_voting = yes_ids + no_ids
        votes_mat = add_votes(votes_mat, all_voting, all_voting)

        # Check agreement values
        assert result_val(matrix, "id1", "id2") == 1.0  # both yes
        assert result_val(matrix, "id1", "id3") == 0.0  # yes vs no
        assert result_val(matrix, "id3", "id3") == 1.0  # both no (self)


class TestCleanVotes:
    def test_removes_all_nan_rows(self):
        ids = ["id1", "id2", "id3"]
        matrix, _ = _create_nan_table(ids)
        votes_mat, _ = _create_nan_table(ids)

        # Give id1 and id2 some values
        matrix.loc["id1", "id2"] = 1.0
        matrix.loc["id2", "id1"] = 1.0
        votes_mat.loc["id1", "id2"] = 1.0
        votes_mat.loc["id2", "id1"] = 1.0

        cleaned_matrix, cleaned_votes = clean_votes(matrix, votes_mat)
        assert "id3" not in cleaned_matrix.index
        assert "id3" not in cleaned_matrix.columns
        assert "id1" in cleaned_matrix.index

    def test_empty_matrix(self):
        empty_df = pd.DataFrame()
        result_m, result_v = clean_votes(empty_df, empty_df)
        assert result_m.empty

    def test_none_matrix(self):
        result_m, result_v = clean_votes(None, None)
        assert result_m is None


class TestCleanSponsorVotes:
    def test_removes_low_sponsors(self):
        ids = ["id1", "id2", "id3"]
        matrix = pd.DataFrame(
            np.ones((3, 3)),
            index=ids,
            columns=ids,
        )
        votes_mat = pd.DataFrame(
            np.ones((3, 3)),
            index=ids,
            columns=ids,
        )
        # Sponsorship counts: id3 has very few
        sponsorship_counts = pd.DataFrame(
            {"count": [10, 10, 0]},
            index=ids,
        )

        cleaned_matrix, _ = clean_sponsor_votes(matrix, votes_mat, sponsorship_counts)
        # id3 should be removed from columns (count 0 < mean - std/2)
        assert "id3" not in cleaned_matrix.columns


class TestNormalizeVotes:
    def test_basic_normalization(self):
        ids = ["id1", "id2"]
        people = pd.DataFrame(
            [[2.0, 1.0], [1.0, 4.0]],
            index=ids,
            columns=ids,
        )
        votes = pd.DataFrame(
            [[4.0, 2.0], [2.0, 4.0]],
            index=ids,
            columns=ids,
        )
        result = normalize_votes(people, votes)
        assert result.loc["id1", "id1"] == pytest.approx(0.5)
        assert result.loc["id1", "id2"] == pytest.approx(0.5)
        assert result.loc["id2", "id2"] == pytest.approx(1.0)

    def test_empty_returns_self(self):
        result = normalize_votes(pd.DataFrame(), pd.DataFrame())
        assert result.empty

    def test_none_returns_none(self):
        result = normalize_votes(None, None)
        assert result is None


class TestProcessParties:
    def test_splits_correctly(self):
        people = pd.DataFrame({
            "sponsor_id": [100, 200, 300, 400],
            "party_id": [1, 0, 1, 0],
        })
        repubs, dems = _process_parties(people)
        assert "id100" in repubs
        assert "id300" in repubs
        assert "id200" in dems
        assert "id400" in dems


class TestExtractPartySubmatrix:
    def test_basic_extraction(self):
        ids = ["id1", "id2", "id3"]
        matrix = pd.DataFrame(
            np.arange(9).reshape(3, 3).astype(float),
            index=ids,
            columns=ids,
        )
        sub = _extract_party_submatrix(matrix, ["id1", "id3"])
        assert sub.shape == (2, 2)
        assert list(sub.index) == ["id1", "id3"]
        assert list(sub.columns) == ["id1", "id3"]

    def test_none_matrix(self):
        result = _extract_party_submatrix(None, ["id1"])
        assert result is None

    def test_empty_matrix(self):
        result = _extract_party_submatrix(pd.DataFrame(), ["id1"])
        assert result is None

    def test_no_matches(self):
        ids = ["id1", "id2"]
        matrix = pd.DataFrame(np.ones((2, 2)), index=ids, columns=ids)
        result = _extract_party_submatrix(matrix, ["id99"])
        assert result is None


def result_val(df: pd.DataFrame, row: str, col: str) -> float:
    return df.loc[row, col]
