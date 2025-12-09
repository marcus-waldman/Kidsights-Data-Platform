# Kidsights Data Platform - Development Guidelines

**Last Updated:** December 2025 | **Version:** 3.5.0

This is a quick reference guide for AI assistants working with the Kidsights Data Platform. For detailed documentation, see the [Documentation Directory](#documentation-directory) below.

---

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research with **seven independent pipelines**:

1. **NE25 Pipeline** - REDCap survey data processing (Nebraska 2025 study)
2. **ACS Pipeline** - IPUMS USA census data extraction
3. **NHIS Pipeline** - IPUMS Health Surveys data extraction
4. **NSCH Pipeline** - National Survey of Children's Health data integration
5. **Raking Targets Pipeline** - Population-representative targets for post-stratification weighting
6. **Imputation Pipeline** - Multiple imputation for geographic, sociodemographic, childcare, and mental health uncertainty
7. **IRT Calibration Pipeline** - Mplus calibration dataset creation for psychometric scale recalibration

### Running Pipelines

**NE25 Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
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

# Get record count
result = db.execute_query("SELECT COUNT(*) FROM ne25_raw")
print(f"Total records: {result[0][0]}")
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

## Documentation Directory

### Architecture & Pipeline Guides
- **[PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 6 pipelines, design rationales, ACS metadata system
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
- **ACS Pipeline:** [docs/acs/](docs/acs/) - IPUMS variables reference, pipeline usage, testing guide, cache management
- **NHIS Pipeline:** [docs/nhis/](docs/nhis/) - NHIS variables reference, pipeline usage, testing guide, transformation mappings
- **NSCH Pipeline:** [docs/nsch/](docs/nsch/) - Database schema, example queries, troubleshooting, variables reference
- **Raking Targets:** [docs/raking/](docs/raking/) - Raking targets pipeline, statistical methods, implementation plan
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

## Current Status (October 2025)

### ✅ NE25 Pipeline - Production Ready
- **Reliability:** 100% success rate (eliminated segmentation faults)
- **Data:** 3,908 records from 4 REDCap projects
- **Derived Variables:** 99 variables created by recode_it()
- **Influential Observations:** MANUAL workflow (Step 6.5 joins influence diagnostics from database if available)
  - Diagnostics stored in `ne25_flagged_observations` table (must be created manually via Cook's Distance analysis)
  - See `scripts/influence_diagnostics/README.md` for influence diagnostics workflow
  - Pipeline creates `influential` column (TRUE if observation manually identified as high-leverage)
  - Pipeline creates `overall_influence_cutoff` column (influence score threshold used for flagging)
- **Storage:** Local DuckDB with 11 tables, 7,812 records
- **GSED Person-Fit Scores (Step 6.7):** Joins manually calibrated person-fit scores from 2023 scale
  - 7 domain scores: General GSED, Feeding, Externalizing, Internalizing, Sleeping, Social Competency, Overall Kidsights
  - Created via fixed item calibration in Mplus (171 fixed + 53 free items)
  - Scores stored in `ne25_kidsights_gsed_pf_scores_2022_scale` table (2,831 records)
  - Conditional standard errors (`_csem`) included for all domains
  - Also joins `ne25_too_few_items` exclusion flags (718 records)
  - See `calibration/ne25/manual_2023_scale/` for workflow

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
- **Population Targets:** 180 raking targets (30 estimands × 6 age groups)
- **Data Sources:** ACS (25 estimands), NHIS (1 estimand), NSCH (4 estimands)
- **Database Integration:** `raking_targets_ne25` table with 4 indexes for efficient querying
- **Execution:** Streamlined pipeline (~2-3 minutes), automated verification
- **Bootstrap Variance:** 614,400 bootstrap replicates for ACS estimands (4096 replicates × 150 targets)
- **Method:** Rao-Wu-Yue-Beaumont bootstrap with shared design across all 25 ACS estimands
- **Execution Time:** ~15-20 minutes (4096 replicates, 16 parallel workers)

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
- **Database Tables:** 32 imputation tables created with 5 imputations each (M=5)
- **Execution Time:** 195.2 seconds (3.3 minutes) for complete 11-stage pipeline
- **Recent Updates (December 2025):**
  - Removed `authentic` column references (replaced by `authenticity_weight` in NE25 pipeline)
  - Updated inclusion criteria to triple-criterion filter: eligible=TRUE & influential=FALSE & too_few_items=FALSE
  - Verified all 11 stages execute successfully with proper database insertions
  - Child ACEs stage validated: 2,585 total rows across 9 ACE tables with binary/valid range checks passing

### 🚧 IRT Calibration Pipeline - In Development (November 2025)
- **Multi-Study Dataset:** 47,084 records across 6 studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24)
- **Item Coverage:** 416 developmental/behavioral items with lexicon-based harmonization
- **NSCH Integration:** National benchmarking samples (1,000 per year, ages 0-6)
- **Historical Data:** 41,577 records from KidsightsPublic package (NE20, NE22, USA24)
- **Mplus Compatibility:** Space-delimited .dat format, 38.71 MB output file
- **Performance:** 28 seconds execution time
- **Database Tables:**
  - `calibration_dataset_2020_2025` (wide format): 303 columns (id, study, years, wgt + 299 items), 47,084 records
  - `calibration_dataset_long` (long format): 9 columns (id, years, study, studynum, lex_equate, y, cooksd_quantile, maskflag, devflag), 1,316,391 rows
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

### ✅ NE25 Calibration Table - Optimized (November 2025)
- **Automated Creation:** Step 11 in NE25 pipeline (no manual intervention required)
- **Streamlined Schema:** 279 columns (id, years, authenticity_weight + 276 calibration items)
- **Storage Efficiency:** ~0.5 MB (vs 15 MB bloated version, 97% reduction)
- **Inclusion Filter:** `meets_inclusion=TRUE` (2,831 participants)
- **Weighted Calibration:** authenticity_weight column (0.42-1.96) for IRT estimation
- **Database:** `ne25_calibration` table with 2 indexes (id, years)
- **Execution Time:** ~5-10 seconds (Step 11)
- **Purpose:** Optimized source for combined IRT calibration dataset with authenticity weighting

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
  - `ne25_kidsights_gsed_pf_scores_2022_scale` - Person-fit scores (2,831 records with scores)
  - `ne25_too_few_items` - Exclusion flags for insufficient item responses (718 records)
- **Pipeline Integration:** Automatically joined in NE25 pipeline Step 6.7 (if tables exist)
- **Workflow Location:** `calibration/ne25/manual_2023_scale/`
- **Orchestrator Script:** `run_manual_calibration.R`
- **Execution:** Manual workflow (run separately before NE25 pipeline)
- **Documentation:** See [Manual 2023 Scale Calibration](docs/irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md)

### 🚧 HRTL Scoring - In Development (November 2025)
- **Status:** **IN DEVELOPMENT** - Functional but pending validation (see GitHub Issue #9)
- **Framework:** Healthy & Ready to Learn (HRTL) for ages 3-5 school readiness assessment
- **Components:** 27 items across 5 domains (Early Learning, Health, Motor, Self-Regulation, Social-Emotional)
- **Functions Created:**
  - `load_hrtl_codebook()`: Extracts 27 items with age-specific thresholds from codebook.json
  - `classify_items()`: Applies age-specific thresholds (3, 4, 5 years) to classify item responses
  - `aggregate_domains()`: Computes domain means using simple averaging with `na.rm=TRUE`
  - `score_hrtl()`: Overall "Ready for Learning" classification using HRTL logic
- **Classification Logic:** Child is "Ready" if `(≥4 domains On-Track) AND (0 domains Needs-Support)`
- **Known Limitations (Issue #9):**
  - Age-based routing excludes 8/27 items from ages 3-5 (developmentally appropriate)
  - Motor Development: Only 1/4 items available (DD207)
  - Early Learning: 6/9 items available
  - Social-Emotional: 4/6 items available
- **Interim Approach:** Simple averaging handles missing items; NE25-specific validation needed
- **Test Results (N=978):** 1.5% Ready, 96.1% Not Ready, 2.4% Insufficient Data
- **Location:** `R/hrtl/` directory with 4 core functions
- **Documentation:** `docs/hrtl/hrtl_item_age_contingency.csv` (27 items × 6 ages with stems/lexicons)
- **Next Steps:** Validate against external criteria, develop NE25-specific norms, integrate into pipeline

### Architecture Highlights
- **Hybrid R-Python Design:** R for transformations, Python for database operations
- **Feather Format:** 3x faster R/Python data exchange, perfect type preservation
- **Independent Pipelines:** NE25 (local survey) + ACS (census) + NHIS (national health) + NSCH (child health) + Raking Targets (weighting) + Imputation (uncertainty) + IRT Calibration (psychometrics)
- **Statistical Integration:** Raking targets + Multiple imputation ready for post-stratification weighting + IRT scoring

**📖 Complete status and architecture:** [PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)

---

**For detailed information on any topic, see the [Documentation Directory](#documentation-directory) above.**

*Updated: January 2025 | Version: 3.4.0*
- pid does not uniquely identify an individual in the nebraska 2025 (ne25) data. It is the pid + record_id combination.