"""Command-line interface for Forge — replaces tester.m.

Usage:
    forge run IN --recompute --predict-montecarlo
    forge run IN --predict-elo --elo-mc-number 15000
    forge classify --optimize
"""

from __future__ import annotations

import logging
import sys

import click

from forge.config import STATE_PROPERTIES, ForgeConfig


@click.group()
@click.option("-v", "--verbose", is_flag=True, help="Enable verbose logging.")
def cli(verbose: bool) -> None:
    """Forge — Legislative analysis and prediction system."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )


@cli.command()
@click.argument("state", type=click.Choice(sorted(STATE_PROPERTIES.keys()), case_sensitive=False))
@click.option("--reprocess", is_flag=True, help="Reprocess LegiScan data.")
@click.option("--recompute", is_flag=True, help="Recompute agreement matrices.")
@click.option("--generate-outputs", is_flag=True, help="Generate plots and outputs.")
@click.option("--predict-montecarlo", is_flag=True, help="Run Monte Carlo prediction.")
@click.option("--recompute-montecarlo", is_flag=True, help="Force recompute MC.")
@click.option("--predict-elo", is_flag=True, help="Run Elo prediction.")
@click.option("--recompute-elo", is_flag=True, help="Force recompute Elo.")
@click.option("--mc-number", type=int, default=16000, help="Monte Carlo iterations.")
@click.option("--elo-mc-number", type=int, default=15000, help="Elo Monte Carlo iterations.")
@click.option("--show-warnings", is_flag=True, help="Show verbose warnings.")
@click.option("--legiscan-dir", type=click.Path(), default="legiscan_data", help="LegiScan data directory.")
@click.option("--data-dir", type=click.Path(), default="data", help="Output data directory.")
def run(
    state: str,
    reprocess: bool,
    recompute: bool,
    generate_outputs: bool,
    predict_montecarlo: bool,
    recompute_montecarlo: bool,
    predict_elo: bool,
    recompute_elo: bool,
    mc_number: int,
    elo_mc_number: int,
    show_warnings: bool,
    legiscan_dir: str,
    data_dir: str,
) -> None:
    """Run the Forge pipeline for a state."""
    config = ForgeConfig(
        state_id=state.upper(),
        reprocess=reprocess,
        recompute=recompute,
        generate_outputs=generate_outputs,
        predict_montecarlo=predict_montecarlo,
        recompute_montecarlo=recompute_montecarlo,
        predict_elo=predict_elo,
        recompute_elo=recompute_elo,
        show_warnings=show_warnings,
        monte_carlo_number=mc_number,
        elo_monte_carlo_number=elo_mc_number,
    )

    from forge.pipeline.runner import run_pipeline

    results = run_pipeline(config, legiscan_dir=legiscan_dir, data_dir=data_dir)

    # Summary
    for chamber in ["house", "senate"]:
        if results.get(chamber):
            ch_data = results[chamber]
            n_bills = len(ch_data.get("bill_ids", []))
            click.echo(f"{chamber.capitalize()}: {n_bills} bills processed")


@cli.command()
@click.option(
    "--xml-dir",
    type=click.Path(),
    default="data/congressional_archive",
    help="Congressional corpus directory (reads the zip archives directly).",
)
@click.option(
    "--output",
    type=click.Path(),
    default="+la/tfidf_classifier.pkl",
    help="Where to write the trained classifier.",
)
@click.option("--test-size", default=0.2, help="Fraction held out to score accuracy.")
@click.option("--seed", default=42, help="Seed for the train/test split.")
def classify(xml_dir: str, output: str, test_size: float, seed: int) -> None:
    """Train the bill classifier from the congressional corpus.

    Reads the corpus, maps each bill's policy area to a concise category, fits a
    TF-IDF + linear SVM model, and reports held-out accuracy before writing it
    out.
    """
    from forge.classify.learning import build_concise_code_map
    from forge.classify.tfidf_classifier import save_tfidf_classifier, train_tfidf_classifier
    from forge.ingest.xml_parser import parse_congressional_xml

    click.echo(f"Reading corpus from {xml_dir} ...")
    bills = parse_congressional_xml(xml_dir)
    if not bills:
        raise click.ClickException(f"No bills parsed from {xml_dir}")
    click.echo(f"  {len(bills)} bills")

    # Category codes are derived from the sorted unique policy areas at training
    # time, matching la/main.m:38 rather than any stored table.
    areas = sorted({bill.policy_area for bill in bills if bill.policy_area})
    area_to_code = {area: index + 1 for index, area in enumerate(areas)}
    concise = build_concise_code_map()

    titles: list[str] = []
    categories: list[int] = []
    unmapped: set[str] = set()
    for bill in bills:
        code = area_to_code.get(bill.policy_area)
        category = concise.get(code) if code else None
        if category is None:
            if bill.policy_area:
                unmapped.add(bill.policy_area)
            continue
        if bill.title:
            titles.append(bill.title)
            categories.append(category)

    click.echo(f"  {len(titles)} bills across {len(set(categories))} categories")
    if unmapped:
        # These are policy areas the corpus contains but the concise recode
        # table does not cover, so their bills are dropped from training.
        click.echo(f"  {len(unmapped)} policy areas have no concise category and were skipped:")
        for area in sorted(unmapped):
            click.echo(f"      {area}")

    model = train_tfidf_classifier(titles, categories, test_size=test_size, random_state=seed)
    click.echo(f"\nHeld-out accuracy: {model.accuracy:.2f}%")
    click.echo(
        "  (measured on congressional bills; state legislature titles are a "
        "different domain and will score lower)"
    )

    save_tfidf_classifier(model, output)
    click.echo(f"Wrote {output}")


def main() -> None:
    """Entry point for the CLI."""
    cli()


if __name__ == "__main__":
    main()
