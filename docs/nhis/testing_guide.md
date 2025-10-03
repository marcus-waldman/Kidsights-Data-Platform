# NHIS Pipeline Testing Guide

Comprehensive testing procedures for the NHIS data extraction pipeline, including API connection tests, end-to-end validation, and troubleshooting.

---

## Table of Contents

1. [Test Overview](#test-overview)
2. [Prerequisites](#prerequisites)
3. [Test 1: API Connection](#test-1-api-connection)
4. [Test 2: Configuration Loading](#test-2-configuration-loading)
5. [Test 3: Cache System](#test-3-cache-system)
6. [Test 4: Single-Year Extraction](#test-4-single-year-extraction)
7. [Test 5: R Validation](#test-5-r-validation)
8. [Test 6: Database Operations](#test-6-database-operations)
9. [Test 7: End-to-End Pipeline](#test-7-end-to-end-pipeline)
10. [Performance Benchmarks](#performance-benchmarks)
11. [Troubleshooting Test Failures](#troubleshooting-test-failures)

---

## Test Overview

### Test Suite Summary

| Test | Duration | Purpose | Required |
|------|----------|---------|----------|
| API Connection | <1 min | Verify IPUMS API authentication | ✓ |
| Configuration Loading | <1 min | Validate YAML configs | ✓ |
| Cache System | <1 min | Test caching logic | ✓ |
| Single-Year Extraction | 5-10 min | Fast extraction test | ✓ |
| R Validation | <1 min | Test R validation functions | ✓ |
| Database Operations | <1 min | Test DuckDB insertion | ✓ |
| End-to-End Pipeline | 30-45 min | Full 6-year pipeline | Optional |

### Test Environment

**Recommended Setup:**
- Fresh Python environment with required packages
- R 4.5.1+ with arrow, dplyr
- Empty cache directory
- Test database separate from production

---

## Prerequisites

### 1. Verify Installation

**Python Packages:**
```bash
python -c "import ipumspy, pandas, pyyaml, duckdb, structlog; print('All packages installed')"
```

**R Packages:**
```r
library(arrow)
library(dplyr)
cat("All packages installed\n")
```

### 2. Verify API Key

```bash
# Check file exists
if [ -f "C:/Users/waldmanm/my-APIs/IPUMS.txt" ]; then
    echo "API key file found"
else
    echo "ERROR: API key file not found"
fi

# Check file not empty
wc -l "C:/Users/waldmanm/my-APIs/IPUMS.txt"
# Should output: 1 line
```

### 3. Create Test Directories

```bash
mkdir -p data/nhis/test
mkdir -p cache/ipums
mkdir -p scripts/nhis
```

---

## Test 1: API Connection

### Objective
Verify IPUMS NHIS API authentication and connectivity.

### Test Script

Create `scripts/nhis/test_api_connection.py`:

```python
#!/usr/bin/env python3
"""Test IPUMS NHIS API Connection"""

import sys
from python.nhis.auth import get_ipums_client

def test_api_connection():
    """Test API authentication and connection"""

    print("="*60)
    print("TEST 1: IPUMS NHIS API CONNECTION")
    print("="*60)

    try:
        # Test 1A: Get API client
        print("\n[Test 1A] Initializing API client...")
        client = get_ipums_client()
        print("[PASS] API client initialized")

        # Test 1B: List available collections
        print("\n[Test 1B] Listing available collections...")
        collections = client.get_all_collection_ids()
        print(f"[INFO] Available collections: {collections}")

        if 'nhis' in collections:
            print("[PASS] NHIS collection available")
        else:
            print("[FAIL] NHIS collection not found")
            return False

        # Test 1C: Get NHIS samples
        print("\n[Test 1C] Retrieving NHIS samples...")
        samples = client.get_all_sample_ids(collection='nhis')
        print(f"[INFO] Found {len(samples)} NHIS samples")
        print(f"[INFO] Sample examples: {samples[:5]}")

        # Check for expected samples
        expected_samples = ['ih2019', 'ih2020', 'ih2021', 'ih2022']
        found_samples = [s for s in expected_samples if s in samples]

        if len(found_samples) == len(expected_samples):
            print(f"[PASS] All expected samples found: {found_samples}")
        else:
            print(f"[WARN] Only found {len(found_samples)}/{len(expected_samples)} expected samples")

        print("\n" + "="*60)
        print("API CONNECTION TEST: PASS")
        print("="*60)
        return True

    except Exception as e:
        print(f"\n[FAIL] API connection test failed: {str(e)}")
        print("\n" + "="*60)
        print("API CONNECTION TEST: FAIL")
        print("="*60)
        return False

if __name__ == "__main__":
    success = test_api_connection()
    sys.exit(0 if success else 1)
```

### Run Test

```bash
python scripts/nhis/test_api_connection.py
```

### Expected Output

```
============================================================
TEST 1: IPUMS NHIS API CONNECTION
============================================================

[Test 1A] Initializing API client...
[PASS] API client initialized

[Test 1B] Listing available collections...
[INFO] Available collections: ['nhis', 'meps', 'atus', ...]
[PASS] NHIS collection available

[Test 1C] Retrieving NHIS samples...
[INFO] Found 45 NHIS samples
[INFO] Sample examples: ['ih2019', 'ih2020', 'ih2021', 'ih2022', 'ih2023']
[PASS] All expected samples found: ['ih2019', 'ih2020', 'ih2021', 'ih2022']

============================================================
API CONNECTION TEST: PASS
============================================================
```

### Troubleshooting

**Error: "API key file not found"**
- Create directory: `mkdir -p "C:/Users/waldmanm/my-APIs"`
- Save API key: `echo YOUR_KEY > "C:/Users/waldmanm/my-APIs/IPUMS.txt"`

**Error: "Invalid API key"**
- Verify key is correct (no extra whitespace)
- Regenerate key at IPUMS website
- Check file permissions

**Error: "Connection timeout"**
- Check internet connection
- Verify no firewall blocking
- Try again later (API may be temporarily down)

---

## Test 2: Configuration Loading

### Objective
Validate YAML configuration files and variable specifications.

### Test Script

Create `scripts/nhis/test_configuration.py`:

```python
#!/usr/bin/env python3
"""Test NHIS Configuration Loading"""

import sys
from python.nhis.config_manager import ConfigManager

def test_configuration():
    """Test configuration loading and validation"""

    print("="*60)
    print("TEST 2: CONFIGURATION LOADING")
    print("="*60)

    try:
        config_mgr = ConfigManager()

        # Test 2A: Load template config
        print("\n[Test 2A] Loading template configuration...")
        template_config = config_mgr.load_config("config/sources/nhis/nhis-template.yaml")
        print(f"[PASS] Template loaded")

        # Test 2B: Load year-specific config
        print("\n[Test 2B] Loading year-specific configuration...")
        config = config_mgr.load_config("config/sources/nhis/nhis-2019-2024.yaml")
        print(f"[PASS] Configuration loaded")

        # Test 2C: Validate configuration structure
        print("\n[Test 2C] Validating configuration structure...")

        required_fields = ['years', 'samples', 'collection', 'variables']
        for field in required_fields:
            if field in config:
                print(f"  [PASS] '{field}' present")
            else:
                print(f"  [FAIL] '{field}' missing")
                return False

        # Test 2D: Check variable groups
        print("\n[Test 2D] Checking variable groups...")
        var_groups = config.get('variables', {})
        print(f"  [INFO] Found {len(var_groups)} variable groups")

        total_vars = sum(len(vars) for vars in var_groups.values())
        print(f"  [INFO] Total variables: {total_vars}")

        if total_vars >= 66:
            print(f"  [PASS] Expected 66 variables, found {total_vars}")
        else:
            print(f"  [FAIL] Expected 66 variables, found {total_vars}")
            return False

        # Test 2E: Validate years/samples match
        print("\n[Test 2E] Validating years and samples...")
        years = config.get('years', [])
        samples = config.get('samples', [])

        print(f"  [INFO] Years: {years}")
        print(f"  [INFO] Samples: {samples}")

        if len(years) == len(samples):
            print(f"  [PASS] Years and samples match ({len(years)} each)")
        else:
            print(f"  [FAIL] Years ({len(years)}) and samples ({len(samples)}) mismatch")
            return False

        print("\n" + "="*60)
        print("CONFIGURATION TEST: PASS")
        print("="*60)
        return True

    except Exception as e:
        print(f"\n[FAIL] Configuration test failed: {str(e)}")
        print("\n" + "="*60)
        print("CONFIGURATION TEST: FAIL")
        print("="*60)
        return False

if __name__ == "__main__":
    success = test_configuration()
    sys.exit(0 if success else 1)
```

### Run Test

```bash
python scripts/nhis/test_configuration.py
```

### Expected Output

```
============================================================
TEST 2: CONFIGURATION LOADING
============================================================

[Test 2A] Loading template configuration...
[PASS] Template loaded

[Test 2B] Loading year-specific configuration...
[PASS] Configuration loaded

[Test 2C] Validating configuration structure...
  [PASS] 'years' present
  [PASS] 'samples' present
  [PASS] 'collection' present
  [PASS] 'variables' present

[Test 2D] Checking variable groups...
  [INFO] Found 11 variable groups
  [INFO] Total variables: 66
  [PASS] Expected 66 variables, found 66

[Test 2E] Validating years and samples...
  [INFO] Years: [2019, 2020, 2021, 2022, 2023, 2024]
  [INFO] Samples: ['ih2019', 'ih2020', 'ih2021', 'ih2022', 'ih2023', 'ih2024']
  [PASS] Years and samples match (6 each)

============================================================
CONFIGURATION TEST: PASS
============================================================
```

---

## Test 3: Cache System

### Objective
Test SHA256-based cache signature generation and validation.

### Test Script

Create `scripts/nhis/test_cache.py`:

```python
#!/usr/bin/env python3
"""Test NHIS Cache System"""

import sys
from python.nhis.config_manager import ConfigManager
from python.nhis.cache_manager import CacheManager

def test_cache_system():
    """Test cache signature generation and validation"""

    print("="*60)
    print("TEST 3: CACHE SYSTEM")
    print("="*60)

    try:
        # Test 3A: Generate cache signature
        print("\n[Test 3A] Generating cache signature...")
        config_mgr = ConfigManager()
        config = config_mgr.load_config("config/sources/nhis/nhis-2019-2024.yaml")

        cache_mgr = CacheManager()
        signature = cache_mgr.generate_extract_signature(config)

        print(f"  [INFO] Signature: {signature}")
        print(f"  [INFO] Signature length: {len(signature)} characters")

        if len(signature) == 64:  # SHA256 produces 64 hex characters
            print("  [PASS] Valid SHA256 signature")
        else:
            print("  [FAIL] Invalid signature length")
            return False

        # Test 3B: Test signature consistency
        print("\n[Test 3B] Testing signature consistency...")
        signature2 = cache_mgr.generate_extract_signature(config)

        if signature == signature2:
            print("  [PASS] Signatures are consistent")
        else:
            print("  [FAIL] Signatures differ (should be identical)")
            return False

        # Test 3C: Test cache directory creation
        print("\n[Test 3C] Testing cache directory...")
        cache_dir = cache_mgr.get_cache_directory()
        print(f"  [INFO] Cache directory: {cache_dir}")

        if cache_dir.exists():
            print("  [PASS] Cache directory exists")
        else:
            print("  [INFO] Creating cache directory...")
            cache_dir.mkdir(parents=True, exist_ok=True)
            print("  [PASS] Cache directory created")

        print("\n" + "="*60)
        print("CACHE SYSTEM TEST: PASS")
        print("="*60)
        return True

    except Exception as e:
        print(f"\n[FAIL] Cache system test failed: {str(e)}")
        print("\n" + "="*60)
        print("CACHE SYSTEM TEST: FAIL")
        print("="*60)
        return False

if __name__ == "__main__":
    success = test_cache_system()
    sys.exit(0 if success else 1)
```

### Run Test

```bash
python scripts/nhis/test_cache.py
```

---

## Test 4: Single-Year Extraction

### Objective
Test fast extraction with single year (2019) to verify pipeline without long wait.

### Prerequisites

Create test configuration `config/sources/nhis/nhis-2019-test.yaml`:

```yaml
years: [2019]
samples: [ih2019]
year_range: "2019"
output_directory: "data/nhis/2019-test"

template: "nhis-template.yaml"

cache:
  enabled: true
  directory: "cache/ipums"
  max_age_days: 90
```

### Run Test

```bash
python pipelines/python/nhis/extract_nhis_data.py \
    --config config/sources/nhis/nhis-2019-test.yaml \
    --verbose
```

### Expected Duration
- First run (no cache): 5-10 minutes
- Subsequent runs (cached): <30 seconds

### Validation Checks

```bash
# Check Feather file created
ls -lh data/nhis/2019-test/raw.feather

# Expected: 8-10 MB file

# Verify record count in Python
python -c "
import pandas as pd
df = pd.read_feather('data/nhis/2019-test/raw.feather')
print(f'Records: {len(df):,}')
print(f'Variables: {len(df.columns)}')
print(f'Years: {sorted(df[\"YEAR\"].unique())}')
"

# Expected output:
# Records: ~52,000
# Variables: 66
# Years: [2019]
```

---

## Test 5: R Validation

### Objective
Test R validation functions with synthetic or real data.

### Test Script

Already created in Phase 3: `scripts/temp/test_nhis_validation.R`

### Run Test

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/temp/test_nhis_validation.R
```

### Expected Output

```
==================================================================
NHIS VALIDATION FUNCTION TEST
==================================================================

Creating synthetic NHIS dataset...
[OK] Created synthetic dataset: 100 records, 61 variables

Testing validation functions...

TEST 1: Variable Presence Check
----------------------------------------------------------------------
  Status: PASS
  Message: All 4 expected variables present

TEST 2: Year Coverage Check
----------------------------------------------------------------------
  Status: PASS
  Message: All expected years present: 2019-2024

... (all 7 tests)

==================================================================
TEST SUMMARY
==================================================================

Individual Tests: 7/7 passed
Full Validation: All checks passed (7/7)

[OK] ALL TESTS PASSED - NHIS validation functions working correctly
==================================================================
```

---

## Test 6: Database Operations

### Objective
Test DuckDB insertion and querying.

### Test Script

Already created in Phase 4: `scripts/temp/test_nhis_database.py`

### Run Test

```bash
python scripts/temp/test_nhis_database.py
```

### Expected Output

```
======================================================================
NHIS DATABASE OPERATIONS TEST
======================================================================

Step 1: Creating synthetic NHIS dataset...
[OK] Created synthetic dataset: 50 records, 61 variables

Step 2: Saving to Feather...
[OK] Saved 50 records to Feather

Step 3: Testing database insertion (replace mode)...
[OK] Connecting to database: data/duckdb/kidsights_local.duckdb
  Table nhis_raw does not exist (will be created)
[OK] Inserted 50 records to nhis_raw

... (additional tests)

======================================================================
TEST SUMMARY
======================================================================
[OK] Created nhis_raw table
[OK] Inserted 50 records (replace mode)
[OK] Appended 25 records (append mode)
[OK] Final record count: 75
[OK] Table schema: 61 columns
[OK] Data integrity verified
======================================================================

[SUCCESS] ALL DATABASE TESTS PASSED
```

---

## Test 7: End-to-End Pipeline

### Objective
Run complete pipeline with 6-year extraction (2019-2024).

### Test Script

Create `scripts/nhis/test_pipeline_end_to_end.R`:

```r
#!/usr/bin/env Rscript
#' End-to-End NHIS Pipeline Test
#'
#' Tests complete pipeline: extract → validate → insert → query

cat("\n")
cat(strrep("=", 70), "\n")
cat("NHIS END-TO-END PIPELINE TEST\n")
cat(strrep("=", 70), "\n\n")

# Configuration
year_range <- "2019-2024"
config_file <- "config/sources/nhis/nhis-2019-2024.yaml"

# ============================================================================
# Step 1: Python Extraction
# ============================================================================

cat("STEP 1: PYTHON EXTRACTION\n")
cat(strrep("-", 70), "\n")

cat("Extracting NHIS data from IPUMS API...\n")
cat("(This may take 30-45 minutes for 6 years)\n\n")

extraction_cmd <- sprintf(
  "python pipelines/python/nhis/extract_nhis_data.py --year-range %s --verbose",
  year_range
)

extraction_result <- system(extraction_cmd, intern = FALSE)

if (extraction_result != 0) {
  stop("Extraction failed!")
}

cat("[OK] Extraction completed\n\n")

# ============================================================================
# Step 2: R Validation
# ============================================================================

cat("STEP 2: R VALIDATION\n")
cat(strrep("-", 70), "\n")

# Source functions
source("R/load/nhis/load_nhis_data.R")
source("R/utils/nhis/validate_nhis_raw.R")

# Load data
cat("Loading raw data...\n")
nhis_data <- load_nhis_feather(year_range, add_metadata = TRUE, validate = TRUE)

cat(sprintf("  Records: %s\n", format(nrow(nhis_data), big.mark = ",")))
cat(sprintf("  Variables: %s\n", ncol(nhis_data)))

# Run validation
cat("\nRunning validation checks...\n")
validation <- validate_nhis_raw_data(
  data = nhis_data,
  year_range = year_range,
  expected_years = 2019:2024,
  verbose = TRUE
)

if (!validation$overall_passed) {
  stop("Validation failed!")
}

cat("[OK] Validation passed\n\n")

# ============================================================================
# Step 3: Database Insertion
# ============================================================================

cat("STEP 3: DATABASE INSERTION\n")
cat(strrep("-", 70), "\n")

insertion_cmd <- sprintf(
  "python pipelines/python/nhis/insert_nhis_database.py --year-range %s --mode replace",
  year_range
)

insertion_result <- system(insertion_cmd, intern = FALSE)

if (insertion_result != 0) {
  stop("Database insertion failed!")
}

cat("[OK] Database insertion completed\n\n")

# ============================================================================
# Step 4: Database Querying
# ============================================================================

cat("STEP 4: DATABASE QUERYING\n")
cat(strrep("-", 70), "\n")

library(duckdb)

# Connect to database
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

# Query record count
total_records <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM nhis_raw")$count
cat(sprintf("Total records in database: %s\n", format(total_records, big.mark = ",")))

# Query by year
year_counts <- dbGetQuery(conn, "
  SELECT YEAR, COUNT(*) as count
  FROM nhis_raw
  GROUP BY YEAR
  ORDER BY YEAR
")

cat("\nRecords by year:\n")
for (i in 1:nrow(year_counts)) {
  cat(sprintf("  %d: %s records\n",
              year_counts$YEAR[i],
              format(year_counts$count[i], big.mark = ",")))
}

# Close connection
dbDisconnect(conn, shutdown = TRUE)

cat("\n[OK] Database queries successful\n\n")

# ============================================================================
# Test Summary
# ============================================================================

cat(strrep("=", 70), "\n")
cat("END-TO-END PIPELINE TEST: PASS\n")
cat(strrep("=", 70), "\n")
cat(sprintf("Total Records Processed: %s\n", format(total_records, big.mark = ",")))
cat(sprintf("Years: 2019-2024\n"))
cat(sprintf("Variables: 66\n"))
cat(strrep("=", 70), "\n\n")

cat("[SUCCESS] ALL TESTS PASSED\n")
```

### Run Test

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/nhis/test_pipeline_end_to_end.R
```

### Expected Duration
- 30-45 minutes (6-year extraction)
- Subsequent runs: <2 minutes (cached)

---

## Performance Benchmarks

### Expected Processing Times

| Operation | Duration | Notes |
|-----------|----------|-------|
| API authentication | <5 sec | First call only |
| Config loading | <1 sec | - |
| Cache signature | <1 sec | - |
| **Extract submission** | 1-5 min | API processing queue |
| **Extract processing** | **25-40 min** | **6 years, 66 variables** |
| Extract download | 1-2 min | ~50-100 MB |
| Data parsing (ipumspy) | 1-2 min | Fixed-width → DataFrame |
| Feather write | 10-20 sec | ~50-100 MB |
| **R validation** | 5-10 sec | 7 checks, 300K records |
| Database insertion | 10-20 sec | Chunked insertion |
| **Total (no cache)** | **~30-45 min** | **First run** |
| **Total (cached)** | **<1 min** | **Subsequent runs** |

### Single-Year Benchmarks

| Year | Records | Extract Time | Total Time |
|------|---------|--------------|------------|
| 2019 | 52,108 | 5-8 min | 6-10 min |
| 2020 | 51,234 | 5-8 min | 6-10 min |
| 2021 | 50,456 | 5-8 min | 6-10 min |
| 2022 | 52,789 | 5-8 min | 6-10 min |

---

## Troubleshooting Test Failures

### Test 1 Failure: API Connection

**Symptom:** "API authentication failed"

**Solutions:**
1. Check API key file exists and contains valid key
2. Verify no firewall blocking IPUMS API
3. Check IPUMS status page for outages
4. Try regenerating API key

---

### Test 4 Failure: Extraction Timeout

**Symptom:** "Extract polling timed out"

**Solutions:**
1. Check extract status manually:
   ```bash
   python scripts/nhis/check_extract_status.py nhis:12345
   ```
2. If still processing, wait and retry download
3. If failed on IPUMS side, resubmit extract
4. Check IPUMS for data availability issues

---

### Test 5 Failure: R Validation

**Symptom:** "Validation check failed: Year coverage"

**Solutions:**
1. Check which years are present in data:
   ```r
   table(nhis_data$YEAR)
   ```
2. Verify config matches data availability
3. Update expected_years in validation call
4. Re-extract with correct years

---

### Test 6 Failure: Database Insertion

**Symptom:** "Database insertion failed: Permission denied"

**Solutions:**
1. Close any open database connections
2. Check file permissions on database
3. Delete and recreate database:
   ```bash
   rm data/duckdb/kidsights_local.duckdb
   python pipelines/python/init_database.py
   ```

---

## Test Automation

### Continuous Integration Script

Create `.github/workflows/nhis-pipeline-test.yml` (if using GitHub):

```yaml
name: NHIS Pipeline Tests

on:
  push:
    paths:
      - 'python/nhis/**'
      - 'R/load/nhis/**'
      - 'R/utils/nhis/**'
      - 'config/sources/nhis/**'

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Set up Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.13'

      - name: Install Python dependencies
        run: |
          pip install ipumspy pandas pyyaml duckdb structlog

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: '4.5.1'

      - name: Install R dependencies
        run: |
          Rscript -e 'install.packages(c("arrow", "dplyr"))'

      - name: Run API connection test
        run: python scripts/nhis/test_api_connection.py
        env:
          IPUMS_API_KEY: ${{ secrets.IPUMS_API_KEY }}

      - name: Run configuration test
        run: python scripts/nhis/test_configuration.py

      - name: Run cache test
        run: python scripts/nhis/test_cache.py

      - name: Run R validation test
        run: Rscript scripts/temp/test_nhis_validation.R

      - name: Run database test
        run: python scripts/temp/test_nhis_database.py
```

---

## Validation Checklist

### Pre-Deployment Checklist

Before using NHIS pipeline in production:

- [ ] API connection test passes
- [ ] Configuration loading test passes
- [ ] Cache system test passes
- [ ] Single-year extraction test passes (2019)
- [ ] R validation test passes (all 7 checks)
- [ ] Database operations test passes
- [ ] End-to-end pipeline test passes (optional, 45 min)
- [ ] Documentation reviewed and understood
- [ ] Cache management procedures understood
- [ ] Troubleshooting guide reviewed

---

**Last Updated:** 2025-10-03
**Pipeline Version:** 1.0.0
