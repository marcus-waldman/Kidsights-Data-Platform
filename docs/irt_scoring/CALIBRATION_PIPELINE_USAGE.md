# IRT Calibration Pipeline - Usage Guide

**Last Updated:** November 2025

This guide explains how to generate and export IRT calibration datasets for Mplus analysis.

---

## Quick Start

### First-Time Setup (Full Pipeline)

```bash
# Run complete pipeline: create tables + validate + export
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R
```

**What this does:**
1. Imports historical data (NE20, NE22, USA24) if not already present
2. Creates current study tables (NE25, NSCH21, NSCH22)
3. Validates all 6 calibration tables
4. Exports combined dataset to `mplus/calibdat.dat`

**Execution time:** ~3-5 minutes (depends on NE25 pipeline if tables don't exist)

**Output:**
- Database tables: `ne20_calibration`, `ne22_calibration`, `ne25_calibration`, `nsch21_calibration`, `nsch22_calibration`, `usa24_calibration`
- Mplus file: `mplus/calibdat.dat` (space-delimited, ready for IRT modeling)

---

## Usage Scenarios

### Scenario 1: Update NE25 Data Only

If you've run the NE25 pipeline and need to refresh just the NE25 calibration table:

```bash
# Re-create NE25 table + export (skips historical data)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R
```

**Why this works:** The pipeline checks if historical tables exist and skips import if present.

### Scenario 2: Change NSCH Sample Size

The default NSCH sample is **n=1,000 per year**. To change:

```bash
# Export with larger NSCH sample (n=5,000 per year)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --nsch-sample 5000
```

**Technical note:** NSCH tables store ALL data (~50K records per year). Sampling occurs at export time, so you can change the sample size without re-running table creation.

### Scenario 3: Re-Export Only (Fast)

If tables already exist and you just need to regenerate the .dat file:

```bash
# Skip table creation, only export (30 seconds)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --export-only
```

**Use case:** Testing different NSCH sample sizes or regenerating after Mplus errors.

### Scenario 4: Create Tables Without Export

If you want to create/update tables but skip the export step:

```bash
# Create tables only (useful for validation)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --tables-only
```

**Use case:** Database maintenance, testing table creation without generating Mplus file.

---

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| *(no args)* | Full pipeline: create tables + validate + quality check + export | - |
| `--export-only` | Skip table creation and quality check, only export to .dat file | Off |
| `--tables-only` | Create/update tables, skip quality check and export | Off |
| `--skip-quality-check` | Skip data quality assessment (faster execution) | Off |
| `--nsch-sample N` | Set NSCH sample size (per year) | 1000 |

**Notes:**
- `--export-only` and `--tables-only` are mutually exclusive
- `--nsch-sample` is ignored if `--tables-only` is used
- Quality check runs automatically unless `--skip-quality-check`, `--export-only`, or `--tables-only` is specified

---

## Pipeline Steps

### Step 1: Create/Update Calibration Tables

**What happens:**

1. **Check for historical tables** (`ne20_calibration`, `ne22_calibration`, `usa24_calibration`)
   - If missing: Run `import_historical_calibration.R` to import from `data/calibration_2020_2024.feather`
   - If present: Skip import

2. **Create current study tables** (`ne25_calibration`, `nsch21_calibration`, `nsch22_calibration`)
   - Runs `create_calibration_tables.R`
   - Uses codebook for item harmonization (lex_equate mappings)
   - Applies reverse coding to items marked in codebook
   - Stores ALL NSCH data (no sampling)

**Table structure:**
```
id              INTEGER    -- Unique ID (format: YYFFFSNNNNNN)
years           INTEGER    -- Child age in years
item_ACE01      DOUBLE     -- ACE item 1 (0-2 scale)
item_ACE02      DOUBLE     -- ACE item 2 (0-2 scale)
...
item_cahmi16    DOUBLE     -- CAHMI item 16 (0-4 scale)
```

**Expected record counts:**
- NE20: 37,546 records (Nebraska 2020)
- NE22: 2,431 records (Nebraska 2022)
- NE25: ~3,507 records (Nebraska 2025, depends on latest data)
- NSCH21: 20,719 records (National 2021, ALL data)
- NSCH22: 19,741 records (National 2022, ALL data)
- USA24: 1,600 records (National 2024)

### Step 2: Validate Calibration Tables

**What happens:**

Runs 6 validation tests via `validate_calibration_tables.R`:

1. **Table existence:** All 6 tables present in database
2. **Record counts:** Within expected ranges (allows ±10% variance)
3. **Age ranges:** All ages between 0-18 years
4. **Item coverage:** Each study has >10 harmonized items
5. **ID uniqueness:** No duplicate IDs within studies
6. **Export test:** Small sample export (n=10) succeeds

**If validation fails:**
- Pipeline continues but prints warnings
- Check `data/duckdb/kidsights_local.duckdb` for table issues

### Step 2.5: Data Quality Assessment (Optional)

**What happens:**

Runs automated quality checks on the combined calibration dataset to detect data quality issues.

**Three types of flags detected:**

1. **Category Mismatch**
   - **Invalid values:** Response values not defined in codebook (e.g., value=9 when only {0,1,2} expected)
   - **Fewer categories:** Missing response categories suggesting ceiling/floor effects

2. **Negative Age-Response Correlation**
   - Items where older children score lower than younger children
   - Developmentally unexpected pattern

3. **Non-Sequential Response Values**
   - Response values with gaps (e.g., {0,1,9} instead of {0,1,2})
   - Suggests undocumented missing codes

**Outputs:**

- `docs/irt_scoring/quality_flags.csv` - Machine-readable flag details (605 flags detected in current data)
- `docs/irt_scoring/calibration_quality_report.html` - Interactive HTML report with:
  - Executive summary (flag counts, affected studies)
  - Detailed flag table (filterable, exportable)
  - Item explorer (age-response plots for top 10 flagged items)

**To skip quality check:**
```bash
# Faster execution, skip quality assessment
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --skip-quality-check
```

**To regenerate HTML report:**
```bash
cd docs/irt_scoring
quarto render calibration_quality_report.qmd
```

**Execution time:** +2-3 minutes for quality check

**Recent Bug Fixes (November 2025 - Issue #6):**

Three critical data quality issues were identified and fixed in the calibration pipeline:

1. **NSCH Missing Code Contamination**
   - **Problem:** NSCH 2021/2022 variables had values >= 90 (e.g., 90="Not applicable", 95="Refused", 97="Don't know", 98="Missing", 99="Missing") being treated as valid response categories
   - **Impact:** Created invalid IRT threshold counts - dichotomous items like DD201 showed 5 thresholds instead of 1 (values: 0, 1, 4, 97, 98 when should be 0, 1)
   - **Fix:** Modified `scripts/irt_scoring/helpers/recode_nsch_2021.R` and `recode_nsch_2022.R` to recode all values >= 90 to NA before reverse/forward coding transformations
   - **Commits:** 20e3cf5, 25d2b47

2. **Missing Study Field Assignment**
   - **Problem:** NSCH helper functions didn't create `study` column, causing `study = NA` when datasets were combined with `bind_rows()`
   - **Impact:** Couldn't trace items back to original study source in combined calibration dataset
   - **Fix:** Added explicit `study = "NSCH21"` and `study = "NSCH22"` assignments in `prepare_calibration_dataset.R` after sampling
   - **Commit:** d72afaa

3. **Syntax Generator Indexing Bug**
   - **Problem:** `write_syntax2.R` used positional indexing `Ks[jdx]` (where jdx=150 for item jid) instead of named lookup `categories[jid == jdx]`
   - **Impact:** Generated incorrect threshold counts - 26 items (EG14b, EG16c, EG17b, etc.) showed wrong threshold boundaries in Mplus syntax
   - **Fix:** Replaced positional indexing with proper category lookup: `item_max_category <- categories[jid == jdx] + 1`
   - **Commit:** 37d2034

**Impact on Quality Checks:**
- "Invalid values" flags now prevented for NSCH items (no longer detecting 90+ as valid responses)
- "Non-Sequential Response Values" flags reduced (fewer gaps in NSCH data)
- Expected flag count may differ from 605 after fixes are applied

**Development Status:** ⚠️ Pipeline under active validation - verify data quality and syntax outputs before use in production analyses

### Step 3: Export Calibration Dataset

**What happens:**

Runs `export_calibration_dat()` to create Mplus-compatible .dat file:

1. **Load study tables** from database
2. **Sample NSCH data** (n=1,000 per year by default)
3. **Combine studies** via `UNION ALL` query
4. **Export to space-delimited file** with missing coded as "."

**Output format:**
```
id years item_ACE01 item_ACE02 ... item_cahmi16
200311000001 5 0 1 ... 2
200311000002 7 . 0 ... 3
...
```

**Mplus compatibility:**
- Space-delimited (no commas)
- Missing values: "." (not NA)
- Integer IDs only (no character IDs)
- Column order: id, years, then items (alphabetical)

---

## Integration with Other Pipelines

### NE25 Pipeline → Calibration Pipeline

The NE25 transformation pipeline now includes **reverse coding** as Step 6:

```r
# In recode_it() function (R/transform/ne25_transforms.R):
message("Applying reverse coding from codebook...")
source("R/transform/reverse_code_items.R")
dat <- reverse_code_items(dat, lexicon_name = "ne25", verbose = TRUE)
```

**Workflow:**
```bash
# 1. Run NE25 pipeline (includes reverse coding)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R

# 2. Run calibration pipeline (uses ne25_transformed table)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R
```

**Dependency:** Calibration pipeline requires `ne25_transformed` table to exist in database.

### NSCH Pipeline → Calibration Pipeline

NSCH helpers (`recode_nsch_2021.R`, `recode_nsch_2022.R`) include reverse coding at transformation time.

**Workflow:**
```bash
# 1. Run NSCH pipeline (if not already loaded)
python scripts/nsch/process_all_years.py --years 2021 2022

# 2. Run calibration pipeline (reads nsch21_raw and nsch22_raw tables)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R
```

**Dependency:** Calibration pipeline requires `nsch21_raw` and `nsch22_raw` tables to exist in database.

---

## Troubleshooting

### Error: "Table ne25_transformed not found"

**Cause:** NE25 pipeline hasn't been run yet.

**Fix:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

### Error: "Table nsch21_raw not found"

**Cause:** NSCH pipeline hasn't loaded 2021 data.

**Fix:**
```bash
python scripts/nsch/process_all_years.py --years 2021 2022
```

### Error: "File data/calibration_2020_2024.feather not found"

**Cause:** Historical calibration data file is missing.

**Fix:** Contact data team for `calibration_2020_2024.feather` file (contains NE20, NE22, USA24 data).

### Warning: "Record count for ne25_calibration outside expected range"

**Cause:** NE25 data has changed significantly since last run.

**Fix:** Check if this is expected (e.g., new data collection). Update expected ranges in `validate_calibration_tables.R` if needed.

### Error: "Can't combine id columns of different types"

**Cause:** ID type mismatch between studies (should not occur with current implementation).

**Fix:** Re-run pipeline with `--tables-only` to rebuild all tables, then export:
```bash
# Rebuild tables
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --tables-only

# Then export
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/run_calibration_pipeline.R --export-only
```

### Mplus Error: "Invalid numeric ID"

**Cause:** ID format doesn't match Mplus requirements (numeric only).

**Current implementation:** Uses integer IDs (format: YYFFFSNNNNNN) which are Mplus-compatible. If error persists, check for character IDs in .dat file:
```bash
head -n 5 mplus/calibdat.dat
```

All IDs should be integers (e.g., `200311000001`, not `"NE20_001"`).

---

## Next Steps After Export

### 1. Review Output File

```bash
# Check first 10 rows
head -n 10 mplus/calibdat.dat

# Check record count
wc -l mplus/calibdat.dat
```

**Expected:** ~47,000 records (all studies combined with NSCH sampled at n=1,000 per year)

### 2. Create Mplus Input File

See **docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md** for:
- Mplus .inp syntax for IRT models
- Item parameter specification
- Model fit assessment
- Example calibration runs

### 3. Run Mplus Calibration

```bash
# From mplus/ directory
mplus calibration.inp
```

**Output:** `calibration.out` with item parameters, fit statistics, and warnings.

### 4. Import Item Parameters

Once Mplus calibration completes, import parameters back to database:

```r
# (Script to be created)
source("scripts/irt_scoring/import_mplus_parameters.R")
import_mplus_parameters(
  mplus_output = "mplus/calibration.out",
  db_path = "data/duckdb/kidsights_local.duckdb"
)
```

---

## Database Schema

### Study-Specific Tables

Each study has its own table with identical structure:

| Table Name | Study | Years | Records |
|------------|-------|-------|---------|
| `ne20_calibration` | Nebraska 2020 | 2-18 | 37,546 |
| `ne22_calibration` | Nebraska 2022 | 2-18 | 2,431 |
| `ne25_calibration` | Nebraska 2025 | 0-18 | 3,507 |
| `nsch21_calibration` | NSCH 2021 | 0-17 | 20,719 |
| `nsch22_calibration` | NSCH 2022 | 0-17 | 19,741 |
| `usa24_calibration` | USA 2024 | 0-18 | 1,600 |

### Column Schema (All Tables)

```sql
CREATE TABLE {study}_calibration (
    id INTEGER PRIMARY KEY,           -- Unique ID (YYFFFSNNNNNN format)
    years INTEGER,                    -- Child age in years
    item_ACE01 DOUBLE,                -- ACE items (0-2 scale)
    item_ACE02 DOUBLE,
    ...
    item_ACE10 DOUBLE,
    item_cahmi01 DOUBLE,              -- CAHMI items (0-4 scale)
    item_cahmi02 DOUBLE,
    ...
    item_cahmi16 DOUBLE
);
```

**Notes:**
- Item names use `lex_equate` mappings from codebook
- All items allow NULL (missing data)
- Items are reverse-coded where specified in codebook

### ID Format Convention

**Format:** `YYFFFSNNNNNN` (11 digits, integer)

| Component | Description | Example |
|-----------|-------------|---------|
| YY | Year (2-digit) | 20, 22, 25 |
| FFF | State FIPS code | 031 (Nebraska), 999 (National) |
| S | Source flag | 0 (NSCH), 1 (Other) |
| NNNNNN | Sequential number (6 digits) | 000001, 000002, ... |

**Examples:**
- `200311000001` - NE20, record 1
- `250311003507` - NE25, record 3507
- `219990000001` - NSCH21, record 1
- `249991000001` - USA24, record 1

**Why this format:**
- Mplus requires numeric IDs (no character strings)
- Encodes metadata (study, year, source) in ID
- Avoids floating-point precision loss
- Fits in R integer range (up to 2.1 billion)

---

## Performance Notes

### Execution Times

| Operation | Time | Notes |
|-----------|------|-------|
| Import historical data | 30 sec | One-time (cached in database) |
| Create NE25 table | 60 sec | Depends on NE25 pipeline state |
| Create NSCH tables | 30 sec | Reads from nsch_raw tables |
| Validate tables | 10 sec | 6 tests across all tables |
| Export to .dat | 20 sec | Sampling NSCH + writing file |
| **Full pipeline** | **3-5 min** | First run (includes all steps) |
| **Export only** | **30 sec** | If tables already exist |

### Storage Requirements

| Component | Size | Notes |
|-----------|------|-------|
| Historical feather file | 45 MB | data/calibration_2020_2024.feather |
| Database tables (all 6) | 58 MB | Study-specific tables |
| Mplus .dat file | 12 MB | Space-delimited export |
| **Total** | **115 MB** | All calibration data |

**Comparison to old architecture:**
- Old combined tables: 135 MB (with duplication)
- New study-specific: 58 MB (35% reduction)

---

## Related Documentation

- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - Architectural changes, API deprecations
- **[MPLUS_CALIBRATION_WORKFLOW.md](MPLUS_CALIBRATION_WORKFLOW.md)** - Mplus modeling workflow (to be created)
- **[CODING_STANDARDS.md](../guides/CODING_STANDARDS.md)** - R namespacing, Windows compatibility
- **[MISSING_DATA_GUIDE.md](../guides/MISSING_DATA_GUIDE.md)** - Missing data handling, composite scores

---

**Last Updated:** November 2025 | **Pipeline Version:** 2.0
