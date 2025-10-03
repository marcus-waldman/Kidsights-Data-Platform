# NSCH Pipeline Testing Guide

Comprehensive testing procedures for validating the NSCH data integration pipeline.

**Last Updated:** October 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Pre-Testing Checklist](#pre-testing-checklist)
3. [Component Testing](#component-testing)
4. [Integration Testing](#integration-testing)
5. [End-to-End Testing](#end-to-end-testing)
6. [Data Quality Validation](#data-quality-validation)
7. [Performance Testing](#performance-testing)

---

## Overview

### Testing Philosophy

The NSCH pipeline uses a layered testing approach:

1. **Component Testing**: Test each pipeline step independently
2. **Integration Testing**: Test step combinations
3. **End-to-End Testing**: Test complete pipeline for single year
4. **Batch Testing**: Test multi-year processing
5. **Data Quality**: Validate output integrity

### Test Levels

| Level | Scope | Duration | Frequency |
|-------|-------|----------|-----------|
| Unit | Single function | <1 min | Every change |
| Component | Single step | 1-5 min | Before commit |
| Integration | Multiple steps | 5-10 min | Before release |
| End-to-End | Full pipeline | 15-25 min | Weekly |
| Batch | All years | 2-5 min | Monthly |

---

## Pre-Testing Checklist

### Environment Setup

**Python Packages:**
```bash
python -c "import pandas, pyreadstat, duckdb, structlog; print('✓ All packages installed')"
```

**R Packages:**
```bash
Rscript -e "library(haven); library(arrow); library(dplyr); cat('✓ All packages loaded\n')"
```

**Test Data:**
```bash
# Verify at least one SPSS file exists
ls data/nsch/spss/ | head -1
```

**Directory Structure:**
```bash
mkdir -p data/nsch/{2016,2017,2018,2019,2020,2021,2022,2023}
mkdir -p data/duckdb
mkdir -p output
```

---

## Component Testing

### Test 1: SPSS to Feather Conversion

**Objective:** Verify SPSS files are correctly converted to Feather format

**Test Command:**
```bash
python pipelines/python/nsch/load_nsch_spss.py --year 2023
```

**Expected Output:**
```
Processing NSCH 2023 data...
SPSS file: data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav
Reading SPSS file... (55,162 records, 895 columns)
Extracting metadata...
Saving to Feather format...
Round-trip validation: PASSED
Duration: 8.2 seconds
```

**Validation Checks:**

1. **Files Created:**
```bash
ls -lh data/nsch/2023/
# Should see:
# - raw.feather (~100 MB)
# - metadata.json (~500 KB)
```

2. **Metadata Content:**
```python
import json

with open('data/nsch/2023/metadata.json', 'r') as f:
    meta = json.load(f)

print(f"Year: {meta['year']}")
print(f"Records: {meta['record_count']:,}")
print(f"Variables: {meta['variable_count']}")
print(f"Has value labels: {len([v for v in meta['variables'].values() if v['has_value_labels']])} variables")

# Expected:
# Year: 2023
# Records: 55,162
# Variables: 895
# Has value labels: ~600 variables
```

3. **Feather File Integrity:**
```python
import pandas as pd

df = pd.read_feather('data/nsch/2023/raw.feather')
print(f"Rows: {len(df):,}")
print(f"Columns: {len(df.columns)}")
print(f"Memory: {df.memory_usage(deep=True).sum() / 1024**2:.1f} MB")

# Expected:
# Rows: 55,162
# Columns: 895
# Memory: ~100 MB
```

**Pass Criteria:**
- ✅ No errors during conversion
- ✅ `raw.feather` and `metadata.json` created
- ✅ Record count matches SPSS file
- ✅ Column count matches SPSS file
- ✅ Round-trip validation passes

---

### Test 2: R Validation

**Objective:** Verify R validation script performs all 7 checks

**Test Command:**
```bash
Rscript pipelines/orchestration/run_nsch_pipeline.R --year 2023
```

**Expected Output:**
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

**Validation Checks:**

1. **Validation Report Created:**
```bash
cat data/nsch/2023/validation_report.txt
```

2. **Processed Feather Created:**
```bash
ls -lh data/nsch/2023/processed.feather
```

3. **All 7 Checks Pass:**
```r
library(arrow)

df <- read_feather('data/nsch/2023/processed.feather')

# Check 1: HHID present
stopifnot('HHID' %in% names(df))

# Check 2: Record count
stopifnot(nrow(df) == 55162)

# Check 3: Column count
stopifnot(ncol(df) == 895)

# Check 4: No empty columns
empty_cols <- sapply(df, function(x) all(is.na(x)))
stopifnot(sum(empty_cols) == 0)

# Check 5: HHID no missing
stopifnot(sum(is.na(df$HHID)) == 0)

# Check 6: YEAR present
stopifnot('YEAR' %in% names(df))

cat("✓ All validation checks passed\n")
```

**Pass Criteria:**
- ✅ All 7 validation checks pass
- ✅ `processed.feather` created
- ✅ `validation_report.txt` generated
- ✅ No errors or warnings

---

### Test 3: Metadata Loading

**Objective:** Verify metadata is correctly inserted into database

**Test Command:**
```bash
python pipelines/python/nsch/load_nsch_metadata.py --year 2023
```

**Expected Output:**
```
Loading NSCH 2023 metadata...
Variables loaded: 895
Value labels loaded: 4,812
Metadata insertion complete
```

**Validation Checks:**

1. **Variable Count:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

var_count = conn.execute("""
    SELECT COUNT(*) FROM nsch_variables WHERE year = 2023
""").fetchone()[0]

print(f"Variables in DB: {var_count}")
# Expected: 895

conn.close()
```

2. **Value Label Count:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

label_count = conn.execute("""
    SELECT COUNT(*) FROM nsch_value_labels WHERE year = 2023
""").fetchone()[0]

print(f"Value labels in DB: {label_count:,}")
# Expected: ~4,800

conn.close()
```

3. **Sample Variable Check:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

sample = conn.execute("""
    SELECT variable_name, variable_label
    FROM nsch_variables
    WHERE year = 2023
      AND variable_name = 'HHID'
""").fetchone()

print(f"HHID label: {sample[1]}")
# Expected: "Unique Household ID" or similar

conn.close()
```

**Pass Criteria:**
- ✅ Variables inserted (895 records)
- ✅ Value labels inserted (~4,800 records)
- ✅ Sample queries return expected data
- ✅ No duplicate records

---

### Test 4: Raw Data Insertion

**Objective:** Verify survey data is correctly inserted into database

**Test Command:**
```bash
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

**Expected Output:**
```
Inserting NSCH 2023 data...
Table: nsch_2023_raw
Records: 55,162
Columns: 895
Chunk size: 10,000
Progress: [====] 100% (6/6 chunks)
Insertion complete: 55,162 rows in 9.5 seconds
```

**Validation Checks:**

1. **Table Created:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

tables = conn.execute("SHOW TABLES").fetchall()
table_names = [t[0] for t in tables]

assert 'nsch_2023_raw' in table_names
print("✓ Table exists")

conn.close()
```

2. **Record Count:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

count = conn.execute("SELECT COUNT(*) FROM nsch_2023_raw").fetchone()[0]
print(f"Records in DB: {count:,}")
# Expected: 55,162

conn.close()
```

3. **Column Count:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

col_count = conn.execute("""
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_name = 'nsch_2023_raw'
""").fetchone()[0]

print(f"Columns in DB: {col_count}")
# Expected: 895

conn.close()
```

4. **Data Integrity:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Check HHID uniqueness
unique_hhids = conn.execute("""
    SELECT COUNT(DISTINCT HHID) FROM nsch_2023_raw
""").fetchone()[0]

total_records = conn.execute("""
    SELECT COUNT(*) FROM nsch_2023_raw
""").fetchone()[0]

assert unique_hhids == total_records, "HHID not unique!"
print("✓ HHID is unique")

conn.close()
```

**Pass Criteria:**
- ✅ Table `nsch_2023_raw` created
- ✅ 55,162 records inserted
- ✅ 895 columns present
- ✅ HHID is unique
- ✅ No NULL HHIDs

---

## Integration Testing

### Test 5: SPSS → Feather → Database

**Objective:** Test SPSS conversion through database insertion (skip R validation)

**Test Commands:**
```bash
# Step 1: Convert SPSS to Feather
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite

# Step 2: Copy raw.feather to processed.feather (simulate R validation)
cp data/nsch/2023/raw.feather data/nsch/2023/processed.feather

# Step 3: Load metadata
python pipelines/python/nsch/load_nsch_metadata.py --year 2023

# Step 4: Insert data
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

**Validation:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Check data and metadata match
result = conn.execute("""
    SELECT
        (SELECT COUNT(*) FROM nsch_2023_raw) AS data_count,
        (SELECT COUNT(DISTINCT variable_name) FROM nsch_variables WHERE year = 2023) AS var_count,
        (SELECT COUNT(*) FROM nsch_value_labels WHERE year = 2023) AS label_count
""").fetchone()

print(f"Data records: {result[0]:,}")
print(f"Variables: {result[1]}")
print(f"Value labels: {result[2]:,}")

conn.close()
```

**Pass Criteria:**
- ✅ All steps complete without errors
- ✅ Data and metadata counts match expectations

---

### Test 6: Full Pipeline with R Validation

**Objective:** Test complete pipeline including R validation

**Test Commands:**
```bash
# Run all 4 steps
python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite
Rscript pipelines/orchestration/run_nsch_pipeline.R --year 2023
python pipelines/python/nsch/load_nsch_metadata.py --year 2023
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

**Validation:**
Use Test 4 validation checks

**Pass Criteria:**
- ✅ All 4 steps complete
- ✅ R validation passes (7/7 checks)
- ✅ Data in database matches Feather file

---

## End-to-End Testing

### Test 7: Single Year Full Pipeline

**Objective:** Test complete automated pipeline for one year

**Test Command:**
```bash
python scripts/nsch/process_all_years.py --years 2023
```

**Expected Output:**
```
======================================================================
PROCESSING YEAR: 2023
======================================================================
  [STEP 1/4] SPSS to Feather conversion... [OK]
  [STEP 2/4] R validation... [OK]
  [STEP 3/4] Metadata loading... [OK]
  [STEP 4/4] Raw data insertion... [OK]

[SUCCESS] Year 2023 processed in 18.4 seconds
```

**Validation:**
Run all component tests (1-4) to verify each output

**Pass Criteria:**
- ✅ All 4 steps marked [OK]
- ✅ Processing completes in <30 seconds
- ✅ All component tests pass

---

### Test 8: Round-Trip Data Integrity

**Objective:** Verify no data loss or corruption

**Test Command:**
```bash
python scripts/nsch/test_db_roundtrip.py --year 2023
```

**Expected Output:**
```
======================================================================
NSCH DATABASE ROUND-TRIP TEST
======================================================================

[CHECK 1/6] Row count... [PASS]
[CHECK 2/6] Column count... [PASS]
[CHECK 3/6] Column names... [PASS]
[CHECK 4/6] Sample values (10 random rows)... [PASS]
[CHECK 5/6] Null counts (first 10 columns)... [PASS]
[CHECK 6/6] Summary statistics (first 5 numeric columns)... [PASS]

======================================================================
TEST SUMMARY
======================================================================
Checks passed: 6/6

[SUCCESS] All round-trip checks passed!
Data integrity verified - no data loss or corruption detected.
```

**Pass Criteria:**
- ✅ All 6 checks pass
- ✅ Row counts match
- ✅ No data corruption detected

---

## Batch Testing

### Test 9: Multi-Year Processing

**Objective:** Test batch processing for multiple years

**Test Command:**
```bash
python scripts/nsch/process_all_years.py --years 2022,2023
```

**Expected Output:**
```
======================================================================
BATCH PROCESSING SUMMARY
======================================================================
Total Years Processed: 2
Successful: 2
Failed: 0
Total Time: 36.8 seconds

PER-YEAR RESULTS:
  [PASS] 2022: 18.4s
  [PASS] 2023: 18.4s
======================================================================
```

**Validation:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Check both years loaded
result = conn.execute("""
    SELECT
        (SELECT COUNT(*) FROM nsch_2022_raw) AS count_2022,
        (SELECT COUNT(*) FROM nsch_2023_raw) AS count_2023
""").fetchone()

print(f"2022 records: {result[0]:,}")
print(f"2023 records: {result[1]:,}")

conn.close()
```

**Pass Criteria:**
- ✅ Both years process successfully
- ✅ Each year completes in <30 seconds
- ✅ Total time <1 minute for 2 years

---

### Test 10: Full Batch (All Years)

**Objective:** Test processing all 8 years

**Test Command:**
```bash
python scripts/nsch/process_all_years.py --years all
```

**Expected Outcome:**
```
Total Years Processed: 8
Successful: 7 (2017-2023)
Failed: 1 (2016 - known limitation)
Total Time: ~2 minutes
```

**Validation:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Check all years
for year in range(2017, 2024):
    count = conn.execute(f"SELECT COUNT(*) FROM nsch_{year}_raw").fetchone()[0]
    print(f"{year}: {count:,} records")

conn.close()
```

**Pass Criteria:**
- ✅ 7/8 years successful (2016 expected to fail)
- ✅ Total processing time <5 minutes
- ✅ 284,496 total records (2017-2023)

---

## Data Quality Validation

### Test 11: Cross-Year Consistency

**Objective:** Verify common variables exist across years

**Test Script:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Find variables in all 7 years
common_vars = conn.execute("""
    SELECT variable_name, COUNT(DISTINCT year) AS year_count
    FROM nsch_variables
    WHERE year BETWEEN 2017 AND 2023
    GROUP BY variable_name
    HAVING COUNT(DISTINCT year) = 7
""").fetchdf()

print(f"Common variables across all years: {len(common_vars)}")
# Expected: ~350

# Check key identifiers present
key_vars = ['HHID', 'YEAR', 'FIPSST', 'SC_AGE_YEARS', 'SC_SEX']
for var in key_vars:
    present = var in common_vars['variable_name'].values
    status = "✓" if present else "✗"
    print(f"{status} {var}")

conn.close()
```

**Pass Criteria:**
- ✅ ~350 common variables found
- ✅ All key identifiers present across years

---

### Test 12: Value Label Integrity

**Objective:** Verify value labels are correctly linked

**Test Script:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Test decoding SC_SEX for 2023
result = conn.execute("""
    SELECT
        d.SC_SEX AS code,
        vl.label,
        COUNT(*) AS count
    FROM nsch_2023_raw d
    LEFT JOIN nsch_value_labels vl
        ON vl.variable_name = 'SC_SEX'
       AND vl.year = 2023
       AND CAST(vl.value AS DOUBLE) = d.SC_SEX
    WHERE d.SC_SEX NOT IN (90, 95, 96, 99)
    GROUP BY d.SC_SEX, vl.label
    ORDER BY d.SC_SEX
""").fetchdf()

print(result)
# Expected:
# code  label    count
# 1.0   Male     ~27,000
# 2.0   Female   ~27,000

conn.close()
```

**Pass Criteria:**
- ✅ All codes have corresponding labels
- ✅ Labels are meaningful (not NULL)
- ✅ Approximately equal sex distribution

---

## Performance Testing

### Test 13: Query Performance

**Objective:** Verify queries complete in reasonable time

**Test Queries:**
```python
import duckdb
import time

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Test 1: Simple SELECT
start = time.time()
result = conn.execute("SELECT * FROM nsch_2023_raw LIMIT 1000").fetchdf()
elapsed = time.time() - start
print(f"Simple SELECT: {elapsed:.3f}s")
# Expected: <0.1s

# Test 2: Aggregation
start = time.time()
result = conn.execute("""
    SELECT FIPSST, COUNT(*), AVG(SC_AGE_YEARS)
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    GROUP BY FIPSST
""").fetchdf()
elapsed = time.time() - start
print(f"Aggregation: {elapsed:.3f}s")
# Expected: <1s

# Test 3: Join with metadata
start = time.time()
result = conn.execute("""
    SELECT d.HHID, d.SC_SEX, vl.label
    FROM nsch_2023_raw d
    LEFT JOIN nsch_value_labels vl
        ON vl.variable_name = 'SC_SEX'
       AND vl.year = 2023
       AND CAST(vl.value AS DOUBLE) = d.SC_SEX
    LIMIT 1000
""").fetchdf()
elapsed = time.time() - start
print(f"Join: {elapsed:.3f}s")
# Expected: <0.5s

conn.close()
```

**Pass Criteria:**
- ✅ Simple SELECT: <0.1 seconds
- ✅ Aggregation: <1 second
- ✅ Join: <0.5 seconds

---

## Test Automation Script

Create a master test runner:

```python
"""
NSCH Pipeline Test Suite

Runs all component, integration, and end-to-end tests.

Usage:
    python scripts/nsch/run_tests.py
"""

import sys
import duckdb
import pandas as pd
from pathlib import Path

def test_environment():
    """Test 0: Verify environment setup"""
    print("\n[TEST 0] Environment Setup")
    try:
        import pandas, pyreadstat, duckdb, structlog
        print("  ✓ Python packages installed")
        return True
    except ImportError as e:
        print(f"  ✗ Missing package: {e}")
        return False

def test_spss_conversion():
    """Test 1: SPSS to Feather conversion"""
    print("\n[TEST 1] SPSS to Feather Conversion")
    # Add test implementation
    return True

# Add more test functions...

def run_all_tests():
    """Run complete test suite"""
    print("=" * 70)
    print("NSCH PIPELINE TEST SUITE")
    print("=" * 70)

    tests = [
        test_environment,
        test_spss_conversion,
        # Add more tests...
    ]

    results = []
    for test in tests:
        try:
            result = test()
            results.append(result)
        except Exception as e:
            print(f"  ✗ Exception: {e}")
            results.append(False)

    # Summary
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)
    passed = sum(results)
    total = len(results)
    print(f"Tests passed: {passed}/{total}")

    if all(results):
        print("\n✓ ALL TESTS PASSED")
        return 0
    else:
        print("\n✗ SOME TESTS FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(run_all_tests())
```

---

## Continuous Testing

### Daily Checks

```bash
# Quick smoke test (single year)
python scripts/nsch/process_all_years.py --years 2023

# Round-trip validation
python scripts/nsch/test_db_roundtrip.py --year 2023
```

### Weekly Checks

```bash
# Full batch processing
python scripts/nsch/process_all_years.py --years all

# Database summary
python scripts/nsch/generate_db_summary.py
```

### Release Checks

- Run all component tests (1-4)
- Run all integration tests (5-6)
- Run all end-to-end tests (7-8)
- Run all batch tests (9-10)
- Run all data quality tests (11-12)
- Run performance tests (13)

---

## Additional Resources

- **Troubleshooting:** [troubleshooting.md](troubleshooting.md)
- **Pipeline Usage:** [pipeline_usage.md](pipeline_usage.md)
- **Database Schema:** [database_schema.md](database_schema.md)

---

**Last Updated:** October 3, 2025
