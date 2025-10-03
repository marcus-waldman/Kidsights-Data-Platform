# NHIS Pipeline Usage Guide

Complete walkthrough for using the NHIS data extraction pipeline with examples, troubleshooting, and best practices.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Complete Pipeline Walkthrough](#complete-pipeline-walkthrough)
3. [Python Extraction Examples](#python-extraction-examples)
4. [R Validation Examples](#r-validation-examples)
5. [Database Querying Examples](#database-querying-examples)
6. [Cache Management](#cache-management)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Prerequisites

### Required Software

**Python 3.13+**
```bash
pip install ipumspy pandas pyyaml duckdb structlog requests
```

**R 4.5.1+**
```r
install.packages(c("arrow", "dplyr"))
```

### IPUMS API Key Setup

1. **Register at IPUMS:**
   - Visit [IPUMS Health Surveys](https://healthsurveys.ipums.org/)
   - Create account (free for academic/research use)

2. **Generate API Key:**
   - Navigate to: Account → API Keys
   - Click "Create New API Key"
   - Copy the generated key

3. **Store API Key:**
   ```bash
   # Create directory
   mkdir -p "C:/Users/waldmanm/my-APIs"

   # Save API key (Windows)
   echo YOUR_API_KEY_HERE > "C:/Users/waldmanm/my-APIs/IPUMS.txt"
   ```

4. **Verify Setup:**
   ```python
   from python.nhis.auth import get_ipums_client
   client = get_ipums_client()
   print("API client initialized successfully!")
   ```

---

## Complete Pipeline Walkthrough

### Step 1: Extract Data from IPUMS API

**Command:**
```bash
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --verbose
```

**What Happens:**
1. Loads configuration from `config/sources/nhis/nhis-2019-2024.yaml`
2. Generates SHA256 cache signature from years + samples + variables
3. Checks cache for existing extract
4. If not cached:
   - Submits extract to IPUMS NHIS API
   - Polls every 30 seconds for completion
   - Downloads .dat file + DDI codebook when ready (~30-45 min)
5. Parses fixed-width data using ipumspy
6. Saves to Feather: `data/nhis/2019-2024/raw.feather`

**Expected Output:**
```
==========================================================
NHIS DATA EXTRACTION PIPELINE
==========================================================
Configuration: config/sources/nhis/nhis-2019-2024.yaml
Year Range: 2019-2024
Years: [2019, 2020, 2021, 2022, 2023, 2024]
Samples: [ih2019, ih2020, ih2021, ih2022, ih2023, ih2024]
Variables: 66

Checking cache...
Cache signature: a7f3d9e2b8c4f1a6...
Cache miss - submitting new extract

Submitting extract to IPUMS API...
Extract submitted successfully!
Extract Number: 12345
Status: queued

Polling for completion (checks every 30 seconds)...
[00:30] Status: started (0% complete)
[01:00] Status: started (25% complete)
...
[28:30] Status: completed

Downloading extract...
Downloaded: 45.2 MB

Loading NHIS data...
Loaded: 312,456 records, 66 variables

Saving to Feather...
Saved: data/nhis/2019-2024/raw.feather (52.3 MB)

EXTRACTION COMPLETE
Elapsed Time: 29 minutes 15 seconds
```

**Processing Time:**
- Single year (2019): ~5-10 minutes
- 6 years (2019-2024): ~30-45 minutes
- Cache hit: <1 minute (instant)

### Step 2: Validate Data in R

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
```

**What Happens:**
1. Loads raw.feather using arrow::read_feather()
2. Runs 7 validation checks:
   - Variable presence (66 expected)
   - Year coverage (2019-2024)
   - Survey design (STRATA, PSU)
   - Sampling weights (SAMPWEIGHT)
   - Critical IDs (SERIAL+PERNUM)
   - ACE variables (8 vars, range 0-9)
   - Mental health (GAD-7, PHQ-8)
3. Generates validation report
4. Saves processed.feather

**Expected Output:**
```
======================================================================
NHIS DATA PIPELINE - R ORCHESTRATION
======================================================================
Started: 2025-10-03 14:32:15

Year Range: 2019-2024
Verbose: TRUE

[Step 1/6] Source R Modules
----------------------------------------------------------------------
  ✓ Sourced: R/load/nhis/load_nhis_data.R
  ✓ Sourced: R/utils/nhis/validate_nhis_raw.R
✓ R modules loaded

[Step 2/6] Load Raw Feather Data
----------------------------------------------------------------------
Loading NHIS data: 2019-2024
  File: data/nhis/2019-2024/raw.feather
  Loaded: 312,456 records, 66 variables
  Added metadata columns: year_range, loaded_at
✓ NHIS data loaded successfully: 2019-2024
  Records: 312,456
  Variables: 68
✓ Raw data loaded successfully

[Step 3/6] Validate Data Quality
----------------------------------------------------------------------
Running NHIS validation: 2019-2024

CHECK 1: Variable Presence
  Expected: 66 variables
  Found: 66 variables
  Status: PASS

CHECK 2: Year Coverage
  Expected years: 2019-2024
  Found years: 2019-2024
  Status: PASS

CHECK 3: Survey Design Variables
  STRATA: 312,456 records (0 missing)
  PSU: 312,456 records (0 missing)
  Status: PASS

CHECK 4: Sampling Weights
  SAMPWEIGHT range: 142.3 - 8,234.7
  Missing/zero weights: 0 records
  Status: PASS

CHECK 5: Critical ID Variables
  SERIAL+PERNUM unique combinations: 312,456
  Duplicates: 0
  Status: PASS

CHECK 6: ACE Variables
  8 ACE variables present
  Value range: 0-9 (valid)
  Status: PASS

CHECK 7: Mental Health Variables
  GAD-7 variables: 8 present
  PHQ-8 variables: 9 present
  Status: PASS

✓ All validation checks passed

[Step 4/6] Write Validation Report
----------------------------------------------------------------------
  Report written to: data/nhis/2019-2024/validation_report.txt
✓ Validation report saved

[Step 5/6] Write Processed Data
----------------------------------------------------------------------
  Removed metadata columns: year_range, loaded_at
  File: data/nhis/2019-2024/processed.feather
  Size: 51.20 MB
  Records: 312,456
  Variables: 66
✓ Processed data written

[Step 6/6] Pipeline Summary
----------------------------------------------------------------------
Year Range: 2019-2024
Expected Years: 2019-2024
Records Processed: 312,456
Variables: 66
Validation Status: PASS
Output File: data/nhis/2019-2024/processed.feather
Validation Report: data/nhis/2019-2024/validation_report.txt
Elapsed Time: 8.42 seconds

======================================================================
PIPELINE COMPLETE
======================================================================
✓ All checks passed - data ready for database insertion
```

### Step 3: Insert into Database

**Command:**
```bash
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024 --mode replace
```

**What Happens:**
1. Loads processed.feather
2. Connects to DuckDB: `data/duckdb/kidsights_local.duckdb`
3. Creates nhis_raw table (if not exists)
4. Deletes existing years (if mode=replace)
5. Inserts data in chunks (10,000 records per chunk)
6. Validates row counts

**Expected Output:**
```
==========================================================
NHIS DATABASE INSERTION
==========================================================
Configuration:
  Year Range: 2019-2024
  Mode: replace
  Source: processed

Loading processed data...
Loaded: 312,456 records, 66 variables

Connecting to database...
Database: data/duckdb/kidsights_local.duckdb
Connected successfully

Creating/updating nhis_raw table...
Mode: replace
Deleting existing records for years: 2019-2024
Deleted: 0 records (table was empty)

Inserting data in chunks (10,000 records per chunk)...
[Chunk 1/32] Inserted 10,000 records
[Chunk 2/32] Inserted 10,000 records
...
[Chunk 32/32] Inserted 2,456 records

Validating insertion...
Expected: 312,456 records
Inserted: 312,456 records
Validation: PASS

INSERTION COMPLETE
Elapsed Time: 12.3 seconds
```

---

## Python Extraction Examples

### Example 1: Extract Single Year (Fast Test)

```bash
# Create test config
cat > config/sources/nhis/nhis-2019.yaml << EOF
years: [2019]
samples: [ih2019]
year_range: "2019"
output_directory: "data/nhis/2019"
template: "nhis-template.yaml"
EOF

# Extract
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019 --verbose

# Expected: ~5-10 min processing, ~50,000 records
```

### Example 2: Force Re-extraction (Ignore Cache)

```bash
python pipelines/python/nhis/extract_nhis_data.py \
    --year-range 2019-2024 \
    --force-refresh \
    --verbose
```

### Example 3: Extract Without Cache

```bash
python pipelines/python/nhis/extract_nhis_data.py \
    --year-range 2019-2024 \
    --no-cache \
    --verbose
```

### Example 4: Custom Configuration

```bash
# Create custom config with fewer variables
cat > config/sources/nhis/nhis-custom.yaml << EOF
years: [2022, 2023]
samples: [ih2022, ih2023]
year_range: "2022-2023"
output_directory: "data/nhis/2022-2023"
collection: nhis
data_format: fixed_width

variables:
  identifiers: [YEAR, SERIAL, PERNUM, SAMPWEIGHT]
  demographics: [AGE, SEX]
  mental_health_gad7: [GADANX, GADWORCTRL, GADWORMUCH, GADRELAX, GADRSTLS, GADANNOY, GADFEAR, GADCAT]
  mental_health_phq8: [PHQINTR, PHQDEP, PHQSLEEP, PHQENGY, PHQEAT, PHQBAD, PHQCONC, PHQMOVE, PHQCAT]

cache:
  enabled: true
  directory: "cache/ipums"
  max_age_days: 90
EOF

# Extract with custom config
python pipelines/python/nhis/extract_nhis_data.py \
    --config config/sources/nhis/nhis-custom.yaml \
    --verbose
```

### Example 5: Programmatic Extraction (Python Script)

```python
#!/usr/bin/env python3
"""Custom NHIS extraction script"""

from python.nhis import ConfigManager, ExtractBuilder, ExtractManager, DataLoader
from pathlib import Path

# Load configuration
config_mgr = ConfigManager()
config = config_mgr.load_config("config/sources/nhis/nhis-2019-2024.yaml")

# Build extract
extract_builder = ExtractBuilder()
extract = extract_builder.build_extract(config)

# Submit and download
extract_mgr = ExtractManager()
extract_number, data_path, ddi_path = extract_mgr.submit_and_download(
    extract,
    cache_enabled=True,
    verbose=True
)

# Load data
loader = DataLoader()
df = loader.load_nhis_data(str(data_path), str(ddi_path))

print(f"Loaded: {len(df)} records, {len(df.columns)} variables")
print(df.head())
```

---

## R Validation Examples

### Example 1: Load NHIS Data in R

```r
# Load NHIS data loading functions
source("R/load/nhis/load_nhis_data.R")

# Load data
nhis_data <- load_nhis_feather(
  year_range = "2019-2024",
  add_metadata = TRUE,
  validate = TRUE
)

# Check dimensions
dim(nhis_data)
# [1] 312456     68

# View first few records
head(nhis_data)

# Check variable names
names(nhis_data)
```

### Example 2: Run Validation Checks

```r
# Load validation functions
source("R/utils/nhis/validate_nhis_raw.R")

# Run full validation
validation <- validate_nhis_raw_data(
  data = nhis_data,
  year_range = "2019-2024",
  expected_years = 2019:2024,
  verbose = TRUE
)

# Check results
validation$overall_passed  # TRUE/FALSE
validation$n_passed       # Number of checks passed
validation$n_failed       # Number of checks failed

# View detailed results
print_validation_report(validation)
```

### Example 3: Check Specific Variables

```r
# Get parent variables
parent_vars <- get_nhis_variable_names(nhis_data, pattern = "^PAR")
print(parent_vars)
# [1] "PAR1REL" "PAR2REL" "PAR1AGE" "PAR2AGE" ...

# Get ACE variables
ace_vars <- get_nhis_variable_names(nhis_data, pattern = "(VIOLEN|JAIL|MENTDEP|ALCDRUGEV)")
print(ace_vars)
# [1] "VIOLENEV" "JAILEV" "MENTDEPEV" "ALCDRUGEV" ...

# Get mental health variables
mh_vars <- get_nhis_variable_names(nhis_data, pattern = "^(GAD|PHQ)")
print(mh_vars)
# [1] "GADANX" "GADWORCTRL" ... "PHQINTR" "PHQDEP" ...
```

### Example 4: Analyze by Year

```r
library(dplyr)

# Record counts by year
nhis_data %>%
  dplyr::group_by(YEAR) %>%
  dplyr::summarise(
    n_records = dplyr::n(),
    mean_age = mean(AGE, na.rm = TRUE),
    mean_weight = mean(SAMPWEIGHT, na.rm = TRUE)
  )

# Output:
#   YEAR n_records mean_age mean_weight
# 1 2019    52108     44.2       1234.5
# 2 2020    51234     44.8       1256.3
# ...
```

### Example 5: Survey Design Analysis

```r
library(survey)
library(srvyr)

# Create survey design object
nhis_design <- nhis_data %>%
  srvyr::as_survey_design(
    ids = PSU,
    strata = STRATA,
    weights = SAMPWEIGHT,
    nest = TRUE
  )

# Weighted means
nhis_design %>%
  srvyr::group_by(YEAR) %>%
  srvyr::summarise(
    mean_age = survey_mean(AGE, na.rm = TRUE),
    mean_poverty = survey_mean(POVERTY, na.rm = TRUE)
  )
```

---

## Database Querying Examples

### Example 1: Connect to Database (Python)

```python
import duckdb

# Connect to database
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Check if nhis_raw table exists
tables = conn.execute("SHOW TABLES").fetchall()
print(tables)
# [('nhis_raw',), ...]

# Get record count
count = conn.execute("SELECT COUNT(*) FROM nhis_raw").fetchone()[0]
print(f"Total records: {count:,}")
```

### Example 2: Query by Year

```python
# Record count by year
year_counts = conn.execute("""
    SELECT YEAR, COUNT(*) as count
    FROM nhis_raw
    GROUP BY YEAR
    ORDER BY YEAR
""").fetchall()

for year, count in year_counts:
    print(f"{year}: {count:,} records")

# Output:
# 2019: 52,108 records
# 2020: 51,234 records
# ...
```

### Example 3: Filter by Demographics

```python
# Children under 5
children = conn.execute("""
    SELECT *
    FROM nhis_raw
    WHERE AGE < 5
""").fetch_df()

print(f"Children under 5: {len(children):,} records")

# Adults 18-64
adults = conn.execute("""
    SELECT *
    FROM nhis_raw
    WHERE AGE BETWEEN 18 AND 64
""").fetch_df()
```

### Example 4: ACE Analysis

```python
# Count ACE endorsements
ace_summary = conn.execute("""
    SELECT
        SUM(CASE WHEN VIOLENEV IN (1, 2) THEN 1 ELSE 0 END) as violence,
        SUM(CASE WHEN JAILEV IN (1, 2) THEN 1 ELSE 0 END) as incarceration,
        SUM(CASE WHEN MENTDEPEV IN (1, 2) THEN 1 ELSE 0 END) as mental_illness,
        SUM(CASE WHEN ALCDRUGEV IN (1, 2) THEN 1 ELSE 0 END) as substance_use
    FROM nhis_raw
    WHERE AGE >= 18
""").fetchone()

print(f"ACE Endorsements (Adults 18+):")
print(f"  Violence: {ace_summary[0]:,}")
print(f"  Incarceration: {ace_summary[1]:,}")
print(f"  Mental Illness: {ace_summary[2]:,}")
print(f"  Substance Use: {ace_summary[3]:,}")
```

### Example 5: Mental Health Screening

```python
# PHQ-8 positive screens (score >= 10)
# Note: PHQ items scored 0-3, PHQCAT has categorical classification
phq_positive = conn.execute("""
    SELECT COUNT(*) as count
    FROM nhis_raw
    WHERE PHQCAT >= 3  -- Moderate or severe depression
    AND YEAR IN (2019, 2022)  -- PHQ-8 only in 2019, 2022
""").fetchone()[0]

print(f"PHQ-8 positive screens: {phq_positive:,}")

# GAD-7 positive screens (score >= 10)
gad_positive = conn.execute("""
    SELECT COUNT(*) as count
    FROM nhis_raw
    WHERE GADCAT >= 3  -- Moderate or severe anxiety
    AND YEAR IN (2019, 2022)  -- GAD-7 only in 2019, 2022
""").fetchone()[0]

print(f"GAD-7 positive screens: {gad_positive:,}")
```

---

## Cache Management

### Check Cache Status

```bash
python scripts/nhis/manage_cache.py --list
```

**Output:**
```
IPUMS NHIS Cache Status
========================================
Cache Directory: cache/ipums
Total Cached Extracts: 3

Extract 1:
  ID: nhis:12345
  Signature: a7f3d9e2b8c4f1a6...
  Age: 5 days
  Size: 45.2 MB
  Files: data.dat, codebook.xml

Extract 2:
  ID: nhis:12346
  Signature: b8e4c1f2a7d9e3f6...
  Age: 62 days
  Size: 8.3 MB
  Files: data.dat, codebook.xml

Extract 3:
  ID: nhis:12347
  Signature: c9f5d2e3b8f4a1e7...
  Age: 125 days (EXPIRED - will be cleaned)
  Size: 52.1 MB
  Files: data.dat, codebook.xml
```

### Validate Cache Integrity

```bash
python scripts/nhis/manage_cache.py --validate
```

### Clean Old Cache

```bash
# Remove extracts older than 90 days
python scripts/nhis/manage_cache.py --clean --max-age 90
```

### Clear All Cache

```bash
python scripts/nhis/manage_cache.py --clear-all
```

---

## Troubleshooting

### Issue 1: API Authentication Failed

**Error:**
```
ERROR: IPUMS API authentication failed
FileNotFoundError: [Errno 2] No such file or directory: 'C:/Users/waldmanm/my-APIs/IPUMS.txt'
```

**Solution:**
1. Verify API key file exists: `C:/Users/waldmanm/my-APIs/IPUMS.txt`
2. Check file contains only API key (no extra whitespace)
3. Test authentication:
   ```python
   from python.nhis.auth import get_ipums_client
   client = get_ipums_client()
   ```

### Issue 2: Extract Submission Failed

**Error:**
```
ERROR: Extract submission failed
ipumspy.exceptions.IpumsApiException: Invalid sample code 'ih2025'
```

**Solution:**
- Check sample codes in config match IPUMS naming (ih2019, ih2020, etc.)
- Verify years match samples (2019 → ih2019)
- Consult `config/sources/nhis/samples.yaml` for valid codes

### Issue 3: Extract Polling Timeout

**Error:**
```
ERROR: Extract polling timed out after 60 minutes
```

**Solution:**
- Large extracts (6 years) can take 30-45 minutes
- Check extract status manually:
  ```bash
  python scripts/nhis/check_extract_status.py nhis:12345
  ```
- If still processing, wait and retry download:
  ```python
  from python.nhis import ExtractManager
  mgr = ExtractManager()
  mgr.download_extract("nhis:12345", output_dir="data/nhis/2019-2024")
  ```

### Issue 4: DDI Parsing Failed

**Error:**
```
ERROR: Failed to parse DDI codebook
ipumspy.exceptions.IpumsParsingException: Invalid DDI format
```

**Solution:**
- Re-download extract (may be corrupted):
  ```bash
  python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --force-refresh
  ```
- Check IPUMS status page for API issues
- Clear cache and retry:
  ```bash
  python scripts/nhis/manage_cache.py --clear-all
  ```

### Issue 5: Feather File Not Found

**Error:**
```
ERROR: NHIS Feather file not found: data/nhis/2019-2024/raw.feather
```

**Solution:**
- Run extraction first:
  ```bash
  python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
  ```
- Check output directory matches config
- Verify year_range argument matches directory name

### Issue 6: Validation Failed

**Error:**
```
WARNING: 1 of 7 validation checks failed
CHECK 2: Year Coverage - FAILED
Expected years: 2019-2024
Found years: 2019-2023
Missing years: 2024
```

**Solution:**
- Check IPUMS data availability for missing years
- Update config to only include available years
- Re-extract with correct year range

### Issue 7: Database Insertion Failed

**Error:**
```
ERROR: Database insertion failed
duckdb.IOException: Could not write to database
```

**Solution:**
- Check database file permissions
- Ensure no other processes have database locked
- Close any open DuckDB connections:
  ```python
  import duckdb
  # Close all connections
  duckdb.close()
  ```
- If corrupted, delete and recreate:
  ```bash
  rm data/duckdb/kidsights_local.duckdb
  python pipelines/python/init_database.py
  ```

### Issue 8: Memory Error (Large Datasets)

**Error:**
```
MemoryError: Unable to allocate array
```

**Solution:**
- Process years separately:
  ```bash
  for year in {2019..2024}; do
    python pipelines/python/nhis/extract_nhis_data.py --year-range $year
    python pipelines/python/nhis/insert_nhis_database.py --year-range $year --mode append
  done
  ```
- Use chunked insertion (already implemented in insert script)
- Increase available memory or use 64-bit Python

---

## Best Practices

### 1. Use Cache Effectively

**DO:**
- Keep cache enabled for repeated extracts
- Clean old cache regularly (>90 days)
- Use `--force-refresh` only when necessary

**DON'T:**
- Disable cache unless debugging
- Delete cache manually (use manage_cache.py script)

### 2. Validate Before Database Insertion

**DO:**
- Always run R validation pipeline before database insertion
- Review validation report for warnings
- Fix data quality issues before inserting

**DON'T:**
- Skip validation step
- Insert data with failed validation checks

### 3. Handle Missing Data Appropriately

**Mental Health Variables:**
- GAD-7 and PHQ-8 only available in 2019 and 2022
- Check YEAR before analyzing these variables
- Missing values coded as 0, 7, 8, 9 depending on item

**ACE Variables:**
- 0 = No, 1 = Yes, 2 = Yes (in past year), 7 = Refused, 8 = Not ascertained, 9 = Don't know
- Filter out 7/8/9 before analysis

### 4. Use Survey Weights

**DO:**
- Always use SAMPWEIGHT for population estimates
- Use survey package for variance estimation
- Account for STRATA and PSU in complex surveys

**DON'T:**
- Analyze unweighted data
- Ignore survey design variables

### 5. Document Custom Configurations

**DO:**
- Save custom configs in `config/sources/nhis/`
- Add comments explaining variable selections
- Version control configuration files

**DON'T:**
- Use inline configs without documentation
- Modify template files directly

### 6. Monitor Extract Processing

**DO:**
- Use `--verbose` flag for detailed logging
- Check extract status manually for long-running jobs
- Save extraction logs for debugging

**DON'T:**
- Run multiple extracts simultaneously (API rate limits)
- Submit duplicate extracts (check cache first)

---

## Advanced Topics

### Custom Variable Selection

Create config with only needed variables to reduce processing time:

```yaml
# config/sources/nhis/nhis-mental-health-only.yaml
years: [2019, 2022]
samples: [ih2019, ih2022]
year_range: "2019+2022"
output_directory: "data/nhis/mental-health-only"

variables:
  identifiers: [YEAR, SERIAL, PERNUM, SAMPWEIGHT, STRATA, PSU]
  demographics: [AGE, SEX]
  mental_health_gad7: [GADANX, GADWORCTRL, GADWORMUCH, GADRELAX, GADRSTLS, GADANNOY, GADFEAR, GADCAT]
  mental_health_phq8: [PHQINTR, PHQDEP, PHQSLEEP, PHQENGY, PHQEAT, PHQBAD, PHQCONC, PHQMOVE, PHQCAT]
```

### Parallel Processing Multiple Years

Process years in parallel (requires sufficient memory):

```bash
# Extract years in parallel (background jobs)
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019 &
python pipelines/python/nhis/extract_nhis_data.py --year-range 2020 &
python pipelines/python/nhis/extract_nhis_data.py --year-range 2021 &
wait

# Insert sequentially
for year in {2019..2021}; do
  python pipelines/python/nhis/insert_nhis_database.py --year-range $year --mode append
done
```

### Integration with NE25 Pipeline

NHIS data can complement NE25 survey data for population benchmarking:

```python
# Load both datasets
import duckdb
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Compare mental health prevalence
ne25_phq = conn.execute("SELECT AVG(phq2_positive) FROM ne25_transformed WHERE phq2_positive IS NOT NULL").fetchone()[0]
nhis_phq = conn.execute("SELECT AVG(CASE WHEN PHQCAT >= 3 THEN 1 ELSE 0 END) FROM nhis_raw WHERE YEAR = 2022").fetchone()[0]

print(f"NE25 PHQ-2 positive: {ne25_phq:.1%}")
print(f"NHIS PHQ-8 positive: {nhis_phq:.1%}")
```

---

**Last Updated:** 2025-10-03
**Pipeline Version:** 1.0.0
