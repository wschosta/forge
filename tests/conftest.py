"""Shared test fixtures for the Forge test suite."""

from pathlib import Path

import pytest


@pytest.fixture
def project_root() -> Path:
    """Return the project root directory."""
    return Path(__file__).parent.parent


@pytest.fixture
def legiscan_data_dir(project_root: Path) -> Path:
    """Return the LegiScan data directory."""
    return project_root / "legiscan_data"


@pytest.fixture
def indiana_data_dir(project_root: Path) -> Path:
    """Return the Indiana processed data directory."""
    return project_root / "data" / "IN"


@pytest.fixture
def congressional_xml_dir(project_root: Path) -> Path:
    """Return the Congressional XML archive directory."""
    return project_root / "data" / "congressional_archive"
