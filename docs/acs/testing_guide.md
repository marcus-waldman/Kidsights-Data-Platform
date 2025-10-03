# ACS Pipeline Testing Guide

**Purpose**: Guide for testing and validating the ACS pipeline to ensure correctness and reliability.

**Version**: 1.0.0
**Last Updated**: 2025-10-03

---

## Table of Contents

- [Quick Start](#quick-start)
- [Test 1: API Connection](#test-1-api-connection)
- [Test 2: End-to-End Pipeline](#test-2-end-to-end-pipeline)
- [Test 3: Web UI Comparison](#test-3-web-ui-comparison)
- [Test 4: Metadata Validation](#test-4-metadata-validation)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- IPUMS API key configured: `C:/Users/waldmanm/my-APIs/IPUMS.txt`
- Python environment with ipumspy, pandas, pyarrow
- R 4.5.1+ with arrow, dplyr packages

### Fast Test Workflow

```bash
# 1. Test API connection
python scripts/acs/test_api_connection.py --test-connection

# 2. Submit test extract (Nebraska 2021, ~5-15 min processing)
python scripts/acs/test_api_connection.py --submit-test

# 3. Wait for processing, then check status
python scripts/acs/test_api_connection.py --check-status usa:12345

# 4. Download test extract
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021

# 5. Run end-to-end test
Rscript scripts/acs/test_pipeline_end_to_end.R
```

---

## Test 1: API Connection

### Purpose

Verify IPUMS API authentication and connectivity before submitting extracts.

### Test Script

`scripts/acs/test_api_connection.py`

### Usage

```bash
# Test connection only
python scripts/acs/test_api_connection.py --test-connection

# Submit test extract
python scripts/acs/test_api_connection.py --submit-test

# Full workflow
python scripts/acs/test_api_connection.py --full-test
```

### Expected Output

```
======================================================================
TEST 1: API CONNECTION
======================================================================

Connecting to IPUMS API...
[OK] Successfully connected to IPUMS API
     Client: <IpumsApiClient object at 0x...>
```

### Test Extract Details

- **State**: Nebraska
- **Sample**: 2021 1-year ACS (us2021a)
- **Population**: Children ages 0-5
- **Processing Time**: 5-15 minutes (vs 45+ min for 5-year sample)
- **Records**: ~9,000 (vs ~45,000 for 5-year)

### Troubleshooting

**API Key Error**:
```
FileNotFoundError: API key file not found: C:/Users/waldmanm/my-APIs/IPUMS.txt
```

**Solution**: Create file with IPUMS API key from https://account.ipums.org/api_keys

---

## Test 2: End-to-End Pipeline

### Purpose

Comprehensive test of the full pipeline workflow including data loading, validation, and database operations.

### Test Script

`scripts/acs/test_pipeline_end_to_end.R`

### Usage

```bash
# Run with test data (nebraska 2021)
Rscript scripts/acs/test_pipeline_end_to_end.R

# Run with custom state/year
Rscript scripts/acs/test_pipeline_end_to_end.R \
    --state nebraska \
    --year-range 2019-2023 \
    --state-fip 31
```

### Test Coverage

The end-to-end test runs **6 comprehensive tests**:

#### Test 1: Feather File Loading
- Verifies Feather file exists
- Loads data with arrow::read_feather()
- Checks basic structure (rows, columns)

#### Test 2: Data Validation
- Runs full validate_acs_raw_data() workflow
- Checks variable presence
- Verifies attached characteristics
- Validates filters applied (AGE 0-5, STATEFIP correct)
- Checks for duplicates

#### Test 3: Variable Presence
- Verifies core variables (YEAR, SERIAL, PERNUM, AGE, SEX, RACE, etc.)
- Checks attached characteristics (EDUC_mom, EDUC_pop, MARST_head)

#### Test 4: Value Ranges
- AGE in [0, 5]
- SEX in [1, 2]
- PERWT coverage > 99%

#### Test 5: Database Connection
- Checks database file exists
- Verifies connectivity

#### Test 6: Summary Statistics
- Age distribution
- Sex distribution
- Sampling weights summary

### Expected Output

```
======================================================================
ACS PIPELINE END-TO-END TEST
======================================================================
Started: 2025-09-30 15:23:45

Test Configuration:
  State: nebraska
  Year Range: 2021
  State FIP: 31

======================================================================
TEST 1: FEATHER FILE LOADING
======================================================================

[PASS] Feather file loaded: 9,123 rows, 32 columns

======================================================================
TEST 2: DATA VALIDATION
======================================================================

[PASS] Variable Presence: All expected variables present
[PASS] Attached Characteristics: Found 5 attached characteristic(s)
[PASS] Age Filter: 100.0% of records have AGE in [0, 5]
[PASS] State Filter: 100.0% of records have STATEFIP = 31
[PASS] Unique Records: No duplicate SERIAL+PERNUM combinations
[PASS] Sampling Weights: PERWT present for 100.0% of records

======================================================================
TEST 3: VARIABLE PRESENCE
======================================================================

[PASS] All core variables present
[PASS] All attached characteristics present

======================================================================
TEST 4: VALUE RANGES
======================================================================

[PASS] AGE range correct: [0, 5]
[PASS] SEX values correct: [1, 2]
[PASS] PERWT coverage: 100.0%

======================================================================
TEST 5: DATABASE CONNECTION
======================================================================

[PASS] Database file exists: data/duckdb/kidsights_local.duckdb

======================================================================
TEST 6: SUMMARY STATISTICS
======================================================================

Total records: 9,123
Total variables: 32

Age distribution:
  Age 0: 1,520 (16.7%)
  Age 1: 1,518 (16.6%)
  Age 2: 1,524 (16.7%)
  Age 3: 1,519 (16.7%)
  Age 4: 1,522 (16.7%)
  Age 5: 1,520 (16.7%)

Sex distribution:
  Male: 4,672 (51.2%)
  Female: 4,451 (48.8%)

Sampling weights (PERWT):
  Min: 12.00
  Mean: 1,234.56
  Max: 8,901.23
  Sum: 11,260,000

======================================================================
[PASS] ALL TESTS PASSED
======================================================================
Completed: 2025-09-30 15:24:12
```

---

## Test 3: Web UI Comparison

### Purpose

Validate that IPUMS API produces identical results to the IPUMS web interface (the "gold standard").

### Manual Process

Since this requires web interface interaction, it's a manual validation process:

#### Step 1: Create Web Interface Extract

1. Go to https://usa.ipums.org/usa/
2. Click "Get Data"
3. Select sample: **2021 ACS**
4. Select variables (match API config):
   - Household: YEAR, SERIAL, HHWT
   - Person: PERNUM, PERWT, AGE, SEX, RACE, HISPAN
   - Geography: STATEFIP, PUMA, METRO
   - Economic: HHINCOME, FTOTINC, POVERTY, GRPIP
   - Programs: FOODSTMP, HINSCAID, HCOVANY
   - Education: EDUC, EDUCD
   - Household: RELATE, MARST, MOMLOC, POPLOC
5. **Attach characteristics**:
   - EDUC: mother, father
   - EDUCD: mother, father
   - MARST: head
6. **Create extract**
7. **Apply filters**:
   - AGE: 0-5
   - STATEFIP: 31 (Nebraska)
8. Submit extract
9. Download when ready

#### Step 2: Compare Results

Load both API and web UI extracts and compare:

```r
# Load API extract
api_data <- arrow::read_feather("data/acs/nebraska/2021/raw.feather")

# Load web UI extract (adjust path)
web_data <- haven::read_dta("path/to/web_ui_extract.dta")
# or
web_data <- read.csv("path/to/web_ui_extract.csv")

# Compare dimensions
cat(sprintf("API records: %s\n", nrow(api_data)))
cat(sprintf("Web records: %s\n", nrow(web_data)))

# Compare variables
api_vars <- sort(names(api_data))
web_vars <- sort(names(web_data))

# Variables only in API
setdiff(api_vars, web_vars)

# Variables only in Web
setdiff(web_vars, api_vars)

# Compare a few records
head(api_data %>% dplyr::select(SERIAL, PERNUM, AGE, SEX, EDUC_mom, EDUC_pop))
head(web_data %>% dplyr::select(SERIAL, PERNUM, AGE, SEX, EDUC_mom, EDUC_pop))
```

#### Step 3: Verify Attached Characteristics

Critical check: Ensure attached characteristics match exactly

```r
# Check EDUC_mom matching
api_educ_mom <- api_data %>%
  dplyr::select(SERIAL, PERNUM, EDUC_mom) %>%
  dplyr::arrange(SERIAL, PERNUM)

web_educ_mom <- web_data %>%
  dplyr::select(SERIAL, PERNUM, EDUC_mom) %>%
  dplyr::arrange(SERIAL, PERNUM)

# Should be identical
all.equal(api_educ_mom, web_educ_mom)
```

### Expected Results

- **Record counts**: Should match exactly
- **Variables**: Should have identical set (order may differ)
- **Attached characteristics**: Values should match exactly for same SERIAL+PERNUM
- **Sampling weights**: Should be identical

### Common Discrepancies

**Different variable order**: OK, just column order difference

**Different data formats**: OK if values are the same (e.g., numeric vs integer)

**Missing metadata columns**: API may add `state`, `year_range` columns - filter these out for comparison

**Different missing value codes**: IPUMS sometimes uses different NA representations - verify coding

---

## Test 4: Metadata Validation

### Purpose

Verify that DDI metadata is correctly parsed, loaded into DuckDB, and accessible via Python and R utilities.

### Prerequisites

- ACS data extracted for at least one state (Nebraska or Minnesota)
- Metadata tables populated in DuckDB

### Python Metadata Tests

#### Test 4.1: Verify Metadata Tables

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    # Check acs_variables table
    var_count = conn.execute("SELECT COUNT(*) FROM acs_variables").fetchone()[0]
    print(f"✓ Variables: {var_count}")
    # Expected: 42

    # Check acs_value_labels table
    label_count = conn.execute("SELECT COUNT(*) FROM acs_value_labels").fetchone()[0]
    print(f"✓ Value Labels: {label_count}")
    # Expected: 1,144

    # Check acs_metadata_registry table
    ddi_count = conn.execute("SELECT COUNT(*) FROM acs_metadata_registry").fetchone()[0]
    print(f"✓ DDI Files: {ddi_count}")
    # Expected: 2 (Nebraska + Minnesota)

    # Check variable types
    types = conn.execute("SELECT type, COUNT(*) FROM acs_variables GROUP BY type").df()
    print("\n✓ Variables by Type:")
    print(types)
    # Expected: categorical=28, continuous=9, identifier=5
```

#### Test 4.2: Value Decoding

```python
from python.acs.metadata_utils import decode_value

# Test state decoding
assert decode_value('STATEFIP', 27, db) == "Minnesota"
assert decode_value('STATEFIP', 31, db) == "Nebraska"
print("✓ State decoding works")

# Test sex decoding
assert decode_value('SEX', 1, db) == "Male"
assert decode_value('SEX', 2, db) == "Female"
print("✓ Sex decoding works")

# Test age decoding
assert decode_value('AGE', 0, db) == "Under 1 year"
assert decode_value('AGE', 5, db) == "5"
print("✓ Age decoding works")
```

#### Test 4.3: DataFrame Decoding

```python
import pandas as pd
from python.acs.metadata_utils import decode_dataframe

# Create test DataFrame
test_df = pd.DataFrame({
    'STATEFIP': [27, 31, 27],
    'SEX': [1, 2, 1],
    'AGE': [0, 3, 5]
})

# Decode
decoded = decode_dataframe(test_df, ['STATEFIP', 'SEX', 'AGE'], db)

# Verify new columns exist
assert 'STATEFIP_label' in decoded.columns
assert 'SEX_label' in decoded.columns
assert 'AGE_label' in decoded.columns
print("✓ DataFrame decoding creates label columns")

# Verify values
assert decoded['STATEFIP_label'].iloc[0] == "Minnesota"
assert decoded['SEX_label'].iloc[1] == "Female"
print("✓ DataFrame decoding values correct")
```

#### Test 4.4: Variable Search

```python
from python.acs.metadata_utils import search_variables

# Search for education variables
educ_vars = search_variables('education', db)
assert len(educ_vars) >= 2  # Should find EDUC, EDUCD
print(f"✓ Found {len(educ_vars)} education variables")

# Search for income variables
income_vars = search_variables('income', db)
assert len(income_vars) >= 3  # Should find HHINCOME, FTOTINC, etc.
print(f"✓ Found {len(income_vars)} income variables")
```

### R Metadata Tests

#### Test 4.5: R Metadata Access

```r
source("R/utils/acs/acs_metadata.R")

# Test variable info
var_info <- acs_get_variable_info("STATEFIP")
stopifnot(var_info$type == "categorical")
cat("✓ R variable info works\n")

# Test value decoding
state <- acs_decode_value("STATEFIP", 31)
stopifnot(state == "Nebraska")
cat("✓ R value decoding works\n")

# Test DataFrame decoding
test_df <- data.frame(
  STATEFIP = c(27, 31, 27),
  SEX = c(1, 2, 1)
)
decoded_df <- acs_decode_column(test_df, "STATEFIP")
decoded_df <- acs_decode_column(decoded_df, "SEX")
stopifnot("STATEFIP_label" %in% names(decoded_df))
stopifnot(decoded_df$STATEFIP_label[1] == "Minnesota")
cat("✓ R DataFrame decoding works\n")

# Test variable search
educ_vars <- acs_search_variables("education")
stopifnot(nrow(educ_vars) >= 2)
cat("✓ R variable search works (found", nrow(educ_vars), "education variables)\n")

# Test type checking
stopifnot(acs_is_categorical("STATEFIP") == TRUE)
stopifnot(acs_is_categorical("PERWT") == FALSE)
cat("✓ R type checking works\n")
```

### Expected Output

**Successful Test Run:**
```
✓ Variables: 42
✓ Value Labels: 1144
✓ DDI Files: 2

✓ Variables by Type:
        type  count
0  categorical     28
1  continuous       9
2  identifier       5

✓ State decoding works
✓ Sex decoding works
✓ Age decoding works
✓ DataFrame decoding creates label columns
✓ DataFrame decoding values correct
✓ Found 2 education variables
✓ Found 4 income variables

✓ R variable info works
✓ R value decoding works
✓ R DataFrame decoding works
✓ R variable search works (found 2 education variables)
✓ R type checking works

[TEST PASSED] All metadata validation tests passed
```

### Common Issues

#### Metadata Tables Empty

**Problem**: Variable count is 0

**Solution**:
```bash
# Load metadata manually
python pipelines/python/acs/load_acs_metadata.py --load-all
```

#### Decoding Returns Original Value

**Problem**: `decode_value('STATEFIP', 31)` returns `"31"` instead of `"Nebraska"`

**Cause**: No value labels found for variable

**Check**:
```python
from python.acs.metadata_utils import get_value_labels
labels = get_value_labels('STATEFIP', db)
print(f"Found {len(labels)} labels")
```

#### R Function Not Found

**Problem**: `Error: object 'acs_decode_value' not found`

**Solution**:
```r
# Source metadata functions
source("R/utils/acs/acs_metadata.R")
```

---

## Troubleshooting

### Test Extract Takes Too Long

**Problem**: Test extract exceeds 15 minutes

**Solution**:
- Check IPUMS system status: https://status.ipums.org/
- Peak times may have longer queues
- Try submitting during off-peak hours (evenings, weekends)

### Feather File Not Found

**Problem**: `test_pipeline_end_to_end.R` can't find Feather file

**Solution**:
```bash
# Run extraction first
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021

# Then run test
Rscript scripts/acs/test_pipeline_end_to_end.R
```

### API Connection Failed

**Problem**: `test_api_connection.py` fails with 401 Unauthorized

**Solution**:
1. Verify API key file exists: `C:/Users/waldmanm/my-APIs/IPUMS.txt`
2. Check API key is valid: https://account.ipums.org/api_keys
3. Regenerate API key if needed

### Attached Characteristics Missing

**Problem**: EDUC_mom, EDUC_pop not in data

**Solution**:
1. Check config has `attach_characteristics`:
   ```yaml
   variables:
     - name: EDUC
       attach_characteristics: [mother, father]
   ```
2. Re-run extraction with `--force-refresh`

### Test Validation Fails

**Problem**: Value range tests fail

**Check**:
- Are filters applied correctly? (AGE 0-5, STATEFIP 31)
- Is data corrupted? Re-download extract
- Is cache stale? Use `--force-refresh`

---

## Additional Testing

### Performance Testing

Test cache performance:

```bash
# First run (no cache) - time it
time python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021

# Second run (with cache) - should be much faster
time python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021
```

### Multi-State Testing

Test batch processing:

```bash
python scripts/acs/run_multiple_states.py \
    --states nebraska iowa kansas \
    --year-range 2021 \
    --skip-extraction  # If already extracted
```

### Cache Management Testing

Test cache utilities:

```bash
# List caches
python scripts/acs/manage_cache.py --list

# Validate integrity
python scripts/acs/manage_cache.py --validate

# Show statistics
python scripts/acs/manage_cache.py --stats
```

---

## Continuous Integration

For automated testing in CI/CD:

```yaml
# .github/workflows/test-acs-pipeline.yml (example)
name: Test ACS Pipeline

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Setup Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.13'

      - name: Setup R
        uses: r-lib/actions/setup-r@v2

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          Rscript -e "install.packages(c('arrow', 'dplyr'))"

      - name: Run API connection test
        run: python scripts/acs/test_api_connection.py --test-connection
        env:
          IPUMS_API_KEY: ${{ secrets.IPUMS_API_KEY }}

      # Note: Full pipeline tests require submitted extracts
      # These would run on a schedule or manual trigger
```

---

**For variable details and IPUMS coding**, see [ipums_variables_reference.md](ipums_variables_reference.md)
**For pipeline usage**, see [pipeline_usage.md](pipeline_usage.md)

**Last Updated**: 2025-09-30
**Pipeline Version**: 1.0.0
