# Kidsights Data Platform - Development Guidelines

**Last Updated:** April 2026 | **Version:** 3.8.0

This is a quick reference guide for AI assistants working with the Kidsights Data Platform. For detailed documentation, see the [Documentation Directory](#documentation-directory) below.

---

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research with **eight independent pipelines**:

1. **NE25 Pipeline** - REDCap survey data processing (Nebraska 2025 study)
2. **MN26 Pipeline** - REDCap survey data processing (Minnesota 2026 study, multi-child households)
3. **ACS Pipeline** - IPUMS USA census data extraction
4. **NHIS Pipeline** - IPUMS Health Surveys data extraction
5. **NSCH Pipeline** - National Survey of Children's Health data integration
6. **Raking Targets Pipeline** - Population-representative targets for post-stratification weighting
7. **Imputation Pipeline** - Multiple imputation for geographic, sociodemographic, childcare, and mental health uncertainty
8. **IRT Calibration Pipeline** - Mplus calibration dataset creation for psychometric scale recalibration

### Running Pipelines

**NE25 Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**MN26 Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_mn26_pipeline.R

# Skip database (test mode)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_mn26_pipeline.R --skip-database
```

**ACS Pipeline:**
```bash
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**NHIS Pipeline:**
```bash
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**NSCH Pipeline:**
```bash
python scripts/nsch/process_all_years.py --years 2023
python scripts/nsch/process_all_years.py --years all  # Process all years (2016-2023)
```

**Raking Targets Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R

# Verify results
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

**NE25 Raking Weights (M=5 multi-imputation, Bucket 2 — April 2026):**
```bash
# Full M=5 calibrated raking-weight pipeline (scripts 32 -> 33 -> 34).
# Prerequisites: run_raking_targets_pipeline.R + scripts 25..30b + imputation pipeline.
# Output: ne25_raked_weights DuckDB table (5 x N rows). Typical runtime ~17-20 min.
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_ne25_raking_full.R
```

**NE25 Bayesian-Bootstrap Replicate Weights (Bucket 3 — April 2026):**
```bash
# MI + sample-only Bayesian bootstrap: M=5 imputations x B=200 replicates = 1,000 Stan refits.
# Prerequisites: Bucket 2 weights (ne25_raked_weights) and harmonized feathers.
# Resumable per-(m,b) feathers under data/raking/ne25/ne25_weights_boot/.
# Output: ne25_raked_weights_boot DuckDB table (1000 x N = 2,645,000 rows).
# Runtime: ~3 hours wall-clock on 8 future::multisession workers with pre-compiled Stan.
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/35_run_bayesian_bootstrap.R
py scripts/raking/ne25/36_store_bootstrap_weights_long.py
```

**Imputation Pipeline:**
```bash
# Setup database schema (one-time, study-specific)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25

# Run full pipeline (geography + sociodem + childcare + mental health + child ACEs + database insertion)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R

# Validate results
python -m python.imputation.helpers
```

**IRT Calibration Pipeline:**
```bash
# Full pipeline (create tables + long format + export to Mplus)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R

# Skip long format creation (faster, ~30 seconds saved)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-long-format

# Skip quality checks (use with caution)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-quality-check
```

### Key Requirements

- **R 4.5.1** with arrow, duckdb packages
- **Python 3.13+** with duckdb, pandas, pyyaml, ipumspy, python-dotenv
- **IPUMS API key:** Configure via `.env` file (see [Environment Configuration](#environment-configuration))
- **REDCap API key:** Configure via `.env` file (see [Environment Configuration](#environment-configuration))

**📖 For detailed pipeline documentation, see:**
- [Quick Reference](docs/QUICK_REFERENCE.md) - Command cheatsheet
- [Pipeline Overview](docs/architecture/PIPELINE_OVERVIEW.md) - Architecture details
- [Pipeline Steps](docs/architecture/PIPELINE_STEPS.md) - Execution instructions

---

## Environment Configuration

**🌍 Cross-Platform Portability via Environment Variables**

The platform uses a **3-tier configuration system** for portability across machines and operating systems:

1. **Environment Variables** (`.env` file) - **HIGHEST PRIORITY**
2. **Config YAML Files** (`config/sources/*.yaml`) - Secondary
3. **Cross-Platform Defaults** (`~/.kidsights/`) - Fallback

### Quick Setup for New Machines

```bash
# 1. Copy environment template
cp .env.template .env

# 2. Edit with your local paths
# Windows: notepad .env
# Mac/Linux: nano .env

# 3. Configure API key paths
IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv
```

### Environment Variables Reference

| Variable | Purpose | Default Fallback |
|----------|---------|------------------|
| `IPUMS_API_KEY_PATH` | IPUMS API key location (ACS/NHIS) | `~/.kidsights/IPUMS.txt` |
| `REDCAP_API_CREDENTIALS_PATH` | REDCap API credentials (NE25) | `~/.kidsights/kidsights_redcap_api.csv` |
| `KIDSIGHTS_DB_PATH` | DuckDB database override (optional) | `data/duckdb/kidsights_local.duckdb` |

**📖 Complete installation guide:** [docs/setup/INSTALLATION_GUIDE.md](docs/setup/INSTALLATION_GUIDE.md)

**⚠️ Security:** The `.env` file is gitignored and never committed. Each collaborator maintains their own `.env` file with machine-specific paths.

---

## Critical Coding Standards

### 1. R Namespacing (REQUIRED)

**All R function calls MUST use explicit package namespacing:**

```r
# ✅ CORRECT
library(dplyr)
data %>%
  dplyr::select(pid, record_id) %>%
  dplyr::mutate(new_var = old_var * 2) %>%
  arrow::write_feather("output.feather")

# ❌ INCORRECT (causes namespace conflicts)
data %>%
  select(pid, record_id) %>%
  mutate(new_var = old_var * 2)
```

**Required Prefixes:**
- `dplyr::` - select(), filter(), mutate(), summarise(), group_by(), left_join()
- `tidyr::` - pivot_longer(), pivot_wider(), separate()
- `stringr::` - str_split(), str_extract(), str_detect()
- `arrow::` - read_feather(), write_feather()

### 2. Windows Console Output (REQUIRED)

**All Python print() statements MUST use ASCII characters only (no Unicode symbols).**

```python
# ✅ CORRECT - ASCII output (Windows-compatible)
print("[OK] Data loaded successfully")
print("[ERROR] Failed to connect")

# ❌ INCORRECT - Unicode symbols (causes UnicodeEncodeError)
print("✓ Data loaded successfully")
print("✗ Failed to connect")
```

**Standard Replacements:** `✓` → `[OK]`, `✗` → `[ERROR]`, `⚠` → `[WARN]`, `ℹ` → `[INFO]`

### 3. Missing Data Handling (CRITICAL)

**All derived variables MUST use `recode_missing()` before transformation to prevent sentinel values from contaminating composite scores.**

```r
# ✅ CORRECT - Recode missing values before transformation
for(old_name in names(variable_mapping)) {
  if(old_name %in% names(dat)) {
    new_name <- variable_mapping[[old_name]]
    # Convert 99 (Prefer not to answer) to NA before assignment
    derived_df[[new_name]] <- recode_missing(dat[[old_name]], missing_codes = c(99))
  }
}

# ❌ INCORRECT - Copying raw values directly
derived_df[[new_name]] <- dat[[old_name]]  # 99 values persist!
```

**Conservative Approach:** All composite scores use `na.rm = FALSE` in calculations. If ANY component item is missing, the total score is marked as NA rather than creating potentially misleading partial scores.

**Critical Issue Prevented:** 254+ records (5.2% of dataset) had invalid ACE total scores (99-990 instead of 0-10) due to "Prefer not to answer" (99) being summed directly before this standard was implemented.

**📖 Complete guidance:**
- [Missing Data Guide](docs/guides/MISSING_DATA_GUIDE.md) - Comprehensive documentation
- [Composite Variables Inventory](docs/guides/MISSING_DATA_GUIDE.md#complete-composite-variables-inventory) - All 12 composite variables

### 4. R Execution (CRITICAL)

⚠️ **Never use inline `-e` commands - they cause segmentation faults**

```bash
# ✅ CORRECT - Use temp script files
echo 'library(dplyr); cat("Success\n")' > scripts/temp/temp_script.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/temp/temp_script.R

# ❌ INCORRECT - Causes segfaults
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "library(dplyr)"
```

### 5. Safe Joins (REQUIRED)

**All `dplyr::left_join()` calls MUST use `safe_left_join()` wrapper to prevent column collisions.**

```r
# ✅ CORRECT - Uses safe_left_join wrapper
source("R/utils/safe_joins.R")
data %>%
  safe_left_join(eligibility_data, by_vars = c("pid", "record_id"))

# ❌ INCORRECT - Direct dplyr::left_join (causes collisions)
data %>%
  dplyr::left_join(eligibility_data, by = c("pid", "record_id"))
```

**Why This Matters:**
- Detects overlapping column names (like `eligible`, `data_quality`) before joining
- Auto-fixes collisions by removing duplicate columns from right table with warnings
- Validates row count doesn't change (catches many-to-many joins)
- Prevents `.x`/`.y` suffix confusion (e.g., `eligible.x` vs `eligible.y`)

**Function Location:** `R/utils/safe_joins.R`

**Parameters:**
- `by_vars`: Join key column names (required, replaces `by`)
- `allow_collision`: If TRUE, allows `.x`/`.y` suffixes (default: FALSE)
- `auto_fix`: If TRUE, automatically removes colliding columns from right table (default: TRUE)

**📖 Complete documentation:** [CODING_STANDARDS.md - Safe Joins](docs/guides/CODING_STANDARDS.md#safe-joins-critical)

### 6. Python Execution from R (REQUIRED)

⚠️ **Never hardcode `"python"` in system2() calls - use `get_python_path()`**

**All R scripts that call Python MUST use the `get_python_path()` function:**

```r
# ✅ CORRECT - Uses environment-aware path resolution
source("R/utils/environment_config.R")
python_path <- get_python_path()
system2(python_path, args = c("script.py", "--arg", "value"))

# ❌ INCORRECT - Hardcoded "python" fails on Windows
system2("python", args = c("script.py", "--arg", "value"))
```

**Why This Matters:**
- Windows uses the `py` launcher instead of `python.exe` in PATH
- Hardcoded `"python"` causes `'"python"' not found` errors on new machines
- `get_python_path()` resolves the correct executable by checking:
  1. `PYTHON_EXECUTABLE` environment variable from `.env` (highest priority)
  2. Common Windows installation paths (`AppData/Local/Programs/Python/`)
  3. System PATH fallbacks (`py`, `python3`, `python`)

**Cross-Platform Compatibility:**
```r
# This pattern works on Windows, Mac, and Linux:
source("R/utils/environment_config.R")
python_path <- get_python_path()

# Use python_path in all system2() calls
system2(python_path, args = c("pipelines/python/init_database.py"))
system2(python_path, args = c("pipelines/python/insert_raw_data.py", "--table", "ne25_raw"))
```

**📖 Complete coding standards:** [CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)

**📖 Environment configuration:** [INSTALLATION_GUIDE.md - PYTHON_EXECUTABLE](docs/setup/INSTALLATION_GUIDE.md#python_executable-configuration)

---

## Common Tasks

### Run Pipelines
```bash
# NE25 Pipeline (REDCap survey data)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R

# Test database connection
python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

### Generate Documentation
```bash
# Generate data dictionary and metadata exports
python scripts/documentation/generate_html_documentation.py

# Render codebook dashboard
quarto render codebook/dashboard/index.qmd
```

### Query Data
```python
from python.db.connection import DatabaseManager
db = DatabaseManager()

# Get record count using context-managed connection (no execute_query method exists)
with db.get_connection(read_only=True) as con:
    result = con.execute("SELECT COUNT(*) FROM ne25_raw").fetchone()
    print(f"Total records: {result[0]}")
```

### Create IRT Calibration Dataset
```bash
# Run full calibration pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R

# Outputs:
#   - Wide format table: calibration_dataset_2020_2025 (47,084 records, 303 columns)
#   - Long format table: calibration_dataset_long (1,316,391 rows, 9 columns)
#   - Mplus export: mplus/calibdat.dat (38.71 MB, 47,084 records, 419 columns)
#   - Execution time: ~5-7 minutes with long format, ~3-5 minutes without

# Skip long format creation (faster iteration)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-long-format
```

### Launch Quality Assurance Tools
```bash
# Age-Response Gradient Explorer (IRT calibration QA - REQUIRED)
shiny::runApp("scripts/shiny/age_gradient_explorer")
```

**Purpose:** Mandatory visual inspection of age-response gradients before Mplus calibration

**Prerequisites:**
- Calibration dataset created (`calibration_dataset_2020_2025` and `calibration_dataset_long` tables)
- Precomputed models recommended (run `source("scripts/shiny/age_gradient_explorer/precompute_models.R")`)

**What it does:**
- Box plots showing age distributions at each response level
- GAM smoothing for non-linear developmental trends
- Quality flag warnings (negative correlations, category mismatches)
- Multi-study filtering (6 studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24)

**New features (v3.0+):**
- Configurable influence threshold slider (1-5% Cook's D quantile)
- Database-backed review notes with JSON export
- Domain labels in item dropdown (Cognitive/Language, Motor, Social-Emotional, Psychosocial Problems)
- Masking toggle to compare original vs QA-cleaned data (Issue #11: partial implementation)
- Response options display below item stem (Issue #11: partial implementation)

### Quick Debugging
1. **Database:** `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"`
2. **R Packages:** Use temp script files, never inline `-e`
3. **Pipeline:** Run from project root directory
4. **Logs:** Check Python error context for detailed debugging

**📖 Complete reference:** [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)

---

## Documentation Maintenance

Three living documents need periodic refresh during active development. Each has a dedicated Claude skill that encapsulates the regeneration recipe so the work doesn't need to be re-derived from scratch each time.

### 1. Onboarding Page (public — GitHub Pages)

**Live URL:** [https://marcus-waldman.github.io/Kidsights-Data-Platform/](https://marcus-waldman.github.io/Kidsights-Data-Platform/)

| Item | Detail |
|---|---|
| **Source file** | `docs/index.html` (committed; tracked despite the `*.html` ignore via a `!docs/index.html` exception) |
| **Pages config** | Source: `main` branch, `/docs` folder. Jekyll disabled via `docs/.nojekyll`. |
| **Auto-rebuild** | Pages rebuilds automatically on every push to `main` that touches `/docs`. Build time ~20s. |
| **Regeneration recipe** | `/refresh-onboarding` skill at `.claude/skills/refresh-onboarding/SKILL.md` |
| **When to refresh** | When platform state *materially* changes — new pipeline, drift item resolved, major status change. Roughly every 3 months minimum. |

**The page is a snapshot.** Small drift between regenerations is acceptable. The authoritative current-state reference is always **this CLAUDE.md**, not the onboarding page.

### 2. Handoff Doc (internal — repo root)

**Source file:** `HANDOFF.md` (repo root)

| Item | Detail |
|---|---|
| **Purpose** | Synthesis doc for the incoming maintainer covering reading order, current pipeline status, in-flight work, drift items, credentials transfer, first-week plan |
| **Regeneration recipe** | `/refresh-handoff` skill at `.claude/skills/refresh-handoff/SKILL.md` |
| **When to refresh** | More often than the onboarding page. Whenever a material commit lands, a drift item resolves, in-flight work status changes, or roughly weekly during active pre-handoff work. |
| **How to refresh** | Surgical edits via the skill — preserves carefully-crafted prose (Tips, First-Week Plan, Knowledge Areas) while updating volatile fields (snapshot date, drift table, in-flight section, uncommitted-work breadcrumb) |

### 3. Database Table Catalog (internal — repo docs)

**Source file:** [`docs/database/TABLES.md`](docs/database/TABLES.md) (generated) + [`docs/database/table_metadata.yaml`](docs/database/table_metadata.yaml) (hand-written source of truth)

| Item | Detail |
|---|---|
| **Purpose** | Authoritative catalog of all ~97 DuckDB tables grouped by pipeline (ne25, ne25_imputed, nsch, nhis, acs, calibration, raking, crosswalks, metadata, cleanup). For each table: row count, column count, source script, primary downstream consumer, status. |
| **Architecture** | Hybrid regeneration — live DB introspection (`scripts/documentation/inventory_tables.py`) merged with hand-written YAML metadata. Assembled by `scripts/documentation/generate_tables_md.py`, which exits non-zero on orphan / stale drift. |
| **Regeneration recipe** | `/refresh-database-inventory` skill at `.claude/skills/refresh-database-inventory/SKILL.md` |
| **When to refresh** | When a table is added, dropped, renamed, or moves between pipelines; when row counts drift materially; when a cleanup-candidate table is finally removed. Weekly-ish during active development. |
| **How to refresh** | Edit `table_metadata.yaml` → run the skill → commit both files together. Never hand-edit `TABLES.md` — it is overwritten on regeneration. |

### Cadence guidance

- **HANDOFF.md** changes often during the pre-handoff window — refresh weekly or after each material commit
- **onboarding.html** changes rarely — only when a public-visible thing actually changed
- **TABLES.md** changes with schema evolution — any table add/drop/rename, plus periodic sweeps to keep metadata and status values accurate
- They are **decoupled by design**: a Bucket 3 progress update belongs in HANDOFF.md but doesn't necessarily warrant a public-facing snapshot refresh; a new cleanup candidate belongs in TABLES.md but doesn't necessarily warrant an onboarding refresh
- All three skills require explicit user authorization before pushing to remote

---

## Documentation Directory

### Architecture & Pipeline Guides
- **[PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 8 pipelines, design rationales, ACS metadata system
- **[PIPELINE_STEPS.md](docs/architecture/PIPELINE_STEPS.md)** - Step-by-step execution instructions, timing expectations, troubleshooting
- **[DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md)** - Complete directory structure for all pipelines, data storage locations

### Coding & Development Guides
- **[CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)** - R namespacing, Windows console output, file naming, R execution patterns
- **[PYTHON_UTILITIES.md](docs/guides/PYTHON_UTILITIES.md)** - R Executor, DatabaseManager, data refresh strategy
- **[MISSING_DATA_GUIDE.md](docs/guides/MISSING_DATA_GUIDE.md)** - Critical missing data handling, composite variables inventory, validation checklist

### Data & Variable Guides
- **[DERIVED_VARIABLES_SYSTEM.md](docs/guides/DERIVED_VARIABLES_SYSTEM.md)** - 99 derived variables breakdown, transformation pipeline, adding new variables
- **[GEOGRAPHIC_CROSSWALKS.md](docs/guides/GEOGRAPHIC_CROSSWALKS.md)** - 10 crosswalk tables, database-backed reference, querying from Python/R

### Quick Reference
- **[QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - Command cheatsheet for all pipelines, utility scripts, common tasks, debugging tips

### Codebook System
- **[codebook/README.md](docs/codebook/README.md)** - JSON-based metadata system, IRT parameters, utility functions, dashboard

### Pipeline-Specific Documentation
- **MN26 Pipeline:** [docs/mn26/pipeline_guide.qmd](docs/mn26/pipeline_guide.qmd) - Single Quarto guide (render to HTML): Quick Start, data flow diagram, variable recoding reference, eligibility logic, scoring, troubleshooting
- **ACS Pipeline:** [docs/acs/](docs/acs/) - IPUMS variables reference, pipeline usage, testing guide, cache management
- **NHIS Pipeline:** [docs/nhis/](docs/nhis/) - NHIS variables reference, pipeline usage, testing guide, transformation mappings
- **NSCH Pipeline:** [docs/nsch/](docs/nsch/) - Database schema, example queries, troubleshooting, variables reference
- **Raking Targets:** [docs/raking/](docs/raking/) - Raking targets pipeline, statistical methods, implementation plan
- **NE25 Weight Construction:** [docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd](docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) - Narrative: method, rationale, and roadmap (render to HTML with `quarto render`)
- **Imputation Pipeline:** [docs/imputation/](docs/imputation/) - Multiple imputation architecture, helper functions, usage examples
- **IRT Calibration:** [docs/irt_scoring/](docs/irt_scoring/) - Calibration pipeline, Mplus workflow, constraint specification, quality assurance tools

---

## Environment Setup

### Required Software Paths
- **R:** `C:/Program Files/R/R-4.5.1/bin`
- **Quarto:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe`
- **Pandoc:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools/pandoc.exe`

### Python Packages
```bash
# Core packages (NE25 pipeline)
pip install duckdb pandas pyyaml structlog python-dotenv

# ACS/NHIS pipeline packages
pip install ipumspy requests

# NSCH pipeline packages
pip install pyreadstat
```

### API Keys Configuration
**Configure via `.env` file** (see [Environment Configuration](#environment-configuration) above)

- **REDCap:** Set `REDCAP_API_CREDENTIALS_PATH` in `.env`
- **IPUMS:** Set `IPUMS_API_KEY_PATH` in `.env` (shared by ACS and NHIS)
- **Security:** Never commit `.env` file (already gitignored)

### Data Storage
- **Local DuckDB:** `data/duckdb/kidsights_local.duckdb`
- **NE25 Temp Feather:** `tempdir()/ne25_pipeline/*.feather`
- **ACS Raw Data:** `data/acs/{state}/{year_range}/raw.feather`
- **NHIS Raw Data:** `data/nhis/{year_range}/raw.feather`
- **NSCH Raw Data:** `data/nsch/{year}/raw.feather`

---

## Current Status (April 2026)

### ✅ NE25 Pipeline - Production Ready (December 2025)
- **Reliability:** 100% success rate (eliminated segmentation faults)
- **Data:** 4,966 records from 4 REDCap projects, 2,645 with calibrated raking weights
- **Derived Variables:** 99 variables created by recode_it()
- **Influential Observations:** MANUAL workflow (Step 6.5 joins influence diagnostics from database if available)
  - Diagnostics stored in `ne25_flagged_observations` table (must be created manually via Cook's Distance analysis)
  - See `scripts/influence_diagnostics/README.md` for influence diagnostics workflow
  - Pipeline creates `influential` column (TRUE if observation manually identified as high-leverage)
  - Pipeline creates `overall_influence_cutoff` column (influence score threshold used for flagging)
- **Storage:** Local DuckDB with ~60 `ne25_*` tables (raw, transformed, scoring outputs, imputations, weights); 97 total tables in DB
- **GSED Person-Fit Scores (Step 6.7):** Joins manually calibrated person-fit scores from 2023 scale
  - 7 domain scores: General GSED, Feeding, Externalizing, Internalizing, Sleeping, Social Competency, Overall Kidsights
  - Created via fixed item calibration in Mplus (171 fixed + 53 free items)
  - Scores stored in `ne25_kidsights_gsed_pf_scores_2022_scale` table (2,785 records)
  - Conditional standard errors (`_csem`) included for all domains
  - Also joins `ne25_too_few_items` exclusion flags (718 records)
  - See `calibration/ne25/manual_2023_scale/` for workflow
- **Calibrated Raking Weights (Step 6.9):** KL divergence minimization for population-representative sampling
  - **Integration:** Automatic join from `ne25_calibrated_weights_m1.feather` if available
  - **Sample Size:** 2,645 in-state Nebraska records with weights (100% of eligible participants)
  - **Weight Quality:** Effective N (Kish) = 1,518.9 (57.4% efficiency), weight ratio (max/min) = 33.55
  - **Correlation Matching:** 71.9% improvement in correlation RMSE (unweighted to weighted)
  - **Method:** Stan optimization minimizes masked factorized covariance structure
  - **Calibration Variables:** 24 variables (7 demographics + 14 PUMA geography + 2 mental health + 1 child outcome)
  - **Scale Standardization:** Z-score normalization within Stan for numerical stability
  - **Target Moments:** Pooled across ACS (25%), NHIS (17%), NSCH (58%) with effective sample sizes per block
  - **Database Column:** `calibrated_weight` in `ne25_transformed` table
  - **Execution:** Scripts 25-33 in raking pipeline (~10 minutes total)
  - **Documentation:** See [Raking Integration Guide](docs/raking/RAKING_INTEGRATION.md) for operator detail and [Weight Construction narrative](docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) for method/rationale/roadmap
- **Out-of-State Handling (Step 6.10):** Bandaid fix for records with no PUMA match
  - **Problem:** 140 records from out-of-state zipcodes (no match in ZCTA→PUMA crosswalk)
  - **Solution:** Marked as `out_of_state = TRUE` and excluded with `meets_inclusion = FALSE`
  - **Audit Trail:** Maintains visibility of excluded records and reason (geographic invalidity)
  - **Verification:** 2,645 records with meets_inclusion=TRUE match exactly with 2,645 records with weights
- **CREDI Developmental Scoring (Step 7.5):** Automated CREDI scoring for children under 4 years old
  - **Eligibility:** Children with years_old < 4 AND meets_inclusion = TRUE
  - **Eligible Sample:** 1,678 children
  - **Scored Sample:** 884 children (52.7% with sufficient item responses)
  - **Items Mapped:** 60 CREDI Long Form (LF) items from codebook.json
  - **Output Scores (15 columns):** 5 domain scores (COG, LANG, MOT, SEM, OVERALL) + 5 Z-scores + 5 standard errors
  - **Database Table:** `ne25_credi_scores` with pid, record_id, and 15 score columns
  - **Execution Time:** ~3 seconds
  - **Implementation:** R/credi/score_credi.R with graceful error handling
  - **Documentation:** See [CREDI Integration Guide](docs/CREDI_SCORING.md)
- **GSED D-score Calculation (Step 7.6):** Automated GSED D-score calculation for all eligible children (December 2025)
  - **Eligibility:** Children with meets_inclusion = TRUE (all ages)
  - **Eligible Sample:** 2,645 children
  - **Scored Sample:** 2,639 children (99.8% with sufficient item responses)
  - **Items Mapped:** 132 GSED items from codebook.json (via gsed lexicon)
  - **Output Scores (6 columns):** D-score (d), Development-for-Age Z-score (daz), standard error (sem), age in years (a), number of items (n), proportion passed (p)
  - **Database Table:** `ne25_dscore_scores` with pid, record_id, and 6 score columns
  - **Execution Time:** ~1.5 seconds
  - **Key Parameters:** key="gsed2406" (most recent GSED 2024 key), xname="age_in_days", xunit="days"
  - **Implementation:** R/dscore/score_dscore.R with automatic codebook parsing and database indexing
  - **D-score Scale:** Linear scale (range: [12.25, 87.14] for NE25, typically 0-100 range)
  - **DAZ Interpretation:** Age-adjusted Z-score relative to reference population (mean=0.41, SD=1.39 for NE25)
  - **Quality Metrics:** Mean items used per child: 11.4, Mean SEM: 3.47 (measurement precision)

### ✅ ACS Pipeline - Complete
- **API Integration:** Direct IPUMS USA API extraction via ipumspy
- **Metadata System:** 3 DuckDB tables with DDI metadata for transformations
- **Smart Caching:** 90+ day retention with checksum validation
- **Status:** Standalone utility, integrated with raking targets pipeline

### ✅ NHIS Pipeline - Production Ready
- **Multi-Year Data:** 6 annual samples (2019-2024), 66 variables, 229,609 records
- **Smart Caching:** SHA256-based caching (years + samples + variables signature)
- **Mental Health:** GAD-7 anxiety and PHQ-8 depression (2019, 2022 only)
- **ACEs Coverage:** 8 ACE variables with direct overlap to NE25

### ✅ NSCH Pipeline - Production Ready
- **Multi-Year Data:** 7 years loaded (2017-2023), 284,496 records, 3,780 unique variables
- **Automated Pipeline:** SPSS → Feather → R validation → Database in single command
- **Performance:** Single year in 20 seconds, batch (7 years) in 2 minutes
- **Metadata System:** Auto-generated variable reference, 36,164 value label mappings

### ✅ Raking Targets Pipeline - Complete (October 2025)
- **Population Targets:** `raking_targets_ne25` table (11 rows as of 2026-04-21). Older design docs describe 180 targets (30 estimands × 6 age groups); the 11-row state reflects the current consolidated/normalized target representation consumed by the NE25 calibration pipeline.
- **Data Sources:** ACS (25 estimands), NHIS (1 estimand), NSCH (4 estimands)
- **Database Integration:** `raking_targets_ne25` table with 4 indexes for efficient querying
- **Execution:** Streamlined pipeline (~2-3 minutes), automated verification
- **Bootstrap Variance:** 614,400 bootstrap replicates for ACS estimands (4096 replicates × 150 targets)
- **Method:** Rao-Wu-Yue-Beaumont bootstrap with shared design across all 25 ACS estimands
- **Execution Time:** ~15-20 minutes (4096 replicates, 16 parallel workers)

### ✅ NE25 Bayesian-Bootstrap Replicate Weights - Complete (April 2026)
- **Framework:** MI + sample-only Bayesian bootstrap (Rubin 1981). Targets treated as fixed; sample variability captured via per-obs `bbw ~ Exp(1)` data-weight draws.
- **Pattern:** Follows `Kidsights-Disparities-NE22/utils.R::make_design_weights` — `bbw` enters the masked factorized moment loss (not the prior), so the flat `Dirichlet(1,…,1)` prior contributes zero gradient.
- **Scale:** 5 imputations × 200 bootstrap draws = **1,000 Stan refits**, all `stan_ok = TRUE`.
- **Storage:** `ne25_raked_weights_boot` DuckDB table (long format, PK = (pid, record_id, imputation_m, boot_b)), 2,645,000 rows.
- **Resumability:** per-(m, b) feathers under `data/raking/ne25/ne25_weights_boot/` (`weights_m{m}_b{b}.feather`).
- **Compute:** ~3 h wall-clock on 8 `future::multisession` workers with Stan pre-compiled in the parent session.
- **Stability:** Kish-N CV across bootstrap draws per imputation = 0.009–0.010. Baseline reproducibility (`bbw = rep(1, N)` vs Bucket 2) within ~3e-2 RMS (autodiff noise).
- **Known concern:** weight ratios extreme (median ~70K, max ~474M) due to wide `[0.01, 100]` bounds. NE22 uses tighter `[0.1, 10]`. Revisit if downstream variance estimates look unstable.
- **Downstream:** Rubin's-rules pooling over `(imputation_m, boot_b)` pairs — `reports/ne25/helpers/model_fitting.R` consumes the point-estimate column only; MI-aware variance integration is a separate ticket.
- **Documentation:** [Bayesian Bootstrap Weights §](docs/raking/RAKING_INTEGRATION.md#bayesian-bootstrap-replicate-weights-bucket-3-shipped-april-2026) and [WEIGHT_CONSTRUCTION.qmd §5.4](docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd).

### ✅ Imputation Pipeline - Production Ready (December 2025)
- **Multi-Study Architecture:** Independent studies (ne25, ia26, co27) with shared codebase
- **Multiple Imputations:** M=5 imputations (easily scalable to M=20+)
- **Inclusion Criteria:** Uses `meets_inclusion` filter (eligible=TRUE & influential=FALSE & too_few_item_responses=FALSE) - **2,785 participants** for ne25
- **Geographic Variables:** 3 variables via probabilistic allocation (PUMA, County, Census Tract)
- **Sociodemographic Variables:** 6 variables via MICE (female, raceG, educ_mom, educ_a2, income, family_size)
- **Childcare Variables:** 4 variables via 3-stage sequential imputation (cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily)
- **Mental Health & Parenting:** 7 variables via CART imputation (phq2_interest, phq2_depressed, gad2_nervous, gad2_worry, q1502, phq2_positive, gad2_positive)
- **Child ACEs:** 9 variables via random forest imputation (8 ACE items + child_ace_total)
- **Storage Pattern:** Study-specific variable tables (`ne25_imputed_{variable}`) with **storage convention:** only imputed/derived values stored (observed values remain in base table)
- **Total Variables:** 29 imputed variables (3 geo + 6 sociodem + 4 childcare + 7 mental health + 9 ACEs)
- **Database Tables:** 34 `ne25_imputed_*` tables in current DB (verified 2026-04-20; includes 4 likely-defunct double-prefixed tables `ne25_imputed_imputed_cc_*` with 0 rows)
- **Execution Time:** 195.2 seconds (3.3 minutes) for complete 11-stage pipeline
- **Recent Updates (December 2025):**
  - Removed `authentic` column references (replaced by `authenticity_weight` in NE25 pipeline)
  - Updated inclusion criteria to triple-criterion filter: eligible=TRUE & influential=FALSE & too_few_items=FALSE
  - Verified all 11 stages execute successfully with proper database insertions
  - Child ACEs stage validated: 2,585 total rows across 9 ACE tables with binary/valid range checks passing

### ✅ MN26 Pipeline - Scoring Complete (April 2026)
- **📖 Full Guide:** [`docs/mn26/pipeline_guide.qmd`](docs/mn26/pipeline_guide.qmd) — authoritative documentation for code reviewers (Quick Start, data flow diagram, variable recoding reference, eligibility logic, scoring, troubleshooting)
- **Status:** Core pipeline + Kidsights + CREDI + GSED D-score + HRTL all shipped (2026-04-27, commits `60c056d`, `942541b`, `fcb78e8`). Raking and imputation remain deferred (need MN ACS extraction first).
- **Study:** Minnesota 2026 (NORC-administered REDCap survey)
- **Multi-Child:** Up to 2 children per household, wide-to-long pivot (pid + record_id + child_num)
- **Reconciliation Audit:** Three-way dictionary comparison (NE25 vs MN26 active vs MN26 full)
  - 331 identical fields, 128 hidden-identical (@HIDDEN but still in data)
  - 341 new child 2 fields, 3 renames, 2 structural (race checkbox reorganization), 3 recoded (sliders)
  - Sex codes (cqr009) confirmed IDENTICAL — earlier "swap" claims were incorrect
  - Education codes (cqr004) confirmed IDENTICAL (both 0-8)
- **Key Variable Changes:** cqr002→mn2 (parent gender), age_in_days→age_in_days_n, eqstate→mn_eqstate, cqr010→cqr010b (race 15→6 categories), sq002→sq002b
- **Analytic Sample (NORC-aligned, replaces simple 4-criterion rule):** Mirrors `kidsights-norc/origin/norc_shared : progress-monitoring/mn26/utils/norc_summarise.R`. Sample-defining work happens **pre-pivot** in `R/harmonize/mn26_norc_sample.R`:
  - `apply_norc_replace_records()` — dedup returning users via `id_xwalk.rds` (P_SUID); reissue PID 8792 supersedes earlier records
  - `apply_norc_sample()` — `filter(!smoke_case | !in_scope)`; retains out-of-scope cases so the sample-frame denominator is preserved
  - `norc_elig_screen()` — 4-scenario eligibility (`elig_type` ∈ {"1","2","3a","3b"}); age cap 2191 days; uses `kids_u6_n`, `mn_birth_c1_n/c2_n`, `parent_guardian_c1_n/c2_n`, `dob_n/c2_n`, `consent_date_n`, `eligibility_form_norc_complete`
  - Pivot derives per-child `eligible` from HH flags: child_num=1 → `solo_kid_elig | youngest_kid_elig`; child_num=2 → `oldest_kid_elig`
  - `compute_mn26_survey_completion()` (post-pivot, NORC-aligned) sets `last_module_complete` from `*_complete` flags + `survey_complete = eligible & last_module_complete %in% {Follow-up, Compensation}`
  - `meets_inclusion = eligible & survey_complete` — matches NORC `summary_rates` "# HHs completing the survey"
- **Required input:** `data/mn26/id_xwalk.rds` (NORC P_SUID crosswalk; ~10,331 rows × 6 cols; no PII so committed in-repo via `.gitignore` whitelist). Path is set in `config/sources/mn26.yaml::analytic_sample.id_xwalk_path`; override with `--id-xwalk` on `run_mn26_pipeline.R` for ad-hoc testing.
- **Pipeline Steps:** Extract → **NORC sample (2.5: replace_records / sample / elig_screen)** → Pivot (per-child eligible) → Store raw → **HRTL Motor `_end` coalesce (4.5)** → Transform → Eligibility validation → **Survey completion (6.5)** → Inclusion filter → Kidsights scoring → **CREDI scoring (8.5)** → **GSED D-score (8.6)** → **HRTL scoring (8.7)** → Store transformed → Dictionary
- **Kidsights Scoring (Step 8):** Automated via `KidsightsPublic` R package (CmdStan MAP with fixed item parameters); 220 developmental items, 1,158 scored. Psychosocial scoring NOT included (NE25-specific items). Graceful failure: pipeline continues with NA scores if CmdStan unavailable.
- **CREDI Scoring (Step 8.5):** `R/credi/score_credi.R` parameterized via `study_id="mn26"`. 60 CREDI LF items, 411 children scored (under-4 cohort). Output: `mn26_credi_scores` (895 rows × 18 cols).
- **GSED D-score (Step 8.6):** `R/dscore/score_dscore.R` parameterized via `study_id="mn26"` and `key="gsed2406"`. 132 GSED items, 1,161 scored. Output: `mn26_dscore_scores` (1,296 rows × 9 cols). Bridges NORC's `age_in_days_n` to the cross-study `age_in_days` column expected by the scorer.
- **HRTL Scoring (Step 8.7):** `R/hrtl/score_hrtl.R` (function-based replacement for the four-script NE25 pipeline). 4 of 5 domains scored (Health domain skipped due to mirt Rasch convergence failure on the 3-item × 67%-missing config). 555 children classified. Auto Motor coverage gate (default 0.50) — MN26 Motor coverage 99.4% triggers SCORED (vs NE25's 25% triggering MASKED). Output: `mn26_hrtl_domain_scores` (2,198 rows) + `mn26_hrtl_overall` (555 rows; 49% HRTL=TRUE).
- **HRTL Motor `_end` Coalesce (Step 4.5):** Pre-`recode_it()` step that folds NORC's `_end`-suffixed Motor catch-up fields (`nom029x_end`, `nom033x_end`, `nom034x_end`) into the canonical column names. NORC added these fields to `module_6_1097_2191` (3–6 yr KMT form) to fix NE25's age-routing gap. Without the coalesce, MN26 would inherit NE25's Motor blind spot.
- **Execution Time:** ~2.6 seconds (full production pipeline including DB writes). Skip-database test mode: ~1.3 seconds.
- **Entry Point:** `run_mn26_pipeline.R` (supports `--skip-database`, `--credentials` flags)
- **Config:** `config/sources/mn26.yaml` (fully populated)
- **Plan:** `todo/mn26_pipeline_plan.md`
- **Audit Scripts:** `scripts/mn26/reconciliation_audit.R`, `scripts/mn26/audit_codebook_lexicons.R` (verifies CREDI/GSED items have MN26 lexicons)
- **Deferred:** Raking targets (needs MN ACS), imputation, SES analytic dataset, HRTL Health domain (mirt fit failure), 3 transform stages (`geographic`, `caregiver relationship`, `education`) producing ~25 unpopulated derived columns — surfaced by first successful live `--skip-database` run (2026-05-11); see [docs/mn26/pipeline_guide.qmd §Known Limitations](docs/mn26/pipeline_guide.qmd#sec-known-limitations)
- **Shared Utils Extracted:** `R/utils/{recode_utils,cpi_utils,poverty_utils}.R` (used by both NE25 and MN26)
- **CRITICAL:** All MN26 joins use `pid + record_id + child_num` (not just `pid + record_id`) for multi-child correctness

### 🚧 IRT Calibration Pipeline - In Development (November 2025)
- **Multi-Study Dataset:** 9,319 records across 6 studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24). The QA-filtering applied in 2025 dropped the pre-filter count (~47,084) to the current 9,319 calibration-eligible records.
- **Item Coverage:** 416 developmental/behavioral items with lexicon-based harmonization
- **NSCH Integration:** National benchmarking samples (1,000 per year, ages 0-6)
- **Historical Data:** 41,577 records from KidsightsPublic package (NE20, NE22, USA24)
- **Mplus Compatibility:** Space-delimited .dat format, 38.71 MB output file
- **Performance:** 28 seconds execution time
- **Database Tables:**
  - `calibration_dataset_2020_2025` (wide format): 312 columns, 9,319 records (verified 2026-04-20)
  - `calibration_dataset_long` (long format): 9 columns (id, years, study, studynum, lex_equate, y, cooksd_quantile, maskflag, devflag), 1,332,042 rows (verified 2026-04-20)
  - Long format benefits: Full NSCH data (787K holdout rows), devflag/maskflag QA system, storage efficiency (~20 MB vs 290+ MB)
- **Weighted Estimation:** wgt column (1.0 for all studies, authenticity_weight 0.42-1.96 for NE25 inauthentic responses)
- **Output:** `mplus/calibdat.dat` ready for weighted graded response model IRT calibration
- **QA Masking System:**
  - `devflag`: 0=holdout (NSCH), 1=development (used for calibration)
  - `maskflag`: 0=original data, 1=QA-cleaned (excluded observations from NE25 issues or Cook's D influence)
  - Age Gradient Explorer uses maskflag to toggle between original and cleaned data views
- **MODEL Syntax Generation:** Automated Mplus syntax generation from codebook constraints
  - 5 constraint types: complete equality, slope-only, threshold ordering, simplex, 1-PL/Rasch
  - Outputs: Excel review file (MODEL, CONSTRAINT, PRIOR sheets) + optional complete .inp file
  - Migration complete from Update-KidsightsPublic (write_syntax2 function)
  - ~5-10 seconds generation time, eliminates 30-60 min manual .inp creation
- **Recent Bug Fixes (November 2025):**
  - **Issue #6 - NSCH Missing Code Contamination:** Fixed NSCH 2021/2022 helper functions to recode values >= 90 to NA before reverse/forward coding (prevents invalid threshold counts like DD201 showing 5 thresholds instead of 1). Commits: 20e3cf5, 25d2b47
  - **Issue #6 - Study Field Assignment:** Added study field creation in `prepare_calibration_dataset.R` to ensure NSCH records properly labeled with study source (fixes `study = NA` issue). Commit: d72afaa
  - **Issue #6 - Syntax Generator Indexing:** Fixed `write_syntax2.R` to use category lookup instead of positional indexing (prevents incorrect threshold counts like EG16c showing 4 thresholds for dichotomous data). Commit: 37d2034
  - **Issue #8 - NSCH Negative Age Correlations (RESOLVED):** Fixed study-specific reverse coding for 14 NSCH items by adding `cahmi22: true` to `codebook.json`. Reduced NSCH negative correlations from 15 to 4 items (73% reduction). Systematic strong negatives (r ≈ -0.82) completely eliminated. Remaining 4 items show weak correlations (r = -0.03 to -0.21) likely due to NSCH age-routing design.
- **Development Status:** Pipeline ready for production use - NSCH harmonization validated, data quality verified
- **QA Cleanup Documentation:** See [docs/irt_scoring/calibration_qa_cleanup_summary.md](docs/irt_scoring/calibration_qa_cleanup_summary.md) for detailed documentation of bug fixes, data cleaning workflow, long format dataset, and masking system
- **Quality Assurance Tools:** Age-Response Gradient Explorer Shiny app (production-ready, REQUIRED)
  - Mandatory pre-calibration visual inspection of 308 developmental items
  - Box plots + GAM smoothing across 6 calibration studies
  - Quality flag integration (negative correlations, category mismatches)
  - Launch: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
  - Documentation: [scripts/shiny/age_gradient_explorer/README.md](scripts/shiny/age_gradient_explorer/README.md)

### ✅ Manual 2023 Scale Calibration - Complete (December 2025)
- **Purpose:** Fixed item calibration to maintain continuity with 2023 GSED scale
- **Method:** Mplus graded response model with 171 fixed parameters from 2023 mirt + 53 new free items
- **Calibration Dataset:** 2,785 NE25 participants (after influential observation exclusions)
- **Person-Fit Scores Generated:**
  - Overall: `kidsights_2022`, `kidsights_2022_csem`
  - General GSED: `general_gsed_pf_2022`, `general_gsed_pf_2022_csem`
  - Feeding: `feeding_gsed_pf_2022`, `feeding_gsed_pf_2022_csem`
  - Externalizing: `externalizing_gsed_pf_2022`, `externalizing_gsed_pf_2022_csem`
  - Internalizing: `internalizing_gsed_pf_2022`, `internalizing_gsed_pf_2022_csem`
  - Sleeping: `sleeping_gsed_pf_2022`, `sleeping_gsed_pf_2022_csem`
  - Social Competency: `social_competency_gsed_pf_2022`, `social_competency_gsed_pf_2022_csem`
- **Database Tables:**
  - `ne25_kidsights_gsed_pf_scores_2022_scale` - Person-fit scores (2,785 records with scores)
  - `ne25_too_few_items` - Exclusion flags for insufficient item responses (718 records)
- **Pipeline Integration:** Automatically joined in NE25 pipeline Step 6.7 (if tables exist)
- **Workflow Location:** `calibration/ne25/manual_2023_scale/`
- **Orchestrator Script:** `run_manual_calibration.R`
- **Execution:** Manual workflow (run separately before NE25 pipeline)
- **Documentation:** See [Manual 2023 Scale Calibration](docs/irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md)

### ✅ HRTL Scoring - Production Ready (December 2025)
- **Status:** **PRODUCTION READY** - Full pipeline integrated into NE25 as Step 7.7 (December 2025)
- **Framework:** Healthy & Ready to Learn (HRTL) for ages 3-5 school readiness assessment
- **Pipeline:** Extract domain data → Fit Rasch models → Impute missing values → Score with CAHMI thresholds
- **Eligibility:** Children with `3 ≤ years_old < 6` AND `meets_inclusion = TRUE` (1,412 eligible)
- **Domains:** 4 domains scored, 1 masked (28 items total)
  - Early Learning Skills (9 items): 1,005/1,413 on-track (71.1%)
  - Health (3 items + derived): 1,266/1,425 on-track (88.8%)
  - Self-Regulation (5 items): 933/1,411 on-track (66.1%)
  - Social-Emotional Development (6 items): 1,222/1,425 on-track (85.8%)
  - Motor Development (4 items): **MASKED** - 93% missing (Issue #15)
- **Scoring Algorithm:**
  1. Rasch IRT model: 1PL graded response model with equal slopes per domain
  2. EAP theta estimation for each child
  3. Bayesian imputation: `mirt::imputeMissing(model, Theta=theta_eap)` fills 0% missing
  4. Item-level CAHMI thresholds applied (age-specific: 3, 4, 5 years)
  5. Response coding: 1=Needs Support, 2=Emerging, 3=On-Track
  6. Domain average & classification: ≥2.5=On-Track, ≥1.5=Emerging, <1.5=Needs Support
- **DailyAct_22 Derivation:** Computed from cqr014x (HCABILITY) + nom044 (HCEXTENT) for Health domain
- **Data Quality Masking (Issue #15):**
  - Motor Development: All classification values masked to NA (age-routed items DrawFace/DrawPerson/BounceBall = 93% missing)
  - Overall HRTL: Marked as NA (incomplete without Motor domain)
  - Masking applied in pipeline with explicit GitHub issue reference
- **Database Tables:**
  - `ne25_hrtl_domain_scores` (7,086 records: 5 domains × ~1,411-1,425 records each, with Motor classification masked to NA)
  - `ne25_hrtl_overall` (1,412 records: hrtl=NA for all due to Motor exclusion)
- **Execution Time:** ~13.4 seconds (extraction + Rasch fitting + imputation + scoring)
- **Pipeline Location:** Step 7.7 (4 sub-steps) in `pipelines/orchestration/ne25_pipeline.R`
- **Scripts:**
  - `scripts/hrtl/01_extract_domain_datasets.R` - Domain data extraction + DailyAct_22 derivation
  - `scripts/hrtl/02_fit_rasch_models.R` - Rasch 1PL graded models (5 domains)
  - `scripts/hrtl/03_impute_missing_values.R` - Bayesian imputation via EAP scores
  - `scripts/hrtl/04_score_hrtl.R` - CAHMI threshold scoring & domain classification
  - `R/hrtl/score_hrtl_itemlevel.R` - Legacy production wrapper (not used - validation issues)
- **Validation:** `scripts/hrtl/validate_hrtl_results.R` - Verifies domain percentages within tolerance

### Architecture Highlights
- **Hybrid R-Python Design:** R for transformations, Python for database operations
- **Feather Format:** 3x faster R/Python data exchange, perfect type preservation
- **Independent Pipelines:** NE25 (local survey) + MN26 (multi-child survey) + ACS (census) + NHIS (national health) + NSCH (child health) + Raking Targets (weighting) + Imputation (uncertainty) + IRT Calibration (psychometrics)
- **Statistical Integration:** Raking targets + Multiple imputation ready for post-stratification weighting + IRT scoring

**📖 Complete status and architecture:** [PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)

---

**For detailed information on any topic, see the [Documentation Directory](#documentation-directory) above.**

*Updated: April 2026 | Version: 3.8.0*
- pid does not uniquely identify an individual in the nebraska 2025 (ne25) data. It is the pid + record_id combination.

---

## Verification Summary

**Last fact-check:** 2026-04-20 (Bucket C Tier 1 of doc audit prior to repo handoff)

### Scope
~30 quantitative claims + ~25 file path / function reference claims + internal consistency checks.

### Confirmed (sample)
- All 11 referenced run scripts exist (`run_ne25_pipeline.R`, `run_mn26_pipeline.R`, `scripts/raking/ne25/run_*.R`, `scripts/irt_scoring/run_calibration_pipeline.R`, etc.)
- All scoring R files exist (`R/credi/score_credi.R`, `R/dscore/score_dscore.R`, `R/hrtl/score_*.R`)
- All `R/utils/*.R` helpers exist (`safe_joins`, `environment_config`, `recode_utils`, `cpi_utils`, `poverty_utils`)
- 4 distinct REDCap project pids in `ne25_raw` ✓
- 2,645 records have non-null `calibrated_weight` ✓ (matches `meets_inclusion = TRUE`)
- 140 records flagged `out_of_state = TRUE` ✓
- 718 records in `ne25_too_few_items` ✓
- 1,412 records in `ne25_hrtl_overall` ✓
- 884 CREDI-scored children ✓ (non-null COG out of 1,678 eligible)
- All Bucket A/B archive moves preserved file history (`git mv`)

### Corrections applied (15 edits)
1. Section header date: "October 2025" → "April 2026"
2. `ne25_raw` count: 3,908 → 4,966
3. Storage claim "11 tables, 7,812 records" → "~60 `ne25_*` tables; 97 total"
4. GSED person-fit scores table size: 2,831 → 2,785 (two locations)
5. `db.execute_query(...)` API example → corrected to `with db.get_connection() as con:` context manager (the documented method does not exist)
6. `raking_targets_ne25` rows: flagged "180 (design)" vs **11 (actual)** — see drift item below
7. Imputation tables: 32 → 34 (with note about 4 defunct double-prefixed tables)
8. IRT calibration `calibration_dataset_2020_2025`: 47,084/303 → **9,319/312** (with maintainer-verify flag)
9. IRT calibration `calibration_dataset_long`: 1,316,391 → 1,332,042 rows
10. `NE25 Calibration Table` section: flagged as documented but absent from DB (`ne25_calibration` does not exist)
11. PIPELINE_OVERVIEW link description: "6 pipelines" → "8 pipelines"
12. Architecture summary (line near end): added missing **MN26** to pipeline list
13. HRTL `ne25_hrtl_domain_scores`: 5,652 → 7,086 (all 5 domains stored uniformly, not 4+1)

### Drift items from the 2026-04-20 audit — status as of 2026-04-21

**Status update (2026-04-21, Marcus):** items 1-5 below were reviewed and closed — the DB represents current intent and the documented numbers/tables/columns were stale design text or pre-QA artifacts. Related ⚠️ warnings have been removed from the pipeline status sections. The cleanup-candidates row remains open as a janitorial item.

| Item | Documented | Actual | Status |
|---|---|---|---|
| `raking_targets_ne25` rows | 180 | 11 | Closed 2026-04-21 (11 is current state; 180 was legacy design text) |
| `calibration_dataset_2020_2025` records | 47,084 | 9,319 | Closed 2026-04-21 (9,319 is the post-QA count) |
| `ne25_calibration` table | exists (Step 11) | does not exist | Closed 2026-04-21 (consolidated into `calibration_dataset_*` family) |
| `overall_influence_cutoff` column in `ne25_transformed` | exists | missing | Closed 2026-04-21 (removed in a refactor; not part of current schema) |
| `authenticity_weight` column in `ne25_transformed` | exists per "Recent Updates" note | missing | Closed 2026-04-21 (lives in calibration dataset, not ne25_transformed) |
| Cleanup candidates: `ne25_*_test`, `ne25_transformed_backup_2025_11_08`, `ne25_imputed_imputed_cc_*` (4 zero-row), `ne25_irt_scores_*` (2 zero-row), `ne25_raw_pid*` (4 zero-row), `ne25_eligibility` (0-row) | n/a | 12 zero/test/backup tables in DB | Open — janitorial cleanup |

### Unverified claims (require pipeline rerun or deep-dive)
- "99 derived variables created by recode_it()" — function exists; couldn't be invoked from a one-shot script
- `ne25_dscore_scores` "2,639 scored" (99.8% of 2,645) — table has full 2,645 eligible; non-null score count not verified
- Statistical metrics: "Effective N (Kish) = 1,518.9", "57.4% efficiency", "weight ratio = 33.55", "71.9% RMSE improvement"
- Execution times (e.g., "~17-20 min", "195.2 seconds", "~13.4 seconds")
- "1,000 NSCH per year" sample, "41,577 historical KidsightsPublic records"
- HRTL on-track percentages by domain (1,005/1,413 etc.)
- `mplus/calibdat.dat` file size "38.71 MB"
