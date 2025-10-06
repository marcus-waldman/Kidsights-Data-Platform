# NE25 Raking Targets Scripts

**Purpose:** Generate population-representative raking targets for post-stratification weighting of Nebraska 2025 survey data.

**Output:** 180 raking targets (30 estimands × 6 age groups) stored in `raking_targets_ne25` database table.

---

## Quick Start

### 1. Run Full Pipeline

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

**Execution time:** ~2-3 minutes
**Prerequisites:**
- ACS estimates from Phase 1 (run scripts 01-10 if missing)
- NHIS data in database (`nhis_combined_raw` table)
- NSCH data in database (`nsch_2022_raw`, `nsch_2023_raw` tables)

### 2. Verify Pipeline Results

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

**Checks:**
- All required files exist
- Row counts are correct (150 + 6 + 24 = 180)
- Estimand counts are correct (25 + 1 + 4 = 30)
- No unexpected missing values
- All estimates are valid proportions (0-1)
- Database table exists with 180 rows

---

## Pipeline Overview

### Data Sources

1. **ACS (American Community Survey)** → 25 estimands (150 rows)
   - Demographics, socioeconomic status, geography

2. **NHIS (National Health Interview Survey)** → 1 estimand (6 rows)
   - Parent mental health (PHQ-2 depression screen)

3. **NSCH (National Survey of Children's Health)** → 4 estimands (24 rows)
   - Child ACEs, health status, child care

### Pipeline Phases

| Phase | Description | Scripts | Output |
|-------|-------------|---------|--------|
| **1** | ACS Estimates | `01_*.R` - `10_*.R` | `acs_estimates.rds` (150 rows) |
| **2** | NHIS Estimates | `12_*.R` - `14_*.R` | `nhis_estimates.rds` (6 rows) |
| **4** | NSCH Estimates | `17_*.R` - `20_*.R` | `nsch_estimates.rds` (24 rows) |
| **5** | Consolidation | `21_*.R` - `24_*.py` | `raking_targets_ne25` table (180 rows) |

### Key Features

- **Age-specific estimates:** All estimands calculated for ages 0-5
- **Mixed methodology:** GLM for ACS/NHIS, GLMM with state random effects for NSCH
- **Defensive coding:** Explicit handling of IPUMS/NSCH missing value codes
- **Database integration:** Final targets stored in DuckDB with indexes for efficient querying

---

## Scripts Reference

### Phase 1: ACS Estimates (25 estimands)

Prerequisite: Run ACS pipeline to generate these estimates first.

| Script | Estimands | Method |
|--------|-----------|--------|
| `01_estimate_income.R` | 5 income categories (0-99%, 100-199%, etc.) | GLM by age |
| `02_estimate_mother_education.R` | Mother Bachelor's+ | GLM by age |
| `03_estimate_mother_marital.R` | Mother Married | GLM by age |
| `04_estimate_race_ethnicity.R` | Black, Hispanic, White non-Hispanic | GLM by age |
| `05_estimate_child_sex.R` | Male | GLM by age |
| `06_estimate_puma.R` | 14 PUMA regions | GLM by age |
| `10_save_acs_estimates_final.R` | - | Consolidate and save |

**Output:** `data/raking/ne25/acs_estimates.rds`

### Phase 2: NHIS Estimates (1 estimand)

| Script | Purpose | Method |
|--------|---------|--------|
| `12_filter_nhis_parents.R` | Filter to NE parents with children 0-5 | DuckDB query |
| `13_estimate_phq2.R` | Estimate PHQ-2 positive (≥3) by age | GLM by age |
| `14_validate_save_nhis.R` | Validate and save estimates | Checks + save |

**Output:** `data/raking/ne25/nhis_estimates.rds`

### Phase 4: NSCH Estimates (4 estimands)

| Script | Purpose | Method |
|--------|---------|--------|
| `17_filter_nsch_nebraska.R` | Filter to NE children ages 0-5 | DuckDB query |
| `18_estimate_nsch_outcomes.R` | Estimate 3 outcomes from NSCH 2023 | GLMM with state RE |
| `20_estimate_childcare_2022.R` | Estimate child care from NSCH 2022 | GLMM with state RE |
| `19_validate_save_nsch.R` | Validate and save estimates | Checks + save |

**Output:** `data/raking/ne25/nsch_estimates.rds`

**Note:** Uses BLUP (Best Linear Unbiased Predictor) to extract Nebraska-specific estimates from national mixed models.

### Phase 5: Consolidation & Database

| Script | Purpose | Method |
|--------|---------|--------|
| `21_consolidate_estimates.R` | Combine all estimates | Row bind with standardization |
| `22_add_descriptions.R` | Add estimand descriptions | Named vector lookup |
| `23_validate_targets.R` | Comprehensive validation | Multiple checks |
| `24_create_database_table.py` | Create table, insert, index | Python + DuckDB |

**Output:** `raking_targets_ne25` table in `data/duckdb/kidsights_local.duckdb`

---

## Querying Raking Targets

### Python

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Get all targets for age 3
with db.get_connection(read_only=True) as conn:
    results = conn.execute("""
        SELECT estimand, estimate, data_source, description
        FROM raking_targets_ne25
        WHERE age_years = 3
        ORDER BY data_source, estimand
    """).fetchall()

    for row in results:
        print(f"{row[0]}: {row[1]:.3f} ({row[2]})")
```

### R

```r
library(DBI)
library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

# Get PHQ-2 targets across all ages
phq2 <- DBI::dbGetQuery(con, "
  SELECT age_years, estimate
  FROM raking_targets_ne25
  WHERE estimand = 'PHQ-2 Positive'
  ORDER BY age_years
")

print(phq2)

DBI::dbDisconnect(con, shutdown = TRUE)
```

---

## Expected Output Summary

### Row Counts
- **ACS:** 150 rows (25 estimands × 6 ages)
- **NHIS:** 6 rows (1 estimand × 6 ages)
- **NSCH:** 24 rows (4 estimands × 6 ages)
- **Total:** 180 rows

### Estimands by Source

**ACS (25):**
- Income: 0-99%, 100-199%, 200-299%, 300-399%, 400%+
- Demographics: Black, Hispanic, White non-Hispanic, Male
- Socioeconomic: Mother Bachelor's+, Mother Married
- Geography: PUMA_100 through PUMA_904 (14 regions)

**NHIS (1):**
- PHQ-2 Positive (parent depression screen)

**NSCH (4):**
- Child ACE Exposure (1+ ACEs)
- Emotional/Behavioral Problems (ages 3-5 only)
- Excellent Health Rating
- Child Care 10+ Hours/Week

### Missing Values
- **Expected:** 3 missing values for "Emotional/Behavioral Problems" at ages 0-2
- **Reason:** Variable only applicable to ages 3-5 in NSCH
- **All other estimates:** Valid proportions (0-1)

---

## Troubleshooting

### Error: ACS estimates not found

**Solution:** Run ACS pipeline scripts 01-10 first:
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/01_estimate_income.R
# ... through 10_save_acs_estimates_final.R
```

### Error: NHIS/NSCH table not found

**Solution:** Load NHIS or NSCH data into database:
```bash
# NHIS
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024

# NSCH
python scripts/nsch/process_all_years.py --years 2022 2023
```

### Error: Verification failed

**Solution:** Run verification script to identify specific issue:
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

---

## Documentation

**Detailed documentation:** [docs/raking/NE25_RAKING_TARGETS_PIPELINE.md](../../../docs/raking/NE25_RAKING_TARGETS_PIPELINE.md)

**Implementation plan:** [docs/raking/NE25_RAKING_IMPLEMENTATION_PLAN.md](../../../docs/raking/NE25_RAKING_IMPLEMENTATION_PLAN.md)

**IPUMS missing data guide:** [docs/raking/IPUMS_MISSING_DATA_DEFENSIVE_CODING.md](../../../docs/raking/IPUMS_MISSING_DATA_DEFENSIVE_CODING.md)

---

**Last Updated:** October 2025
**Version:** 1.0
