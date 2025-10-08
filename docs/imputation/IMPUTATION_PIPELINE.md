# Imputation Pipeline Architecture

**Last Updated:** October 2025 | **Version:** 2.1.0

## Overview

The Kidsights Data Platform implements a **9-stage sequential multiple imputation pipeline** that handles geographic, sociodemographic, childcare, and mental health uncertainty through variable-specific database storage. The system supports multiple independent studies (ne25, ia26, co27) with M=5 imputations per study, storing 21 variables per study in normalized tables for flexibility, transparency, and consistency across the imputation workflow.

## Design Philosophy

### Core Principles

1. **Normalized Storage:** Each imputed variable gets its own study-specific table: `{study_id}_imputed_{variable}`
2. **Pre-Computed Imputations:** All M imputations are generated during the 9-stage pipeline and stored in the database
3. **Sequential Chained Imputation:** Geography → Sociodem → Childcare → Mental Health ensures proper uncertainty propagation
4. **On-Demand Assembly:** Helper functions join imputed variable tables to construct completed datasets for analysis
5. **Internal Consistency:** Each imputation number (m=1 to M) maintains consistent values across all 21 variables
6. **Multi-Study Architecture:** Independent pipelines for each study with shared helper functions
7. **Storage Convention:** Only imputed/derived values stored (not observed values from base table)

### Why This Architecture?

**Modularity:**
- Re-impute individual variables without affecting others
- Different variables can have different numbers of imputations (M)
- Independent imputation workflows (geography → demographics → outcomes)

**Transparency:**
- Easy to audit specific variables across imputations
- Compare imputation distributions for quality control
- Track imputation metadata (method, date, parameters)

**Storage Efficiency:**
- Only imputed values stored, not full repeated datasets
- Observed data remains in base tables (ne25_derived, etc.)
- Reduced database size compared to wide-format storage

**Statistical Validity:**
- Proper propagation of uncertainty across multiple sources
- Geography uncertainty integrated with substantive imputation
- Compatible with standard MI combining rules (Rubin 1987)

---

## Database Schema

### Imputed Variable Tables

Each imputed variable follows this template:

```sql
CREATE TABLE imputed_{variable_name} (
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  {variable_name} {data_type},
  PRIMARY KEY (record_id, imputation_m),
  FOREIGN KEY (record_id) REFERENCES ne25_derived(record_id)
);

CREATE INDEX idx_imputed_{variable_name}_m ON imputed_{variable_name}(imputation_m);
```

### Geography Imputation Tables

**Geographic variables with allocation factor (afact) uncertainty:**

```sql
-- PUMA (Public Use Microdata Area)
CREATE TABLE imputed_puma (
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  puma VARCHAR NOT NULL,
  PRIMARY KEY (record_id, imputation_m)
);

-- County
CREATE TABLE imputed_county (
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  county VARCHAR NOT NULL,
  PRIMARY KEY (record_id, imputation_m)
);

-- Census Tract
CREATE TABLE imputed_census_tract (
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  census_tract VARCHAR NOT NULL,
  PRIMARY KEY (record_id, imputation_m)
);
```

**Notes:**
- Only records with geographic ambiguity (multiple possible assignments) are stored
- Records with deterministic geography use values from `ne25_derived` directly
- Sampling uses afact variables (allocation factors) as probabilities

### Sociodemographic Imputation Tables

**Study-specific sociodemographic variables (7 variables):**

```sql
-- Sociodemographic variables (Study: ne25)
CREATE TABLE ne25_imputed_female (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  female BOOLEAN,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_raceG (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  raceG VARCHAR,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Additional tables: educ_mom, educ_a2, income, family_size, fplcat
-- (Same structure, different variable names and types)
```

**Notes:**
- Imputed via MICE (Multivariate Imputation by Chained Equations)
- Uses geography imputations as predictors
- Only stores imputed values (observed values remain in base table)

### Childcare Imputation Tables

**Study-specific childcare variables (4 variables):**

```sql
-- Childcare variables (Study: ne25)
CREATE TABLE ne25_imputed_cc_receives_care (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_receives_care BOOLEAN,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_cc_primary_type (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_primary_type VARCHAR,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_cc_hours_per_week (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_hours_per_week DOUBLE,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_childcare_10hrs_nonfamily (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  childcare_10hrs_nonfamily BOOLEAN,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Notes:**
- 3-stage sequential: receives_care → type/hours → derived 10hrs indicator
- Conditional logic: type/hours only imputed when receives_care = "Yes"
- Data cleaning: hours capped at 168/week before imputation

### Mental Health & Parenting Imputation Tables

**Study-specific mental health and parenting variables (7 variables):**

```sql
-- PHQ-2 items (depression screening)
CREATE TABLE ne25_imputed_phq2_interest (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  phq2_interest INTEGER,  -- 0-3 scale
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_phq2_depressed (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  phq2_depressed INTEGER,  -- 0-3 scale
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- GAD-2 items (anxiety screening)
CREATE TABLE ne25_imputed_gad2_nervous (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  gad2_nervous INTEGER,  -- 0-3 scale
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_gad2_worry (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  gad2_worry INTEGER,  -- 0-3 scale
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Parenting self-efficacy
CREATE TABLE ne25_imputed_q1502 (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  q1502 INTEGER,  -- 0-3 scale (handling day-to-day demands)
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Derived positive screening indicators
CREATE TABLE ne25_imputed_phq2_positive (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  phq2_positive BOOLEAN,  -- TRUE if phq2_interest + phq2_depressed >= 3
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE ne25_imputed_gad2_positive (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  gad2_positive BOOLEAN,  -- TRUE if gad2_nervous + gad2_worry >= 3
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Notes:**
- Imputed via MICE with CART method (ordinal 0-3 scale)
- Uses geography + sociodem imputations as predictors
- **Storage convention:** Only stores imputed item values and derived screen values (not all eligible records)
- Positive screens derived from imputed items: PHQ-2+ (≥3), GAD-2+ (≥3)
- Production metrics (NE25, M=5):
  - Items: 545 rows total (phq2_interest: 85, phq2_depressed: 130, gad2_nervous: 125, gad2_worry: 95, q1502: 110)
  - Derived screens: 280 rows total (phq2_positive: 135, gad2_positive: 145)
  - Prevalence: PHQ-2+ 13.7%, GAD-2+ 17.0%

### Metadata Table

**Tracking imputation provenance and parameters:**

```sql
CREATE TABLE imputation_metadata (
  variable_name VARCHAR PRIMARY KEY,
  n_imputations INTEGER NOT NULL,
  imputation_method VARCHAR,
  predictors TEXT,  -- JSON array of predictor variables
  created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR,
  software_version VARCHAR,
  notes TEXT
);
```

**Example metadata entry:**
```sql
INSERT INTO imputation_metadata VALUES (
  'puma',
  20,
  'probabilistic_allocation',
  '["geocode_latitude", "geocode_longitude", "afact_puma"]',
  '2025-10-06',
  'impute_geography.py',
  '1.0.0',
  'Sampled from afact probabilities for records with multiple possible PUMAs'
);
```

---

## Imputation Workflow

### Phase 1: Geography Imputation (Priority)

**Goal:** Resolve geographic uncertainty using allocation factors

**Input Data:**
- `ne25_derived.geocode_latitude`, `geocode_longitude`
- Geographic crosswalk tables with afact variables
- Records where multiple geographies are possible

**Process:**
1. Identify records with geographic ambiguity (multiple PUMA/county candidates)
2. For each ambiguous record:
   - Retrieve all possible geography assignments + afact probabilities
   - Sample M geography values using afact as sampling weights
   - Store in `imputed_puma`, `imputed_county`, `imputed_census_tract`
3. Update `imputation_metadata` table

**Output:**
- M complete geography assignments for each ambiguous record
- Deterministic records use observed values from `ne25_derived`

### Phase 2: Substantive Imputation (Future)

**Goal:** Impute missing demographic/outcome variables

**Input Data:**
- Base data: `ne25_derived` + geography imputations
- Missing data patterns for target variables

**Process:**
1. For each imputation m = 1 to M:
   - Construct completed dataset with geography from imputation m
   - Run imputation model (MICE, Amelia, etc.) for target variable
   - Use realized geography as predictors
   - Store imputed values in variable-specific table
2. Update `imputation_metadata` table

**Key Design:**
- Geography imputations are **conditionally independent** (sampled from afact)
- Substantive imputations are **conditionally dependent** (use geography as predictors)
- This ensures within-imputation consistency

---

## Helper Functions

### Python: `get_completed_dataset()`

**Purpose:** Construct a completed dataset for a specific imputation

```python
from python.db.connection import DatabaseManager

def get_completed_dataset(imputation_m, variables=None, include_observed=True):
    """
    Construct a completed dataset for imputation m

    Parameters
    ----------
    imputation_m : int
        Which imputation to retrieve (1 to M)
    variables : list of str, optional
        Imputed variables to include. If None, includes all available.
    include_observed : bool, default True
        Whether to include base observed data from ne25_derived

    Returns
    -------
    pandas.DataFrame
        Completed dataset with observed + imputed values

    Examples
    --------
    # Get imputation 5 with geography only
    df = get_completed_dataset(5, variables=['puma', 'county'])

    # Get imputation 10 with all imputed variables
    df = get_completed_dataset(10)
    """
    db = DatabaseManager()

    # Start with base data (if requested)
    if include_observed:
        base = db.query_to_dataframe("SELECT * FROM ne25_derived")
    else:
        base = db.query_to_dataframe("SELECT record_id FROM ne25_derived")

    # Get list of available imputed variables
    if variables is None:
        meta = db.query_to_dataframe("SELECT variable_name FROM imputation_metadata")
        variables = meta['variable_name'].tolist()

    # Join each imputed variable table
    for var in variables:
        query = f"""
            SELECT record_id, {var}
            FROM imputed_{var}
            WHERE imputation_m = {imputation_m}
        """
        imputed = db.query_to_dataframe(query)

        # Left join: only ambiguous records are in imputed tables
        base = base.merge(imputed, on='record_id', how='left', suffixes=('', '_imputed'))

        # Coalesce: use imputed value if available, else observed
        if f'{var}_imputed' in base.columns:
            base[var] = base[f'{var}_imputed'].fillna(base[var])
            base = base.drop(columns=[f'{var}_imputed'])

    return base
```

### Python: `get_all_imputations()`

**Purpose:** Retrieve all M imputations in long format

```python
def get_all_imputations(variables=None):
    """
    Get all imputations for specified variables in long format

    Parameters
    ----------
    variables : list of str, optional
        Imputed variables to include. If None, includes all.

    Returns
    -------
    pandas.DataFrame
        Long-format data with imputation_m column

    Examples
    --------
    # Get all geography imputations
    df_long = get_all_imputations(['puma', 'county'])

    # Analyze across imputations
    df_long.groupby('imputation_m')['puma'].value_counts()
    """
    db = DatabaseManager()

    # Get available imputations
    if variables is None:
        meta = db.query_to_dataframe("SELECT variable_name FROM imputation_metadata")
        variables = meta['variable_name'].tolist()

    # Start with base data
    base = db.query_to_dataframe("SELECT * FROM ne25_derived")

    # Get max M across all variables
    meta = db.query_to_dataframe("""
        SELECT MAX(n_imputations) as max_m FROM imputation_metadata
    """)
    max_m = meta['max_m'].iloc[0]

    # Stack all imputations
    all_imputations = []
    for m in range(1, max_m + 1):
        df_m = get_completed_dataset(m, variables=variables)
        df_m['imputation_m'] = m
        all_imputations.append(df_m)

    return pd.concat(all_imputations, ignore_index=True)
```

### R: `get_completed_dataset()`

**Purpose:** Construct completed dataset in R for survey analysis

```r
library(dplyr)
library(DBI)

get_completed_dataset <- function(imputation_m, variables = NULL, db_path = NULL) {
  #' Get Completed Dataset for Imputation m
  #'
  #' @param imputation_m Integer, which imputation to retrieve (1 to M)
  #' @param variables Character vector of imputed variable names. NULL = all.
  #' @param db_path Path to DuckDB database. NULL = default location.
  #'
  #' @return data.frame with observed + imputed values
  #'
  #' @examples
  #' # Get imputation 5 with geography
  #' df <- get_completed_dataset(5, variables = c("puma", "county"))
  #'
  #' # Get all imputed variables for imputation 10
  #' df <- get_completed_dataset(10)

  if (is.null(db_path)) {
    db_path <- "data/duckdb/kidsights_local.duckdb"
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Get base data
  base <- dplyr::tbl(con, "ne25_derived") %>% dplyr::collect()

  # Get available imputed variables
  if (is.null(variables)) {
    meta <- dplyr::tbl(con, "imputation_metadata") %>% dplyr::collect()
    variables <- meta$variable_name
  }

  # Join each imputed variable
  for (var in variables) {
    query <- glue::glue("
      SELECT record_id, {var}
      FROM imputed_{var}
      WHERE imputation_m = {imputation_m}
    ")

    imputed <- DBI::dbGetQuery(con, query)

    # Left join and coalesce
    base <- base %>%
      dplyr::left_join(imputed, by = "record_id", suffix = c("", "_imputed")) %>%
      dplyr::mutate(
        !!var := dplyr::coalesce(.data[[paste0(var, "_imputed")]], .data[[var]])
      ) %>%
      dplyr::select(-dplyr::ends_with("_imputed"))
  }

  return(base)
}
```

### R: `get_imputation_list()`

**Purpose:** Get imputations as a list for `survey::withReplicates()` or `mice::pool()`

```r
get_imputation_list <- function(variables = NULL, db_path = NULL, max_m = NULL) {
  #' Get All Imputations as a List
  #'
  #' @param variables Character vector of imputed variables. NULL = all.
  #' @param db_path Path to DuckDB database. NULL = default.
  #' @param max_m Maximum imputation number. NULL = auto-detect.
  #'
  #' @return List of M data.frames, each a completed dataset
  #'
  #' @examples
  #' # Get list of 20 imputed datasets
  #' imp_list <- get_imputation_list()
  #'
  #' # Analyze with survey package
  #' results <- lapply(imp_list, function(df) {
  #'   svydesign(..., data = df) %>% svymean(~outcome)
  #' })
  #' mitools::MIcombine(results)

  if (is.null(db_path)) {
    db_path <- "data/duckdb/kidsights_local.duckdb"
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Auto-detect max M
  if (is.null(max_m)) {
    meta <- DBI::dbGetQuery(con, "SELECT MAX(n_imputations) as max_m FROM imputation_metadata")
    max_m <- meta$max_m[1]
  }

  # Generate list of completed datasets
  imp_list <- lapply(1:max_m, function(m) {
    get_completed_dataset(m, variables = variables, db_path = db_path)
  })

  return(imp_list)
}
```

---

## Usage Examples

### Example 1: Geography Imputation Analysis

**Python: Compare PUMA distributions across imputations**

```python
from python.imputation.helpers import get_all_imputations
import pandas as pd

# Get all geography imputations
df = get_all_imputations(variables=['puma', 'county'])

# Compare PUMA distributions
puma_dist = df.groupby(['imputation_m', 'puma']).size().unstack(fill_value=0)
print(puma_dist)

# Check variance in assignments for specific record
record_imputations = df[df['record_id'] == 123][['imputation_m', 'puma', 'county']]
print(record_imputations)
```

**R: Survey analysis with imputed geography**

```r
library(survey)
library(mitools)

# Get list of 20 imputed datasets
imp_list <- get_imputation_list(variables = c("puma", "county"))

# Analyze each imputation
results <- lapply(imp_list, function(df) {
  design <- svydesign(ids = ~1, weights = ~weight, data = df)
  svymean(~factor(puma), design)
})

# Combine using Rubin's rules
combined <- mitools::MIcombine(results)
summary(combined)
```

### Example 2: Quality Control

**Check imputation metadata:**

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()
metadata = db.query_to_dataframe("SELECT * FROM imputation_metadata")
print(metadata)

# Output:
# variable_name  n_imputations  imputation_method         created_date
# puma           20             probabilistic_allocation  2025-10-06
# county         20             probabilistic_allocation  2025-10-06
```

**Validate imputation counts:**

```sql
-- Check that all records have M imputations
SELECT
  variable_name,
  n_imputations as expected,
  (SELECT COUNT(DISTINCT imputation_m) FROM imputed_puma) as actual_puma,
  (SELECT COUNT(DISTINCT imputation_m) FROM imputed_county) as actual_county
FROM imputation_metadata;
```

---

## Implementation Status

### Phase 1: Geography Imputation ✅ COMPLETE

- [x] Design database schema
- [x] Document architecture
- [x] Implement `01_impute_geography.py` script
- [x] Create helper functions (Python + R)
- [x] Generate M=5 geography imputations
- [x] Validate against afact distributions

### Phase 2: Helper Function Integration ✅ COMPLETE

- [x] Add to `python/imputation/helpers.py` module
- [x] Add to `R/imputation/helpers.R` module
- [x] Write validation functions
- [x] Update CLAUDE.md with usage examples

### Phase 3: Sociodemographic Imputation ✅ COMPLETE

- [x] Identify variables requiring imputation (7 variables)
- [x] Design MICE imputation models with geography predictors
- [x] Implement `02_impute_sociodemographic.R` script
- [x] Implement `02b_insert_sociodem_imputations.py` script
- [x] Validate against known distributions

### Phase 4: Childcare Imputation ✅ COMPLETE

- [x] Design 3-stage sequential architecture
- [x] Implement Stage 1: `03a_impute_cc_receives_care.R`
- [x] Implement Stage 2: `03b_impute_cc_type_hours.R`
- [x] Implement Stage 3: `03c_derive_childcare_10hrs.R`
- [x] Implement database insertion: `04_insert_childcare_imputations.py`
- [x] Data quality safeguards (NULL filtering, outlier cleaning)
- [x] Statistical validation and diagnostics

### Phase 5: Multi-Study Architecture ✅ COMPLETE

- [x] Refactor to study-specific tables
- [x] Create automated setup script (`create_new_study.py`)
- [x] Update helper functions with `study_id` parameter
- [x] Document onboarding process (ADDING_NEW_STUDY.md)

### Current Production Status (October 2025)

**✅ Production Ready:**
- 7-stage sequential pipeline operational
- 14 variables imputed per study (3 geography + 7 sociodem + 4 childcare)
- M=5 imputations, 76,636 rows for study ne25
- 2-minute runtime, 0% error rate
- Complete validation and diagnostics
- Multi-study support ready (ne25, ia26, co27)

**📖 Documentation:**
- [USING_IMPUTATION_AGENT.md](USING_IMPUTATION_AGENT.md) - User guide
- [CHILDCARE_IMPUTATION_IMPLEMENTATION.md](CHILDCARE_IMPUTATION_IMPLEMENTATION.md) - Implementation plan
- [PIPELINE_TEST_REPORT.md](PIPELINE_TEST_REPORT.md) - Validation results
- [ADDING_NEW_STUDY.md](ADDING_NEW_STUDY.md) - Multi-study onboarding

---

## Technical Notes

### Storage Considerations

**Why not store full M datasets?**
- 3,908 records × 500 variables × 20 imputations = 39 million cells
- Feather files: ~100 MB per imputation = 2 GB total
- Database storage: Only imputed values (~5-10% of cells) = 200 MB

**Why not store probabilities instead of realized values?**
- Imputation models need **fixed** predictors across iterations
- Geography in imputation #5 must be consistent for all downstream imputations
- Storing realized values ensures internal consistency

### Performance Considerations

**Query optimization:**
- Indexes on `imputation_m` for fast filtering
- Primary keys on `(record_id, imputation_m)` for fast joins
- DuckDB's columnar storage minimizes I/O for variable subsets

**Typical query times (estimated):**
- Single imputation: ~50ms (3,908 records × 10 variables)
- All M=20 imputations: ~500ms
- Metadata lookup: <10ms

---

## References

**Multiple Imputation Theory:**
- Rubin, D. B. (1987). *Multiple Imputation for Nonresponse in Surveys*. Wiley.
- Van Buuren, S. (2018). *Flexible Imputation of Missing Data* (2nd ed.). CRC Press.

**Geographic Allocation Factors:**
- U.S. Census Bureau. (2020). *GEOCORR 2022: Geographic Correspondence Engine*.
- IPUMS USA. (2024). *Allocation Flags and Editing Documentation*.

**Software:**
- Python: `mice`, `sklearn.impute`, `statsmodels`
- R: `mice`, `Amelia`, `missForest`, `survey::withReplicates()`

---

**Status:** ✅ Production Ready | **Last Updated:** October 2025 | **Version:** 2.0.0
