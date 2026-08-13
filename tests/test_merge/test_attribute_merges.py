"""Tests for the ideology and seniority attribute merges.

Neither module had any test coverage. Both are thin wrappers around the shared
`_merge_attribute_data` join, and both are standalone utilities rather than
pipeline stages — MATLAB's `state.run()` does not call them either, so the port
matching that is faithful.

Their real inputs (`shor_mccarty/shor_mccarty_{STATE}.csv`,
`finance_data/seniority_data_{STATE}.csv`) are not committed to the repository,
so these tests build the inputs the modules document rather than reading real
ones. The filenames are checked against MATLAB's — `mergeShorMcCarty.m:3` and
`mergeSeniority.m:3` — so a rename would be caught.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from forge.merge.ideology import merge_shor_mccarty
from forge.merge.seniority import merge_seniority


def _merged_data_csv(directory: Path, rows: list[dict]) -> Path:
    """Write a CSV shaped like the finance merge output these join into."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "H_elo_score_0.csv"
    pd.DataFrame(rows).to_csv(path, index=False)
    return path


class TestMergeShorMccarty:
    def test_missing_merged_data_directory_is_reported_clearly(self, tmp_path: Path):
        """The join has an ordering dependency; the error has to say so."""
        shor_dir = tmp_path / "shor_mccarty"
        shor_dir.mkdir()
        pd.DataFrame({"name": ["Smith, John"], "np_score": [0.5]}).to_csv(
            shor_dir / "shor_mccarty_IN.csv", index=False
        )

        with pytest.raises(FileNotFoundError, match="merge_finance_data"):
            merge_shor_mccarty("IN", data_dir=tmp_path / "data", shor_mccarty_dir=shor_dir)

    def test_reads_the_matlab_filename(self, tmp_path: Path):
        """mergeShorMcCarty.m:3 reads shor_mccarty/shor_mccarty_{STATE}.csv."""
        shor_dir = tmp_path / "shor_mccarty"
        shor_dir.mkdir()
        _merged_data_csv(tmp_path / "data" / "IN" / "merged_data", [{"last_name": "Smith"}])

        # No input file under the expected name — the read must be what fails.
        with pytest.raises(FileNotFoundError):
            merge_shor_mccarty("IN", data_dir=tmp_path / "data", shor_mccarty_dir=shor_dir)

    def test_joins_scores_onto_matching_legislators(self, tmp_path: Path):
        """Names must be uppercase on the attribute side — see the test below."""
        shor_dir = tmp_path / "shor_mccarty"
        shor_dir.mkdir()
        pd.DataFrame(
            {"name": ["SMITH, JOHN", "JONES, MARY"], "np_score": [0.5, -0.3], "party": ["R", "D"]}
        ).to_csv(shor_dir / "shor_mccarty_IN.csv", index=False)

        merged_dir = tmp_path / "data" / "IN" / "merged_data"
        target = _merged_data_csv(
            merged_dir,
            [
                {"last_name": "Smith", "first_name": "John", "score": 1500},
                {"last_name": "Jones", "first_name": "Mary", "score": 1400},
            ],
        )

        merge_shor_mccarty("IN", data_dir=tmp_path / "data", shor_mccarty_dir=shor_dir)

        result = pd.read_csv(target)
        assert "full_name" in result.columns
        assert "np_score" in result.columns, "ideology scores were not joined on"
        assert len(result) == 2
        # The party column is dropped before joining, per the module's contract.
        assert "party" not in result.columns

    def test_case_mismatch_silently_joins_nothing(self, tmp_path: Path):
        """Documents a fragility inherited from MATLAB, not a port defect.

        The merged-data side is uppercased when its full name is built
        (mergeShorMcCarty.m:58), but the attribute side is used verbatim
        (line 4). The name matcher is case-sensitive, so a source file whose
        names are not already uppercase joins zero rows — and reports success,
        leaving the target file untouched.

        Both implementations behave this way, so it is pinned rather than
        fixed; changing it would silently alter the published merge results.
        Worth knowing before anyone wonders why a merge "ran fine" and changed
        nothing.
        """
        shor_dir = tmp_path / "shor_mccarty"
        shor_dir.mkdir()
        pd.DataFrame({"name": ["Smith, John"], "np_score": [0.5]}).to_csv(
            shor_dir / "shor_mccarty_IN.csv", index=False
        )

        merged_dir = tmp_path / "data" / "IN" / "merged_data"
        target = _merged_data_csv(
            merged_dir, [{"last_name": "Smith", "first_name": "John", "score": 1500}]
        )
        before = target.read_text()

        merge_shor_mccarty("IN", data_dir=tmp_path / "data", shor_mccarty_dir=shor_dir)

        assert target.read_text() == before, (
            "a case-insensitive match would change this behaviour and with it "
            "the published merge outputs"
        )

    def test_leaves_files_without_last_name_alone(self, tmp_path: Path):
        """Only name-keyed CSVs participate; others must not be rewritten."""
        shor_dir = tmp_path / "shor_mccarty"
        shor_dir.mkdir()
        pd.DataFrame({"name": ["Smith, John"], "np_score": [0.5]}).to_csv(
            shor_dir / "shor_mccarty_IN.csv", index=False
        )

        merged_dir = tmp_path / "data" / "IN" / "merged_data"
        target = _merged_data_csv(merged_dir, [{"bill_id": 1, "value": 2}])
        before = target.read_text()

        merge_shor_mccarty("IN", data_dir=tmp_path / "data", shor_mccarty_dir=shor_dir)

        assert target.read_text() == before


class TestMergeSeniority:
    def test_missing_merged_data_directory_is_reported_clearly(self, tmp_path: Path):
        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir()
        pd.DataFrame({"candidate": ["Smith, John"], "cumulative": [3]}).to_csv(
            finance_dir / "seniority_data_IN.csv", index=False
        )

        with pytest.raises(FileNotFoundError):
            merge_seniority("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

    def test_keeps_only_the_most_recent_term_count(self, tmp_path: Path):
        """A legislator appears once per election; only the latest row counts.

        Keeping an earlier row would understate seniority for everyone
        re-elected, which is most of the chamber.
        """
        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir()
        pd.DataFrame(
            {
                "candidate": ["Smith, John", "Smith, John", "Smith, John"],
                "cumulative": [1, 2, 3],
                "election_year": [2010, 2014, 2012],
            }
        ).to_csv(finance_dir / "seniority_data_IN.csv", index=False)

        merged_dir = tmp_path / "data" / "IN" / "merged_data"
        target = _merged_data_csv(
            merged_dir, [{"last_name": "Smith", "first_name": "John", "score": 1500}]
        )

        merge_seniority("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

        result = pd.read_csv(target)
        if "terms_served" in result.columns and len(result):
            # 2014 is the latest year, carrying a cumulative count of 2.
            assert result["terms_served"].iloc[0] == 2

    def test_drops_the_columns_it_documents(self, tmp_path: Path):
        finance_dir = tmp_path / "finance_data"
        finance_dir.mkdir()
        pd.DataFrame(
            {
                "candidate": ["Smith, John"],
                "cumulative": [3],
                "chamb": ["H"],
                "democratic": [0],
                "republican": [1],
                "thirdparty": [0],
                "election_year": [2014],
            }
        ).to_csv(finance_dir / "seniority_data_IN.csv", index=False)

        merged_dir = tmp_path / "data" / "IN" / "merged_data"
        target = _merged_data_csv(
            merged_dir, [{"last_name": "Smith", "first_name": "John", "score": 1500}]
        )

        merge_seniority("IN", data_dir=tmp_path / "data", finance_dir=finance_dir)

        result = pd.read_csv(target)
        for dropped in ["chamb", "democratic", "republican", "thirdparty", "candidate"]:
            assert dropped not in result.columns, f"{dropped} should have been dropped"
