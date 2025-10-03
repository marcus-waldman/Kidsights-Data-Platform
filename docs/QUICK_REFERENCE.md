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

## Pipeline Status Summary

### NE25 Pipeline
✅ **Production Ready** | 3,908 records | 11 tables | 100% reliability

### ACS Pipeline
✅ **Complete** | Census data | State-specific extracts | 90+ day cache

### NHIS Pipeline
✅ **Production Ready** | 229,609 records | 66 variables | 6 years (2019-2024)

### NSCH Pipeline
✅ **Production Ready** | 284,496 records | 3,780 variables | 7 years (2017-2023)

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
