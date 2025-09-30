# ACS Data Pipeline - Usage Guide

**Purpose**: Complete guide to using the ACS data extraction and processing pipeline for statistical raking.

**Version**: 1.0.0
**Last Updated**: 2025-09-30

---

## Table of Contents

- [Pipeline Overview](#pipeline-overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Configuration Guide](#configuration-guide)
- [Usage Instructions](#usage-instructions)
- [Multi-State Workflows](#multi-state-workflows)
- [Caching System](#caching-system)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## Pipeline Overview

The ACS data pipeline extracts American Community Survey (ACS) data from the IPUMS USA API for statistical raking of Kidsights survey data.

### Key Features

- **Multi-state support**: Extract data for any U.S. state
- **Multi-year support**: Any ACS 5-year sample (2019-2023, etc.)
- **Intelligent caching**: SHA256-based content addressing (~10 sec cache hits vs 15-60 min API calls)
- **Raw IPUMS variables**: No harmonization or transformations applied
- **Attached characteristics**: Automatic parent-child linking (EDUC_mom, EDUC_pop)
- **Hybrid architecture**: Python (API, database) + R (validation, statistics)
- **DuckDB storage**: Fast local database with multi-state support

### Target Population

- **Age**: Children 0-5 years old
- **Geography**: State-level (Nebraska, Iowa, Kansas, etc.)
- **Sample**: ACS 5-year pooled estimates

### Data Uses

- Statistical raking/weighting for Kidsights survey data
- Population benchmarking by demographics, parent education, economics
- Geographic stratification (urban/rural, PUMA)

---

## Quick Start

### Prerequisites

```bash
# Python 3.13+
pip install ipumspy pandas pyarrow pyyaml structlog

# R 4.5.1+ with required packages
Rscript -e "install.packages(c('arrow', 'duckdb', 'dplyr', 'tidyr'))"

# IPUMS API key in C:/Users/waldmanm/my-APIs/IPUMS.txt
```

### Extract Nebraska 2019-2023 Data

```bash
# Step 1: Extract from IPUMS API (or cache)
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023

# Step 2: Validate and process in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
    pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31

# Step 3: Insert into DuckDB
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023
```

### Output Files

```
data/acs/nebraska/2019-2023/
├── raw.feather              # Raw IPUMS data from API
├── processed.feather        # Validated data ready for database
├── metadata.json            # Extract metadata (variables, filters, etc.)
└── validation_report.txt    # R validation results
```

### Database Query

```python
import duckdb
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Query Nebraska children ages 0-5
df = conn.execute("""
    SELECT * FROM acs_data
    WHERE state = 'nebraska' AND year_range = '2019-2023'
""").df()

print(f"Records: {len(df):,}")
```

---

## Architecture

### Hybrid Python-R Design

```
┌─────────────────────────────────────────────────────────────────┐
│                      ACS DATA PIPELINE                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ IPUMS USA    │────▶│   Python     │────▶│   Feather    │
│   API        │     │  Extraction  │     │   Files      │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                     │
                            ▼                     ▼
                     ┌──────────────┐     ┌──────────────┐
                     │  SHA256      │     │      R       │
                     │   Cache      │     │  Validation  │
                     └──────────────┘     └──────────────┘
                                                 │
                                                 ▼
                                          ┌──────────────┐
                                          │   Python     │
                                          │   Database   │
                                          └──────────────┘
                                                 │
                                                 ▼
                                          ┌──────────────┐
                                          │   DuckDB     │
                                          │ (acs_data)   │
                                          └──────────────┘
```

### Component Responsibilities

**Python Extraction** (`pipelines/python/acs/extract_acs_data.py`):
- IPUMS API authentication and requests
- Extract submission and download
- Intelligent caching (SHA256 signatures)
- Feather file conversion

**R Validation** (`pipelines/orchestration/run_acs_pipeline.R`):
- Data quality checks (age filters, state FIPS, critical variables)
- Attached characteristics validation
- Statistical summaries
- Validation report generation

**Python Database** (`pipelines/python/acs/insert_acs_database.py`):
- DuckDB connection management
- Table creation and indexing
- Multi-state data insertion
- Duplicate prevention

### Data Flow

1. **Configuration** → YAML file specifies state, years, variables
2. **Extract Signature** → SHA256 hash from config parameters
3. **Cache Check** → Look for existing extract with matching signature
4. **API Request** → Submit/download if no cache hit (15-60 min)
5. **Feather Conversion** → Python pandas → Feather file
6. **R Validation** → Quality checks and statistical summaries
7. **Database Insert** → Load into DuckDB (replace or append mode)

---

## Configuration Guide

### YAML Configuration Structure

All state/year configurations live in `config/acs/states/*.yaml`.

**Base Template** (`config/acs/base_template.yaml`):
```yaml
# IPUMS API settings
ipums:
  collection: "usa"
  api_key_file: "C:/Users/waldmanm/my-APIs/IPUMS.txt"

# Extract description
description: "ACS children ages 0-5 for statistical raking"

# Time period (5-year ACS sample)
samples:
  - "us2023b"  # 2019-2023 ACS

# Children ages 0-5
case_selections:
  AGE:
    general: [0, 1, 2, 3, 4, 5]

# Variables to extract
variables:
  - name: "YEAR"
  - name: "STATEFIP"
  - name: "SERIAL"
  - name: "PERNUM"
  - name: "HHWT"
  - name: "PERWT"
  - name: "AGE"
  - name: "SEX"
  - name: "RACE"
  - name: "HISPAN"
  - name: "EDUC"
    attach_characteristics: ["mother", "father"]  # Creates EDUC_mom, EDUC_pop
  # ... more variables
```

**State-Specific Config** (`config/acs/states/nebraska_2019-2023.yaml`):
```yaml
# Inherit from base template
extends: "config/acs/base_template.yaml"

# State-specific metadata
metadata:
  state: "nebraska"
  state_fip: 31
  year_range: "2019-2023"

# Override: Nebraska state filter
case_selections:
  STATEFIP:
    general: [31]

# Cache and output settings
cache:
  enabled: true
  directory: "data/acs/cache"

output:
  directory: "data/acs/nebraska/2019-2023"
  format: "feather"
```

### Configuration Inheritance

The pipeline uses **deep merging** for YAML inheritance:

1. Load base template
2. Load state-specific config
3. Deep merge (state overrides base)
4. Result: Complete extract configuration

**Example**: Nebraska config inherits all variables from base template but overrides `case_selections.STATEFIP` with Nebraska's FIPS code (31).

### Creating New State Configurations

**To add Iowa 2019-2023**:

```yaml
# config/acs/states/iowa_2019-2023.yaml
extends: "config/acs/base_template.yaml"

metadata:
  state: "iowa"
  state_fip: 19
  year_range: "2019-2023"

case_selections:
  STATEFIP:
    general: [19]  # Iowa FIPS code

cache:
  enabled: true
  directory: "data/acs/cache"

output:
  directory: "data/acs/iowa/2019-2023"
  format: "feather"
```

Then run:
```bash
python pipelines/python/acs/extract_acs_data.py --state iowa --year-range 2019-2023
```

### Variables and Attached Characteristics

**Parent Education Example**:

```yaml
variables:
  - name: "EDUC"
    attach_characteristics: ["mother", "father"]
  - name: "EDUCD"
    attach_characteristics: ["mother", "father"]
```

This creates **6 variables** in output:
- `EDUC` (child's own, typically N/A for ages 0-5)
- `EDUC_mom` (mother's education via MOMLOC)
- `EDUC_pop` (father's education via POPLOC)
- `EDUCD` (detailed version)
- `EDUCD_mom`
- `EDUCD_pop`

**Household Head Marital Status**:

```yaml
variables:
  - name: "MARST"
    attach_characteristics: ["head"]
```

Creates:
- `MARST` (child's own, always N/A)
- `MARST_head` (household head's marital status)

See [ipums_variables_reference.md](ipums_variables_reference.md) for complete variable list and IPUMS coding.

---

## Usage Instructions

### Python Extraction Script

**Command**: `python pipelines/python/acs/extract_acs_data.py`

**Required Arguments**:
- `--state`: State name (lowercase, e.g., `nebraska`, `iowa`, `kansas`)
- `--year-range`: Year range (e.g., `2019-2023`)

**Optional Arguments**:
- `--force-refresh`: Force new API request (ignore cache)
- `--no-cache`: Disable caching entirely
- `--output-dir`: Custom output directory (default: `data/acs/{state}/{year_range}`)
- `--verbose`: Enable verbose logging

**Examples**:

```bash
# Basic extraction (uses cache if available)
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023

# Force new API request
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --force-refresh

# Custom output directory
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --output-dir data/custom_output

# Verbose logging
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --verbose
```

**Output**:
```
====================================================================
ACS DATA EXTRACTION PIPELINE
====================================================================
Started: 2025-09-30 14:23:45
State: nebraska
Year Range: 2019-2023
Configuration: config/acs/states/nebraska_2019-2023.yaml

====================================================================
STEP 1: Load Configuration
====================================================================
✓ Configuration loaded
  Variables: 25
  Filters: AGE (0-5), STATEFIP (31)
  Attached Characteristics: EDUC, EDUCD, MARST

====================================================================
STEP 2: Create Output Directory
====================================================================
✓ Output directory created: data/acs/nebraska/2019-2023

====================================================================
STEP 3: Get or Submit Extract
====================================================================
Checking cache for existing extract...
✓ Cache hit! Found matching extract: abc123def456
✓ Data retrieved from cache (~10 sec)

====================================================================
STEP 4: Convert to Feather Format
====================================================================
Loading IPUMS data from: data/acs/cache/abc123def456/usa_00001.dat
✓ Data loaded: 45,234 rows, 30 columns
✓ Feather file written: data/acs/nebraska/2019-2023/raw.feather

====================================================================
STEP 5: Save Metadata
====================================================================
✓ Metadata saved: data/acs/nebraska/2019-2023/metadata.json

====================================================================
EXTRACTION SUMMARY
====================================================================
State: nebraska
Year Range: 2019-2023
Records: 45,234
Variables: 30
Cache Status: HIT
Extract ID: abc123def456
Output Files:
  - data/acs/nebraska/2019-2023/raw.feather
  - data/acs/nebraska/2019-2023/metadata.json
Elapsed Time: 12.34 seconds

====================================================================
✓ EXTRACTION COMPLETE
====================================================================
```

### R Validation Pipeline

**Command**: `Rscript pipelines/orchestration/run_acs_pipeline.R`

**Required Arguments**:
- `--state`: State name (must match extraction)
- `--year-range`: Year range (must match extraction)
- `--state-fip`: State FIPS code for validation

**Optional Arguments**:
- `--verbose`: Enable verbose output

**Examples**:

```bash
# Basic validation
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
    pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31

# Verbose mode
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
    pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31 \
    --verbose
```

**Output**:
```
====================================================================
ACS R VALIDATION PIPELINE
====================================================================
State: nebraska
Year Range: 2019-2023
State FIPS: 31

[STEP 1] Loading raw Feather data...
✓ Data loaded: 45,234 rows, 30 variables
  File: data/acs/nebraska/2019-2023/raw.feather

[STEP 2] Validating data quality...
✓ All expected variables present (30/30)
✓ Attached characteristics found: EDUC_mom, EDUC_pop, EDUCD_mom, EDUCD_pop, MARST_head
✓ Age filter applied correctly: 100% ages 0-5
✓ State filter applied correctly: 100% STATEFIP = 31
✓ No duplicate records (SERIAL + PERNUM)
✓ Sampling weights present: PERWT (0 missing), HHWT (0 missing)

[STEP 3] Writing validation report...
✓ Report saved: data/acs/nebraska/2019-2023/validation_report.txt

[STEP 4] Writing processed Feather file...
✓ Processed data saved: data/acs/nebraska/2019-2023/processed.feather

====================================================================
✓ VALIDATION COMPLETE
====================================================================
```

### Database Insertion Script

**Command**: `python pipelines/python/acs/insert_acs_database.py`

**Required Arguments**:
- `--state`: State name
- `--year-range`: Year range

**Optional Arguments**:
- `--mode`: Insert mode - `replace` (default) or `append`
- `--source`: Source file - `processed` (default) or `raw`
- `--database`: Database path (default: `data/duckdb/kidsights_local.duckdb`)
- `--verbose`: Enable verbose logging

**Examples**:

```bash
# Basic insertion (replace mode)
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023

# Append mode (add to existing data)
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023 \
    --mode append

# Custom database path
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023 \
    --database data/duckdb/custom.duckdb
```

**Replace vs Append Mode**:

- **Replace** (default): Deletes existing state/year data before inserting
  - Use when re-running pipeline for same state/year
  - Prevents duplicates
  - Safe for updates

- **Append**: Adds data without deleting
  - Use when adding new state or year range
  - Faster (no delete step)
  - Risk of duplicates if re-run (prevented by PRIMARY KEY constraint)

**Output**:
```
====================================================================
ACS DATABASE INSERTION PIPELINE
====================================================================
Started: 2025-09-30 14:45:12
State: nebraska
Year Range: 2019-2023
Mode: replace
Source: processed
Database: data/duckdb/kidsights_local.duckdb

====================================================================
STEP 1: Load Feather Data
====================================================================
✓ Feather data loaded
  Rows: 45,234
  Columns: 30
  File Size: 12.5 MB

====================================================================
STEP 2: Add Metadata Columns
====================================================================
✓ Added metadata columns: state, year_range

====================================================================
STEP 3: Connect to Database
====================================================================
✓ Connected to database: data/duckdb/kidsights_local.duckdb

====================================================================
STEP 4: Create Table and Indexes
====================================================================
✓ acs_data table created (or already exists)
✓ Indexes created

====================================================================
STEP 5: Insert Data
====================================================================
Deleting existing data (replace mode)...
✓ Existing data deleted: 45,120 rows
✓ Inserting data into acs_data: 45,234 rows
✓ Data inserted successfully

====================================================================
STEP 6: Gather Statistics
====================================================================

====================================================================
INSERTION SUMMARY
====================================================================
State: nebraska
Year Range: 2019-2023
Mode: replace
Rows Inserted: 45,234
Rows Deleted (replaced): 45,120
Total Rows (this state/year): 45,234
Total Rows (all data): 45,234
Distinct States: 1
Distinct Year Ranges: 1
Variables Stored: 32
Age Distribution: {0: 7523, 1: 7612, 2: 7589, 3: 7498, 4: 7501, 5: 7511}
Database: data/duckdb/kidsights_local.duckdb
Elapsed Time: 3.45 seconds

====================================================================
✓ INSERTION COMPLETE
====================================================================
```

---

## Multi-State Workflows

### Adding Multiple States

**Goal**: Extract ACS data for Nebraska, Iowa, and Kansas.

**Step 1: Create state configurations** (if not exists):

```bash
# Already exists: config/acs/states/nebraska_2019-2023.yaml

# Create Iowa config
cat > config/acs/states/iowa_2019-2023.yaml << 'EOF'
extends: "config/acs/base_template.yaml"

metadata:
  state: "iowa"
  state_fip: 19
  year_range: "2019-2023"

case_selections:
  STATEFIP:
    general: [19]

cache:
  enabled: true
  directory: "data/acs/cache"

output:
  directory: "data/acs/iowa/2019-2023"
  format: "feather"
EOF

# Create Kansas config
cat > config/acs/states/kansas_2019-2023.yaml << 'EOF'
extends: "config/acs/base_template.yaml"

metadata:
  state: "kansas"
  state_fip: 20
  year_range: "2019-2023"

case_selections:
  STATEFIP:
    general: [20]

cache:
  enabled: true
  directory: "data/acs/cache"

output:
  directory: "data/acs/kansas/2019-2023"
  format: "feather"
EOF
```

**Step 2: Extract data for each state**:

```bash
# Extract Nebraska
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
Rscript pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023

# Extract Iowa
python pipelines/python/acs/extract_acs_data.py --state iowa --year-range 2019-2023
Rscript pipelines/orchestration/run_acs_pipeline.R --state iowa --year-range 2019-2023 --state-fip 19
python pipelines/python/acs/insert_acs_database.py --state iowa --year-range 2019-2023 --mode append

# Extract Kansas
python pipelines/python/acs/extract_acs_data.py --state kansas --year-range 2019-2023
Rscript pipelines/orchestration/run_acs_pipeline.R --state kansas --year-range 2019-2023 --state-fip 20
python pipelines/python/acs/insert_acs_database.py --state kansas --year-range 2019-2023 --mode append
```

**Step 3: Query multi-state data**:

```python
import duckdb
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# All three states
df = conn.execute("""
    SELECT state, year_range, COUNT(*) as children
    FROM acs_data
    GROUP BY state, year_range
    ORDER BY state
""").df()

print(df)
#        state year_range  children
# 0       iowa  2019-2023     42312
# 1     kansas  2019-2023     39847
# 2   nebraska  2019-2023     45234
```

### Multi-Year Extraction

**Goal**: Extract Nebraska data for both 2019-2023 and 2014-2018.

**Step 1: Create config for 2014-2018**:

```yaml
# config/acs/states/nebraska_2014-2018.yaml
extends: "config/acs/base_template.yaml"

metadata:
  state: "nebraska"
  state_fip: 31
  year_range: "2014-2018"

samples:
  - "us2018b"  # 2014-2018 ACS 5-year sample

case_selections:
  STATEFIP:
    general: [31]

cache:
  enabled: true
  directory: "data/acs/cache"

output:
  directory: "data/acs/nebraska/2014-2018"
  format: "feather"
```

**Step 2: Extract both time periods**:

```bash
# 2019-2023 (already done)
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
# ... R validation and database insertion

# 2014-2018 (new)
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2014-2018
Rscript pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2014-2018 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2014-2018 --mode append
```

**Step 3: Query time trends**:

```python
df = conn.execute("""
    SELECT
        state,
        year_range,
        AVG(PERWT) as avg_weight,
        COUNT(*) as children
    FROM acs_data
    WHERE state = 'nebraska'
    GROUP BY state, year_range
    ORDER BY year_range
""").df()

print(df)
#        state  year_range  avg_weight  children
# 0  nebraska  2014-2018     1234.5     43891
# 1  nebraska  2019-2023     1289.3     45234
```

---

## Caching System

### How Caching Works

The pipeline uses **SHA256 content-addressed caching** to avoid redundant IPUMS API requests.

**Cache Signature Generation**:
1. Extract configuration parameters (state FIPS, year, variables, filters, attached characteristics)
2. Serialize to canonical JSON representation
3. Compute SHA256 hash
4. Use hash as cache directory name

**Cache Lookup**:
1. Generate signature from current request
2. Check `data/acs/cache/{signature}/` exists
3. If exists → load from cache (~10 sec)
4. If not exists → submit to IPUMS API (15-60 min) → save to cache

**Example**:

```bash
# First request: Nebraska 2019-2023
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
# ✓ New extract submitted to IPUMS API
# ✓ Extract ID: 123456
# ✓ Download time: 45 minutes
# ✓ Saved to cache: data/acs/cache/abc123def456.../

# Second request: Same parameters
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
# ✓ Cache hit! Found matching extract: abc123def456
# ✓ Retrieved from cache in 8 seconds
```

### Cache Management

**View cache contents**:

```bash
ls data/acs/cache/
# abc123def456789abcdef0123456789abcdef0123456789abcdef0123456789/
# def456789abcdef0123456789abcdef0123456789abcdef0123456789abc123/
```

**Force cache refresh**:

```bash
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --force-refresh
```

**Disable caching**:

```bash
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --no-cache
```

**Clear cache manually**:

```bash
# Remove all cached extracts
rm -rf data/acs/cache/*

# Remove specific extract
rm -rf data/acs/cache/abc123def456.../
```

### Cache Invalidation

Cache is automatically invalidated when:
- Variables list changes
- Filters change (age range, state FIPS)
- Attached characteristics change
- Sample year changes
- Data format changes

**Example**: Adding new variable invalidates cache:

```yaml
# Original config
variables:
  - name: "EDUC"

# Modified config (adds EDUCD)
variables:
  - name: "EDUC"
  - name: "EDUCD"  # NEW - cache invalidated
```

---

## Troubleshooting

### Common Issues

#### 1. IPUMS API Key Not Found

**Error**:
```
FileNotFoundError: API key file not found: C:/Users/waldmanm/my-APIs/IPUMS.txt
```

**Solution**:
```bash
# Create file with your IPUMS API key
echo "your_api_key_here" > C:/Users/waldmanm/my-APIs/IPUMS.txt

# Verify
cat C:/Users/waldmanm/my-APIs/IPUMS.txt
```

#### 2. IPUMS API Authentication Failed

**Error**:
```
IpumsApiException: 401 Unauthorized
```

**Solution**:
1. Verify API key is correct: https://account.ipums.org/api_keys
2. Check API key file has no extra whitespace
3. Regenerate API key if needed

#### 3. Configuration File Not Found

**Error**:
```
FileNotFoundError: Configuration not found: config/acs/states/nebraska_2019-2023.yaml
```

**Solution**:
```bash
# Verify state name matches filename exactly
ls config/acs/states/

# Create missing config (see Configuration Guide above)
```

#### 4. Feather File Not Found (R Pipeline)

**Error**:
```
Error: File does not exist: data/acs/nebraska/2019-2023/raw.feather
```

**Solution**:
```bash
# Run Python extraction first
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023

# Then run R pipeline
Rscript pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31
```

#### 5. Database Primary Key Violation

**Error**:
```
duckdb.ConstraintException: PRIMARY KEY constraint violated: (state, year_range, SERIAL, PERNUM)
```

**Solution**:
```bash
# Use replace mode to update existing data
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023 \
    --mode replace  # Delete existing first
```

#### 6. R Package Not Installed

**Error**:
```
Error: package 'arrow' is not installed
```

**Solution**:
```r
# Install missing packages
install.packages(c("arrow", "duckdb", "dplyr", "tidyr"))
```

#### 7. IPUMS Extract Failed

**Error**:
```
IpumsApiException: Extract failed with status: failed
```

**Solution**:
1. Check IPUMS system status: https://status.ipums.org/
2. Verify variable names are valid: https://usa.ipums.org/usa-action/variables/group
3. Check sample availability (some variables not in all years)
4. Review IPUMS error message in logs
5. Contact IPUMS support if persistent: ipums@umn.edu

#### 8. Attached Characteristics Missing

**Error (R validation)**:
```
[FAIL] Missing attached characteristics: EDUC_mom, EDUC_pop
```

**Solution**:

Verify config has attach_characteristics:

```yaml
variables:
  - name: "EDUC"
    attach_characteristics: ["mother", "father"]  # Required!
```

Re-run extraction:
```bash
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --force-refresh  # Force new extract
```

### Logging and Debugging

**Enable verbose logging**:

```bash
# Python extraction
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023 \
    --verbose

# R validation
Rscript pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31 \
    --verbose

# Database insertion
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023 \
    --verbose
```

**Check validation report**:

```bash
cat data/acs/nebraska/2019-2023/validation_report.txt
```

**Inspect metadata**:

```bash
cat data/acs/nebraska/2019-2023/metadata.json | python -m json.tool
```

**Query database directly**:

```python
import duckdb
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Check table exists
tables = conn.execute("SHOW TABLES").df()
print(tables)

# Check record count
count = conn.execute("SELECT COUNT(*) FROM acs_data").fetchone()[0]
print(f"Records: {count:,}")

# Check for specific state/year
df = conn.execute("""
    SELECT COUNT(*) as count
    FROM acs_data
    WHERE state = 'nebraska' AND year_range = '2019-2023'
""").df()
print(df)
```

### Getting Help

**Documentation**:
- IPUMS USA: https://usa.ipums.org/usa/
- ipumspy: https://github.com/ipums/ipumspy
- DuckDB: https://duckdb.org/docs/
- Arrow/Feather: https://arrow.apache.org/docs/python/

**IPUMS Support**:
- User Forum: https://forum.ipums.org/
- Email: ipums@umn.edu

**Kidsights Data Platform**:
- See `CLAUDE.md` for development guidelines
- Check `docs/acs/ipums_variables_reference.md` for variable details

---

## Advanced Usage

### Custom Variable Selection

**Goal**: Extract only core demographics + parent education.

```yaml
# config/acs/states/nebraska_minimal.yaml
extends: "config/acs/base_template.yaml"

metadata:
  state: "nebraska"
  state_fip: 31
  year_range: "2019-2023"

# Override: minimal variable set
variables:
  - name: "YEAR"
  - name: "SERIAL"
  - name: "PERNUM"
  - name: "HHWT"
  - name: "PERWT"
  - name: "AGE"
  - name: "SEX"
  - name: "RACE"
  - name: "HISPAN"
  - name: "EDUC"
    attach_characteristics: ["mother", "father"]
```

### R Data Loading

**Load ACS data directly in R**:

```r
# Source loading functions
source("R/load/acs/load_acs_data.R")

# Load Nebraska data
ne_data <- load_acs_feather(
  state = "nebraska",
  year_range = "2019-2023",
  add_metadata = TRUE,
  validate = TRUE
)

# Check structure
str(ne_data)
summary(ne_data$AGE)
table(ne_data$EDUC_mom)

# List all available extracts
available <- list_available_acs_extracts()
print(available)
```

### Python Data Loading

**Load from Feather in Python**:

```python
import pandas as pd

# Load raw data
df = pd.read_feather("data/acs/nebraska/2019-2023/raw.feather")

print(f"Records: {len(df):,}")
print(f"Variables: {len(df.columns)}")
print(df.head())

# Age distribution
print(df['AGE'].value_counts().sort_index())

# Mother's education
print(df['EDUC_mom'].value_counts())
```

### Database Queries

**Statistical raking preparation**:

```python
import duckdb
import pandas as pd

conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Create raking margins for Nebraska
df = conn.execute("""
    SELECT
        AGE,
        SEX,
        CASE
            WHEN HISPAN > 0 THEN 'Hispanic'
            WHEN RACE = 1 THEN 'White Non-Hispanic'
            WHEN RACE = 2 THEN 'Black Non-Hispanic'
            ELSE 'Other'
        END as race_ethnicity,
        CASE
            WHEN EDUC_mom >= 10 THEN 'Bachelors+'
            WHEN EDUC_mom >= 7 THEN 'HS Grad'
            ELSE 'Less than HS'
        END as parent_education,
        SUM(PERWT) as population
    FROM acs_data
    WHERE state = 'nebraska' AND year_range = '2019-2023'
    GROUP BY AGE, SEX, race_ethnicity, parent_education
    ORDER BY AGE, SEX, race_ethnicity, parent_education
""").df()

# Export for raking software
df.to_csv("data/raking/nebraska_margins.csv", index=False)
```

**Geographic analysis**:

```python
# Urban vs rural distribution by age
df = conn.execute("""
    SELECT
        AGE,
        CASE
            WHEN METRO IN (2, 3, 4) THEN 'Metro'
            WHEN METRO = 1 THEN 'Non-Metro'
            ELSE 'Unknown'
        END as metro_status,
        COUNT(*) as children,
        SUM(PERWT) as weighted_population
    FROM acs_data
    WHERE state = 'nebraska' AND year_range = '2019-2023'
    GROUP BY AGE, metro_status
    ORDER BY AGE, metro_status
""").df()

print(df)
```

---

**For variable definitions and IPUMS coding**, see [ipums_variables_reference.md](ipums_variables_reference.md)

**Last Updated**: 2025-09-30
**Pipeline Version**: 1.0.0
