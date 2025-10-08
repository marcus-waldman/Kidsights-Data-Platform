# Phase 1 Architecture Review - Childcare Imputation Implementation

**Date:** 2025-10-07
**Status:** Complete

---

## Current Pipeline Structure

### File Organization
```
scripts/imputation/ne25/
├── 01_impute_geography.py              # Stage 1: Python
├── 02_impute_sociodemographic.R        # Stage 2: R
├── 02b_insert_sociodem_imputations.py  # Stage 3: Python
└── run_full_imputation_pipeline.R      # Orchestrator
```

### Pipeline Flow

#### Stage 1: Geographic Imputation (Python)
- **Script:** `01_impute_geography.py`
- **Method:** Probabilistic allocation from afact probabilities
- **Variables:** puma, county, census_tract
- **Output:** Direct database insertion to `ne25_imputed_{variable}`
- **Records:** 878 PUMA, 1,054 county, 3,164 census tract imputations

#### Stage 2: Sociodemographic Imputation (R)
- **Script:** `02_impute_sociodemographic.R`
- **Method:** Chained imputation using `mice` package
- **Variables:** female, raceG, educ_mom, educ_a2, income, family_size, fplcat (derived)
- **Pattern:**
  - Loop over M imputations (M=5)
  - For each m: merge geography imputation m → run mice(m=1) → save Feather
- **Output:** Feather files to `{study_data_dir}/sociodem_feather/{variable}_m{m}.feather`
- **Key Functions:**
  - `load_base_data()` - Load from ne25_transformed
  - `merge_geography_imputation()` - Merge PUMA + county for imputation m
  - `calculate_fpl_category()` - Derive FPL from income + family_size
  - `save_imputation_feather()` - Save only originally missing values

#### Stage 3: Database Insertion (Python)
- **Script:** `02b_insert_sociodem_imputations.py`
- **Method:** Read Feather files → Insert to DuckDB
- **Pattern:**
  - Load all `{variable}_m*.feather` files
  - Combine across M imputations
  - Insert to `ne25_imputed_{variable}`
- **Key Functions:**
  - `load_feather_files()` - Load all M files for one variable
  - `insert_variable_imputations()` - Insert to database
  - `update_metadata()` - Update imputation_metadata table

---

## Database Schema

### Existing Imputation Tables
```
ne25_imputed_census_tract  (geography)
ne25_imputed_county        (geography)
ne25_imputed_puma          (geography)
ne25_imputed_female        (sociodem)
ne25_imputed_raceG         (sociodem)
ne25_imputed_educ_mom      (sociodem)
ne25_imputed_educ_a2       (sociodem)
ne25_imputed_income        (sociodem)
ne25_imputed_family_size   (sociodem)
ne25_imputed_fplcat        (sociodem - derived)
```

### Standard Table Schema
```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_{variable} (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  {variable} {DATA_TYPE} NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_{variable}_m
  ON ne25_imputed_{variable}(imputation_m);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_{variable}_study
  ON ne25_imputed_{variable}(study_id, pid);
```

**Storage Efficiency:** Only originally missing values are stored (not complete dataset)

---

## Integration Points for Childcare Stages

**Important:** Childcare imputation requires **3 sequential stages** due to conditional logic.

### New Stage 4: Childcare Stage 1 - Impute cc_receives_care (R)

**File:** `scripts/imputation/ne25/03a_impute_cc_receives_care.R`

**Dependencies:**
- Geography imputations (PUMA) from database
- Sociodemographic imputations (7 variables) from database
- Base variable: cc_receives_care from ne25_transformed

**Pattern:**
```r
# Load base data (eligible.x == TRUE only)
base_data <- load_base_data(db_path, eligible_only = TRUE)  # Includes cc_receives_care

# Loop over M imputations
for (m in 1:M) {
  # Load PUMA + 7 sociodem for imputation m
  puma_m <- load_puma_imputation(m)
  sociodem_m <- load_sociodem_imputations(m)

  dat_m <- merge_all(base_data, puma_m, sociodem_m)

  # Impute cc_receives_care ~ 9 auxiliary variables (CART)
  mice_result <- mice::mice(data = dat_m, m = 1, method = c(cc_receives_care = "cart"))

  completed_m <- mice::complete(mice_result, 1)

  # Save only originally missing (491 records)
  save_feather(completed_m, "cc_receives_care", m)
}
```

**Output:** `{study_data_dir}/childcare_feather/cc_receives_care_m{m}.feather`

---

### New Stage 5: Childcare Stage 2 - Conditional Imputation (R)

**File:** `scripts/imputation/ne25/03b_impute_cc_type_hours.R`

**Dependencies:**
- Completed cc_receives_care from Stage 4
- Geography imputations (PUMA) from database
- Sociodemographic imputations (7 variables) from database
- Base variables: cc_primary_type, cc_hours_per_week from ne25_transformed

**Key Feature:** **Only impute for records where cc_receives_care = "Yes"**

**Pattern:**
```r
for (m in 1:M) {
  # Load completed cc_receives_care from Stage 4
  cc_receives_m <- load_cc_receives_care_imputation(m)

  # Filter to ONLY records with cc_receives_care = "Yes"
  dat_receives_yes <- filter(cc_receives_m, cc_receives_care == "Yes")

  # Load base childcare type/hours for these records
  base_data <- load_childcare_type_hours(dat_receives_yes$pid)

  # Load auxiliary variables
  puma_m <- load_puma_imputation(m)
  sociodem_m <- load_sociodem_imputations(m)

  dat_m <- merge_all(base_data, puma_m, sociodem_m, cc_receives_m)

  # Impute both variables using mice
  mice_result <- mice::mice(
    data = dat_m,
    m = 1,
    method = c(
      cc_primary_type = "cart",      # Categorical (6 levels)
      cc_hours_per_week = "cart"     # Continuous
    )
  )

  completed_m <- mice::complete(mice_result, 1)

  # Cap hours at 168 (24×7)
  completed_m$cc_hours_per_week <- pmin(completed_m$cc_hours_per_week, 168)

  # Save only originally missing
  save_feather(completed_m, "cc_primary_type", m)
  save_feather(completed_m, "cc_hours_per_week", m)
}
```

**Output:**
- `{study_data_dir}/childcare_feather/cc_primary_type_m{m}.feather`
- `{study_data_dir}/childcare_feather/cc_hours_per_week_m{m}.feather`

---

### New Stage 6: Childcare Stage 3 - Derive Final Outcome (R)

**File:** `scripts/imputation/ne25/03c_derive_childcare_10hrs.R`

**Dependencies:**
- Completed cc_receives_care from Stage 4
- Completed cc_primary_type from Stage 5
- Completed cc_hours_per_week from Stage 5

**Pattern:**
```r
for (m in 1:M) {
  # Load all completed childcare variables for imputation m
  cc_receives_m <- load_cc_receives_care_imputation(m)
  cc_type_m <- load_cc_primary_type_imputation(m)
  cc_hours_m <- load_cc_hours_per_week_imputation(m)

  # Merge all completed variables
  dat_m <- merge_all_childcare(cc_receives_m, cc_type_m, cc_hours_m)

  # Derive final outcome
  dat_m <- dat_m %>%
    dplyr::mutate(
      childcare_10hrs_nonfamily = dplyr::case_when(
        cc_receives_care == "No" ~ FALSE,
        cc_hours_per_week >= 10 & cc_primary_type != "Relative care" ~ TRUE,
        TRUE ~ FALSE
      )
    )

  # Save derived variable (ALL eligible records, not just originally missing)
  save_feather(dat_m, "childcare_10hrs_nonfamily", m)
}
```

**Output:** `{study_data_dir}/childcare_feather/childcare_10hrs_nonfamily_m{m}.feather`

---

### New Stage 7: Childcare Database Insertion (Python)

**File:** `scripts/imputation/ne25/04_insert_childcare_imputations.py`

**Pattern:** Extends `02b_insert_sociodem_imputations.py` to handle 4 variables

**Output Tables:**
- `ne25_imputed_cc_receives_care`
- `ne25_imputed_cc_primary_type`
- `ne25_imputed_cc_hours_per_week`
- `ne25_imputed_childcare_10hrs_nonfamily`

### Updated Orchestration

**File:** `scripts/imputation/ne25/run_full_imputation_pipeline.R`

**New Structure (7 Stages):**
```r
# Stage 1: Geographic Imputation (Python)
reticulate::py_run_file("01_impute_geography.py")

# Stage 2: Sociodemographic Imputation (R)
source("02_impute_sociodemographic.R")

# Stage 3: Sociodem Database Insertion (Python)
reticulate::py_run_file("02b_insert_sociodem_imputations.py")

# Stage 4: Childcare Stage 1 - Impute cc_receives_care (R) - NEW
source("03a_impute_cc_receives_care.R")

# Stage 5: Childcare Stage 2 - Conditional imputation (R) - NEW
source("03b_impute_cc_type_hours.R")

# Stage 6: Childcare Stage 3 - Derive final outcome (R) - NEW
source("03c_derive_childcare_10hrs.R")

# Stage 7: Childcare Database Insertion (Python) - NEW
reticulate::py_run_file("04_insert_childcare_imputations.py")
```

**Final Result:**
- **14 imputation tables total**
  - 3 geography tables
  - 7 sociodem tables (includes derived fplcat)
  - 4 childcare tables (3 imputed + 1 derived)

---

## Key Design Decisions

### 1. Sequential Chained Imputation
- Each mice run uses **one completed dataset** from prior stages
- Geography → Sociodem → Childcare creates dependency chain
- M imputations created by repeating entire chain M times

### 2. CART Method for Childcare
- User requested `method = "cart"` for childcare variable
- Appropriate for binary/categorical outcome with nonlinear relationships
- Handles interactions between predictors automatically

### 3. Eligibility Filtering
- **Filter to eligible records only:** `eligible.x == TRUE` (3,460 of 3,908 records)
- Follows same pattern as sociodemographic imputation
- Only eligible participants receive childcare imputations

### 4. Auxiliary Variables
- **From geography:** PUMA only (not county/tract)
- **From base data:** authentic.x (100% complete for eligible records)
- **From sociodem:** All 7 variables (female, raceG, educ_mom, educ_a2, income, family_size, fplcat)
- Total: 9 auxiliary variables for childcare imputation

### 5. Storage Strategy
- Follow existing pattern: Only store originally missing values
- Reduces storage by ~50% compared to storing complete dataset
- Observed values remain in ne25_transformed table

---

## Configuration Requirements

### R Configuration (`config/imputation/imputation_config.yaml`)
Need to add childcare section:
```yaml
# Childcare imputation settings (CART via mice)
childcare:
  # Variable to impute
  variables:
    - childcare  # Child receives >=10 hours/week childcare from non-family

  # Auxiliary predictor variables (from geography, sociodem, and base data)
  auxiliary_variables:
    - puma           # Geographic PUMA from geography imputation m
    - authentic.x    # Authenticity flag (100% complete for eligible records)
    - female         # From sociodem imputation m
    - raceG          # From sociodem imputation m
    - educ_mom       # From sociodem imputation m
    - educ_a2        # From sociodem imputation m
    - income         # From sociodem imputation m
    - family_size    # From sociodem imputation m
    - fplcat         # From sociodem imputation m (derived)

  # Filter to eligible records only (eligible.x == TRUE, n=3,460)
  eligible_only: true

  # mice imputation method
  mice_method:
    childcare: "cart"  # CART for binary outcome

  # Maximum iterations for mice algorithm
  maxit: 5

  # Chained imputation (run mice once per completed dataset)
  chained: true
```

### SQL Schema (`sql/imputation/create_childcare_imputation_table.sql`)
```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_childcare (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  childcare BOOLEAN NOT NULL,  -- Assuming binary: TRUE = >=10hrs, FALSE = <10hrs
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_childcare_m
  ON ne25_imputed_childcare(imputation_m);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_childcare_study
  ON ne25_imputed_childcare(study_id, pid);
```

---

## Testing Strategy

### Baseline Test (Before Implementation)
- Run current pipeline end-to-end
- Verify 10 existing imputation tables populated
- Confirm M=5 imputations per variable
- Check row counts match expected

### Incremental Testing (During Implementation)
1. **After R script:** Verify Feather files created
2. **After Python script:** Verify database table created
3. **After orchestration:** Verify full pipeline runs
4. **Validation:** Confirm plausible imputations

---

## Next Steps

**Phase 1 Complete ✓**

**Phase 2: Data Discovery** - Identify childcare variable in NE25 dataset

Tasks:
- Search codebook for childcare variable
- Validate variable encoding (binary, hours, etc.)
- Calculate missing data percentage
- Document variable specification

---

**Review Complete:** 2025-10-07
