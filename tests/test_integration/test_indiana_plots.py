"""Visualization validation — the stage MATLAB runs but the port never had.

`plot.plotRunner` is called from inside `state.run()` (state.m:218, 249, 315),
so plotting is part of a normal MATLAB run rather than an optional extra. The
Python port puts it behind `--generate-outputs`, and nothing had ever set that
flag against real data.

Images cannot be diffed pixel-for-pixel against MATLAB's: the two use different
plotting engines, and the underlying matrices differ slightly anyway. What is
checkable, and what actually catches breakage, is that every figure MATLAB
produced also gets produced here, that each file is a real PNG rather than a
zero-byte stub, and that both the surface and flattened variants appear. A
plotting stage that silently emits nothing, or writes empty files, fails these.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

#: The first eight bytes of every PNG file.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

REFERENCE_STATE = "IN"


@pytest.fixture(scope="module")
def plotted_run(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Run the pipeline once with plotting enabled, for the pooled category.

    Kept separate from the shared `indiana_run` fixture: rendering figures for
    all twelve categories would multiply an already slow run, and category 0
    exercises every plotting code path.
    """
    import matplotlib

    # Render off-screen; there is no display in CI.
    matplotlib.use("Agg")

    from forge.config import ForgeConfig
    from forge.pipeline.runner import INDIANA_HOUSE_ROSTER, run_pipeline

    root = Path(__file__).resolve().parents[2]
    if not (root / "legiscan_data" / REFERENCE_STATE).is_dir():
        pytest.skip("LegiScan data not available")

    classifier = root / "+la" / "learning_algorithm_data.mat"
    if not classifier.exists():
        pytest.skip("trained classifier not available")

    data_dir = tmp_path_factory.mktemp("forge_plots")
    source_roster = root / "data" / REFERENCE_STATE / INDIANA_HOUSE_ROSTER
    if source_roster.exists():
        target = data_dir / REFERENCE_STATE / INDIANA_HOUSE_ROSTER
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_roster, target)

    config = ForgeConfig(
        state_id=REFERENCE_STATE,
        generate_all_categories=False,
        # Pinned to the legacy classifier deliberately. These tests compare
        # against MATLAB's committed outputs, which were produced by the
        # word-frequency scorer; it leaves ~5% of bills unclassified and those
        # bills are consequently absent from the pooled category-0 matrices.
        # The TF-IDF default classifies everything, so running it here would
        # compare different bill sets and fail for reasons that are not defects.
        classifier="legacy",
        generate_outputs=True,
        learning_data_path=str(classifier),
    )
    run_pipeline(config, legiscan_dir=root / "legiscan_data", data_dir=data_dir)
    return data_dir / REFERENCE_STATE / "outputs"


def _pngs(directory: Path) -> list[Path]:
    return sorted(directory.glob("*.png")) if directory.is_dir() else []


class TestPlotsAreProduced:
    def test_surface_plots_are_written(self, plotted_run: Path) -> None:
        """The plotting stage must emit something at all."""
        assert _pngs(plotted_run), f"no PNGs written to {plotted_run}"

    def test_histograms_are_written(self, plotted_run: Path) -> None:
        assert _pngs(plotted_run / "histograms"), "no histogram PNGs written"

    def test_every_golden_figure_has_a_counterpart(
        self, plotted_run: Path, golden_dir: Path
    ) -> None:
        """Catch a figure family silently dropping out of the run.

        Only the pooled-category figures are in scope; the golden directory
        also holds per-category and Monte Carlo figures this run does not
        generate.
        """
        golden = {
            path.name
            for path in golden_dir.glob("*.png")
            if path.stem.endswith("_0") or path.stem.endswith("_0_flat")
        }
        if not golden:
            pytest.skip("no golden figures for the pooled category")
        produced = {path.name for path in _pngs(plotted_run)}
        missing = sorted(golden - produced)
        assert not missing, f"figures MATLAB produced that the port did not: {missing}"

    def test_both_surface_and_flat_variants_exist(self, plotted_run: Path) -> None:
        """Each surface plot has a flattened heatmap companion."""
        names = {path.stem for path in _pngs(plotted_run)}
        surfaces = {name for name in names if not name.endswith("_flat")}
        missing = sorted(name for name in surfaces if f"{name}_flat" not in names)
        assert not missing, f"surface plots with no flat companion: {missing}"


class TestPlotsAreValidImages:
    """A figure written as an empty or truncated file is worse than none.

    matplotlib will happily create a file and leave it empty if the figure was
    never drawn, which looks like success to anything that only checks the
    filename.
    """

    def test_no_empty_files(self, plotted_run: Path) -> None:
        images = _pngs(plotted_run) + _pngs(plotted_run / "histograms")
        empty = [path.name for path in images if path.stat().st_size == 0]
        assert not empty, f"zero-byte figures: {empty}"

    def test_all_files_are_real_pngs(self, plotted_run: Path) -> None:
        images = _pngs(plotted_run) + _pngs(plotted_run / "histograms")
        assert images, "no figures to check"
        malformed = [
            path.name
            for path in images
            if path.read_bytes()[:8] != PNG_SIGNATURE
        ]
        assert not malformed, f"files that are not valid PNGs: {malformed}"

    def test_figures_have_plausible_size(self, plotted_run: Path) -> None:
        """A near-empty axes renders to a few hundred bytes; real plots do not."""
        images = _pngs(plotted_run)
        tiny = [path.name for path in images if path.stat().st_size < 5_000]
        assert not tiny, f"suspiciously small figures, likely blank: {tiny}"
