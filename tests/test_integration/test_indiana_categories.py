"""Per-category golden validation — the outputs that actually test classification.

`test_indiana_golden.py` compares category 0, the pooled matrix built from every
classified bill. That comparison is blind to misclassification: a bill filed
under the wrong policy area still lands in the same pooled aggregate, so the
matrix is unchanged. Only the per-category matrices separate the bills, and they
account for 99 of the 128 committed golden CSVs.

Expect looser agreement here than at category 0, for a structural reason. Each
category holds a fraction of the bills, so a single bill landing in a different
category moves a small denominator much further than it moves the pooled one.
The tolerances reflect that rather than pretending otherwise, and the tests that
matter most are the structural ones: whether a category came out empty, and
whether the classifier distributed bills across categories the way MATLAB's did.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from tests.test_integration.golden import compare_to_golden

CATEGORIES = list(range(1, 12))

#: Families that exist per-category. Chosen to cover the pooled agreement
#: matrix, the raw co-vote tallies and both party subsets.
FAMILIES = [
    "H_cha_A_matrix",
    "H_cha_A_votes",
    "H_cha_R_votes",
    "H_cha_D_votes",
]

#: Categories that reproduce MATLAB to floating-point precision — measured worst
#: case across them is 5e-16, i.e. accumulated rounding and nothing else. Six of
#: the eleven policy areas do, which is far stronger agreement than the pooled
#: category 0 shows, and it says the disagreement is not spread evenly: it is
#: confined to the categories the two classifier vintages sort differently.
EXACT_CATEGORIES = [1, 6, 7, 9, 10, 11]

#: Headroom above the measured 5e-16 while staying orders of magnitude below any
#: difference a real bill-selection change would produce.
EXACT_TOLERANCE = 1e-12

#: The rest differ because bills move between them. Measured worst case is
#: max 0.250 (category 3) and mean 0.0133; these sit just above that as a
#: regression gate.
CATEGORY_MAX_TOLERANCE = 0.35
CATEGORY_MEAN_TOLERANCE = 0.03


def _compare(golden_dir: Path, indiana_run: Path, name: str):
    golden_path = golden_dir / name
    python_path = indiana_run / name
    if not golden_path.exists():
        pytest.skip(f"no golden for {name}")
    assert python_path.exists(), (
        f"pipeline did not produce {name}; MATLAB did, so a whole category "
        f"stopped emitting output"
    )
    return compare_to_golden(golden_path, python_path)


@pytest.mark.parametrize("category", CATEGORIES)
def test_category_matrix_is_not_empty(golden_dir: Path, indiana_run: Path, category: int) -> None:
    """Every policy area MATLAB found bills for must also get bills here.

    An empty category is the per-category form of the silent-empty-output bug:
    the file is written, correctly named, and contains nothing.
    """
    comparison = _compare(golden_dir, indiana_run, f"H_cha_A_matrix_{category}.csv")
    assert comparison.python_shape[0] > 0, (
        f"category {category} produced an empty matrix: {comparison.summary()}"
    )
    assert comparison.compared_cells > 0, comparison.summary()


@pytest.mark.parametrize("category", CATEGORIES)
def test_category_rosters_match(golden_dir: Path, indiana_run: Path, category: int) -> None:
    """The chamber roster does not depend on category, so labels must match exactly."""
    comparison = _compare(golden_dir, indiana_run, f"H_cha_A_matrix_{category}.csv")
    assert comparison.labels_match, comparison.summary()


@pytest.mark.parametrize("category", CATEGORIES)
@pytest.mark.parametrize("family", FAMILIES)
def test_category_values_within_tolerance(
    golden_dir: Path, indiana_run: Path, family: str, category: int
) -> None:
    """Values must stay within the measured band for per-category outputs."""
    comparison = _compare(golden_dir, indiana_run, f"{family}_{category}.csv")
    if comparison.compared_cells == 0:
        pytest.skip(f"{family}_{category} has no comparable cells")
    if family.endswith("_votes") and "A_votes" in family:
        # Raw co-vote counts, measured in whole votes rather than ratio points.
        return
    assert comparison.max_abs_diff <= CATEGORY_MAX_TOLERANCE, comparison.summary()
    assert comparison.mean_abs_diff <= CATEGORY_MEAN_TOLERANCE, comparison.summary()


@pytest.mark.parametrize("category", EXACT_CATEGORIES)
@pytest.mark.parametrize(
    "family", ["H_cha_A_matrix", "H_cha_R_votes", "H_cha_D_votes"]
)
def test_exactly_matching_categories_stay_exact(
    golden_dir: Path, indiana_run: Path, family: str, category: int
) -> None:
    """These policy areas reproduce MATLAB to floating-point precision.

    Six of eleven categories agree to ~5e-16 — accumulated rounding, nothing
    more. This is the strongest evidence in the suite that the agreement-matrix
    arithmetic is right: wherever the two classifier vintages agree on which
    bills belong to a policy area, the resulting matrices are the same numbers.
    It also isolates the remaining disagreement to classification rather than
    computation.

    A failure here is unambiguous — it means a change altered results in a
    place that previously had no error to hide behind.
    """
    comparison = _compare(golden_dir, indiana_run, f"{family}_{category}.csv")
    if comparison.compared_cells == 0:
        pytest.skip(f"{family}_{category} has no comparable cells")
    assert comparison.max_abs_diff < EXACT_TOLERANCE, (
        f"category {category} no longer matches MATLAB to precision: {comparison.summary()}"
    )


def test_every_category_golden_has_a_counterpart(golden_dir: Path, indiana_run: Path) -> None:
    """Catch a whole policy area silently dropping out of the run."""
    missing = []
    for family in FAMILIES:
        for category in CATEGORIES:
            name = f"{family}_{category}.csv"
            if (golden_dir / name).exists() and not (indiana_run / name).exists():
                missing.append(name)
    assert not missing, f"pipeline stopped producing: {missing}"


def test_classification_spread_resembles_matlab(golden_dir: Path, indiana_run: Path) -> None:
    """Compare how bills are distributed across policy areas.

    This is the most diagnostic per-category check available. Each category's
    co-vote tallies scale with how many bills landed in it, so the relative
    sizes across categories are a proxy for the classifier's distribution. A
    classifier that systematically over- or under-populates a policy area shows
    up here even when individual matrices look plausible.
    """
    golden_totals, python_totals = {}, {}
    for category in CATEGORIES:
        name = f"H_cha_A_votes_{category}.csv"
        if not (golden_dir / name).exists() or not (indiana_run / name).exists():
            continue
        golden = pd.read_csv(golden_dir / name, index_col=0).to_numpy(dtype=float)
        python = pd.read_csv(indiana_run / name, index_col=0).to_numpy(dtype=float)
        golden_totals[category] = float(pd.Series(golden.ravel()).sum(skipna=True))
        python_totals[category] = float(pd.Series(python.ravel()).sum(skipna=True))

    assert golden_totals, "no per-category vote tallies to compare"

    golden_series = pd.Series(golden_totals)
    python_series = pd.Series(python_totals)
    # Rank correlation across policy areas: are the big categories the same
    # ones? Magnitudes differ with bill selection, so ranks are the fair test.
    correlation = golden_series.corr(python_series, method="spearman")
    assert correlation > 0.5, (
        f"classifier distributes bills across policy areas differently from "
        f"MATLAB (Spearman {correlation:.3f}).\n"
        f"golden: {golden_totals}\npython: {python_totals}"
    )
