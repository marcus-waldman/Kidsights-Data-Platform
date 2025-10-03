# NSCH Pipeline Usage Guide

Detailed instructions for using the NSCH data integration pipeline.

**Last Updated:** October 2025

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Setup and Installation](#setup-and-installation)
3. [Single Year Processing](#single-year-processing)
4. [Batch Processing (All Years)](#batch-processing-all-years)
5. [CLI Reference](#cli-reference)
6. [Data Access](#data-access)
7. [Common Workflows](#common-workflows)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Software Requirements

**Python 3.13+**
```bash
python --version  # Should be 3.13 or higher
```

**R 4.5.1+**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --version
```

### Python Packages

Install required packages:

```bash
pip install pandas pyreadstat structlog duckdb
```

**Package Details:**
- `pandas` (>=2.0.0) - Data manipulation
- `pyreadstat` (>=1.2.0) - SPSS file reading
- `structlog` (>=23.0.0) - Structured logging
- `duckdb` (>=0.9.0) - Analytical database

### R Packages

```r
install.packages(c(
    "haven",      # SPSS file reading
    "arrow",      # Feather format I/O
    "dplyr",      # Data manipulation
    "tidyr",      # Data tidying
    "stringr",    # String operations
    "cli",        # CLI output formatting
    "glue"        # String interpolation
))
```

### Data Files

**SPSS Source Files:**

Download NSCH SPSS files and place in `data/nsch/spss/` directory:

```
data/nsch/spss/
├── NSCH2016_Topical_SPSS_CAHM_DRCv2.sav
├── 2017 NSCH_Topical_CAHMI_DRCv2.sav
├── 2018 NSCH_Topical_DRC_v2.sav
├── 2019 NSCH_Topical_CAHMI DRCv2.sav
├── NSCH_2020e_Topical_CAHMI_DRCv3.sav
├── 2021e NSCH_Topical_DRC_CAHMIv3.sav
├── NSCH_2022e_Topical_SPSS_CAHMI_DRCv3.sav
└── NSCH_2023e_Topical_CAHMI_DRC.sav
```

**Download Sources:**
- NSCH Data: https://www.census.gov/programs-surveys/nsch/data/datasets.html
- Select "Topical" dataset
- Choose "SPSS" format
- Download for desired years

### Directory Structure

Ensure these directories exist:

```bash
mkdir -p data/nsch/spss
mkdir -p data/nsch/2016
mkdir -p data/nsch/2017
mkdir -p data/nsch/2018
mkdir -p data/nsch/2019
mkdir -p data/nsch/2020
mkdir -p data/nsch/2021
mkdir -p data/nsch/2022
mkdir -p data/nsch/2023
mkdir -p data/duckdb
```

---

## Setup and Installation

### 1. Verify Python Environment

```bash
# Check Python version
python --version

# Verify packages installed
python -c "import pandas, pyreadstat, duckdb, structlog; print('All packages installed')"
```

### 2. Verify R Environment

```bash
# Check R version
"C:\Program Files\R\R-4.5.1\bin\R.exe" --version

# Verify R packages (create temp script)
echo "library(haven); library(arrow); library(dplyr); cat('All packages loaded\n')" > test_packages.R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" test_packages.R
rm test_packages.R
```

### 3. Verify SPSS Files

```bash
# Check if SPSS files exist
python -c "
from pathlib import Path
spss_dir = Path('data/nsch/spss')
files = list(spss_dir.glob('*.sav'))
print(f'Found {len(files)} SPSS files:')
for f in sorted(files):
    print(f'  - {f.name}')
"
```

### 4. Initialize Database (Optional)

The database will be created automatically during first run, but you can initialize it manually:

```bash
python -c "
import duckdb
from pathlib import Path
db_path = Path('data/duckdb/kidsights_local.duckdb')
db_path.parent.mkdir(parents=True, exist_ok=True)
conn = duckdb.connect(str(db_path))
print(f'Database initialized at {db_path}')
conn.close()
"
```

---

## Single Year Processing

Process a single NSCH year through all 4 pipeline steps.

### Step 1: SPSS to Feather Conversion

Converts SPSS file to Feather format with metadata extraction.

```bash
python pipelines/python/nsch/load_nsch_spss.py --year 2023
```

**What it does:**
- Reads SPSS file for specified year
- Extracts variable metadata (names, labels, types)
- Extracts value labels (codes and meanings)
- Saves metadata to `data/nsch/{year}/metadata.json`
- Converts data to Feather format: `data/nsch/{year}/raw.feather`
- Validates round-trip conversion

**Output:**
```
Processing NSCH 2023 data...
SPSS file: data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav
Reading SPSS file... (55,162 records, 895 columns)
Extracting metadata...
Saving to Feather format...
Round-trip validation: PASSED
Duration: 8.2 seconds
```

**Options:**
```bash
# Overwrite existing files
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite

# Validate existing Feather file only
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --validate-only
```

### Step 2: R Validation

Validates data quality with 7 comprehensive checks.

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nsch_pipeline.R --year 2023
```

**What it does:**
- Loads Feather file
- Runs 7 validation checks:
  1. HHID variable present
  2. Expected record count
  3. Column count matches metadata
  4. No empty columns
  5. Valid data types
  6. No missing HHID values
  7. Year variable present
- Saves processed data to `data/nsch/{year}/processed.feather`
- Generates validation report: `data/nsch/{year}/validation_report.txt`

**Output:**
```
NSCH Data Validation - Year 2023
=================================
✓ HHID variable present
✓ Record count: 55,162
✓ Column count: 895
✓ No empty columns
✓ Data types valid
✓ HHID complete (no missing)
✓ Year variable: YEAR

VALIDATION PASSED: 7/7 checks successful
```

### Step 3: Metadata Loading

Loads variable definitions and value labels into database.

```bash
python pipelines/python/nsch/load_nsch_metadata.py --year 2023
```

**What it does:**
- Reads `data/nsch/{year}/metadata.json`
- Inserts into `nsch_variables` table (variable definitions)
- Inserts into `nsch_value_labels` table (value label mappings)
- Validates insertion counts

**Output:**
```
Loading NSCH 2023 metadata...
Variables loaded: 895
Value labels loaded: 4,812
Metadata insertion complete
```

**Options:**
```bash
# Append to existing metadata (default: replace)
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --mode append

# Custom database path
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --database path/to/custom.duckdb

# Verbose logging
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --verbose
```

### Step 4: Raw Data Insertion

Inserts survey data into year-specific database table.

```bash
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

**What it does:**
- Reads `data/nsch/{year}/processed.feather`
- Creates table `nsch_{year}_raw` if not exists
- Inserts data in chunks (10,000 rows per chunk)
- Validates row counts and data integrity
- Reports insertion statistics

**Output:**
```
Inserting NSCH 2023 data...
Table: nsch_2023_raw
Records: 55,162
Columns: 895
Chunk size: 10,000
Progress: [====] 100% (6/6 chunks)
Insertion complete: 55,162 rows in 9.5 seconds
```

**Options:**
```bash
# Custom database path
python pipelines/python/nsch/insert_nsch_database.py --year 2023 --database path/to/custom.duckdb

# Verbose logging
python pipelines/python/nsch/insert_nsch_database.py --year 2023 --verbose
```

---

## Batch Processing (All Years)

Process multiple years at once using the batch processing script.

### Process All Years

```bash
python scripts/nsch/process_all_years.py --years all
```

**Processes:** All years 2016-2023 (8 years)

### Process Year Range

```bash
# Process 2020-2023
python scripts/nsch/process_all_years.py --years 2020-2023
```

### Process Specific Years

```bash
# Process only 2016, 2020, and 2023
python scripts/nsch/process_all_years.py --years 2016,2020,2023
```

### Skip R Validation (Not Recommended)

```bash
# Skip validation step (faster but less safe)
python scripts/nsch/process_all_years.py --years all --skip-validation
```

**Warning:** Skipping validation is not recommended. The R validation step:
- Ensures data quality
- Creates the `processed.feather` file needed for database insertion
- Takes only 2-5 seconds per year

### Batch Output

```
======================================================================
NSCH BATCH PROCESSING
======================================================================
Started: 2025-10-03 14:47:42
Years to process: [2017, 2018, 2019, 2020, 2021, 2022]
Database: data/duckdb/kidsights_local.duckdb
======================================================================

[VERIFY] Checking SPSS files...
  [OK] 2017: 2017 NSCH_Topical_CAHMI_DRCv2.sav
  [OK] 2018: 2018 NSCH_Topical_DRC_v2.sav
  ...

======================================================================
PROCESSING YEAR: 2017
======================================================================
  [STEP 1/4] SPSS to Feather conversion... [OK]
  [STEP 2/4] R validation... [OK]
  [STEP 3/4] Metadata loading... [OK]
  [STEP 4/4] Raw data insertion... [OK]

[SUCCESS] Year 2017 processed in 15.9 seconds

...

======================================================================
BATCH PROCESSING SUMMARY
======================================================================
Total Years Processed: 6
Successful: 6
Failed: 0
Total Time: 117.0 seconds (2.0 minutes)

[SUCCESS] All years processed successfully!
```

---

## CLI Reference

### load_nsch_spss.py

**Purpose:** Convert SPSS files to Feather format

```bash
python pipelines/python/nsch/load_nsch_spss.py --year YEAR [--overwrite] [--validate-only]
```

**Arguments:**
- `--year` (required): Survey year (2016-2023)
- `--overwrite`: Overwrite existing Feather/metadata files
- `--validate-only`: Only validate existing Feather file (skip conversion)

**Examples:**
```bash
# Convert 2023 SPSS to Feather
python pipelines/python/nsch/load_nsch_spss.py --year 2023

# Overwrite existing files
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite

# Validate existing Feather
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --validate-only
```

### run_nsch_pipeline.R

**Purpose:** Validate data quality with R

```bash
Rscript pipelines/orchestration/run_nsch_pipeline.R --year YEAR
```

**Arguments:**
- `--year` (required): Survey year (2016-2023)

**Examples:**
```bash
# Validate 2023 data
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nsch_pipeline.R --year 2023
```

### load_nsch_metadata.py

**Purpose:** Load metadata into database

```bash
python pipelines/python/nsch/load_nsch_metadata.py --year YEAR [OPTIONS]
```

**Arguments:**
- `--year` (required): Survey year (2016-2023)
- `--mode`: Insert mode - 'replace' (default) or 'append'
- `--database`: Database path (default: data/duckdb/kidsights_local.duckdb)
- `--verbose`: Enable verbose logging

**Examples:**
```bash
# Load 2023 metadata (replace existing)
python pipelines/python/nsch/load_nsch_metadata.py --year 2023

# Append to existing metadata
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --mode append

# Custom database path
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --database custom.duckdb

# Verbose output
python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --verbose
```

### insert_nsch_database.py

**Purpose:** Insert raw data into database

```bash
python pipelines/python/nsch/insert_nsch_database.py --year YEAR [OPTIONS]
```

**Arguments:**
- `--year` (required): Survey year (2016-2023)
- `--database`: Database path (default: data/duckdb/kidsights_local.duckdb)
- `--verbose`: Enable verbose logging

**Examples:**
```bash
# Insert 2023 data
python pipelines/python/nsch/insert_nsch_database.py --year 2023

# Custom database
python pipelines/python/nsch/insert_nsch_database.py --year 2023 --database custom.duckdb

# Verbose output
python pipelines/python/nsch/insert_nsch_database.py --year 2023 --verbose
```

### process_all_years.py

**Purpose:** Batch process multiple years

```bash
python scripts/nsch/process_all_years.py --years YEARS [OPTIONS]
```

**Arguments:**
- `--years` (required): Years to process
  - "all": All years 2016-2023
  - "YYYY-YYYY": Year range (e.g., "2020-2023")
  - "YYYY,YYYY,...": Comma-separated years (e.g., "2016,2020,2023")
- `--skip-validation`: Skip R validation step (not recommended)
- `--database`: Database path (default: data/duckdb/kidsights_local.duckdb)
- `--verbose`: Enable verbose logging

**Examples:**
```bash
# Process all years
python scripts/nsch/process_all_years.py --years all

# Process 2020-2023
python scripts/nsch/process_all_years.py --years 2020-2023

# Process specific years
python scripts/nsch/process_all_years.py --years 2017,2019,2021

# Skip validation (not recommended)
python scripts/nsch/process_all_years.py --years 2023 --skip-validation
```

### generate_db_summary.py

**Purpose:** Generate database summary report

```bash
python scripts/nsch/generate_db_summary.py [OPTIONS]
```

**Arguments:**
- `--database`: Database path (default: data/duckdb/kidsights_local.duckdb)
- `--output`: Output file path (default: print to console)

**Examples:**
```bash
# Print summary to console
python scripts/nsch/generate_db_summary.py

# Save to file
python scripts/nsch/generate_db_summary.py --output docs/nsch/database_summary.txt

# Custom database
python scripts/nsch/generate_db_summary.py --database custom.duckdb
```

### test_db_roundtrip.py

**Purpose:** Test data integrity (round-trip validation)

```bash
python scripts/nsch/test_db_roundtrip.py [OPTIONS]
```

**Arguments:**
- `--year`: Survey year to test (default: 2023)
- `--database`: Database path (default: data/duckdb/kidsights_local.duckdb)

**Examples:**
```bash
# Test 2023 data
python scripts/nsch/test_db_roundtrip.py --year 2023

# Test custom database
python scripts/nsch/test_db_roundtrip.py --year 2023 --database custom.duckdb
```

---

## Data Access

### Python (DuckDB)

```python
import duckdb
import pandas as pd

# Connect to database
conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Query data
df = conn.execute("""
    SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS >= 10 AND SC_AGE_YEARS <= 17
    LIMIT 100
""").fetchdf()

print(df.head())

# Close connection
conn.close()
```

### R (DuckDB)

```r
library(duckdb)

# Connect to database
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Query data
df <- dbGetQuery(conn, "
  SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX
  FROM nsch_2023_raw
  WHERE SC_AGE_YEARS >= 10 AND SC_AGE_YEARS <= 17
  LIMIT 100
")

head(df)

# Close connection
dbDisconnect(conn, shutdown = TRUE)
```

### Direct Feather Access (Python)

```python
import pandas as pd

# Read Feather file directly (faster for single-year analysis)
df = pd.read_feather('data/nsch/2023/processed.feather')

print(df.info())
print(df.head())
```

### Direct Feather Access (R)

```r
library(arrow)

# Read Feather file
df <- read_feather('data/nsch/2023/processed.feather')

str(df)
head(df)
```

---

## Common Workflows

### Workflow 1: Add a New Year

When a new NSCH year is released:

```bash
# 1. Download SPSS file to data/nsch/spss/

# 2. Create year directory
mkdir -p data/nsch/2024

# 3. Update YEAR_TO_FILE mapping in scripts
# Edit: pipelines/python/nsch/load_nsch_spss.py
# Add: 2024: "NSCH_2024e_Topical_CAHMI_DRC.sav"

# 4. Process the new year
python scripts/nsch/process_all_years.py --years 2024

# 5. Verify data loaded
python scripts/nsch/generate_db_summary.py
```

### Workflow 2: Reprocess a Single Year

If data needs to be refreshed:

```bash
# Run full pipeline for one year
python scripts/nsch/process_all_years.py --years 2023
```

This will:
- Overwrite existing Feather files
- Replace metadata (mode=replace)
- Replace raw data table

### Workflow 3: Export Data for Analysis

```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Export to CSV
conn.execute("""
    COPY (
        SELECT * FROM nsch_2023_raw
        WHERE SC_AGE_YEARS <= 5
    ) TO 'output/nsch_2023_ages_0_5.csv' (HEADER, DELIMITER ',')
""")

# Export to Parquet
conn.execute("""
    COPY (SELECT * FROM nsch_2023_raw)
    TO 'output/nsch_2023_full.parquet' (FORMAT PARQUET)
""")

conn.close()
```

### Workflow 4: Query Metadata

```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Find all ACE-related variables in 2023
ace_vars = conn.execute("""
    SELECT variable_name, variable_label
    FROM nsch_variables
    WHERE year = 2023
      AND (
          LOWER(variable_label) LIKE '%ace%'
          OR LOWER(variable_label) LIKE '%adverse%'
      )
    ORDER BY variable_name
""").fetchdf()

print(ace_vars)

conn.close()
```

### Workflow 5: Cross-Year Comparison

```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Compare record counts across years
summary = conn.execute("""
    SELECT
        2017 AS year, COUNT(*) AS records FROM nsch_2017_raw
    UNION ALL
    SELECT 2018, COUNT(*) FROM nsch_2018_raw
    UNION ALL
    SELECT 2019, COUNT(*) FROM nsch_2019_raw
    UNION ALL
    SELECT 2020, COUNT(*) FROM nsch_2020_raw
    UNION ALL
    SELECT 2021, COUNT(*) FROM nsch_2021_raw
    UNION ALL
    SELECT 2022, COUNT(*) FROM nsch_2022_raw
    UNION ALL
    SELECT 2023, COUNT(*) FROM nsch_2023_raw
    ORDER BY year
""").fetchdf()

print(summary)

conn.close()
```

---

## Troubleshooting

### Issue: "SPSS file not found"

**Error:**
```
FileNotFoundError: SPSS file not found: data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav
```

**Solution:**
1. Verify SPSS file is in `data/nsch/spss/` directory
2. Check filename matches exactly (case-sensitive)
3. Ensure file has `.sav` extension

### Issue: "Feather file not found" during database insertion

**Error:**
```
FileNotFoundError: Processed Feather file not found: data/nsch/2023/processed.feather
```

**Solution:**
Run R validation step first:
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nsch_pipeline.R --year 2023
```

The R validation creates the `processed.feather` file needed for database insertion.

### Issue: Database locked

**Error:**
```
duckdb.IOException: Could not set lock on file
```

**Solution:**
1. Close any open connections to the database
2. Check no other processes are using the database file
3. In Python, always use `conn.close()`
4. In R, use `dbDisconnect(conn, shutdown = TRUE)`

### Issue: Memory error during processing

**Error:**
```
MemoryError: Unable to allocate array
```

**Solution:**
1. Process years individually instead of batch
2. Close other applications
3. Increase system RAM if possible
4. The pipeline uses chunked processing to minimize memory usage

### Issue: R package not found

**Error:**
```
Error in library(haven): there is no package called 'haven'
```

**Solution:**
```r
install.packages("haven")
```

For more troubleshooting, see [troubleshooting.md](troubleshooting.md).

---

**Next Steps:**
- See [example_queries.md](example_queries.md) for query patterns
- Read [database_schema.md](database_schema.md) for schema details
- Check [troubleshooting.md](troubleshooting.md) for common issues
