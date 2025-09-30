# Kidsights Data Platform - Development Guidelines

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research with two primary pipelines:

1. **NE25 Pipeline**: REDCap survey data processing (Nebraska 2025 study)
2. **ACS Pipeline**: IPUMS USA census data extraction for statistical raking

**Run NE25 Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**Run ACS Pipeline:**
```bash
# Extract data from IPUMS API
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023

# Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R \
    --state nebraska --year-range 2019-2023 --state-fip 31

# Insert into database
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**Key Requirements:**
- R 4.5.1 with arrow, duckdb packages
- Python 3.13+ with duckdb, pandas, pyyaml, ipumspy
- **IPUMS API key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt`
- **REDCap API key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- Use temp script files for R execution (never `-e` inline commands)
- All R functions MUST use explicit namespacing (`dplyr::`, `tidyr::`, etc.)

## Architecture

### NE25 Pipeline: Hybrid R-Python Design (September 2025)

**Problem Solved:** R DuckDB segmentation faults caused 50% pipeline failure rate
**Solution:** R handles orchestration/transforms, Python handles all database operations

```
REDCap (4 projects) → R: Extract/Transform → Feather Files → Python: Database Ops → Local DuckDB
     3,906 records      REDCapR, recode_it()      arrow format      Chunked processing     47MB local
```

**Key Benefits:**
- 100% pipeline reliability (was 50%)
- 3x faster I/O with Feather format
- Rich error context (no more segfaults)
- Perfect data type preservation R ↔ Python

### ACS Pipeline: Census Data Extraction (September 2025)

**Purpose:** Extract American Community Survey data from IPUMS USA API for statistical raking

**Architecture:**
```
IPUMS USA API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → Local DuckDB
  Census data     ipumspy, requests     arrow format    Statistical QC    Chunked inserts    Separate tables
```

**Key Features:**
- **API Integration:** Direct IPUMS USA API calls (no manual web downloads)
- **Smart Caching:** Automatic caching with checksum validation (90+ day retention)
- **R Validation:** Statistical QC and data validation in R
- **Standalone Design:** Independent of NE25 pipeline (no dependencies)
- **Future Use:** Enables post-stratification raking after harmonization

## Directory Structure

### Core Directories (NE25 Pipeline)
- **`/python/`** - Database operations (connection.py, operations.py)
- **`/pipelines/python/`** - Executable database scripts (init_database.py, insert_raw_data.py)
- **`/R/`** - R functions (extract/, harmonize/, transform/, utils/)
- **`/pipelines/orchestration/`** - Main pipeline controllers
- **`/config/`** - YAML configurations (sources/, duckdb.yaml)
- **`/scripts/`** - Maintenance utilities (temp/ for R scripts, audit/ for data validation)
- **`/codebook/`** - JSON-based metadata system

### ACS Pipeline Directories
- **`/python/acs/`** - ACS modules (auth.py, config_manager.py, extract_builder.py, extract_manager.py, cache.py)
- **`/pipelines/python/acs/`** - Executable scripts (extract_acs_data.py, insert_acs_database.py)
- **`/pipelines/orchestration/`** - R validation script (run_acs_pipeline.R)
- **`/R/load/acs/`** - Data loading functions (load_acs_data.R)
- **`/R/utils/acs/`** - Validation utilities (validate_acs_raw.R)
- **`/config/sources/acs/`** - State-specific configurations (nebraska-2019-2023.yaml, iowa-2019-2023.yaml, etc.)
- **`/scripts/acs/`** - Maintenance scripts (test_api_connection.py, check_extract_status.py, manage_cache.py, run_multiple_states.py)
- **`/docs/acs/`** - Documentation (ipums_variables_reference.md, pipeline_usage.md, testing_guide.md, cache_management.md)

### Data Storage
- **Local DuckDB:** `data/duckdb/kidsights_local.duckdb`
- **NE25 Temp Feather:** `tempdir()/ne25_pipeline/*.feather`
- **ACS Raw Data:** `data/acs/{state}/{year_range}/raw.feather`
- **ACS Cache:** `cache/ipums/{extract_id}/`
- **REDCap API Key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- **IPUMS API Key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt`

## Development Standards

### R Coding Standards (CRITICAL)

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

### File Naming
- R files: `snake_case.R`
- Config files: `kebab-case.yaml`
- Documentation: `UPPER_CASE.md` for key docs

## Pipeline Execution

### R Execution Guidelines (CRITICAL)

⚠️ **Never use inline `-e` commands - they cause segmentation faults**

```bash
# ✅ CORRECT - Use temp script files
echo 'library(dplyr); cat("Success\n")' > scripts/temp/temp_script.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/temp/temp_script.R

# ❌ INCORRECT - Causes segfaults
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "library(dplyr)"
```

### NE25 Pipeline Steps
1. **Database Init:** `python pipelines/python/init_database.py --config config/sources/ne25.yaml`
2. **Data Extraction:** R extracts from 4 REDCap projects
3. **Raw Storage:** Python stores via Feather files
4. **Transformations:** R applies recode_it() for 21 derived variables
5. **Final Storage:** Python stores transformed data
6. **Metadata:** Python generates comprehensive documentation

### ACS Pipeline Steps
1. **Extract from API:** `python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023`
   - Submits extract to IPUMS API or retrieves from cache
   - Saves to `data/acs/{state}/{year_range}/raw.feather`
   - Processing time: 5-15 min (1-year) or 45+ min (5-year)

2. **Validate in R:** `"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31`
   - Loads Feather file with `arrow::read_feather()`
   - Validates variable presence, age/state filters, weights
   - Generates summary statistics

3. **Insert to Database:** `python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023`
   - Chunks data for efficient insertion
   - Stores in `acs_raw` table
   - Validates row counts

### ACS Utility Scripts

```bash
# Test API connection
python scripts/acs/test_api_connection.py --test-connection

# Submit test extract (Nebraska 2021, fast processing)
python scripts/acs/test_api_connection.py --submit-test

# Check extract status
python scripts/acs/check_extract_status.py usa:12345

# Run multiple states
python scripts/acs/run_multiple_states.py --states nebraska iowa kansas --year-range 2019-2023

# Manage cache
python scripts/acs/manage_cache.py --list
python scripts/acs/manage_cache.py --validate
python scripts/acs/manage_cache.py --clean --max-age 90

# Run end-to-end test
Rscript scripts/acs/test_pipeline_end_to_end.R
```

## Python Utilities

### R Executor (Recommended)
```python
from python.utils.r_executor import execute_r_script

code = '''
library(dplyr)
cat("Hello from R!\\n")
'''
output, return_code = execute_r_script(code)
```

### Database Operations
```python
from python.db.connection import DatabaseManager
dm = DatabaseManager()
success = dm.test_connection()
```

### Data Refresh Strategy
**Important:** Pipeline uses `replace` mode for database operations to ensure clean datasets without duplicates.

## Derived Variables System

### 48 Derived Variables Created by recode_it()

**Eligibility (3):** `eligible`, `authentic`, `include`
**Race/Ethnicity (6):** `hisp`, `race`, `raceG`, `a1_hisp`, `a1_race`, `a1_raceG`
**Education (12):** 8/4/6-category versions of `educ_max`, `educ_a1`, `educ_a2`, `educ_mom`
**Geographic (27):** PUMA, County, Tract, CBSA, Urban/Rural, School/Legislative/Congressional districts, Native Lands

### Configuration
- **Variables list:** `config/derived_variables.yaml`
- **Transform code:** `R/transform/ne25_transforms.R`
- **Documentation:** Only derived variables appear in transformed-variables.html

## Geographic Crosswalk System

### Database-Backed Reference Tables (10 tables, 126K rows)

Geographic crosswalk data is stored in DuckDB and queried via the hybrid R-Python approach to avoid segmentation faults.

**Tables:**
- `geo_zip_to_puma` - Public Use Microdata Areas (2020 Census)
- `geo_zip_to_county` - County FIPS codes
- `geo_zip_to_tract` - Census tract FIPS codes
- `geo_zip_to_cbsa` - Core-Based Statistical Areas
- `geo_zip_to_urban_rural` - Urban/Rural classification (2022 Census)
- `geo_zip_to_school_dist` - School districts (2020)
- `geo_zip_to_state_leg_lower` - State house districts (2024)
- `geo_zip_to_state_leg_upper` - State senate districts (2024)
- `geo_zip_to_congress` - US Congressional districts (119th Congress)
- `geo_zip_to_native_lands` - AIANNH areas (2021)

**Loading Crosswalk Data:**
```bash
# Initial load or refresh geographic reference tables
python pipelines/python/load_geo_crosswalks_sql.py
```

**Querying from R:**
```r
# Source utility function
source("R/utils/query_geo_crosswalk.R")

# Query a crosswalk table (returns data frame)
puma_data <- query_geo_crosswalk("geo_zip_to_puma")
county_data <- query_geo_crosswalk("geo_zip_to_county")
```

**Derived Variables:** Geographic transformation creates 27 variables from ZIP code (`sq001`):
- **PUMA:** `puma`, `puma_afact`
- **County:** `county`, `county_name`, `county_afact`
- **Census Tract:** `tract`, `tract_afact`
- **CBSA:** `cbsa`, `cbsa_name`, `cbsa_afact`
- **Urban/Rural:** `urban_rural`, `urban_rural_afact`, `urban_pct`
- **School District:** `school_dist`, `school_name`, `school_afact`
- **State Legislative Lower:** `sldl`, `sldl_afact`
- **State Legislative Upper:** `sldu`, `sldu_afact`
- **Congressional District:** `congress_dist`, `congress_afact`
- **Native Lands:** `aiannh_code`, `aiannh_name`, `aiannh_afact`

All geographic variables use **semicolon-separated format** to preserve multiple assignments (e.g., ZIP codes spanning multiple counties). Allocation factors (`afact`) indicate the proportion of ZIP population in each geography.

**Source Files:**
- Data loader: `pipelines/python/load_geo_crosswalks_sql.py`
- Query utilities: `python/db/query_geo_crosswalk.py` and `R/utils/query_geo_crosswalk.R`
- Transformation: `R/transform/ne25_transforms.R:545-790`
- Configuration: `config/derived_variables.yaml`

## Codebook System

### JSON-Based Metadata (305 Items)
- **Location:** `codebook/data/codebook.json`
- **Version:** 3.0
- **Studies:** NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED
- **IRT Parameters:** NE22, NE25, CREDI (SF/LF), GSED (multi-calibration)
- **Response Sets:** Study-specific (NE25 uses `9`, others use `-9` for missing)

### Key Functions
```r
# Basic querying
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")
motor_items <- filter_items_by_domain(codebook, "motor")
ne25_items <- filter_items_by_study(codebook, "NE25")

# Data extraction utilities
source("R/codebook/extract_codebook.R")
crosswalk <- codebook_extract_lexicon_crosswalk(codebook)
irt_params <- codebook_extract_irt_parameters(codebook, "NE22")
responses <- codebook_extract_response_sets(codebook, study = "NE25")
content <- codebook_extract_item_content(codebook, domains = "motor")
summary <- codebook_extract_study_summary(codebook, "NE25")
```

### Utility Functions for Analysis
**File:** `R/codebook/extract_codebook.R` | **Documentation:** `docs/codebook_utilities.md`

| Function | Purpose |
|----------|---------|
| `codebook_extract_lexicon_crosswalk()` | Item ID mappings across studies |
| `codebook_extract_irt_parameters()` | IRT discrimination/threshold parameters |
| `codebook_extract_response_sets()` | Response options and value labels |
| `codebook_extract_item_content()` | Item text, domains, age ranges |
| `codebook_extract_study_summary()` | Study-level summary statistics |

**Example workflow:**
```r
# Run complete analysis example
source("scripts/examples/codebook_utilities_examples.R")
```

### IRT Parameters

The codebook includes IRT calibration parameters for multiple studies:

**NE22 Parameters** (203 items):
- Unidimensional model: factor = "kidsights"
- PS items: Bifactor model with general + specific factors (eat/sle/soc/int/ext)
- Script: `scripts/codebook/update_ne22_irt_parameters.R`

**CREDI Parameters** (60 items):
- **Short Form (SF)**: 37 items, unidimensional, factor = "credi_overall"
- **Long Form (LF)**: 60 items, multidimensional, factors = mot/cog/lang/sem
- Nested structure: `CREDI → short_form/long_form → parameters`
- Script: `scripts/codebook/update_credi_irt_parameters.R`
- Source: `data/credi-mest_df.csv`

**GSED Parameters** (132 items):
- Rasch model: loading = 1.0 (all items)
- Multiple calibrations per item (avg 3.03): gsed2406, gsed2212, gsed1912, gcdg, dutch, 293_0
- Nested structure: `GSED → calibration_key → parameters`
- Script: `scripts/codebook/update_gsed_irt_parameters.R`
- Source: `dscore::builtin_itembank`

**Threshold Transformations:**
- NE22: threshold = -tau (negated and sorted)
- CREDI SF: threshold = -delta / alpha
- CREDI LF: threshold = -tau
- GSED: threshold = -tau

### Dashboard
```bash
quarto render codebook/dashboard/index.qmd
```

## Pipeline Integration and Relationship

### Two Independent Pipelines

The Kidsights Data Platform operates two **independent, standalone pipelines**:

**1. NE25 Pipeline (Primary):**
- **Purpose:** Process REDCap survey data from Nebraska 2025 study
- **Data Source:** 4 REDCap projects via REDCapR
- **Architecture:** Hybrid R-Python with Feather files
- **Status:** Production ready, 100% reliability
- **Tables:** `ne25_raw`, `ne25_transformed`, 9 validation/metadata tables

**2. ACS Pipeline (Utility):**
- **Purpose:** Extract census data from IPUMS USA API for statistical raking
- **Data Source:** IPUMS USA API via ipumspy
- **Architecture:** Python extraction → R validation → Python database
- **Status:** Complete (Phase 11 integration)
- **Tables:** `acs_raw`, `acs_metadata`

### Design Decision: Why Separate?

**No automatic integration** - ACS pipeline does NOT run as part of NE25 pipeline.

**Rationale:**
1. **Different cadences:** NE25 runs frequently (new survey data), ACS runs rarely (annual census updates)
2. **Different dependencies:** NE25 requires REDCap API, ACS requires IPUMS API
3. **Future use case:** ACS data needed for post-stratification raking (Phase 12+)
4. **Modular design:** Each pipeline can be maintained/tested independently

### How They Work Together

```
NE25 Pipeline                    ACS Pipeline
     ↓                               ↓
ne25_raw                         acs_raw
ne25_transformed                     ↓
     ↓                          (future)
     ↓                               ↓
     └─────── → RAKING MODULE ← ─────┘
                (Phase 12+)
            Harmonizes geography
         Applies sampling weights
       Generates raked estimates
```

**Future Integration (Phase 12+):**
- **Harmonization:** Match NE25 ZIP codes to ACS geographic units (PUMA, county)
- **Raking:** Adjust NE25 sample weights to match ACS population distributions
- **Module Location:** `R/utils/raking_utils.R` (deferred)

### When to Run Each Pipeline

**NE25 Pipeline:**
```bash
# Run whenever new REDCap data is available
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**ACS Pipeline:**
```bash
# Run annually or when new ACS data is released
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

## Environment Setup

### Required Software Paths
- **R:** `C:/Program Files/R/R-4.5.1/bin`
- **Quarto:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe`
- **Pandoc:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools/pandoc.exe`

### Python Packages
```bash
# Core packages (NE25 pipeline)
pip install duckdb pandas pyyaml structlog

# ACS pipeline packages
pip install ipumspy requests
```

## Current Status (September 2025)

### ✅ NE25 Pipeline - Production Ready
- **Pipeline Reliability:** 100% success rate (eliminated segmentation faults)
- **Data Processing:** 3,908 records from 4 REDCap projects
- **Storage:** Local DuckDB with 11 tables, 7,812 records
- **Format:** Feather files for 3x faster R/Python data exchange
- **Documentation:** Auto-generated JSON, HTML, Markdown exports

### ✅ ACS Pipeline - Complete (Phase 11)
- **API Integration:** Direct IPUMS USA API extraction via ipumspy
- **Smart Caching:** Automatic caching with 90+ day retention, checksum validation
- **Data Validation:** R-based statistical QC and validation
- **Testing:** Comprehensive test suite (API connection, end-to-end, web UI comparison)
- **Documentation:** Complete usage guides, variable reference, testing procedures
- **Status:** Standalone utility ready for use, raking integration deferred to Phase 12+

### ✅ Architecture Simplified
- **CID8 Removed:** No more complex IRT analysis causing instability
- **8 Eligibility Criteria:** CID1-7 + completion (was 9)
- **Feather Migration:** Perfect R factor ↔ pandas category preservation
- **Response Sets:** Study-specific missing value conventions (NE25: 9, others: -9)
- **Dual Pipeline Design:** NE25 (survey) + ACS (census) as independent, complementary systems

### Quick Debugging
1. **Database:** `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"`
2. **R Packages:** Use temp script files, never inline `-e`
3. **Pipeline:** Run from project root directory
4. **Logs:** Check Python error context for detailed debugging
5. **HTML Docs:** `python scripts/documentation/generate_html_documentation.py`

---
*Updated: September 2025 | Version: 3.0.0*