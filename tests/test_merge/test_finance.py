"""Tests for the finance merge module."""

from __future__ import annotations

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
