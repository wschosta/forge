"""Quantify how far the TF-IDF baseline moves from the committed MATLAB outputs.

The three states with committed MATLAB results (IN, OR, WI) are the only places
this comparison can be made. It is a measurement, not a test: the MATLAB outputs
were produced by a classifier that no longer exists, so a difference here is
evidence about how much the categorisation drives the matrices — not evidence
that either side is wrong.

Oregon and Wisconsin reproduce MATLAB *exactly* under ``--classifier legacy``,
so any movement reported for them is attributable to the classifier alone, with
no other difference in play. Indiana carries unrelated provenance problems and
its numbers should be read with that in mind.

Usage:
    python scripts/compare_baseline_to_matlab.py [--baseline baseline] [--golden data]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tests"))

from test_integration.golden import compare_to_golden  # noqa: E402

#: The pooled agreement matrices are the headline outputs — the ones downstream
#: Stata scripts consume. Per-category files are compared too, but summarised.
POOLED = ["cha_A_matrix_0", "cha_A_votes_0", "cha_A_s_matrix_0"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="baseline", type=Path)
    parser.add_argument("--golden", default="data", type=Path)
    parser.add_argument("--states", nargs="*", default=["IN", "OR", "WI"])
    args = parser.parse_args()

    exit_code = 0
    for state in args.states:
        golden_dir = args.golden / state / "outputs"
        baseline_dir = args.baseline / state / "outputs"
        if not golden_dir.is_dir() or not baseline_dir.is_dir():
            print(f"{state}: skipped (missing {golden_dir} or {baseline_dir})")
            exit_code = 1
            continue

        print(f"\n{'=' * 78}\n{state}\n{'=' * 78}")

        for chamber in ("H", "S"):
            pooled_rows = []
            per_category = []

            for golden_csv in sorted(golden_dir.glob(f"{chamber}_*.csv")):
                # Oregon and Wisconsin predate the per-category filenames: their
                # goldens are `H_cha_A_matrix.csv` where Indiana's are
                # `H_cha_A_matrix_0.csv`. Both name the pooled matrix, so an
                # unsuffixed golden is matched against the `_0` output.
                candidate = baseline_dir / golden_csv.name
                if not candidate.exists():
                    candidate = baseline_dir / f"{golden_csv.stem}_0.csv"
                if not candidate.exists():
                    per_category.append((golden_csv.stem, None))
                    continue
                comparison = compare_to_golden(golden_csv, candidate)
                stem = golden_csv.stem[2:]  # drop the chamber prefix
                if stem in POOLED or f"{stem}_0" in POOLED:
                    pooled_rows.append((stem, comparison))
                else:
                    per_category.append((stem, comparison))

            if not pooled_rows and not per_category:
                continue

            print(f"\n  {chamber} — pooled (category 0)")
            for stem, comparison in pooled_rows:
                print(
                    f"    {stem:<20} mean|Δ|={comparison.mean_abs_diff:.4f} "
                    f"max|Δ|={comparison.max_abs_diff:.4f} "
                    f"cells={comparison.compared_cells} "
                    f"finite-mismatch={comparison.finite_mismatch}"
                )

            compared = [c for _, c in per_category if c is not None]
            missing = [s for s, c in per_category if c is None]
            if compared:
                worst = max(compared, key=lambda c: c.mean_abs_diff)
                mean_of_means = sum(c.mean_abs_diff for c in compared) / len(compared)
                print(
                    f"  {chamber} — per-category: {len(compared)} files, "
                    f"mean|Δ| avg={mean_of_means:.4f}, worst={worst.name} "
                    f"({worst.mean_abs_diff:.4f})"
                )
            if missing:
                # A file the golden has and the baseline does not means the new
                # classifier put no bills in that category for that chamber.
                print(f"  {chamber} — {len(missing)} golden files have no baseline counterpart:")
                for stem in missing:
                    print(f"        {stem}")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
