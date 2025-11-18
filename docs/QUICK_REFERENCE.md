# Quick Reference Guide

**Last Updated:** October 2025

This document provides a quick reference cheatsheet for common Kidsights Data Platform operations. For detailed documentation, see the linked guides.

---

## Table of Contents

1. [Pipeline Commands](#pipeline-commands)
2. [ACS Utility Scripts](#acs-utility-scripts)
3. [Environment Setup](#environment-setup)
4. [Quick Debugging](#quick-debugging)
5. [Common Tasks](#common-tasks)
6. [Interactive Tools](#interactive-tools)

---

## Pipeline Commands

### NE25 Pipeline

**Purpose:** Process REDCap survey data from Nebraska 2025 study

```bash
# Run complete pipeline
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**What it does:**
- Extracts data from 4 REDCap projects
- Transforms data (99 derived variables)
- Stores in DuckDB database
- Generates documentation

**Documentation:** [docs/architecture/PIPELINE_STEPS.md](architecture/PIPELINE_STEPS.md#ne25-pipeline-steps)

---

### ACS Pipeline

**Purpose:** Extract census data from IPUMS USA API for statistical raking

```bash
# Step 1: Extract data from IPUMS API
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023

# Step 2: Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska --year-range 2019-2023 --state-fip 31

# Step 3: Insert into database
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**What it does:**
- Submits extract to IPUMS USA API (or retrieves from cache)
- Validates age/state filters and sampling weights
- Stores in `acs_raw` table with metadata

**Timing:** 5-15 min (1-year) or 45+ min (5-year)

**Documentation:** [docs/acs/pipeline_usage.md](acs/pipeline_usage.md)

---

### NHIS Pipeline

**Purpose:** Extract National Health Interview Survey data for ACEs/mental health benchmarking

```bash
# Step 1: Extract data from IPUMS NHIS API
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

# Step 2: Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024

# Step 3: Insert into database
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**What it does:**
- Extracts 66 variables across 6 annual samples (2019-2024)
- Validates survey design variables, ACEs, mental health measures
- Stores in `nhis_raw` table (229,609 records)

**Timing:** ~1-2 minutes (with cache), ~60 seconds (production extraction)

**Documentation:** [docs/nhis/pipeline_usage.md](nhis/pipeline_usage.md)

---

### NSCH Pipeline

**Purpose:** Integrate National Survey of Children's Health data for benchmarking

```bash
# Process single year
python scripts/nsch/process_all_years.py --years 2023

# Process all years (2016-2023)
python scripts/nsch/process_all_years.py --years all

# Process year range
python scripts/nsch/process_all_years.py --years 2020-2023
```

**What it does:**
- Converts SPSS files to Feather format
- Runs 7 QC checks per year
- Stores in year-specific tables (`nsch_2023_raw`, etc.)
- Generates metadata and variable reference

**Timing:** ~20 seconds (single year), ~2 minutes (all 7 years)

**Documentation:** [docs/nsch/pipeline_usage.md](nsch/pipeline_usage.md)

---

### Raking Targets Pipeline

**Purpose:** Generate population-representative raking targets for post-stratification weighting

```bash
# Run full pipeline (Phases 1-5)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R

# Verify results
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

**What it does:**
- Loads ACS estimates (25 estimands from Phase 1)
- Estimates NHIS outcomes (1 estimand: parent PHQ-2)
- Estimates NSCH outcomes (4 estimands: ACEs, health, child care)
- Consolidates to 180 raking targets (30 estimands × 6 ages)
- Loads to database table `raking_targets_ne25`

**Timing:** ~2-3 minutes

**Output:** 180 raking targets in DuckDB with 4 indexes

**Documentation:** [docs/raking/NE25_RAKING_TARGETS_PIPELINE.md](raking/NE25_RAKING_TARGETS_PIPELINE.md)

---

### Imputation Pipeline

**Purpose:** Generate M=5 imputations for geographic, sociodemographic, childcare, and mental health uncertainty

```bash
# Setup database schema (one-time, study-specific)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25

# Run full 9-stage pipeline (Geography → Sociodem → Childcare → Mental Health)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R

# Validate results
python -m python.imputation.helpers
```

**What it does:**
- **Stage 1-3:** Geography imputation (PUMA, county, census_tract)
- **Stage 4:** Sociodemographic imputation via MICE (7 variables)
- **Stage 5-7:** Childcare 3-stage sequential imputation (4 variables)
- **Stage 8-9:** Mental health & parenting imputation via CART (7 variables: 5 items + 2 derived screens)
- **Stage 10-11:** Child ACEs imputation via random forest (9 variables: 8 items + derived total)
- Stores only imputed/derived values in variable-specific tables
- Provides helper functions to retrieve completed datasets

**Timing:** ~3 minutes for complete 11-stage pipeline

**Output:** 85,746 imputation rows across 30 tables

**Python usage - Get Complete Dataset (All 30 Variables):**
```python
from python.imputation.helpers import (
    get_complete_dataset,
    get_childcare_imputations,
    get_mental_health_imputations,
    get_child_aces_imputations
)

# Get imputation m=1 with all 30 variables
df = get_complete_dataset(study_id='ne25', imputation_number=1)
# Returns: puma, county, census_tract, female, raceG, educ_mom, educ_a2,
#          income, family_size, fplcat, cc_receives_care, cc_primary_type,
#          cc_hours_per_week, childcare_10hrs_nonfamily, phq2_interest,
#          phq2_depressed, gad2_nervous, gad2_worry, q1502, phq2_positive, gad2_positive,
#          child_ace_parent_divorce, child_ace_parent_death, child_ace_parent_jail,
#          child_ace_domestic_violence, child_ace_neighborhood_violence,
#          child_ace_mental_illness, child_ace_substance_use,
#          child_ace_discrimination, child_ace_total

# Get just childcare variables (4 variables)
childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)

# Get just mental health variables (7 variables: 5 items + 2 derived screens)
mental_health = get_mental_health_imputations(study_id='ne25', imputation_number=1)

# Get just child ACEs variables (9 variables: 8 items + derived total)
aces = get_child_aces_imputations(study_id='ne25', imputation_number=1)
# Check 4+ ACEs prevalence
pct_4plus = (aces['child_ace_total'] >= 4).mean() * 100

# Get all 5 imputations in long format
from python.imputation.helpers import get_all_imputations
df_long = get_all_imputations(study_id='ne25', variables=['puma', 'childcare_10hrs_nonfamily', 'phq2_positive', 'child_ace_total'])
```

**R usage - Survey Analysis with MI (via reticulate):**
```r
source("R/imputation/helpers.R")
library(survey); library(mitools)

# Get all M=5 imputations for mitools
imp_list <- get_imputation_list(study_id = 'ne25')

# Create survey designs
designs <- lapply(imp_list, function(df) {
  svydesign(ids=~1, weights=~weight, data=df)
})

# Estimate with Rubin's rules
results <- lapply(designs, function(d) svymean(~childcare_10hrs_nonfamily, d))
combined <- MIcombine(results)
summary(combined)  # Proper MI variance
```

**Multi-Study Support:**
```bash
# Add new study (automated)
python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"

# Run study-specific pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ia26/run_full_imputation_pipeline.R
```

**Documentation:**
- [USING_IMPUTATION_AGENT.md](imputation/USING_IMPUTATION_AGENT.md) - User guide with 3 use cases
- [ADDING_NEW_STUDY.md](imputation/ADDING_NEW_STUDY.md) - Multi-study onboarding

---

### IRT Calibration Pipeline

**Purpose:** Create Mplus-compatible calibration dataset for psychometric recalibration of developmental/behavioral items

```bash
# Full pipeline (recommended): Create tables + long format + Mplus export
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R

# Skip long format (faster iteration, ~30 seconds saved)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-long-format

# Skip quality checks (use with caution)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-quality-check

# One-time: Import historical data (NE20, NE22, USA24) - only if starting fresh
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/import_historical_calibration.R
```

**Note:** NE25 calibration table is automatically created by NE25 pipeline (Step 11) - manual execution rarely needed

**What it does:**
- Combines 6 studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24
- Harmonizes 416 items via lexicon mappings (ne25/cahmi21/cahmi22 → lex_equate)
- Creates two database tables:
  - `calibration_dataset_2020_2025` (wide format): 47,084 records × 303 columns
  - `calibration_dataset_long` (long format): 1,316,391 rows × 9 columns
- Exports Mplus .dat file (space-delimited, missing as ".")
- Computes Cook's D influence diagnostics for QA masking

**Timing:** ~5-7 minutes (full pipeline), ~3-5 minutes (with --skip-long-format)

**Output:**
- Wide format: 47,084 records × 419 columns (~38 MB) for Mplus
- Long format: 1.3M rows for QA analysis (~20 MB, includes full NSCH holdout sample)

**⚠️ REQUIRED NEXT STEP:** After creating the calibration dataset, you MUST run the Age-Response Gradient Explorer for visual quality assurance before proceeding to Mplus calibration.

```r
# Launch QA tool
shiny::runApp("scripts/shiny/age_gradient_explorer")
```

See [Interactive Tools](#interactive-tools) section for detailed QA checklist.

**Validation Commands:**
```bash
# Test Mplus format compatibility
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/test_mplus_compatibility.R

# Validate item missingness patterns
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/validate_item_missingness.R

# Full-scale performance test
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/run_full_scale_test.R
```

**Database Query Examples:**

```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Study distribution (wide format)
DBI::dbGetQuery(conn, "
  SELECT study_num, COUNT(*) as n
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
")

# Long format: Record counts by study and dev/mask flags
DBI::dbGetQuery(conn, "
  SELECT
    study,
    COUNT(DISTINCT id) as n_participants,
    COUNT(*) as n_observations,
    SUM(CASE WHEN devflag = 1 THEN 1 ELSE 0 END) as n_development,
    SUM(CASE WHEN devflag = 0 THEN 1 ELSE 0 END) as n_holdout,
    SUM(CASE WHEN maskflag = 1 THEN 1 ELSE 0 END) as n_masked
  FROM calibration_dataset_long
  GROUP BY study
  ORDER BY study
")

# Long format: Convert to wide format for specific item
DBI::dbGetQuery(conn, "
  SELECT
    id, years, study,
    MAX(CASE WHEN lex_equate = 'DD221' THEN y END) as DD221,
    MAX(CASE WHEN lex_equate = 'EG44_2' THEN y END) as EG44_2
  FROM calibration_dataset_long
  WHERE lex_equate IN ('DD221', 'EG44_2')
  GROUP BY id, years, study
  LIMIT 10
")

# Age distribution by study
DBI::dbGetQuery(conn, "
  SELECT
    study_num,
    MIN(years) as min_age,
    AVG(years) as mean_age,
    MAX(years) as max_age
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
")

DBI::dbDisconnect(conn)
```

**R Function Usage:**
```r
# Source function directly
source("scripts/irt_scoring/prepare_calibration_dataset.R")

# Run with defaults (NSCH n=1000, output: mplus/calibdat.dat)
prepare_calibration_dataset()

# Or with custom paths
prepare_calibration_dataset(
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb"
)
```

**Documentation:**
- [MPLUS_CALIBRATION_WORKFLOW.md](irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md) - Complete 4-stage workflow
- [CALIBRATION_DATASET_EXAMPLE.md](irt_scoring/CALIBRATION_DATASET_EXAMPLE.md) - Step-by-step walkthrough with FAQ
- [Validation Summary](../todo/calibration_dataset_validation_summary.md) - Test results and production approval

---

### IRT Calibration MODEL Syntax Generation

**Purpose:** Generate Mplus MODEL, CONSTRAINT, and PRIOR syntax from codebook constraints

```bash
# Interactive workflow (prompts for outputs)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/run_calibration_workflow.R

# Or source in R session for more control
```

**R Function Usage:**
```r
# Source orchestrator function
source("scripts/irt_scoring/calibration/generate_model_syntax.R")

# Generate Excel only (for review)
result <- generate_kidsights_model_syntax(
  scale_name = "kidsights",
  output_xlsx = "mplus/generated_syntax.xlsx"
)

# Generate both Excel + complete .inp file
result <- generate_kidsights_model_syntax(
  scale_name = "kidsights",
  output_xlsx = "mplus/generated_syntax.xlsx",
  output_inp = "mplus/calibration.inp",
  dat_file_path = "calibdat.dat"
)

# Use existing template for TITLE/DATA/VARIABLE/ANALYSIS sections
result <- generate_kidsights_model_syntax(
  output_xlsx = "mplus/generated_syntax.xlsx",
  output_inp = "mplus/calibration.inp",
  template_inp = "mplus/my_template.inp"
)
```

**What it does:**
- Loads codebook.json and builds equate table (jid <-> lex_equate)
- Extracts param_constraints from psychometric metadata
- Loads calibration dataset from DuckDB (47,084 records, 416 items)
- Generates MODEL syntax (factor loadings, thresholds)
- Generates MODEL CONSTRAINT syntax (5 constraint types + 1-PL)
- Generates MODEL PRIOR syntax (N(1,1) Bayesian priors)
- Writes Excel file with 3 sheets (MODEL, CONSTRAINT, PRIOR)
- Optionally generates complete .inp file ready for Mplus execution

**Timing:** ~5-10 seconds

**Output Files:**
- `mplus/generated_syntax.xlsx` - Review syntax in Excel (always created)
- `mplus/calibration.inp` - Complete Mplus input file (if output_inp specified)

**Supported Constraint Types (from codebook param_constraints field):**
1. **Complete Equality:** "Constrain all to AA102"
2. **Slope-Only Equality:** "Constrain slope to AA102"
3. **Threshold Ordering:** "Constrain tau$1 to be greater than AA102$1"
4. **Simplex Constraints:** "Constrain tau$1 to be a simplex between AA102$1 and AA102$4"
5. **1-PL/Rasch:** Automatic for unconstrained items (equal discriminations)

**Multiple Constraints Example:**
```json
"param_constraints": "Constrain slope to AA102; Constrain tau$1 to be greater than AA102$1"
```

**Next Steps:**
1. Review Excel file to verify syntax correctness
2. Open .inp file in Mplus (if generated)
3. Run -> Run Mplus
4. Check .out file for convergence and fit statistics

**Documentation:**
- [calibration/README.md](irt_scoring/calibration/README.md) - Complete syntax generation guide
- [CONSTRAINT_SPECIFICATION.md](irt_scoring/CONSTRAINT_SPECIFICATION.md) - Constraint types reference

---

## ACS Utility Scripts

### Test API Connection

```bash
# Test IPUMS API connectivity and authentication
python scripts/acs/test_api_connection.py --test-connection
```

**Use case:** Verify API key is valid before running full extract

---

### Submit Test Extract

```bash
# Submit test extract (Nebraska 2021, fast processing ~5 min)
python scripts/acs/test_api_connection.py --submit-test
```

**Use case:** Test full API workflow with small extract

---

### Check Extract Status

```bash
# Check status of existing extract
python scripts/acs/check_extract_status.py usa:12345
```

**Use case:** Monitor long-running extract progress

**Output:** Status (queued/processing/completed), processing time, download URL

---

### Run Multiple States

```bash
# Run multiple states in sequence
python scripts/acs/run_multiple_states.py --states nebraska iowa kansas --year-range 2019-2023
```

**Use case:** Batch process multiple states

**Timing:** ~45 min per state (5-year extracts)

---

### Manage Cache

```bash
# List all cached extracts
python scripts/acs/manage_cache.py --list

# Validate cache integrity (check SHA256 signatures)
python scripts/acs/manage_cache.py --validate

# Remove old cache (90+ days)
python scripts/acs/manage_cache.py --clean --max-age 90
```

**Use case:** Free disk space, validate cached data

**Cache location:** `cache/ipums/{extract_id}/`

---

### End-to-End Test

```bash
# Run end-to-end test (Nebraska 2021, full pipeline)
Rscript scripts/acs/test_pipeline_end_to_end.R
```

**Use case:** Verify complete pipeline after code changes

**What it tests:** API extraction, R validation, database insertion

---

## Environment Setup

### Required Software Paths

```bash
# R executable
C:/Program Files/R/R-4.5.1/bin

# Quarto (for documentation rendering)
C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe

# Pandoc (for document conversion)
C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools/pandoc.exe
```

---

### Python Packages

```bash
# Core packages (NE25 pipeline)
pip install duckdb pandas pyyaml structlog

# ACS/NHIS pipeline packages
pip install ipumspy requests

# NSCH pipeline packages
pip install pyreadstat
```

**Verify installation:**
```bash
python -c "import duckdb, pandas, ipumspy, pyreadstat; print('[OK] All packages installed')"
```

---

### API Keys

**REDCap API key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- Used by: NE25 pipeline
- Format: CSV with `project_id`, `api_key` columns

**IPUMS API key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt`
- Used by: ACS and NHIS pipelines
- Format: Plain text file with API key
- Obtain from: https://account.ipums.org/api_keys

---

## Quick Debugging

### 1. Test Database Connection

```bash
# Quick database connection test
python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

**Expected output:** `True`

**If False:** Check database path in `config/sources/ne25.yaml`

---

### 2. R Package Issues

**Problem:** R script fails with package errors

**Solution:** Always use temp script files, never inline `-e` commands

```bash
# ✅ CORRECT
echo 'library(dplyr); cat("Success\n")' > scripts/temp/test.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave -f scripts/temp/test.R

# ❌ INCORRECT (causes segfaults)
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "library(dplyr)"
```

**Documentation:** [guides/CODING_STANDARDS.md](guides/CODING_STANDARDS.md#r-execution-guidelines)

---

### 3. Pipeline Working Directory

**Problem:** Pipeline can't find files

**Solution:** Always run from project root directory

```bash
# Check current directory
pwd
# Should show: /path/to/Kidsights-Data-Platform

# If in wrong directory, navigate to project root
cd C:\Users\waldmanm\git-repositories\Kidsights-Data-Platform
```

---

### 4. Check Python Error Logs

**Problem:** Pipeline fails with cryptic error

**Solution:** Check detailed error context in Python output

```bash
# Run with verbose logging
python pipelines/python/insert_raw_data.py --verbose

# Or check structlog output for details
```

**Log fields:** timestamp, level, event, context (file, line, function)

---

### 5. Generate HTML Documentation

```bash
# Generate data dictionary and metadata exports
python scripts/documentation/generate_html_documentation.py
```

**Output files:**
- `docs/data_dictionary/ne25_data_dictionary_full.html`
- `docs/data_dictionary/ne25_metadata_export.json`
- `docs/data_dictionary/ne25_data_dictionary_full.md`

**Use case:** Verify derived variables, check transformations

---

## Common Tasks

### View Database Tables

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# List all tables
tables = db.execute_query("""
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'main'
    ORDER BY table_name
""")

for table in tables:
    print(table[0])
```

---

### Query Survey Data

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Get record count
result = db.execute_query("SELECT COUNT(*) FROM ne25_raw")
print(f"Total records: {result[0][0]}")

# Get age distribution
result = db.execute_query("""
    SELECT
        FLOOR(years_old) as age,
        COUNT(*) as n
    FROM ne25_transformed
    GROUP BY age
    ORDER BY age
""")

for row in result:
    print(f"Age {row[0]}: {row[1]} children")
```

---

### Export Data to CSV

```python
from python.db.connection import DatabaseManager
import pandas as pd

db = DatabaseManager()

# Export table to DataFrame
with db.get_connection(read_only=True) as conn:
    df = pd.read_sql("SELECT * FROM ne25_transformed", conn)

# Save to CSV
df.to_csv("ne25_export.csv", index=False)
print(f"[OK] Exported {len(df)} records to ne25_export.csv")
```

---

### Load Feather File in R

```r
library(arrow)

# Load transformed data
data <- arrow::read_feather("data/ne25/transformed.feather")
cat("Loaded", nrow(data), "records\n")

# Summary statistics
summary(data$years_old)
table(data$race, useNA = "always")
```

---

### Render Codebook Dashboard

```bash
# Render interactive codebook dashboard
quarto render codebook/dashboard/index.qmd

# Open in browser
# Output: codebook/dashboard/index.html
```

**Use case:** Browse 305 items across 8 studies, explore IRT parameters

---

### Query Geographic Crosswalks

```r
# Source utility function
source("R/utils/query_geo_crosswalk.R")

# Get county crosswalk
county_data <- query_geo_crosswalk("geo_zip_to_county")

# Find counties for specific ZIP
county_data %>%
  dplyr::filter(zip == "68001")
```

**Documentation:** [guides/GEOGRAPHIC_CROSSWALKS.md](guides/GEOGRAPHIC_CROSSWALKS.md)

---

### Add Derived Variable

**Steps:**
1. Edit `R/transform/ne25_transforms.R`
2. Apply `recode_missing()` before calculation
3. Use `na.rm = FALSE` in aggregation
4. Update `config/derived_variables.yaml`
5. Run validation script

**Documentation:** [guides/MISSING_DATA_GUIDE.md#creating-new-composite-variables](guides/MISSING_DATA_GUIDE.md#creating-new-composite-variables)

---

## Interactive Tools

### Launch Age-Response Gradient Explorer (REQUIRED QA)

**Purpose:** Mandatory visual quality assurance for IRT calibration before Mplus

```r
# Launch from project root
shiny::runApp("scripts/shiny/age_gradient_explorer")
```

**What it does:**
- Box-and-whisker plots showing age distributions at each response level
- GAM smoothing (b-splines) for non-linear age trends
- Multi-study filtering (6 studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24)
- Quality flag warnings (negative correlations, category mismatches)
- Codebook metadata integration
- Interactive controls for GAM smoothness (k=3-10)

**Prerequisites:**
- Calibration dataset created (`calibration_dataset_2020_2025` table)
- Required R packages: shiny, duckdb, dplyr, ggplot2, mgcv, jsonlite, DT

**Quality Assurance Checklist:**
1. **Developmental Gradients:** Verify positive age-response correlations for skill items
2. **Negative Flags:** Investigate items with negative gradients (may need exclusion/recoding)
3. **Category Separation:** Check box plot overlap - overlapping categories indicate poor discrimination
4. **Study Consistency:** Compare age patterns across all 6 studies

**Timing:** 3-5 seconds startup, <1 second plot rendering, 15-30 minutes thorough review

**Documentation:** [scripts/shiny/age_gradient_explorer/README.md](../scripts/shiny/age_gradient_explorer/README.md)

---

## Pipeline Status Summary

### NE25 Pipeline
✅ **Production Ready** | 3,908 records | 11 tables | 100% reliability

### ACS Pipeline
✅ **Complete** | Census data | State-specific extracts | 90+ day cache

### NHIS Pipeline
✅ **Production Ready** | 229,609 records | 66 variables | 6 years (2019-2024)

### NSCH Pipeline
✅ **Production Ready** | 284,496 records | 3,780 variables | 7 years (2017-2023)

### Raking Targets Pipeline
✅ **Production Ready** | 180 raking targets | 614,400 bootstrap replicates | ~2-3 min runtime

### Imputation Pipeline
✅ **Production Ready** | 30 variables | 85,746 rows | M=5 imputations | 11-stage sequential | ~3 min runtime

---

## Related Documentation

### Architecture
- **Pipeline Overview:** [architecture/PIPELINE_OVERVIEW.md](architecture/PIPELINE_OVERVIEW.md)
- **Pipeline Steps:** [architecture/PIPELINE_STEPS.md](architecture/PIPELINE_STEPS.md)
- **Directory Structure:** [DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md)

### Guides
- **Coding Standards:** [guides/CODING_STANDARDS.md](guides/CODING_STANDARDS.md)
- **Missing Data:** [guides/MISSING_DATA_GUIDE.md](guides/MISSING_DATA_GUIDE.md)
- **Python Utilities:** [guides/PYTHON_UTILITIES.md](guides/PYTHON_UTILITIES.md)
- **Geographic Crosswalks:** [guides/GEOGRAPHIC_CROSSWALKS.md](guides/GEOGRAPHIC_CROSSWALKS.md)

### Pipeline-Specific
- **ACS:** [acs/README.md](acs/README.md)
- **NHIS:** [nhis/README.md](nhis/README.md)
- **NSCH:** [nsch/README.md](nsch/README.md)

---

*Last Updated: October 2025 | Quick Reference v1.0*
