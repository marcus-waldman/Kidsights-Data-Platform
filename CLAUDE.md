# Kidsights Data Platform - Development Guidelines

## Quick Start

The Kidsights Data Platform is a multi-source ETL system for childhood development research with four primary pipelines:

1. **NE25 Pipeline**: REDCap survey data processing (Nebraska 2025 study)
2. **ACS Pipeline**: IPUMS USA census data extraction for statistical raking
3. **NHIS Pipeline**: IPUMS Health Surveys data extraction for national benchmarking
4. **NSCH Pipeline**: National Survey of Children's Health data integration for benchmarking

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

**Run NHIS Pipeline:**
```bash
# Extract data from IPUMS NHIS API
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

# Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024

# Insert into database
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**Run NSCH Pipeline:**
```bash
# Process single year
python scripts/nsch/process_all_years.py --years 2023

# Process all years (2016-2023)
python scripts/nsch/process_all_years.py --years all

# Process year range
python scripts/nsch/process_all_years.py --years 2020-2023
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

### NHIS Pipeline: Health Surveys Data Extraction (October 2025)

**Purpose:** Extract National Health Interview Survey data from IPUMS Health Surveys API for national benchmarking and ACEs/mental health research

**Architecture:**
```
IPUMS NHIS API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → DuckDB
  ih2019-ih2024    ipumspy, requests     arrow format    7 validation    Chunked inserts   nhis_raw table
      ↓                    ↓                     ↓            checks              ↓              ↓
  66 variables      SHA256 caching         3x faster I/O    Survey QC    Perfect types    300K+ records
  6 annual samples  90+ day retention      R ↔ Python       ACE/MH       preservation     47+ MB
```

**Key Features:**
- **API Integration:** Direct IPUMS NHIS API calls (collection: `nhis`)
- **Multi-Year Samples:** 6 annual samples (2019-2024), not pooled like ACS
- **Smart Caching:** SHA256 signatures based on years + samples + variables
- **66 Variables:** Demographics, parent info, ACEs, GAD-7, PHQ-8, economic indicators
- **No Case Selection:** Nationwide, all ages (vs ACS state/age filters)
- **Survey Design:** Includes SAMPWEIGHT, STRATA, PSU for complex survey analysis
- **Mental Health Focus:** GAD-7 anxiety and PHQ-8 depression (2019, 2022 only)
- **ACEs Coverage:** 8 ACE variables with direct overlap to NE25
- **Documentation:** Complete usage guides, testing procedures, transformation mappings

**Use Cases:**
- Compare NE25 ACE prevalence to national NHIS estimates
- Extract PHQ-2/GAD-2 from full PHQ-8/GAD-7 scales for comparability
- Population benchmarking for Nebraska sample
- Future harmonization for raking (Phase 12+)

### NSCH Pipeline: Survey Data Integration (October 2025)

**Purpose:** Integrate National Survey of Children's Health (NSCH) data from SPSS files for national benchmarking and trend analysis

**Architecture:**
```
SPSS Files → Python: Convert → Feather → R: Validate → Python: Load → DuckDB
  2016-2023    pyreadstat      arrow     7 QC checks    Chunked     nsch_{year}_raw
     ↓              ↓            ↓             ↓         inserts          ↓
  840-923 vars  Metadata   Fast I/O    Integrity   10K/chunk    284K records
  50K-55K rows  extraction  3x faster    checks    validation    7 years loaded
```

**Key Features:**
- **Multi-Year Support:** 8 years (2016-2023), 284,496 records loaded
- **Automated Pipeline:** Single command processes SPSS → Database
- **Metadata Extraction:** Auto-generates variable reference (3,780 variables)
- **Data Quality:** 7-point validation ensures 100% integrity
- **Efficient Storage:** 200:1 compression (SPSS → DuckDB)
- **Batch Processing:** Processes 7 years in 2 minutes
- **Documentation:** 10 comprehensive guides (629 KB total)

**Current Status:** ✅ Production Ready (7/8 years loaded, 2016 schema incompatibility documented)

**Use Cases:**
- National benchmarking for state/local child health data
- Trend analysis (2017-2023) for longitudinal studies
- ACE prevalence comparison across years
- Cross-year harmonization (future Phase 8)

### ACS Metadata System (October 2025)

**Purpose:** Leverage IPUMS DDI (Data Documentation Initiative) metadata for transformation, harmonization, and documentation

**Architecture:**
```
DDI XML Files → Python: Parse Metadata → DuckDB: Metadata Tables → Python/R: Query & Transform
  Variable defs    metadata_parser.py    3 tables (42 vars, 1,144 labels)   Decode, harmonize
```

**Components:**

1. **Metadata Extraction (Phase 1)**
   - **Parser:** `python/acs/metadata_parser.py` - Extracts variables, value labels, dataset info from DDI
   - **Schema:** `python/acs/metadata_schema.py` - Defines 3 DuckDB tables (acs_variables, acs_value_labels, acs_metadata_registry)
   - **Loader:** `pipelines/python/acs/load_acs_metadata.py` - Populates metadata tables
   - **Auto-loading:** Integrated into extraction pipeline (Step 4.6)

2. **Transformation Utilities (Phase 2)**
   - **Python Utilities:** `python/acs/metadata_utils.py`
     - `decode_value()`: Decode single values (e.g., STATEFIP 27 → "Minnesota")
     - `decode_dataframe()`: Decode entire columns
     - `get_variable_info()`, `search_variables()`: Query metadata
     - `is_categorical()`, `is_continuous()`, `is_identifier()`: Type checking
   - **R Utilities:** `R/utils/acs/acs_metadata.R`
     - `acs_decode_value()`, `acs_decode_column()`: Decode values
     - `acs_get_variable_info()`, `acs_search_variables()`: Query metadata
     - `acs_is_categorical()`, etc.: Type checking
   - **Harmonization Tools:** `python/acs/harmonization.py`
     - `harmonize_race_ethnicity()`: Maps IPUMS RACE/HISPAN to 7 NE25 categories
     - `harmonize_education()`: Maps IPUMS EDUC to NE25 8-cat or 4-cat education levels
     - `harmonize_income_to_fpl()`: Converts income to Federal Poverty Level percentages
     - `apply_harmonization()`: Applies all harmonizations at once

3. **Documentation & Analysis (Phase 3)**
   - **Data Dictionary Generator:** `scripts/acs/generate_data_dictionary.py`
     - Auto-generates HTML/Markdown data dictionaries from metadata
     - Includes variable descriptions, value labels, data types
   - **Transformation Docs:** `docs/acs/transformation_mappings.md`
     - Documents IPUMS → NE25 category mappings
     - Race/ethnicity, education, income/FPL transformations
   - **Query Cookbook:** `docs/acs/metadata_query_cookbook.md`
     - Practical examples in Python and R
     - Common patterns for decoding, searching, harmonizing

**Usage Examples:**

*Python:*
```python
from python.acs.metadata_utils import decode_value, decode_dataframe
from python.acs.harmonization import harmonize_race_ethnicity
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Decode values
state = decode_value('STATEFIP', 27, db)  # "Minnesota"

# Decode DataFrame columns
df = decode_dataframe(df, ['STATEFIP', 'SEX'], db)

# Harmonize to NE25 categories
df['ne25_race'] = harmonize_race_ethnicity(df, 'RACE', 'HISPAN')
```

*R:*
```r
source("R/utils/acs/acs_metadata.R")

# Decode values
state <- acs_decode_value("STATEFIP", 27)  # "Minnesota"

# Decode DataFrame columns
df <- acs_decode_column(df, "STATEFIP")

# Search variables
educ_vars <- acs_search_variables("education")
```

**Key Benefits:**
- **Precise transformations:** Know exactly what IPUMS codes mean
- **Automated validation:** Check categorical values against DDI
- **Reduced errors:** No guesswork in code-to-label mappings
- **Self-documenting:** Auto-generated data dictionaries
- **Category alignment:** Ensure ACS and NE25 categories match for raking

**Documentation:**
- Transformation mappings: `docs/acs/transformation_mappings.md`
- Query cookbook: `docs/acs/metadata_query_cookbook.md`
- Data dictionary: `docs/acs/data_dictionary.html` (auto-generated)

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

### NHIS Pipeline Directories
- **`/python/nhis/`** - NHIS modules (auth.py, config_manager.py, extract_builder.py, extract_manager.py, cache_manager.py, data_loader.py)
- **`/pipelines/python/nhis/`** - Executable scripts (extract_nhis_data.py, insert_nhis_database.py)
- **`/pipelines/orchestration/`** - R validation script (run_nhis_pipeline.R)
- **`/R/load/nhis/`** - Data loading functions (load_nhis_data.R)
- **`/R/utils/nhis/`** - Validation utilities (validate_nhis_raw.R)
- **`/config/sources/nhis/`** - Year-specific configurations (nhis-template.yaml, nhis-2019-2024.yaml, samples.yaml)
- **`/scripts/nhis/`** - Test scripts (test_api_connection.py, test_configuration.py, test_cache.py, test_pipeline_end_to_end.R)
- **`/docs/nhis/`** - Documentation (README.md, pipeline_usage.md, nhis_variables_reference.md, testing_guide.md, transformation_mappings.md)

### NSCH Pipeline Directories
- **`/python/nsch/`** - NSCH modules (spss_loader.py, data_loader.py, config_manager.py)
- **`/pipelines/python/nsch/`** - Executable scripts (load_nsch_spss.py, load_nsch_metadata.py, insert_nsch_database.py)
- **`/pipelines/orchestration/`** - R validation script (run_nsch_pipeline.R)
- **`/R/load/nsch/`** - Data loading functions (load_nsch_data.R)
- **`/R/utils/nsch/`** - Validation utilities (validate_nsch_raw.R)
- **`/config/sources/nsch/`** - Database schema (database_schema.sql, nsch-template.yaml)
- **`/scripts/nsch/`** - Utilities (process_all_years.py, generate_db_summary.py, test_db_roundtrip.py, generate_variable_reference.py)
- **`/docs/nsch/`** - Documentation (README.md, pipeline_usage.md, database_schema.md, example_queries.md, troubleshooting.md, testing_guide.md, variables_reference.md, NSCH_PIPELINE_SUMMARY.md, IMPLEMENTATION_PLAN.md)

### Data Storage
- **Local DuckDB:** `data/duckdb/kidsights_local.duckdb`
- **NE25 Temp Feather:** `tempdir()/ne25_pipeline/*.feather`
- **ACS Raw Data:** `data/acs/{state}/{year_range}/raw.feather`
- **ACS Cache:** `cache/ipums/{extract_id}/`
- **NHIS Raw Data:** `data/nhis/{year_range}/raw.feather`, `data/nhis/{year_range}/processed.feather`
- **NHIS Cache:** `cache/ipums/{extract_id}/` (shared with ACS)
- **NSCH SPSS Files:** `data/nsch/spss/*.sav` (source files)
- **NSCH Raw Data:** `data/nsch/{year}/raw.feather`, `data/nsch/{year}/processed.feather`
- **NSCH Metadata:** `data/nsch/{year}/metadata.json`, `data/nsch/{year}/validation_report.txt`
- **REDCap API Key:** `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- **IPUMS API Key:** `C:/Users/waldmanm/my-APIs/IPUMS.txt` (shared by ACS and NHIS)

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

### Windows Console Output (CRITICAL)

**All Python print() statements MUST use ASCII characters only (no Unicode symbols).**

```python
# ✅ CORRECT - ASCII output (Windows-compatible)
print("[OK] Data loaded successfully")
print("[ERROR] Failed to connect")
print("[WARN] Missing variables detected")
print("[INFO] Processing records...")

# ❌ INCORRECT - Unicode symbols (causes UnicodeEncodeError on Windows)
print("✓ Data loaded successfully")  # U+2713
print("✗ Failed to connect")  # U+2717
print("⚠ Missing variables")  # U+26A0
```

**Rationale:**
- Windows console uses cp1252 encoding (not UTF-8)
- Unicode symbols cause `UnicodeEncodeError: 'charmap' codec can't encode character`
- ASCII alternatives are universally compatible

**Standard Replacements:**
- `✓` → `[OK]`
- `✗` → `[ERROR]` or `[FAIL]`
- `⚠` → `[WARN]`
- `ℹ` → `[INFO]`

### Missing Data Handling (CRITICAL)

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
for(old_name in names(variable_mapping)) {
  if(old_name %in% names(dat)) {
    new_name <- variable_mapping[[old_name]]
    derived_df[[new_name]] <- dat[[old_name]]  # 99 values persist!
  }
}
```

**Requirements for Adding New Derived Variables:**

1. **Check REDCap Data Dictionary:** Before implementing any transformation, query the REDCap data dictionary to identify missing value codes:
   ```r
   # Check response options for variable
   dict_entry <- redcap_dict[[variable_name]]
   response_options <- dict_entry$select_choices_or_calculations
   # Look for: "99, Prefer not to answer", "9, Don't know", etc.
   ```

2. **Apply Defensive Recoding:** Even if no current missing codes exist, apply `recode_missing()` as a safeguard:
   ```r
   # Defensive recoding (future-proofs against survey changes)
   clean_var <- recode_missing(raw_var, missing_codes = c(99, 9))
   ```

3. **Use Conservative Composite Score Calculation:** Always use `na.rm = FALSE` in `rowSums()` for composite scores:
   ```r
   # ✅ CORRECT - Preserves missingness
   total_score <- rowSums(item_df[item_cols], na.rm = FALSE)
   # If ANY item is NA, total is NA (conservative, prevents misleading partial scores)

   # ❌ INCORRECT - Creates misleading partial scores
   total_score <- rowSums(item_df[item_cols], na.rm = TRUE)
   # Person who answered 1 item and declined 9 would appear to have low score
   ```

4. **Document Missing Codes:** Add code comments explaining which missing codes are used:
   ```r
   # Recode missing values (99 = "Prefer not to answer")
   # This ensures invalid responses don't contaminate the total score calculation
   ```

**Common Missing Value Codes:**
- `99`: "Prefer not to answer" (most common in NE25 data)
- `9`: "Don't know"
- `-99`, `999`, `9999`: Alternative missing codes
- Factor level "Missing": Used in some categorical variables (e.g., childcare)

**Critical Issue Prevented:** The `recode_missing()` function was added after discovering that 254+ records (5.2% of dataset) had invalid ACE total scores (99-990 instead of 0-10) due to "Prefer not to answer" (99) being summed directly. See `docs/fixes/missing_data_audit_2025_10.md` for full audit.

**Conservative Approach Statement:** All composite scores in the NE25 pipeline use `na.rm = FALSE` in calculations. This conservative approach ensures that if ANY component item is missing, the total score is marked as NA rather than creating potentially misleading partial scores.

**Complete Composite Variables Inventory:**

| Composite Variable | Components | Valid Range | Missing Policy | Defensive Recoding |
|-------------------|-----------|-------------|---------------|-------------------|
| `phq2_total` | 2 depression items | 0-6 | na.rm = FALSE | ✓ c(99, 9) |
| `gad2_total` | 2 anxiety items | 0-6 | na.rm = FALSE | ✓ c(99, 9) |
| `ace_total` | 10 caregiver ACE items | 0-10 | na.rm = FALSE | ✓ c(99) |
| `child_ace_total` | 8 child ACE items | 0-8 | na.rm = FALSE | ✓ c(99, 9) |
| `family_size` | fqlive1_1 + fqlive1_2 + 1 | 1-99 | conditional | ✓ via < 999 check |
| `fpl` | income / threshold × 100 | 0-∞ | NA if components NA | Via family_size |
| `fplcat` | Factor from fpl | 5 categories | Factor NA | Via fpl |
| `years_old` | age_in_days / 365.25 | 0-5 | NA if source NA | No sentinel values |
| `months_old` | years_old × 12 | 0-60 | NA if source NA | Via years_old |
| `urban_pct` | % urban from ZIP | 0-100 | NA if ZIP not found | Database lookup |
| `cc_weekly_cost_*` | Childcare costs | 0-∞ | conditional | Factor "Missing" |
| `cc_any_support` | family OR subsidy | Binary | conditional | Factor "Missing" |

**Impact on Sample Size (N=4,900):**
- `phq2_total`: 3,108 non-missing (63.4%), 1,792 missing (36.6%)
- `gad2_total`: 3,100 non-missing (63.3%), 1,800 missing (36.7%)
- `ace_total`: 2,704 non-missing (55.2%), 2,196 missing (44.8%)
- `child_ace_total`: 3,881 non-missing (99.6%), 19 missing (0.4%)
- `fpl`: 3,773 non-missing (97.4%), 127 missing (2.6%)

**Detailed Documentation:** See `R/transform/README.md` section "Composite Variables: Complete Inventory and Missing Data Policy" for full implementation details, code examples, and validation procedures.

**Validation Checklist:**
- [ ] Checked REDCap data dictionary for missing codes
- [ ] Applied `recode_missing()` before variable assignment
- [ ] Used `na.rm = FALSE` in composite score calculation
- [ ] Tested with sample data containing 99 values
- [ ] Verified no sentinel values (99, 9, etc.) persist in transformed data
- [ ] Confirmed composite scores are NA when any component is missing
- [ ] Validated all composite variables against expected valid ranges
- [ ] Documented missing data patterns and sample size impact
- [ ] Updated composite variables inventory table if adding new composite variables

### Creating New Composite Variables (Checklist)

**When adding a new composite variable to the NE25 pipeline, follow this checklist to ensure proper missing data handling and documentation:**

**1. Implementation (R/transform/ne25_transforms.R)**
- [ ] Apply `recode_missing()` to ALL component variables before calculation
- [ ] Use `na.rm = FALSE` in `rowSums()` or aggregation functions
- [ ] Document valid range in code comments (e.g., "0-10 for ACE total")
- [ ] Add descriptive variable label using `labelled::var_label()`
- [ ] Test with sample data containing sentinel values (99, 9, etc.)

**2. Validation**
- [ ] Create validation query to check for values outside valid range
- [ ] Verify no sentinel values (99, 9, -99, 999) persist in transformed data
- [ ] Run automated validation script: `python scripts/validation/validate_composite_variables.py`
- [ ] Document missing data patterns and sample size impact

**3. Documentation Updates (Required for ALL new composites)**
- [ ] Add variable to `config/derived_variables.yaml` composite_variables section with:
  - `is_composite: true`
  - `components: [list of source variables]`
  - `valid_range: [min, max]`
  - `missing_policy: "na.rm = FALSE"` (or describe custom logic)
  - `defensive_recoding: "c(99, 9)"` (or specify codes)
  - `category: "Mental Health"` (or appropriate category)
  - `sample_size_impact: "stats or 'Production variable'"`
- [ ] Add variable to composite inventory table in `R/transform/README.md` (lines 617-638)
- [ ] Add variable to composite inventory table in `CLAUDE.md` (lines 424-437)
- [ ] Update derived variable count in documentation (currently 99 → 100+)

**4. Template Available**
- See `R/transform/composite_variable_template.R` for complete example code
- Includes defensive recoding pattern, calculation, validation, and documentation

**Example: Adding a new 3-item scale "xyz_total"**
```r
# Step 1: Defensive recoding
xyz_df <- dat %>%
  dplyr::mutate(
    xyz_item1 = recode_missing(dat$rawvar1, missing_codes = c(99, 9)),
    xyz_item2 = recode_missing(dat$rawvar2, missing_codes = c(99, 9)),
    xyz_item3 = recode_missing(dat$rawvar3, missing_codes = c(99, 9))
  )

# Step 2: Calculate composite (na.rm = FALSE)
xyz_df$xyz_total <- rowSums(
  xyz_df[c("xyz_item1", "xyz_item2", "xyz_item3")],
  na.rm = FALSE  # Conservative: ANY missing component → NA total
)

# Step 3: Validation query (Python/DuckDB)
# SELECT COUNT(*) FROM ne25_transformed WHERE xyz_total > 9  -- Should be 0
# SELECT COUNT(*) - COUNT(xyz_total) as missing FROM ne25_transformed

# Step 4: Update all 3 documentation files with new variable details
```

**Critical Reminders:**
- ⚠️ **NEVER** use `na.rm = TRUE` for composite scores (creates misleading partial scores)
- ⚠️ **ALWAYS** apply `recode_missing()` before calculation (prevents sentinel value contamination)
- ⚠️ **ALWAYS** update all 3 documentation locations (README.md, CLAUDE.md, YAML)

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
4. **Transformations:** R applies recode_it() for 99 derived variables
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

### 99 Derived Variables Created by recode_it()

**Eligibility (3):** `eligible`, `authentic`, `include`
**Race/Ethnicity (6):** `hisp`, `race`, `raceG`, `a1_hisp`, `a1_race`, `a1_raceG`
**Education (12):** 8/4/6-category versions of `educ_max`, `educ_a1`, `educ_a2`, `educ_mom`
**Income (6):** `income`, `inc99`, `family_size`, `federal_poverty_threshold`, `fpl`, `fplcat`, `fpl_derivation_flag`
**Mental Health - PHQ-2 (5):** `phq2_interest`, `phq2_depressed`, `phq2_total`, `phq2_positive`, `phq2_risk_cat`
**Mental Health - GAD-2 (5):** `gad2_nervous`, `gad2_worry`, `gad2_total`, `gad2_positive`, `gad2_risk_cat`
**Caregiver ACEs (12):** `ace_neglect`, `ace_parent_loss`, `ace_mental_illness`, `ace_substance_use`, `ace_domestic_violence`, `ace_incarceration`, `ace_verbal_abuse`, `ace_physical_abuse`, `ace_emotional_neglect`, `ace_sexual_abuse`, `ace_total`, `ace_risk_cat`
**Child ACEs (10):** `child_ace_parent_divorce`, `child_ace_parent_death`, `child_ace_parent_jail`, `child_ace_domestic_violence`, `child_ace_neighborhood_violence`, `child_ace_mental_illness`, `child_ace_substance_use`, `child_ace_discrimination`, `child_ace_total`, `child_ace_risk_cat`
**Childcare (21):** Access, costs, quality, subsidies, derived indicators for formal care and intensity
**Geographic (25):** PUMA, County, Tract, CBSA, Urban/Rural, School/Legislative/Congressional districts, Native Lands

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

## Current Status (October 2025)

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

### ✅ NHIS Pipeline - Production Ready (Phases 1-7 Complete)
- **API Integration:** Direct IPUMS NHIS API extraction via ipumspy (collection: `nhis`)
- **Multi-Year Data:** 6 annual samples (2019-2024), 64 variables, 229,609 records (Oct 2025)
- **Smart Caching:** SHA256-based caching (years + samples + variables signature)
- **R Validation:** 7 comprehensive checks (variables, years, survey design, ACEs, mental health)
- **Testing (Phase 6):** Complete test suite passing - API connection test, end-to-end pipeline test (3.4s execution), performance benchmarks documented
- **Production (Phase 7):** Full 2019-2024 extraction (61s processing), 188,620 sample persons + 40,989 non-sample, database insertion complete
- **Performance:** Cache retrieval <1s (60x faster), production extraction 61s, database insertion <1s
- **Status:** Production ready, all 7 phases complete (Oct 2025)

### ✅ NSCH Pipeline - Production Ready (Phases 1-7 Complete)
- **SPSS Integration:** Direct loading from SPSS files via pyreadstat
- **Multi-Year Data:** 7 years successfully loaded (2017-2023), 284,496 records, 3,780 unique variables
- **Automated Pipeline:** Batch processing handles SPSS → Feather → R validation → Database in single command
- **R Validation:** 7 comprehensive QC checks per year (HHID, record count, columns, data types, missing values)
- **Metadata System:** Auto-generated variable reference (3,780 variables), 36,164 value label mappings
- **Documentation (Phase 7):** 10 comprehensive guides (629 KB) - README, pipeline usage, database schema, example queries, troubleshooting, testing, variable reference, executive summary
- **Performance:** Single year in 20 seconds, batch (7 years) in 2 minutes, 200:1 compression ratio
- **Status:** Production ready, 7/8 years loaded (2016 schema incompatibility documented), all 7 phases complete (Oct 2025)

### ✅ Architecture Simplified
- **CID8 Removed:** No more complex IRT analysis causing instability
- **8 Eligibility Criteria:** CID1-7 + completion (was 9)
- **Feather Migration:** Perfect R factor ↔ pandas category preservation
- **Response Sets:** Study-specific missing value conventions (NE25: 9, others: -9)
- **Four Pipeline Design:** NE25 (local survey) + ACS (census) + NHIS (national health) + NSCH (child health survey) as independent, complementary systems

### Quick Debugging
1. **Database:** `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"`
2. **R Packages:** Use temp script files, never inline `-e`
3. **Pipeline:** Run from project root directory
4. **Logs:** Check Python error context for detailed debugging
5. **HTML Docs:** `python scripts/documentation/generate_html_documentation.py`

---
*Updated: October 2025 | Version: 3.1.0*