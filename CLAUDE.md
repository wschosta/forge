# CLAUDE.md — Forge Project

## Project Overview

Forge is a legislative analysis and prediction system originally written in MATLAB, being refactored to Python. It processes U.S. state and federal legislative data from LegiScan to build legislator voting agreement matrices, classify bills by policy area, and predict legislative outcomes using Bayesian inference, Monte Carlo simulation, and Elo rating systems.

**Authors:** Walter Schostak and Eric Waltenburg

## Repository Structure

```
forge/
├── @forge/              # Core engine class (MATLAB) — data reading, vote processing, prediction
├── @state/              # State subclass (MATLAB) — configures per-state runs, orchestrates pipeline
├── +la/                 # Learning algorithm package — bill text classification (NLP)
├── +predict/            # Prediction package — Bayesian updating functions
├── +plot/               # Visualization package — surface plots, histograms
├── +util/               # Utility package — table creation, ID helpers, JSON parsing
│   └── +templates/      # Data struct templates (bill, vote, chamber)
├── +finance/            # Campaign finance data processing and merging
├── +error_correction/   # Elo scoring error analysis scripts
├── legiscan_data/       # Raw LegiScan CSV/JSON data (all 50 states + DC + US Congress)
├── data/                # Processed outputs per state (IN, OR, WI, congressional_archive)
├── finance_data/        # Campaign finance spreadsheets
├── shor_mccarty/        # Shor-McCarty ideology score datasets
├── stata/               # Stata .do analysis scripts
├── reference/           # Third-party library zip files (CStrAinBP, xml2struct, pugixml)
├── webcrawler/          # Unused — placeholder for newspaper scraping
├── startup.m            # MATLAB path setup (runs on MATLAB launch)
├── tester.m             # Main entry point / run script
├── PRD.md               # Program Requirements Document
└── CLAUDE.md            # This file
```

## Key Concepts

- **`forge` class** — Superclass containing all data properties, CSV/JSON readers, vote matrix builders, prediction algorithms, and plotting drivers. Handle class defined in `@forge/`.
- **`state` class** — Subclass of `forge`. Sets chamber sizes per state, creates output directories, loads the learning algorithm, and runs the full pipeline via `state.run()`.
- **Bill classification** — The `+la` package implements a word-frequency-based classifier trained on Congressional XML data. Bills are assigned to one of 11 "concise" or 32 "granular" policy categories.
- **Agreement matrices** — NxN legislator matrices where cell (i,j) = (times i and j voted the same) / (times both voted). Computed for: chamber votes, committee votes, sponsorship, and party subsets.
- **Bayesian prediction** — `predict.updateBayes` uses revealed legislator preferences to iteratively update P(bill passes) using prior voting agreement scores.
- **Elo rating** — Legislators are rated using a chess-style Elo system where "winning" means having higher prediction accuracy. Two variants: variable-K and fixed-K (K=16).
- **Monte Carlo** — Both the prediction and Elo systems are run across thousands of random legislator orderings (default 16,000 / 15,000 iterations).

## Data Flow

```
LegiScan CSV/JSON → forge.init() → bill_set map + tables
                                          ↓
                    state.run() → processChamberVotes() → agreement matrices
                                          ↓
                    writeTables() → CSV exports
                    plot.plotRunner() → PNG visualizations
                                          ↓
                    montecarloPrediction() / eloMonteCarlo() → prediction outputs
                                          ↓
                    finance.mergeData() / util.mergeShorMcCarty() → merged CSV
```

## Important Configuration

| Parameter | Default | Where Set |
|-----------|---------|-----------|
| `monte_carlo_number` | 16,000 | `state.m` constructor |
| `elo_monte_carlo_number` | 15,000 | `state.m:run()` |
| `committee_threshold` | 0.75 | `state.m` constructor |
| `competitive_threshold` | 0.85 | `state.m` constructor |
| `bayes_initial` | 0.5 | `predictOutcomes.m` / `eloPrediction.m` |
| `cut_off` | 3,001 | `generateLearningTable.m` |

## Supported States

Configured in `@state/state_properties.m`: CA, NY, WI, OH, OR, VT, KY, IN, ME, MT, US. Each has Senate and House chamber sizes specified. Adding a state requires adding a case to the switch statement and having LegiScan data in `legiscan_data/{STATE}/`.

## Known Issues / Technical Debt

1. Committee vote processing is commented out in `processChamberVotes.m`; committee matrices are always empty.
2. Senate vs. House determination uses total vote count vs. chamber size — fragile for committees.
3. Indiana has special-case hardcoded data reading logic.
4. `eloPrediction.m` and `predictOutcomes.m` contain significant duplicated code.
5. Some file paths use Windows backslashes (`+la\parsed_xml.mat`).
6. A `keyboard` debugging statement remains in `state.m:run()`.
7. No automated test suite — `tester.m` is just a manual run script.
8. Third-party MEX binaries (`CStrAinBP.mexw64`, `xml2struct.mexw64`) are Windows-only.

## Build / Run (Current MATLAB)

1. Open MATLAB in the `forge/` directory — `startup.m` runs automatically to set paths.
2. Run `tester.m` or create a `state` object directly: `a = state('IN'); a.recompute = true; a.run();`
3. For the learning algorithm: `la.main()`

## Build / Run (Python — Future)

_To be defined during the refactoring process. Target stack: pandas, numpy, scipy, scikit-learn, matplotlib._

## Conventions for the Refactoring

- Preserve the same directory output structure (`data/{STATE}/outputs/`, etc.)
- Maintain CSV output format compatibility so existing Stata scripts continue to work.
- Use reproducible random seeds matching the MATLAB `rng` behavior where possible.
- Maintain the same classification accuracy thresholds as validation gates.
- All Python code should include type hints and docstrings.
- Use `pytest` for testing.
