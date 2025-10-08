# Directory Structure

**Last Updated:** October 2025

This document provides a comprehensive guide to the Kidsights Data Platform directory structure, organized by pipeline and functional area.

---

## Table of Contents

1. [Overview](#overview)
2. [Core Directories (NE25 Pipeline)](#core-directories-ne25-pipeline)
3. [ACS Pipeline Directories](#acs-pipeline-directories)
4. [NHIS Pipeline Directories](#nhis-pipeline-directories)
5. [NSCH Pipeline Directories](#nsch-pipeline-directories)
6. [Imputation Pipeline Directories](#imputation-pipeline-directories)
7. [Shared Directories](#shared-directories)
8. [Data Storage](#data-storage)
9. [Quick Navigation](#quick-navigation)

---

## Overview

The Kidsights Data Platform uses a **modular directory structure** that separates concerns by:
- **Pipeline:** Each pipeline (NE25, ACS, NHIS, NSCH) has dedicated directories
- **Language:** Python and R code are organized separately
- **Function:** Extract, transform, load, validate, and utility functions are grouped logically

**Key Principles:**
- **Pipeline independence:** Each pipeline can function standalone
- **Hybrid R-Python:** R for data science, Python for database operations
- **Configuration-driven:** YAML configs control pipeline behavior
- **Documentation co-located:** Each pipeline has its own docs/ subdirectory

---

## Core Directories (NE25 Pipeline)

The NE25 pipeline processes REDCap survey data from the Nebraska 2025 study.

### `/python/`
**Purpose:** Core Python modules for database operations

**Key Files:**
- `db/connection.py` - DatabaseManager class for DuckDB connections
- `db/operations.py` - High-level database operations (insert, export, validate)
- `db/config.py` - Configuration loading utilities
- `db/query_geo_crosswalk.py` - Geographic crosswalk queries
- `utils/r_executor.py` - Safe R script execution (avoids segfaults)
- `utils/logging.py` - Structured logging utilities
- `imputation/config.py` - Imputation configuration loader
- `imputation/helpers.py` - Helper functions for multiple imputation workflows

**Why Python?** Eliminates R DuckDB segmentation faults by handling all database I/O in Python.

### `/python/imputation/`
**Purpose:** Multiple imputation system for geographic uncertainty

**Key Files:**
- `config.py` - Load imputation configuration from YAML (M, random seed, variables)
- `helpers.py` - Helper functions for retrieving completed datasets
  - `get_completed_dataset(m)` - Retrieve single imputation with LEFT JOIN + COALESCE
  - `get_all_imputations()` - Long format across all M imputations
  - `get_imputation_metadata()` - Variable metadata
  - `validate_imputations()` - Validation checks

**Design Philosophy:** Single source of truth - R calls Python via reticulate to avoid code duplication.

### `/pipelines/python/`
**Purpose:** Executable Python scripts that orchestrate pipeline steps

**Key Files:**
- `init_database.py` - Initialize DuckDB database schema
- `insert_raw_data.py` - Load raw REDCap data from Feather files
- `insert_transformed_data.py` - Load transformed data from Feather files
- `load_geo_crosswalks_sql.py` - Load geographic crosswalk reference tables

**Usage:** Called by main pipeline orchestrator (`run_ne25_pipeline.R`)

### `/R/`
**Purpose:** R functions organized by pipeline stage

**Subdirectories:**
- `extract/` - REDCap API extraction (`ne25_extract.R`)
- `transform/` - Data transformations (`ne25_transforms.R`)
- `harmonize/` - Cross-study harmonization (future)
- `utils/` - Utility functions (validation, helpers)
- `codebook/` - Codebook querying functions
- `load/` - Data loading from various sources
- `imputation/` - Multiple imputation helper functions (via reticulate)

**Why R?** Strengths in statistical computing, data transformation, and REDCap integration.

### `/R/imputation/`
**Purpose:** R interface to imputation system via reticulate

**Key Files:**
- `config.R` - Get configuration (calls Python)
- `helpers.R` - Wrapper functions for imputation helpers
  - `get_completed_dataset(m)` - Retrieve single imputation in R
  - `get_imputation_list()` - Get list of M datasets for mitools/survey package
  - `get_all_imputations()` - Long format in R
  - `validate_imputations()` - Validation via Python

**Usage Example:**
```r
library(reticulate)
source("R/imputation/helpers.R")

# Get imputation 3 with geography
df3 <- get_completed_dataset(3, variables = c("puma", "county"))

# Survey analysis with mitools
imp_list <- get_imputation_list()
results <- lapply(imp_list, function(df) {
  design <- svydesign(ids = ~1, weights = ~weight, data = df)
  svymean(~outcome, design)
})
combined <- mitools::MIcombine(results)
```

### `/pipelines/orchestration/`
**Purpose:** Main pipeline controller scripts

**Key Files:**
- `run_ne25_pipeline.R` - NE25 pipeline orchestrator (calls R extract/transform, Python database ops)

**Pattern:** R orchestrates, calls R functions for transformations, calls Python for database operations.

### `/config/`
**Purpose:** YAML configuration files

**Structure:**
- `duckdb.yaml` - Database configuration (path, connection settings)
- `sources/ne25.yaml` - NE25 pipeline configuration (REDCap projects, tables)
- `sources/acs/` - ACS pipeline configs (state-specific)
- `sources/nhis/` - NHIS pipeline configs (year-specific)
- `sources/nsch/` - NSCH pipeline configs (database schema)
- `derived_variables.yaml` - Derived variable definitions

**Why YAML?** Human-readable, version-controlled configuration management.

### `/scripts/`
**Purpose:** Maintenance utilities and one-off scripts

**Subdirectories:**
- `temp/` - Temporary R scripts (used by r_executor.py)
- `audit/` - Data validation scripts
- `documentation/` - Documentation generation scripts
- `validation/` - Validation utilities
- `imputation/` - Imputation pipeline scripts

**Pattern:** Scripts are for maintenance/debugging, not production pipeline.

### `/codebook/`
**Purpose:** JSON-based codebook metadata system

**Structure:**
- `data/codebook.json` - 305 items across 8 studies (NE25, NE22, CAHMI, ECDI, CREDI, GSED)
- `dashboard/` - Quarto dashboard for interactive browsing

**Usage:** Provides item definitions, IRT parameters, response sets for analysis.

---

## ACS Pipeline Directories

The ACS pipeline extracts American Community Survey data from IPUMS USA API for statistical raking.

### `/python/acs/`
**Purpose:** ACS-specific Python modules

**Key Files:**
- `auth.py` - IPUMS API authentication
- `config_manager.py` - ACS configuration management
- `extract_builder.py` - Build IPUMS extract requests
- `extract_manager.py` - Manage extract submission and download
- `cache.py` - Smart caching with SHA256 signatures
- `data_loader.py` - Load ACS data from Feather files
- `metadata_parser.py` - Parse DDI metadata XML
- `metadata_utils.py` - Metadata querying utilities
- `harmonization.py` - Harmonize ACS to NE25 categories

**Design:** Modular, testable components for API interaction.

### `/pipelines/python/acs/`
**Purpose:** Executable ACS pipeline scripts

**Key Files:**
- `extract_acs_data.py` - Extract from IPUMS API, save to Feather
- `insert_acs_database.py` - Load Feather into DuckDB
- `load_acs_metadata.py` - Load DDI metadata into database

**Usage:**
```bash
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

### `/pipelines/orchestration/`
**Purpose:** ACS validation scripts (shared with NE25)

**Key Files:**
- `run_acs_pipeline.R` - R validation after extraction

**Pattern:** Python extracts/loads, R validates.

### `/R/load/acs/` and `/R/utils/acs/`
**Purpose:** ACS-specific R functions

**Key Files:**
- `load/acs/load_acs_data.R` - Load ACS data into R
- `utils/acs/validate_acs_raw.R` - Validation checks
- `utils/acs/acs_metadata.R` - Query metadata from R

### `/config/sources/acs/`
**Purpose:** State-specific ACS configurations

**Files:**
- `acs-template.yaml` - Template configuration
- `nebraska-2019-2023.yaml` - Nebraska 5-year ACS
- `iowa-2019-2023.yaml` - Iowa 5-year ACS
- `minnesota-2019-2023.yaml` - Minnesota 5-year ACS

**Pattern:** One config per state/year combination.

### `/scripts/acs/`
**Purpose:** ACS maintenance utilities

**Key Files:**
- `test_api_connection.py` - Test IPUMS API connectivity
- `check_extract_status.py` - Check extract processing status
- `manage_cache.py` - Cache management (list, validate, clean)
- `run_multiple_states.py` - Batch process multiple states
- `generate_data_dictionary.py` - Auto-generate data dictionary from metadata

### `/docs/acs/`
**Purpose:** ACS pipeline documentation

**Key Files:**
- `README.md` - ACS pipeline overview
- `pipeline_usage.md` - Usage instructions
- `ipums_variables_reference.md` - Variable definitions
- `testing_guide.md` - Testing procedures
- `cache_management.md` - Cache management guide
- `transformation_mappings.md` - IPUMS → NE25 mappings
- `metadata_query_cookbook.md` - Metadata query examples

---

## NHIS Pipeline Directories

The NHIS pipeline extracts National Health Interview Survey data from IPUMS Health Surveys API for benchmarking.

### `/python/nhis/`
**Purpose:** NHIS-specific Python modules

**Key Files:**
- `auth.py` - IPUMS NHIS API authentication (collection: `nhis`)
- `config_manager.py` - NHIS configuration management
- `extract_builder.py` - Build NHIS extract requests
- `extract_manager.py` - Manage extract submission and download
- `cache_manager.py` - SHA256-based caching (years + samples + variables)
- `data_loader.py` - Load NHIS data from Feather files

**Design:** Similar to ACS but with multi-year sample handling.

### `/pipelines/python/nhis/`
**Purpose:** Executable NHIS pipeline scripts

**Key Files:**
- `extract_nhis_data.py` - Extract from IPUMS NHIS API
- `insert_nhis_database.py` - Load Feather into DuckDB

**Usage:**
```bash
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

### `/R/load/nhis/` and `/R/utils/nhis/`
**Purpose:** NHIS-specific R functions

**Key Files:**
- `load/nhis/load_nhis_data.R` - Load NHIS data into R
- `utils/nhis/validate_nhis_raw.R` - 7 validation checks

### `/config/sources/nhis/`
**Purpose:** Year-specific NHIS configurations

**Files:**
- `nhis-template.yaml` - Template configuration
- `nhis-2019-2024.yaml` - 6-year NHIS extract (2019-2024)
- `samples.yaml` - Sample definitions (ih2019-ih2024)

### `/scripts/nhis/`
**Purpose:** NHIS testing scripts

**Key Files:**
- `test_api_connection.py` - Test NHIS API connectivity
- `test_configuration.py` - Validate configuration files
- `test_cache.py` - Test caching functionality
- `test_pipeline_end_to_end.R` - Full pipeline test

### `/docs/nhis/`
**Purpose:** NHIS pipeline documentation

**Key Files:**
- `README.md` - NHIS pipeline overview
- `pipeline_usage.md` - Usage instructions
- `nhis_variables_reference.md` - 66 variables documented
- `testing_guide.md` - Testing procedures
- `transformation_mappings.md` - NHIS → NE25 mappings

---

## NSCH Pipeline Directories

The NSCH pipeline integrates National Survey of Children's Health data from SPSS files for benchmarking.

### `/python/nsch/`
**Purpose:** NSCH-specific Python modules

**Key Files:**
- `spss_loader.py` - Load SPSS files with pyreadstat
- `data_loader.py` - Load NSCH data into database
- `config_manager.py` - NSCH configuration management

**Design:** SPSS-focused (vs API-based like ACS/NHIS).

### `/pipelines/python/nsch/`
**Purpose:** Executable NSCH pipeline scripts

**Key Files:**
- `load_nsch_spss.py` - Convert SPSS → Feather
- `load_nsch_metadata.py` - Extract metadata from SPSS
- `insert_nsch_database.py` - Load Feather into DuckDB

**Usage:**
```bash
python scripts/nsch/process_all_years.py --years all
```

### `/R/load/nsch/` and `/R/utils/nsch/`
**Purpose:** NSCH-specific R functions

**Key Files:**
- `load/nsch/load_nsch_data.R` - Load NSCH data into R
- `utils/nsch/validate_nsch_raw.R` - 7 QC checks

### `/config/sources/nsch/`
**Purpose:** NSCH configuration and schema

**Files:**
- `database_schema.sql` - Table definitions
- `nsch-template.yaml` - Template configuration

### `/scripts/nsch/`
**Purpose:** NSCH utilities

**Key Files:**
- `process_all_years.py` - Batch process multiple years
- `generate_db_summary.py` - Database summary statistics
- `test_db_roundtrip.py` - Test SPSS → DB → SPSS roundtrip
- `generate_variable_reference.py` - Auto-generate variable reference

### `/docs/nsch/`
**Purpose:** NSCH pipeline documentation (10 comprehensive guides)

**Key Files:**
- `README.md` - NSCH pipeline overview
- `pipeline_usage.md` - Usage instructions
- `database_schema.md` - Schema documentation
- `example_queries.md` - SQL query examples
- `troubleshooting.md` - Common issues and solutions
- `testing_guide.md` - Testing procedures
- `variables_reference.md` - 3,780 variables documented
- `NSCH_PIPELINE_SUMMARY.md` - Executive summary
- `IMPLEMENTATION_PLAN.md` - Development plan

---

## Imputation Pipeline Directories

The Imputation Pipeline handles geographic, sociodemographic, and childcare uncertainty through 7-stage sequential multiple imputation (M=5).

### `/scripts/imputation/`
**Purpose:** Imputation pipeline execution scripts (study-specific subdirectories)

**Study-Specific Structure:**
```
scripts/imputation/
├── 00_setup_imputation_schema.py         # One-time setup (all studies)
├── create_new_study.py                   # Automated study onboarding
└── {study_id}/                           # Study-specific pipeline (e.g., ne25/)
    ├── run_full_imputation_pipeline.R    # 7-stage orchestrator
    ├── 01_impute_geography.py            # Stage 1-3: Geography
    ├── 02_impute_sociodemographic.R      # Stage 4: Sociodem (MICE)
    ├── 02b_insert_sociodem_imputations.py# Stage 4: DB insertion
    ├── 03a_impute_cc_receives_care.R     # Stage 5: Childcare access
    ├── 03b_impute_cc_type_hours.R        # Stage 6: Childcare type/hours
    ├── 03c_derive_childcare_10hrs.R      # Stage 7: Derived outcome
    ├── 04_insert_childcare_imputations.py# Stage 7: DB insertion
    └── test_childcare_diagnostics.R      # Statistical validation
```

**Usage:**
```bash
# Setup (one-time, study-specific)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25

# Run full 7-stage pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R

# Validate
python -m python.imputation.helpers
```

**Multi-Study Architecture:**
- Each study (ne25, ia26, co27) has independent subdirectory
- Shared setup script and helper module
- Study-specific configurations and pipeline scripts

### `/python/imputation/`
**Purpose:** Python imputation helper module

**Key Files:**
- `config.py` - Configuration loader (reads study-specific YAML)
- `helpers.py` - Helper functions for retrieving completed datasets
  - `get_complete_dataset()` - Get single imputation with all 14 variables
  - `get_geography_imputations()` - Get geography only (3 variables)
  - `get_sociodem_imputations()` - Get sociodem only (7 variables)
  - `get_childcare_imputations()` - Get childcare only (4 variables)
  - `get_all_imputations()` - Long format across all M
  - `validate_imputations()` - Validation checks

**Design:** Single source of truth - R calls Python via reticulate

### `/R/imputation/`
**Purpose:** R interface to imputation system via reticulate

**Key Files:**
- `config.R` - Get configuration (calls Python)
- `helpers.R` - Wrapper functions for imputation helpers
  - `get_completed_dataset()` - Retrieve single imputation in R
  - `get_imputation_list()` - Get list of M datasets for mitools/survey
  - `get_all_imputations()` - Long format in R
  - `validate_imputations()` - Validation via Python

### `/config/imputation/`
**Purpose:** Study-specific imputation configurations

**Files:**
- `{study_id}_config.yaml` - Study-specific configuration (M, seed, variables)
  - Example: `ne25_config.yaml` - Nebraska 2025 configuration

**Multi-Study Support:** Independent configs for each study

### `/data/imputation/{study_id}/`
**Purpose:** Intermediate data storage (study-specific)

**Structure:**
```
data/imputation/ne25/
├── geography_feather/         # Geography imputations (Stages 1-3)
│   ├── puma_m1.feather
│   └── ... (15 files: 3 vars × 5 imputations)
├── sociodem_feather/          # Sociodem imputations (Stage 4)
│   ├── female_m1.feather
│   └── ... (35 files: 7 vars × 5 imputations)
└── childcare_feather/         # Childcare imputations (Stages 5-7)
    ├── cc_receives_care_m1.feather
    └── ... (20 files: 4 vars × 5 imputations)
```

**Total:** 70 Feather files per study (14 variables × 5 imputations)

### `/docs/imputation/`
**Purpose:** Imputation pipeline documentation (comprehensive)

**Key Files:**
- `IMPUTATION_PIPELINE.md` - Architecture and design rationale
- `USING_IMPUTATION_AGENT.md` - User guide with 3 use cases + troubleshooting
- `CHILDCARE_IMPUTATION_IMPLEMENTATION.md` - 8-phase implementation plan (complete)
- `PIPELINE_TEST_REPORT.md` - Clean run verification from fresh database
- `CHILDCARE_DIAGNOSTICS_REPORT.md` - Statistical validation results
- `ADDING_NEW_STUDY.md` - Complete onboarding guide for new studies
- `STUDY_SPECIFIC_MIGRATION_PLAN.md` - Multi-study architecture guide

**Total:** 7 comprehensive documentation files

---

## Shared Directories

### `/docs/`
**Purpose:** Project-wide documentation

**Structure:**
- `architecture/` - Architecture documentation (PIPELINE_OVERVIEW.md, PIPELINE_STEPS.md)
- `guides/` - User guides (CODING_STANDARDS.md, MISSING_DATA_GUIDE.md, PYTHON_UTILITIES.md)
- `acs/`, `nhis/`, `nsch/` - Pipeline-specific docs
- `codebook/` - Codebook system documentation
- `fixes/` - Bug fix documentation
- `api/` - API documentation
- `INDEX.md`, `README.md` - Documentation indexes
- `QUICK_REFERENCE.md` - Command cheatsheet (Phase 5)
- `DIRECTORY_STRUCTURE.md` - This file

### `/data/`
**Purpose:** Data storage (excluded from git)

**Structure:**
- `duckdb/` - DuckDB database files
- `acs/` - ACS raw data by state/year
- `nhis/` - NHIS raw data by year range
- `nsch/` - NSCH raw data and metadata by year

### `/cache/`
**Purpose:** IPUMS extract caching (excluded from git)

**Structure:**
- `ipums/{extract_id}/` - Cached IPUMS extracts (shared by ACS and NHIS)

**Retention:** 90+ days

---

## Data Storage

### Database Files

**Local DuckDB:** `data/duckdb/kidsights_local.duckdb`
- **Size:** ~47 MB
- **Tables:** 15+ tables (ne25_raw, ne25_transformed, acs_raw, nhis_raw, nsch_{year}_raw, imputed_puma, imputed_county, imputed_census_tract, etc.)
- **Records:** 7,812+ records (NE25) + 25,483 rows (imputations) + varies by pipeline runs

### Temporary Files

**NE25 Temp Feather:** `tempdir()/ne25_pipeline/*.feather`
- **Purpose:** Intermediate R → Python data exchange
- **Lifecycle:** Created during pipeline run, cleaned up after
- **Format:** Apache Arrow Feather (perfect R factor ↔ Python category preservation)

### Pipeline-Specific Data Storage

#### ACS Pipeline

**Raw Data:** `data/acs/{state}/{year_range}/raw.feather`
- Example: `data/acs/nebraska/2019-2023/raw.feather`
- **Format:** Feather (from IPUMS fixed-width format)
- **Size:** Varies by state/year (Nebraska 5-year ~20 MB)

**Cache:** `cache/ipums/{extract_id}/`
- **Contains:** Downloaded data file, DDI metadata XML, extract manifest
- **Naming:** Extract ID from IPUMS (e.g., `usa:12345`)
- **Retention:** 90+ days (configurable with `manage_cache.py`)

#### NHIS Pipeline

**Raw Data:** `data/nhis/{year_range}/raw.feather`
- Example: `data/nhis/2019-2024/raw.feather`
- **Format:** Feather (from IPUMS fixed-width format)
- **Size:** ~47+ MB (6 years, 229K records)

**Processed Data:** `data/nhis/{year_range}/processed.feather`
- **Purpose:** Harmonized/transformed data (future use)

**Cache:** `cache/ipums/{extract_id}/` (shared with ACS)

#### NSCH Pipeline

**SPSS Files:** `data/nsch/spss/*.sav`
- **Source:** Downloaded from NSCH website
- **Naming:** `{year}_topical.sav` (e.g., `2023_topical.sav`)
- **Size:** ~200 MB per year (compressed)

**Raw Data:** `data/nsch/{year}/raw.feather`
- Example: `data/nsch/2023/raw.feather`
- **Format:** Feather (converted from SPSS)
- **Size:** ~10 MB per year (200:1 compression)

**Metadata:** `data/nsch/{year}/metadata.json`
- **Contains:** Variable definitions, value labels, data types
- **Generated:** Automatically during SPSS conversion

**Validation Reports:** `data/nsch/{year}/validation_report.txt`
- **Contains:** 7 QC check results

#### Imputation Pipeline

**Database Tables:** In `data/duckdb/kidsights_local.duckdb`

**Study-Specific Tables (Example: ne25):**

*Geographic Imputations (3 variables):*
- `ne25_imputed_puma` - 4,390 rows (878 records × 5 imputations)
- `ne25_imputed_county` - 5,270 rows (1,054 records × 5 imputations)
- `ne25_imputed_census_tract` - 15,820 rows (3,164 records × 5 imputations)
- Subtotal: 25,480 rows

*Sociodemographic Imputations (7 variables):*
- `ne25_imputed_female` - 880 rows
- `ne25_imputed_raceG` - 1,095 rows
- `ne25_imputed_educ_mom` - 4,560 rows
- `ne25_imputed_educ_a2` - 3,720 rows
- `ne25_imputed_income` - 45 rows
- `ne25_imputed_family_size` - 580 rows
- `ne25_imputed_fplcat` - 15,558 rows
- Subtotal: 26,438 rows

*Childcare Imputations (4 variables):*
- `ne25_imputed_cc_receives_care` - 805 rows
- `ne25_imputed_cc_primary_type` - 7,934 rows
- `ne25_imputed_cc_hours_per_week` - 6,329 rows
- `ne25_imputed_childcare_10hrs_nonfamily` - 15,590 rows
- Subtotal: 24,718 rows

**Total:** 76,636 rows across 14 tables (for study ne25)

**Storage Philosophy:**
- Variable-specific tables (normalized design)
- Study-specific tables (`{study_id}_imputed_{variable}`)
- Only imputed values stored (not observed)
- 50%+ storage efficiency

**Composite Primary Key:** `(study_id, pid, record_id, imputation_m)`

**Usage:**
```python
from python.imputation.helpers import get_complete_dataset, get_childcare_imputations

# Get imputation m=1 with all 14 variables
df = get_complete_dataset(study_id='ne25', imputation_number=1)

# Get just childcare variables (4 variables)
childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)
```

### API Keys

**REDCap API Key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- **Used by:** NE25 pipeline
- **Format:** CSV with project_id, api_key columns

**IPUMS API Key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt`
- **Used by:** ACS and NHIS pipelines
- **Format:** Plain text file with API key
- **Shared:** Same key for IPUMS USA and IPUMS NHIS

---

## Quick Navigation

### I want to...

**Run a pipeline:**
- NE25: `run_ne25_pipeline.R`
- ACS: `pipelines/python/acs/extract_acs_data.py`
- NHIS: `pipelines/python/nhis/extract_nhis_data.py`
- NSCH: `scripts/nsch/process_all_years.py`
- Imputation: `scripts/imputation/ne25/run_full_imputation_pipeline.R`

**Understand pipeline architecture:**
- `docs/architecture/PIPELINE_OVERVIEW.md`
- `docs/architecture/PIPELINE_STEPS.md`

**Add a new derived variable:**
- Code: `R/transform/ne25_transforms.R`
- Guide: `docs/guides/MISSING_DATA_GUIDE.md`
- Config: `config/derived_variables.yaml`

**Query the codebook:**
- Functions: `R/codebook/query_codebook.R`
- Dashboard: `codebook/dashboard/index.qmd`
- Guide: `docs/codebook_utilities.md`

**Debug database issues:**
- Connection: `python/db/connection.py`
- Operations: `python/db/operations.py`
- Guide: `docs/guides/PYTHON_UTILITIES.md`

**Validate data:**
- NE25: `scripts/audit/`
- ACS: `R/utils/acs/validate_acs_raw.R`
- NHIS: `R/utils/nhis/validate_nhis_raw.R`
- NSCH: `R/utils/nsch/validate_nsch_raw.R`

**Find pipeline documentation:**
- ACS: `docs/acs/README.md`
- NHIS: `docs/nhis/README.md`
- NSCH: `docs/nsch/README.md`

**Configure a pipeline:**
- NE25: `config/sources/ne25.yaml`
- ACS: `config/sources/acs/{state}-{years}.yaml`
- NHIS: `config/sources/nhis/nhis-{years}.yaml`
- NSCH: `config/sources/nsch/nsch-template.yaml`

---

## Related Documentation

- **Pipeline Architecture:** [architecture/PIPELINE_OVERVIEW.md](architecture/PIPELINE_OVERVIEW.md)
- **Pipeline Execution:** [architecture/PIPELINE_STEPS.md](architecture/PIPELINE_STEPS.md)
- **Quick Reference:** [QUICK_REFERENCE.md](QUICK_REFERENCE.md) (Phase 5)
- **Documentation Index:** [INDEX.md](INDEX.md)

---

*Last Updated: October 2025*
