# Program Requirements Document (PRD)
# The Forge Project — Legislative Analysis and Prediction System

**Authors:** Walter Schostak and Eric Waltenburg
**Current Implementation:** MATLAB (~4,900 lines across 63 files)
**Target Implementation:** Python
**Date:** 2026-02-28
**Version:** 2.0

---

## 1. Executive Summary

Forge is a computational political science platform that ingests U.S. state and federal legislative data (primarily from LegiScan), processes legislator voting records, builds agreement and sponsorship matrices, classifies bills by policy area using a word-frequency-based learning algorithm, and predicts legislative outcomes using Bayesian inference, Monte Carlo simulation, and an Elo rating system. The system produces statistical outputs, visualizations, and CSV exports for downstream academic analysis in Stata.

---

## 2. System Purpose and Goals

1. **Data Ingestion** — Read legislative data (bills, votes, rollcalls, sponsors, people, history) from LegiScan CSV and JSON datasets for any supported U.S. state or the U.S. Congress.
2. **Bill Classification** — Classify bills into policy categories (16 "concise" issue codes or 32 granular codes) using a word-frequency learning algorithm trained on Congressional XML bill data.
3. **Agreement Matrix Generation** — Compute legislator-to-legislator voting agreement matrices (chamber votes, committee votes, sponsorship matrices) for both full chamber and party-specific subsets.
4. **Outcome Prediction** — Predict bill passage using Bayesian updating of revealed legislator preferences, run as Monte Carlo simulations across randomized legislator orderings.
5. **Elo Rating** — Score legislators using an adapted Elo rating system (both fixed-K and variable-K variants), applied per-bill across Monte Carlo iterations.
6. **Data Merging** — Merge legislator scoring data with campaign finance data, Shor-McCarty ideology scores, and seniority data.
7. **Visualization** — Generate 3D surface plots, heatmaps, histograms, boxplots, and consistency plots of the agreement/sponsorship matrices.
8. **Export** — Output all matrices, scores, and predictions as CSV files for downstream analysis (e.g., in Stata).

---

## 3. Architecture Overview

### 3.1 Class Hierarchy

```
forge (superclass, MATLAB handle class)
  └── state (subclass)
```

- **`forge`** (`@forge/forge.m`, 522 lines) — The core engine. Contains all data properties, data-reading methods (`readAllFilesOfSubject`, `readAllInfo`), vote-processing logic (`addVotes`, `cleanVotes`, `normalizeVotes`), prediction algorithms, and plotting drivers. Defined as a MATLAB `handle` class with both instance and static methods.
- **`state`** (`@state/state.m`, 396 lines) — Extends `forge`. Configures state-specific properties (chamber sizes via `state_properties.m`), sets up output directory structure, loads the learning algorithm, and orchestrates the full pipeline via `run()`.

### 3.2 MATLAB Package Structure (Namespaces)

| Package | Files | Purpose |
|---------|-------|---------|
| `+la` | 14 `.m` files + data assets | **Learning Algorithm** — XML bill parsing, text cleanup, word-frequency learning table generation, bill classification, frontier optimization |
| `+predict` | 4 `.m` files | **Prediction** — Bayesian update function (`updateBayes`), impact calculator (`getSpecificImpact`), T-set plotting |
| `+plot` | 4 `.m` files | **Visualization** — Surface plots, histograms, GIF generation, plot orchestration |
| `+util` | 12 `.m` files + 2 MEX binaries | **Utilities** — Table creation, ID string generation, JSON parsing, data merging helpers, SLOC counting |
| `+util/+templates` | 3 `.m` files | **Data Templates** — Struct templates for bills, votes, and chambers |
| `+finance` | 2 `.m` files | **Finance** — Campaign finance data aggregation and merging |
| `+error_correction` | 2 `.m` files | **Error Analysis** — Elo scoring K-factor error investigation scripts |
| `@forge` | 16 `.m` files | **Core Engine** — All methods of the forge superclass |
| `@state` | 2 `.m` files | **State Runner** — Constructor, run method, state properties |

### 3.3 Constant Definitions

**PARTY_KEY** (defined in `forge.m`):
```
'0' → 'Democrat', '1' → 'Republican', '2' → 'Independent'
'Democrat' → 0, 'Republican' → 1, 'Independent' → 2
```
Note: LegiScan uses 1=Democrat, 2=Republican but the code adjusts `party_id` by subtracting 1 in `state.run()`.

**VOTE_KEY** (defined in `forge.m`):
```
'1' → 'yea', '2' → 'nay', '3' → 'absent', '4' → 'no vote'
```

**ISSUE_KEY** (defined in `state.m`, 16 concise categories):
```
1  → Agriculture
2  → Commerce, Business, Economic Development
3  → Courts & Judicial
4  → Education
5  → Elections & Apportionment
6  → Employment & Labor
7  → Environment & Natural Resources
8  → Family, Children, Human Affairs & Public Health
9  → Banks & Financial Institutions
10 → Insurance
11 → Government & Regulatory Reform
12 → Local Government
13 → Roads & Transportation
14 → Utilities, Energy & Telecommunications
15 → Ways & Means, Appropriations
16 → Other
```

### 3.4 Data Flow

```
LegiScan CSV/JSON Data
        │
        ▼
  forge.init() ─── CSV path: readAllFilesOfSubject() reads bills, people,
        │              rollcalls, sponsors, votes, history CSVs
        │          JSON path: readAllInfo() reads bill/vote/people JSON files
        │          Classifies each bill using la.classifyBill()
        │          Builds bill_set containers.Map keyed by bill_id
        │          Caches to data/{STATE}/processed_data.mat
        ▼
  state.run() ─── Filters people by year (max year) and chamber (role_id)
        │          Special case: Indiana reads precompiled Excel data
        │          For both House and Senate:
        │            Calls processChamberVotes() for category 0 and 1–11
        │            Generates agreement matrices (chamber, committee, sponsor)
        │            Partitions by party (Republican/Democrat)
        │            Computes seat proximity (if seat data available)
        │            Writes CSV outputs via writeTables()
        │            Generates visualizations via plot.plotRunner()
        │          Caches to data/{STATE}/saved_data.mat
        ▼
  Prediction ─── montecarloPrediction()
        │          → runMonteCarlo() iterates over bills
        │            → predictOutcomes() per bill, per MC iteration:
        │              • Computes sponsor effect via Bayesian updating
        │              • Randomizes legislator order
        │              • Iteratively reveals preferences using updateBayes()
        │              • Tracks accuracy at each step
        │          → processLegislatorImpacts() computes per-legislator scores
        │          Generates prediction boxplots
        ▼
  Elo Scoring ── eloMonteCarlo() orchestrator
        │          → eloPrediction() per MC iteration, per bill:
        │            • Same sponsor effect + Bayesian prediction as above
        │            • Pairwise Elo updates: higher accuracy legislator "wins"
        │            • Variable-K: K = 8000/clamp(count, 200, 800)
        │            • Fixed-K: K = 16
        │          Averages scores across MC iterations
        │          Supports per-issue-category scoring
        ▼
  Data Merge ─── finance.process() → finance.mergeData()
        │          → util.mergeShorMcCarty()
        │          → util.mergeSeniority()
        │          Joins Elo scores with finance, ideology, and seniority data
        ▼
  CSV/MAT Outputs + PNG Visualizations
```

---

## 4. Functional Requirements

### 4.1 Data Ingestion (FR-100)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-101 | Read LegiScan CSV files (bills, people, rollcalls, sponsors, votes, history) from `legiscan_data/{STATE}/{session}/csv/` directories, where session names match pattern `\d+-\d+_.*` | `forge.readAllFilesOfSubject()` |
| FR-102 | Concatenate multi-session CSV data, appending a `year` column extracted from the session directory name (first 4-digit group after hyphen in `\d+-(\d+)_.*`) | `forge.readAllFilesOfSubject()` |
| FR-103 | Handle schema differences between sessions: when a new table has columns missing from the existing table, fill with `NaN` (numeric) or empty cells (cell type) | `forge.readAllFilesOfSubject()` |
| FR-104 | Read LegiScan JSON files from `legiscan_data/{STATE}/{session}/bill/`, `/vote/`, `/people/` directories; build dict-like structures keyed by `bill_id`, `roll_call_id`, `people_id` | `forge.readAllInfo()` |
| FR-105 | Compute derived rollcall fields: `total_vote = yea + nay`, `yes_percent = yea / total_vote`, `senate` flag (`total_vote <= senate_size`) | `forge.init()` |
| FR-106 | For each bill, build a Bill struct containing: bill metadata, sponsors list, sorted history, classified issue category, house/senate chamber data (rollcalls separated by chamber), competitiveness flag, and passage status | `forge.init()` |
| FR-107 | Determine bill competitiveness: `final_yes_percentage < competitive_threshold` AND `final_yes_percentage > (1 - competitive_threshold)` | `forge.init()` |
| FR-108 | Cache processed data to `data/{STATE}/processed_data.mat`; reload if file exists and `reprocess` flag is false | `forge.init()` |
| FR-109 | Track people across sessions in JSON mode: update `last_year` for returning legislators | `forge.readAllInfo()` |

### 4.2 Bill Classification / Learning Algorithm (FR-200)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-201 | Parse Congressional XML bill data from `data/congressional_archive/*.xml` to extract: title, policy area, summary text (CDATA), and legislative subject areas | `la.xmlparse()` |
| FR-202 | Support incremental XML parsing: check for existing parsed data, compare file dates, only reparse new/updated bills | `la.xmlparse()` |
| FR-203 | Clean text by: splitting on non-word/whitespace characters, removing numbers and number-prefixed words (`\d+\w*`), removing 1-2 character words, removing `<p>` and `<b>` HTML tags, removing common/stop words (700+ words including US state names, months, Roman numerals, single letters, legislative terms), uppercasing, deduplicating with frequency counts | `la.cleanupText()` |
| FR-204 | Build a learning table: for each issue code, aggregate cleaned text from all training bills in that category, compute word frequency weights as `count / bill_count` per category, truncate to top `cut_off` words (default: 3,001) | `la.generateLearningTable()` |
| FR-205 | Support both 32-category (granular) and 11-category (concise) classification schemes. Concise recoding groups: `{[1,2],[9,15,30],[25,32,13],[26,10],[5,24,28],[7,17],[4,27,29],[19,12,31],[3,6,8,11,23],[16,20,21],[14,18,22]}` | `la.main()` |
| FR-206 | Classify bills by: cleaning bill title, matching against each category's learned word vectors, summing `learned_weight * title_word_weight` products, assigning the highest-scoring category. Return NaN if no matches found | `la.classifyBill()` |
| FR-207 | Support additional manually-chosen "boost" words per category, weighted by configurable `iwv` (issue word weight, default 0.13) and `awv` (additional word weight, default 0.0) parameters | `la.generateLearningTable()` |
| FR-208 | Optimize iwv/awv parameters via iterative grid search: start coarse, zoom in on the optimum with decreasing step size (factor 0.5), stop at step size floor of `10^-5` | `la.optimizeFrontierSimple()` |
| FR-209 | Generate accuracy statistics, confusion-style adjacency matrices, and issue code frequency histograms | `la.processAlgorithm()`, `la.generateAdjacencyMatrix()` |
| FR-210 | Persist learning materials and results to `.mat` files for reuse; support loading pre-trained data via `la.loadLearnedMaterials()` | `la.main()`, `la.loadLearnedMaterials()` |

### 4.3 Vote Processing and Agreement Matrices (FR-300)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-301 | Build NxN legislator agreement matrices (as labeled tables with `id{N}` row/column names) initialized to NaN. Each cell becomes: `(shared agreement votes) / (total possible shared votes)` | `processChamberVotes()`, `util.createTable()` |
| FR-302 | Separate rollcalls into chamber vs. committee by vote size threshold: votes with `total_vote < chamber_size * committee_threshold` are committee votes; others are full-chamber | `processChamberRollcalls()` |
| FR-303 | For each rollcall, extract yes/no/abstain voter lists by matching `vote` column against VOTE_KEY constants | `addRollcallVotes()` |
| FR-304 | Filter bills by competitiveness flag and issue category before matrix processing | `processChamberVotes()` |
| FR-305 | Filter chamber votes by vote description: only process votes matching `(THIRD\|3RD\|ON PASSAGE)` regex (third reading / passage votes) | `processChamberVotes()` |
| FR-306 | Build four matrix types per chamber: chamber agreement, chamber sponsorship, committee agreement (currently disabled), committee sponsorship (currently disabled) | `processChamberVotes()` |
| FR-307 | Agreement matrix construction: for matching voters (both voted yes, or both voted no), add 1 to agreement cell; for disagreeing voters, add 0; always increment possible-votes matrix | `forge.addVotes()` |
| FR-308 | Sponsorship matrix: sponsors get agreement/disagreement scores with voters on the final vote | `processChamberVotes()` |
| FR-309 | Clean matrices: remove legislators with all-NaN rows (no recorded votes), with warnings | `forge.cleanVotes()` |
| FR-310 | Clean sponsor matrices: additionally remove sponsors below the sponsor filter threshold (mean - std/2 of sponsorship counts) | `forge.cleanSponsorVotes()` |
| FR-311 | Normalize all matrices: element-wise `agreement / possible_votes` | `forge.normalizeVotes()` |
| FR-312 | Partition matrices by party: extract Republican-only and Democrat-only sub-matrices | `forge.processParties()`, `processChamberVotes()` |
| FR-313 | Compute seat proximity matrices using Euclidean distance when SEATROW/SEATCOLUMN data exists | `forge.processSeatProximity()` |
| FR-314 | Track chamber-committee voting consistency per legislator (currently disabled, consistency matrix allocated but not populated) | `processChamberVotes()` |
| FR-315 | Process matrices for all categories (0 = all, 1-11 = individual concise categories) when `generate_all_categories` flag is set | `state.run()` |

### 4.4 Outcome Prediction — Bayesian Monte Carlo (FR-400)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-401 | For each bill, compute initial sponsor effect: for each sponsor, compute Bayesian posterior from agreement scores with other sponsors. Formula: `P = prod(impacts) * prior / (prod(impacts) * prior + prod(1-impacts) * (1-prior))`. Requires >1 sponsor; otherwise set all to 0.5 | `predictOutcomes()` |
| FR-402 | Apply `getSpecificImpact()` to clamp agreement values to [0.001, 0.999] and flip direction for "no" votes (impact becomes `1 - impact` for revealed_preference=0) | `predict.getSpecificImpact()` |
| FR-403 | Iteratively update predictions using `updateBayes()`: for each revealed legislator, compute per-legislator impact as `abs(1 - revealed_preference - agreement_score)`, then update posterior: `P_new = (impact * P_old) / (impact * P_old + (1-impact) * (1-P_old))` | `predict.updateBayes()` |
| FR-404 | Clamp posterior probabilities to [0.001, 0.999] to avoid degenerate updates. Set revealed legislator's own probability to `abs(revealed_preference - 0.001)` | `predict.updateBayes()` |
| FR-405 | Preserve NaN values: if a legislator had NaN prior, keep NaN posterior (don't update based on unrevealed preferences) | `predict.updateBayes()` |
| FR-406 | Compute accuracy at each step: `100 * (1 - (incorrect - are_nan) / (100 - are_nan))` | `predict.updateBayes()` |
| FR-407 | Run configurable Monte Carlo iterations (default: 16,000) with reproducible random seeds using Mersenne Twister (`mt19937ar`) seeded with the iteration number | `predictOutcomes()`, `util.setRandomSeed()` |
| FR-408 | For each MC iteration, randomize legislator revelation order via `randperm` | `predictOutcomes()` |
| FR-409 | Skip incomplete bills (missing data) and bills with fewer than 50% of chamber size voting | `predictOutcomes()` |
| FR-410 | Compute per-legislator impact scores using placement-weighted accuracy deltas: `score = sum(delta * placement_points) / (1 - initial_accuracy)`, where placement points are linearly spaced from 100 to 1 across positions | `processLegislatorImpacts()` |
| FR-411 | Aggregate legislator impacts across all bills, normalize scores to [0, 1] range relative to max scorer, compute coverage (fraction of bills each legislator appears in) | `processLegislatorImpacts()` |

### 4.5 Elo Rating System (FR-500)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-501 | Initialize all legislators at Elo score 1500 with two score variants (variable-K and fixed-K) and a match count of 0 | `eloPrediction()` |
| FR-502 | For each bill: compute the same sponsor effect and Bayesian prediction as the outcome prediction system (FR-401 through FR-406), obtaining per-legislator accuracy scores | `eloPrediction()` |
| FR-503 | Perform pairwise Elo updates for all legislator pairs: the one with higher prediction accuracy "wins" (W=1), equal accuracy gets W=0.5 | `eloPrediction()` |
| FR-504 | Variable-K Elo: `K = 8000 / clamp(count, 200, 800)` — K ranges from 40 (low count) to 10 (high count) | `eloPrediction()` |
| FR-505 | Fixed-K Elo: `K = 16` for all legislators | `eloPrediction()` |
| FR-506 | Elo update formula: `new_score = old_score + K * (W - E)`, where `E = 1 / (1 + 10^((opponent_score - own_score) / 400))` | `eloPrediction()` |
| FR-507 | Run Elo scoring across Monte Carlo iterations (default: 15,000) and average the variable-K and fixed-K scores | `eloMonteCarlo()` |
| FR-508 | Support per-issue-category Elo scoring: filter bills by category, run separate Elo chains, produce separate CSV outputs per category | `eloMonteCarlo()` |
| FR-509 | Compute score difference (variable-K minus fixed-K) and join with legislator metadata from people table | `eloPrediction()` |
| FR-510 | Cache Elo results to `.mat` files; support reload without recomputation | `eloPrediction()` |

### 4.6 Data Merging (FR-600)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-601 | Process campaign finance data: for each unique legislator name, aggregate financial columns (sum) across years | `finance.process()` |
| FR-602 | Merge Elo scores with campaign finance data by constructing normalized full names: `"LAST SUFFIX, FIRST MIDDLE (NICKNAME)"` uppercased, periods removed | `finance.mergeData()` |
| FR-603 | Merge with Shor-McCarty ideology scores using the same name normalization | `util.mergeShorMcCarty()` |
| FR-604 | Merge with seniority data: for each legislator, take the most recent election year's cumulative terms served | `util.mergeSeniority()` |
| FR-605 | Indiana special case: additionally join with precompiled people file from `data/IN/undergrad/` | `finance.mergeData()` |
| FR-606 | All merges use `CStrAinBP` for bidirectional name matching and MATLAB `join` for table combination | All merge files |

### 4.7 Visualization (FR-700)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-701 | Generate 3D surface plots (`surf`) and flat 2D heatmaps (via `view(2)`) of agreement/sponsorship matrices with jet colormap, axis [0,1], colorbar | `plot.generatePlots()` |
| FR-702 | Generate per-legislator agreement score histograms with fitted normal distribution (`histfit`): separate plots for matching legislators (diagonal) and non-matching (off-diagonal) | `plot.generateHistograms()` |
| FR-703 | Generate issue category frequency histograms comparing all bills vs. competitive bills | `forge.init()` |
| FR-704 | Generate Monte Carlo prediction boxplots: per-bill accuracy, per-bill delta, total accuracy, total delta | `forge.runMonteCarlo()` |
| FR-705 | Generate chamber-committee consistency histogram with fitted distribution | `plot.plotRunner()` |
| FR-706 | Save all plots as PNG files in organized output directories: `{outputs_directory}/{tag}.png`, `{histogram_directory}/{tag}_histogram_all.png` | All plot functions |
| FR-707 | Plot runner orchestrates 6 chamber types x 2 (chamber + committee) = 12 matrix plots plus consistency, for each chamber and each category | `plot.plotRunner()` |

### 4.8 Export (FR-800)

| ID | Requirement | Source File |
|----|-------------|-------------|
| FR-801 | Export all matrices as CSV with row names. File naming convention: `{outputs_dir}/{C}_{type}_{party}_{modifier}_{category}.csv` where C=H/S (house/senate), type=cha/com, party=A/R/D, modifier=matrix/votes/s_matrix/s_votes | `forge.writeTables()` |
| FR-802 | Delete existing CSV files for a chamber/category before writing new ones | `forge.writeTables()` |
| FR-803 | Export Elo scores per category as CSV with row names: `{elo_dir}/{C}_elo_score_{category}.csv` for single-pass; `{elo_dir}/{C}_elo_score_total_{category}_mc{N}.csv` for MC-averaged | `eloPrediction()`, `eloMonteCarlo()` |
| FR-804 | Export prediction model results as CSV: `{outputs_dir}/{C}_prediction_model_results_m{N}.csv` | `montecarloPrediction()` |
| FR-805 | Export merged data as CSV: `data/{STATE}/merged_data/*.csv` | `finance.mergeData()`, `util.mergeShorMcCarty()` |
| FR-806 | Persist intermediate data as serialized files (currently .mat, future: pickle/parquet) for session resumption | Various |
| FR-807 | Export seat proximity matrix as CSV when seat data is available | `forge.writeTables()` |

---

## 5. Supported States and Jurisdictions

Configured in `@state/state_properties.m`. States are selected based on Squire legislative professionalism index for high/medium/low representation:

| State | Squire Rank | Senate (Upper) | House (Lower) | Tier |
|-------|-------------|----------------|---------------|------|
| CA | 1 | 40 | 88 | High |
| NY | 2 | 63 | 150 | High |
| WI | 3 | 33 | 99 | High |
| OH | 7 | 33 | 99 | High |
| OR | 25 | 30 | 60 | Medium |
| VT | 26 | 30 | 150 | Medium |
| KY | 27 | 38 | 100 | Medium |
| IN | 41 | 50 | 100 | Low |
| ME | 42 | 35 | 154 | Low |
| MT | 43 | 50 | 100 | Low |
| US | — | 100 | 435 | Federal |

LegiScan data is available for all 50 states + DC + US Congress in `legiscan_data/`.

Adding a state requires: (1) adding a case to `state_properties.m`, (2) having LegiScan data in `legiscan_data/{STATE}/`.

---

## 6. Data Sources

| Source | Format | Location | Usage |
|--------|--------|----------|-------|
| LegiScan Legislative Data | CSV (bills, people, rollcalls, sponsors, votes, history) | `legiscan_data/{STATE}/{session}/csv/` | Primary data ingestion |
| LegiScan Legislative Data | JSON (bill, vote, people) | `legiscan_data/{STATE}/{session}/bill/`, `/vote/`, `/people/` | Alternative JSON ingestion path |
| Congressional Bill XML | XML (~2,600+ files) | `data/congressional_archive/*.xml` | Training data for learning algorithm |
| Campaign Finance Data | XLSX, CSV | `finance_data/{STATE}_reduced.xlsx`, `{STATE}_merged_data.csv` | Post-Elo data merging |
| Shor-McCarty Ideology Scores | CSV, TAB | `shor_mccarty/shor_mccarty_{STATE}.csv` | Post-Elo data merging |
| Seniority Data | CSV | `finance_data/seniority_data_{STATE}.csv` | Post-Elo data merging |
| Indiana Pre-compiled People | XLSX | `data/IN/undergrad/people_2013-2014.xlsx` | Special case for IN |
| Stata Analysis Scripts | .do files | `stata/` | Downstream analysis of CSV outputs |
| LegiScan API Manual | PDF | `legiscan_data/LegiScan_API_User_Manual.pdf` | Reference documentation |

---

## 7. Key Configuration Parameters

| Parameter | Default | Set In | Description |
|-----------|---------|--------|-------------|
| `monte_carlo_number` | 16,000 | `state.m` constructor | MC iterations for Bayesian prediction |
| `elo_monte_carlo_number` | 15,000 | `state.m:run()` | MC iterations for Elo scoring |
| `committee_threshold` | 0.75 | `state.m` constructor | Fraction of chamber size distinguishing committee from full-chamber votes |
| `competitive_threshold` | 0.85 | `state.m` constructor | Maximum yes-vote % for a bill to be "competitive" |
| `bayes_initial` | 0.5 | `predictOutcomes.m`, `eloPrediction.m` | Starting Bayesian prior |
| `cut_off` | 3,001 | `generateLearningTable.m` | Max words per category in learning table |
| `iwv` | 0.13 | `la.main()` | Issue word weight for classification |
| `awv` | 0.0 | `la.main()` | Additional word weight for classification |
| `sponsor_filter` | mean - std/2 | `cleanSponsorVotes.m` | Min sponsorship count to keep in sponsor matrix |
| `Elo initial score` | 1500 | `eloPrediction.m` | Starting Elo rating for all legislators |
| `Elo variable-K range` | 8000 / [200, 800] | `eloPrediction.m` | K = 8000/clamp(count, 200, 800) |
| `Elo fixed-K` | 16 | `eloPrediction.m` | Constant K factor |
| `random seed` | iteration number | `util.setRandomSeed()` | Mersenne Twister seeded per MC iteration |

---

## 8. Third-Party Dependencies

### 8.1 MATLAB Toolboxes
- **Statistics and Machine Learning Toolbox** — `histfit`, `randperm`
- **Optimization Toolbox** — frontier optimization

### 8.2 Third-Party MEX Binaries (Windows-only)
| Binary | Purpose | Location |
|--------|---------|----------|
| `CStrAinBP.mexw64` | Case-sensitive string matching: finds indices of elements in array A that appear in array B. Returns `[indices_in_A, indices_in_B]`. Used pervasively (~30 call sites). | `+util/` |
| `xml2struct.mexw64` | Parses XML files into MATLAB struct trees | `+util/` |

### 8.3 Reference Libraries (zipped, not directly used)
- `reference/CStrAinBP_20130408.zip`
- `reference/xml2struct.zip`
- `reference/pugixml.zip`

---

## 9. Output Directory Structure

```
data/{STATE}/
├── processed_data.mat                    # Cached ingested data
├── saved_data.mat                        # Cached computed matrices
├── issue_category_frequency_total.png
├── issue_category_frequency_competitive.png
├── outputs/
│   ├── {C}_cha_A_matrix_{cat}.csv       # Chamber agreement matrix
│   ├── {C}_cha_A_votes_{cat}.csv        # Chamber possible votes
│   ├── {C}_cha_R_votes_{cat}.csv        # Republican chamber votes
│   ├── {C}_cha_D_votes_{cat}.csv        # Democrat chamber votes
│   ├── {C}_cha_A_s_matrix_{cat}.csv     # Sponsor chamber matrix
│   ├── {C}_cha_A_s_votes_{cat}.csv      # Sponsor possible votes
│   ├── {C}_cha_R_s_votes_{cat}.csv      # Republican sponsor votes
│   ├── {C}_cha_D_s_votes_{cat}.csv      # Democrat sponsor votes
│   ├── {C}_com_*.csv                    # Committee variants (if active)
│   ├── {C}_consistency_matrix_{cat}.csv # Chamber-committee consistency
│   ├── {C}_seat_matrix_{cat}.csv        # Seat proximity
│   ├── {C}_prediction_boxplot_m{N}.png
│   ├── {C}_prediction_delta_boxplot_m{N}.png
│   ├── {C}_prediction_total_boxplot_m{N}.png
│   ├── {C}_prediction_model_results_m{N}.csv
│   ├── {C}_{tag}.png                    # Surface plots
│   ├── {C}_{tag}_flat.png               # Flat heatmaps
│   └── histograms/
│       ├── {C}_{tag}_histogram_all.png
│       └── {C}_{tag}_histogram_match.png
├── prediction_model/
│   └── {C}_prediction_model_m{N}.mat
├── elo_model/
│   ├── {C}_elo_score_{cat}.csv
│   ├── {C}_elo_prediction_{cat}.mat
│   └── MC/
│       ├── {C}_elo_score_total_{cat}_mc{N}.csv
│       └── {C}_elo_prediction_total_{cat}_mc{N}.mat
└── merged_data/
    └── *.csv                             # Finance + ideology merged data
```

Where `{C}` = H (House) or S (Senate), `{cat}` = category number (0=all, 1-11=individual), `{N}` = MC iteration count.

---

## 10. Known Limitations and Technical Debt

### Critical Issues
1. **Senate/Committee Vote Disambiguation** — Using `total_vote <= senate_size` to determine if a vote is a Senate vote is fragile and explicitly noted as "PROBLEMATIC" in source comments. Committee votes with similar counts will be misclassified. The source notes: "THIS REALLY FUCKS UP COMMITTEES."
2. **Committee Processing Disabled** — The entire committee vote processing block in `processChamberVotes.m` is commented out (lines 63-108). Committee matrices are always set to empty arrays `[]`.
3. **Duplicated Code** — `eloPrediction.m` copy-pastes ~60 lines from `predictOutcomes.m` for the sponsor effect and Bayesian prediction. Source acknowledges: "THIS IS ALL COPY+PASTED FROM PREDICTOUTCOMES. SAD!"

### Medium Issues
4. **Indiana Hardcoding** — When standard data reading fails for IN, falls back to `data/IN/undergrad/people_2013-2014.xlsx`. Finance merging also has an IN-specific code path.
5. **`keyboard` Debug Statement** — A `keyboard` breakpoint remains at `state.m` line 263, pausing execution.
6. **Windows Path Separators** — File paths use backslashes (`+la\parsed_xml.mat`), making code Windows-dependent.
7. **No Automated Tests** — No test suite. `tester.m` is a manual run script.
8. **Memory-Intensive** — All data held in memory with large `.mat` files.
9. **Suppressed Warnings** — `warning('OFF','ALL')` used in multiple places.

### Bugs Found During Analysis
10. **`classifyBill.m` line 13** — References undeclared variable `text` instead of `clean_title`.
11. **`outputBillInformation.m` line 14** — References undeclared variable `senate_bill_ids` instead of `chamber_bill_ids`.
12. **Accuracy denominator** — `updateBayes.m` and `predictOutcomes.m` use hardcoded `100` instead of actual legislator count in accuracy formula.
13. **Consistency matrix not populated** — Tracking code in `processChamberVotes.m` (lines 153-159) is commented out.
14. **Elo K-factor historical bug** — `k_factor_error.m` documents a typo (`count > 80` vs `count > 800`) that was corrected.

---

## 11. Non-Functional Requirements

| Requirement | Description |
|-------------|-------------|
| **Reproducibility** | Random seeds must be set deterministically for all Monte Carlo runs using Mersenne Twister seeded with iteration number |
| **Incremental Processing** | Support caching/loading of intermediate results to avoid recomputation |
| **Extensibility** | Easy to add new states by adding configuration and having LegiScan data |
| **Data Integrity** | Warn (but don't crash) on missing votes, bad party IDs, empty matrices |
| **Output Compatibility** | CSV output structure and column names must remain identical so existing Stata `.do` scripts work unchanged |
| **Output Organization** | Structured directory hierarchy per state with consistent naming conventions |
| **Performance** | MC prediction and Elo scoring complete in reasonable time for full states |

---

## 12. File Inventory Summary

| Component | Files | ~Lines |
|-----------|-------|--------|
| `@forge/` (core engine) | 16 | ~1,800 |
| `@state/` (subclass) | 2 | ~450 |
| `+la/` (learning algorithm) | 14 | ~850 |
| `+predict/` (Bayesian prediction) | 4 | ~120 |
| `+plot/` (visualization) | 4 | ~175 |
| `+util/` (utilities + templates) | 15 | ~280 |
| `+finance/` (data merging) | 2 | ~110 |
| `+error_correction/` (analysis) | 2 | ~100 |
| Top-level (`tester.m`, `startup.m`) | 2 | ~90 |
| **Total** | **63** | **~4,900** |
