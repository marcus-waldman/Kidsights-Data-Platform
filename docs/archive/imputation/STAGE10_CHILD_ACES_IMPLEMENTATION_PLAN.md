# Stage 10-11: Child ACEs Imputation Implementation Plan

**Status:** Planning Phase
**Created:** January 2025
**Target Completion:** TBD

---

## Overview

Implement Stage 10-11 of the imputation pipeline to impute child ACEs (Adverse Childhood Experiences) items and derive the total ACE count. This follows the same architectural pattern as adult mental health (Stage 8-9).

### Variables to Impute (8 binary items)

| REDCap Variable | Renamed Variable | Description | Scale |
|-----------------|------------------|-------------|-------|
| `cqr017` | `child_ace_parent_divorce` | Parent divorced or separated | 0/1 |
| `cqr018` | `child_ace_parent_death` | Parent died | 0/1 |
| `cqr019` | `child_ace_parent_jail` | Parent served time in jail | 0/1 |
| `cqr020` | `child_ace_domestic_violence` | Saw/heard parents/adults slap/hit | 0/1 |
| `cqr021` | `child_ace_neighborhood_violence` | Victim/witness of neighborhood violence | 0/1 |
| `cqr022` | `child_ace_mental_illness` | Lived with mentally ill person | 0/1 |
| `cqr023` | `child_ace_substance_use` | Lived with substance abuser | 0/1 |
| `cqr024` | `child_ace_discrimination` | Treated/judged unfairly due to race/ethnicity | 0/1 |

### Derived Variable

- **`child_ace_total`**: Sum of 8 ACE items (range: 0-8)
  - Only saved for records where ANY of the 8 items needed imputation
  - Uses `na.rm = FALSE` (conservative approach)

### Missing Value Handling

- **Missing codes**: 99 (Prefer not to answer), 9 (system missing)
- **Recoding**: Applied via `recode_missing()` before imputation
- **Storage convention**: Only imputed values stored (not all eligible records)

---

## Implementation Phases

### Phase 1: R Imputation Script

**File:** `scripts/imputation/ne25/06_impute_child_aces.R`

#### Tasks

1. **Create script header and setup**
   - Package loading: duckdb, dplyr, mice, arrow
   - Source configuration: `R/imputation/config.R`
   - Load study config and validate parameters

2. **Implement `load_base_child_aces_data()` function**
   - Query `ne25_transformed` for 8 ACE items (cqr017-cqr024)
   - Include auxiliary variables from base: `authentic.x`, `age_in_days`, `female`
   - Apply defensive filtering: `eligible.x = TRUE AND authentic.x = TRUE`
   - Apply `recode_missing()` for codes 99, 9

3. **Implement `load_auxiliary_imputations()` function**
   - Load PUMA from `ne25_imputed_puma` (imputation m)
   - Load sociodem from imputation m: `raceG`, `educ_mom`, `income`, `family_size`, `fplcat`
   - Load mental health from imputation m: `phq2_positive`, `gad2_positive`
   - Merge with base data using left joins on `pid + record_id`
   - Fill missing auxiliary values from `ne25_transformed` (for observed values)

4. **Implement `save_child_ace_feather()` function**
   - Save only originally-missing records (storage convention)
   - Filter out records where imputation failed (value still NA)
   - Column order: `study_id, pid, record_id, imputation_m, [variable]`
   - Output path: `data/imputation/ne25/child_aces_feather/{variable}_m{m}.feather`

5. **Implement `derive_child_ace_total()` function**
   - Calculate sum of 8 ACE items: `rowSums(..., na.rm = FALSE)`
   - Only save records where ANY of 8 items needed imputation (join-based filtering)
   - Add defensive empty dataframe checks before column assignments

6. **Implement main imputation loop**
   - Loop over M=5 imputations
   - For each m:
     - Load base ACE data
     - Load auxiliary imputations for imputation m
     - Merge all data
     - Configure mice predictor matrix (8 ACE items use all auxiliary variables)
     - Configure method vector: `method = "rf"` for all 8 ACE items
     - Run mice with `m=1, maxit=5, remove.collinear=FALSE, seed=seed+m`
     - Extract completed dataset
     - Save each ACE item (8 files)
     - Derive and save `child_ace_total` (1 file)

7. **Add summary output**
   - Report imputation counts per variable
   - Report child ACE total statistics
   - Print next steps message

8. **Test R script standalone**
   - Run: `Rscript scripts/imputation/ne25/06_impute_child_aces.R`
   - Verify 9 Feather files per imputation (8 items + 1 total)
   - Check row counts match expected missingness
   - Validate `child_ace_total` range (0-8)

9. **Load Phase 2 tasks** ✅

---

### Phase 2: Python Database Insertion Script

**File:** `scripts/imputation/ne25/06b_insert_child_aces.py`

#### Tasks

1. **Create script header and imports**
   - Import: pandas, pathlib, DatabaseManager, get_imputation_config, get_study_config
   - Set up logging with structlog or print statements

2. **Define database schema**
   - 8 item tables: `ne25_imputed_child_ace_{variable}` with INTEGER type
   - 1 derived table: `ne25_imputed_child_ace_total` with INTEGER type
   - Standard columns: `(study_id VARCHAR, pid INTEGER, record_id INTEGER, imputation_m INTEGER, {variable} INTEGER)`
   - Add indexes on `(pid, record_id)` and `imputation_m`

3. **Implement `create_child_ace_tables()` function**
   - Drop tables if they exist (fresh insert)
   - Create 9 tables with proper schema
   - Add indexes for query performance

4. **Implement `insert_child_ace_imputations()` function**
   - Load Feather files from `data/imputation/ne25/child_aces_feather/`
   - For each variable × M=5 imputations:
     - Read Feather file: `{variable}_m{m}.feather`
     - Validate columns: `study_id, pid, record_id, imputation_m, {variable}`
     - Insert into corresponding table
     - Report row count

5. **Add validation checks**
   - Query each table to verify row counts
   - Check for NULL values in ACE items (should be none)
   - Validate `child_ace_total` range (0-8)
   - Report total rows across all 9 tables

6. **Test Python script standalone**
   - Run: `python scripts/imputation/ne25/06b_insert_child_aces.py`
   - Verify 9 tables created in database
   - Check row counts match Feather file counts
   - Query sample records to verify data integrity

7. **Load Phase 3 tasks** ✅

---

### Phase 3: Pipeline Integration

#### Tasks

1. **Update `run_full_imputation_pipeline.R`**
   - Add Stage 10 section after Stage 9
     - Header: "STAGE 10: Child ACEs Imputation (8 items + total)"
     - Execute: `source("scripts/imputation/ne25/06_impute_child_aces.R")`
     - Time tracking: `start_time_ca`, `end_time_ca`, `elapsed_ca`
   - Add Stage 11 section
     - Header: "STAGE 11: Insert Child ACEs into Database"
     - Execute: `reticulate::py_run_file("scripts/imputation/ne25/06b_insert_child_aces.py")`
     - Time tracking: `start_time_ca_insert`, `end_time_ca_insert`, `elapsed_ca_insert`
   - Update final summary
     - Add Stage 10-11 to execution time summary
     - Update total variables: 21 → 30 (+ 9 child ACEs)
     - Update database tables list
     - Update total elapsed time calculation

2. **Test integrated pipeline**
   - Run: `Rscript scripts/imputation/ne25/run_full_imputation_pipeline.R`
   - Verify all 11 stages complete successfully
   - Check total execution time (~2.5-3 minutes)
   - Confirm 30 imputation tables in database

3. **Load Phase 4 tasks** ✅

---

### Phase 4: Python Helper Functions

**File:** `python/imputation/helpers.py`

#### Tasks

1. **Add `get_child_aces_imputations()` function**
   - Parameters: `study_id='ne25', imputation_number=1, include_base_data=False`
   - Variables list: 8 ACE items + `child_ace_total`
   - Docstring with examples showing:
     - Basic usage
     - Prevalence calculation: `(child_ace_total >= 4).mean()`
     - Cross-tabulation by demographics
   - Return via `get_completed_dataset()` with child ACE variables

2. **Update `get_complete_dataset()` function**
   - Add optional parameter: `include_child_aces=True`
   - Update variable list to include 9 child ACE variables
   - Update docstring to show 30 total variables
   - Update examples to demonstrate child ACEs retrieval

3. **Update `validate_imputations()` function**
   - Add validation for 9 child ACE tables
   - Check row counts per imputation
   - Verify `child_ace_total` range (0-8)
   - Check for NULL values (should be none in successfully imputed records)

4. **Update module docstring**
   - Update quick examples to include `get_child_aces_imputations()`
   - Update total variable count: 21 → 30

5. **Test helper functions**
   - Run: `python -m python.imputation.helpers`
   - Verify `get_child_aces_imputations()` returns correct columns
   - Check prevalence calculations make sense
   - Test `get_complete_dataset()` with all 30 variables

6. **Load Phase 5 tasks** ✅

---

### Phase 5: Documentation Updates

#### Tasks

1. **Update `IMPUTATION_PIPELINE.md`**
   - Add "Child ACEs Imputation Tables" section
   - Include SQL schema for all 9 tables
   - Document storage convention for child ACE total
   - Update pipeline overview: 9-stage → 11-stage, 21 → 30 variables
   - Update production metrics (total rows, execution time)
   - Add notes about random forest method for binary outcomes

2. **Update `PIPELINE_OVERVIEW.md`**
   - Update imputation pipeline summary
     - Architecture: 11-stage sequential
     - Variables: 30 (3 geography + 7 sociodem + 4 childcare + 7 mental health + 9 child ACEs)
     - Total rows: ~83,401 → ~85,000+ (add child ACEs)
     - Execution time: ~2.3 min → ~2.5-3 min
   - Update table list to include 9 child ACE tables

3. **Update `QUICK_REFERENCE.md`**
   - Update imputation pipeline command section
     - Purpose: Add "child ACEs" to list
     - What it does: Add Stage 10-11 description
     - Timing: Update to ~2.5-3 minutes
     - Output: Update to 30 variables across 30 tables
   - Update Python usage examples
     - Add `get_child_aces_imputations()` import
     - Add example: Get child ACEs for imputation m=1
     - Add example: Check 4+ ACEs prevalence
     - Update `get_complete_dataset()` to show 30 variables
   - Update pipeline status summary: 21 → 30 variables

4. **Update `CLAUDE.md`**
   - Update imputation pipeline quick start
     - Command description: Add child ACEs
     - Execution time: ~2.3 → ~2.5-3 minutes
   - Update current status section
     - Variables: 21 → 30
     - Database rows: 83,401 → ~85,000+
     - Stages: 9 → 11
     - Add child ACEs description: "9 variables via random forest (8 items + derived total)"

5. **Create `STAGE10_CHILD_ACES_TASK_LIST.md` (this file)**
   - Mark status as "Complete"
   - Add final checklist with actual row counts
   - Document any implementation notes or gotchas

6. **Verify all documentation is consistent**
   - Check all mentions of "21 variables" updated to "30"
   - Check all mentions of "9 stages" updated to "11"
   - Check execution time updated throughout
   - Check all code examples work correctly

7. **Final validation** ✅

---

## Auxiliary Variables Configuration

### Geography (from imputation m)
- `puma` - Public Use Microdata Area

### Sociodemographic (from imputation m, fillna from base)
- `raceG` - Race/ethnicity (grouped)
- `educ_mom` - Mother's education
- `income` - Household income
- `family_size` - Number in household
- `fplcat` - Federal poverty level category

### Mental Health (from imputation m, fillna from base)
- `phq2_positive` - PHQ-2 positive screen (≥3)
- `gad2_positive` - GAD-2 positive screen (≥3)

### Base Data (always from ne25_transformed)
- `authentic.x` - Data quality flag (also used as defensive filter)
- `age_in_days` - Child's age in days
- `female` - Child's sex (0=male, 1=female)

---

## MICE Configuration

```r
mice::mice(
  data = dat_mice,
  m = 1,                          # Chained approach (1 per imputation m)
  method = "rf",                  # Random forest for all 8 ACE items
  predictorMatrix = predictor_matrix,  # ACE items use all auxiliary vars
  maxit = 5,                      # Iteration count
  remove.collinear = FALSE,       # Per user requirement
  seed = seed + m,                # Unique seed per imputation
  printFlag = FALSE
)
```

**Predictor Matrix:**
- Each ACE item predicted by: puma, raceG, educ_mom, income, family_size, fplcat, phq2_positive, gad2_positive, authentic.x, age_in_days, female
- Auxiliary variables NOT imputed (use complete cases or pre-imputed values)

---

## Expected Output

### Database Tables (9 total)
- `ne25_imputed_child_ace_parent_divorce`
- `ne25_imputed_child_ace_parent_death`
- `ne25_imputed_child_ace_parent_jail`
- `ne25_imputed_child_ace_domestic_violence`
- `ne25_imputed_child_ace_neighborhood_violence`
- `ne25_imputed_child_ace_mental_illness`
- `ne25_imputed_child_ace_substance_use`
- `ne25_imputed_child_ace_discrimination`
- `ne25_imputed_child_ace_total` (derived)

### Row Counts (estimated)
- Per item: Varies based on missingness (likely 50-200 rows per imputation)
- Total across all 9 tables: ~1,500-2,000 rows (for M=5)

### Execution Time
- Stage 10 (R imputation): ~10-15 seconds
- Stage 11 (Database insertion): ~2-5 seconds
- **Total pipeline: ~2.5-3 minutes** (up from 2.3 minutes)

---

## Storage Convention Compliance

**Critical Principle:** Only imputed/derived values are stored in imputation tables.

1. **ACE Items (8 tables):**
   - Store ONLY records where original value was NA
   - Filter: `is.na(original_data[[variable]])`
   - Defensive: Remove records where imputation failed (still NA after mice)

2. **Child ACE Total (1 table):**
   - Store ONLY records where ANY of 8 items needed imputation
   - Logic: Join with union of all 8 items' imputed records
   - Defensive: Check `nrow() > 0` before adding columns

3. **Retrieval:**
   - Helper functions use `fillna()` to merge imputed (from tables) with observed (from base)
   - Result: Complete dataset with proper uncertainty propagation

---

## Testing Checklist

### R Script Testing
- [ ] Script runs without errors
- [ ] 9 Feather files created per imputation (45 total)
- [ ] Row counts match expected missingness
- [ ] `child_ace_total` range is 0-8
- [ ] No NA values in successfully imputed records

### Python Script Testing
- [ ] 9 database tables created
- [ ] Row counts match Feather file counts
- [ ] Indexes created on all tables
- [ ] Sample queries return correct data

### Pipeline Integration Testing
- [ ] All 11 stages complete successfully
- [ ] Execution time ~2.5-3 minutes
- [ ] No errors or warnings
- [ ] Database has 30 imputation tables total

### Helper Functions Testing
- [ ] `get_child_aces_imputations()` returns 9 variables
- [ ] `get_complete_dataset()` returns 30 variables
- [ ] Validation passes for all 9 tables
- [ ] Prevalence calculations make sense (e.g., 4+ ACEs < 25%)

### Documentation Testing
- [ ] All variable counts updated (21 → 30)
- [ ] All stage counts updated (9 → 11)
- [ ] All execution times updated
- [ ] Code examples run successfully

---

## Next Steps After Completion

1. **Validation:** Run end-to-end pipeline test
2. **Analysis:** Calculate child ACE prevalence by demographics
3. **Comparison:** Compare with NSCH national estimates for validation
4. **Reporting:** Generate summary statistics for child ACE exposure
5. **Integration:** Use in multi-level models with multiply imputed data

---

## Notes

- **Method Choice:** Random forest (`method = "rf"`) chosen over CART because it handles binary outcomes more robustly and is less prone to overfitting
- **Collinearity:** `remove.collinear = FALSE` specified by user, appropriate for random forest
- **Uncertainty Propagation:** Proper sequential imputation ensures uncertainty from geography → sociodem → mental health → child ACEs
- **Defensive Filtering:** `eligible.x = TRUE AND authentic.x = TRUE` ensures only high-quality records are imputed

---

**Document Version:** 1.0
**Last Updated:** January 2025
