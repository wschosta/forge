# MATLAB-to-Python Refactoring Plan
# The Forge Project

**Date:** 2026-02-28
**Scope:** Full conversion of ~4,900 lines of MATLAB across 63 files to Python
**Version:** 2.0

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
16. [Bug Fixes During Migration](#bug-fixes-during-migration)
17. [Risk Register](#risk-register)
18. [Migration Checklist](#migration-checklist)

---

## 1. Guiding Principles

1. **Fidelity first** — Numerical outputs from the Python version must match MATLAB outputs for the same inputs. Validate with Indiana (IN) as the reference state.
2. **Bottom-up build order** — Start with leaf-level utilities, then build upward. Each phase should be independently testable before the next begins.
3. **Preserve output compatibility** — CSV output structure, column names, and file naming conventions must remain identical so existing Stata `.do` scripts work unchanged.
4. **Incremental delivery** — Each phase produces runnable, tested code. No "big bang" rewrite.
5. **Clean up technical debt as we go** — Fix identified bugs, remove commented-out code, eliminate duplicated logic, fix Windows-only paths. But don't add new features.
6. **Type safety** — Use Python type hints throughout. Use dataclasses for structured data.
7. **Test-driven** — Write tests alongside each phase. Indiana is the reference validation state.

---

## 2. Target Python Stack

| Purpose | Library | Replaces |
|---------|---------|----------|
| DataFrames & tables | `pandas` | MATLAB `table`, `readtable`, `writetable` |
| Numerical computation | `numpy` | MATLAB matrix operations, `bsxfun` |
| Scientific computing | `scipy` | MATLAB `histfit`, optimization, `.mat` file reading |
| Visualization | `matplotlib` + `seaborn` | MATLAB `figure`, `surf`, `histogram`, `boxplot` |
| XML parsing | `lxml` or `xml.etree.ElementTree` | `xml2struct` MEX binary |
| JSON parsing | `json` (stdlib) | `util.parse_json` / `util.readJSON` |
| String matching | `pandas` / native Python | `CStrAinBP` MEX binary |
| NLP text processing | `re` (stdlib) | `la.cleanupText` regex operations |
| Serialization | `pickle` / `parquet` | MATLAB `.mat` files |
| Testing | `pytest` | None (no tests exist currently) |
| CLI | `click` | `tester.m` script |
| Configuration | `dataclasses` + Python dicts | Hardcoded MATLAB properties |
| Reproducibility | `numpy.random.default_rng(seed)` | `util.setRandomSeed` / MATLAB `rng` |
| Progress bars | `tqdm` | MATLAB `fprintf` progress counters |
| Linting | `ruff` | N/A |
| Type checking | `mypy` | N/A |

### Python Version

Target **Python 3.10+** (for `match` statements, union types with `|`, and `dataclasses` improvements).

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
│       ├── cli.py              # Command-line entry point (replaces tester.m)
│       ├── config.py           # State properties, constants, all parameters
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
│       │   ├── stopwords.py    # Common words list (replaces la.getCommonWordsList)
│       │   ├── learning.py     # Learning table generation (replaces la.generateLearningTable)
│       │   ├── classifier.py   # Bill classifier (replaces la.classifyBill, la.processAlgorithm)
│       │   └── optimizer.py    # Frontier optimization (replaces la.optimizeFrontierSimple)
│       ├── matrices/
│       │   ├── __init__.py
│       │   ├── agreement.py    # Agreement matrix builder (replaces processChamberVotes, addVotes, cleanVotes, normalizeVotes)
│       │   ├── rollcalls.py    # Rollcall processor (replaces processChamberRollcalls, addRollcallVotes)
│       │   └── proximity.py    # Seat proximity (replaces processSeatProximity)
│       ├── predict/
│       │   ├── __init__.py
│       │   ├── bayes.py        # Bayesian updating (replaces predict.updateBayes, getSpecificImpact)
│       │   ├── monte_carlo.py  # Monte Carlo simulation (replaces runMonteCarlo, predictOutcomes, montecarloPrediction)
│       │   └── impact.py       # Legislator impact scoring (replaces processLegislatorImpacts)
│       ├── elo/
│       │   ├── __init__.py
│       │   ├── rating.py       # Elo prediction (replaces eloPrediction)
│       │   └── monte_carlo.py  # Elo Monte Carlo (replaces eloMonteCarlo)
│       ├── merge/
│       │   ├── __init__.py
│       │   ├── finance.py      # Finance data merge (replaces +finance/mergeData, process)
│       │   ├── ideology.py     # Shor-McCarty merge (replaces util.mergeShorMcCarty)
│       │   └── seniority.py    # Seniority merge (replaces util.mergeSeniority)
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
│   ├── conftest.py             # Shared fixtures (sample data paths)
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
└── matlab/                     # (new) original MATLAB files moved here for reference
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
| `classdef` handle class | Python class (objects are references by default) | No handle semantics needed |
| `containers.Map` | `dict` | Direct replacement |
| `table` | `pandas.DataFrame` | Core data structure swap |
| `struct` | `@dataclass` | Prefer typed dataclasses |
| `cell array` | `list` | |
| `NaN` | `numpy.nan` or `float('nan')` | |
| `readtable()` | `pandas.read_csv()` | |
| `writetable()` | `df.to_csv()` | |
| `array2table()` | `pd.DataFrame(data, index=..., columns=...)` | |
| `regexp()` | `re.search()` / `re.findall()` | |
| `regexprep()` | `re.sub()` | |
| `sprintf()` | f-strings | |
| `containers.Map('KeyType','int32','ValueType','any')` | `dict[int, Any]` | |
| `bsxfun(@minus,x,x')` | `x[:, None] - x[None, :]` (numpy broadcasting) | |
| `histogram()` | `plt.hist()` or `sns.histplot()` | |
| `histfit()` | `sns.histplot(kde=True)` + manual fit | No direct equivalent |
| `surf()` | `ax.plot_surface()` or `sns.heatmap()` | |
| `boxplot()` | `plt.boxplot()` or `sns.boxplot()` | |
| `saveas(gcf,path,'png')` | `plt.savefig(path)` | |
| `save(...,'.mat')` | `pickle.dump()` or `df.to_parquet()` | |
| `load(...,'.mat')` | `pickle.load()` or `pd.read_parquet()` | For reading existing .mat: `scipy.io.loadmat()` |
| `inputParser` | `click` (CLI) or function kwargs with defaults | |
| MATLAB packages (`+pkg`) | Python packages (directories with `__init__.py`) | |
| MATLAB class folders (`@class`) | Regular Python classes in modules | |
| `CStrAinBP(A, B)` | Custom helper using set operations / `np.isin()` | **Critical — ~30 call sites** |
| `xml2struct` | `lxml.etree` or `xml.etree.ElementTree` | |
| `rng(seed)` | `numpy.random.default_rng(seed)` | Sequences will differ |
| `randperm(n)` | `rng.permutation(n)` | |
| `unique(x)` | `np.unique(x)` or `pd.Series.unique()` | Watch sort order |
| `cellfun(@fn, cells)` | List comprehension or `map()` | |
| `arrayfun(@fn, arr)` | `np.vectorize(fn)(arr)` or comprehension | |

### `CStrAinBP` — Critical Migration Item

This MEX binary is used in ~30 locations. Its behavior:
- `[indices_in_A] = CStrAinBP(A, B)` — Returns indices of elements in cell array A that are also in cell array B
- `[indices_in_A, indices_in_B] = CStrAinBP(A, B)` — Also returns corresponding indices in B
- Case-sensitive string comparison
- Used for: filtering legislator IDs, matching row/column names, name matching in merges

Python equivalent needs to handle both return modes:
```python
def cstr_ainbp(a: list[str], b: list[str]) -> tuple[list[int], list[int]]:
    """Find indices of elements in A that appear in B, and their positions in B."""
    b_set = {v: i for i, v in enumerate(b)}
    a_indices = []
    b_indices = []
    for i, val in enumerate(a):
        if val in b_set:
            a_indices.append(i)
            b_indices.append(b_set[val])
    return a_indices, b_indices
```

---

## Phase 0: Scaffolding and Infrastructure

**Goal:** Set up the Python project skeleton, dependency management, and CI.

**Estimated effort:** Small

### Steps

| # | Task | Files Created |
|---|------|---------------|
| 0.1 | Create `pyproject.toml` with dependencies (pandas, numpy, scipy, matplotlib, seaborn, lxml, pytest, click, tqdm, ruff) | `pyproject.toml` |
| 0.2 | Create `src/forge/__init__.py` and all sub-package `__init__.py` files (~15 files) | `src/forge/**/__init__.py` |
| 0.3 | Create `tests/conftest.py` with fixtures pointing to sample LegiScan data (use IN as reference) | `tests/conftest.py` |
| 0.4 | Create/update `.gitignore` for `__pycache__`, `.pytest_cache`, `*.pyc`, `*.egg-info`, virtual envs | `.gitignore` |
| 0.5 | Verify `pip install -e .` works and `pytest` discovers test directory | — |
| 0.6 | Move all original MATLAB files to `matlab/` for reference (preserve git history via `git mv`) | `matlab/` |

### Validation Gate
- `pip install -e .` succeeds
- `pytest` runs (zero tests, empty suite)
- `python -c "import forge"` works

---

## Phase 1: Utilities and Data Templates

**Goal:** Port the foundational utility functions and data model templates that everything else depends on.

**Estimated effort:** Small

### MATLAB → Python Mapping

| MATLAB File | Python File | Key Changes |
|---|---|---|
| `+util/+templates/getBillTemplate.m` | `src/forge/models/bill.py` | Convert struct to `@dataclass` with typed fields |
| `+util/+templates/getVoteTemplate.m` | `src/forge/models/vote.py` | Convert struct to `@dataclass` |
| `+util/+templates/getChamberTemplate.m` | `src/forge/models/chamber.py` | Convert struct to `@dataclass` |
| `+util/createTable.m` | Inline `pd.DataFrame` construction | Remove — trivial with pandas |
| `+util/createIDstrings.m` | `src/forge/config.py` utility function | `f"id{x}"` formatting |
| `+util/greaterThanZero.m` | Remove — trivial | Use `max(x, 0)` inline |
| `+util/setRandomSeed.m` | `numpy.random.default_rng(seed)` | Inline where needed |
| `+util/parse_json.m` / `readJSON.m` | `json.load()` (stdlib) | Direct replacement |
| `CStrAinBP` (MEX binary) | `src/forge/config.py::cstr_ainbp()` | **Critical** — see Section 4 |
| `@state/state_properties.m` | `src/forge/config.py::STATE_PROPERTIES` | Dict mapping state codes to `(senate_size, house_size)` |
| Constants (PARTY_KEY, VOTE_KEY, ISSUE_KEY) | `src/forge/config.py` | Python dicts |

### Steps

| # | Task |
|---|------|
| 1.1 | Create `config.py` with `STATE_PROPERTIES` dict, `PARTY_KEY`, `VOTE_KEY`, `ISSUE_KEY`, `create_id_strings()`, `cstr_ainbp()` |
| 1.2 | Create `models/bill.py` with `Bill` dataclass matching `getBillTemplate` fields (bill_id, bill_number, title, issue_category, sponsors, dates, chamber data, passage flags, competitive flag, complete flag) |
| 1.3 | Create `models/vote.py` with `Vote` dataclass (rollcall_id, description, date, yea, nay, nv, total_vote, yes_percent, yes_list, no_list, abstain_list) |
| 1.4 | Create `models/chamber.py` with `ChamberData` dataclass (committee_votes, chamber_votes, passed, finals, competitive flag) |
| 1.5 | Write tests for `cstr_ainbp()` — test both 1-return and 2-return modes, edge cases (empty arrays, no matches, duplicates), case sensitivity |
| 1.6 | Write tests for all dataclass construction and config lookups |

### Validation Gate
- All `test_config.py` and `test_models.py` tests pass
- `cstr_ainbp()` matches MATLAB `CStrAinBP` behavior on sample inputs

---

## Phase 2: Data Ingestion Layer

**Goal:** Read LegiScan CSV and JSON data into pandas DataFrames, matching the exact structure produced by MATLAB's `readAllFilesOfSubject` and `readAllInfo`.

**Estimated effort:** Medium

### MATLAB → Python Mapping

| MATLAB | Python | Notes |
|---|---|---|
| `forge.readAllFilesOfSubject()` | `ingest/csv_reader.py::read_all_csv()` | Iterates session dirs, reads CSV, appends year column, handles schema differences |
| `forge.readAllInfo()` | `ingest/json_reader.py::read_all_json()` | Reads bill/vote/people JSON, builds dict structures |
| `la.xmlparse()` | `ingest/xml_parser.py::parse_congressional_xml()` | Parses XML bills for learning algorithm training data |

### Steps

| # | Task |
|---|------|
| 2.1 | Implement `csv_reader.py::read_all_csv(data_type, state)` — reads `legiscan_data/{state}/*/csv/{type}.csv`, filters dirs by `\d+-\d+_.*` pattern, concatenates with year column, handles missing columns by filling NaN or empty |
| 2.2 | Implement derived fields for rollcalls: `total_vote = yea + nay`, `yes_percent = yea / total_vote`, `senate = total_vote <= senate_size` |
| 2.3 | Implement `json_reader.py::read_all_json(state)` — reads JSON bill/vote/people files, builds dicts keyed by ID, handles nested JSON structures (committee, history, sponsors, etc.), tracks people across sessions |
| 2.4 | Implement `xml_parser.py::parse_congressional_xml()` — parses `data/congressional_archive/*.xml` using `lxml`, extracts title, policyArea, summary CDATA, subjects. Handle single vs. multiple items. Filter incomplete bills. |
| 2.5 | Add caching: save processed DataFrames to `data/{state}/processed_data.pkl` (or `.parquet`). Check for existing cache if `reprocess=False`. |
| 2.6 | Write tests using real IN data: verify column names, row counts, data types match expectations |

### Validation Gate
- `read_all_csv('bills', 'IN')` produces a DataFrame with identical columns and row count to MATLAB
- `read_all_csv('people', 'IN').shape` matches MATLAB
- XML parser extracts the same number of valid bills as MATLAB's `xmlparse`

---

## Phase 3: Bill Classification / Learning Algorithm

**Goal:** Port the text-based bill classification system from `+la/`.

**Estimated effort:** Medium-Large

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `la.cleanupText()` | `classify/text_cleanup.py::cleanup_text()` |
| `la.getCommonWordsList()` | `classify/stopwords.py::get_common_words()` |
| `la.generateLearningTable()` | `classify/learning.py::generate_learning_table()` |
| `la.classifyBill()` | `classify/classifier.py::classify_bill()` |
| `la.processAlgorithm()` | `classify/classifier.py::process_all_bills()` |
| `la.loadLearnedMaterials()` | `classify/learning.py::load_learned_materials()` |
| `la.optimizeFrontierSimple()` | `classify/optimizer.py::optimize_frontier()` |
| `la.generateAdjacencyMatrix()` | `classify/classifier.py::generate_adjacency_matrix()` |
| `la.generateConciseMaps()` | `classify/learning.py` (inline configuration) |
| `la.main()` | `classify/__init__.py::run_learning_pipeline()` |

### Steps

| # | Task |
|---|------|
| 3.1 | Port `cleanup_text()` — regex-based: remove `\d+\w*`, remove 1-2 char words, remove `<p>` and `<b>` tags, split on `\W+\|\s+`, remove stop words (case-insensitive), uppercase, deduplicate with frequency counts. Must return `(unique_words, weights)`. |
| 3.2 | Port `get_common_words()` — the full 700+ stop word list including common English, US state names/abbreviations, months, Roman numerals, single letters, legislative terms |
| 3.3 | Port `generate_learning_table()` — for each category: aggregate cleaned text from training bills, compute word frequency as `count / bill_count`, truncate to `cut_off` words, construct combined description text with `iwv`-weighted issue text and `awv`-weighted additional text |
| 3.4 | Port `classify_bill()` — clean title, score against each category's word vectors (`sum(learned_weight * title_weight)`), return argmax. **Fix bug:** use cleaned title variable, not undefined `text` |
| 3.5 | Port concise category recoding (32 → 11 categories) with the specific groupings |
| 3.6 | Port `process_all_bills()` — batch classification with accuracy calculation |
| 3.7 | Port `optimize_frontier()` — iterative grid search over iwv/awv with zoom-in |
| 3.8 | Write tests comparing classification accuracy against MATLAB baseline. Use a sample of 100+ bills with known correct categories. |

### Validation Gate
- `classify_bill(title, data_storage)` returns the same category as MATLAB for a sample of 100 bills
- Overall accuracy within 1% of MATLAB baseline on the full training set

---

## Phase 4: Vote Processing and Agreement Matrices

**Goal:** Port the core vote processing logic that builds NxN agreement, sponsorship, and consistency matrices.

**Estimated effort:** Large (most complex phase)

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
| 4.1 | Port `build_bill_set()` — iterate bills, create Bill dataclasses, classify them, attach rollcall/sponsor/history data, determine competitiveness. Build `bill_set: dict[int, Bill]` |
| 4.2 | Port `process_chamber_rollcalls()` — separate rollcalls into chamber vs. committee by `total_vote < chamber_size * committee_threshold`. Return ChamberData with vote lists, final vote percentages |
| 4.3 | Port `add_rollcall_votes()` — extract yes/no/abstain lists from rollcall by matching vote codes against VOTE_KEY |
| 4.4 | Port `process_chamber_votes()` — the large function that: initializes NaN matrices, iterates bills, filters by category and competitiveness, filters votes by "THIRD/3RD/ON PASSAGE", builds agreement and sponsor matrices, tracks bill IDs |
| 4.5 | Port `add_votes()` — adds 1 (agreement) or 0 (disagreement) to matrix cells. Handle NaN→value initialization. Port as DataFrame operations. |
| 4.6 | Port `clean_votes()` — remove legislators with all-NaN rows/columns |
| 4.7 | Port `clean_sponsor_votes()` — additionally filter sponsors below `mean - std/2` threshold |
| 4.8 | Port `normalize_votes()` — element-wise `agreement / possible_votes` |
| 4.9 | Port party splitting — extract Republican-only and Democrat-only sub-matrices using `cstr_ainbp` |
| 4.10 | Port `compute_seat_proximity()` — Euclidean distance via numpy broadcasting: `sqrt((x[:,None]-x[None,:])^2 + (y[:,None]-y[None,:])^2)` |
| 4.11 | Write tests comparing output matrices against MATLAB CSV exports in `data/IN/outputs/` |

### Validation Gate
- For Indiana, `process_chamber_votes(house_people, 'house', 0)` produces a chamber matrix matching `data/IN/outputs/H_cha_A_matrix_0.csv` to within floating-point tolerance (1e-10)
- Party sub-matrices match `H_cha_R_votes_0.csv` and `H_cha_D_votes_0.csv`

---

## Phase 5: Bayesian Prediction and Monte Carlo

**Goal:** Port the Bayesian updating and Monte Carlo prediction system.

**Estimated effort:** Medium

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `predict.getSpecificImpact()` | `predict/bayes.py::get_specific_impact()` |
| `predict.updateBayes()` | `predict/bayes.py::update_bayes()` |
| `forge.predictOutcomes()` | `predict/monte_carlo.py::predict_outcomes()` |
| `forge.runMonteCarlo()` | `predict/monte_carlo.py::run_monte_carlo()` |
| `forge.montecarloPrediction()` | `predict/monte_carlo.py::monte_carlo_prediction()` |
| `forge.processLegislatorImpacts()` | `predict/impact.py::process_legislator_impacts()` |

### Steps

| # | Task |
|---|------|
| 5.1 | Port `get_specific_impact()` — clamp to [0.001, 0.999], flip for no-votes (`1-impact`), return 0.5 for NaN |
| 5.2 | Port `update_bayes()` — vectorized Bayesian posterior: `P_new = (impact * P_old) / (impact * P_old + (1-impact) * (1-P_old))`. Preserve NaNs. Clamp to [0.001, 0.999]. Set revealed legislator to `abs(pref - 0.001)`. Compute accuracy. |
| 5.3 | Port `predict_outcomes()` — per-bill prediction: sponsor effect calculation, MC loop with random seed per iteration, randomized legislator order, iterative Bayes updates, accuracy tracking per step |
| 5.4 | Port `run_monte_carlo()` — iterate over all bills, call predict_outcomes per bill, aggregate results |
| 5.5 | Port `monte_carlo_prediction()` — top-level orchestrator with caching |
| 5.6 | Port `process_legislator_impacts()` — placement-weighted accuracy deltas, aggregation across bills, normalization |
| 5.7 | **Vectorize** — Ensure numpy operations for the inner Bayes loop. The `update_bayes` function operates on full arrays already; keep this pattern. |
| 5.8 | Write unit tests for `update_bayes()` with hand-crafted inputs/outputs, edge cases (NaN handling, clamping) |

### Validation Gate
- `update_bayes()` produces identical outputs to MATLAB for a set of hand-crafted test vectors
- `get_specific_impact()` edge cases all match MATLAB behavior
- Monte Carlo prediction accuracy distribution for IN House matches MATLAB within statistical tolerance

---

## Phase 6: Elo Rating System

**Goal:** Port the Elo scoring system, **deduplicating** the shared Bayesian logic with Phase 5.

**Estimated effort:** Medium

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `forge.eloPrediction()` | `elo/rating.py::elo_prediction()` |
| `forge.eloMonteCarlo()` | `elo/monte_carlo.py::elo_monte_carlo()` |

### Steps

| # | Task |
|---|------|
| 6.1 | **Extract shared logic** — The MATLAB code has ~60 duplicated lines between `predictOutcomes` and `eloPrediction` (sponsor effect + Bayesian prediction). In Python, create a shared function `predict/bayes.py::compute_bill_prediction()` that both systems call. |
| 6.2 | Port `elo_prediction()` — single pass over all bills. For each bill: call shared prediction, then perform pairwise Elo updates. Two variants: variable-K (`K = 8000/clamp(count, 200, 800)`) and fixed-K (`K = 16`). |
| 6.3 | Port Elo update formula: `new = old + K * (W - E)` where `E = 1/(1+10^((opp-own)/400))` and `W = 1 if accuracy_i > accuracy_j, 0.5 if equal, 0 otherwise` |
| 6.4 | Port `elo_monte_carlo()` — runs Elo across N iterations, averages scores. Per-category support: filter bills by category, produce separate outputs. |
| 6.5 | Join Elo results with legislator metadata, sort by score |
| 6.6 | Write tests comparing final Elo scores for IN against existing CSV outputs in `data/IN/elo_model/` |

### Validation Gate
- Elo scores for IN House (single pass, no MC) match MATLAB CSV output
- MC-averaged Elo scores match within statistical tolerance

---

## Phase 7: Visualization

**Goal:** Port all plotting code. Lower priority than data processing — plots are for verification and presentation.

**Estimated effort:** Medium

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `plot.generatePlots()` | `viz/surfaces.py::generate_plots()` |
| `plot.generateHistograms()` | `viz/histograms.py::generate_histograms()` |
| `plot.plotRunner()` | `viz/surfaces.py::plot_runner()` |
| `plot.makeGif()` | Remove (unused) |
| Prediction boxplots in `runMonteCarlo.m` | `viz/predictions.py::plot_prediction_boxplots()` |

### Steps

| # | Task |
|---|------|
| 7.1 | Port `generate_plots()` — 3D surface using `ax.plot_surface()` with jet colormap, colorbar, [0,1] range. Also flat 2D view using `imshow` or `pcolormesh`. Save both as PNG. |
| 7.2 | Port `generate_histograms()` — per-legislator histograms: separate diagonal (matching) from off-diagonal scores, `histfit` equivalent using `sns.histplot(kde=True)` or `scipy.stats.norm.fit()` |
| 7.3 | Port `plot_runner()` — orchestrates 12 matrix plots (6 types × chamber/committee) plus consistency for each chamber and category |
| 7.4 | Port prediction boxplots — per-bill accuracy, per-bill delta, total accuracy, total delta |
| 7.5 | Port issue category frequency histograms (all bills vs. competitive bills) |
| 7.6 | Port chamber-committee consistency histogram with fitted distribution |
| 7.7 | Ensure all plots save to the same directory paths and file names as MATLAB |

### Validation Gate
- Plots are generated without errors for IN
- Visual spot-check against MATLAB PNG outputs (not pixel-exact, but structurally equivalent)

---

## Phase 8: Data Merging and Export

**Goal:** Port the CSV export and data merging functions.

**Estimated effort:** Medium

### MATLAB → Python Mapping

| MATLAB | Python |
|---|---|
| `forge.writeTables()` | `export/csv_writer.py::write_tables()` |
| `finance.process()` | `merge/finance.py::process_finance()` |
| `finance.mergeData()` | `merge/finance.py::merge_finance_data()` |
| `util.mergeShorMcCarty()` | `merge/ideology.py::merge_shor_mccarty()` |
| `util.mergeSeniority()` | `merge/seniority.py::merge_seniority()` |

### Steps

| # | Task |
|---|------|
| 8.1 | Port `write_tables()` — write all matrix types as CSV with row names (index). Delete existing files for chamber/category before writing. Match exact file naming convention: `{C}_{type}_{party}_{modifier}_{category}.csv` |
| 8.2 | Port `process_finance()` — aggregate finance data by unique legislator name (sum financial columns) |
| 8.3 | Port `merge_finance_data()` — construct normalized full names (`"LAST SUFFIX, FIRST MIDDLE (NICKNAME)"`, uppercased, periods removed), join with Elo scores via `cstr_ainbp` name matching. Handle IN special case. |
| 8.4 | Port `merge_shor_mccarty()` — same name normalization, join with ideology scores |
| 8.5 | Port `merge_seniority()` — for each legislator take most recent election year's cumulative terms, join using name matching |
| 8.6 | Ensure name normalization logic is identical across all three merge functions (refactor into shared utility) |
| 8.7 | Write tests comparing merged CSV outputs against existing files in `data/IN/merged_data/` |

### Validation Gate
- `write_tables()` CSV outputs are byte-identical to MATLAB outputs (ignoring float precision)
- Merged data CSVs match MATLAB outputs

---

## Phase 9: Integration, CLI, and Orchestration

**Goal:** Wire everything together into the top-level pipeline and a CLI.

**Estimated effort:** Medium

### Steps

| # | Task |
|---|------|
| 9.1 | Create `pipeline.py` — replaces `state.run()`. Orchestrates: ingest → classify → build bill_set → build matrices (per category) → write tables → plot → predict → Elo → merge. Parameterized by state and all flags. |
| 9.2 | Create `cli.py` using `click` — replaces `tester.m`. Arguments: `--state`, `--reprocess`, `--recompute`, `--outputs`, `--predict-mc`, `--recompute-mc`, `--predict-elo`, `--recompute-elo`, `--show-warnings`, `--all-categories` |
| 9.3 | Add caching logic — check for existing `.pkl`/`.parquet` files before recomputing. Match MATLAB's two-tier cache: `processed_data` (ingestion) and `saved_data` (matrices). |
| 9.4 | Add logging — replace MATLAB `fprintf` progress messages with Python `logging` module |
| 9.5 | Add progress bars using `tqdm` for long-running loops (MC iterations, bill processing) |
| 9.6 | Register CLI as entry point in `pyproject.toml`: `forge = "forge.cli:main"` |
| 9.7 | End-to-end test: `python -m forge --state IN --recompute --outputs` |

### Validation Gate
- Full pipeline runs for IN without errors
- Output directory structure matches MATLAB output structure exactly
- All CSVs match MATLAB outputs

---

## Phase 10: Validation and Testing

**Goal:** Comprehensive validation that the Python port produces identical results to MATLAB.

**Estimated effort:** Medium

### Steps

| # | Task |
|---|------|
| 10.1 | **Reference data preservation** — Ensure all existing MATLAB CSV outputs for IN are preserved as "golden" reference files in a `tests/fixtures/golden/` directory |
| 10.2 | **Automated comparison** — Write `test_indiana_pipeline.py` that diffs every Python CSV output against the MATLAB golden file. Tolerance: 1e-10 for floats, exact for strings. |
| 10.3 | **Classification accuracy** — Verify learning algorithm accuracy matches MATLAB within 1% |
| 10.4 | **Monte Carlo statistical tests** — For MC outputs, verify mean and standard deviation match within expected statistical bounds (different RNG sequences will produce different individual runs but same distributions) |
| 10.5 | **Stata compatibility check** — Run existing `.do` scripts against Python-generated CSVs and verify they work unchanged |
| 10.6 | **Edge cases** — Test with states that have minimal data, missing fields, or special-case logic (IN hardcoded data) |
| 10.7 | **Performance benchmarking** — Time the Python pipeline and compare to MATLAB; optimize if Python is >3x slower. Consider `numba` JIT for hot loops if needed. |
| 10.8 | **Code quality** — Run `ruff` for linting, `mypy` for type checking. Aim for zero ruff errors and minimal mypy issues. |
| 10.9 | **Multi-state validation** — Run pipeline for OR and WI (if MATLAB outputs exist) to verify generalization |

### Validation Gate
- All golden-file comparison tests pass
- Stata scripts run successfully on Python outputs
- No regressions in classification accuracy
- `ruff` and `mypy` pass cleanly

---

## Bug Fixes During Migration

These bugs were identified during code analysis and should be fixed during their respective phases:

| Bug | Phase | Fix |
|-----|-------|-----|
| `classifyBill.m` line 13 references undeclared `text` instead of `clean_title` | Phase 3 | Use correct variable name |
| `outputBillInformation.m` line 14 references `senate_bill_ids` instead of `chamber_bill_ids` | Phase 4 | Use correct parameter name |
| Accuracy formula uses hardcoded `100` instead of actual legislator count | Phase 5 | Use `len(legislators)` |
| `keyboard` debug statement in `state.m` line 263 | Phase 9 | Remove |
| Windows backslash paths throughout `+la/` | Phase 0 | Use `pathlib.Path` / forward slashes |
| Committee processing entirely commented out | Phase 4 | Leave disabled but structure code so it can be re-enabled later |
| Duplicated code between `predictOutcomes` and `eloPrediction` | Phase 6 | Extract shared function |
| Consistency matrix never populated | Phase 4 | Leave as-is (not a regression), document |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Random number divergence** — MATLAB `rng('mt19937ar', seed)` and numpy `default_rng(seed)` produce different sequences | High | Medium | Accept numerical differences in MC outputs. Validate statistically (same mean/std) rather than exactly. Document this as a known difference. |
| **CStrAinBP edge cases** — The MEX binary may have undocumented behavior with duplicates, empty inputs, or ordering | Medium | High | Write exhaustive unit tests. Compare on real data from IN. Test: empty arrays, no matches, all matches, duplicates in A, duplicates in B. |
| **Floating-point differences** — MATLAB and numpy handle NaN propagation, division by zero, and rounding differently | Medium | Medium | Use `numpy.testing.assert_allclose` with tolerance. Document accepted differences. |
| **Large data performance** — Python may be significantly slower for 16K-iteration MC loops with 100+ legislators | Medium | Medium | Profile early (Phase 5). Use numpy vectorization. Consider `numba` JIT for inner loop if needed. The `update_bayes` inner loop is already partially vectorized. |
| **Missing training data** — `.mat` files may not load correctly via `scipy.io.loadmat` for complex nested structures | Medium | Medium | Retrain from scratch using XML source data rather than trying to load `.mat` files. The XML data is available in `data/congressional_archive/`. |
| **Pandas vs. MATLAB table semantics** — Row/column name handling, NaN behavior, and indexing differ | Medium | Low | Write comparison tests early. Be explicit about index handling in pandas. |
| **Memory for large states** — CA (88+40 legislators), NY (150+63) will have larger matrices | Low | Low | Numpy arrays are memory-efficient. Profile on CA if performance is a concern. |

---

## Migration Checklist

Use this to track progress across all phases:

- [ ] **Phase 0** — Project scaffolding, `pyproject.toml`, empty test suite, MATLAB files moved
- [ ] **Phase 1** — Config, data models, `cstr_ainbp`, utilities, all tests passing
- [ ] **Phase 2** — CSV reader, JSON reader, XML parser, caching, all tests passing
- [ ] **Phase 3** — Text cleanup, learning table, bill classifier, optimizer, accuracy validated
- [ ] **Phase 4** — Agreement matrices, rollcall processing, vote normalization, party splitting, CSV output validated against IN golden files
- [ ] **Phase 5** — Bayesian updating, Monte Carlo prediction, impact scoring, statistical validation
- [ ] **Phase 6** — Elo rating (both variants), Elo Monte Carlo, shared logic extracted, validated against IN
- [ ] **Phase 7** — Surface plots, histograms, boxplots, visual spot-check
- [ ] **Phase 8** — CSV export, finance merge, ideology merge, seniority merge, output validated
- [ ] **Phase 9** — Pipeline orchestrator, CLI, logging, progress bars, caching, end-to-end test
- [ ] **Phase 10** — Golden-file validation, Stata compatibility, performance benchmarking, code quality
- [ ] **Cleanup** — All bugs fixed, documentation updated, MATLAB files in `matlab/`

---

## Dependency Graph

Phases must be completed in approximately this order due to dependencies:

```
Phase 0 (Scaffolding)
    │
    ▼
Phase 1 (Utilities & Models)
    │
    ├──────────────┐
    ▼              ▼
Phase 2          Phase 3
(Ingestion)      (Classification)
    │              │
    └──────┬───────┘
           ▼
       Phase 4
    (Matrices) ◄── most complex, depends on both ingestion and classification
           │
     ┌─────┴─────┐
     ▼           ▼
  Phase 5     Phase 7
  (Predict)   (Viz) ◄── can start after Phase 4
     │
     ▼
  Phase 6
  (Elo) ◄── depends on shared Bayesian logic from Phase 5
     │
     ▼
  Phase 8
  (Merge & Export) ◄── depends on Elo output
     │
     ▼
  Phase 9
  (Integration)
     │
     ▼
  Phase 10
  (Validation)
```

Note: Phases 2 and 3 can be developed in parallel. Phase 7 (Visualization) can begin after Phase 4 and proceed in parallel with Phases 5-6.
