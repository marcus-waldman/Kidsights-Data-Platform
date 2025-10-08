# Adding Imputation Stages to the Pipeline

**Last Updated:** October 2025 | **Version:** 1.0.0

This document provides standardized patterns for adding new imputation stages to the Kidsights imputation pipeline. These patterns were identified through analysis of existing stage implementations (sociodemographic, childcare, mental health, child ACEs).

---

## Table of Contents

1. [5-Phase Implementation Pattern](#5-phase-implementation-pattern)
2. [Technical Patterns](#technical-patterns)
3. [Implementation Checklist](#implementation-checklist)
4. [Detailed Phase Instructions](#detailed-phase-instructions)
5. [Common Pitfalls to Avoid](#common-pitfalls-to-avoid)
6. [Testing Guidelines](#testing-guidelines)

---

## 5-Phase Implementation Pattern

Every new imputation stage follows this consistent workflow:

### Phase 1: R Imputation Script
**File:** `scripts/imputation/{study_id}/XX_impute_{domain}.R`

- **Naming Convention:** Sequential numbered prefix (e.g., `06_impute_child_aces.R`)
- **Structure:** Configuration → Helper Functions → Main Loop → Output
- **Duration:** Most complex phase, typically 50% of implementation time

### Phase 2: Python Database Insertion
**File:** `scripts/imputation/{study_id}/XXb_insert_{domain}.py`

- **Naming Convention:** Same number + `b` suffix (e.g., `06b_insert_child_aces.py`)
- **Structure:** Load → Create Tables → Insert → Validate → Update Metadata
- **Duration:** 25% of implementation time

### Phase 3: Pipeline Integration
**File:** `scripts/imputation/{study_id}/run_full_imputation_pipeline.R`

- Add stage section with timing and error handling
- Execute R script via `source()`
- Execute Python script via `reticulate::py_run_file()`
- **Duration:** 10% of implementation time

### Phase 4: Python Helper Functions
**File:** `python/imputation/helpers.py`

- Add domain-specific getter function (e.g., `get_child_aces_imputations()`)
- Update `get_complete_dataset()` with optional parameter
- Add validation logic to `validate_imputations()`
- **Duration:** 10% of implementation time

### Phase 5: Documentation Updates
**Files:** `CLAUDE.md`, `docs/architecture/PIPELINE_OVERVIEW.md`, `docs/QUICK_REFERENCE.md`

- Update metrics (variables, stages, execution time, rows)
- Add usage examples
- Update status sections
- **Duration:** 5% of implementation time

---

## Technical Patterns

### 1. Chained Imputation Loop (CRITICAL)

**Purpose:** Each imputation uses auxiliary variables from the same imputation number to maintain consistency across multiply-imputed datasets.

```r
# Load base data ONCE before loop
base_data <- load_base_{domain}_data(db_path, eligible_only = TRUE)

# LOOP over imputations
for (m in 1:M) {
  cat(sprintf("\nIMPUTATION m=%d/%d\n", m, M))

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load sociodem imputations m
  sociodem_m <- load_sociodem_imputations(db_path, m)

  # Step 3: Load mental health imputations m (if needed)
  mh_m <- load_mental_health_imputations(db_path, m)

  # Step 4: Merge with base data
  dat_m <- merge_imputed_data(base_data, puma_m, sociodem_m, mh_m, db_path)

  # Step 5: Configure MICE
  # - Set predictor matrix (which variables predict which)
  # - Set method vector (cart, rf, pmm, etc.)

  # Step 6: Run MICE with unique seed
  set.seed(seed + m)  # CRITICAL: seed + m, not just seed
  mice_result <- mice::mice(
    data = dat_mice,
    m = 1,  # Always 1 per loop iteration
    method = method_vector,
    predictorMatrix = predictor_matrix,
    maxit = 5,
    remove.collinear = FALSE,
    printFlag = FALSE
  )

  # Step 7: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 8: Save only imputed values to Feather
  for (var in variables_to_impute) {
    save_feather(completed_m, base_data, m, output_dir, var)
  }

  # Step 9: Derive and save composite scores (if applicable)
  derive_composite_scores(completed_m, base_data, m, output_dir)
}
```

**Key Principles:**
- Load base data once, auxiliary data M times
- Use `seed + m` for reproducibility
- Only save imputed values (space-efficient design)
- Each loop iteration uses `m = 1` (single imputation per iteration)

---

### 2. Storage Convention (Space-Efficient)

**Critical Rule:** Only store records that needed imputation, not observed values.

```r
save_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  # Identify records that were originally missing
  originally_missing <- is.na(original_data[[variable_name]])

  # Extract only those records from completed data
  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", variable_name)]
  imputed_records$imputation_m <- m

  # DEFENSIVE FILTERING: Remove records where imputation failed
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\n", n_null_filtered))
  }

  # Reorder columns: study_id, pid, record_id, imputation_m, [variable]
  imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", variable_name)]

  # Save to Feather file
  output_path <- file.path(output_dir, sprintf("%s_m%d.feather", variable_name, m))
  arrow::write_feather(imputed_records, output_path)

  cat(sprintf("  [OK] %s: %d values -> %s\n", variable_name, nrow(imputed_records), basename(output_path)))
}
```

**Why This Matters:**
- Reduces storage by ~90% (only missing values stored)
- Prevents observed values from being overwritten
- Maintains single source of truth (base table for observed, imputed tables for missing)

---

### 3. Defensive Filtering (EVERYWHERE)

**Rule:** Always filter to eligible AND authentic records.

```r
# In R scripts
query <- "SELECT ... FROM ne25_transformed"
query <- paste0(query, "\n    WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE")

# When loading auxiliary variables
geo_observed <- DBI::dbGetQuery(con, "
  SELECT ...
  FROM ne25_transformed
  WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE
")
```

**Python equivalent:**
```python
base_data = db.execute_query("""
    SELECT ...
    FROM ne25_transformed
    WHERE eligible.x = TRUE AND authentic.x = TRUE
""")
```

---

### 4. Table Naming Convention

**Pattern:** `{study_id}_imputed_{variable}`

**Examples:**
- `ne25_imputed_child_ace_total`
- `ne25_imputed_phq2_positive`
- `ne25_imputed_puma`

**Table Structure:**
```sql
CREATE TABLE {study_id}_imputed_{variable} (
    study_id VARCHAR NOT NULL,
    pid INTEGER NOT NULL,
    record_id INTEGER NOT NULL,
    imputation_m INTEGER NOT NULL,
    {variable} {DATA_TYPE} NOT NULL,
    PRIMARY KEY (study_id, pid, record_id, imputation_m)
)
```

**Indexes (Required):**
```sql
CREATE INDEX IF NOT EXISTS idx_{study_id}_imputed_{variable}_pid_record
ON {study_id}_imputed_{variable} (pid, record_id);

CREATE INDEX IF NOT EXISTS idx_{study_id}_imputed_{variable}_imputation
ON {study_id}_imputed_{variable} (imputation_m);
```

---

### 5. Unique Seeds for Reproducibility

**Always use `seed + m`, never just `seed`:**

```r
# ✅ CORRECT
for (m in 1:M) {
  set.seed(seed + m)
  mice_result <- mice::mice(...)
}

# ❌ INCORRECT (all imputations identical)
for (m in 1:M) {
  set.seed(seed)
  mice_result <- mice::mice(...)
}
```

---

### 6. Derived Variables Pattern

**For composite scores (e.g., PHQ-2 total, ACE total), only save if ANY component was imputed:**

```r
derive_composite_scores <- function(completed_data, base_data, m, output_dir) {
  # Calculate composite score
  completed_data$composite_score <- rowSums(completed_data[, component_items], na.rm = FALSE)

  # Identify records where ANY component item was originally missing
  any_component_missing <- rowSums(is.na(base_data[, component_items])) > 0

  records_needing_derivation <- base_data[any_component_missing, c("pid", "record_id")]

  if (nrow(records_needing_derivation) > 0) {
    records_needing_derivation$needs_derivation <- TRUE

    # Merge with completed data
    derived_data <- dplyr::left_join(
      completed_data[, c("study_id", "pid", "record_id", "composite_score")],
      records_needing_derivation,
      by = c("pid", "record_id")
    )

    # Filter to only records that needed derivation
    derived_data <- derived_data[!is.na(derived_data$needs_derivation), ]
    derived_data <- derived_data[, c("study_id", "pid", "record_id", "composite_score")]

    # DEFENSIVE FILTERING: Remove NULL values
    derived_data <- derived_data[!is.na(derived_data$composite_score), ]

    if (nrow(derived_data) > 0) {
      derived_data$imputation_m <- m
      derived_data <- derived_data[, c("study_id", "pid", "record_id", "imputation_m", "composite_score")]

      output_path <- file.path(output_dir, sprintf("composite_score_m%d.feather", m))
      arrow::write_feather(derived_data, output_path)
    }
  }
}
```

---

### 7. Configuration System Integration

**All imputation stages must integrate with the centralized configuration system:**

**R Configuration (via reticulate):**
```r
# Source configuration
source("R/imputation/config.R")

# Load configuration
study_id <- "ne25"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

# Access configuration values
M <- config$n_imputations
seed <- config$random_seed
db_path <- config$database$db_path
data_dir <- study_config$data_dir
```

**Python Configuration:**
```python
from python.imputation.config import get_study_config, get_table_prefix

# Load configuration
study_config = get_study_config(study_id)
n_imputations = study_config['n_imputations']
table_prefix = get_table_prefix(study_id)
```

**Configuration Files:**
- **Main config:** `config/imputation/imputation_config.yaml`
- **Study-specific:** `config/imputation/{study_id}_config.yaml`

---

### 8. Metadata Tracking (imputation_metadata table)

**Every Python insertion script MUST update the imputation_metadata table:**

```python
def update_metadata(
    db: DatabaseManager,
    study_id: str,
    variable_name: str,
    n_imputations: int,
    n_records: int,
    imputation_method: str,
    variable_type: str = "imputed"
):
    """Update or insert metadata for imputed/derived variable"""
    with db.get_connection() as conn:
        # Check if metadata exists
        exists = conn.execute(f"""
            SELECT COUNT(*) as count
            FROM imputation_metadata
            WHERE study_id = '{study_id}' AND variable_name = '{variable_name}'
        """).df()

        notes = f"{'Derived' if variable_type == 'derived' else 'Imputed'} via {domain} pipeline ({n_records} total records)"

        if exists['count'].iloc[0] > 0:
            # Update existing
            conn.execute(f"""
                UPDATE imputation_metadata
                SET n_imputations = {n_imputations},
                    imputation_method = '{imputation_method}',
                    created_date = CURRENT_TIMESTAMP,
                    created_by = 'XXb_insert_{domain}.py',
                    notes = '{notes}'
                WHERE study_id = '{study_id}' AND variable_name = '{variable_name}'
            """)
        else:
            # Insert new
            conn.execute(f"""
                INSERT INTO imputation_metadata
                (study_id, variable_name, n_imputations, imputation_method, created_by, notes)
                VALUES (
                    '{study_id}',
                    '{variable_name}',
                    {n_imputations},
                    '{imputation_method}',
                    'XXb_insert_{domain}.py',
                    '{notes}'
                )
            """)

# Call after each variable insertion
for var in variables:
    n_rows = insert_variable_imputations(db, var, imputations, study_id)
    update_metadata(db, study_id, var, n_imputations, n_rows, method, variable_type)
```

**Metadata Table Schema:**
```sql
CREATE TABLE IF NOT EXISTS imputation_metadata (
    study_id VARCHAR NOT NULL,
    variable_name VARCHAR NOT NULL,
    n_imputations INTEGER NOT NULL,
    imputation_method VARCHAR,
    predictors VARCHAR,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR,
    notes VARCHAR,
    PRIMARY KEY (study_id, variable_name)
);
```

---

### 9. Missing Data Handling (CRITICAL)

**Always apply `recode_missing()` BEFORE imputation if sentinel values present:**

```r
# Load base data
base_data <- load_base_data(db_path)

# Apply recode_missing to variables with sentinel values
# Common missing codes: 99 (Prefer not to answer), 9 (Don't know), 7 (Refused)
for (var in variables_to_impute) {
  if (var %in% names(base_data)) {
    base_data[[var]] <- recode_missing(base_data[[var]], missing_codes = c(99, 9, 7))
  }
}
```

**Why This Matters:**
- Prevents sentinel values (99, 9) from contaminating imputed values
- Ensures mice treats these as genuinely missing data
- See `docs/guides/MISSING_DATA_GUIDE.md` for complete guidance

---

## Implementation Checklist

### R Script Requirements

**Configuration & Setup:**
- [ ] Source configuration: `source("R/imputation/config.R")`
- [ ] Load required packages: duckdb, dplyr, mice, arrow
- [ ] Set study_id and load study config
- [ ] Define output directory

**Helper Functions:**
- [ ] `load_base_{domain}_data()` - Load base data with defensive filtering
- [ ] `load_puma_imputation()` - Load PUMA for imputation m
- [ ] `load_{previous_stage}_imputations()` - Load auxiliary variables for imputation m
- [ ] `merge_imputed_data()` - Merge base + auxiliary, fill observed values from base
- [ ] `save_{domain}_feather()` - Save only imputed values to Feather
- [ ] `derive_{composite}_scores()` - Derive and save composite scores (if applicable)

**Main Imputation Loop:**
- [ ] Load base data once before loop
- [ ] Loop over imputations (for m in 1:M)
- [ ] Load auxiliary variables for imputation m
- [ ] Merge data
- [ ] Configure MICE (predictor matrix + method vector)
- [ ] Run MICE with `set.seed(seed + m)`
- [ ] Extract completed dataset
- [ ] Save imputed values to Feather files
- [ ] Derive composite scores (if applicable)

**Missing Data Handling:**
- [ ] Apply `recode_missing()` if sentinel values present
- [ ] Use `na.rm = FALSE` for composite scores (conservative approach)

**Output & Documentation:**
- [ ] Print configuration summary
- [ ] Print missing data summary
- [ ] Print mice configuration
- [ ] Print completion summary with next steps

---

### Python Script Requirements

**Structure:**
- [ ] `load_feather_files()` - Load Feather files with validation
- [ ] `create_{domain}_tables()` - Create tables with proper data types
- [ ] `insert_variable_imputations()` - Insert data with NULL filtering
- [ ] `validate_{domain}_tables()` - Validate row counts, ranges, NULLs, duplicates
- [ ] `main()` - Orchestrate workflow

**Table Creation:**
- [ ] Use `{study_id}_imputed_{variable}` naming convention
- [ ] Define primary key: `(study_id, pid, record_id, imputation_m)`
- [ ] Use correct data types (INTEGER for binary/counts, DOUBLE for continuous, BOOLEAN for flags)
- [ ] Create indexes on (pid, record_id) and (imputation_m)

**Data Insertion:**
- [ ] Defensive NULL filtering before insert (remove rows with NULL values)
- [ ] Validate data types match table schema
- [ ] Validate value ranges (e.g., 0-3 for Likert, 0/1 for binary)
- [ ] Check for duplicates on (pid, record_id, imputation_m)

**Validation:**
- [ ] Check row counts per imputation
- [ ] Check for NULL values (should be 0)
- [ ] Check value ranges for specific variable types
- [ ] Check for duplicate primary keys
- [ ] Calculate and report prevalence/distribution statistics

---

### Pipeline Integration Requirements

**File:** `scripts/imputation/{study_id}/run_full_imputation_pipeline.R`

```r
# =============================================================================
# STAGE XX: [Domain Name]
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE XX: Impute [Domain Name]\n")
cat(strrep("=", 60), "\n")

start_time <- Sys.time()

# R Imputation Script
tryCatch({
  source("scripts/imputation/ne25/XX_impute_{domain}.R")
  cat("\n[OK] R imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Stage XX R script failed:\n")
  cat(conditionMessage(e), "\n")
  stop("Pipeline halted at Stage XX (R imputation)")
})

# Python Database Insertion
tryCatch({
  reticulate::py_run_file("scripts/imputation/ne25/XXb_insert_{domain}.py")
  cat("\n[OK] Database insertion complete\n")
}, error = function(e) {
  cat("\n[ERROR] Stage XX Python script failed:\n")
  cat(conditionMessage(e), "\n")
  stop("Pipeline halted at Stage XX (database insertion)")
})

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))
cat(sprintf("\n[OK] Stage XX complete (%.1f seconds)\n", elapsed))
```

**Checklist:**
- [ ] Add stage section with sequential numbering
- [ ] Execute R script via `source()`
- [ ] Execute Python script via `reticulate::py_run_file()`
- [ ] Track execution time
- [ ] Error handling with informative messages
- [ ] Status messages at each step

---

### Helper Functions Requirements

**File:** `python/imputation/helpers.py`

**1. Add Domain-Specific Getter Function:**

```python
def get_{domain}_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1,
    include_base_data: bool = False
) -> pd.DataFrame:
    """
    Get {domain} variables (N variables: X items + Y derived)

    Parameters
    ----------
    study_id : str
        Study identifier (default: "ne25")
    imputation_number : int
        Which imputation to retrieve (1 to M, default: 1)
    include_base_data : bool
        If True, includes all base data columns (default: False)

    Returns
    -------
    pd.DataFrame
        DataFrame with {domain} variables for specified imputation

    Examples
    --------
    >>> # Get {domain} variables for imputation 1
    >>> data = get_{domain}_imputations(study_id="ne25", imputation_number=1)
    >>>
    >>> # Get with base data
    >>> data = get_{domain}_imputations(imputation_number=1, include_base_data=True)
    """
    {domain}_vars = [
        'variable_1',
        'variable_2',
        # ... list all variables
    ]

    return get_completed_dataset(
        imputation_m=imputation_number,
        variables={domain}_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=include_base_data
    )
```

**2. Update `get_complete_dataset()` with Optional Parameter:**

```python
def get_complete_dataset(
    study_id: str = "ne25",
    imputation_number: int = 1,
    include_base_data: bool = False,
    include_mental_health: bool = True,
    include_child_aces: bool = True,
    include_{domain}: bool = True  # NEW PARAMETER
) -> pd.DataFrame:
    """Get complete imputed dataset..."""

    all_imputed_vars = [...]  # Geography, sociodem, childcare

    if include_mental_health:
        all_imputed_vars.extend([...])

    if include_child_aces:
        all_imputed_vars.extend([...])

    if include_{domain}:
        all_imputed_vars.extend([...])  # NEW SECTION

    return get_completed_dataset(...)
```

**3. Add Validation to `validate_imputations()`:**

```python
# In validate_imputations() function

# {Domain} validation
elif var in ['{domain}_item_1', '{domain}_item_2', ...]:
    # Example: Binary 0/1 validation
    bool_check = conn.execute(f"""
        SELECT COUNT(*) as count
        FROM {table_name}
        WHERE study_id = '{study_id}' AND {var} NOT IN (0, 1)
    """).df()

    if bool_check['count'].iloc[0] > 0:
        print(f"  [WARN] {var}: {bool_check['count'].iloc[0]} non-binary values")

elif var == '{domain}_total':
    # Example: 0-N scale validation
    range_check = conn.execute(f"""
        SELECT COUNT(*) as count
        FROM {table_name}
        WHERE study_id = '{study_id}' AND ({var} < 0 OR {var} > {N})
    """).df()

    if range_check['count'].iloc[0] > 0:
        print(f"  [WARN] {var}: {range_check['count'].iloc[0]} out-of-range values")
```

**4. Update Module Docstring:**

```python
"""
Imputation Helper Functions

This module provides helper functions for working with multiply-imputed data
from the Kidsights imputation pipeline.

Variables Available (N total across M imputations):
- Geography (3): puma, county, census_tract
- Sociodemographic (7): female, raceG, educ_mom, educ_a2, income, family_size, fplcat
- Childcare (4): childcare_coverage, childcare_type, childcare_provider, childcare_cost
- Mental Health (7): phq2_interest, phq2_depressed, gad2_nervous, gad2_worry, q1502, phq2_positive, gad2_positive
- Child ACEs (9): 8 items + total
- {Domain Name} (N): ...  # NEW SECTION
"""
```

---

### Documentation Update Requirements

**1. CLAUDE.md Updates:**

Update the "Imputation Pipeline - Production Ready" section:

```markdown
### ✅ Imputation Pipeline - Production Ready (October 2025)
- **Multi-Study Architecture:** Independent studies (ne25, ia26, co27) with shared codebase
- **Multiple Imputations:** M=5 imputations (easily scalable to M=20+)
- **Geographic Variables:** [N] PUMA, [N] county, [N] census tract imputations (ne25)
- **Sociodemographic Variables:** 7 variables imputed via mice
- **{Domain} Variables:** [N] variables imputed via mice/rf/cart  # NEW LINE
- **Storage Efficiency:** Study-specific variable tables (`{study_id}_imputed_{variable}`)
- **Language Support:** Python native + R via reticulate (single source of truth)
- **Database:** [N] total imputation rows ([breakdown]) for ne25
- **Execution Time:** ~X minutes for complete pipeline (Y stages)
```

**2. PIPELINE_OVERVIEW.md Updates:**

Add section to imputation pipeline description:

```markdown
#### Stage XX-YY: {Domain Name} Imputation

**Variables:** [N] variables ([X] items + [Y] derived)

**Method:** {MICE method - cart/rf/pmm}

**Auxiliary Variables:**
- PUMA (from geography imputation m)
- Sociodemographic variables (from sociodem imputation m)
- ... (list all auxiliary variables)

**Implementation:**
- R Script: `scripts/imputation/ne25/XX_impute_{domain}.R`
- Python Insert: `scripts/imputation/ne25/XXb_insert_{domain}.py`
- Database Tables: `ne25_imputed_{variable}` (N tables)
- Execution Time: ~X seconds per imputation (~Y minutes total)
```

**3. QUICK_REFERENCE.md Updates:**

Add usage example:

```markdown
### Query {Domain} Imputations

```python
from python.imputation.helpers import get_{domain}_imputations

# Get {domain} variables for imputation 1
data = get_{domain}_imputations(study_id="ne25", imputation_number=1)

# Get with base data included
data = get_{domain}_imputations(imputation_number=1, include_base_data=True)

# Access specific variables
print(data[['pid', 'record_id', '{variable_1}', '{variable_2}']].head())
```
```

---

## Detailed Phase Instructions

### Phase 1: R Imputation Script

**Step 1: File Setup**

Create file: `scripts/imputation/{study_id}/XX_impute_{domain}.R`

**Header Template:**
```r
# {Domain Name} Stage: Impute [Variables] for {STUDY_ID}
#
# Generates M=5 imputations for {domain} variables using {method} method.
# Uses chained imputation approach where each mice run uses geography + sociodem
# + [previous stages] from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/{study_id}/XX_impute_{domain}.R
#
# Variables Imputed (N total):
#   - variable_1 ({method}) - Description (scale)
#   - variable_2 ({method}) - Description (scale)
#   ...
#
# Derived Variables (N total, computed after imputation):
#   - derived_var_1 - Description
#   ...
#
# Auxiliary Variables (N total):
#   - puma (from geography imputation m)
#   - sociodem vars (from sociodem imputation m if imputed, else base)
#   - [other auxiliary vars]
```

**Step 2: Configuration Loading**

```r
# =============================================================================
# SETUP
# =============================================================================

cat("{Domain Name}: Impute [Variables] for {STUDY_ID}\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

# Package availability checks
if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
}
# ... (repeat for other packages)

# Source configuration
source("R/imputation/config.R")

# Source transforms if using recode_missing
# source("R/transform/ne25_transforms.R")

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

study_id <- "{study_id}"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

cat("\nConfiguration:\n")
cat("  Study ID:", study_id, "\n")
cat("  Study Name:", study_config$study_name, "\n")
cat("  Number of imputations (M):", config$n_imputations, "\n")
cat("  Random seed:", config$random_seed, "\n")
cat("  Data directory:", study_config$data_dir, "\n")
cat("  Variables to impute: [list]\n")
cat("  Method: {method}\n")
cat("  Defensive filtering: eligible.x = TRUE AND authentic.x = TRUE\n")

M <- config$n_imputations
seed <- config$random_seed
```

**Step 3: Helper Functions**

Implement these required helper functions:

```r
# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base {domain} data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to eligible.x == TRUE AND authentic.x == TRUE
#'
#' @return data.frame with base {domain} data
load_base_{domain}_data <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base {domain} data from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      '{study_id}' as study_id,

      -- Variables to impute
      variable_1,
      variable_2,
      -- ...

      -- Auxiliary variables
      \"authentic.x\",
      age_in_days,
      -- ...

      -- Eligibility flag
      \"eligible.x\"
    FROM {study_id}_transformed
  "

  if (eligible_only) {
    query <- paste0(query, "\n    WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  # Apply recode_missing if sentinel values present
  # for (var in c("variable_1", "variable_2")) {
  #   if (var %in% names(dat)) {
  #     dat[[var]] <- recode_missing(dat[[var]], missing_codes = c(99, 9))
  #   }
  # }

  cat("  [OK] Loaded", nrow(dat), "records (defensive filtering applied)\n")

  return(dat)
}


#' Load PUMA imputation from database
load_puma_imputation <- function(db_path, m, study_id = "{study_id}") {
  cat(sprintf("\n[INFO] Loading PUMA imputation m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      puma
    FROM %s_imputed_puma
    WHERE study_id = '%s' AND imputation_m = %d
  ", study_id, study_id, m)

  puma_data <- DBI::dbGetQuery(con, query)

  cat(sprintf("  [OK] Loaded %d PUMA imputations\n", nrow(puma_data)))

  return(puma_data)
}


#' Load [previous stage] imputations
#'
#' NOTE: Customize this function based on which auxiliary variables you need
load_auxiliary_imputations <- function(db_path, m, study_id = "{study_id}") {
  cat(sprintf("\n[INFO] Loading auxiliary imputations m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Example: Load sociodem variables
  # Customize based on your needs

  cat(sprintf("  [OK] Loaded auxiliary imputations\n"))

  return(aux_data)
}


#' Merge base data with auxiliary imputations
merge_imputed_data <- function(base_data, puma_imp, aux_imp, db_path) {
  cat("\n[INFO] Merging base data with imputations...\n")

  # Merge PUMA
  dat_merged <- base_data %>%
    dplyr::left_join(puma_imp, by = c("pid", "record_id"))

  # Fill missing PUMA from base table (for records without geography ambiguity)
  if (any(is.na(dat_merged$puma))) {
    con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

    geo_observed <- DBI::dbGetQuery(con, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        puma as puma_observed
      FROM {study_id}_transformed
      WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE
    ")

    dat_merged <- dat_merged %>%
      dplyr::left_join(geo_observed, by = c("pid", "record_id")) %>%
      dplyr::mutate(puma = ifelse(is.na(puma), puma_observed, puma)) %>%
      dplyr::select(-puma_observed)
  }

  # Merge auxiliary imputations
  # ... (customize based on auxiliary variables needed)

  cat(sprintf("  [OK] Merged data: %d records with %d columns\n", nrow(dat_merged), ncol(dat_merged)))

  return(dat_merged)
}


#' Save imputation to Feather (single variable)
save_{domain}_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  cat(sprintf("\n[INFO] Saving %s imputation m=%d to Feather...\n", variable_name, m))

  # Save ONLY originally-missing records
  originally_missing <- is.na(original_data[[variable_name]])

  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", variable_name)]
  imputed_records$imputation_m <- m

  # DEFENSIVE FILTERING: Remove records where imputation failed
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\n", n_null_filtered))
  }

  if (nrow(imputed_records) > 0) {
    # Reorder columns
    imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", variable_name)]

    # Save to Feather
    output_path <- file.path(output_dir, sprintf("%s_m%d.feather", variable_name, m))
    arrow::write_feather(imputed_records, output_path)

    cat(sprintf("  [OK] %s: %d values -> %s\n", variable_name, nrow(imputed_records), basename(output_path)))
  } else {
    cat(sprintf("  [WARN] %s: No imputed values to save\n", variable_name))
  }

  return(invisible(NULL))
}
```

**Step 4: Main Imputation Loop**

```r
# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting {Domain Name} Imputation\n")
cat(strrep("=", 60), "\n")

# Setup output directory
output_dir <- file.path(study_config$data_dir, "{domain}_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\n")
}

# Load base data ONCE
db_path <- config$database$db_path
base_data <- load_base_{domain}_data(db_path, eligible_only = TRUE)

# Check missing data
{domain}_vars <- c("variable_1", "variable_2", ...)

cat("\nMissing data summary:\n")
for (var in {domain}_vars) {
  n_missing <- sum(is.na(base_data[[var]]))
  pct_missing <- 100 * n_missing / nrow(base_data)
  cat(sprintf("  %s: %d of %d (%.1f%%)\n", var, n_missing, nrow(base_data), pct_missing))
}

# LOOP OVER IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load auxiliary imputations m
  aux_m <- load_auxiliary_imputations(db_path, m)

  # Step 3: Merge all data
  dat_m <- merge_imputed_data(base_data, puma_m, aux_m, db_path)

  # Step 4: Prepare data for mice
  imp_vars <- c("variable_1", "variable_2", ...)
  aux_vars <- c("puma", "sociodem_var1", "sociodem_var2", ...)

  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables exist
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\n[WARN] Missing columns (will skip): %s\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Step 5: Configure mice
  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # Each variable to impute can use all auxiliary variables as predictors
  for (var in imp_vars) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
      predictor_matrix[var, aux_vars_existing] <- 1
    }
  }

  # Auxiliary variables are NOT imputed
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  for (var in imp_vars) {
    if (var %in% names(method_vector)) {
      method_vector[var] <- "{method}"  # cart, rf, pmm, etc.
    }
  }

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations: 5\n")
  cat("  Method: {method}\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\n")
  cat("  remove.collinear: FALSE\n")

  # Step 6: Run mice
  cat("\n[INFO] Running mice imputation...\n")

  set.seed(seed + m)  # CRITICAL: seed + m

  mice_result <- mice::mice(
    data = dat_mice,
    m = 1,
    method = method_vector,
    predictorMatrix = predictor_matrix,
    maxit = 5,
    remove.collinear = FALSE,
    printFlag = FALSE
  )

  cat("  [OK] mice imputation complete\n")

  # Step 7: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 8: Save each variable to Feather
  for (var in {domain}_vars) {
    save_{domain}_feather(completed_m, dat_m, m, output_dir, var)
  }

  # Step 9: Derive composite scores (if applicable)
  # derive_composite_scores(completed_m, base_data, m, output_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("{Domain Name} Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variables imputed: %s\n", paste({domain}_vars, collapse = ", ")))
cat(sprintf("  Method: {method}\n"))
cat(sprintf("  Output directory: %s\n", output_dir))
cat(sprintf("  Total output files: %d\n", length({domain}_vars) * M))

cat("\nNext steps:\n")
cat("  1. Run: python scripts/imputation/{study_id}/XXb_insert_{domain}.py\n")
cat(strrep("=", 60), "\n")
```

---

### Phase 2: Python Database Insertion Script

**Step 1: File Setup**

Create file: `scripts/imputation/{study_id}/XXb_insert_{domain}.py`

**Header Template:**
```python
"""
Insert {Domain Name} Imputations into DuckDB

Reads Feather files generated by {domain} imputation script (XX_impute_{domain}.R)
and inserts imputed/derived values into DuckDB tables.

This script handles N {domain} variables:
- variable_1: DATA_TYPE (description)
- variable_2: DATA_TYPE (description)
...

Usage:
    python scripts/imputation/{study_id}/XXb_insert_{domain}.py
"""

import sys
from pathlib import Path
import pandas as pd

# Add project root to path
# CRITICAL: Use correct parent chain for your file location
# __file__ is scripts/imputation/{study_id}/XXb_insert_{domain}.py
# parent = {study_id}/, parent.parent = imputation/, parent.parent.parent = scripts/,
# parent.parent.parent.parent = project_root
project_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
from python.imputation.config import get_study_config, get_table_prefix
```

**Step 2: Load Feather Files Function**

```python
def load_feather_files(feather_dir: Path, variable_name: str, n_imputations: int, required: bool = True):
    """
    Load Feather files for a single variable across all imputations

    Parameters
    ----------
    feather_dir : Path
        Directory containing Feather files
    variable_name : str
        Name of variable (e.g., "variable_1")
    n_imputations : int
        Number of imputations to load (M)
    required : bool
        If True, raise error if files not found. If False, return empty dict.

    Returns
    -------
    dict
        Dictionary mapping imputation_m to DataFrame
    """
    # Pattern: {variable}_m{m}.feather
    pattern = f"{variable_name}_m*.feather"
    feather_files = sorted(feather_dir.glob(pattern))

    if len(feather_files) == 0:
        if required:
            raise FileNotFoundError(
                f"No Feather files found for variable '{variable_name}' in {feather_dir}\n"
                f"Expected pattern: {pattern}\n"
                f"Run {domain} imputation script first: scripts/imputation/{study_id}/XX_impute_{domain}.R"
            )
        else:
            print(f"  [WARN] No Feather files found for {variable_name}")
            return {}

    imputations = {}

    for f in feather_files:
        # Extract m from filename
        import re
        match = re.search(r'_m(\d+)$', f.stem)
        if not match:
            raise ValueError(f"Could not extract imputation number from filename: {f.name}")
        m = int(match.group(1))
        df = pd.read_feather(f)

        # Validate columns
        expected_cols = {'study_id', 'pid', 'record_id', 'imputation_m', variable_name}
        if not expected_cols.issubset(df.columns):
            raise ValueError(
                f"Missing columns in {f.name}. Expected: {expected_cols}, Got: {set(df.columns)}"
            )

        imputations[m] = df

    if len(imputations) != n_imputations:
        print(f"  [WARN] Expected {n_imputations} files, found {len(imputations)} for {variable_name}")

    return imputations
```

**Step 3: Create Tables Function**

```python
def create_{domain}_tables(db: DatabaseManager, study_id: str):
    """
    Create database tables for {domain} imputations

    Following pattern: separate table per variable with naming:
    {study_id}_imputed_{variable_name}

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier (e.g., "ne25")
    """
    print(f"\n[INFO] Creating {domain} imputation tables...")

    table_prefix = get_table_prefix(study_id)

    with db.get_connection() as conn:
        # Create table for each variable
        # Example for continuous variable (0-3 scale):
        conn.execute(f"""
            DROP TABLE IF EXISTS {table_prefix}_variable_1
        """)
        conn.execute(f"""
            CREATE TABLE {table_prefix}_variable_1 (
                study_id VARCHAR NOT NULL,
                pid INTEGER NOT NULL,
                record_id INTEGER NOT NULL,
                imputation_m INTEGER NOT NULL,
                variable_1 DOUBLE NOT NULL,
                PRIMARY KEY (study_id, pid, record_id, imputation_m)
            )
        """)

        # Example for binary variable:
        conn.execute(f"""
            DROP TABLE IF EXISTS {table_prefix}_variable_2
        """)
        conn.execute(f"""
            CREATE TABLE {table_prefix}_variable_2 (
                study_id VARCHAR NOT NULL,
                pid INTEGER NOT NULL,
                record_id INTEGER NOT NULL,
                imputation_m INTEGER NOT NULL,
                variable_2 INTEGER NOT NULL,
                PRIMARY KEY (study_id, pid, record_id, imputation_m)
            )
        """)

        # Create indexes for all tables
        for var in ['{domain}_variables']:
            conn.execute(f"""
                CREATE INDEX IF NOT EXISTS idx_{table_prefix}_{var}_pid_record
                ON {table_prefix}_{var} (pid, record_id)
            """)
            conn.execute(f"""
                CREATE INDEX IF NOT EXISTS idx_{table_prefix}_{var}_imputation
                ON {table_prefix}_{var} (imputation_m)
            """)

    print(f"  [OK] Created N {domain} tables with indexes")
```

**Step 4: Insert Function**

```python
def insert_{domain}_imputations(db: DatabaseManager, study_id: str, feather_dir: Path, n_imputations: int):
    """
    Insert {domain} imputations from Feather files into database

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier
    feather_dir : Path
        Directory containing Feather files
    n_imputations : int
        Number of imputations (M)
    """
    print(f"\n[INFO] Inserting {domain} imputations into database...")

    table_prefix = get_table_prefix(study_id)

    {domain}_vars = ['variable_1', 'variable_2', ...]

    total_rows_inserted = 0

    for variable in {domain}_vars:
        print(f"\n[INFO] Processing {variable}...")

        # Load Feather files
        imputations = load_feather_files(feather_dir, variable, n_imputations, required=True)

        variable_rows = 0

        # Insert each imputation
        for m, df in sorted(imputations.items()):
            with db.get_connection() as conn:
                # Validate data types and ranges
                # Example: Binary validation
                if variable in ['binary_var_1', 'binary_var_2']:
                    unique_vals = df[variable].unique()
                    if not set(unique_vals).issubset({0, 1}):
                        raise ValueError(
                            f"Invalid binary values in {variable} imputation {m}: {unique_vals}"
                        )

                # Example: Range validation
                elif variable == 'continuous_var':
                    if df[variable].min() < 0 or df[variable].max() > 3:
                        raise ValueError(
                            f"Invalid range in {variable} imputation {m}: "
                            f"min={df[variable].min()}, max={df[variable].max()}"
                        )

                # Insert into table
                table_name = f"{table_prefix}_{variable}"
                df.to_sql(table_name, conn, if_exists='append', index=False)

                variable_rows += len(df)
                print(f"  [OK] Inserted {len(df)} rows for imputation m={m}")

        total_rows_inserted += variable_rows
        print(f"  [OK] Total for {variable}: {variable_rows} rows")

    print(f"\n[OK] All {domain} imputations inserted: {total_rows_inserted} total rows across N tables")
```

**Step 5: Validate Function**

```python
def validate_{domain}_tables(db: DatabaseManager, study_id: str, n_imputations: int):
    """
    Validate {domain} imputation tables

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier
    n_imputations : int
        Expected number of imputations (M)
    """
    print(f"\n[INFO] Validating {domain} imputation tables...")

    table_prefix = get_table_prefix(study_id)
    {domain}_vars = ['variable_1', 'variable_2', ...]

    with db.get_connection(read_only=True) as conn:
        for variable in {domain}_vars:
            table_name = f"{table_prefix}_{variable}"

            # Check row count
            result = conn.execute(f"SELECT COUNT(*) as count FROM {table_name}").fetchone()
            total_rows = result[0]

            # Check for NULL values
            result = conn.execute(f"SELECT COUNT(*) FROM {table_name} WHERE {variable} IS NULL").fetchone()
            null_count = result[0]

            if null_count > 0:
                print(f"  [WARN] {variable}: {null_count} NULL values found")
            else:
                print(f"  [OK] {variable}: {total_rows} rows, no NULLs")

            # Check value ranges (customize based on variable type)
            if variable in ['binary_var_1', 'binary_var_2']:
                result = conn.execute(f"SELECT DISTINCT {variable} FROM {table_name} ORDER BY {variable}").fetchall()
                unique_vals = [row[0] for row in result]
                if set(unique_vals) != {0, 1}:
                    print(f"  [WARN] {variable}: Non-binary values: {unique_vals}")
                else:
                    print(f"  [OK] {variable}: Binary values (0, 1)")

            elif variable in ['continuous_var']:
                result = conn.execute(f"SELECT MIN({variable}), MAX({variable}) FROM {table_name}").fetchone()
                min_val, max_val = result[0], result[1]
                if min_val < 0 or max_val > 3:
                    print(f"  [WARN] {variable}: Invalid range ({min_val}-{max_val}), expected 0-3")
                else:
                    print(f"  [OK] {variable}: Valid range ({min_val}-{max_val})")

        # Summary statistics
        print(f"\n[INFO] Summary Statistics:")

        # Total rows across all tables
        # (Customize query based on your variables)

    print(f"\n[OK] Validation complete")
```

**Step 6: Main Function**

```python
def main():
    """Main execution function"""
    print("=" * 60)
    print("{Domain Name} Imputation Database Insertion")
    print("=" * 60)

    # Configuration
    study_id = "{study_id}"
    study_config = get_study_config(study_id)
    n_imputations = 5

    # Feather directory
    feather_dir = Path(study_config['data_dir']) / "{domain}_feather"

    print(f"\nConfiguration:")
    print(f"  Study ID: {study_id}")
    print(f"  Feather directory: {feather_dir}")
    print(f"  Number of imputations: {n_imputations}")

    if not feather_dir.exists():
        raise FileNotFoundError(
            f"Feather directory not found: {feather_dir}\n"
            f"Run {domain} imputation script first: scripts/imputation/{study_id}/XX_impute_{domain}.R"
        )

    # Initialize database connection
    db = DatabaseManager()

    try:
        # Step 1: Create tables
        create_{domain}_tables(db, study_id)

        # Step 2: Insert imputations
        insert_{domain}_imputations(db, study_id, feather_dir, n_imputations)

        # Step 3: Validate tables
        validate_{domain}_tables(db, study_id, n_imputations)

        print("\n" + "=" * 60)
        print("{Domain Name} Imputation Database Insertion Complete!")
        print("=" * 60)

        print("\nNext steps:")
        print("  1. Query {domain} via helper functions:")
        print("     from python.imputation.helpers import get_{domain}_imputations")
        print("     data = get_{domain}_imputations(study_id='{study_id}', imputation_number=1)")
        print("  2. Update pipeline orchestrator to include this stage")
        print("  3. Update documentation")

    except Exception as e:
        print(f"\n[ERROR] Database insertion failed: {e}")
        raise


if __name__ == "__main__":
    main()
```

---

## Special Patterns

### Conditional Imputation Pattern

**For variables that depend on other variables (e.g., childcare type only if childcare_coverage = 1):**

**R Script Pattern:**
```r
# Example from childcare imputation
# Stage 1: Impute coverage (unconditional)
childcare_coverage_vars <- c("childcare_coverage", "childcare_cost")

# Stage 2: Impute type/hours (conditional on coverage = 1)
# Filter data to only those with childcare coverage
dat_with_childcare <- dat_mice %>%
  dplyr::filter(childcare_coverage == 1)

if (nrow(dat_with_childcare) > 0) {
  # Run mice only on subset with coverage
  mice_result_conditional <- mice::mice(
    data = dat_with_childcare,
    m = 1,
    method = method_vector_conditional,
    predictorMatrix = predictor_matrix_conditional,
    maxit = 5,
    remove.collinear = FALSE,
    printFlag = FALSE
  )

  completed_conditional <- mice::complete(mice_result_conditional, 1)

  # Save only for records that had missing type/hours AND had coverage
  originally_missing_type <- is.na(dat_with_childcare$cc_primary_type)
  save_childcare_feather(completed_conditional, dat_with_childcare, m, output_dir, "cc_primary_type")
}
```

**Python Insertion Pattern:**
```python
# Handle conditional variables that may not exist for all imputations
for var in conditional_vars:
    imputations = load_feather_files(feather_dir, var, n_imputations, required=False)
    if len(imputations) > 0:
        n_rows = insert_variable_imputations(db, var, imputations, study_id)
        if n_rows > 0:  # Only update metadata if we inserted something
            update_metadata(db, study_id, var, n_imputations, n_rows, method)
    else:
        print(f"  [INFO] No imputations found for conditional variable {var}")
```

---

### Multi-Stage Imputation Pattern

**For complex domains with interdependent variables:**

```r
# Example: Childcare with 3 stages
cat("\nStage 1: Impute childcare coverage and cost (unconditional)\n")
# ... mice for coverage and cost ...

cat("\nStage 2: Impute childcare type and hours (conditional on coverage=1)\n")
# ... mice for type and hours, only for those with coverage ...

cat("\nStage 3: Derive childcare_10hrs_nonfamily\n")
# ... derive composite variable ...
```

**Key Principles:**
1. Impute unconditional variables first
2. Use results from stage 1 to filter/condition stage 2
3. Derive composite variables last
4. Save each stage's outputs separately

---

## Common Pitfalls to Avoid

### 1. Incorrect Seed Usage
**❌ Wrong:**
```r
for (m in 1:M) {
  set.seed(seed)  # All imputations will be identical!
  mice_result <- mice::mice(...)
}
```

**✅ Correct:**
```r
for (m in 1:M) {
  set.seed(seed + m)  # Each imputation is unique but reproducible
  mice_result <- mice::mice(...)
}
```

---

### 2. Saving Observed Values
**❌ Wrong:**
```r
# Saving all records, including those with observed values
output_data <- completed_m[, c("study_id", "pid", "record_id", "variable")]
```

**✅ Correct:**
```r
# Only save records that were originally missing
originally_missing <- is.na(base_data[[variable]])
output_data <- completed_m[originally_missing, c("study_id", "pid", "record_id", "variable")]
```

---

### 3. Forgetting Defensive Filtering
**❌ Wrong:**
```r
query <- "SELECT ... FROM ne25_transformed"
```

**✅ Correct:**
```r
query <- "SELECT ... FROM ne25_transformed WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE"
```

---

### 4. Not Filtering Failed Imputations
**❌ Wrong:**
```r
# Saving all records, even those where imputation failed (value still NA)
arrow::write_feather(imputed_records, output_path)
```

**✅ Correct:**
```r
# Remove records where imputation failed
successfully_imputed <- !is.na(imputed_records[[variable_name]])
imputed_records <- imputed_records[successfully_imputed, ]

if (nrow(imputed_records) > 0) {
  arrow::write_feather(imputed_records, output_path)
}
```

---

### 5. Missing Data Type Validation
**❌ Wrong:**
```python
# Inserting without validating data types
df.to_sql(table_name, conn, if_exists='append', index=False)
```

**✅ Correct:**
```python
# Validate data types before insertion
if variable == "binary_var":
    unique_vals = df[variable].unique()
    if not set(unique_vals).issubset({0, 1}):
        raise ValueError(f"Invalid binary values: {unique_vals}")

df.to_sql(table_name, conn, if_exists='append', index=False)
```

---

### 6. Not Applying recode_missing()
**❌ Wrong:**
```r
# Loading raw data with sentinel values (99, 9)
base_data <- load_base_data(db_path)
# Sentinel values will contaminate imputations!
```

**✅ Correct:**
```r
# Apply recode_missing to convert sentinel values to NA
base_data <- load_base_data(db_path)

for (var in variables_with_sentinels) {
  base_data[[var]] <- recode_missing(base_data[[var]], missing_codes = c(99, 9))
}
```

---

### 7. Forgetting to Create Indexes
**❌ Wrong:**
```python
# Creating table without indexes
conn.execute(f"CREATE TABLE {table_name} (...)")
```

**✅ Correct:**
```python
# Create table AND indexes
conn.execute(f"CREATE TABLE {table_name} (...)")

conn.execute(f"""
    CREATE INDEX IF NOT EXISTS idx_{table_name}_pid_record
    ON {table_name} (pid, record_id)
""")

conn.execute(f"""
    CREATE INDEX IF NOT EXISTS idx_{table_name}_imputation
    ON {table_name} (imputation_m)
""")
```

---

### 8. Incorrect Derived Variable Storage
**❌ Wrong:**
```r
# Saving derived variable for ALL records
derived_data <- completed_m[, c("study_id", "pid", "record_id", "composite_score")]
```

**✅ Correct:**
```r
# Only save derived variable if ANY component was imputed
any_component_missing <- rowSums(is.na(base_data[, component_items])) > 0
records_needing_derivation <- base_data[any_component_missing, c("pid", "record_id")]

# Filter derived data to only these records
```

---

## Testing Guidelines

### Phase 1 Testing (R Imputation Script)

**Test Execution:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/{study_id}/XX_impute_{domain}.R
```

**Validation Checks:**
1. **Output Directory Created:** Check that `data/{study_id}/{domain}_feather/` exists
2. **Feather Files Generated:** Should have `N_variables × M` files (e.g., 8 variables × 5 imputations = 40 files)
3. **File Naming:** Files should follow pattern `{variable}_m{m}.feather`
4. **File Contents:**
   - Each file should have columns: `study_id`, `pid`, `record_id`, `imputation_m`, `{variable}`
   - No NULL values in imputed variable
   - Row count should match number of originally-missing records
5. **Console Output:** Should show:
   - Configuration summary
   - Missing data summary
   - Progress for each imputation (m=1/5, m=2/5, etc.)
   - Completion summary

**Test Read Feather File:**
```r
library(arrow)
test_file <- "data/{study_id}/{domain}_feather/variable_1_m1.feather"
test_data <- arrow::read_feather(test_file)

# Check columns
print(names(test_data))

# Check for NULLs
print(sum(is.na(test_data$variable_1)))

# Check value distribution
print(table(test_data$variable_1))
```

---

### Phase 2 Testing (Python Database Insertion)

**Test Execution:**
```bash
python scripts/imputation/{study_id}/XXb_insert_{domain}.py
```

**Validation Checks:**
1. **Tables Created:** Verify N tables exist in database
2. **Row Counts:** Each table should have consistent row counts across imputations
3. **No NULLs:** Validation should report 0 NULL values
4. **Value Ranges:** Validation should confirm correct ranges (e.g., 0-3, 0/1)
5. **No Duplicates:** Validation should report no duplicate primary keys
6. **Indexes Created:** Check that indexes exist on (pid, record_id) and (imputation_m)

**Test Query Database:**
```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection(read_only=True) as conn:
    # Check table exists
    result = conn.execute("""
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_name = '{study_id}_imputed_variable_1'
    """).fetchone()
    print(f"Table exists: {result[0] > 0}")

    # Check row count
    result = conn.execute("""
        SELECT COUNT(*) FROM {study_id}_imputed_variable_1
    """).fetchone()
    print(f"Total rows: {result[0]}")

    # Check imputation coverage
    result = conn.execute("""
        SELECT imputation_m, COUNT(*) as count
        FROM {study_id}_imputed_variable_1
        GROUP BY imputation_m
        ORDER BY imputation_m
    """).fetchall()
    print(f"Rows per imputation: {result}")
```

---

### Phase 3 Testing (Pipeline Integration)

**Test Execution:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/{study_id}/run_full_imputation_pipeline.R
```

**Validation Checks:**
1. **Stage Execution:** New stage should execute without errors
2. **Timing:** Stage timing should be reported
3. **Error Handling:** If stage fails, pipeline should halt with informative error
4. **Sequential Execution:** Stage should execute after previous stages complete

---

### Phase 4 Testing (Helper Functions)

**Test Helper Function:**
```python
from python.imputation.helpers import get_{domain}_imputations

# Test basic retrieval
data = get_{domain}_imputations(study_id="{study_id}", imputation_number=1)

# Validate structure
print(f"Shape: {data.shape}")
print(f"Columns: {data.columns.tolist()}")

# Check for NULLs
print(f"NULL counts:\n{data.isnull().sum()}")

# Test with base data
data_with_base = get_{domain}_imputations(imputation_number=1, include_base_data=True)
print(f"Shape with base: {data_with_base.shape}")
```

**Test get_complete_dataset():**
```python
from python.imputation.helpers import get_complete_dataset

# Test with new domain included
data = get_complete_dataset(
    study_id="{study_id}",
    imputation_number=1,
    include_{domain}=True
)

# Validate all variables present
expected_vars = ['puma', 'county', 'census_tract',  # Geography
                 'female', 'raceG', 'educ_mom', 'income',  # Sociodem
                 '{domain}_var1', '{domain}_var2']  # New domain

missing_vars = set(expected_vars) - set(data.columns)
if missing_vars:
    print(f"Missing variables: {missing_vars}")
else:
    print("All expected variables present")
```

**Test validate_imputations():**
```python
from python.imputation.helpers import validate_imputations

# Run validation
validate_imputations(study_id="{study_id}", imputation_m=1)

# Should report:
# - Row counts for all tables
# - NULL counts (should be 0)
# - Value range checks
# - Any validation warnings/errors
```

---

### Integration Testing

**End-to-End Test:**
```python
"""
Test complete workflow: imputation → database → retrieval → analysis
"""
from python.imputation.helpers import get_{domain}_imputations, get_complete_dataset
import pandas as pd

# Step 1: Retrieve imputed data
print("Step 1: Retrieve {domain} imputations for m=1")
data_m1 = get_{domain}_imputations(imputation_number=1)
print(f"  Retrieved {len(data_m1)} records")

# Step 2: Verify no duplicates
print("\nStep 2: Check for duplicates")
duplicates = data_m1.duplicated(subset=['pid', 'record_id']).sum()
print(f"  Duplicates: {duplicates} (should be 0)")

# Step 3: Verify all imputations
print("\nStep 3: Verify all M imputations")
for m in range(1, 6):
    data = get_{domain}_imputations(imputation_number=m)
    print(f"  m={m}: {len(data)} records")

# Step 4: Merge with base data
print("\nStep 4: Merge with base data")
complete_data = get_complete_dataset(
    imputation_number=1,
    include_base_data=True,
    include_{domain}=True
)
print(f"  Complete dataset: {complete_data.shape}")

# Step 5: Validate merged data
print("\nStep 5: Validate merged data")
base_cols = ['pid', 'record_id', 'age_in_days', 'source_project']
{domain}_cols = ['{domain}_var1', '{domain}_var2']

for col in base_cols + {domain}_cols:
    if col not in complete_data.columns:
        print(f"  [ERROR] Missing column: {col}")
    else:
        null_count = complete_data[col].isnull().sum()
        print(f"  {col}: {null_count} NULLs")

print("\n[OK] Integration test complete")
```

---

## Summary

When adding a new imputation stage:

1. **Follow the 5-phase pattern** (R script → Python insert → Pipeline integration → Helper functions → Documentation)
2. **Use chained imputation** (load auxiliary variables from imputation m)
3. **Apply storage convention** (only save imputed values, not observed)
4. **Use defensive filtering everywhere** (eligible.x = TRUE AND authentic.x = TRUE)
5. **Use unique seeds** (seed + m, not just seed)
6. **Validate at every step** (data types, ranges, NULLs, duplicates)
7. **Test thoroughly** (unit tests for each phase, integration test end-to-end)
8. **Update documentation** (CLAUDE.md, PIPELINE_OVERVIEW.md, QUICK_REFERENCE.md)

---

**For questions or clarifications, see:**
- **docs/imputation/USING_IMPUTATION_AGENT.md** - How to use imputation helper functions
- **docs/guides/MISSING_DATA_GUIDE.md** - Missing data handling
- **docs/architecture/PIPELINE_OVERVIEW.md** - Overall pipeline architecture
- **python/imputation/helpers.py** - Helper function source code
- **R/imputation/config.R** - Configuration system

*Last Updated: October 2025 | Version: 1.0.0*
