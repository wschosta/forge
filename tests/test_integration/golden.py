"""Comparison helpers for golden-file validation against the MATLAB outputs.

The committed CSVs under ``data/IN/outputs/`` are the outputs the MATLAB
implementation actually produced, and they are the only independent check that
the Python port computes the same thing. Unit tests elsewhere in this suite
build their own synthetic inputs, so they can only prove the code is
self-consistent — they cannot catch a stage that silently produces nothing.

Two details make a naive ``DataFrame.equals`` comparison useless here:

* **Row/column order differs.** MATLAB and pandas sort legislators differently
  within a party, so every comparison aligns on labels rather than position.
* **Label sets can differ.** The sponsor matrices in particular carry slightly
  different sponsor columns between the two implementations. Comparing only the
  shared labels — and reporting the unshared ones separately — localises a
  disagreement instead of collapsing it into one opaque failure.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd


@dataclass
class GoldenComparison:
    """The result of comparing one Python output CSV to its MATLAB counterpart."""

    name: str
    golden_shape: tuple[int, int]
    python_shape: tuple[int, int]

    shared_rows: int
    shared_cols: int
    golden_only_rows: list[str] = field(default_factory=list)
    python_only_rows: list[str] = field(default_factory=list)
    golden_only_cols: list[str] = field(default_factory=list)
    python_only_cols: list[str] = field(default_factory=list)

    #: Cells where both sides are finite, and so are actually comparable.
    compared_cells: int = 0
    max_abs_diff: float = 0.0
    mean_abs_diff: float = 0.0

    #: Cells finite in one implementation but not the other. A large count here
    #: means the two disagree about *which* pairs of legislators ever co-voted,
    #: which is a structural disagreement rather than a numerical one.
    finite_mismatch: int = 0

    @property
    def labels_match(self) -> bool:
        """True when both sides carry exactly the same row and column labels."""
        return not (
            self.golden_only_rows
            or self.python_only_rows
            or self.golden_only_cols
            or self.python_only_cols
        )

    def summary(self) -> str:
        """One-line human-readable summary, used in assertion messages."""
        label_note = "labels match" if self.labels_match else (
            f"labels differ (+{len(self.python_only_rows)}r/-{len(self.golden_only_rows)}r "
            f"+{len(self.python_only_cols)}c/-{len(self.golden_only_cols)}c)"
        )
        return (
            f"{self.name}: golden{self.golden_shape} python{self.python_shape}, {label_note}, "
            f"{self.compared_cells} cells compared, max|Δ|={self.max_abs_diff:.3e}, "
            f"mean|Δ|={self.mean_abs_diff:.3e}, finite-mismatch={self.finite_mismatch}"
        )


def compare_to_golden(golden_path: Path, python_path: Path) -> GoldenComparison:
    """Compare a Python-generated CSV against the MATLAB golden file.

    Both files are labelled matrices whose first column holds the row labels
    (legislator ``id{N}`` strings). Comparison is done on the intersection of
    labels, so ordering differences are irrelevant and label differences are
    reported rather than silently masked.

    Args:
        golden_path: Path to the committed MATLAB output.
        python_path: Path to the freshly generated Python output.

    Returns:
        A GoldenComparison describing both structural and numerical agreement.
    """
    golden = pd.read_csv(golden_path, index_col=0)
    python = pd.read_csv(python_path, index_col=0)

    golden_rows, python_rows = list(golden.index), list(python.index)
    golden_cols, python_cols = list(golden.columns), list(python.columns)

    # Preserve golden ordering so the comparison is deterministic.
    shared_rows = [r for r in golden_rows if r in set(python_rows)]
    shared_cols = [c for c in golden_cols if c in set(python_cols)]

    result = GoldenComparison(
        name=golden_path.name,
        golden_shape=golden.shape,
        python_shape=python.shape,
        shared_rows=len(shared_rows),
        shared_cols=len(shared_cols),
        golden_only_rows=sorted(set(golden_rows) - set(python_rows)),
        python_only_rows=sorted(set(python_rows) - set(golden_rows)),
        golden_only_cols=sorted(set(golden_cols) - set(python_cols)),
        python_only_cols=sorted(set(python_cols) - set(golden_cols)),
    )

    if not shared_rows or not shared_cols:
        return result

    golden_values = golden.loc[shared_rows, shared_cols].to_numpy(dtype=float)
    python_values = python.loc[shared_rows, shared_cols].to_numpy(dtype=float)

    golden_finite = np.isfinite(golden_values)
    python_finite = np.isfinite(python_values)
    both_finite = golden_finite & python_finite

    result.finite_mismatch = int((golden_finite ^ python_finite).sum())
    result.compared_cells = int(both_finite.sum())

    if result.compared_cells:
        diffs = np.abs(golden_values[both_finite] - python_values[both_finite])
        result.max_abs_diff = float(diffs.max())
        result.mean_abs_diff = float(diffs.mean())

    return result
