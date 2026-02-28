# Program Requirements Document (PRD)
# The Forge Project — Legislative Analysis and Prediction System

**Authors:** Walter Schostak and Eric Waltenburg
**Current Implementation:** MATLAB
**Target Implementation:** Python
**Date:** 2026-02-28

---

## 1. Executive Summary

Forge is a computational political science platform that ingests U.S. state and federal legislative data (primarily from LegiScan), processes legislator voting records, builds agreement/sponsorship matrices, classifies bills by policy area using a text-based learning algorithm, and predicts legislative outcomes using Bayesian inference, Monte Carlo simulation, and an Elo rating system. The system produces statistical outputs, visualizations, and CSV exports for academic research.

---

## 2. System Purpose and Goals

1. **Data Ingestion** — Read legislative data (bills, votes, rollcalls, sponsors, people, history) from LegiScan CSV and JSON datasets for any supported U.S. state or the U.S. Congress.
2. **Bill Classification** — Classify bills into policy categories (up to 16 "concise" issue codes or 32 granular codes) using a text-based learning algorithm trained on Congressional XML bill data.
3. **Agreement Matrix Generation** — Compute legislator-to-legislator voting agreement matrices (chamber votes, committee votes, sponsorship matrices) for both full chamber and party-specific subsets.
4. **Outcome Prediction** — Predict bill passage using Bayesian updating of revealed legislator preferences, run as Monte Carlo simulations across randomized legislator orderings.
5. **Elo Rating** — Score legislators using an adapted Elo rating system (both fixed-K and variable-K variants), applied per-bill across Monte Carlo iterations.
6. **Data Merging** — Merge legislator scoring data with campaign finance data and Shor-McCarty ideology scores.
7. **Visualization** — Generate 3D surface plots, heatmaps, histograms, boxplots, and optionally GIFs of the agreement/sponsorship matrices.
8. **Export** — Output all matrices, scores, and predictions as CSV files for downstream analysis (e.g., in Stata).

---

## 3. Architecture Overview

### 3.1 Class Hierarchy

```
forge (superclass, handle)
  └── state (subclass)
```

- **`forge`** — The core engine. Contains all data properties, data-reading methods, vote-processing logic, prediction algorithms, and plotting drivers. Defined as a MATLAB `handle` class in `@forge/`.
- **`state`** — Extends `forge`. Configures state-specific properties (chamber sizes via `state_properties.m`), sets up directory structure, loads the learning algorithm, and orchestrates the full pipeline via `run()`.

### 3.2 MATLAB Package Structure (Namespaces)

| Package | Purpose |
|---------|---------|
| `+la` | **Learning Algorithm** — Bill text parsing (XML), text cleanup, learning table generation, bill classification, frontier optimization |
| `+predict` | **Prediction** — Bayesian update functions, impact calculation |
| `+plot` | **Visualization** — Surface plots, histograms, GIF generation |
| `+util` | **Utilities** — Table creation, ID string generation, JSON parsing, data merging helpers |
| `+util/+templates` | **Data Templates** — Struct templates for bills, votes, and chambers |
| `+finance` | **Finance** — Campaign finance data processing and merging |
| `+error_correction` | **Error Analysis** — Elo scoring error investigation scripts |

### 3.3 Data Flow

```
LegiScan CSV/JSON Data
        │
        ▼
  forge.init() ─── Reads bills, people, rollcalls, sponsors, votes, history
        │           Classifies bills using learning algorithm (la.classifyBill)
        │           Builds bill_set containers.Map
        │           Saves processed_data.mat
        ▼
  state.run() ─── Filters people by year/chamber
        │          Calls processChamberVotes() for House and Senate
        │          Generates agreement matrices (chamber, committee, sponsor)
        │          Partitions by party (Republican/Democrat)
        │          Computes seat proximity (if seat data available)
        │          Writes CSV outputs via writeTables()
        │          Generates visualizations via plot.plotRunner()
        ▼
  Prediction ─── montecarloPrediction() → runMonteCarlo() → predictOutcomes()
        │          Uses Bayesian updating (predict.updateBayes)
        │          Processes legislator impacts (processLegislatorImpacts)
        ▼
  Elo Scoring ── eloMonteCarlo() → eloPrediction()
        │          Variable-K and Fixed-K Elo variants
        │          Monte Carlo averaging across iterations
        ▼
  Data Merge ─── finance.mergeData() → util.mergeShorMcCarty()
        │          Joins Elo scores with campaign finance and ideology data
        ▼
  CSV/MAT Outputs + PNG Visualizations
```

---

## 4. Functional Requirements

### 4.1 Data Ingestion (FR-100)

| ID | Requirement |
|----|-------------|
| FR-101 | Read LegiScan CSV files (bills, people, rollcalls, sponsors, votes, history) from `legiscan_data/{STATE}/{session}/csv/` directories |
| FR-102 | Read LegiScan JSON files from `legiscan_data/{STATE}/{session}/bill/`, `/vote/`, `/people/` directories |
| FR-103 | Merge multi-session data into unified tables with year annotations |
| FR-104 | Handle schema differences between sessions (missing columns filled with NaN or empty cells) |
| FR-105 | Compute derived rollcall fields: `total_vote`, `yes_percent`, `senate` flag (based on chamber size threshold) |
| FR-106 | Cache processed data to `data/{STATE}/processed_data.mat` to avoid reprocessing |

### 4.2 Bill Classification / Learning Algorithm (FR-200)

| ID | Requirement |
|----|-------------|
| FR-201 | Parse Congressional XML bill data to extract title, policy area, summary text, and subject areas |
| FR-202 | Clean text by removing numbers, short words (<=2 chars), HTML tags, and common/stop words |
| FR-203 | Build a learning table: for each issue code, compute word frequency weights from training bills |
| FR-204 | Support both 32-category (granular) and 11-category (concise) classification schemes via configurable recoding |
| FR-205 | Classify bills by matching cleaned title text against the learned word-weight vectors; assign the highest-scoring category |
| FR-206 | Support additional manually-chosen "boost" words per category with configurable issue-word-weight (iwv) and additional-word-weight (awv) parameters |
| FR-207 | Optimize iwv/awv parameters via grid search on a frontier (optimizeFrontierSimple) |
| FR-208 | Generate accuracy statistics and confusion-style adjacency matrices |
| FR-209 | Persist learning materials and results to .mat files |

### 4.3 Vote Processing and Agreement Matrices (FR-300)

| ID | Requirement |
|----|-------------|
| FR-301 | Build NxN legislator agreement matrices where each cell is (shared votes / possible votes) |
| FR-302 | Separately compute: chamber votes, committee votes, chamber sponsorship, committee sponsorship matrices |
| FR-303 | Filter bills by competitiveness threshold (default: 85% yes-vote ceiling) |
| FR-304 | Filter bills by issue category |
| FR-305 | Distinguish chamber vs. committee votes using a size threshold (default: 75% of chamber size) |
| FR-306 | Identify "third reading" / "on passage" votes via text pattern matching on vote descriptions |
| FR-307 | Clean matrices by removing legislators with no recorded votes |
| FR-308 | Normalize vote matrices (element-wise division of agreement by opportunity) |
| FR-309 | Partition matrices by party affiliation (Republican, Democrat) |
| FR-310 | Compute chamber-committee voting consistency per legislator |
| FR-311 | Compute seat proximity matrices using Euclidean distance (when seat position data available) |

### 4.4 Outcome Prediction — Bayesian Monte Carlo (FR-400)

| ID | Requirement |
|----|-------------|
| FR-401 | For each bill, compute initial vote probability using sponsor agreement scores via Bayesian inference |
| FR-402 | Iteratively update predictions as legislators reveal preferences in randomized order |
| FR-403 | Use the `updateBayes` function: P(yes) = (impact * prior) / (impact * prior + (1-impact) * (1-prior)) |
| FR-404 | Clamp probabilities to [0.001, 0.999] to avoid degenerate Bayesian updates |
| FR-405 | Run configurable Monte Carlo iterations (default: 16,000) with reproducible random seeds |
| FR-406 | Track accuracy at each step of legislator preference revelation |
| FR-407 | Compute per-legislator impact scores using placement-weighted accuracy deltas (F1-style point system) |
| FR-408 | Generate prediction boxplots across bills and Monte Carlo runs |

### 4.5 Elo Rating System (FR-500)

| ID | Requirement |
|----|-------------|
| FR-501 | Initialize all legislators at Elo score 1500 |
| FR-502 | Implement Variable-K Elo: K = 8000 / clamp(count, 200, 800) |
| FR-503 | Implement Fixed-K Elo: K = 16 |
| FR-504 | Score based on prediction accuracy: for each legislator pair, the one with higher prediction accuracy "wins" |
| FR-505 | Run Elo scoring across Monte Carlo iterations (default: 15,000) and average results |
| FR-506 | Support per-issue-category Elo scoring |
| FR-507 | Export Elo scores with legislator metadata to CSV |

### 4.6 Data Merging (FR-600)

| ID | Requirement |
|----|-------------|
| FR-601 | Merge Elo scores with campaign finance data by matching legislator names |
| FR-602 | Merge with Shor-McCarty ideology scores by matching legislator names |
| FR-603 | Handle name format normalization (last, first middle suffix nickname) |

### 4.7 Visualization (FR-700)

| ID | Requirement |
|----|-------------|
| FR-701 | Generate 3D surface plots (and flat 2D views) of agreement/sponsorship matrices |
| FR-702 | Generate histograms of agreement score distributions per legislator |
| FR-703 | Generate issue category frequency histograms |
| FR-704 | Generate Monte Carlo prediction boxplots (per-bill and aggregate) |
| FR-705 | Generate chamber-committee consistency histograms with fitted distributions |
| FR-706 | Save all plots as PNG files in organized output directories |

### 4.8 Export (FR-800)

| ID | Requirement |
|----|-------------|
| FR-801 | Export all matrices (chamber, committee, sponsor, party-specific) as CSV with row names |
| FR-802 | Export Elo scores per category as CSV |
| FR-803 | Export prediction model results as CSV |
| FR-804 | Persist intermediate data as serialized files (currently .mat, future: pickle/parquet/HDF5) |

---

## 5. Supported States and Jurisdictions

The system currently supports the following via `state_properties.m`, each with configured Senate (upper) and House (lower) chamber sizes:

| State | Squire Rank | Senate | House |
|-------|-------------|--------|-------|
| CA | 1 | 40 | 88 |
| NY | 2 | 63 | 150 |
| WI | 3 | 33 | 99 |
| OH | 7 | 33 | 99 |
| OR | 25 | 30 | 60 |
| VT | 26 | 30 | 150 |
| KY | 27 | 38 | 100 |
| IN | 41 | 50 | 100 |
| ME | 42 | 35 | 154 |
| MT | 43 | 50 | 100 |
| US | - | 100 | 435 |

LegiScan data is available for all 50 states + DC + US Congress.

---

## 6. Data Sources

| Source | Format | Location |
|--------|--------|----------|
| LegiScan Legislative Data | CSV, JSON | `legiscan_data/{STATE}/{session}/` |
| Congressional Bill XML | XML | `data/congressional_archive/*.xml` |
| Campaign Finance Data | XLSX, CSV | `finance_data/` |
| Shor-McCarty Ideology Scores | CSV, TAB | `shor_mccarty/` |
| Stata Analysis Data | DTA | `stata/` |
| Indiana Pre-compiled People Data | XLSX | `data/IN/undergrad/` |

---

## 7. Key Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `monte_carlo_number` | 16,000 | Number of Monte Carlo iterations for prediction |
| `elo_monte_carlo_number` | 15,000 | Number of Monte Carlo iterations for Elo |
| `committee_threshold` | 0.75 | Fraction of chamber size to distinguish committee from full-chamber votes |
| `competitive_threshold` | 0.85 | Maximum yes-vote percentage for a bill to be "competitive" |
| `bayes_initial` | 0.5 | Initial Bayesian prior for vote prediction |
| `cut_off` | 3,001 | Maximum number of words per category in learning table |
| `iwv` | 0.13 | Issue word weight for learning algorithm |
| `awv` | 0.0 | Additional word weight for learning algorithm |

---

## 8. Known Limitations and Technical Debt

1. **Senate/Committee Disambiguation** — Using total vote count vs. chamber size to distinguish Senate from House and committee from full-chamber is fragile (noted in source comments as "problematic").
2. **Indiana Hardcoding** — Special-case logic for Indiana reads pre-compiled Excel data instead of using the standard pipeline.
3. **Commented-out Committee Logic** — Committee vote processing in `processChamberVotes` is entirely commented out; committee matrices are set to empty.
4. **Code Duplication** — Significant copy-paste between `eloPrediction` and `predictOutcomes` (acknowledged in comments: "THIS IS ALL COPY+PASTED... SAD!").
5. **Windows Path Separators** — Some file paths use backslashes (`+la\parsed_xml.mat`), making the code Windows-dependent.
6. **`keyboard` Statement** — A debugging `keyboard` statement is left in `state.m:run()` line 263.
7. **No Automated Tests** — No test suite exists; `tester.m` is just a run script.
8. **No Dependency Management** — No `requirements.txt` or equivalent; relies on MATLAB toolboxes (Statistics, Optimization).
9. **Memory-Intensive** — Large `.mat` files and in-memory tables for all states; no lazy loading.
10. **Third-Party Dependencies** — `CStrAinBP` (case-sensitive string matching), `xml2struct` packaged as zip files in `reference/`.

---

## 9. Non-Functional Requirements

| Requirement | Description |
|-------------|-------------|
| **Reproducibility** | Random seeds must be set deterministically for all Monte Carlo runs |
| **Incremental Processing** | Support caching/loading of intermediate results to avoid recomputation |
| **Extensibility** | Easy to add new states by adding a case to state_properties |
| **Data Integrity** | Warn (but don't crash) on missing votes, bad party IDs, empty matrices |
| **Output Organization** | Structured directory hierarchy: `data/{STATE}/outputs/`, `/prediction_model/`, `/elo_model/`, `/histograms/` |
