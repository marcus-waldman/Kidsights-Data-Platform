# Raking Targets Documentation

**Last Updated:** April 2026 (drift-checked 2026-04-20)

This directory contains comprehensive documentation for the NE25 raking targets pipeline - a system for generating population-representative targets for post-stratification weighting of survey data.

---

## 📋 Quick Start

### Run Raking Targets Pipeline

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

**Execution time:** ~2-3 minutes
**Output:** 180 raking targets by design in `raking_targets_ne25` database table *(⚠️ as of 2026-04-20 the table contains only 11 rows — verify whether the full target table needs regeneration)*

### Run Bootstrap Replicates (ACS Only)

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_bootstrap_pipeline.R
```

**Execution time:** ~15-20 minutes (4096 replicates, 16 workers)
**Output:** 737,280 bootstrap replicates in `raking_targets_boot_replicates` table (verified 2026-04-20; was 614,400 in earlier docs — bootstrap was expanded from 150 to 180 target slots)
**Note:** Bootstrap currently implemented for ACS estimands only (25 of 30)

### Verify Results

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

---

## 📚 Documentation Index

### Core Pipeline Documentation

- **[NE25_RAKING_TARGETS_PIPELINE.md](NE25_RAKING_TARGETS_PIPELINE.md)** ⭐ **START HERE**
  - Complete pipeline documentation
  - Architecture overview
  - Step-by-step execution instructions
  - Database schema and querying
  - Validation and troubleshooting

### Implementation Documentation

Located in `ne25/` subdirectory:

- **[IMPLEMENTATION_TODO.md](../archive/raking/ne25/IMPLEMENTATION_TODO.md)** - Task tracking (archived after Phases 1-5 complete)
- **[RAKING_TARGETS_ESTIMATION_PLAN.md](ne25/RAKING_TARGETS_ESTIMATION_PLAN.md)** - Detailed estimation plan (active reference)
- **[STATISTICAL_METHODS_RAKING_TARGETS.md](ne25/STATISTICAL_METHODS_RAKING_TARGETS.md)** - Statistical methodology + bootstrap variance estimation
- **[BOOTSTRAP_IMPLEMENTATION_PLAN.md](../archive/raking/ne25/BOOTSTRAP_IMPLEMENTATION_PLAN.md)** - Bootstrap replicate weights implementation (archived; work completed Oct 2025)
- **[BOOTSTRAP_TASK_LIST.md](../archive/raking/ne25/BOOTSTRAP_TASK_LIST.md)** - Phase-by-phase task tracking for bootstrap (archived)
- **[MULTINOMIAL_APPROACH_DECISION.md](ne25/MULTINOMIAL_APPROACH_DECISION.md)** - Why separate binary models for FPL/PUMA
- **[MOTHER_EDUCATION_ADDITION.md](ne25/MOTHER_EDUCATION_ADDITION.md)** - Mother's education implementation
- **[MOTHER_MARITAL_STATUS_ADDITION.md](ne25/MOTHER_MARITAL_STATUS_ADDITION.md)** - Marital status implementation
- **[RAKING_INTEGRATION.md](RAKING_INTEGRATION.md)** ⭐ — NE25 raking weight integration guide (April 2026, current)
- **[ne25/WEIGHT_CONSTRUCTION.qmd](ne25/WEIGHT_CONSTRUCTION.qmd)** — Weight construction narrative (April 2026, current)

---

## 🎯 What is Raking?

**Raking** (also called iterative proportional fitting or post-stratification) is a statistical technique that adjusts survey weights to match known population distributions.

### Why We Need It

The NE25 survey sample may not perfectly represent Nebraska's population of children ages 0-5. Raking corrects this by:

1. **Comparing** survey distributions to population benchmarks (raking targets)
2. **Adjusting** sample weights to match population marginals
3. **Improving** the representativeness of survey estimates

### Our Implementation

**Raking Targets Pipeline (Phases 1-5):** ✅ Complete (October 2025)
- Generates 180 population targets from ACS, NHIS, and NSCH data
- Stores in database for efficient querying
- Provides 30 estimands across 6 age groups (0-5 years)

**Raking Implementation (Phase 6+):** Future work
- Will apply targets to NE25 using R `survey` package
- Will generate raked weights for analysis

---

## 📊 Raking Targets Overview

### Data Sources

| Source | Estimands | Purpose | Method |
|--------|-----------|---------|--------|
| **ACS** | 25 | Demographics, SES, geography | GLM by age |
| **NHIS** | 1 | Parent mental health (PHQ-2) | GLM by age |
| **NSCH** | 4 | Child ACEs, health, child care | GLMM with state random effects |
| **Total** | **30** | **180 targets (30 × 6 ages)** | - |

### Estimands

**ACS (25):**
- Income: 0-99%, 100-199%, 200-299%, 300-399%, 400%+ FPL
- Demographics: Black, Hispanic, White non-Hispanic, Male
- Socioeconomic: Mother Bachelor's+, Mother Married
- Geography: 14 PUMA regions in Nebraska

**NHIS (1):**
- PHQ-2 Positive (parent depression screen ≥3)

**NSCH (4):**
- Child ACE Exposure (1+ ACEs)
- Emotional/Behavioral Problems (ages 3-5 only)
- Excellent Health Rating
- Child Care 10+ Hours/Week

---

## 🚀 Pipeline Architecture

### Five-Phase Implementation

```
Phase 1: ACS Estimates (25 estimands)
  ├─ Income, demographics, geography
  ├─ GLM models by age
  └─ Output: acs_estimates.rds (150 rows)

Phase 2: NHIS Estimates (1 estimand)
  ├─ Filter to Nebraska parents
  ├─ PHQ-2 depression screening
  └─ Output: nhis_estimates.rds (6 rows)

Phase 4: NSCH Estimates (4 estimands)
  ├─ Filter to Nebraska children
  ├─ Mixed models with state random effects
  └─ Output: nsch_estimates.rds (24 rows)

Phase 5: Consolidation & Database
  ├─ Combine all estimates
  ├─ Add descriptions and metadata
  ├─ Validate data quality
  └─ Output: raking_targets_ne25 table (180 rows)
```

**Master Script:** `scripts/raking/ne25/run_raking_targets_pipeline.R`

---

## 💾 Database Schema

### Table: `raking_targets_ne25`

```sql
CREATE TABLE raking_targets_ne25 (
    target_id INTEGER PRIMARY KEY,
    survey VARCHAR NOT NULL,              -- Always 'ne25'
    age_years INTEGER NOT NULL,           -- 0-5
    estimand VARCHAR NOT NULL,            -- Short name
    description VARCHAR NOT NULL,         -- Full description
    data_source VARCHAR NOT NULL,         -- 'ACS', 'NHIS', 'NSCH'
    estimator VARCHAR NOT NULL,           -- 'GLM' or 'GLMM'
    estimate DOUBLE,                      -- Proportion (0-1)
    se DOUBLE,                            -- Standard error (placeholder)
    lower_ci DOUBLE,                      -- Lower 95% CI (placeholder)
    upper_ci DOUBLE,                      -- Upper 95% CI (placeholder)
    sample_size INTEGER,                  -- Sample size (placeholder)
    estimation_date DATE NOT NULL,        -- Date generated
    notes VARCHAR                         -- Additional notes (placeholder)
)
```

### Indexes

- `idx_estimand` - Filter by specific target
- `idx_data_source` - Filter by data source
- `idx_age_years` - Filter by age
- `idx_estimand_age` - Combined queries

---

## 📖 Usage Examples

### Query from Python

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Get all targets for age 3
with db.get_connection(read_only=True) as conn:
    results = conn.execute("""
        SELECT estimand, estimate, description
        FROM raking_targets_ne25
        WHERE age_years = 3
        ORDER BY data_source, estimand
    """).fetchall()

    for row in results:
        print(f"{row[0]}: {row[1]:.3f} - {row[2]}")
```

### Query from R

```r
library(DBI)
library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(),
    "data/duckdb/kidsights_local.duckdb",
    read_only = TRUE)

# Get PHQ-2 targets across all ages
phq2_targets <- DBI::dbGetQuery(con, "
  SELECT age_years, estimate
  FROM raking_targets_ne25
  WHERE estimand = 'PHQ-2 Positive'
  ORDER BY age_years
")

print(phq2_targets)

DBI::dbDisconnect(con, shutdown = TRUE)
```

---

## ✅ Validation

The pipeline includes comprehensive validation:

- **Completeness:** All key columns populated (except expected NAs)
- **Range checks:** All estimates are valid proportions (0-1)
- **Consistency:** Each estimand has exactly 6 rows (ages 0-5)
- **Expected missing:** 3 values for Emotional/Behavioral at ages 0-2 (not applicable)
- **Database integrity:** 180 rows, 30 unique estimands, 4 indexes

**Verification script:** `scripts/raking/ne25/verify_pipeline.R`

---

## 🔗 Related Documentation

### Architecture Documentation
- [PIPELINE_OVERVIEW.md](../architecture/PIPELINE_OVERVIEW.md) - All pipelines architecture
- [QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - Command cheatsheet

### Data Source Documentation
- [ACS Pipeline](../acs/) - Census data extraction
- [NHIS Pipeline](../nhis/) - Health surveys data
- [NSCH Pipeline](../nsch/) - Children's health survey

### Development Guides
- [CODING_STANDARDS.md](../guides/CODING_STANDARDS.md) - R namespacing, defensive coding
- [MISSING_DATA_GUIDE.md](../guides/MISSING_DATA_GUIDE.md) - IPUMS missing data handling

---

## 🛠️ Troubleshooting

### Common Issues

**Error: ACS estimates not found**
- **Solution:** Run ACS estimation scripts (Phase 1) first
- **Location:** `scripts/raking/ne25/01_*.R` through `10_*.R`

**Error: NHIS/NSCH table not found**
- **Solution:** Load NHIS or NSCH data into database
- **Commands:** See [QUICK_REFERENCE.md](../QUICK_REFERENCE.md)

**Error: Verification failed**
- **Solution:** Run verification script to identify specific issue
- **Command:** `"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R`

---

## 📈 Future Work (Phase 6+)

### Raking Implementation
- Apply raking targets to NE25 survey data
- Use R `survey` package for iterative proportional fitting
- Generate raked weights for all NE25 records
- Validate convergence and effective sample size

### Benchmarking
- Compare NE25 estimates to national NHIS/NSCH benchmarks
- Track trends over time using multi-year NSCH data
- Generate comparative reports (Nebraska vs National)

---

**For questions or issues, see the main documentation or open an issue in the repository.**

*Last Updated: April 2026 (drift-checked 2026-04-20)*

---

## Verification Summary

**Last fact-check:** 2026-04-20 (Bucket C Tier 4 of doc audit)

### Corrections applied
- 3 broken links to docs archived in Bucket B repointed to `../archive/raking/ne25/` (`IMPLEMENTATION_TODO.md`, `BOOTSTRAP_IMPLEMENTATION_PLAN.md`, `BOOTSTRAP_TASK_LIST.md`)
- Bootstrap replicate count: 614,400 → 737,280 (verified — bootstrap was expanded from 4096×150 to 4096×180)
- Added pointers to current April 2026 docs (`RAKING_INTEGRATION.md`, `WEIGHT_CONSTRUCTION.qmd`)
- Flagged `raking_targets_ne25` table DB drift (180 designed vs 11 actual)
- Last Updated date refreshed
