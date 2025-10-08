# Pipeline Execution Steps

**Last Updated:** October 2025

This document provides step-by-step execution instructions for all four data pipelines. Each pipeline follows a similar pattern (Extract → Validate → Load) but with pipeline-specific tools and data sources.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [R Execution Guidelines](#r-execution-guidelines-critical)
3. [NE25 Pipeline](#ne25-pipeline-steps)
4. [ACS Pipeline](#acs-pipeline-steps)
5. [NHIS Pipeline](#nhis-pipeline-steps)
6. [NSCH Pipeline](#nsch-pipeline-steps)
7. [Imputation Pipeline](#imputation-pipeline-steps)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
- **R 4.5.1** with packages: arrow, duckdb, dplyr, tidyr, REDCapR
- **Python 3.13+** with packages: duckdb, pandas, pyyaml, ipumspy, pyreadstat, structlog

### API Keys
- **IPUMS API key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt` (for ACS and NHIS pipelines)
- **REDCap API key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv` (for NE25 pipeline)

### File Paths
- **R:** `C:/Program Files/R/R-4.5.1/bin`
- **Working Directory:** Project root (`Kidsights-Data-Platform/`)

---

## R Execution Guidelines (CRITICAL)

⚠️ **Never use inline `-e` commands - they cause segmentation faults**

### Correct Pattern: Use Temp Script Files

```bash
# ✅ CORRECT - Write to temp file, then execute
echo 'library(dplyr); cat("Success\n")' > scripts/temp/temp_script.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/temp/temp_script.R
```

### Incorrect Pattern: Inline Commands

```bash
# ❌ INCORRECT - Causes segmentation faults
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "library(dplyr)"
```

**Why?** The R DuckDB driver has stability issues when run with `-e` inline commands. Using script files eliminates this problem entirely.

---

## NE25 Pipeline Steps

**Purpose:** Process REDCap survey data from Nebraska 2025 study
**Run Time:** ~5-10 minutes for 3,900+ records
**Frequency:** Run whenever new REDCap data is available

### Quick Command

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

### Detailed Steps

#### 1. Database Initialization
```bash
python pipelines/python/init_database.py --config config/sources/ne25.yaml
```
**What it does:**
- Creates/validates DuckDB database structure
- Initializes 11 tables (ne25_raw, ne25_transformed, 9 validation/metadata tables)
- Checks database connection

#### 2. Data Extraction (R)
**Executed by:** `R/extract/ne25_extract.R`
**What it does:**
- Connects to 4 REDCap projects via REDCapR
- Extracts raw survey responses (~3,900 records)
- Applies initial data cleaning

#### 3. Raw Storage (Python via Feather)
**Executed by:** `pipelines/python/insert_raw_data.py`
**What it does:**
- Reads Feather file from R (`tempdir()/ne25_pipeline/raw.feather`)
- Chunks data for efficient insertion (500 records/chunk)
- Stores in `ne25_raw` table with perfect type preservation

#### 4. Transformations (R)
**Executed by:** `R/transform/ne25_transforms.R`
**What it does:**
- Applies recode_it() to create 99 derived variables
- Handles missing data with recode_missing()
- Creates composite scores (PHQ-2, GAD-2, ACE totals)
- Geographic transformations (ZIP → PUMA, County, etc.)

#### 5. Final Storage (Python via Feather)
**Executed by:** `pipelines/python/insert_transformed_data.py`
**What it does:**
- Reads transformed Feather file from R
- Stores in `ne25_transformed` table
- Validates record counts match raw data

#### 6. Metadata Generation (Python)
**Executed by:** `scripts/documentation/generate_html_documentation.py`
**What it does:**
- Generates JSON metadata export
- Creates HTML data dictionary
- Produces Markdown documentation

### Expected Output

- **Tables:** `ne25_raw` (3,900+ rows), `ne25_transformed` (3,900+ rows)
- **Files:** Data dictionary HTML, JSON metadata, validation reports
- **Status:** "Pipeline completed successfully" message

---

## ACS Pipeline Steps

**Purpose:** Extract Census data from IPUMS USA API for statistical raking
**Run Time:** 5-15 min (1-year) or 45+ min (5-year)
**Frequency:** Run annually when new ACS data is released

### Quick Commands

```bash
# Full 3-step pipeline for Nebraska 2019-2023
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

### Detailed Steps

#### Step 1: Extract from IPUMS API

```bash
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
```

**What it does:**
- Reads configuration from `config/sources/acs/nebraska-2019-2023.yaml`
- Checks cache for existing extract (based on SHA256 signature)
- If not cached:
  - Submits extract request to IPUMS USA API
  - Polls for completion (5-15 min for 1-year, 45+ min for 5-year)
  - Downloads and validates data file
  - Caches for future use (90+ day retention)
- Converts to Feather format: `data/acs/{state}/{year_range}/raw.feather`

**Output:**
- Feather file with census microdata
- Cache directory: `cache/ipums/{extract_id}/`
- DDI metadata file for variable definitions

#### Step 2: Validate in R

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska --year-range 2019-2023 --state-fip 31
```

**What it does:**
- Loads Feather file with `arrow::read_feather()`
- Validates required variables present (YEAR, STATEFIP, AGE, PERWT, etc.)
- Checks age filter (children under 6)
- Checks state filter (matches --state-fip)
- Validates sampling weights (PERWT > 0)
- Generates summary statistics

**Validation Checks:**
1. File exists and is readable
2. Required variables present
3. Age range correct (0-5 years)
4. State FIPS matches configuration
5. No missing sampling weights
6. Record counts reasonable
7. No duplicate records

**Output:**
- Console summary with record counts, age distribution, weight statistics
- Validation PASS/FAIL status

#### Step 3: Insert to Database

```bash
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**What it does:**
- Loads validated Feather file
- Chunks data for efficient insertion (10,000 records/chunk)
- Stores in `acs_raw` table (separate from NE25 tables)
- Validates row counts match input file
- Loads DDI metadata into `acs_variables`, `acs_value_labels`, `acs_metadata_registry` tables

**Output:**
- `acs_raw` table populated with census microdata
- Metadata tables populated for decoding/harmonization
- Insertion summary with record counts

### ACS Utility Scripts

```bash
# Test API connection and authentication
python scripts/acs/test_api_connection.py --test-connection

# Submit test extract (Nebraska 2021, fast processing ~5 min)
python scripts/acs/test_api_connection.py --submit-test

# Check status of existing extract
python scripts/acs/check_extract_status.py usa:12345

# Run multiple states in sequence
python scripts/acs/run_multiple_states.py --states nebraska iowa kansas --year-range 2019-2023

# Cache management
python scripts/acs/manage_cache.py --list                # List all cached extracts
python scripts/acs/manage_cache.py --validate            # Validate cache integrity
python scripts/acs/manage_cache.py --clean --max-age 90  # Remove old cache (90+ days)

# End-to-end test (Nebraska 2021, full pipeline)
Rscript scripts/acs/test_pipeline_end_to_end.R
```

### Expected Output

- **Tables:** `acs_raw` (varies by state/year), `acs_variables`, `acs_value_labels`, `acs_metadata_registry`
- **Files:** Feather data file, DDI XML metadata, cache directory
- **Status:** "Data successfully inserted" message

---

## NHIS Pipeline Steps

**Purpose:** Extract National Health Interview Survey data for ACEs/mental health benchmarking
**Run Time:** ~1-2 minutes (with cache), ~60 seconds (production extraction)
**Frequency:** Run annually when new NHIS data is released

### Quick Commands

```bash
# Full 3-step pipeline for 2019-2024
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

### Detailed Steps

#### Step 1: Extract from IPUMS NHIS API

```bash
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
```

**What it does:**
- Reads configuration from `config/sources/nhis/nhis-2019-2024.yaml`
- Checks cache (SHA256 signature based on years + samples + variables)
- If not cached:
  - Submits extract request to IPUMS NHIS API (collection: `nhis`)
  - Polls for completion (~5-10 min for 6-year extract)
  - Downloads 66 variables across 6 annual samples (2019-2024)
  - Validates data file
  - Caches for future use
- Converts to Feather format: `data/nhis/{year_range}/raw.feather`

**Variables Extracted (66 total):**
- Demographics: AGE, SEX, RACEA, HISPETH
- Parent info: PARENTREL, PARENTAGE, PARENTEDU, PARENTEMPL
- ACEs: 8 variables (parent divorce, death, jail, domestic violence, etc.)
- Mental health: GAD-7 (7 items), PHQ-8 (8 items) - 2019, 2022 only
- Economic: POVERTY, EDUC, EMPSTAT
- Survey design: SAMPWEIGHT, STRATA, PSU

**Output:**
- Feather file with 229,609 records (188,620 sample + 40,989 non-sample)
- Cache directory with data + DDI metadata

#### Step 2: Validate in R

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
```

**What it does:**
- Loads Feather file with `arrow::read_feather()`
- Runs 7 comprehensive validation checks

**Validation Checks:**
1. Required variables present (66 variables)
2. Year range correct (2019-2024, 6 years)
3. Survey design variables valid (SAMPWEIGHT, STRATA, PSU)
4. ACE variables present (8 ACE items)
5. Mental health variables present (GAD-7, PHQ-8 for 2019, 2022)
6. No duplicate records
7. Record counts reasonable

**Output:**
- Console validation report
- Summary statistics (record count by year, sample weights, ACE prevalence)

#### Step 3: Insert to Database

```bash
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**What it does:**
- Loads validated Feather file
- Chunks data (10,000 records/chunk)
- Stores in `nhis_raw` table
- Validates row counts

**Output:**
- `nhis_raw` table with 229,609 records
- Insertion summary

### Expected Output

- **Tables:** `nhis_raw` (229,609 records)
- **Files:** Feather data file, DDI metadata, cache directory
- **Status:** "NHIS data successfully inserted" message

---

## NSCH Pipeline Steps

**Purpose:** Integrate National Survey of Children's Health data for benchmarking
**Run Time:** ~20 seconds (single year), ~2 minutes (all 7 years)
**Frequency:** Run when new NSCH year is released

### Quick Commands

```bash
# Process single year (2023)
python scripts/nsch/process_all_years.py --years 2023

# Process all years (2017-2023, 7 years)
python scripts/nsch/process_all_years.py --years all

# Process year range
python scripts/nsch/process_all_years.py --years 2020-2023
```

### Detailed Steps

The NSCH pipeline uses an **integrated single-command workflow** that handles:

1. **SPSS Conversion (Python)**
   - Loads SPSS file from `data/nsch/spss/{year}_topical.sav`
   - Extracts variable metadata (labels, value labels)
   - Converts to Feather format: `data/nsch/{year}/raw.feather`

2. **Validation (R)**
   - Runs 7 QC checks:
     - HHID variable present
     - Record count matches SPSS file
     - Expected column count (840-923 variables)
     - Data types correct
     - No excessive missing values
     - Year identifier valid
     - File integrity confirmed

3. **Database Loading (Python)**
   - Chunks data (10,000 records/chunk)
   - Stores in year-specific table: `nsch_{year}_raw`
   - Generates metadata: `data/nsch/{year}/metadata.json`

4. **Metadata Generation**
   - Auto-generates variable reference
   - Creates value label mappings
   - Produces validation report

### Manual Step-by-Step (if needed)

```bash
# 1. Load SPSS file
python pipelines/python/nsch/load_nsch_spss.py --year 2023

# 2. Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nsch_pipeline.R --year 2023

# 3. Insert to database
python pipelines/python/nsch/insert_nsch_database.py --year 2023

# 4. Generate variable reference (optional)
python scripts/nsch/generate_variable_reference.py
```

### Expected Output

- **Tables:** `nsch_2017_raw`, `nsch_2018_raw`, ..., `nsch_2023_raw` (7 tables, 284,496 total records)
- **Files:** Feather files, metadata JSON, variable reference, validation reports
- **Status:** "Successfully processed 7 years" message

---

## Imputation Pipeline Steps

**Purpose:** Generate M=5 imputations for geographic, sociodemographic, and childcare uncertainty
**Run Time:** ~2 minutes for complete 7-stage pipeline
**Frequency:** Run after NE25 pipeline completes

### Quick Command

```bash
# Full 7-stage pipeline (Geography → Sociodem → Childcare)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R
```

### Detailed Steps

The imputation pipeline uses a **7-stage sequential architecture** that propagates uncertainty from geography through sociodemographics to childcare variables.

#### Prerequisites

**One-Time Setup:**
```bash
# Create database schema for study (run once per study)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25
```

**What it does:**
- Creates 14 imputation tables: `ne25_imputed_{variable}`
- Adds imputation_metadata table
- Sets up indexes for efficient querying

#### Stage 1-3: Geography Imputation (Python)

**Executed by:** `scripts/imputation/ne25/01_impute_geography.py`

**What it does:**
- Parses semicolon-delimited geography values from `ne25_transformed`
- Extracts allocation factor (afact) probabilities
- Samples M=5 values using weighted random selection
- Stores only ambiguous records (afact < 1) in variable-specific tables

**Output:**
- `ne25_imputed_puma`: 4,390 rows (878 records × 5 imputations)
- `ne25_imputed_county`: 5,270 rows (1,054 records × 5 imputations)
- `ne25_imputed_census_tract`: 15,820 rows (3,164 records × 5 imputations)
- **Subtotal:** 25,480 rows across 3 tables

**Timing:** ~3-5 seconds

#### Stage 4: Sociodemographic Imputation (R + Python)

**Executed by:**
1. `scripts/imputation/ne25/02_impute_sociodemographic.R` - MICE imputation
2. `scripts/imputation/ne25/02b_insert_sociodem_imputations.py` - Database insertion

**What it does:**
- Loads geography imputations (M=5) from Stage 1-3
- Uses MICE (Multivariate Imputation by Chained Equations)
- Imputes 7 sociodemographic variables using geography as predictors
- Defensive NULL filtering before database insertion

**Variables Imputed:**
- `female` - Child sex
- `raceG` - Combined race/ethnicity
- `educ_mom`, `educ_a2` - Mother/second caregiver education
- `income` - Household income
- `family_size` - Household size
- `fplcat` - Federal Poverty Level categories

**Output:**
- 7 tables: `ne25_imputed_female`, `ne25_imputed_raceG`, etc.
- **Subtotal:** 26,438 rows across 7 tables

**Timing:** ~100 seconds (MICE convergence + database insertion)

#### Stage 5: Childcare Receives Care (R)

**Executed by:** `scripts/imputation/ne25/03a_impute_cc_receives_care.R`

**What it does:**
- Loads geography (M=5) + sociodem (M=5) from Stages 1-4
- Uses CART method to impute `cc_receives_care` (Yes/No)
- Saves to Feather: `data/imputation/ne25/childcare_feather/cc_receives_care_m{m}.feather`

**Output:**
- 5 Feather files (one per imputation)
- Imputes missing childcare access indicator

**Timing:** ~5 seconds

#### Stage 6: Childcare Type & Hours (R)

**Executed by:** `scripts/imputation/ne25/03b_impute_cc_type_hours.R`

**What it does:**
- **Conditional logic:** Filters to records with `cc_receives_care = "Yes"`
- **Data cleaning:** Caps `cc_hours_per_week` at 168 (prevents outlier propagation)
- Uses CART to impute `cc_primary_type` and `cc_hours_per_week`
- Saves to Feather files

**Variables Imputed:**
- `cc_primary_type` - Type of childcare arrangement (6 categories)
- `cc_hours_per_week` - Hours per week in childcare (0-168)

**Output:**
- 10 Feather files (2 variables × 5 imputations)

**Timing:** ~7 seconds

#### Stage 7: Childcare Derived Variable (R) + Database Insertion (Python)

**Executed by:**
1. `scripts/imputation/ne25/03c_derive_childcare_10hrs.R` - Derivation
2. `scripts/imputation/ne25/04_insert_childcare_imputations.py` - Database insertion

**What it does:**
- Derives `childcare_10hrs_nonfamily` from completed type + hours
- **Logic:** TRUE if hours ≥10 AND type ≠ "Relative care"
- Inserts all 4 childcare variables into database with defensive NULL filtering

**Output:**
- `ne25_imputed_cc_receives_care`: 805 rows
- `ne25_imputed_cc_primary_type`: 7,934 rows
- `ne25_imputed_cc_hours_per_week`: 6,329 rows
- `ne25_imputed_childcare_10hrs_nonfamily`: 15,590 rows
- **Subtotal:** 24,718 rows across 4 tables

**Timing:** ~4 seconds (derivation + database insertion)

### Expected Output

**Database Tables:**
- **Geography:** 3 tables, 25,480 rows
- **Sociodemographic:** 7 tables, 26,438 rows
- **Childcare:** 4 tables, 24,718 rows
- **Total:** 14 tables, 76,636 rows

**Console Output:**
```
=======================================================================
IMPUTATION PIPELINE SUMMARY
=======================================================================

Stages Completed:
  Stage 1-3: Geography Imputation         [OK] 3.2 sec
  Stage 4:   Sociodemographic Imputation  [OK] 96.9 sec
  Stage 5:   Childcare Receives Care      [OK] 5.3 sec
  Stage 6:   Childcare Type & Hours       [OK] 7.3 sec
  Stage 7:   Childcare Derivation & DB    [OK] 4.0 sec

Total Runtime: 122.6 seconds (2.0 minutes)
Total Rows Inserted: 76,636 across 14 tables

=======================================================================
VALIDATION CHECKS - ALL PASSED
=======================================================================
```

### Validation

**Quick Validation:**
```bash
python -m python.imputation.helpers
```

**What it checks:**
- All 14 variables have metadata entries
- No NULL values in imputation tables
- No duplicate records
- Childcare values within valid ranges
- Row counts match expectations

**Detailed Diagnostics:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/test_childcare_diagnostics.R
```

**What it checks:**
- Imputed vs observed proportions (stability across M)
- Variance across imputations (50% variation expected)
- Predictor relationships (geographic/income gradients)
- Plausibility checks (range validation, logical consistency)

### Usage After Pipeline Completion

**Python - Get Complete Dataset:**
```python
from python.imputation.helpers import get_complete_dataset

# Get imputation m=1 with all 14 variables
df = get_complete_dataset(study_id='ne25', imputation_number=1)
# Returns: puma, county, census_tract, female, raceG, educ_mom, educ_a2,
#          income, family_size, fplcat, cc_receives_care, cc_primary_type,
#          cc_hours_per_week, childcare_10hrs_nonfamily
```

**R - Survey Analysis with MI:**
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

### Multi-Study Usage

**Adding a New Study:**
```bash
# Automated setup script
python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"

# Customize config
# Edit: config/imputation/ia26_config.yaml

# Run pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ia26/run_full_imputation_pipeline.R
```

**Documentation:** [docs/imputation/ADDING_NEW_STUDY.md](../imputation/ADDING_NEW_STUDY.md)

---

## Troubleshooting

### Common Issues

#### 1. R Segmentation Faults
**Symptom:** R crashes with "Segmentation fault" error
**Solution:** Never use `-e` inline commands. Always use temp script files.

#### 2. IPUMS API Authentication Failed
**Symptom:** "Invalid API key" or "Authentication failed"
**Solution:** Verify API key file exists at `C:/Users/waldmanm/my-APIs/IPUMS.txt`

#### 3. Cache Not Found
**Symptom:** "Extract not found in cache, submitting new request"
**Solution:** This is normal for first run. Subsequent runs will use cache.

#### 4. Feather File Not Found
**Symptom:** "File not found: data/{pipeline}/raw.feather"
**Solution:** Run extraction step before validation step

#### 5. Database Connection Failed
**Symptom:** "Could not connect to database"
**Solution:**
```bash
# Test database connection
python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

#### 6. Missing Python Packages
**Symptom:** "ModuleNotFoundError: No module named 'ipumspy'"
**Solution:**
```bash
pip install duckdb pandas pyyaml ipumspy pyreadstat structlog
```

#### 7. SPSS File Not Found (NSCH)
**Symptom:** "File not found: data/nsch/spss/2023_topical.sav"
**Solution:** Download SPSS file from NSCH website and place in `data/nsch/spss/`

### Performance Tips

1. **Use cache:** ACS/NHIS pipelines cache extracts for 90+ days
2. **Parallel processing:** Run multiple states/years in separate terminal sessions
3. **Chunk size:** Adjust chunk size in insert scripts if memory issues occur
4. **Clean old cache:** Periodically run `scripts/acs/manage_cache.py --clean --max-age 90`

---

## Related Documentation

- **Pipeline Architecture:** [PIPELINE_OVERVIEW.md](PIPELINE_OVERVIEW.md)
- **Quick Reference:** [../QUICK_REFERENCE.md](../QUICK_REFERENCE.md)
- **Troubleshooting Guide:** [../troubleshooting.md](../troubleshooting.md)
- **ACS Documentation:** [../acs/README.md](../acs/README.md)
- **NHIS Documentation:** [../nhis/README.md](../nhis/README.md)
- **NSCH Documentation:** [../nsch/README.md](../nsch/README.md)

---

*Last Updated: October 2025*
