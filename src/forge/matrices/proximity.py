"""Seat proximity matrix — replaces processSeatProximity.m.

Computes Euclidean distance between legislator seat positions.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from forge.config import create_id_strings


def compute_seat_proximity(people: pd.DataFrame) -> pd.DataFrame:
    """Compute Euclidean distance between all pairs of legislators.

    Replaces @forge/processSeatProximity.m. Uses numpy broadcasting:
    ``sqrt((x[:,None]-x[None,:])^2 + (y[:,None]-y[None,:])^2)``

    Args:
        people: People DataFrame with 'sponsor_id', 'SEATROW', 'SEATCOLUMN' columns.

    Returns:
        Square DataFrame of pairwise Euclidean distances indexed by legislator IDs.

    Raises:
        KeyError: If SEATROW or SEATCOLUMN columns are missing.
    """
    ids = create_id_strings(people["sponsor_id"].tolist())
    x = people["SEATROW"].values.astype(float)
    y = people["SEATCOLUMN"].values.astype(float)

    dist = np.sqrt((x[:, None] - x[None, :]) ** 2 + (y[:, None] - y[None, :]) ** 2)

    return pd.DataFrame(dist, index=ids, columns=ids)
