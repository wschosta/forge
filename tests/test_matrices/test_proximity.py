"""Tests for the seat proximity module."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from forge.matrices.proximity import compute_seat_proximity


class TestComputeSeatProximity:
    def test_basic_distance(self):
        people = pd.DataFrame({
            "sponsor_id": [1, 2, 3],
            "SEATROW": [0, 3, 0],
            "SEATCOLUMN": [0, 4, 1],
        })
        result = compute_seat_proximity(people)
        assert result.shape == (3, 3)
        # Distance from (0,0) to (3,4) = 5
        assert result.loc["id1", "id2"] == pytest.approx(5.0)
        # Distance from (0,0) to (0,1) = 1
        assert result.loc["id1", "id3"] == pytest.approx(1.0)
        # Self-distance = 0
        assert result.loc["id1", "id1"] == pytest.approx(0.0)

    def test_symmetric(self):
        people = pd.DataFrame({
            "sponsor_id": [10, 20],
            "SEATROW": [1, 4],
            "SEATCOLUMN": [2, 6],
        })
        result = compute_seat_proximity(people)
        assert result.loc["id10", "id20"] == pytest.approx(result.loc["id20", "id10"])

    def test_missing_column_raises(self):
        people = pd.DataFrame({
            "sponsor_id": [1],
            "SEATROW": [0],
        })
        with pytest.raises(KeyError):
            compute_seat_proximity(people)
