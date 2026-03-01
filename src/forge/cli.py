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
        if chamber in results and results[chamber]:
            ch_data = results[chamber]
            n_bills = len(ch_data.get("bill_ids", []))
            click.echo(f"{chamber.capitalize()}: {n_bills} bills processed")


@cli.command()
@click.option("--optimize", is_flag=True, help="Run iwv/awv grid search optimization.")
@click.option("--xml-dir", type=click.Path(), default="legiscan_data/congressional_xml", help="Congressional XML directory.")
def classify(optimize: bool, xml_dir: str) -> None:
    """Run the bill classification learning algorithm."""
    from forge.classify import cleanup_text, generate_learning_table

    click.echo("Bill classification not yet fully wired (data files needed).")
    if optimize:
        click.echo("Optimization requires pre-parsed training data.")


def main() -> None:
    """Entry point for the CLI."""
    cli()


if __name__ == "__main__":
    main()
