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

Nine of the eleven produce full output. Two do not, and both were only
discovered by running every state rather than the three with goldens:

| State | Status |
|-------|--------|
| KY | **No output.** `legiscan_data/KY/` has zero rollcall rows — a data gap, not a code defect. |
| ME | **Substantially incomplete** (31 House / 6 Senate bills). Maine records passage as parliamentary abbreviations — "Acc Maj OTP Rep" — which the passage pattern does not model; only 84 of 2,514 rollcalls are recognised. Deciding which motions count is a domain judgement, so it is left open. |

A state whose rollcall vocabulary is unrecognised produces **empty matrices
while the run exits successfully**. New York was in this state until the
`FINAL PASSAGE` alternative was added: all 10,127 of its rollcalls read
"Floor Vote - Final Passage" and every one was discarded, because the pattern
required the literal "ON PASSAGE". The pipeline now logs a WARNING when a
chamber matches no bills, and `tests/test_integration/test_passage_vocabulary.py`
asserts a floor on matches for every state with committed data.

When extending `_PASSAGE_PATTERN`, keep the change *additive*. Relaxing it to a
bare `PASSAGE` was measured and would additionally match committee "Do Pass"
motions in OR (+124), OH (+446), CA (+574) and US (+3) — silently changing
results for states that currently reproduce MATLAB exactly.

## Known Issues / Technical Debt

1. Committee vote processing is commented out in `processChamberVotes.m`; committee matrices are always empty.
2. Senate vs. House determination uses `total_vote <= senate_size` — fragile for committees. Source: "THIS REALLY FUCKS UP COMMITTEES."
3. `eloPrediction.m` and `predictOutcomes.m` contain ~60 lines of duplicated code (acknowledged in comments).
4. Indiana has special-case hardcoded data reading logic — the House roster comes from `data/IN/undergrad/people_2013-2014.xlsx`, not LegiScan (LegiScan's 2016 roster lists 104 members for a 100-seat chamber). Ported in `runner._load_indiana_house_people`.
5. Some file paths use Windows backslashes (`+la\parsed_xml.mat`).
6. A `keyboard` debugging statement remains in `state.m:run()` line 263.
7. No automated test suite — `tester.m` is just a manual run script.
8. Third-party MEX binaries (`CStrAinBP.mexw64`, `xml2struct.mexw64`) are Windows-only.
9. Bug in `classifyBill.m`: references `text` instead of `clean_title` at line 13.
10. Bug in `outputBillInformation.m`: references `senate_bill_ids` instead of `chamber_bill_ids` at line 14.
11. Accuracy formula uses hardcoded `100` instead of actual legislator count.

## Bill Classification

Two classifiers exist. `ForgeConfig.classifier` selects between them, and the
choice changes which bills are analysed, so it is a scientific decision rather
than a setting.

| | Held-out accuracy | Unclassified |
|---|---|---|
| `"tfidf"` (default) — TF-IDF + linear SVM | **84.3%** | 0% |
| `"legacy"` — MATLAB word-frequency scorer | 42.9% | ~5% |

Accuracy is measured on held-out *congressional* bills, the only labelled corpus
available. The model is applied to *state* titles, which are shorter and drafted
differently — **84.3% must not be quoted as state-level accuracy.** Closing that
gap needs a hand-labelled sample of state bills; nothing here can measure it.

Train the model once after cloning (it is not committed — 4.4 MB, and
scikit-learn pickles are version-fragile):

```bash
forge classify              # ~40s, writes +la/tfidf_classifier.pkl
```

Without it the pipeline warns and falls back to `"legacy"`.

`"legacy"` is required to reproduce the committed MATLAB outputs: it leaves ~5%
of bills unclassified, and those bills are consequently absent from the pooled
category-0 matrices. Every golden comparison pins `classifier="legacy"` for that
reason. Switching to `"tfidf"` on Indiana adds 5 House bills to the matrices and
moves the pooled agreement matrix by 0.0055 mean absolute — small, because
pooling depends on which bills are included rather than on their category.
Per-category matrices move much more.

## The Reproducible Baseline

The committed MATLAB outputs cannot be reproduced — the classifier that made
them is gone. `baseline/` is the reproducible counterpart: matrix outputs for
all eleven configured states, regenerated from committed inputs by

```bash
forge classify                      # ~60s, trains +la/tfidf_classifier.pkl
./scripts/regenerate_baseline.sh    # ~15 min, all states
```

It is gitignored (~100 MB of derived CSVs) apart from `baseline/README.md`,
which carries the per-state coverage table and the agreement measurements.
Verified byte-identical across repeated runs. Monte Carlo and Elo outputs are
*not* included: they are stochastic and cost hours to days, so they remain
on-demand.

`scripts/compare_baseline_to_matlab.py` quantifies the gap against the MATLAB
outputs for the three states that have them. The headline result:

**Oregon and Wisconsin reproduce MATLAB exactly under the TF-IDF classifier**
— mean|Δ| = 0.0000 on every golden file. This is not luck. The legacy scorer
left 36 Oregon and 25 Wisconsin bills unclassified, and none of them had a
competitive passage vote, so none was ever eligible for the pooled matrix; the
bill set is identical either way. Indiana is the exception because 9 of its 142
unclassified bills *are* eligible, so the new classifier adds them — which is
why only Indiana moves (mean|Δ| 0.0073 House, 0.0009 Senate) and why its raw
co-vote tallies shift by ~4 on average.

The practical consequence: **switching classifiers does not invalidate the
pooled Oregon and Wisconsin results.** Per-category matrices are a different
matter and do move.

## Validating the Python Port

`tests/test_integration/` runs the real Indiana pipeline and diffs its output
against the committed MATLAB results in `data/IN/outputs/`. This is the only
test that can catch a stage silently producing nothing — the rest of the suite
builds synthetic inputs, so it validates self-consistency, not correctness.

```bash
pytest tests/test_integration/ -v     # all golden comparisons (~5 min)
pytest                                # everything (~7 min)
```

What lives where in `tests/test_integration/`:

| Module | Scope |
|--------|-------|
| `test_multistate_golden.py` | Oregon and Wisconsin — exact, both chambers |
| `test_matrix_invariants.py` | Properties true for *any* classification |
| `test_passage_vocabulary.py` | Every state's rollcall phrasing is recognised |
| `test_indiana_golden.py` | Indiana pooled category 0 |
| `test_indiana_categories.py` | Indiana per-category — pinned to the current classifier |
| `test_indiana_elo.py` | Elo structure and rating invariants |
| `test_indiana_plots.py` | Figures are produced and are real PNGs |

`test_matrix_invariants.py` is the module to trust when the categorization logic
is replaced: it asserts pooling consistency, symmetry, ratio bounds and party
partitioning, none of which depend on how bills are assigned to policy areas.
`test_indiana_categories.py` is the one to retire at that point rather than
retune — its expectations describe the current classifier.

Current parity:

| Output | Agreement with MATLAB |
|--------|-----------------------|
| **Oregon — all 16 outputs, both chambers** | **exact** |
| **Wisconsin — all 16 outputs, both chambers** | **exact** |
| Indiana seat proximity | 5e-14 (floating point) |
| Indiana per-category, categories 6, 7, 9, 10, 11 | ~5e-16 (floating point) |
| Indiana per-category, categories 1–5, 8 | up to 0.33 |
| Indiana pooled category 0 | ~0.6% mean absolute error |
| Indiana Monte Carlo `coverage` | Pearson 0.9995 |
| Indiana Monte Carlo impact `results` | Spearman ~0.82 |
| Elo | structure and invariants only — see below |

**Oregon and Wisconsin reproduce MATLAB exactly** — every committed output file,
both chambers, agreement ratios and raw integer tallies alike. That is the
headline: where Indiana's classifier and roster provenance are not in play, the
port is not approximately right, it is identical.

Indiana is the outlier and its goldens are the unreliable party. Its classifier
vintage is gone, its prediction and Elo outputs use a different roster from its
matrix outputs, its `saved_data.mat` is stale, and its filenames come from a
different era again. Do not tune the port to close Indiana's residual — a fix
that is provably correct (sorting rollcalls by date, forge.m:147) made Oregon
and Wisconsin exact while making Indiana *worse*. See `REFACTORING_PLAN.md`.

**The classifier that generated the committed outputs no longer exists** — it is
not in the repository and neither author has it. That means the goldens cannot
be reproduced exactly by any amount of work, and they are best treated as a
historical reference rather than a target. The route to a reproducible baseline
is retraining from the congressional corpus and regenerating; note that
`forge classify` is currently a stub, so that path needs wiring first.

Elo is validated for structure and rating invariants but not values: MATLAB's
goldens are at 15,000 Monte Carlo iterations, roughly a day of compute, so a
test-scale run has not converged and any tolerance loose enough to pass would
prove nothing.

Tolerances are set just above measured error so they act as regression gates.

Two things this harness depends on, both easy to break:
- `+la/learning_algorithm_data.mat` — the MATLAB-trained classifier. Without
  it, bills go unclassified and every category-filtered matrix comes out empty.
- `data/IN/undergrad/people_2013-2014.xlsx` — Indiana's curated House roster.

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
