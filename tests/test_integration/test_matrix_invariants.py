"""Classification-independent correctness properties of the agreement matrices.

Everything else in this package compares against MATLAB's committed outputs,
which ties it to the classifier vintage that produced them. The categorization
logic is slated to be rewritten — it is acknowledged as rudimentary — and when
it is, every golden comparison involving categories becomes stale by design.

These tests are the part that survives. They assert properties the matrices must
satisfy whatever decides which bill belongs to which policy area:

* pooling is consistent — the pooled matrix is exactly the sum of the
  per-category ones, so no bill is double-counted or dropped;
* agreement is symmetric, self-agreement is total, ratios are ratios;
* the party partitions are genuine partitions of the chamber and agree with the
  full matrix wherever they overlap.

A failure here is a real defect in the matrix arithmetic. A failure in the
golden comparisons, after the classifier changes, probably is not.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

CATEGORIES = list(range(1, 12))


def _read(directory: Path, name: str) -> pd.DataFrame | None:
    path = directory / name
    if not path.exists():
        return None
    return pd.read_csv(path, index_col=0)


class TestPoolingIsConsistent:
    """Category 0 pools categories 1-11, so it must equal their sum.

    This is the strongest classification-independent check available: it holds
    for any assignment of bills to categories, and it fails the moment a bill is
    counted twice, dropped between the pooled and per-category paths, or
    assigned to more than one category.
    """

    def test_pooled_covotes_equal_the_sum_of_categories(self, indiana_run: Path) -> None:
        pooled = _read(indiana_run, "H_cha_A_votes_0.csv")
        if pooled is None:
            pytest.skip("pooled co-vote matrix not produced")

        total = pd.DataFrame(0.0, index=pooled.index, columns=pooled.columns)
        found = 0
        for category in CATEGORIES:
            frame = _read(indiana_run, f"H_cha_A_votes_{category}.csv")
            if frame is None:
                continue
            found += 1
            # Per-category matrices drop legislators who cast no vote in that
            # category, so align on the pooled roster before adding.
            total += frame.reindex(index=pooled.index, columns=pooled.columns).fillna(0.0)

        assert found, "no per-category matrices to sum"
        np.testing.assert_allclose(
            pooled.fillna(0.0).to_numpy(dtype=float),
            total.to_numpy(dtype=float),
            rtol=0, atol=1e-9,
            err_msg="pooled co-vote counts are not the sum of the per-category counts",
        )

    def test_no_category_exceeds_the_pooled_total(self, indiana_run: Path) -> None:
        """A single category holding more co-votes than the pool is impossible."""
        pooled = _read(indiana_run, "H_cha_A_votes_0.csv")
        if pooled is None:
            pytest.skip("pooled co-vote matrix not produced")
        pooled_values = pooled.fillna(0.0)

        for category in CATEGORIES:
            frame = _read(indiana_run, f"H_cha_A_votes_{category}.csv")
            if frame is None:
                continue
            aligned = frame.reindex(index=pooled.index, columns=pooled.columns).fillna(0.0)
            assert (aligned.to_numpy() <= pooled_values.to_numpy() + 1e-9).all(), (
                f"category {category} reports more co-votes than the pooled matrix"
            )


class TestAgreementMatrixShape:
    """Properties of an agreement ratio matrix that hold by construction."""

    @pytest.mark.parametrize("name", ["H_cha_A_matrix_0.csv", "S_cha_A_matrix_0.csv"])
    def test_is_symmetric(self, indiana_run: Path, name: str) -> None:
        """Agreement between i and j is the same quantity as between j and i."""
        frame = _read(indiana_run, name)
        if frame is None:
            pytest.skip(f"{name} not produced")
        values = frame.to_numpy(dtype=float)
        np.testing.assert_allclose(
            values, values.T, rtol=0, atol=1e-9, equal_nan=True,
            err_msg=f"{name} is not symmetric",
        )

    @pytest.mark.parametrize("name", ["H_cha_A_matrix_0.csv", "S_cha_A_matrix_0.csv"])
    def test_self_agreement_is_total(self, indiana_run: Path, name: str) -> None:
        """A legislator always agrees with themselves."""
        frame = _read(indiana_run, name)
        if frame is None:
            pytest.skip(f"{name} not produced")
        diagonal = np.diag(frame.to_numpy(dtype=float))
        finite = diagonal[np.isfinite(diagonal)]
        assert finite.size, "diagonal is entirely NaN"
        np.testing.assert_allclose(finite, 1.0, rtol=0, atol=1e-9)

    @pytest.mark.parametrize("name", ["H_cha_A_matrix_0.csv", "S_cha_A_matrix_0.csv"])
    def test_ratios_are_within_zero_and_one(self, indiana_run: Path, name: str) -> None:
        frame = _read(indiana_run, name)
        if frame is None:
            pytest.skip(f"{name} not produced")
        values = frame.to_numpy(dtype=float)
        finite = values[np.isfinite(values)]
        assert finite.size
        assert finite.min() >= -1e-9, f"{name} has agreement below 0"
        assert finite.max() <= 1 + 1e-9, f"{name} has agreement above 1"


class TestCovoteCounts:
    @pytest.mark.parametrize("name", ["H_cha_A_votes_0.csv", "S_cha_A_votes_0.csv"])
    def test_counts_are_non_negative_whole_numbers(self, indiana_run: Path, name: str) -> None:
        """Co-vote tallies count events, so fractional values mean a bug."""
        frame = _read(indiana_run, name)
        if frame is None:
            pytest.skip(f"{name} not produced")
        values = frame.to_numpy(dtype=float)
        finite = values[np.isfinite(values)]
        assert finite.size
        assert finite.min() >= 0, f"{name} has a negative co-vote count"
        np.testing.assert_allclose(
            finite, np.round(finite), rtol=0, atol=1e-9,
            err_msg=f"{name} has fractional co-vote counts",
        )

    @pytest.mark.parametrize("name", ["H_cha_A_votes_0.csv", "S_cha_A_votes_0.csv"])
    def test_counts_are_symmetric(self, indiana_run: Path, name: str) -> None:
        frame = _read(indiana_run, name)
        if frame is None:
            pytest.skip(f"{name} not produced")
        values = frame.to_numpy(dtype=float)
        np.testing.assert_allclose(
            values, values.T, rtol=0, atol=1e-9, equal_nan=True,
            err_msg=f"{name} is not symmetric",
        )


class TestPartyPartition:
    """The party subsets must partition the chamber and agree with the whole.

    These hold regardless of classification, and they are what catches a party
    filter selecting the wrong legislators — which would otherwise show up only
    as slightly-off numbers in a golden diff.
    """

    @pytest.mark.parametrize(
        "chamber,full,republican,democrat",
        [
            ("house", "H_cha_A_matrix_0.csv", "H_cha_R_votes_0.csv", "H_cha_D_votes_0.csv"),
            ("senate", "S_cha_A_matrix_0.csv", "S_cha_R_votes_0.csv", "S_cha_D_votes_0.csv"),
        ],
    )
    def test_parties_are_disjoint(
        self, indiana_run: Path, chamber: str, full: str, republican: str, democrat: str
    ) -> None:
        rep = _read(indiana_run, republican)
        dem = _read(indiana_run, democrat)
        if rep is None or dem is None:
            pytest.skip(f"{chamber} party matrices not produced")
        overlap = set(rep.index) & set(dem.index)
        assert not overlap, f"legislators in both parties: {sorted(overlap)}"

    @pytest.mark.parametrize(
        "chamber,full,republican,democrat",
        [
            ("house", "H_cha_A_matrix_0.csv", "H_cha_R_votes_0.csv", "H_cha_D_votes_0.csv"),
            ("senate", "S_cha_A_matrix_0.csv", "S_cha_R_votes_0.csv", "S_cha_D_votes_0.csv"),
        ],
    )
    def test_parties_cover_the_chamber(
        self, indiana_run: Path, chamber: str, full: str, republican: str, democrat: str
    ) -> None:
        """Every legislator belongs to one party subset or the other."""
        whole = _read(indiana_run, full)
        rep = _read(indiana_run, republican)
        dem = _read(indiana_run, democrat)
        if whole is None or rep is None or dem is None:
            pytest.skip(f"{chamber} matrices not produced")
        missing = set(whole.index) - (set(rep.index) | set(dem.index))
        assert not missing, f"legislators in neither party subset: {sorted(missing)}"

    @pytest.mark.parametrize(
        "full,subset",
        [
            ("H_cha_A_matrix_0.csv", "H_cha_R_votes_0.csv"),
            ("H_cha_A_matrix_0.csv", "H_cha_D_votes_0.csv"),
            ("S_cha_A_matrix_0.csv", "S_cha_R_votes_0.csv"),
            ("S_cha_A_matrix_0.csv", "S_cha_D_votes_0.csv"),
        ],
    )
    def test_party_agreement_matches_the_full_matrix(
        self, indiana_run: Path, full: str, subset: str
    ) -> None:
        """Two legislators' agreement does not change when others are excluded.

        The party matrices are the same pairwise ratios restricted to a subset,
        so every shared cell must carry the same value as in the full matrix. A
        mismatch means the subset was recomputed from a different vote set
        rather than sliced out of the same one.
        """
        whole = _read(indiana_run, full)
        part = _read(indiana_run, subset)
        if whole is None or part is None:
            pytest.skip("matrices not produced")

        rows = [i for i in part.index if i in set(whole.index)]
        cols = [c for c in part.columns if c in set(whole.columns)]
        if not rows or not cols:
            pytest.skip("no shared labels")

        a = whole.loc[rows, cols].to_numpy(dtype=float)
        b = part.loc[rows, cols].to_numpy(dtype=float)
        both = np.isfinite(a) & np.isfinite(b)
        assert both.any(), "no comparable cells"
        np.testing.assert_allclose(
            a[both], b[both], rtol=0, atol=1e-9,
            err_msg=f"{subset} disagrees with {full} on shared pairs",
        )
