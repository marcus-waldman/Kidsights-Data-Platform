# CART Imputation Pipeline - Implementation Plan

**Created:** October 2025
**Purpose:** Extend geographic imputation pipeline to include sociodemographic variables using CART method via R `mice` package

---

## Overview

Extend the geographic imputation pipeline to include **sociodemographic variables** using **CART (Classification and Regression Trees)** method via the R `mice` package. This will create M=5 imputations for missing values in child and family characteristics.

### Unified Pipeline Design

**Single Command Execution:** The complete imputation pipeline runs as a unified workflow via `scripts/imputation/run_full_imputation_pipeline.R`.

**Two-Stage Sequential Process:**

**Stage 1: Geographic Imputation (Python)**
```
Script: scripts/imputation/01_impute_geography.py
Method: Probabilistic allocation using afact (allocation factors)
Output: 5 imputations for puma, county, census_tract
Runtime: ~2-3 seconds
```

**Stage 2: Sociodemographic Imputation (R)**
```
Script: scripts/imputation/02_impute_sociodemographic.R
Method: CART + Random Forest via mice package

For each geography imputation m in 1:5:
  1. Load base data + imputed geography from imputation m (puma, county)
  2. Filter to eligible records only (eligible.x=TRUE)
  3. Run mice(m=1, method=cart/rf) using geography as fixed predictors
  4. Calculate derived FPL category from imputed income + family_size
  5. Store sociodem imputation m to database

Runtime: ~5-10 minutes (mice with CART/RF on 3,460 records × 5 iterations)
```

**Result:** Each of 5 imputations has **internally consistent** geography and sociodemographic values. If person lives in wealthy PUMA in imputation 3, their income/education reflects that context.

---

## Variables to Impute (6 total)

### From `ne25_transformed` table (ELIGIBLE RECORDS ONLY):

**IMPORTANT:** Imputation will only be performed on records where `eligible.x = TRUE` (n=3,460 records, 70.6% of dataset). Ineligible records will be excluded from imputation.

1. **female** - Child is female (Binary: TRUE/FALSE)
   - Current missingness: 39.4% (1,929 / 4,900 total, ~14.5% among eligible)
   - Type: Binary logical
   - Method: CART

2. **raceG** - Child's race/ethnicity grouped (Factor: 7 categories)
   - Categories: White non-Hisp., AIAN non-Hisp., Asian/PI non-Hisp., Black non-Hisp., Hispanic, Other non-Hisp., Two or More non-Hisp.
   - Current missingness: 40.0% (1,961 / 4,900 total, TBD among eligible)
   - Type: Nominal categorical
   - Method: CART

3. **educ_mom** - Maternal education (Factor: 8 categories)
   - Current missingness: 55.0% (2,696 / 4,900 total, TBD among eligible)
   - Type: Ordinal categorical
   - Method: Random Forest (ranger)

4. **educ_a2** - Adult 2 (secondary caregiver/father) education (Factor: 8 categories)
   - Current missingness: 51.3% (2,513 / 4,900 total, TBD among eligible)
   - Type: Ordinal categorical
   - Method: Random Forest (ranger)

5. **income** - Family income (Numeric: dollars)
   - Current missingness: 35.3% (1,732 / 4,900 total, TBD among eligible)
   - Type: Continuous
   - Method: CART

6. **family_size** - Household size (Numeric: 1-99)
   - Current missingness: 38.2% (1,874 / 4,900 total, TBD among eligible)
   - Type: Count
   - Method: CART

### Derived After Imputation:

7. **fplcat** - Federal Poverty Level category (Factor: 5 levels)
   - Calculated from imputed `income` and `family_size`
   - Current missingness: 38.6% (1,893 / 4,900)
   - Formula: `fpl = (income / federal_poverty_threshold(family_size)) * 100`

---

## Auxiliary Variables (Predictors)

**Include in imputation models but do NOT impute:**

1. **puma** - Geographic PUMA (from geography imputation m, varies by imputation)
2. **county** - County FIPS code (from geography imputation m, varies by imputation)
3. **source_project** - Project ID (redcap_pid: 7679, 7943, 7999, 8014)
4. **authentic.x** - Authenticity flag (Logical: TRUE/FALSE)
5. **age_in_days** - Child age in days (continuous, complete data)
6. **consent_date** - Survey date (for temporal patterns, complete data)
7. **mom_a1** - Is Adult 1 the mother? (Logical: TRUE/FALSE, 36% missing)
8. **relation1** - Adult 1's relationship to child (Factor: 6 levels, 36% missing)

**Note:** `eligible.x` is used to FILTER the dataset (only eligible=TRUE records are imputed), not as a predictor.

---

## Implementation Architecture

### Phase 1: Configuration & Schema

**Tasks:**

- [ ] **Task 1.1:** Extend `config/imputation/imputation_config.yaml` with sociodemographic section
- [ ] **Task 1.2:** Update `python/imputation/config.py` to load sociodemographic config
- [ ] **Task 1.3:** Update `R/imputation/config.R` to expose sociodemographic config via reticulate
- [ ] **Task 1.4:** Create `sql/imputation/create_sociodem_imputation_tables.sql` with 7 new tables
- [ ] **Task 1.5:** Update `scripts/imputation/00_setup_imputation_schema.py` to execute new SQL
- [ ] **Task 1.6:** Run schema setup to create tables in DuckDB
- [ ] **Task 1.7:** VERIFICATION - Confirm all Phase 1 tasks complete, load Phase 2 tasks

**1.1 Config YAML Extension:**
```yaml
n_imputations: 5
random_seed: 42

geography:
  variables: [puma, county, census_tract]
  method: "probabilistic_allocation"

sociodemographic:  # NEW SECTION
  variables: [female, raceG, educ_mom, educ_a2, income, family_size]
  eligible_only: true  # Only impute records where eligible.x = TRUE
  mice_method:
    female: "cart"
    raceG: "cart"
    educ_mom: "rf"      # Random forest for ordinal variables
    educ_a2: "rf"       # Random forest for ordinal variables
    income: "cart"
    family_size: "cart"
  rf_package: "ranger"  # Use ranger for random forest (fast C++ implementation)
  auxiliary_variables: [puma, county, source_project, authentic.x, age_in_days, consent_date, mom_a1, relation1]
  remove_collinear: false  # Keep collinear variables (important for imputation quality)
  chained: true  # Run mice 5 times (once per geography imputation)

derived:  # NEW SECTION
  variables: [fplcat]
  depends_on: [income, family_size]
```

**1.4 SQL Schema (7 tables):**
```sql
-- Imputed female (binary: TRUE/FALSE)
CREATE TABLE imputed_female (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  female BOOLEAN NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Imputed raceG (similar structure)
CREATE TABLE imputed_raceG (...);
CREATE TABLE imputed_educ_mom (...);
CREATE TABLE imputed_educ_a2 (...);
CREATE TABLE imputed_income (...);      -- DOUBLE type
CREATE TABLE imputed_family_size (...); -- DOUBLE type
CREATE TABLE imputed_fplcat (...);      -- Derived variable
```

---

### Phase 2: CART Imputation Script (R)

**Tasks:**

- [ ] **Task 2.1:** Create `scripts/imputation/02_impute_sociodemographic.R` skeleton
- [ ] **Task 2.2:** Implement data loading from DuckDB with geography merge
- [ ] **Task 2.3:** Implement `mice` configuration and imputation workflow
- [ ] **Task 2.4:** Implement FPL calculation for each imputation
- [ ] **Task 2.5:** Implement selective storage (only originally missing records)
- [ ] **Task 2.6:** Create Python insertion script `scripts/imputation/02b_insert_sociodem_imputations.py`
- [ ] **Task 2.7:** Create unified orchestrator `scripts/imputation/run_full_imputation_pipeline.R`
- [ ] **Task 2.8:** Test with small subset (n=100 records, m=2 imputations)
- [ ] **Task 2.9:** Run full imputation (n=4,900 records, m=5 imputations)
- [ ] **Task 2.10:** VERIFICATION - Confirm all Phase 2 tasks complete, load Phase 3 tasks

**2.1-2.5 R Script Pseudocode (CHAINED APPROACH):**
```r
library(mice)
library(duckdb)
source("R/imputation/config.R")

# Get config
M <- get_n_imputations()  # 5
seed <- get_random_seed() # 42

# Variables to impute
imp_vars <- c("female", "raceG", "educ_mom", "educ_a2", "income", "family_size")

# Auxiliary variables (include geography - will vary by imputation m)
aux_vars <- c("puma", "county", "source_project", "authentic.x", "age_in_days",
              "mom_a1", "relation1")

# Configure mice - CART for categorical/continuous, RF for ordinal
methods <- c(
  female = "cart",
  raceG = "cart",
  educ_mom = "rf",      # Random forest for ordinal
  educ_a2 = "rf",       # Random forest for ordinal
  income = "cart",
  family_size = "cart"
)

# LOOP OVER GEOGRAPHY IMPUTATIONS
for(m in 1:M) {
  cat(sprintf("\n=== Running imputation for geography imputation m=%d ===\n", m))

  # Load base data + geography imputation m
  dat_m <- load_base_data_from_duckdb()

  # FILTER TO ELIGIBLE RECORDS ONLY
  dat_m <- dat_m[dat_m$eligible.x == TRUE, ]
  cat(sprintf("Eligible records: %d (filtered from %d total)\n", nrow(dat_m), 4900))

  # Add geography from imputation m
  dat_m$puma <- get_imputed_geography("puma", m)
  dat_m$county <- get_imputed_geography("county", m)

  # Run mice with geography as FIXED auxiliary (m=1 means create 1 imputation)
  set.seed(seed + m)  # Different seed per geography imputation
  imp_m <- mice(dat_m[c(imp_vars, aux_vars)],
                m=1,                      # Create 1 sociodem imputation per geography imputation
                method=methods,           # CART for categorical/continuous, RF for ordinal
                rfPackage="ranger",       # Use ranger for random forest
                remove.collinear=FALSE,   # Keep collinear predictors (important!)
                maxit=20,
                printFlag=FALSE)

  # Extract completed dataset - this is imputation m overall
  completed_m <- complete(imp_m, 1)

  # Calculate derived FPL category
  completed_m$fplcat <- calculate_fpl_category(completed_m$income,
                                                completed_m$family_size,
                                                completed_m$consent_date)

  # Store only originally missing values for imputation m
  store_imputation_feather(completed_m, m, original_data=dat_m)
}

cat("\n=== Imputation complete for all M=5 imputations ===\n")
cat(sprintf("Total records imputed: %d eligible records\n", nrow(dat_m)))
cat("Methods used: CART (female, raceG, income, family_size), RF (educ_mom, educ_a2)\n")
```

**2.6 Python Insertion Script:**
```python
# Read feather files from R output
# Insert into imputed_female, imputed_raceG, etc.
# Update imputation_metadata table
```

**2.7 Unified Pipeline Orchestrator:**
```r
# scripts/imputation/run_full_imputation_pipeline.R
#
# Purpose: Single entry point for complete imputation pipeline
# Executes both geographic and sociodemographic imputation in sequence

library(reticulate)

cat("=" %R% rep("=", 70) %R% "\n")
cat("KIDSIGHTS IMPUTATION PIPELINE - UNIFIED ORCHESTRATOR\n")
cat("=" %R% rep("=", 70) %R% "\n\n")

# STAGE 1: Geographic Imputation (Python)
cat("STAGE 1: Geographic Imputation (PUMA, County, Census Tract)\n")
cat("-" %R% rep("-", 70) %R% "\n")

py_run_file("scripts/imputation/01_impute_geography.py")
cat("[OK] Geographic imputation complete\n\n")

# STAGE 2: Sociodemographic Imputation (R)
cat("STAGE 2: Sociodemographic Imputation (Sex, Race, Education, Income, Family Size)\n")
cat("-" %R% rep("-", 70) %R% "\n")

source("scripts/imputation/02_impute_sociodemographic.R")
cat("[OK] Sociodemographic imputation complete\n\n")

# FINAL SUMMARY
cat("=" %R% rep("=", 70) %R% "\n")
cat("PIPELINE COMPLETE - All imputations stored in database\n")
cat("=" %R% rep("=", 70) %R% "\n")
cat("\nUse python/imputation/helpers.py to retrieve completed datasets\n")
```

---

### Phase 3: Helper Function Updates

**Tasks:**

- [ ] **Task 3.1:** Update `python/imputation/helpers.py` - extend `get_completed_dataset()`
- [ ] **Task 3.2:** Update `python/imputation/helpers.py` - extend `get_all_imputations()`
- [ ] **Task 3.3:** Update `python/imputation/helpers.py` - extend `validate_imputations()`
- [ ] **Task 3.4:** Test Python helper functions with sociodem variables
- [ ] **Task 3.5:** Test R helper functions via reticulate (should work without changes)
- [ ] **Task 3.6:** VERIFICATION - Confirm all Phase 3 tasks complete, load Phase 4 tasks

**3.1 Python Helper Update:**
```python
def get_completed_dataset(imputation_m, variables=None, ...):
    if variables is None:
        variables = ['puma', 'county', 'census_tract',  # existing
                     'female', 'raceG', 'educ_mom', 'educ_a2',
                     'income', 'family_size', 'fplcat']  # NEW

    # Join imputed_female, imputed_raceG, etc. with LEFT JOIN + COALESCE pattern
    for var in variables:
        if var in ['puma', 'county', 'census_tract']:
            # Geography imputation (existing logic)
            pass
        else:
            # Sociodemographic imputation (NEW logic)
            query += f"""
            LEFT JOIN imputed_{var} ON base.study_id = imputed_{var}.study_id
                AND base.record_id = imputed_{var}.record_id
                AND imputed_{var}.imputation_m = {imputation_m}
            """
```

---

### Phase 4: Integration & Validation

**Tasks:**

- [ ] **Task 4.1:** Create `scripts/imputation/validate_sociodem_imputation.R`
- [ ] **Task 4.2:** Run validation checks (M=5, no overwrites, valid ranges)
- [ ] **Task 4.3:** Create `scripts/imputation/03_validate_all_imputations.py` (combined geography + sociodem)
- [ ] **Task 4.4:** Generate summary statistics for imputed variables
- [ ] **Task 4.5:** Compare observed vs imputed distributions
- [ ] **Task 4.6:** VERIFICATION - Confirm all Phase 4 tasks complete, load Phase 5 tasks

**4.1 Validation Script Checks:**
1. M=5 imputations exist for all 7 variables (female, raceG, educ_mom, educ_a2, income, family_size, fplcat)
2. No imputed values for records with observed data (selective storage verified)
3. Imputed values match original factor levels/ranges
4. FPL calculation correct for all M imputations
5. Imputation quality metrics (convergence, missing data patterns)
6. Only eligible records (eligible.x=TRUE) have imputations
7. Ineligible records excluded from imputation tables

---

### Phase 5: Documentation

**Tasks:**

- [ ] **Task 5.1:** Update `docs/imputation/IMPUTATION_PIPELINE.md` - Add CART imputation section
- [ ] **Task 5.2:** Update `docs/imputation/IMPUTATION_SETUP_COMPLETE.md` - Update storage metrics
- [ ] **Task 5.3:** Create `docs/imputation/CART_IMPUTATION_METHODOLOGY.md` - Statistical methods doc
- [ ] **Task 5.4:** Update `CLAUDE.md` - Update imputation pipeline description
- [ ] **Task 5.5:** Update `docs/QUICK_REFERENCE.md` - Add sociodem imputation commands
- [ ] **Task 5.6:** Update imputation specialist agent `.claude/agents/imputation-specialist.yaml`
- [ ] **Task 5.7:** VERIFICATION - Confirm all Phase 5 tasks complete, implementation finished

---

## Key Technical Decisions

### 1. CART + Random Forest Methods
**Decision:** Use CART for categorical/continuous, Random Forest for ordinal variables
**Rationale:**
- **CART** (female, raceG, income, family_size): Fast, interpretable, works well for binary/nominal/continuous
- **Random Forest** (educ_mom, educ_a2): Ensemble method, better for ordinal variables
  - Averages many trees → more stable predictions
  - Handles ordinality implicitly through aggregation
  - Ranger package provides fast C++ implementation
  - No proportional odds assumptions (unlike polr)
- Both methods are nonparametric (no distributional assumptions)

### 2. Eligible Records Only
**Decision:** Only impute records where `eligible.x = TRUE` (n=3,460, 70.6% of dataset)
**Rationale:**
- Ineligible records (failed screening criteria) are not part of analysis population
- Saves computational resources (30% fewer records to impute)
- Cleaner imputation models (focus on analysis-relevant population)
- Authenticity used as predictor (some eligible records are suspicious but retained)

### 3. Chained Imputation Approach
**Decision:** Run mice 5 times (once per geography imputation m), not once with m=5
**Rationale:**
- Creates within-imputation consistency between geography and sociodemographics
- Geography values from imputation m serve as FIXED auxiliary variables for sociodem imputation m
- Each imputation represents a jointly plausible "world" (geography + sociodem together)
- Proper MI framework: each imputation captures uncertainty in ALL variables consistently

### 4. Selective Storage
**Decision:** Only store records where original value was missing
**Rationale:** Consistency with geography imputation, 50%+ storage efficiency

### 5. FPL Derivation
**Decision:** Calculate after imputation, store as separate variable
**Rationale:** FPL is deterministic function of income + family_size, ensure consistency across imputations

### 6. Geography as Fixed Auxiliary
**Decision:** Include puma, county from imputation m as predictors (not re-imputed)
**Rationale:** Geography already imputed in Phase 1, use those values to inform sociodem imputation

### 7. Maternal + Secondary Caregiver Education
**Decision:** Impute `educ_mom` and `educ_a2` (not educ_a1)
**Rationale:**
- `educ_mom` = mother's education (specific parental variable)
- `educ_a2` = secondary caregiver education (father/partner when available)
- Captures **parental** education rather than respondent education
- More relevant for child outcomes research

### 8. Keep Collinear Predictors
**Decision:** Use `remove.collinear=FALSE` in mice() call
**Rationale:**
- By default, mice removes collinear predictors to avoid singularity issues
- However, collinear variables (e.g., mom_a1 and educ_mom, puma and county) provide useful information
- CART and RF can handle collinearity without problems (unlike regression-based methods)
- Keeping all predictors improves imputation quality

### 9. Relationship Variables as Predictors
**Decision:** Include `mom_a1` and `relation1` as auxiliary variables
**Rationale:**
- `mom_a1` indicates if Adult 1 is the mother (helps link educ_a1 to educ_mom)
- `relation1` captures relationship type (biological parent, grandparent, foster, etc.)
- Both variables may predict education/income patterns (e.g., grandparents vs. parents)
- 36% missing is acceptable for auxiliary variables in mice

### 10. Multiple Seeds
**Decision:** Use seed+m for each geography imputation (seed+1, seed+2, ..., seed+5)
**Rationale:** Different random draws for each imputation while maintaining reproducibility

---

## Integration with Geography Imputations

**Chained Approach (IMPLEMENTED):**
- Geography: M=5 imputations created first via probabilistic allocation (Phase 1, already complete)
- Sociodemographic: For each geography imputation m, run `mice(m=1)` with that geography as auxiliary
- Result: Imputation m has **internally consistent** geography and sociodem values

**How it Works:**
```
Imputation 1:
  - Person A: puma=00802 (from geography imputation 1) → sociodem imputed using puma=00802
  - Person B: puma=00901 (from geography imputation 1) → sociodem imputed using puma=00901

Imputation 2:
  - Person A: puma=00801 (from geography imputation 2) → sociodem imputed using puma=00801
  - Person B: puma=00901 (from geography imputation 2) → sociodem imputed using puma=00901
```

**Advantages:**
- Geography and sociodem **jointly plausible** within each imputation
- Geographic context improves sociodem imputation quality
- Proper MI variance estimation (all uncertainty captured)
- Maintains separate storage (3 geography + 7 sociodem = 10 tables)
- Can re-run sociodem imputation without re-running geography

---

## Timeline & Execution Order

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 1: Configuration & Schema | 7 tasks | 1 hour |
| Phase 2: CART Imputation Script | 10 tasks | 3-4 hours |
| Phase 3: Helper Function Updates | 6 tasks | 1.5 hours |
| Phase 4: Integration & Validation | 6 tasks | 1.5 hours |
| Phase 5: Documentation | 7 tasks | 1.5 hours |
| **TOTAL** | **36 tasks** | **8-10 hours** |

## Running the Complete Pipeline

**Single Command (Recommended):**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/run_full_imputation_pipeline.R
```

**This executes:**
1. Stage 1: Geographic imputation (Python via reticulate) - ~2-3 seconds
2. Stage 2: Sociodemographic imputation (R mice) - ~5-10 minutes
3. Total runtime: ~5-10 minutes for M=5 imputations

**Manual Two-Stage Execution (Alternative):**
```bash
# Stage 1: Geography
python scripts/imputation/01_impute_geography.py

# Stage 2: Sociodemographic
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/02_impute_sociodemographic.R
```

---

## Storage Estimates

### Current (Geography Only):
- 3 tables: `imputed_puma`, `imputed_county`, `imputed_census_tract`
- 25,483 rows total

### After CART Implementation:
- 10 tables total (3 geography + 7 sociodem)
- Estimated new rows:
  - `imputed_female`: 1,929 records × 5 imputations = 9,645 rows
  - `imputed_raceG`: 1,961 × 5 = 9,805 rows
  - `imputed_educ_a2`: 2,513 × 5 = 12,565 rows
  - `imputed_educ_a1`: 1,752 × 5 = 8,760 rows
  - `imputed_income`: 1,732 × 5 = 8,660 rows
  - `imputed_family_size`: 1,874 × 5 = 9,370 rows
  - `imputed_fplcat`: 1,893 × 5 = 9,465 rows
- **Sociodem total:** 68,270 rows
- **Grand total:** 25,483 + 68,270 = **93,753 rows** across 10 tables

---

---

## Summary: Variables Being Imputed vs Auxiliary Variables

### Variables Being Imputed (6 sociodemographic + 1 derived)

**THESE HAVE MISSING VALUES AND WILL BE IMPUTED USING CART:**

1. **female** - Child is female (Binary: TRUE/FALSE) - ~39% missing among eligible
   - Method: **CART**
2. **raceG** - Child's race/ethnicity grouped (7 categories) - ~40% missing among eligible
   - Method: **CART**
3. **educ_mom** - Maternal education (8 categories, ordinal) - ~55% missing among eligible
   - Method: **Random Forest (ranger)**
4. **educ_a2** - Adult 2 (secondary caregiver/father) education (8 categories, ordinal) - ~51% missing among eligible
   - Method: **Random Forest (ranger)**
5. **income** - Family income in dollars (continuous) - ~35% missing among eligible
   - Method: **CART**
6. **family_size** - Household size (count: 1-99) - ~38% missing among eligible
   - Method: **CART**
7. **fplcat** - Federal Poverty Level category (5 levels, derived from income + family_size)
   - Method: **Calculated post-imputation**

**Population:** Only eligible records (eligible.x=TRUE, n=3,460, 70.6% of dataset)
**Iterations:** Run mice 5 times (once per geography imputation m)

### Auxiliary Variables (8 predictors)

**THESE ARE COMPLETE (OR IMPUTED ALREADY) AND USED AS PREDICTORS ONLY:**

1. **puma** - Geographic PUMA from geography imputation m (varies by m)
2. **county** - County FIPS from geography imputation m (varies by m)
3. **source_project** - REDCap project ID (4 values: 7679, 7943, 7999, 8014)
4. **authentic.x** - Authenticity flag (TRUE/FALSE)
5. **age_in_days** - Child age in days (continuous, complete)
6. **consent_date** - Survey completion date (date, complete)
7. **mom_a1** - Is Adult 1 the mother? (TRUE/FALSE, 36% missing)
8. **relation1** - Adult 1's relationship to child (6 levels: bio/adoptive parent, foster, grandparent, step-parent, other relative, non-relative; 36% missing)

**Note:** `eligible.x` is used to FILTER the dataset (only eligible=TRUE are imputed), NOT as a predictor

### Key Design Points

✅ **Eligible Records Only:** Impute only where eligible.x=TRUE (n=3,460, 70.6%)
✅ **Chained Imputation:** Run `mice` 5 times (once per geography imputation m=1:5)
✅ **CART + Random Forest:** CART for categorical/continuous, RF for ordinal education
✅ **Geography as Auxiliary:** Use imputed geography from each m as fixed predictors
✅ **Within-Imputation Consistency:** Each m has jointly plausible geography + sociodem
✅ **Selective Storage:** Only store originally missing values (50%+ efficiency)
✅ **Derived FPL:** Calculate fplcat after imputing income and family_size
✅ **Parental Education:** Impute educ_mom (maternal) and educ_a2 (secondary caregiver)
✅ **Keep Collinear Predictors:** Use remove.collinear=FALSE (CART/RF handle collinearity)
✅ **Relationship Predictors:** Include mom_a1 and relation1 for better predictions

---

**Next Step:** Begin Phase 1 implementation (Configuration & Schema).
