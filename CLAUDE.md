# Kidsights Data Platform - Development Guidelines

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research. Data from REDCap projects is processed using a hybrid R-Python architecture and stored in local DuckDB.

**Run Pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**Key Requirements:**
- R 4.5.1 with arrow, duckdb packages
- Python 3.13+ with duckdb, pandas, pyyaml
- Use temp script files for R execution (never `-e` inline commands)
- All R functions MUST use explicit namespacing (`dplyr::`, `tidyr::`, etc.)

## Architecture

### Hybrid R-Python Design (September 2025)

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

## Directory Structure

### Core Directories
- **`/python/`** - Database operations (connection.py, operations.py)
- **`/pipelines/python/`** - Executable database scripts (init_database.py, insert_raw_data.py)
- **`/R/`** - R functions (extract/, harmonize/, transform/, utils/)
- **`/pipelines/orchestration/`** - Main pipeline controllers
- **`/config/`** - YAML configurations (sources/, duckdb.yaml)
- **`/scripts/`** - Maintenance utilities (temp/ for R scripts, audit/ for data validation)
- **`/codebook/`** - JSON-based metadata system

### Data Storage
- **Local DuckDB:** `data/duckdb/kidsights_local.duckdb`
- **Temp Feather:** `tempdir()/ne25_pipeline/*.feather`
- **API Credentials:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`

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

### Pipeline Steps
1. **Database Init:** `python pipelines/python/init_database.py --config config/sources/ne25.yaml`
2. **Data Extraction:** R extracts from 4 REDCap projects
3. **Raw Storage:** Python stores via Feather files
4. **Transformations:** R applies recode_it() for 21 derived variables
5. **Final Storage:** Python stores transformed data
6. **Metadata:** Python generates comprehensive documentation

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

### 21 Derived Variables Created by recode_it()

**Eligibility (3):** `eligible`, `authentic`, `include`
**Race/Ethnicity (6):** `hisp`, `race`, `raceG`, `a1_hisp`, `a1_race`, `a1_raceG`
**Education (12):** 8/4/6-category versions of `educ_max`, `educ_a1`, `educ_a2`, `educ_mom`

### Configuration
- **Variables list:** `config/derived_variables.yaml`
- **Transform code:** `R/transform/ne25_transforms.R`
- **Documentation:** Only derived variables appear in transformed-variables.html

## Codebook System

### JSON-Based Metadata (306 Items)
- **Location:** `codebook/data/codebook.json`
- **Studies:** NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED_PF
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

### Dashboard
```bash
quarto render codebook/dashboard/index.qmd
```

## Environment Setup

### Required Software Paths
- **R:** `C:/Program Files/R/R-4.5.1/bin`
- **Quarto:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe`
- **Pandoc:** `C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools/pandoc.exe`

### Python Packages
```bash
pip install duckdb pandas pyyaml structlog
```

## Current Status (September 2025)

### ✅ Production Ready
- **Pipeline Reliability:** 100% success rate (eliminated segmentation faults)
- **Data Processing:** 3,908 records from 4 REDCap projects
- **Storage:** Local DuckDB with 11 tables, 7,812 records
- **Format:** Feather files for 3x faster R/Python data exchange
- **Documentation:** Auto-generated JSON, HTML, Markdown exports

### ✅ Architecture Simplified
- **CID8 Removed:** No more complex IRT analysis causing instability
- **8 Eligibility Criteria:** CID1-7 + completion (was 9)
- **Feather Migration:** Perfect R factor ↔ pandas category preservation
- **Response Sets:** Study-specific missing value conventions (NE25: 9, others: -9)

### Quick Debugging
1. **Database:** `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"`
2. **R Packages:** Use temp script files, never inline `-e`
3. **Pipeline:** Run from project root directory
4. **Logs:** Check Python error context for detailed debugging
5. **HTML Docs:** `python scripts/documentation/generate_html_documentation.py`

---
*Updated: September 2025 | Version: 2.8.0*