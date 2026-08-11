"""Oregon and Wisconsin golden validation — the states without special cases.

Indiana is the reference state everywhere else in this package, and it is the
awkward one: its House roster is special-cased to a curated spreadsheet, and the
classifier vintage behind its committed outputs no longer exists, which puts a
floor under how closely it can ever be reproduced.

Oregon and Wisconsin have neither problem. They take the ordinary LegiScan
roster path — never exercised by the Indiana tests — and **every one of their
sixteen committed outputs is reproduced exactly**, per state: pooled agreement,
sponsorship agreement, the raw integer tallies underneath both, and each party
subset, across both chambers.

Oregon's Senate was the last chamber to disagree, by two co-votes. It came down
to a single bill out of 266, and the cause was rollcalls not being sorted by
date (forge.m:147): a bill's outcome is read from its last chamber vote,
LegiScan orders rollcalls by id, and once a bill has votes across more than one
session file that ordering is not chronological. Sorting closed it completely.

Exact agreement on the raw integer tallies is the part worth dwelling on. Those
are counts of events with no averaging or normalization anywhere in them, so
matching cell-for-cell across a 100x100 matrix is not something two
implementations do by accident. This is the evidence that the agreement-matrix
arithmetic is right, and that Indiana's residual is about the provenance of its
classifier and roster rather than about computation.

These outputs also predate the per-category filenames: the goldens here are
`H_cha_A_matrix.csv`, where Indiana's are `H_cha_A_matrix_0.csv`. Another sign
the committed outputs span several code vintages.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from tests.test_integration.golden import compare_to_golden

#: Exact to floating point. Set as a hard gate deliberately: these states have
#: no known source of divergence, so any drift is a real regression.
EXACT_TOLERANCE = 1e-9

@pytest.fixture(scope="module", params=["OR", "WI"])
def state_run(request, tmp_path_factory: pytest.TempPathFactory):
    """Run the full pipeline for a state that needs no special-casing."""
    from forge.config import STATE_PROPERTIES, ForgeConfig
    from forge.pipeline.runner import run_pipeline

    state = request.param
    root = Path(__file__).resolve().parents[2]

    if not (root / "legiscan_data" / state).is_dir():
        pytest.skip(f"LegiScan data not available for {state}")
    if state not in STATE_PROPERTIES:
        pytest.skip(f"{state} not configured")

    classifier = root / "+la" / "learning_algorithm_data.mat"
    if not classifier.exists():
        pytest.skip("trained classifier not available")

    data_dir = tmp_path_factory.mktemp(f"forge_{state}")
    config = ForgeConfig(
        state_id=state,
        generate_all_categories=False,
        learning_data_path=str(classifier),
    )
    run_pipeline(config, legiscan_dir=root / "legiscan_data", data_dir=data_dir)
    return state, root / "data" / state / "outputs", data_dir / state / "outputs"


def _compare(golden_dir: Path, run_dir: Path, family: str):
    """Golden files here carry no category suffix; the port's outputs do."""
    golden = golden_dir / f"{family}.csv"
    produced = run_dir / f"{family}_0.csv"
    if not golden.exists():
        pytest.skip(f"no golden for {family}")
    assert produced.exists(), (
        f"pipeline did not produce {family}_0.csv; MATLAB produced {family}.csv"
    )
    return compare_to_golden(golden, produced)


#: Every family MATLAB emitted for these states: pooled agreement, sponsor
#: agreement, sponsor tallies, co-vote tallies, and both party subsets, per
#: chamber. All sixteen reproduce exactly, so all sixteen are asserted.
FAMILIES = [
    f"{chamber}_cha_{group}"
    for chamber in ("H", "S")
    for group in (
        "A_matrix", "A_votes", "A_s_matrix", "A_s_votes",
        "R_votes", "R_s_votes", "D_votes", "D_s_votes",
    )
]


class TestNonIndianaStatesReproduceExactly:
    """These states take the plain LegiScan roster path and match it exactly.

    Not approximately: every committed output file, for both chambers, for both
    states, agrees cell for cell. That covers agreement ratios, sponsorship
    agreement, and the raw integer tallies underneath both, across the full
    chamber and each party subset.
    """

    @pytest.mark.parametrize("family", FAMILIES)
    def test_every_output_matches_exactly(self, state_run, family: str) -> None:
        state, golden_dir, run_dir = state_run
        comparison = _compare(golden_dir, run_dir, family)
        assert comparison.labels_match, comparison.summary()
        assert comparison.compared_cells > 0, comparison.summary()
        assert comparison.max_abs_diff < EXACT_TOLERANCE, (
            f"{state} {family} no longer reproduces MATLAB exactly: "
            f"{comparison.summary()}"
        )


class TestLegiscanRosterPath:
    """Indiana's curated roster means these tests are the only cover for the
    ordinary roster-selection path in `_prepare_people`."""

    def test_roster_matches_the_golden(self, state_run) -> None:
        state, golden_dir, run_dir = state_run
        comparison = _compare(golden_dir, run_dir, "H_cha_A_matrix")
        assert comparison.labels_match, (
            f"{state} selected a different set of legislators than MATLAB: "
            f"{comparison.summary()}"
        )

    def test_chamber_is_plausibly_sized(self, state_run) -> None:
        """Catch a roster selection that silently returns almost nobody.

        The count is not asserted equal to the configured chamber size: real
        rosters carry mid-term replacements alongside the members they
        replaced, so a 99-seat chamber legitimately yields 100 rows.
        """
        from forge.config import STATE_PROPERTIES

        state, golden_dir, run_dir = state_run
        comparison = _compare(golden_dir, run_dir, "H_cha_A_matrix")
        expected = STATE_PROPERTIES[state].house_size
        actual = comparison.python_shape[0]
        assert 0.8 * expected <= actual <= 1.2 * expected, (
            f"{state} House roster has {actual} members against a configured "
            f"size of {expected}"
        )
