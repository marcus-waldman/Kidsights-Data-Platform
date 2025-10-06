# Kidsights Data Platform - Development Guidelines

**Last Updated:** October 2025 | **Version:** 3.2.0

This is a quick reference guide for AI assistants working with the Kidsights Data Platform. For detailed documentation, see the [Documentation Directory](#documentation-directory) below.

---

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research with **five independent pipelines**:

1. **NE25 Pipeline** - REDCap survey data processing (Nebraska 2025 study)
2. **ACS Pipeline** - IPUMS USA census data extraction
3. **NHIS Pipeline** - IPUMS Health Surveys data extraction
4. **NSCH Pipeline** - National Survey of Children's Health data integration
5. **Raking Targets Pipeline** - Population-representative targets for post-stratification weighting

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

**📖 Complete coding standards:** [CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)

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

### Quick Debugging
1. **Database:** `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"`
2. **R Packages:** Use temp script files, never inline `-e`
3. **Pipeline:** Run from project root directory
4. **Logs:** Check Python error context for detailed debugging

**📖 Complete reference:** [QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)

---

## Documentation Directory

### Architecture & Pipeline Guides
- **[PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 4 pipelines, design rationales, ACS metadata system
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
- **Storage:** Local DuckDB with 11 tables, 7,812 records

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

### Architecture Highlights
- **Hybrid R-Python Design:** R for transformations, Python for database operations
- **Feather Format:** 3x faster R/Python data exchange, perfect type preservation
- **Independent Pipelines:** NE25 (local survey) + ACS (census) + NHIS (national health) + NSCH (child health) + Raking Targets (weighting)
- **Statistical Integration:** Raking targets ready for post-stratification weighting implementation

**📖 Complete status and architecture:** [PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)

---

**For detailed information on any topic, see the [Documentation Directory](#documentation-directory) above.**

*Updated: October 2025 | Version: 3.2.0*
