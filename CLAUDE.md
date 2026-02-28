# CLAUDE.md — Forge Project

## Project Overview

Forge is a legislative analysis and prediction system written in MATLAB (~4,900 lines, 63 files), being refactored to Python. It processes U.S. state and federal legislative data from LegiScan to build legislator voting agreement matrices, classify bills by policy area, and predict legislative outcomes using Bayesian inference, Monte Carlo simulation, and Elo rating systems.

**Authors:** Walter Schostak and Eric Waltenburg

## Repository Structure

```
forge/
├── @forge/                # Core engine class (MATLAB) — data reading, vote processing, prediction
│   ├── forge.m            # Class def: properties, init(), readAllFilesOfSubject(), readAllInfo(), addVotes(), cleanVotes(), normalizeVotes()
│   ├── processChamberVotes.m      # Main matrix builder: iterates bills, builds agreement/sponsor matrices, partitions by party
│   ├── processChamberRollcalls.m  # Separates rollcalls into chamber vs. committee by vote count
│   ├── addRollcallVotes.m         # Extracts yes/no/abstain voter lists from a rollcall
│   ├── cleanSponsorVotes.m        # Filters sponsors below threshold
│   ├── getSponsorName.m           # Maps legislator IDs to names
│   ├── processSeatProximity.m     # Euclidean distance between seat positions
│   ├── writeTables.m              # CSV export of all matrices
│   ├── predictOutcomes.m          # Per-bill Bayesian prediction with MC support
│   ├── runMonteCarlo.m            # MC orchestrator, generates boxplots
│   ├── montecarloPrediction.m     # Top-level prediction entry with caching
│   ├── processLegislatorImpacts.m # Per-legislator impact scores from MC results
│   ├── eloPrediction.m            # Single-pass Elo scoring (variable-K + fixed-K)
│   ├── eloMonteCarlo.m            # Elo MC orchestrator with per-category support
│   ├── outputBillInformation.m    # Bill metadata table export (has bugs)
│   └── plotTSet.m                 # T-set visualization helper
├── @state/                # State subclass — configures per-state runs, orchestrates pipeline
│   ├── state.m            # Constructor, run() method, ISSUE_KEY constant
│   └── state_properties.m # Chamber sizes per state (switch statement)
├── +la/                   # Learning algorithm package — bill text classification (NLP)
│   ├── main.m             # Entry point: XML parse → clean → learn → optimize → classify
│   ├── xmlparse.m         # Congressional XML parser with incremental updates
│   ├── cleanupText.m      # Text preprocessing: split, filter, uppercase, deduplicate
│   ├── getCommonWordsList.m  # 700+ stop words
│   ├── generateLearningTable.m   # Per-category word frequency tables
│   ├── classifyBill.m     # Classifies bill title against learned word vectors
│   ├── processAlgorithm.m # Batch classification with accuracy reporting
│   ├── optimizeFrontierSimple.m  # Grid search for iwv/awv parameters
│   ├── loadLearnedMaterials.m    # Loads pre-trained .mat data
│   ├── generateAdjacencyMatrix.m # Confusion matrix generation
│   └── (+ data files: .mat, .xlsx, .csv)
├── +predict/              # Prediction package — Bayesian updating functions
│   ├── updateBayes.m      # Core Bayesian posterior update (vectorized)
│   ├── getSpecificImpact.m # Impact value clamping and direction-flipping
│   ├── updateBayes_old.m  # Deprecated table-based version
│   └── plotTSet.m         # T-set visualization
├── +plot/                 # Visualization package — surface plots, histograms
│   ├── plotRunner.m       # Orchestrates all plots for one chamber
│   ├── generatePlots.m    # 3D surface + flat heatmap with jet colormap
│   ├── generateHistograms.m  # Per-legislator agreement histograms with histfit
│   └── makeGif.m          # GIF animation (unused)
├── +util/                 # Utility package — table creation, ID helpers, JSON parsing
│   ├── +templates/        # Data struct templates (bill, vote, chamber)
│   ├── createIDstrings.m  # Converts numeric IDs to "id{N}" strings
│   ├── createTable.m      # Creates NaN or zero-initialized labeled tables
│   ├── readJSON.m / parse_json.m  # JSON file reading
│   ├── setRandomSeed.m    # Sets Mersenne Twister random seed
│   ├── mergeShorMcCarty.m # Shor-McCarty ideology score merging
│   ├── mergeSeniority.m   # Seniority data merging
│   ├── CStrAinBP.mexw64   # Case-sensitive string matching (Windows MEX binary)
│   └── xml2struct.mexw64  # XML parsing (Windows MEX binary)
├── +finance/              # Campaign finance data processing and merging
│   ├── mergeData.m        # Joins Elo scores with finance data by name
│   └── process.m          # Aggregates finance data by legislator
├── +error_correction/     # Elo scoring error analysis scripts
├── legiscan_data/         # Raw LegiScan CSV/JSON data (all 50 states + DC + US Congress)
├── data/                  # Processed outputs (IN, OR, WI, congressional_archive)
├── finance_data/          # Campaign finance spreadsheets
├── shor_mccarty/          # Shor-McCarty ideology score datasets
├── stata/                 # Stata .do analysis scripts (downstream consumers of CSV output)
├── reference/             # Third-party library zip files (CStrAinBP, xml2struct, pugixml)
├── webcrawler/            # Unused placeholder
├── startup.m              # MATLAB path setup (runs on MATLAB launch)
├── tester.m               # Manual run script for IN
├── PRD.md                 # Program Requirements Document
├── CLAUDE.md              # This file
└── REFACTORING_PLAN.md    # MATLAB-to-Python migration plan
```

## Key Concepts

- **`forge` class** (`@forge/forge.m`) — Superclass (MATLAB `handle` class) containing all data properties, CSV/JSON readers, vote matrix builders, prediction algorithms, and plotting drivers.
- **`state` class** (`@state/state.m`) — Subclass of `forge`. Sets chamber sizes per state, creates output directories, loads the learning algorithm, and runs the full pipeline via `state.run()`.
- **Bill classification** — The `+la` package implements a word-frequency classifier trained on Congressional XML data. Bills are assigned to one of 11 "concise" or 32 "granular" policy categories.
- **Agreement matrices** — NxN legislator tables where cell (i,j) = (times i and j voted the same) / (times both voted). Computed for: chamber votes, committee votes (disabled), sponsorship, and party subsets.
- **Bayesian prediction** — `predict.updateBayes` uses revealed legislator preferences to iteratively update P(bill passes). Formula: `P_new = (impact * P_old) / (impact * P_old + (1-impact) * (1-P_old))`.
- **Elo rating** — Legislators are rated using a chess-style Elo system where "winning" means having higher prediction accuracy. Two variants: variable-K (`K = 8000/clamp(count, 200, 800)`) and fixed-K (`K = 16`).
- **Monte Carlo** — Both the prediction and Elo systems are run across thousands of random legislator orderings (default 16,000 / 15,000 iterations).
- **`CStrAinBP`** — Critical MEX binary for case-sensitive string matching used in ~30 call sites. Returns indices of elements in A that appear in B.

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
| `iwv` / `awv` | 0.13 / 0.0 | `la.main()` |

## Supported States

Configured in `@state/state_properties.m`: CA, NY, WI, OH, OR, VT, KY, IN, ME, MT, US. Each has Senate and House chamber sizes specified. Adding a state requires adding a case to the switch statement and having LegiScan data in `legiscan_data/{STATE}/`.

## Known Issues / Technical Debt

1. Committee vote processing is commented out in `processChamberVotes.m`; committee matrices are always empty.
2. Senate vs. House determination uses `total_vote <= senate_size` — fragile for committees. Source: "THIS REALLY FUCKS UP COMMITTEES."
3. `eloPrediction.m` and `predictOutcomes.m` contain ~60 lines of duplicated code (acknowledged in comments).
4. Indiana has special-case hardcoded data reading logic.
5. Some file paths use Windows backslashes (`+la\parsed_xml.mat`).
6. A `keyboard` debugging statement remains in `state.m:run()` line 263.
7. No automated test suite — `tester.m` is just a manual run script.
8. Third-party MEX binaries (`CStrAinBP.mexw64`, `xml2struct.mexw64`) are Windows-only.
9. Bug in `classifyBill.m`: references `text` instead of `clean_title` at line 13.
10. Bug in `outputBillInformation.m`: references `senate_bill_ids` instead of `chamber_bill_ids` at line 14.
11. Accuracy formula uses hardcoded `100` instead of actual legislator count.

## Build / Run (Current MATLAB)

1. Open MATLAB in the `forge/` directory — `startup.m` runs automatically to set paths.
2. Run `tester.m` or create a `state` object directly: `a = state('IN'); a.recompute = true; a.run();`
3. For the learning algorithm: `la.main()`

## Build / Run (Python — Future)

_Target stack: pandas, numpy, scipy, scikit-learn, matplotlib, seaborn, lxml, click, pytest._
_See REFACTORING_PLAN.md for the full migration strategy._

## Conventions for the Refactoring

- Preserve the same directory output structure (`data/{STATE}/outputs/`, etc.)
- Maintain CSV output format compatibility so existing Stata scripts continue to work.
- Use reproducible random seeds — verify against MATLAB `rng` behavior where possible.
- Maintain the same classification accuracy thresholds as validation gates.
- All Python code should include type hints and docstrings.
- Use `pytest` for testing with Indiana as the reference validation state.
- Clean up technical debt as we go: remove commented-out code, fix bugs, deduplicate shared logic between `predictOutcomes` and `eloPrediction`.
- Do not add new features during the refactoring.
