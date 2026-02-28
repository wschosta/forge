# MATLAB-to-Python Refactoring Plan
# The Forge Project

**Date:** 2026-02-28
**Scope:** Full conversion of ~3,100 lines of MATLAB across 60 files to Python

---

## Table of Contents

1. [Guiding Principles](#1-guiding-principles)
2. [Target Python Stack](#2-target-python-stack)
3. [Project Layout](#3-target-project-layout)
4. [MATLAB-to-Python Mapping](#4-matlab-to-python-concept-mapping)
5. [Phase 0: Scaffolding and Infrastructure](#phase-0-scaffolding-and-infrastructure)
6. [Phase 1: Utilities and Data Templates](#phase-1-utilities-and-data-templates)
7. [Phase 2: Data Ingestion Layer](#phase-2-data-ingestion-layer)
8. [Phase 3: Bill Classification / Learning Algorithm](#phase-3-bill-classification--learning-algorithm)
9. [Phase 4: Vote Processing and Agreement Matrices](#phase-4-vote-processing-and-agreement-matrices)
10. [Phase 5: Bayesian Prediction and Monte Carlo](#phase-5-bayesian-prediction-and-monte-carlo)
11. [Phase 6: Elo Rating System](#phase-6-elo-rating-system)
12. [Phase 7: Visualization](#phase-7-visualization)
13. [Phase 8: Data Merging and Export](#phase-8-data-merging-and-export)
14. [Phase 9: Integration, CLI, and Orchestration](#phase-9-integration-cli-and-orchestration)
15. [Phase 10: Validation and Testing](#phase-10-validation-and-testing)
16. [Risk Register](#risk-register)
17. [Migration Checklist](#migration-checklist)

---

## 1. Guiding Principles

1. **Fidelity first** — Numerical outputs from the Python version must match MATLAB outputs for the same inputs. Validate with Indiana (IN) as the reference state.
2. **Bottom-up build order** — Start with leaf-level utilities, then build upward. Each phase should be independently testable before the next begins.
3. **Preserve output compatibility** — CSV output structure and column names must remain identical so existing Stata `.do` scripts work unchanged.
4. **Incremental delivery** — Each phase produces runnable, tested code. No "big bang" rewrite.
5. **Clean up technical debt as we go** — Remove commented-out code, eliminate duplicated logic, fix Windows-only paths. But don't add new features.
6. **Type safety** — Use Python type hints throughout. Use dataclasses or Pydantic models for structured data.

---

## 2. Target Python Stack

| Purpose | Library | Replaces |
|---------|---------|----------|
| DataFrames & tables | `pandas` | MATLAB `table`, `readtable`, `writetable` |
| Numerical computation | `numpy` | MATLAB matrix operations, `bsxfun` |
| Scientific computing | `scipy` | MATLAB `histfit`, optimization |
| Visualization | `matplotlib` + `seaborn` | MATLAB `figure`, `surf`, `histogram`, `boxplot` |
| XML parsing | `xml.etree.ElementTree` or `lxml` | `xml2struct` MEX binary |
| JSON parsing | `json` (stdlib) | `util.parse_json` / `util.readJSON` |
| String matching | `pandas` / native Python | `CStrAinBP` MEX binary |
| NLP text processing | `re` (stdlib) | `la.cleanupText` regex operations |
| Serialization | `pickle` / `parquet` | MATLAB `.mat` files |
| Testing | `pytest` | None (no tests exist currently) |
| CLI | `argparse` or `click` | `tester.m` script |
| Configuration | `dataclasses` or YAML | Hardcoded MATLAB properties |
| Reproducibility | `numpy.random.default_rng(seed)` | `util.setRandomSeed` → MATLAB `rng` |

### Python Version

Target Python 3.10+ (for `match` statements, union types with `|`, and `dataclasses` improvements).

---

## 3. Target Project Layout

```
forge/
├── pyproject.toml              # Project metadata, dependencies
├── CLAUDE.md
├── PRD.md
├── REFACTORING_PLAN.md
├── src/
│   └── forge/
│       ├── __init__.py
│       ├── cli.py              # Command-line entry point
│       ├── config.py           # State properties, constants, parameters
│       ├── models/
│       │   ├── __init__.py
│       │   ├── bill.py         # Bill dataclass (replaces getBillTemplate)
│       │   ├── vote.py         # Vote dataclass (replaces getVoteTemplate)
│       │   └── chamber.py      # Chamber dataclass (replaces getChamberTemplate)
│       ├── ingest/
│       │   ├── __init__.py
│       │   ├── csv_reader.py   # LegiScan CSV reading (replaces readAllFilesOfSubject)
│       │   ├── json_reader.py  # LegiScan JSON reading (replaces readAllInfo)
│       │   └── xml_parser.py   # Congressional XML parsing (replaces la.xmlparse)
│       ├── classify/
│       │   ├── __init__.py
│       │   ├── text_cleanup.py # Text preprocessing (replaces la.cleanupText)
│       │   ├── learning.py     # Learning table generation (replaces la.generateLearningTable)
│       │   ├── classifier.py   # Bill classifier (replaces la.classifyBill, la.processAlgorithm)
│       │   └── optimizer.py    # Frontier optimization (replaces la.optimizeFrontierSimple)
│       ├── matrices/
│       │   ├── __init__.py
│       │   ├── agreement.py    # Agreement matrix builder (replaces processChamberVotes)
│       │   ├── rollcalls.py    # Rollcall processor (replaces processChamberRollcalls)
│       │   ├── sponsorship.py  # Sponsorship matrix logic
│       │   ├── consistency.py  # Chamber-committee consistency
│       │   └── proximity.py    # Seat proximity (replaces processSeatProximity)
│       ├── predict/
│       │   ├── __init__.py
│       │   ├── bayes.py        # Bayesian updating (replaces predict.updateBayes)
│       │   ├── monte_carlo.py  # Monte Carlo simulation (replaces runMonteCarlo, predictOutcomes)
│       │   └── impact.py       # Legislator impact scoring (replaces processLegislatorImpacts)
│       ├── elo/
│       │   ├── __init__.py
│       │   ├── rating.py       # Elo prediction (replaces eloPrediction)
│       │   └── monte_carlo.py  # Elo Monte Carlo (replaces eloMonteCarlo)
│       ├── merge/
│       │   ├── __init__.py
│       │   ├── finance.py      # Finance data merge (replaces +finance/mergeData, process)
│       │   └── ideology.py     # Shor-McCarty merge (replaces util.mergeShorMcCarty)
│       ├── viz/
│       │   ├── __init__.py
│       │   ├── surfaces.py     # 3D surface / heatmap plots (replaces generatePlots)
│       │   ├── histograms.py   # Histogram generation (replaces generateHistograms)
│       │   └── predictions.py  # Prediction boxplots (replaces runMonteCarlo plotting)
│       ├── export/
│       │   ├── __init__.py
│       │   └── csv_writer.py   # CSV export (replaces writeTables)
│       └── pipeline.py         # Main orchestrator (replaces state.run + forge.init)
├── tests/
│   ├── conftest.py             # Shared fixtures (sample data)
│   ├── test_config.py
│   ├── test_models.py
│   ├── test_ingest/
│   │   ├── test_csv_reader.py
│   │   ├── test_json_reader.py
│   │   └── test_xml_parser.py
│   ├── test_classify/
│   │   ├── test_text_cleanup.py
│   │   ├── test_classifier.py
│   │   └── test_learning.py
│   ├── test_matrices/
│   │   ├── test_agreement.py
│   │   └── test_rollcalls.py
│   ├── test_predict/
│   │   ├── test_bayes.py
│   │   └── test_monte_carlo.py
│   ├── test_elo/
│   │   └── test_rating.py
│   └── test_integration/
│       └── test_indiana_pipeline.py  # End-to-end validation against MATLAB outputs
├── data/                       # (existing) processed data
├── legiscan_data/              # (existing) raw data
├── finance_data/               # (existing) finance data
├── shor_mccarty/               # (existing) ideology data
└── matlab_archive/             # (new) original MATLAB files moved here for reference
    ├── @forge/
    ├── @state/
    ├── +la/
    ├── +predict/
    ├── +plot/
    ├── +util/
    ├── +finance/
    ├── +error_correction/
    ├── startup.m
    └── tester.m
```

---

## 4. MATLAB-to-Python Concept Mapping

| MATLAB Concept | Python Equivalent | Notes |
|---|---|---|
| `classdef` handle class | Python class (no need for handle semantics; Python objects are references by default) | |
| `containers.Map` | `dict` | |
| `table` | `pandas.DataFrame` | |
| `struct` | `dataclass` or `dict` | Prefer `dataclass` for typed templates |
| `cell array` | `list` | |
| `NaN` | `numpy.nan` or `float('nan')` | |
| `readtable()` | `pandas.read_csv()` | |
| `writetable()` | `df.to_csv()` | |
| `regexp()` | `re.search()` / `re.findall()` | |
| `regexprep()` | `re.sub()` | |
| `sprintf()` | f-strings or `str.format()` | |
| `containers.Map('KeyType','int32','ValueType','any')` | `dict[int, Any]` | |
| `array2table()` | `pd.DataFrame(data, index=..., columns=...)` | |
| `bsxfun(@minus,x,x')` | `x[:, None] - x[None, :]` (numpy broadcasting) | |
| `histogram()` | `plt.hist()` or `sns.histplot()` | |
| `surf()` | `ax.plot_surface()` or `sns.heatmap()` | |
| `boxplot()` | `plt.boxplot()` or `sns.boxplot()` | |
| `saveas(gcf,path,'png')` | `plt.savefig(path)` | |
| `save(...,'.mat')` | `pickle.dump()` or `df.to_parquet()` | |
| `load(...,'.mat')` | `pickle.load()` or `pd.read_parquet()` | |
| `inputParser` | `argparse` (CLI) or function kwargs with defaults | |
| MATLAB packages (`+pkg`) | Python packages (directories with `__init__.py`) | |
| MATLAB class folders (`@class`) | Regular Python classes in modules | |
| `CStrAinBP(A, B)` | `pd.Index.isin()`, `np.isin()`, or list comprehension | Critical — used everywhere |
| `xml2struct` | `xml.etree.ElementTree` or `lxml` | |
| `rng(seed)` | `numpy.random.default_rng(seed)` | Verify output parity |

---

## Phase 0: Scaffolding and Infrastructure

**Goal:** Set up the Python project skeleton, dependency management, and CI.

### Steps

| # | Task | Files Created |
|---|------|---------------|
| 0.1 | Create `pyproject.toml` with dependencies (pandas, numpy, scipy, matplotlib, seaborn, lxml, pytest, click) | `pyproject.toml` |
| 0.2 | Create `src/forge/__init__.py` and all sub-package `__init__.py` files | ~15 `__init__.py` files |
| 0.3 | Create `tests/conftest.py` with fixtures pointing to sample LegiScan data (use a small state like DC or a subset of IN) | `tests/conftest.py` |
| 0.4 | Create `.gitignore` entries for `__pycache__`, `.pytest_cache`, `*.pyc`, virtual envs | `.gitignore` update |
| 0.5 | Verify `pip install -e .` works and `pytest` discovers test directory | — |
| 0.6 | Move all original MATLAB files to `matlab_archive/` for reference (preserve git history) | `matlab_archive/` |

### Validation Gate
- `pip install -e .` succeeds
- `pytest` runs (zero tests pass, zero tests fail — empty suite)

---

## Phase 1: Utilities and Data Templates

**Goal:** Port the foundational utility functions and data model templates that everything else depends on.

### MATLAB → Python Mapping

| MATLAB File | Python File | Key Changes |
|---|---|---|
| `+util/+templates/getBillTemplate.m` | `src/forge/models/bill.py` | Convert struct template to `@dataclass` with typed fields |
| `+util/+templates/getVoteTemplate.m` | `src/forge/models/vote.py` | Convert struct template to `@dataclass` |
| `+util/+templates/getChamberTemplate.m` | `src/forge/models/chamber.py` | Convert struct template to `@dataclass` |
| `+util/createTable.m` | `src/forge/matrices/agreement.py` (inline) | Replace with `pd.DataFrame` construction |
| `+util/createIDstrings.m` | `src/forge/config.py` (utility function) | `lambda x: f"id{x}"` or similar |
| `+util/greaterThanZero.m` | Remove — trivial | Use `> 0` inline |
| `+util/setRandomSeed.m` | `numpy.random.default_rng(seed)` | Inline where needed |
| `+util/parse_json.m` / `readJSON.m` | `json.load()` (stdlib) | Direct replacement |
| `CStrAinBP` (MEX binary) | Custom helper using `pd.Index.isin()` or `np.isin()` | **Critical migration item** — used in ~30 call sites |
| `@state/state_properties.m` | `src/forge/config.py` | Dict mapping state codes to `(senate_size, house_size)` |
| Constants (PARTY_KEY, VOTE_KEY, ISSUE_KEY) | `src/forge/config.py` | Python dicts |

### Steps

| # | Task |
|---|------|
| 1.1 | Create `config.py` with `STATE_PROPERTIES` dict, `PARTY_KEY`, `VOTE_KEY`, `ISSUE_KEY`, and `create_id_strings()` function |
| 1.2 | Create `models/bill.py` with `Bill` dataclass matching `getBillTemplate` fields |
| 1.3 | Create `models/vote.py` with `Vote` dataclass matching `getVoteTemplate` fields |
| 1.4 | Create `models/chamber.py` with `ChamberData` dataclass |
| 1.5 | Implement `cstr_ainbp()` — a Python equivalent of the CStrAinBP MEX function. This is used pervasively and must be correct. It returns indices of elements in list A that appear in list B. |
| 1.6 | Write tests for all of the above |

### Validation Gate
- All `test_config.py` and `test_models.py` tests pass
- `cstr_ainbp()` matches MATLAB `CStrAinBP` behavior on sample inputs

---

## Phase 2: Data Ingestion Layer

**Goal:** Read LegiScan CSV and JSON data into pandas DataFrames, matching the exact structure produced by MATLAB's `readAllFilesOfSubject` and `readAllInfo`.

### MATLAB → Python Mapping

| MATLAB | Python | Notes |
|---|---|---|
| `forge.readAllFilesOfSubject()` | `ingest/csv_reader.py::read_all_csv()` | Iterates session dirs, reads CSV, appends year column, handles schema differences |
| `forge.readAllInfo()` | `ingest/json_reader.py::read_all_json()` | Reads bill/vote/people JSON, builds dict structures |
| `la.xmlparse()` | `ingest/xml_parser.py::parse_congressional_xml()` | Parses XML bills for learning algorithm training data |

### Steps

| # | Task |
|---|------|
| 2.1 | Implement `csv_reader.py::read_all_csv(data_type, state)` — reads `legiscan_data/{state}/*/csv/{type}.csv`, concatenates with year column, handles missing columns |
| 2.2 | Implement derived fields for rollcalls: `total_vote`, `yes_percent`, `senate` flag |
| 2.3 | Implement `json_reader.py::read_all_json(state)` — reads JSON bill/vote/people files, returns dicts keyed by ID |
| 2.4 | Implement `xml_parser.py::parse_congressional_xml()` — parses `data/congressional_archive/*.xml` using `lxml` or `ElementTree` |
| 2.5 | Add caching: save processed DataFrames to `data/{state}/processed_data.pkl` (or `.parquet`) |
| 2.6 | Write tests using a small subset of real data (e.g., a single session from KY or a small state) |

### Validation Gate
- `read_all_csv('bills', 'IN')` produces a DataFrame with identical columns and row count to MATLAB
- `read_all_csv('people', 'IN').shape` matches MATLAB
- XML parser produces the same number of valid bills as MATLAB's `xmlparse`

---

## Phase 3: Bill Classification / Learning Algorithm

**Goal:** Port the text-based bill classification system from `+la/`.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `la.cleanupText()` | `classify/text_cleanup.py::cleanup_text()` |
| `la.getCommonWordsList()` | `classify/text_cleanup.py::get_common_words()` |
| `la.generateLearningTable()` | `classify/learning.py::generate_learning_table()` |
| `la.classifyBill()` | `classify/classifier.py::classify_bill()` |
| `la.processAlgorithm()` | `classify/classifier.py::process_all_bills()` |
| `la.loadLearnedMaterials()` | `classify/learning.py::load_learned_materials()` |
| `la.optimizeFrontierSimple()` | `classify/optimizer.py::optimize_frontier()` |
| `la.generateAdjacencyMatrix()` | `classify/classifier.py::generate_adjacency_matrix()` |
| `la.generateConciseMaps()` | `classify/learning.py` (inline in configuration) |
| `la.main()` | `classify/__init__.py::run_learning_pipeline()` |

### Steps

| # | Task |
|---|------|
| 3.1 | Port `cleanup_text()` — regex-based word splitting, common word removal, uppercasing, deduplication with frequency weights |
| 3.2 | Port `get_common_words()` — the stop-word list |
| 3.3 | Port `generate_learning_table()` — builds per-category word frequency weights from training data |
| 3.4 | Port `classify_bill()` — scores a bill title against learned word vectors, returns highest-scoring category |
| 3.5 | Port `process_all_bills()` — runs classifier on all bills, computes accuracy statistics |
| 3.6 | Port `optimize_frontier()` — grid search over iwv/awv parameters |
| 3.7 | Port concise category recoding (32 → 11 categories) |
| 3.8 | Write tests comparing classification accuracy against MATLAB baseline |

### Validation Gate
- `classify_bill(title, data_storage)` returns the same category as MATLAB for a sample of 100 bills
- Overall accuracy within 1% of MATLAB baseline on the full training set

---

## Phase 4: Vote Processing and Agreement Matrices

**Goal:** Port the core vote processing logic that builds NxN agreement, sponsorship, and consistency matrices.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `forge.init()` (bill processing loop) | `pipeline.py::build_bill_set()` |
| `forge.processChamberRollcalls()` | `matrices/rollcalls.py::process_chamber_rollcalls()` |
| `forge.addRollcallVotes()` | `matrices/rollcalls.py::add_rollcall_votes()` |
| `state.processChamberVotes()` | `matrices/agreement.py::process_chamber_votes()` |
| `forge.addVotes()` | `matrices/agreement.py::add_votes()` |
| `forge.cleanVotes()` | `matrices/agreement.py::clean_votes()` |
| `forge.cleanSponsorVotes()` | `matrices/agreement.py::clean_sponsor_votes()` |
| `forge.normalizeVotes()` | `matrices/agreement.py::normalize_votes()` |
| `forge.processParties()` | `matrices/agreement.py::split_by_party()` |
| `forge.processSeatProximity()` | `matrices/proximity.py::compute_seat_proximity()` |

### Steps

| # | Task |
|---|------|
| 4.1 | Port `build_bill_set()` — iterates bills, creates Bill objects, classifies them, attaches rollcall/sponsor/history data |
| 4.2 | Port `process_chamber_rollcalls()` — separates committee vs. chamber votes by size threshold |
| 4.3 | Port `add_rollcall_votes()` — extracts yes/no/abstain lists from individual rollcalls |
| 4.4 | Port `process_chamber_votes()` — the large function that builds all 4 matrix types (chamber, committee, sponsor-chamber, sponsor-committee), filters by competitiveness and category |
| 4.5 | Port `add_votes()`, `clean_votes()`, `normalize_votes()` as DataFrame operations |
| 4.6 | Port party splitting — filter matrices by Republican/Democrat IDs |
| 4.7 | Port `compute_seat_proximity()` — Euclidean distance between seat positions |
| 4.8 | **Deduplicate** — The MATLAB code has significant shared logic between chamber and committee processing. Unify into a single parameterized function. |
| 4.9 | Write tests comparing output matrices against MATLAB CSV exports for IN |

### Validation Gate
- For Indiana, `process_chamber_votes(house_people, 'house', 0)` produces a chamber matrix that matches `data/IN/outputs/H_cha_A_matrix_0.csv` to within floating-point tolerance (1e-10)

---

## Phase 5: Bayesian Prediction and Monte Carlo

**Goal:** Port the Bayesian updating and Monte Carlo prediction system.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `predict.updateBayes()` | `predict/bayes.py::update_bayes()` |
| `predict.getSpecificImpact()` | `predict/bayes.py::get_specific_impact()` |
| `forge.predictOutcomes()` | `predict/monte_carlo.py::predict_outcomes()` |
| `forge.runMonteCarlo()` | `predict/monte_carlo.py::run_monte_carlo()` |
| `forge.montecarloPrediction()` | `predict/monte_carlo.py::monte_carlo_prediction()` |
| `forge.processLegislatorImpacts()` | `predict/impact.py::process_legislator_impacts()` |

### Steps

| # | Task |
|---|------|
| 5.1 | Port `get_specific_impact()` — clamps and flips impact values |
| 5.2 | Port `update_bayes()` — core Bayesian posterior update using agreement matrix and revealed preferences |
| 5.3 | Port `predict_outcomes()` — per-bill prediction with sponsor effect and iterative Bayesian updates |
| 5.4 | Port `run_monte_carlo()` — runs prediction across all bills with configurable MC iterations |
| 5.5 | Port `monte_carlo_prediction()` — orchestrator that loads/saves results |
| 5.6 | Port `process_legislator_impacts()` — computes per-legislator impact scores using placement-weighted deltas |
| 5.7 | **Vectorize** — The inner loop in `update_bayes` is already partially vectorized in MATLAB; ensure numpy operations are used in Python for performance |
| 5.8 | Write unit tests for `update_bayes()` with known inputs/outputs |

### Validation Gate
- `update_bayes()` produces identical outputs to MATLAB for a set of hand-crafted test vectors
- Monte Carlo prediction accuracy distribution for IN House matches MATLAB within statistical tolerance

---

## Phase 6: Elo Rating System

**Goal:** Port the Elo scoring system, including the Monte Carlo wrapper.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `forge.eloPrediction()` | `elo/rating.py::elo_prediction()` |
| `forge.eloMonteCarlo()` | `elo/monte_carlo.py::elo_monte_carlo()` |
| `+error_correction/elo_scoring.m` | Remove — test/exploration script, not production code |

### Steps

| # | Task |
|---|------|
| 6.1 | Port `elo_prediction()` — single Elo pass over all bills. **Deduplicate** the shared Bayesian logic with `predict_outcomes()` by extracting common sponsor-effect and preference-revelation code into shared functions. |
| 6.2 | Port the two Elo variants: variable-K (`K = 8000/clamp(count, 200, 800)`) and fixed-K (`K = 16`) |
| 6.3 | Port `elo_monte_carlo()` — runs Elo across N iterations, averages scores |
| 6.4 | Port per-category Elo scoring |
| 6.5 | Write tests comparing final Elo scores for IN against MATLAB CSV outputs |

### Validation Gate
- Elo scores for IN House (single pass, no MC) match MATLAB CSV output
- MC-averaged Elo scores match within statistical tolerance

---

## Phase 7: Visualization

**Goal:** Port all plotting code.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `plot.generatePlots()` | `viz/surfaces.py::generate_plots()` |
| `plot.generateHistograms()` | `viz/histograms.py::generate_histograms()` |
| `plot.plotRunner()` | `viz/surfaces.py::plot_runner()` |
| `plot.makeGif()` | Remove or convert to animated matplotlib (low priority) |
| Prediction boxplots in `runMonteCarlo.m` | `viz/predictions.py::plot_prediction_boxplots()` |

### Steps

| # | Task |
|---|------|
| 7.1 | Port `generate_plots()` — 3D surface and 2D flat heatmap using `matplotlib` `plot_surface` and `imshow`/`pcolormesh` |
| 7.2 | Port `generate_histograms()` — per-legislator agreement score histograms |
| 7.3 | Port `plot_runner()` — orchestrator that generates all plots for a chamber |
| 7.4 | Port prediction boxplots |
| 7.5 | Port issue category frequency histograms |
| 7.6 | Port chamber-committee consistency histogram with fitted distribution |
| 7.7 | Ensure all plots save to the same directory paths as MATLAB |

### Validation Gate
- Plots are generated without errors for IN
- Visual spot-check against MATLAB PNG outputs

---

## Phase 8: Data Merging and Export

**Goal:** Port the CSV export and data merging functions.

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `forge.writeTables()` | `export/csv_writer.py::write_tables()` |
| `finance.mergeData()` | `merge/finance.py::merge_finance_data()` |
| `finance.process()` | `merge/finance.py::process_finance()` |
| `util.mergeShorMcCarty()` | `merge/ideology.py::merge_shor_mccarty()` |
| `util.mergeSeniority()` | `merge/ideology.py::merge_seniority()` |

### Steps

| # | Task |
|---|------|
| 8.1 | Port `write_tables()` — writes all matrix types as CSV with row names |
| 8.2 | Port `process_finance()` — aggregates finance data by legislator name |
| 8.3 | Port `merge_finance_data()` — joins Elo scores with campaign finance data via name matching |
| 8.4 | Port `merge_shor_mccarty()` — joins with ideology scores via name matching |
| 8.5 | Ensure name normalization logic (last, first middle suffix nickname → uppercase, no periods) is identical |
| 8.6 | Write tests comparing merged CSV outputs |

### Validation Gate
- `write_tables()` CSV outputs are identical to MATLAB outputs (diff check)
- Merged data CSVs match MATLAB outputs

---

## Phase 9: Integration, CLI, and Orchestration

**Goal:** Wire everything together into the top-level pipeline and a CLI.

### Steps

| # | Task |
|---|------|
| 9.1 | Create `pipeline.py` that replaces `state.run()` — orchestrates: ingest → classify → build matrices → write tables → plot → predict → Elo → merge |
| 9.2 | Create `cli.py` using `click` — replaces `tester.m`. Arguments: `--state`, `--reprocess`, `--recompute`, `--outputs`, `--predict-mc`, `--predict-elo`, etc. |
| 9.3 | Add caching logic — check for existing `.pkl`/`.parquet` files before recomputing |
| 9.4 | Add logging (replace MATLAB `fprintf` progress messages with Python `logging`) |
| 9.5 | Add progress bars using `tqdm` for long-running loops (MC iterations, bill processing) |
| 9.6 | End-to-end test: `python -m forge --state IN --recompute --outputs` |

### Validation Gate
- Full pipeline runs for IN without errors
- Output directory structure matches MATLAB output structure

---

## Phase 10: Validation and Testing

**Goal:** Comprehensive validation that the Python port produces identical results to MATLAB.

### Steps

| # | Task |
|---|------|
| 10.1 | **Reference data generation** — Run the MATLAB pipeline one final time for IN, OR, WI and save all CSV outputs as "golden" reference files |
| 10.2 | **Automated comparison** — Write a test that diffs every Python CSV output against the MATLAB golden file (tolerance: 1e-10 for floats, exact for strings) |
| 10.3 | **Classification accuracy** — Verify learning algorithm accuracy matches within 1% |
| 10.4 | **Monte Carlo statistical tests** — For MC outputs, verify mean and standard deviation match within expected statistical bounds |
| 10.5 | **Performance benchmarking** — Time the Python pipeline and compare to MATLAB; optimize if Python is >3x slower on the same data |
| 10.6 | **Stata compatibility check** — Run existing `.do` scripts against Python-generated CSVs and verify they work unchanged |
| 10.7 | **Edge cases** — Test with states that have minimal data, missing fields, or special-case logic (IN hardcoded data) |
| 10.8 | **Code quality** — Run `ruff` or `flake8` for linting, `mypy` for type checking |

### Validation Gate
- All golden-file comparison tests pass
- Stata scripts run successfully on Python outputs
- No regressions in classification accuracy

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Random number divergence** — MATLAB `rng` and numpy `default_rng` produce different sequences for the same seed | High | Medium | Accept numerical differences in MC outputs; validate statistically rather than exactly. Or use a seed-mapping approach to align sequences. |
| **CStrAinBP behavior edge cases** — The MEX binary may have subtle behavior (case sensitivity, handling of duplicates, ordering) not documented | Medium | High | Write exhaustive unit tests for the Python replacement. Compare on real data from IN. |
| **Floating-point differences** — MATLAB and Python/numpy may handle edge cases (NaN propagation, division by zero, rounding) differently | Medium | Medium | Use `numpy.testing.assert_allclose` with appropriate tolerances. Document any accepted differences. |
| **Large data performance** — Python may be significantly slower for the 16,000-iteration Monte Carlo loops | Medium | Medium | Profile early (Phase 5). Use numpy vectorization. Consider `numba` JIT for hot loops if needed. |
| **Missing training data** — The `.mat` files containing trained learning algorithm data may not load correctly via `scipy.io.loadmat` for complex nested structures | Medium | Medium | Retrain from scratch using the XML source data rather than trying to load `.mat` files. |
| **Windows path dependencies** — Backslash paths in MATLAB code may indicate data was generated on Windows with Windows-specific encodings | Low | Low | Normalize all paths to forward slashes. Test on both Linux and macOS. |

---

## Migration Checklist

Use this to track progress across all phases:

- [ ] **Phase 0** — Project scaffolding, `pyproject.toml`, empty test suite
- [ ] **Phase 1** — Config, data models, `cstr_ainbp`, utilities
- [ ] **Phase 2** — CSV reader, JSON reader, XML parser
- [ ] **Phase 3** — Text cleanup, learning table, bill classifier, optimizer
- [ ] **Phase 4** — Agreement matrices, rollcall processing, vote normalization
- [ ] **Phase 5** — Bayesian updating, Monte Carlo prediction, impact scoring
- [ ] **Phase 6** — Elo rating (both variants), Elo Monte Carlo
- [ ] **Phase 7** — Surface plots, histograms, boxplots
- [ ] **Phase 8** — CSV export, finance merge, ideology merge
- [ ] **Phase 9** — Pipeline orchestrator, CLI, logging, caching
- [ ] **Phase 10** — Golden-file validation, Stata compatibility, performance
- [ ] **Cleanup** — Move MATLAB files to `matlab_archive/`, update documentation
