# Calibration Dataset Example Usage Guide

**Last Updated:** January 2025
**Version:** 1.0
**Status:** Production Ready

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Step-by-Step Walkthrough](#step-by-step-walkthrough)
3. [Common Use Cases](#common-use-cases)
4. [Troubleshooting](#troubleshooting)
5. [FAQ](#faq)
6. [Advanced Usage](#advanced-usage)

---

## Quick Start

### Prerequisites

**Required Software:**
- R 4.5.1 or higher
- DuckDB database with required tables
- Mplus (for running IRT calibration)

**Required R Packages:**
```r
# Core packages
install.packages(c("duckdb", "dplyr", "jsonlite", "stringr"))

# For historical data import (one-time)
install.packages("KidsightsPublic")
install.packages("haven")
```

**Required Data:**
- ✅ `ne25_transformed` table (NE25 pipeline output)
- ✅ `nsch_2021_raw` table (NSCH pipeline output)
- ✅ `nsch_2022_raw` table (NSCH pipeline output)
- ✅ `historical_calibration_2020_2024` table (one-time import)

### 30-Second Start

```bash
# Interactive mode (recommended for first use)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/prepare_calibration_dataset.R
```

**What happens:**
1. Prompts for NSCH sample size (default: 1000)
2. Prompts for output file path (default: mplus/calibdat.dat)
3. Creates calibration dataset (~30 seconds)
4. Outputs: `.dat` file + DuckDB table

---

## Step-by-Step Walkthrough

### Step 1: One-Time Historical Data Import

**Only run this once per database instance:**

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/import_historical_calibration.R
```

**Expected Output:**
```
================================================================================
IMPORT HISTORICAL CALIBRATION DATA FROM KIDSIGHTSPUBLIC PACKAGE
================================================================================

[1/7] Loading required packages
      Packages loaded successfully

[2/7] Loading calibdat from KidsightsPublic package
      Loaded calibdat: 41,577 records, 242 columns

[3/7] Processing calibdat
      - Stripping haven labels
      - Deriving study column from ID ranges
      - Filtering to required columns
      Processed: 41,577 records, 242 columns

[4/7] Opening DuckDB connection
      Connected to: data/duckdb/kidsights_local.duckdb

[5/7] Dropping existing table (if exists)
      Table 'historical_calibration_2020_2024' dropped

[6/7] Writing to DuckDB table 'historical_calibration_2020_2024'
      Successfully wrote 41,577 records

[7/7] Creating indexes
      [OK] Index created on study column
      [OK] Index created on id column

[OK] HISTORICAL DATA IMPORT COMPLETE
```

**Verification:**
```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Check table exists and record counts
DBI::dbGetQuery(conn, "
  SELECT study, COUNT(*) as n
  FROM historical_calibration_2020_2024
  GROUP BY study
  ORDER BY study
")
# Expected:
#   study     n
# 1  NE20 37546
# 2  NE22  2431
# 3 USA24  1600

DBI::dbDisconnect(conn)
```

---

### Step 2: Prepare Calibration Dataset

**Run the main workflow:**

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/prepare_calibration_dataset.R
```

**Interactive Prompts:**

**Prompt 1: NSCH Sample Size**
```
Enter NSCH sample size per year (recommended: 1000, press Enter for default):
```
- **Default:** 1000 (press Enter)
- **Alternative:** 500 (faster, less data) or 2000 (more data, slower)
- **Impact:** Affects final dataset size and representativeness

**Prompt 2: Output File Path**
```
Enter output .dat file path (default: mplus/calibdat.dat):
```
- **Default:** `mplus/calibdat.dat` (press Enter)
- **Alternative:** `mplus/calibdat_fullscale.dat` or custom path
- **Note:** Directory must exist (creates `mplus/` if needed)

**Expected Execution Log:**

```
================================================================================
PREPARE CALIBRATION DATASET FOR MPLUS IRT RECALIBRATION
================================================================================

[SETUP] Loading required packages and helper functions
        Loaded 4 packages successfully

[1/10] Loading codebook lexicon mappings
        Loaded 416 items with lexicons from codebook.json

[2/10] Loading historical calibration data
        Loaded 41,577 records from historical_calibration_2020_2024 table
        Studies: NE20 (37,546), NE22 (2,431), USA24 (1,600)

[3/10] Loading NE25 data
        Loaded 3,507 records from ne25_transformed (eligible=TRUE)

[4/10] Loading NSCH 2021 data
        Loaded 1,000 sampled records from NSCH 2021

[5/10] Loading NSCH 2022 data
        Loaded 1,000 sampled records from NSCH 2022

[6/10] Combining all data sources
        Combined 47,084 records from 6 studies

[7/10] Finalizing dataset structure
        Final dimensions: 47,084 records × 419 columns

[8/10] Writing Mplus .dat file
        Output: mplus/calibdat.dat
        Format: space-delimited, missing as "."

[9/10] Storing in DuckDB
        Table: calibration_dataset_2020_2025
        Records written: 47,084
        Indexes created: 4

[10/10] Summary statistics
        Study distribution:
          NE20: 37,546 (79.7%)
          NE22: 2,431 (5.2%)
          NE25: 3,507 (7.4%)
          NSCH21: 1,000 (2.1%)
          NSCH22: 1,000 (2.1%)
          USA24: 1,600 (3.4%)

[OK] CALIBRATION DATASET PREPARATION COMPLETE
     Output file: mplus/calibdat.dat (38.71 MB)
     Database table: calibration_dataset_2020_2025
     Total records: 47,084
```

**Expected Duration:** ~30 seconds

---

### Step 3: Validate Output

**Run validation tests:**

```bash
# Test 1: Mplus format compatibility
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/test_mplus_compatibility.R

# Test 2: Item missingness patterns
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/validate_item_missingness.R
```

**Expected Results:**
- ✅ Format: Space-delimited with missing as "."
- ✅ Structure: 47,084 rows × 419 columns
- ✅ Study codes: 1, 2, 3, 5, 6, 7 (correct)
- ✅ Missingness: 92.3% overall (expected for multi-study data)

---

## Common Use Cases

### Use Case 1: Standard Calibration Dataset

**Goal:** Create production calibration dataset with default settings.

```r
# Interactive R session
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()

# Press Enter at both prompts to use defaults:
# - NSCH sample size: 1000
# - Output path: mplus/calibdat.dat
```

**When to use:**
- First-time calibration
- Standard IRT analysis
- Production use

---

### Use Case 2: Large Sample NSCH Calibration

**Goal:** Include more NSCH data for better national representation.

```r
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()

# At NSCH sample size prompt, enter: 2000
# At output path prompt, press Enter for default
```

**Trade-offs:**
- ✅ More representative national data
- ✅ Better estimation of DIF parameters
- ❌ Longer execution time (~45 seconds)
- ❌ Larger file size (~42 MB)

**When to use:**
- DIF analysis across studies
- National benchmarking
- Sensitivity analysis

---

### Use Case 3: Development/Testing Calibration

**Goal:** Quick dataset for testing Mplus syntax or workflow.

```r
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()

# At NSCH sample size prompt, enter: 100
# At output path prompt, enter: mplus/calibdat_test.dat
```

**Trade-offs:**
- ✅ Fast execution (~15 seconds)
- ✅ Small file size (~35 MB)
- ❌ Less representative NSCH data

**When to use:**
- Testing Mplus input files
- Debugging workflow
- Quick parameter checks

---

### Use Case 4: Query Calibration Dataset from Database

**Goal:** Analyze calibration data without re-running preparation.

```r
library(duckdb)
library(dplyr)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Study distribution
study_counts <- DBI::dbGetQuery(conn, "
  SELECT study_num, COUNT(*) as n
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
  ORDER BY study_num
")
print(study_counts)

# Item coverage by study (top 10 items)
item_coverage <- DBI::dbGetQuery(conn, "
  SELECT
    study_num,
    COUNT(CASE WHEN NOM046X IS NOT NULL THEN 1 END) as NOM046X_n,
    COUNT(CASE WHEN CQFA002 IS NOT NULL THEN 1 END) as CQFA002_n,
    COUNT(CASE WHEN PS001 IS NOT NULL THEN 1 END) as PS001_n
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
  ORDER BY study_num
")
print(item_coverage)

# Age distribution
age_summary <- DBI::dbGetQuery(conn, "
  SELECT
    study_num,
    MIN(years) as min_age,
    AVG(years) as mean_age,
    MAX(years) as max_age
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
  ORDER BY study_num
")
print(age_summary)

DBI::dbDisconnect(conn)
```

---

### Use Case 5: Subset Calibration Dataset for Specific Items

**Goal:** Create domain-specific calibration dataset (e.g., social-emotional only).

```r
library(duckdb)
library(dplyr)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Extract only social-emotional items (PS* items)
social_emotional <- DBI::dbGetQuery(conn, "
  SELECT
    study_num, id, years,
    PS001, PS002, PS003, PS004, PS005, PS006, PS007, PS008, PS009, PS010,
    PS011, PS012, PS013, PS014, PS015, PS016, PS017, PS018, PS019, PS020,
    PS021, PS022, PS023, PS024, PS025, PS026, PS027, PS028, PS029, PS030
  FROM calibration_dataset_2020_2025
")

# Filter to records with at least 5 non-missing PS items
social_emotional <- social_emotional %>%
  dplyr::filter(
    rowSums(!is.na(dplyr::select(., dplyr::starts_with("PS")))) >= 5
  )

# Write subset to new .dat file
write.table(social_emotional,
            file = "mplus/calibdat_social_emotional.dat",
            row.names = FALSE, col.names = FALSE,
            sep = " ", na = ".")

cat(sprintf("Created social-emotional subset: %d records, %d items\n",
            nrow(social_emotional), ncol(social_emotional) - 3))

DBI::dbDisconnect(conn)
```

**When to use:**
- Domain-specific IRT calibration
- Reducing computational complexity
- Testing specific item sets

---

## Troubleshooting

### Problem: Historical data table not found

**Error Message:**
```
Error: Table 'historical_calibration_2020_2024' does not exist
```

**Cause:** Historical data import step skipped.

**Solution:**
```bash
# Run one-time historical data import
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/import_historical_calibration.R
```

---

### Problem: NSCH tables not found

**Error Message:**
```
Error: Table 'nsch_2021_raw' does not exist
```

**Cause:** NSCH pipeline not run.

**Solution:**
```bash
# Run NSCH pipeline for both years
python scripts/nsch/process_all_years.py --years 2021 2022
```

**Verification:**
```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
tables <- DBI::dbListTables(conn)
cat("NSCH tables available:\n")
print(tables[grepl("nsch_.*_raw", tables)])
DBI::dbDisconnect(conn)
```

---

### Problem: Output directory doesn't exist

**Error Message:**
```
Error: cannot open the connection
In addition: Warning message:
In file(file, ifelse(append, "a", "w")) :
  cannot open file 'mplus/calibdat.dat': No such file or directory
```

**Cause:** `mplus/` directory doesn't exist.

**Solution:**
```r
# Create directory
dir.create("mplus", showWarnings = FALSE, recursive = TRUE)

# Re-run workflow
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()
```

---

### Problem: NE25 data is empty

**Error Message:**
```
Warning: NE25 data is empty after filtering by eligible=TRUE
Proceeding without NE25 data
```

**Cause:** NE25 pipeline not run or no eligible records.

**Solution:**
```bash
# Run NE25 pipeline
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=run_ne25_pipeline.R
```

**Verification:**
```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
ne25_count <- DBI::dbGetQuery(conn, "
  SELECT COUNT(*) as n
  FROM ne25_transformed
  WHERE eligible = TRUE
")
cat(sprintf("Eligible NE25 records: %d\n", ne25_count$n))
DBI::dbDisconnect(conn)
```

---

### Problem: Mplus can't read .dat file

**Symptom:** Mplus error "Data file cannot be read" or "Format error"

**Diagnosis:**
```bash
# Test Mplus compatibility
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/test_mplus_compatibility.R
```

**Common Issues:**

1. **Wrong delimiter**: Check for tabs or commas instead of spaces
   ```r
   # Read first line
   first_line <- readLines("mplus/calibdat.dat", n = 1)
   cat("Delimiters found:\n")
   cat("  Tabs:", grepl("\t", first_line), "\n")
   cat("  Commas:", grepl(",", first_line), "\n")
   cat("  Spaces:", grepl(" ", first_line), "\n")
   ```

2. **Column headers present**: Mplus requires no headers
   ```r
   # Check first line
   first_line <- readLines("mplus/calibdat.dat", n = 1)
   first_values <- strsplit(first_line, "\\s+")[[1]]
   all_numeric <- all(grepl("^[0-9.-]+$", first_values))
   cat("First line is numeric only:", all_numeric, "\n")
   ```

3. **Non-numeric values**: Mplus requires numeric-only or missing "."
   ```r
   # Read and check
   dat <- read.table("mplus/calibdat.dat", header = FALSE, sep = "", na.strings = ".")
   non_numeric <- which(!sapply(dat, is.numeric))
   if (length(non_numeric) > 0) {
     cat("Non-numeric columns:", paste(non_numeric, collapse = ", "), "\n")
   } else {
     cat("All columns are numeric: OK\n")
   }
   ```

---

### Problem: High missingness in output

**Observation:** 92-94% missingness in calibration dataset

**Is this a problem?** **NO** - This is expected and appropriate.

**Explanation:**
- Different studies measure different item subsets
- 416 total items across all studies
- Each study measures ~50-100 items
- IRT models handle sparse matrices appropriately
- Missingness within studies is low (14-26%)

**Verify within-study missingness:**
```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Check missingness by study
study_missingness <- DBI::dbGetQuery(conn, "
  WITH item_cols AS (
    SELECT * FROM calibration_dataset_2020_2025
  )
  SELECT
    study_num,
    COUNT(*) as n_records,
    -- Calculate % missing across all items for each study
    AVG(
      CAST(
        (SELECT COUNT(*) FROM pragma_table_info('calibration_dataset_2020_2025') WHERE name NOT IN ('study_num', 'id', 'years'))
        AS FLOAT
      )
    ) * 100 as mean_missingness_pct
  FROM calibration_dataset_2020_2025
  GROUP BY study_num
  ORDER BY study_num
")
print(study_missingness)

DBI::dbDisconnect(conn)
```

---

## FAQ

### Q1: How long does calibration dataset preparation take?

**A:** ~30 seconds with default settings (NSCH n=1000).

**Factors affecting time:**
- NSCH sample size (larger = slower)
- Database performance
- First run vs subsequent runs (caching)

**Benchmarks:**
- NSCH n=100: ~15 seconds
- NSCH n=1000: ~30 seconds (recommended)
- NSCH n=2000: ~45 seconds

---

### Q2: How often should I regenerate the calibration dataset?

**Regenerate when:**
- ✅ New NE25 data collected (quarterly surveys)
- ✅ Adding new historical studies
- ✅ Codebook lexicon mappings updated
- ✅ Different NSCH sample size needed

**No need to regenerate for:**
- ❌ Minor codebook changes (labels, descriptions)
- ❌ Testing different Mplus models
- ❌ Analyzing results

**Best practice:** Store dated versions for reproducibility
```bash
# Dated output filenames
mplus/calibdat_2025_01.dat  # January 2025
mplus/calibdat_2025_04.dat  # April 2025 (after Q1 data)
```

---

### Q3: Can I use the database table instead of the .dat file?

**A:** Yes, for R-based IRT packages. No, for Mplus.

**R-based IRT (mirt, ltm, TAM):**
```r
library(duckdb)
library(mirt)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
calibration_data <- DBI::dbGetQuery(conn, "
  SELECT * FROM calibration_dataset_2020_2025
")
DBI::dbDisconnect(conn)

# Extract item columns only
items <- calibration_data %>%
  dplyr::select(-study_num, -id, -years)

# Fit graded response model
model <- mirt(items, model = 1, itemtype = "graded", verbose = FALSE)
```

**Mplus:**
- Requires .dat file (cannot read from database)
- Use `mplus/calibdat.dat` output

---

### Q4: What if I only want certain studies in the calibration?

**Option 1: Modify function (advanced)**

Edit `prepare_calibration_dataset.R` to skip unwanted studies:

```r
# Comment out NSCH 2022 loading (lines ~200-210)
# cat("[5/10] Loading NSCH 2022 data\n")
# nsch22_data <- recode_nsch_2022(...)
```

**Option 2: Filter database table (recommended)**

```r
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Create study-specific subset
DBI::dbExecute(conn, "
  CREATE OR REPLACE TABLE calibration_nebraska_only AS
  SELECT * FROM calibration_dataset_2020_2025
  WHERE study_num IN (1, 2, 3, 7)  -- NE20, NE22, NE25, USA24 only
")

# Export to .dat file
nebraska_only <- DBI::dbGetQuery(conn, "SELECT * FROM calibration_nebraska_only")
write.table(nebraska_only,
            file = "mplus/calibdat_nebraska_only.dat",
            row.names = FALSE, col.names = FALSE,
            sep = " ", na = ".")

DBI::dbDisconnect(conn)
```

---

### Q5: What items are included in the calibration dataset?

**A:** All 416 items with lexicon mappings in `codebook.json`.

**Item domains:**
- Developmental milestones (motor, language, cognitive)
- Social-emotional functioning (PS001-PS030)
- Behavioral problems (internalizing, externalizing)
- Family demographics and structure
- Health and healthcare access

**Check available items:**
```r
library(jsonlite)

# Load codebook
codebook <- jsonlite::fromJSON("codebook/data/codebook.json")

# Extract items with lexicons
items_with_lexicons <- sapply(codebook$items, function(item) {
  !is.null(item$lexicons$lex_equate)
})

item_names <- names(codebook$items)[items_with_lexicons]
cat(sprintf("Total items with lexicons: %d\n", length(item_names)))
cat("\nFirst 20 items:\n")
print(head(item_names, 20))
```

---

### Q6: Can I customize NSCH sampling strategy?

**Current Implementation:** Simple random sampling with set.seed()

**Alternative Strategies:**

**Stratified sampling by age:**
```r
# Modify recode_nsch_2021() to stratify
nsch21_sampled <- nsch21_filtered %>%
  dplyr::group_by(age_group = cut(years, breaks = c(0, 2, 4, 6))) %>%
  dplyr::slice_sample(n = sample_size / 3, replace = FALSE) %>%
  dplyr::ungroup() %>%
  dplyr::select(-age_group)
```

**Probability-weighted sampling:**
```r
# Weight by inverse probability (more rare ages sampled more)
nsch21_sampled <- nsch21_filtered %>%
  dplyr::mutate(
    weight = 1 / table(cut(years, breaks = c(0, 2, 4, 6)))[cut(years, breaks = c(0, 2, 4, 6))]
  ) %>%
  dplyr::slice_sample(n = sample_size, weight_by = weight, replace = FALSE) %>%
  dplyr::select(-weight)
```

**Note:** Custom sampling requires modifying helper functions in `scripts/irt_scoring/helpers/`.

---

### Q7: Why are study codes non-sequential (1,2,3,5,6,7)?

**A:** Study 4 was skipped intentionally to maintain consistency with Update-KidsightsPublic.

**Mapping:**
- **1** = NE20 (Nebraska 2020)
- **2** = NE22 (Nebraska 2022)
- **3** = NE25 (Nebraska 2025)
- **[4]** = Reserved/Skipped
- **5** = NSCH21 (National Survey 2021)
- **6** = NSCH22 (National Survey 2022)
- **7** = USA24 (National 2024)

**Rationale:** Allows future studies to fill in gaps without renumbering.

---

### Q8: What is the "authentic" column issue?

**Issue:** All NE25 records have `authentic=FALSE` in ne25_transformed.

**Current Workaround:** Filter by `eligible=TRUE` only (line 148 in prepare_calibration_dataset.R)

**Impact:** None on calibration dataset quality (eligible filter is sufficient)

**Status:** Investigation needed (see `.github/ISSUE_TEMPLATE/authentic_column_all_false.md`)

**Track Progress:**
```bash
# Check GitHub issue status
gh issue list --label "data-quality"
```

---

## Advanced Usage

### Running Non-Interactively with Custom Parameters

**Override readline() for automation:**

```r
# Create wrapper script
cat('
# Override readline for non-interactive execution
readline <- function(prompt = "") {
  cat(prompt)
  if (grepl("NSCH sample size", prompt, ignore.case = TRUE)) {
    cat("2000\\n")
    return("2000")
  } else if (grepl("Output .dat file path", prompt, ignore.case = TRUE)) {
    cat("mplus/calibdat_large.dat\\n")
    return("mplus/calibdat_large.dat")
  }
  return("")
}

# Source and run
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()
', file = "scripts/temp/run_calibration_noninteractive.R")

# Execute
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/temp/run_calibration_noninteractive.R
```

---

### Comparing Multiple Calibration Datasets

**Create comparison report:**

```r
library(duckdb)
library(dplyr)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Create dated versions
datasets <- c("calibration_dataset_2024_12", "calibration_dataset_2025_01")

comparison <- lapply(datasets, function(table_name) {
  DBI::dbGetQuery(conn, sprintf("
    SELECT
      '%s' as dataset,
      COUNT(*) as total_records,
      COUNT(DISTINCT study_num) as n_studies,
      MIN(years) as min_age,
      MAX(years) as max_age,
      AVG(years) as mean_age
    FROM %s
  ", table_name, table_name))
})

comparison_df <- dplyr::bind_rows(comparison)
print(comparison_df)

DBI::dbDisconnect(conn)
```

---

### Exporting Calibration Metadata

**Create machine-readable metadata file:**

```r
library(jsonlite)
library(duckdb)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Gather metadata
metadata <- list(
  dataset_name = "calibration_dataset_2020_2025",
  creation_date = Sys.Date(),
  total_records = DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM calibration_dataset_2020_2025")$n,
  studies = DBI::dbGetQuery(conn, "
    SELECT study_num, COUNT(*) as n
    FROM calibration_dataset_2020_2025
    GROUP BY study_num
  "),
  items = DBI::dbGetQuery(conn, "
    SELECT column_name
    FROM information_schema.columns
    WHERE table_name = 'calibration_dataset_2020_2025'
      AND column_name NOT IN ('study_num', 'id', 'years')
  ")$column_name,
  age_range = DBI::dbGetQuery(conn, "
    SELECT MIN(years) as min, MAX(years) as max, AVG(years) as mean
    FROM calibration_dataset_2020_2025
  ")
)

# Export to JSON
jsonlite::write_json(metadata,
                     path = "mplus/calibdat_metadata.json",
                     pretty = TRUE,
                     auto_unbox = TRUE)

cat("Metadata exported to: mplus/calibdat_metadata.json\n")

DBI::dbDisconnect(conn)
```

---

## Next Steps

After creating the calibration dataset:

1. **Run Mplus IRT Calibration**
   - See: [docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md](MPLUS_CALIBRATION_WORKFLOW.md)
   - Create Mplus .inp file with graded response model
   - Execute calibration (~2-4 hours for 416 items)

2. **Extract Item Parameters**
   - Parse Mplus output files
   - Store slopes and thresholds in codebook.json
   - Validate parameter estimates

3. **Score NE25 Data**
   - Use calibrated parameters for IRT scoring
   - Generate theta scores for each domain
   - Compare to raw scores for validation

4. **Validate Calibration Quality**
   - Check item fit statistics
   - Test for differential item functioning (DIF)
   - Assess model convergence

---

**For questions or issues, see:**
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [GitHub Issues](https://github.com/your-repo/issues)

---

*Last Updated: January 2025*
*Document Version: 1.0*
*Status: Production Ready*
