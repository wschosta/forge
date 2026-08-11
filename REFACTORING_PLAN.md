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
| Accuracy formula uses hardcoded `100` instead of actual legislator count | Phase 5 | Use `len(legislators)` — **see below, this changes every Senate figure** |
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
- [~] **Phase 10** — Golden-file validation **in place for Indiana** (`tests/test_integration/`); Stata compatibility, performance benchmarking, and full multi-state validation still outstanding
- [ ] **Cleanup** — All bugs fixed, documentation updated, MATLAB files in `matlab/`

### Phase 10 status: what the golden comparison currently shows

Running the pipeline against real Indiana data and diffing every category-0
matrix against the committed MATLAB outputs gives:

| Output | Labels | max abs diff | mean abs diff |
|--------|--------|--------------|---------------|
| `H_seat_matrix_0` | identical | 5e-14 | 3e-15 |
| `H_cha_A_matrix_0` (agreement) | identical | 4.4e-2 | 4.4e-3 |
| `S_cha_A_matrix_0` (agreement) | identical | 1.3e-2 | 3.4e-3 |
| `H_cha_A_votes_0` (co-vote counts) | identical | 7 votes | 3.1 votes |
| `S_cha_A_votes_0` (co-vote counts) | identical | 3 votes | 2.1 votes |
| sponsor matrices | 2 columns differ | 3.3e-1 | 5.6e-3 |

Read this as: **structure matches, arithmetic is close, bill selection is not
identical.** Seat proximity — the one output that does not depend on which
bills are included — agrees to floating point, which is good evidence the
numerical core is correct.

#### Why the residual cannot currently be closed

The residual was tracked down rather than left open, and the conclusion is that
it is a **data-provenance gap, not a code defect**. The evidence:

1. **The difference is strictly additive.** Comparing golden to Python co-vote
   counts cell by cell: golden is higher in 56% of cells, equal in 44%, and
   lower in **0%**. Python never counts a co-vote MATLAB did not; it only
   misses some. So the logic does not fabricate agreement — it is
   under-inclusive.

2. **The shortfall is bimodal by legislator.** Exactly 25 of 100 House members
   match perfectly; the other 75 are short by ~4.3 votes each. The 25 average
   181 recorded votes against 280 for the rest — they are short-serving
   members. The bills Python is missing therefore sit in a period those 25
   were not present for.

3. **The missing bills are ones MATLAB classified and Python cannot.** Five
   House bills (*Novelty lighters*, *Mopeds*, *Expungement* ×2, *Motorsports*)
   score zero against every category, so both implementations' final guard
   returns NaN and the category filter drops them. Forcing them in collapses
   the worst per-legislator gap from 4.97 to 0.92.

4. **Their vocabulary is missing from the committed classifier.** The pruned
   `description_text` in `+la/learning_algorithm_data.mat` holds 8,752 distinct
   words and contains none of EXPUNGEMENT, MOTORSPORTS, or NOVELTY. The
   unpruned `unique_text_full_store` in the same file holds 24,238 words and
   contains all three.

The committed classifier is therefore **a different vintage from the one that
generated the committed outputs** — it was pruned harder. `data/IN/saved_data.mat`
is stale in the same way: it lists 310 House bills, and forcing Python to use
exactly that set makes agreement *worse* (mean gap 3.06 → 4.68), so it does not
correspond to the golden CSVs either.

Closing the gap from here means recovering or retraining the classifier that
produced the goldens, then regenerating them — not adjusting filters. Tuning
selection logic until the numbers line up would overfit to an artifact whose
provenance is unknown, and would silently trade correctness for a green test.
The 1e-10 target in Phase 10.2 should be restored only once inputs and outputs
are known to come from the same run.

One genuine fidelity bug *was* found while investigating and is fixed: the
competitive test only bracketed the vote on one side (`pct < threshold`) where
MATLAB brackets both (`(1 - threshold) < pct < threshold`, forge.m:156-157), so
near-unanimous *failures* were treated as competitive. No Indiana bill falls in
that band, so it does not move these numbers, but it would affect other states.

---

## Phase 5 status: Monte Carlo prediction

The prediction half was run against real Indiana data for the first time and
compared to the committed `H_prediction_model_results_m2500.csv` at matching
iteration count (2,500), over the 87 legislators the two runs share:

| Column | Golden | Python | Pearson | Spearman |
|--------|--------|--------|---------|----------|
| `coverage` | mean 0.844, sd 0.174 | mean 0.841, sd 0.177 | **0.9995** | 0.9974 |
| `results` | mean 0.752, sd 0.155 | mean 0.673, sd 0.189 | **0.8057** | **0.8159** |

`coverage` agreeing to 0.9995 is strong evidence the Monte Carlo machinery is
sound: bill selection, legislator ordering and iteration counting all line up.

Measured again at the same 2,500 iterations before and after the two fixes
below, impact scores moved from Pearson 0.7417 / Spearman 0.7621 to
0.8057 / 0.8159, and their mean from 8.194 to 0.673 against the golden's 0.752.

Worth noting which fix did what. The rollcall date sort made Indiana's
*matrices* slightly worse — that is documented above and accepted — while making
its *predictions* measurably better. There is no contradiction: the sort changes
which rollcall counts as a bill's final vote, and prediction reads that vote
directly where the matrices only use it to decide inclusion. It is a further
reason to trust the sort over Indiana's matrix goldens.

**Resolved: impact scores were sign-inverted by a percentage/fraction mixup.**
Accuracies travel through the Monte Carlo as percentages, so the denominator
`1 - accuracy` (processLegislatorImpacts.m:66) was evaluating to about -46
instead of the ~0.53 of remaining headroom it means. A positive numerator over
a negative denominator made every impact score negative; normalizing negatives
by their maximum then produced an unbounded column rather than the golden's
[0, 1]. Reading the accuracy as a fraction fixes both.

| | min | max | mean |
|---|---|---|---|
| Golden | 0.0287 | 1.0000 | 0.683 |
| Before | 1.0000 | 18.2419 | 8.194 |
| After | 0.1428 | 1.0000 | 0.694 |

Two further divergences from MATLAB were corrected at the same time, both
affecting magnitude rather than sign:

1. Placement weight is summed over *all* Monte Carlo iterations before being
   applied (processLegislatorImpacts.m:65), so a legislator repeatedly drawn
   into an influential position is weighted by how often that happened. The
   port applied a per-iteration placement instead.
2. MATLAB uses iteration 1's starting accuracy as the denominator for every
   iteration (`specific_accuracy_list(1,1)`, not `(j,1)`). This looks like an
   indexing slip, but the committed results depend on it, so it is reproduced.

Rank correlation against the golden is essentially unchanged (Spearman 0.74 vs
0.76) — the ranking was always roughly right. What changed is that magnitudes
are now on the same scale as MATLAB's and therefore comparable across runs,
chambers and states.

The residual correlation of ~0.75 is consistent with the provenance
differences documented under Phase 10: the two runs use different bill sets,
different rosters (100 vs 104) and different classifier vintages.

An earlier attempt to fix this at the normalization step, by switching to
MATLAB's signed maximum, corrected the output sign while leaving the inversion
in place and is what produced the unbounded scale. The lesson generalizes:
a normalization that has to be adjusted to make signs come out is usually
compensating for something upstream.

Two further notes from the same run:

- `montecarloPrediction.m:20` writes the results CSV; the port computed the
  table and ignored its `outputs_directory`, leaving the directory empty on a
  successful run. Fixed.
- The prediction golden carries 104 legislators — LegiScan's roster — where the
  matrix goldens carry the curated 100. The committed outputs were not all
  generated from one configuration, which is more evidence for the provenance
  problem described under Phase 10.

### Performance

`update_bayes` dominated at 92% of Monte Carlo runtime. Removing a linear ID
scan, an N-1 element list rebuilt per call, and numpy dispatch overhead on
~100-element arrays took it from 7.04 ms to 3.12 ms per iteration, verified
bit-identical on a 25-bill signature over real data. A production 16,000
iteration House run extrapolates to ~4.1 hours, down from ~9.3 — a long batch
job, but a feasible one.

---

## Phase 6 status: Elo rating

Elo had also never been run against real data. It works: output is
structurally correct, `score_fixed_k` stays pinned at exactly 1500 (the
rating system is zero-sum, so this is a real invariant rather than a
coincidence), and pairwise comparison counts scale linearly with iteration
count in line with the golden.

`tests/test_integration/test_indiana_elo.py` covers structure, the rating
invariants, and the comparison budget. It deliberately does **not** assert
score values against the golden: MATLAB's were produced at 15,000 iterations,
where the spread has narrowed to 1232-1516; a tractable test run sits at
1060-1880 simply because it has not converged. Any tolerance loose enough to
pass would prove nothing.

**Performance is the open problem here, and it is worse than prediction.**
The pairwise update is O(n^2) per bill per iteration — about 4,950 comparisons
for a 100-seat chamber — and each comparison reads scores that earlier
comparisons in the same sweep already wrote, so the loop is inherently
sequential and cannot be vectorized without changing the numbers. Hoisting
config lookups out of the inner loop (they were being resolved tens of millions
of times) and switching to plain Python floats gave 2.36x, verified
bit-identical. That takes a full 15,000-iteration run over all 12 categories
from roughly 58 hours to roughly 25.

25 hours is still not a routine run. Closing that gap needs either a compiled
inner loop (numba/Cython) or an algorithmic change, and neither is a
refactoring decision — it is a question about how often this analysis actually
needs to be rerun.

---

## Phase 3/4 status: per-category matrices

The golden harness originally compared only category 0 — the matrix pooled
across every classified bill — which is structurally blind to
misclassification: a bill filed under the wrong policy area lands in the same
pooled aggregate, so the matrix does not move. The per-category matrices are
99 of the 128 committed golden CSVs, and comparing them localizes the residual
sharply.

Maximum absolute difference by policy area (House, agreement matrix):

| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|----|----|
| 0 | .098 | .250 | .050 | .143 | 0 | 0 | .029 | 0 | 0 | 0 |

Six of eleven categories agree with MATLAB to ~5e-16 — accumulated rounding and
nothing else. The disagreement is confined to categories 2, 3, 4, 5 and 8.

Stated positively: **wherever the two classifier vintages agree on which bills
belong to a policy area, the resulting matrices are the same numbers.** The
agreement-matrix arithmetic is correct; what remains is which bills get sorted
where, which is consistent with the missing classifier vintage rather than with
any computational defect.

## Phase 7 status: visualization

`plot.plotRunner` is called from inside `state.run()` (state.m:218, 249, 315),
so plotting is part of a normal MATLAB run rather than an optional extra. The
port had never executed it against real data.

It works. All 20 pooled-category figures MATLAB produced are produced here, all
48 files (figures plus histograms) are valid PNGs, none empty, each surface plot
paired with its flattened companion. The port additionally emits four Senate
party-sponsor figures the golden lacks, which is harmless.

Figures are not compared pixel-for-pixel — different plotting engines, and the
underlying matrices differ slightly regardless. The tests check the failure
modes that actually occur: a figure family dropping out of the run, and
matplotlib writing a file it never drew into.

## Multi-state validation: Oregon and Wisconsin reproduce exactly

Indiana is the awkward reference state — its House roster is special-cased to a
curated spreadsheet, and the classifier vintage behind its outputs is gone, both
of which put a floor under how closely it can be reproduced. Oregon and
Wisconsin have neither problem and take the ordinary LegiScan roster path, which
the Indiana tests never exercise.

| State / chamber | Agreement matrix | Co-vote counts |
|-----------------|------------------|----------------|
| WI House (100x100) | **exact** | **exact** |
| WI Senate (34x34) | **exact** | **exact** |
| OR House (59x59) | **exact** | **exact** |
| OR Senate (29x29) | **exact** | **exact** |

Exact agreement on the raw co-vote tallies is the part that matters. Those are
counts of events, with no averaging or normalization anywhere in them, so
matching cell-for-cell across a 100x100 matrix is not something two
implementations do by coincidence.

**This is the strongest evidence in the project that the agreement-matrix
arithmetic is correct.** Where Indiana's classifier and roster provenance are
not in play, the port reproduces MATLAB exactly.

### The rollcall ordering bug

Oregon's Senate was the last chamber to disagree — by two co-votes, tracked down
to a single bill out of 266. The cause was a dropped sort.

`forge.m:147` reads a bill's rollcalls with
`sortrows(..., 'date')`. The port did not sort. That matters because a bill's
outcome is taken from its **last** chamber vote, and LegiScan orders rollcalls
by `roll_call_id`, which stops being chronological as soon as a bill has votes
recorded across more than one session file. Oregon bill 676975 has rollcalls
dated Feb 7, Jun 21, Jun 26, Apr 1, Apr 9, May 13, May 28 — in that order.

Reading the wrong rollcall as final changes the recorded yes-percentage, which
changes whether the bill counts as competitive, which decides whether it enters
the matrices at all. Sorting closed Oregon's Senate completely: 266 bills, zero
missing, zero extra, every cell identical.

**It also made Indiana worse** — its worst per-category difference went from
0.250 to 0.333, and category 1 stopped matching exactly. The fix was kept
anyway, on three grounds: it is literally what the MATLAB source does, it makes
two entire states exact across both chambers and both output types, and "the
final vote" can only sensibly mean the chronologically final one.

Indiana moving the wrong way under a provably correct fix is not an argument
against the fix. It is more evidence for what the rest of this document already
says: **Indiana's committed outputs came from a code vintage that did not sort**,
alongside a classifier that no longer exists, a roster that differs from its own
prediction outputs, and filenames from a different era again.

Note these goldens predate the per-category filenames — `H_cha_A_matrix.csv`
here against Indiana's `H_cha_A_matrix_0.csv` — which is more evidence the
committed outputs span several code vintages.

## Retraining the classifier: feasibility

With the vintage that produced the committed outputs confirmed unavailable,
retraining is the only route to a reproducible baseline. It was measured rather
than assumed, and it is cheap:

| Step | Cost |
|------|------|
| Parse 30,495 bills from the committed corpus archives | 40 s |
| Preprocess (clean and tokenize titles and summaries) | 16 s |
| Build the learning table | <1 s |

About a minute end to end, against 12 hours or more for a full analysis run.
Retraining is not the expensive part of anything.

The retrained model recovers vocabulary the committed one lacks: 9,197 distinct
words against 8,752, sharing 88.1% of the committed vocabulary. Of the five
words whose absence causes bills to go unclassified (see Phase 10), the
retrained model contains **MOTORSPORTS**; MOPEDS, EXPUNGEMENT, NOVELTY and
LIGHTERS remain absent even after retraining, so the vocabulary gap is only
partly a pruning artifact.

**One blocker, and it must be fixed before retraining is usable.** The corpus
contains **35** distinct policy areas, but the concise recode table maps only
**32**. Three areas have no concise category and are silently dropped:

| Code | Policy area |
|------|-------------|
| 33 | Transportation and Public Works |
| 34 | Unemployment |
| 35 | Water Resources Development |

This is not a porting error — MATLAB's own table covers the same 32
(`main.m:55`), and the port transcribed it faithfully. It is data drift: the
table was written against a smaller corpus, and the committed archives have
since grown. Rerunning MATLAB today would drop the same three.

The saving grace is that all three sort at the end of the alphabet, so they take
codes 33-35 and leave the existing 1-32 assignments untouched. Extending
`CONCISE_RECODE` to place them is therefore a purely additive change — but it is
a substantive one, since transportation is not a marginal policy area, and it
decides which concise category those bills join. That is a research judgement,
not a refactoring decision.

## Known gap: the training path is not wired

`forge classify` is a stub. It prints "Bill classification not yet fully wired
(data files needed)" and returns without doing anything, and its default
`--xml-dir` points at `legiscan_data/congressional_xml` while the corpus is at
`data/congressional_archive`.

The underlying pieces all exist — `parse_congressional_xml`,
`generate_learning_table`, `build_concise_code_map`, `ADDITIONAL_ISSUE_WORDS` —
and MATLAB derives its category codes from the sorted unique policy areas at
training time (main.m:38, 80) rather than from a hardcoded table, so nothing is
missing. They are simply not connected. This matters more than it did before:
with the classifier vintage that produced the goldens unavailable, retraining is
the only route to a reproducible baseline.

### The accuracy denominator: an intended fix with a large, undocumented effect

`predictOutcomes.m:149` computes accuracy as
`100*(1-(incorrect-are_nan)/(100-are_nan))`. That literal `100` stands in for
the number of legislators and is only correct for a 100-seat chamber. The port
divides by the actual roster size instead, which is listed above as an intended
fix — but the consequence was not recorded anywhere, and it is not small.

With five mispredictions and no abstentions:

| Chamber | MATLAB | Port | Difference |
|---------|--------|------|------------|
| House (100 seats) | 95.00% | 95.00% | 0.00 pts |
| Indiana Senate (51) | 95.00% | 90.20% | 4.80 pts |
| Wisconsin Senate (34) | 95.00% | 85.29% | 9.71 pts |
| Oregon Senate (29) | 95.00% | 82.76% | **12.24 pts** |

So **every Senate prediction and Elo accuracy figure is expected to disagree
with the committed MATLAB outputs**, independently of every other difference in
this document, and by up to twelve percentage points. The House agrees exactly
because that is the case MATLAB's constant happens to fit.

This is worth a research decision rather than being left implicit. The port's
version is the defensible one — scoring a 29-seat chamber out of 100 understates
error by design — but it means Senate accuracies are not comparable to any
previously published figure. Pinned by tests in `test_bayes.py` so it cannot be
rediscovered as a bug.

### Elo against Oregon and Wisconsin

Their single-pass Elo goldens (`{H,S}_elo_score_0.csv`, from
eloPrediction.m:222) were checked too, now that their matrices reproduce
exactly.

Scores cannot be compared. MATLAB shuffles the legislator order with `randperm`
(eloPrediction.m:114) and numpy's generator produces a different sequence from
any seed, and in a *single* pass that ordering dominates the result — Monte
Carlo averaging is what makes Elo scores stable. Rank correlations against the
goldens are accordingly near zero in both directions, which says nothing about
correctness.

The `count` column is the exception: it tallies pairwise comparisons and does
not depend on ordering, so it is deterministic given the same bills. Oregon's
House matches it **exactly**. Oregon's Senate and both Wisconsin chambers do
not, despite every one of their matrices matching cell for cell.

That gap has not been chased. The likely explanation is that Elo processes a
subset of the matrix bills — `predict_bill` drops any bill whose passage vote
covers less than half the chamber — so the Elo goldens depend on more than the
bill selection the matrices already agree on. It is also consistent with these
goldens being yet another vintage.

### Roster provenance, again

The Elo golden carries LegiScan's 104-member roster, like the prediction
golden, while the agreement-matrix goldens carry the curated 100 that state.m
substitutes for Indiana. The two rosters share 87 members; neither contains the
other. That is now three committed output families generated from at least two
different configurations, which is worth keeping in view when interpreting any
comparison against them.

Three defects had to be fixed before any comparison was possible at all:

| Defect | Effect | Fix |
|--------|--------|-----|
| `total_vote` / `yes_percent` never derived | Pipeline raised `KeyError` on the first real rollcall file | Derive at ingest, mirroring forge.m:98-99 |
| Bills never classified | Every category filter excluded every bill; pipeline completed and wrote **empty 0×0 matrices** without erroring | Load the MATLAB-trained classifier and classify in `_init_bills`, mirroring forge.m:133-136 |
| Indiana House roster not special-cased | LegiScan's 2016 roster yields 104 members for a 100-seat chamber | Read `data/IN/undergrad/people_2013-2014.xlsx`, mirroring state.m:153-158 |

The second is the one to keep in mind when planning future phases: the unit
suite was fully green throughout, because every unit test builds its own
synthetic inputs. Only a test that runs real data through the whole pipeline
and compares against a known-good result can catch a stage that silently
produces nothing.

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
