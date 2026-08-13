"""Fixtures for the Indiana golden-file integration tests.

These tests need the real LegiScan data and the committed MATLAB outputs, both
of which live in the repository. When either is absent the whole module skips
rather than fails, so a sparse checkout still gets a green unit-test run.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

REFERENCE_STATE = "IN"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def golden_dir() -> Path:
    """Directory of committed MATLAB outputs for the reference state."""
    path = _repo_root() / "data" / REFERENCE_STATE / "outputs"
    if not path.is_dir():
        pytest.skip(f"MATLAB golden outputs not available at {path}")
    return path


@pytest.fixture(scope="session")
def indiana_run(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Run the full Indiana pipeline once and return its outputs directory.

    The pipeline is slow relative to a unit test, so it is session-scoped and
    every comparison in this package reads the same run.

    Indiana's curated House roster lives under the *state data directory*,
    which MATLAB treats as both an input and an output location. The run writes
    to a temporary directory, so the roster is copied across first to reproduce
    that layout without touching the repository.
    """
    from forge.config import ForgeConfig
    from forge.pipeline.runner import INDIANA_HOUSE_ROSTER, run_pipeline

    root = _repo_root()
    legiscan_dir = root / "legiscan_data" / REFERENCE_STATE
    if not legiscan_dir.is_dir():
        pytest.skip(f"LegiScan data not available at {legiscan_dir}")

    classifier = root / "+la" / "learning_algorithm_data.mat"
    if not classifier.exists():
        pytest.skip(f"Trained classifier not available at {classifier}")

    data_dir = tmp_path_factory.mktemp("forge_data")
    source_roster = root / "data" / REFERENCE_STATE / INDIANA_HOUSE_ROSTER
    if source_roster.exists():
        target_roster = data_dir / REFERENCE_STATE / INDIANA_HOUSE_ROSTER
        target_roster.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_roster, target_roster)

    config = ForgeConfig(
        state_id=REFERENCE_STATE,
        # All 12 categories: 0 is the pooled matrix, 1-11 are the per-policy-area
        # ones. The pooled matrix cannot see a bill filed under the wrong
        # category — it lands in the same aggregate either way — so the
        # per-category outputs are the only ones that exercise classification.
        # One run serves every comparison in this package.
        generate_all_categories=True,
        # Pinned to the legacy classifier deliberately. These tests compare
        # against MATLAB's committed outputs, which were produced by the
        # word-frequency scorer; it leaves ~5% of bills unclassified and those
        # bills are consequently absent from the pooled category-0 matrices.
        # The TF-IDF default classifies everything, so running it here would
        # compare different bill sets and fail for reasons that are not defects.
        classifier="legacy",
        learning_data_path=str(classifier),
    )

    run_pipeline(config, legiscan_dir=root / "legiscan_data", data_dir=data_dir)

    outputs = data_dir / REFERENCE_STATE / "outputs"
    if not outputs.is_dir():
        pytest.fail(f"Pipeline produced no outputs directory at {outputs}")
    return outputs
