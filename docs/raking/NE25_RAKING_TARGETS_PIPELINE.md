# NE25 Raking Targets Pipeline Documentation

**Last Updated:** October 2025
**Version:** 1.0
**Pipeline Scripts:** `scripts/raking/ne25/`

---

## Overview

The NE25 Raking Targets Pipeline generates population-representative targets for post-stratification raking of the Nebraska 2025 survey data. The pipeline integrates data from three national sources to create 30 estimands across 6 age groups (0-5 years), resulting in 180 raking targets stored in the `raking_targets_ne25` database table.

### Data Sources

1. **ACS (American Community Survey)** - 25 estimands
   - Demographics: race/ethnicity, sex
   - Socioeconomic: household income, mother's education, marital status
   - Geography: 14 PUMA regions in Nebraska

2. **NHIS (National Health Interview Survey)** - 1 estimand
   - Parent mental health: PHQ-2 positive screen for depression

3. **NSCH (National Survey of Children's Health)** - 4 estimands
   - Child ACE exposure (1+ adverse childhood experiences)
   - Emotional/behavioral problems (ages 3-5 only)
   - Excellent health rating
   - Child care 10+ hours/week (ages 0-4, from 2022 data)

---

## Quick Start

### Run Full Pipeline

```r
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

**Execution time:** ~2-3 minutes
**Output:** `raking_targets_ne25` table with 180 rows

### Run Bootstrap Replicates (ACS Estimands Only)

```r
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_bootstrap_pipeline.R
```

**Execution time:** ~15-20 minutes (4096 replicates, 16 workers)
**Output:** `raking_targets_boot_replicates` table with 614,400 rows (ACS only)
**Note:** Bootstrap currently implemented for ACS estimands only (25 of 30 estimands)

### Prerequisites

1. **ACS estimates** must exist from Phase 1:
   - File: `data/raking/ne25/acs_estimates.rds`
   - If missing, run ACS pipeline scripts 01-10 first

2. **NHIS data** must be loaded:
   - Database table: `nhis_combined_raw`
   - If missing, run NHIS pipeline

3. **NSCH data** must be loaded:
   - Database tables: `nsch_2022_raw`, `nsch_2023_raw`
   - If missing, run NSCH pipeline

---

## Pipeline Architecture

### Phase 1: ACS Estimates (25 estimands)

**Scripts:** `01_estimate_income.R` through `10_save_acs_estimates.R`

**Estimands:**
- **Income (5):** 0-99%, 100-199%, 200-299%, 300-399%, 400%+ FPL
- **Race/Ethnicity (3):** Black, Hispanic, White non-Hispanic
- **Demographics (2):** Male, Mother Bachelor's+, Mother Married
- **Geography (14):** PUMA regions 100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904

**Method:** GLM models with `glm(outcome ~ as.factor(age), family = binomial, weights = perwt)`

**Output:** `data/raking/ne25/acs_estimates.rds` (150 rows)

### Phase 2: NHIS Estimates (1 estimand)

**Scripts:**
- `12_filter_nhis_parents.R` - Filter to Nebraska parents with children 0-5
- `13_estimate_phq2.R` - Estimate PHQ-2 positive screen
- `14_validate_save_nhis.R` - Validate and save estimates

**Estimand:** PHQ-2 Positive (parent depression screen, score ≥ 3)

**Method:** GLM with `glm(phq2_positive ~ 1, family = binomial, weights = WTFA)`

**Output:** `data/raking/ne25/nhis_estimates.rds` (6 rows)

### Phase 4: NSCH Estimates (4 estimands)

**Scripts:**
- `17_filter_nsch_nebraska.R` - Filter to Nebraska children ages 0-5
- `18_estimate_nsch_outcomes.R` - Estimate 3 outcomes from NSCH 2023
- `20_estimate_childcare_2022.R` - Estimate child care from NSCH 2022
- `19_validate_save_nsch.R` - Validate and save estimates

**Estimands:**
- Child ACE Exposure (1+ ACEs) - ages 0-5
- Emotional/Behavioral Problems - ages 3-5 only (NA for 0-2)
- Excellent Health Rating - ages 0-5
- Child Care 10+ Hours/Week - ages 0-5 (from 2022 data)

**Method:** Mixed models with `glmer(outcome ~ as.factor(AGE) + (1|FIPSST), family = binomial, weights = FWC)`

**Note:** Uses state random effects (BLUPs) to extract Nebraska-specific estimates

**Output:** `data/raking/ne25/nsch_estimates.rds` (24 rows)

### Phase 5: Consolidation and Database

**Scripts:**
- `21_consolidate_estimates.R` - Combine all estimates into single data frame
- `22_add_descriptions.R` - Add standardized descriptions for all estimands
- `23_validate_targets.R` - Comprehensive validation checks
- `24_create_database_table.py` - Create table, insert data, create indexes

**Consolidation Steps:**
1. Load all estimate files (ACS, NHIS, NSCH)
2. Standardize column names (rename `age` to `age_years`)
3. Add metadata columns (target_id, survey, data_source, estimator, etc.)
4. Add estimand descriptions
5. Validate data (completeness, range, consistency, age patterns)
6. Create database table with proper schema
7. Insert 180 rows with NULL handling for missing values
8. Create 4 indexes for efficient querying

**Output:** `raking_targets_ne25` table in `data/duckdb/kidsights_local.duckdb`

---

## Database Schema

### Table: `raking_targets_ne25`

```sql
CREATE TABLE raking_targets_ne25 (
    target_id INTEGER PRIMARY KEY,
    survey VARCHAR NOT NULL,              -- Always 'ne25'
    age_years INTEGER NOT NULL,           -- 0, 1, 2, 3, 4, 5
    estimand VARCHAR NOT NULL,            -- Short name (e.g., 'PHQ-2 Positive')
    description VARCHAR NOT NULL,         -- Full description
    data_source VARCHAR NOT NULL,         -- 'ACS', 'NHIS', or 'NSCH'
    estimator VARCHAR NOT NULL,           -- 'GLM' or 'GLMM'
    estimate DOUBLE,                      -- Proportion (0-1), NULL if not applicable
    se DOUBLE,                            -- Standard error (placeholder)
    lower_ci DOUBLE,                      -- Lower 95% CI (placeholder)
    upper_ci DOUBLE,                      -- Upper 95% CI (placeholder)
    sample_size INTEGER,                  -- Sample size (placeholder)
    estimation_date DATE NOT NULL,        -- Date estimates were generated
    notes VARCHAR                         -- Additional notes (placeholder)
)
```

### Indexes

- `idx_estimand` - Index on estimand for filtering by specific target
- `idx_data_source` - Index on data_source for filtering by source
- `idx_age_years` - Index on age_years for filtering by age
- `idx_estimand_age` - Composite index on (estimand, age_years) for combined queries

### Table: `raking_targets_boot_replicates`

**Purpose:** Stores bootstrap replicate estimates for variance estimation via Rao-Wu-Yue-Beaumont method.

```sql
CREATE TABLE raking_targets_boot_replicates (
    survey VARCHAR NOT NULL,              -- Always 'ne25'
    data_source VARCHAR NOT NULL,         -- 'ACS', 'NHIS', or 'NSCH'
    age INTEGER NOT NULL,                 -- 0-5 (CHECK constraint)
    estimand VARCHAR NOT NULL,            -- Estimand name (e.g., 'sex_male')
    replicate INTEGER NOT NULL,           -- Bootstrap replicate number (1-4096)
    estimate DOUBLE,                      -- Replicate estimate (NULL for emot_behav ages 0-2)
    bootstrap_method VARCHAR NOT NULL,    -- Always 'Rao-Wu-Yue-Beaumont'
    n_boot INTEGER NOT NULL,              -- Total number of replicates (4 or 4096)
    estimation_date DATE NOT NULL,        -- Date estimates were generated
    created_at TIMESTAMP DEFAULT NOW(),   -- Database insertion timestamp
    PRIMARY KEY (survey, data_source, estimand, age, replicate)
)
```

### Bootstrap Indexes

- `idx_boot_estimand_age` - Composite (estimand, age) for fast replicate retrieval
- `idx_boot_estimand_age_rep` - Composite (estimand, age, replicate) for point lookups
- `idx_boot_data_source` - Single column (data_source) for source filtering

### Bootstrap Table Counts

**IMPLEMENTATION NOTE:** Bootstrap currently implemented for ACS estimands only (25 of 30 total).

**Test Mode (n_boot = 96):**

| Data Source | Estimands | Rows | Ages | Replicates | Status |
|------------|-----------|------|------|------------|--------|
| ACS | 25 | 14,400 | 0-5 | 96 | ✅ Implemented |
| NHIS | 1 | - | - | - | Not Implemented |
| NSCH | 4 | - | - | - | Not Implemented |
| **Total** | **25** | **14,400** | **0-5** | **96** | **Test Complete** |

**Production Mode (n_boot = 4096):**

| Data Source | Estimands | Rows | Ages | Replicates | Status |
|------------|-----------|------|------|------------|--------|
| ACS | 25 | 614,400 | 0-5 | 4096 | ✅ Implemented |
| NHIS | 1 | - | - | - | Not Implemented |
| NSCH | 4 | - | - | - | Not Implemented |
| **Total** | **25** | **614,400** | **0-5** | **4096** | **Production** |

### Shared Bootstrap Design

**Implementation:** All 25 ACS estimands share the same 4096 bootstrap replicate weights from a single survey design object created by `01a_create_acs_bootstrap_design.R`.

**Method:** Rao-Wu-Yue-Beaumont bootstrap via `svrep::as_bootstrap_design()`

**Key Features:**
- **Shared Weights:** All estimands use identical replicate weights from base ACS design
- **Correct Correlation:** Preserves covariance structure across estimands
- **Computational Efficiency:** Create once, use for all 25 estimands
- **Statistical Validity:** Enables joint inference across multiple targets

**Separate Binary Models:** FPL (5 categories) and PUMA (14 categories) use separate binary logistic regressions + post-hoc normalization rather than multinomial models. See `docs/raking/ne25/MULTINOMIAL_APPROACH_DECISION.md` for rationale.

### Bootstrap Validation

```python
# Example: Compute bootstrap standard error
from python.db.connection import DatabaseManager
import numpy as np

db = DatabaseManager()
with db.get_connection() as conn:
    # Get replicates for one estimand-age combination
    result = conn.execute("""
        SELECT estimate
        FROM raking_targets_boot_replicates
        WHERE estimand = 'sex_male' AND age = 0
    """).fetchall()

    replicates = [row[0] for row in result]
    boot_se = np.std(replicates, ddof=1)
    boot_ci = np.percentile(replicates, [2.5, 97.5])

    print(f"Bootstrap SE: {boot_se:.6f}")
    print(f"Bootstrap 95% CI: [{boot_ci[0]:.6f}, {boot_ci[1]:.6f}]")
```

---

## Expected Outputs

### Row Counts by Data Source

| Data Source | Estimands | Rows | Ages |
|------------|-----------|------|------|
| ACS | 25 | 150 | 0-5 |
| NHIS | 1 | 6 | 0-5 |
| NSCH | 4 | 24 | 0-5 |
| **Total** | **30** | **180** | **0-5** |

### Missing Values

- **Expected:** 3 missing values for "Emotional/Behavioral Problems" at ages 0-2
- **Reason:** NSCH variable only applicable to ages 3-5
- **All other estimates:** Should have valid values (no NULLs)

### Estimate Ranges

- **All estimates:** Proportions between 0 and 1
- **Typical ranges:**
  - Demographics (race/ethnicity): 0.06 - 0.63 (constant across ages)
  - Income: 0.11 - 0.29 (varies by age)
  - Geography (PUMA): 0.05 - 0.12 (varies slightly by age)
  - PHQ-2 Positive: 0.058 (constant across ages)
  - Child outcomes: 0.09 - 0.81 (varies by age)

---

## Pipeline Validation

### Completeness Checks

```r
# All key columns should have no missing values except 'estimate'
all_estimates <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")

# Check for unexpected missing values
library(dplyr)
all_estimates %>%
  dplyr::filter(is.na(estimate)) %>%
  dplyr::filter(!(estimand == "Emotional/Behavioral Problems" & age_years %in% 0:2))
# Should return 0 rows
```

### Range Checks

```r
# All estimates should be proportions (0-1)
all_estimates %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::filter(estimate < 0 | estimate > 1)
# Should return 0 rows
```

### Consistency Checks

```r
# Each estimand should appear exactly 6 times (once per age)
all_estimates %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n = dplyr::n()) %>%
  dplyr::filter(n != 6)
# Should return 0 rows (all estimands have 6 ages)
```

### Database Validation

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection(read_only=True) as conn:
    # Test 1: Total row count
    result = conn.execute("SELECT COUNT(*) FROM raking_targets_ne25").fetchone()
    assert result[0] == 180, f"Expected 180 rows, got {result[0]}"

    # Test 2: Data source counts
    result = conn.execute("""
        SELECT data_source, COUNT(*)
        FROM raking_targets_ne25
        GROUP BY data_source
    """).fetchall()
    assert dict(result) == {'ACS': 150, 'NHIS': 6, 'NSCH': 24}

    # Test 3: No unexpected NULLs
    result = conn.execute("""
        SELECT COUNT(*) FROM raking_targets_ne25
        WHERE estimate IS NULL
        AND NOT (estimand = 'Emotional/Behavioral Problems' AND age_years IN (0,1,2))
    """).fetchone()
    assert result[0] == 0, f"Unexpected NULL values: {result[0]}"

    print("✓ All database validation checks passed")
```

---

## Querying Raking Targets

### Python Examples

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Get all targets for age 3
with db.get_connection(read_only=True) as conn:
    results = conn.execute("""
        SELECT estimand, estimate, data_source
        FROM raking_targets_ne25
        WHERE age_years = 3
        ORDER BY data_source, estimand
    """).fetchall()

# Get income distribution across all ages
with db.get_connection(read_only=True) as conn:
    results = conn.execute("""
        SELECT age_years, estimand, estimate
        FROM raking_targets_ne25
        WHERE estimand LIKE '%-%' OR estimand LIKE '%FPL%'
        ORDER BY age_years, target_id
    """).fetchall()

# Get all NSCH estimands
with db.get_connection(read_only=True) as conn:
    results = conn.execute("""
        SELECT age_years, estimand, estimate
        FROM raking_targets_ne25
        WHERE data_source = 'NSCH'
        ORDER BY estimand, age_years
    """).fetchall()
```

### R Examples

```r
library(DBI)
library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

# Get all targets for specific estimand
phq2_targets <- DBI::dbGetQuery(con, "
  SELECT age_years, estimate
  FROM raking_targets_ne25
  WHERE estimand = 'PHQ-2 Positive'
  ORDER BY age_years
")

# Get demographic targets for age 0
demo_targets <- DBI::dbGetQuery(con, "
  SELECT estimand, estimate, description
  FROM raking_targets_ne25
  WHERE age_years = 0
    AND estimand IN ('Black', 'Hispanic', 'White non-Hispanic', 'Male')
")

DBI::dbDisconnect(con, shutdown = TRUE)
```

---

## Troubleshooting

### Issue: ACS estimates not found

**Error:** `ERROR: ACS estimates not found`

**Solution:** Run ACS pipeline first:
```r
source("scripts/raking/ne25/01_estimate_income.R")
source("scripts/raking/ne25/02_estimate_mother_education.R")
# ... through 10_save_acs_estimates.R
```

### Issue: NHIS/NSCH data not in database

**Error:** Table `nhis_combined_raw` or `nsch_2023_raw` not found

**Solution:** Run respective data pipeline:
```bash
# NHIS pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024

# NSCH pipeline
python scripts/nsch/process_all_years.py --years 2022 2023
```

### Issue: Python script fails with database error

**Error:** `RuntimeError: generator didn't stop after throw()`

**Solution:** Check for NaN/NULL handling issues. The pipeline should handle these automatically, but ensure:
- All DataFrame columns use proper NULL conversion: `pd.isna(val)` → `None`
- Database columns allow NULL where appropriate (se, lower_ci, upper_ci, sample_size, notes)

### Issue: Missing values in unexpected places

**Error:** Validation shows missing values beyond Emotional/Behavioral at ages 0-2

**Solution:** Check defensive coding in NSCH estimation:
```r
# Ensure explicit case_when() for all NSCH variables
dplyr::case_when(
  variable >= 1 & variable <= 2 ~ 1,  # Valid range
  variable == 0 ~ 0,                  # Valid zero
  TRUE ~ NA_real_                      # Exclude missing codes (90, 95, 96, 99)
)
```

---

## File Structure

```
scripts/raking/ne25/
├── run_raking_targets_pipeline.R       # Master orchestration script
│
├── Phase 1: ACS Estimates
│   ├── 01_estimate_income.R
│   ├── 02_estimate_mother_education.R
│   ├── 03_estimate_mother_marital.R
│   ├── 04_estimate_race_ethnicity.R
│   ├── 05_estimate_child_sex.R
│   ├── 06_estimate_puma.R
│   ├── 07_estimate_mother_marital_status.R
│   ├── 08_compile_acs_estimates.R
│   └── 10_save_acs_estimates_final.R
│
├── Phase 2: NHIS Estimates
│   ├── 12_filter_nhis_parents.R
│   ├── 13_estimate_phq2.R
│   └── 14_validate_save_nhis.R
│
├── Phase 4: NSCH Estimates
│   ├── 17_filter_nsch_nebraska.R
│   ├── 18_estimate_nsch_outcomes.R
│   ├── 19_validate_save_nsch.R
│   └── 20_estimate_childcare_2022.R
│
└── Phase 5: Consolidation
    ├── 21_consolidate_estimates.R
    ├── 22_add_descriptions.R
    ├── 23_validate_targets.R
    └── 24_create_database_table.py

data/raking/ne25/
├── acs_estimates.rds                   # 150 rows (25 estimands × 6 ages)
├── nhis_parents_ne.rds                 # Filtered NHIS data
├── nhis_estimates_raw.rds              # Raw NHIS estimates
├── nhis_estimates.rds                  # 6 rows (1 estimand × 6 ages)
├── nsch_nebraska.rds                   # Filtered NSCH 2023 data
├── nsch_estimates_raw.rds              # Raw NSCH 2023 estimates
├── childcare_2022_estimates.rds        # NSCH 2022 child care estimates
├── nsch_estimates.rds                  # 24 rows (4 estimands × 6 ages)
├── raking_targets_consolidated.rds     # 180 rows (all consolidated)
└── temp_targets.feather                # Temporary file for R→Python transfer

data/duckdb/
└── kidsights_local.duckdb              # Contains raking_targets_ne25 table
```

---

## Next Steps

After generating raking targets, the next phase (not yet implemented) will:

1. **Phase 6: Load NE25 Survey Data**
   - Read from `ne25_derived` table
   - Create raking variables matching estimand definitions

2. **Phase 7: Implement Raking Algorithm**
   - Use `survey` package or `anesrake` package
   - Apply iterative proportional fitting (rake) to adjust weights

3. **Phase 8: Validate Raked Weights**
   - Check convergence
   - Verify target match
   - Calculate effective sample size

4. **Phase 9: Apply Raked Weights**
   - Save weights to database
   - Update analysis pipelines to use raked weights

---

**For questions or issues, see:**
- [Raking Implementation Plan](docs/raking/NE25_RAKING_IMPLEMENTATION_PLAN.md)
- [IPUMS Missing Data Guide](docs/raking/IPUMS_MISSING_DATA_DEFENSIVE_CODING.md)
- [Pipeline Overview](docs/architecture/PIPELINE_OVERVIEW.md)
