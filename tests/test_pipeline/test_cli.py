"""Tests for the CLI module."""

from __future__ import annotations

import pytest
from click.testing import CliRunner

from forge.cli import cli


@pytest.fixture
def runner():
    return CliRunner()


class TestCli:
    def test_help(self, runner):
        result = runner.invoke(cli, ["--help"])
        assert result.exit_code == 0
        assert "Forge" in result.output

    def test_run_help(self, runner):
        result = runner.invoke(cli, ["run", "--help"])
        assert result.exit_code == 0
        assert "--recompute" in result.output
        assert "--predict-montecarlo" in result.output
        assert "--predict-elo" in result.output

    def test_classify_help(self, runner):
        """The command trains the classifier; it used to be a stub.

        `--optimize` belonged to the word-frequency classifier's iwv/awv grid
        search and has no analogue in the TF-IDF model, so it is gone rather
        than kept as a no-op.
        """
        result = runner.invoke(cli, ["classify", "--help"])
        assert result.exit_code == 0
        for option in ["--xml-dir", "--output", "--test-size", "--seed"]:
            assert option in result.output, f"{option} missing from classify --help"

    def test_run_invalid_state(self, runner):
        result = runner.invoke(cli, ["run", "XX"])
        assert result.exit_code != 0
