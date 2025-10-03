# ACS Data Pipeline Documentation

**Complete documentation for the American Community Survey (ACS) data extraction and metadata system.**

---

## Overview

The ACS pipeline extracts census data from IPUMS USA for statistical raking of Kidsights survey data. It features intelligent caching, R validation, and a comprehensive metadata system for transformations and harmonization.

### Key Features

- **Multi-State Extraction:** Query any U.S. state via IPUMS API
- **Smart Caching:** SHA256-based content addressing (~10 sec cache hits vs 45+ min API)
- **Metadata System:** DDI-based metadata with 42 variables, 1,144 value labels
- **Harmonization Tools:** Map IPUMS categories to NE25 survey categories
- **Hybrid Architecture:** Python (API/database) + R (validation/statistics)
- **DuckDB Storage:** Fast local database with multi-state support

### Current Database Status

- **States:** Nebraska, Minnesota
- **Records:** 24,449 children ages 0-5
- **Variables:** 42 (demographics, education, income, geography)
- **Metadata:** 1,144 value labels from 2 DDI files
- **Tables:** `acs_raw`, `acs_variables`, `acs_value_labels`, `acs_metadata_registry`

---

## Quick Start

### Step 1: Extract ACS Data

```bash
python pipelines/python/acs/extract_acs_data.py \
    --state nebraska \
    --year-range 2019-2023
```

### Step 2: Validate in R

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
    pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31
```

### Step 3: Insert to Database

```bash
python pipelines/python/acs/insert_acs_database.py \
    --state nebraska \
    --year-range 2019-2023
```

### Step 4: Query Metadata

**Python:**
```python
from python.db.connection import DatabaseManager
from python.acs.metadata_utils import decode_value

db = DatabaseManager()
state_name = decode_value('STATEFIP', 31, db)  # "Nebraska"
```

**R:**
```r
source("R/utils/acs/acs_metadata.R")
state_name <- acs_decode_value("STATEFIP", 31)  # "Nebraska"
```

---

## Documentation Index

### Core Pipeline Documentation

#### 1. [Pipeline Usage Guide](pipeline_usage.md)
Complete guide to using the ACS extraction and processing pipeline.

- **Topics:** Configuration, extraction, validation, database insertion, caching
- **Audience:** Users running the pipeline
- **Last Updated:** 2025-10-03

#### 2. [IPUMS Variables Reference](ipums_variables_reference.md)
Reference documentation for all IPUMS USA variables in the dataset.

- **Topics:** Variable definitions, IPUMS coding, raw values
- **Audience:** Analysts working with ACS data
- **Format:** Variable-by-variable reference with IPUMS URLs

#### 3. [Testing Guide](testing_guide.md)
Guide for testing and validating the ACS pipeline.

- **Topics:** API connection tests, end-to-end pipeline tests, troubleshooting
- **Audience:** Developers and QA
- **Last Updated:** 2025-10-03

### Metadata System Documentation

#### 4. [Metadata Query Cookbook](metadata_query_cookbook.md)
Practical examples for querying and using ACS metadata in Python and R.

- **Topics:** Variable queries, value decoding, harmonization, quality checks
- **Audience:** Analysts and developers using metadata
- **Format:** Copy-paste code examples with expected output
- **Sections:**
  - Getting Started (setup)
  - Basic Queries (variable info, summaries)
  - Value Label Decoding (single values, DataFrames)
  - Variable Discovery (search by keyword, type checking)
  - Data Transformation (harmonization examples)
  - Quality Checks (validation, missing values)
  - Advanced Patterns (analysis-ready datasets, batch processing)

#### 5. [Transformation Mappings](transformation_mappings.md)
Documentation of category harmonization between IPUMS ACS and NE25 survey data.

- **Topics:** Race/ethnicity, education, income (FPL) mappings
- **Audience:** Raking analysts, survey methodologists
- **Format:** Detailed mapping tables with transformation rules
- **Key Harmonizations:**
  - Race/Ethnicity: IPUMS RACE/HISPAN → 7 NE25 categories
  - Education: IPUMS EDUC → 8-cat and 4-cat versions
  - Income: IPUMS FTOTINC/FAMSIZE → FPL percentages

#### 6. [Data Dictionary](data_dictionary.html) / [Markdown](data_dictionary.md)
Auto-generated comprehensive data dictionary from DDI metadata.

- **Format:** HTML (styled) and Markdown
- **Topics:** All 42 variables with descriptions, value labels, types
- **Auto-Generated:** Run `scripts/acs/generate_data_dictionary.py` to regenerate

#### 7. [Metadata Implementation Plan](metadata_implementation_plan.md)
Historical document tracking the 3-phase metadata system implementation.

- **Status:** ✅ Completed - October 2025
- **Topics:** DDI parsing, database schema, transformation utilities, documentation
- **Audience:** Developers, project managers

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      ACS DATA PIPELINE                           │
└──────────────────────────────────────────────────────────────────┘

┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ IPUMS USA   │────▶│   Python     │────▶│   Feather    │
│   API       │     │  Extraction  │     │   Files      │
└─────────────┘     └──────────────┘     └──────────────┘
                           │                      │
                           ▼                      ▼
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
                                         │ (4 tables)   │
                                         └──────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    METADATA SYSTEM                               │
└──────────────────────────────────────────────────────────────────┘

┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ IPUMS DDI   │────▶│   Python     │────▶│   DuckDB     │
│   XML       │     │  DDI Parser  │     │   Tables     │
└─────────────┘     └──────────────┘     └──────────────┘
                                                │
                    ┌───────────────────────────┴───────────┐
                    ▼                                       ▼
            ┌──────────────┐                       ┌──────────────┐
            │   Python     │                       │      R       │
            │  Utilities   │                       │  Utilities   │
            └──────────────┘                       └──────────────┘
                    │                                       │
                    └───────────────────────────────────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │ Harmonization│
                              │  NE25 ↔ ACS  │
                              └──────────────┘
```

---

## Common Workflows

### Workflow 1: Add New State

```bash
# 1. Create state configuration (if not exists)
# Copy config/acs/states/nebraska_2019-2023.yaml
# Update state name, FIPS code, output directory

# 2. Extract data
python pipelines/python/acs/extract_acs_data.py --state iowa --year-range 2019-2023

# 3. Validate
Rscript pipelines/orchestration/run_acs_pipeline.R --state iowa --year-range 2019-2023 --state-fip 19

# 4. Insert to database
python pipelines/python/acs/insert_acs_database.py --state iowa --year-range 2019-2023 --mode append
```

### Workflow 2: Query and Decode Data

**Python:**
```python
from python.db.connection import DatabaseManager
from python.acs.metadata_utils import decode_dataframe

db = DatabaseManager()

# Load data
with db.get_connection() as conn:
    df = conn.execute("SELECT * FROM acs_raw WHERE state = 'nebraska' LIMIT 100").df()

# Decode categorical variables
df_decoded = decode_dataframe(df, ['STATEFIP', 'SEX', 'RACE'], db)

# Now df has: STATEFIP_label, SEX_label, RACE_label
print(df_decoded[['STATEFIP', 'STATEFIP_label', 'SEX', 'SEX_label']].head())
```

**R:**
```r
source("R/utils/acs/acs_metadata.R")
library(duckdb)

# Load data
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)
df <- dbGetQuery(conn, "SELECT * FROM acs_raw WHERE state = 'nebraska' LIMIT 100")
dbDisconnect(conn)

# Decode columns
df <- acs_decode_column(df, "STATEFIP")
df <- acs_decode_column(df, "SEX")
df <- acs_decode_column(df, "RACE")

# Now df has: STATEFIP_label, SEX_label, RACE_label
print(head(df[, c("STATEFIP", "STATEFIP_label", "SEX", "SEX_label")]))
```

### Workflow 3: Harmonize for Raking

```python
from python.acs.harmonization import harmonize_race_ethnicity, harmonize_education, harmonize_income_to_fpl

# Load Nebraska data
with db.get_connection() as conn:
    df = conn.execute("SELECT * FROM acs_raw WHERE state = 'nebraska'").df()

# Apply harmonizations
df['ne25_race'] = harmonize_race_ethnicity(df, 'RACE', 'HISPAN', db)
df['ne25_educ8'] = harmonize_education(df, 'EDUC', db, categories=8)
df['fpl_percent'] = harmonize_income_to_fpl(df, 'FTOTINC', 'FAMSIZE', year=2023)

# Check distributions
print(df['ne25_race'].value_counts())
print(df['ne25_educ8'].value_counts())
print(df['fpl_percent'].describe())
```

---

## File Locations

### Python Modules
- **`python/acs/metadata_parser.py`** - DDI XML parser
- **`python/acs/metadata_schema.py`** - Database schema definitions
- **`python/acs/metadata_utils.py`** - Query and decoding utilities
- **`python/acs/harmonization.py`** - Category harmonization tools
- **`python/acs/extract_builder.py`** - IPUMS extract configuration builder
- **`python/acs/extract_manager.py`** - API submission and download

### R Modules
- **`R/utils/acs/acs_metadata.R`** - Metadata query functions
- **`R/utils/acs/validate_acs_raw.R`** - Data validation functions
- **`R/load/acs/load_acs_data.R`** - Data loading utilities

### Executable Scripts
- **`pipelines/python/acs/extract_acs_data.py`** - Main extraction CLI
- **`pipelines/python/acs/insert_acs_database.py`** - Database insertion CLI
- **`pipelines/python/acs/load_acs_metadata.py`** - Metadata loader CLI
- **`pipelines/orchestration/run_acs_pipeline.R`** - R validation pipeline
- **`scripts/acs/generate_data_dictionary.py`** - Data dictionary generator
- **`scripts/acs/test_api_connection.py`** - API testing utility

### Configuration
- **`config/acs/base_template.yaml`** - Base extract configuration
- **`config/acs/states/*.yaml`** - State-specific configurations

### Output Files
- **`data/acs/{state}/{year_range}/raw.feather`** - Raw IPUMS data
- **`data/acs/{state}/{year_range}/processed.feather`** - Validated data
- **`data/acs/{state}/{year_range}/metadata.json`** - Extract metadata
- **`data/duckdb/kidsights_local.duckdb`** - Local database

---

## Getting Help

### Documentation Resources
- **IPUMS USA:** https://usa.ipums.org/usa/
- **ipumspy:** https://github.com/ipums/ipumspy
- **DuckDB:** https://duckdb.org/docs/
- **Arrow/Feather:** https://arrow.apache.org/docs/python/

### IPUMS Support
- **User Forum:** https://forum.ipums.org/
- **Email:** ipums@umn.edu

### Kidsights Data Platform
- **Project Documentation:** See `CLAUDE.md` in project root
- **Issues:** Report via project issue tracker

---

**Version:** 1.0.0
**Last Updated:** 2025-10-03
**Status:** Production Ready
