# Imputation Stage Templates

**Last Updated:** October 2025 | **Version:** 1.0.0

This document contains complete code templates for the imputation-stage-builder agent to use when scaffolding new imputation stages. These templates follow all patterns documented in `ADDING_IMPUTATION_STAGES.md`.

---

## Table of Contents

1. [R Script Template](#r-script-template)
2. [Python Script Template](#python-script-template)
3. [Variable Substitution Guide](#variable-substitution-guide)
4. [TODO Marker Examples](#todo-marker-examples)

---

## R Script Template

```r
# {{DOMAIN_TITLE}} Stage: Impute {{VARIABLES_LIST}} for {{STUDY_ID_UPPER}}
#
# Generates M=5 imputations for {{DOMAIN}} variables using {{MICE_METHOD}} method.
# Uses chained imputation approach where each mice run uses geography + sociodem
# + [previous stages] from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/{{STUDY_ID}}/{{STAGE_NUMBER}}_impute_{{DOMAIN}}.R
#
# Variables Imputed ({{N_VARIABLES}} total):
{{VARIABLE_DESCRIPTIONS}}
#
# Derived Variables ({{N_DERIVED}} total, computed after imputation):
{{DERIVED_VARIABLE_DESCRIPTIONS}}
#
# Auxiliary Variables ({{N_AUXILIARY}} total):
#   - puma (from geography imputation m)
#   - sociodem vars (from sociodem imputation m if imputed, else base)
{{AUXILIARY_VARIABLE_LIST}}

# =============================================================================
# SETUP
# =============================================================================

cat("{{DOMAIN_TITLE}}: Impute {{VARIABLES_LIST}} for {{STUDY_ID_UPPER}}\\n")
cat(strrep("=", 60), "\\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

# TODO: [SETUP] Verify all required packages are installed
# Run: install.packages(c("duckdb", "dplyr", "mice", "arrow"))

if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
}
if (!requireNamespace("dplyr", quietly = TRUE)) {
  stop("Package 'dplyr' is required. Install with: install.packages('dplyr')")
}
if (!requireNamespace("mice", quietly = TRUE)) {
  stop("Package 'mice' is required. Install with: install.packages('mice')")
}
if (!requireNamespace("arrow", quietly = TRUE)) {
  stop("Package 'arrow' is required. Install with: install.packages('arrow')")
}

# Source configuration
source("R/imputation/config.R")

# TODO: [CONFIGURATION] If using recode_missing, source transforms
# source("R/transform/{{STUDY_ID}}_transforms.R")

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

study_id <- "{{STUDY_ID}}"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

cat("\\nConfiguration:\\n")
cat("  Study ID:", study_id, "\\n")
cat("  Study Name:", study_config$study_name, "\\n")
cat("  Number of imputations (M):", config$n_imputations, "\\n")
cat("  Random seed:", config$random_seed, "\\n")
cat("  Data directory:", study_config$data_dir, "\\n")
cat("  Variables to impute: {{VARIABLES_LIST}}\\n")
cat("  Method: {{MICE_METHOD}}\\n")
cat("  Defensive filtering: eligible.x = TRUE AND authentic.x = TRUE\\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base {{DOMAIN}} data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to eligible.x == TRUE AND authentic.x == TRUE
#'
#' @return data.frame with base {{DOMAIN}} data
load_base_{{DOMAIN}}_data <- function(db_path, eligible_only = TRUE) {
  cat("\\n[INFO] Loading base {{DOMAIN}} data from DuckDB...\\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Build query
  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      '{{STUDY_ID}}' as study_id,

      -- Variables to impute ({{N_VARIABLES}} total)
{{SELECT_VARIABLES}}

      -- Auxiliary variables (complete or mostly complete)
      \\"authentic.x\\",
      age_in_days,
      female,

      -- Eligibility flag
      \\"eligible.x\\"

    FROM {{STUDY_ID}}_transformed
  "

  if (eligible_only) {
    # DEFENSIVE FILTERING: Both eligible AND authentic
    query <- paste0(query, "\\n    WHERE \\"eligible.x\\" = TRUE AND \\"authentic.x\\" = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  # TODO: [DOMAIN LOGIC] Apply recode_missing if sentinel values present
  # Common missing codes: 99 (Prefer not to answer), 9 (Don't know), 7 (Refused)
  #
  # Example:
  # for (var in c({{VARIABLE_NAMES_QUOTED}})) {
  #   if (var %in% names(dat)) {
  #     dat[[var]] <- recode_missing(dat[[var]], missing_codes = c(99, 9))
  #   }
  # }

  cat("  [OK] Loaded", nrow(dat), "records (defensive filtering applied)\\n")

  return(dat)
}


#' Load PUMA imputation from database
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with PUMA for imputation m
load_puma_imputation <- function(db_path, m, study_id = "{{STUDY_ID}}") {
  cat(sprintf("\\n[INFO] Loading PUMA imputation m=%d...\\n", m))

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

  cat(sprintf("  [OK] Loaded %d PUMA imputations\\n", nrow(puma_data)))

  return(puma_data)
}


#' Load auxiliary imputations for {{DOMAIN}}
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with auxiliary variables for imputation m
load_auxiliary_imputations_for_{{DOMAIN}} <- function(db_path, m, study_id = "{{STUDY_ID}}") {
  cat(sprintf("\\n[INFO] Loading auxiliary imputations m=%d...\\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # TODO: [DOMAIN LOGIC] Specify which auxiliary variables to load
  # Common auxiliary variables:
  # - Sociodemographic: raceG, educ_mom, educ_a1, income, family_size, fplcat
  # - Mental health: phq2_positive, gad2_positive
  # - Child ACEs: child_ace_total
  #
  # Load each variable from its imputed table:
  # aux_vars <- c("raceG", "income", ...)
  # for (var in aux_vars) {
  #   query <- sprintf("SELECT pid, record_id, %s FROM %s_imputed_%s WHERE imputation_m = %d",
  #                    var, study_id, var, m)
  #   ...
  # }

  # Placeholder - customize based on your needs
  aux_data <- data.frame(pid = integer(), record_id = integer())

  cat(sprintf("  [OK] Loaded auxiliary imputations\\n"))

  return(aux_data)
}


#' Merge base data with auxiliary imputations
#'
#' @param base_data data.frame with base {{DOMAIN}} data
#' @param puma_imp data.frame with PUMA imputation
#' @param aux_imp data.frame with auxiliary imputations
#' @param db_path Path to DuckDB database
#'
#' @return data.frame with merged data
merge_imputed_data <- function(base_data, puma_imp, aux_imp, db_path) {
  cat("\\n[INFO] Merging base data with imputations...\\n")

  # Merge PUMA
  dat_merged <- base_data %>%
    dplyr::left_join(puma_imp, by = c("pid", "record_id"))

  # For records without geography ambiguity, fill from {{STUDY_ID}}_transformed
  if (any(is.na(dat_merged$puma))) {
    con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

    geo_observed <- DBI::dbGetQuery(con, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        puma as puma_observed
      FROM {{STUDY_ID}}_transformed
      WHERE \\"eligible.x\\" = TRUE AND \\"authentic.x\\" = TRUE
    ")

    dat_merged <- dat_merged %>%
      dplyr::left_join(geo_observed, by = c("pid", "record_id")) %>%
      dplyr::mutate(puma = ifelse(is.na(puma), puma_observed, puma)) %>%
      dplyr::select(-puma_observed)
  }

  # Merge auxiliary imputations
  if (ncol(aux_imp) > 2) {  # More than just pid, record_id
    dat_merged <- dat_merged %>%
      dplyr::left_join(aux_imp, by = c("pid", "record_id"))

    # TODO: [DOMAIN LOGIC] Fill missing auxiliary values from base table
    # For records with observed values (not imputed), get from ne25_transformed
    # Example pattern from existing implementations
  }

  cat(sprintf("  [OK] Merged data: %d records with %d columns\\n", nrow(dat_merged), ncol(dat_merged)))

  return(dat_merged)
}


#' Save {{DOMAIN}} imputation to Feather (single variable)
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#' @param variable_name Character, name of variable to save
#'
#' @return Invisible NULL
save_{{DOMAIN}}_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  cat(sprintf("\\n[INFO] Saving %s imputation m=%d to Feather...\\n", variable_name, m))

  # Save ONLY originally-missing records (space-efficient design)
  originally_missing <- is.na(original_data[[variable_name]])

  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", variable_name)]
  imputed_records$imputation_m <- m

  # DEFENSIVE FILTERING: Remove records where imputation failed (value still NA)
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\\n", n_null_filtered))
  }

  if (nrow(imputed_records) > 0) {
    # Reorder columns: study_id, pid, record_id, imputation_m, [variable]
    imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", variable_name)]

    # Save to Feather file
    output_path <- file.path(output_dir, sprintf("%s_m%d.feather", variable_name, m))
    arrow::write_feather(imputed_records, output_path)

    cat(sprintf("  [OK] %s: %d values -> %s\\n", variable_name, nrow(imputed_records), basename(output_path)))
  } else {
    cat(sprintf("  [WARN] %s: No imputed values to save\\n", variable_name))
  }

  return(invisible(NULL))
}

# TODO: [DOMAIN LOGIC] Add derived variable function if needed
# Example pattern:
# derive_{{DOMAIN}}_total <- function(completed_data, base_data, m, output_dir) {
#   # Calculate total score
#   # Save only for records where ANY component was imputed
#   # See existing implementations for pattern
# }

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\\n", strrep("=", 60), "\\n")
cat("Starting {{DOMAIN_TITLE}} Imputation\\n")
cat(strrep("=", 60), "\\n")

# Setup study-specific output directory
output_dir <- file.path(study_config$data_dir, "{{DOMAIN}}_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\\n")
}

# Load base data ONCE
db_path <- config$database$db_path
base_data <- load_base_{{DOMAIN}}_data(db_path, eligible_only = TRUE)

# Check missing data
{{DOMAIN}}_vars <- c({{VARIABLE_NAMES_QUOTED}})

cat("\\nMissing data summary:\\n")
for (var in {{DOMAIN}}_vars) {
  n_missing <- sum(is.na(base_data[[var]]))
  pct_missing <- 100 * n_missing / nrow(base_data)
  cat(sprintf("  %s: %d of %d (%.1f%%)\\n", var, n_missing, nrow(base_data), pct_missing))
}

# LOOP OVER IMPUTATIONS
for (m in 1:M) {
  cat("\\n", strrep("-", 60), "\\n")
  cat(sprintf("IMPUTATION m=%d/%d\\n", m, M))
  cat(strrep("-", 60), "\\n")

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load auxiliary imputations m
  aux_m <- load_auxiliary_imputations_for_{{DOMAIN}}(db_path, m)

  # Step 3: Merge all data
  dat_m <- merge_imputed_data(base_data, puma_m, aux_m, db_path)

  # Step 4: Prepare data for mice
  imp_vars <- c({{VARIABLE_NAMES_QUOTED}})

  # TODO: [DOMAIN LOGIC] Specify auxiliary variables
  # Available options (depends on previous stages):
  # - Geography: puma
  # - Sociodemographic: raceG, educ_mom, educ_a1, income, family_size, fplcat, female
  # - Mental health: phq2_positive, gad2_positive
  # - Child ACEs: child_ace_total
  # - Always available: authentic.x, age_in_days
  aux_vars <- c("puma", "authentic.x", "age_in_days", "female")  # TODO: Customize

  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables actually exist in dat_m
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\\n[WARN] Missing columns (will skip): %s\\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Step 5: Configure MICE
  # TODO: [STATISTICAL DECISION] Configure predictor matrix
  # Decision points:
  # 1. Which auxiliary variables should predict which target variables?
  # 2. Should target variables predict each other? (often yes for related constructs)
  # 3. Are there theoretical relationships to enforce?
  #
  # Resources:
  # - See similar implementations in scripts/imputation/{{STUDY_ID}}/
  # - Review correlation matrix between targets and auxiliaries
  # - Consider domain theory (e.g., depression items often correlate)

  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  # Get auxiliary variables that actually exist in the data
  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # Each target variable can use all auxiliary variables as predictors
  for (var in imp_vars) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0  # Reset row
      predictor_matrix[var, aux_vars_existing] <- 1  # Use auxiliaries
      # TODO: [STATISTICAL DECISION] Should target variables predict each other?
      # predictor_matrix[var, setdiff(imp_vars, var)] <- 1  # Uncomment to use other targets
    }
  }

  # Auxiliary variables are NOT imputed (use complete cases or pre-imputed)
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # TODO: [STATISTICAL DECISION] Set up methods vector
  # Common methods:
  # - cart: Classification/regression trees (robust, handles non-linearity)
  # - rf: Random forest (best for complex interactions, requires adequate N)
  # - pmm: Predictive mean matching (preserves distribution, good for continuous)
  # - logreg: Logistic regression (for binary variables)
  #
  # Method selection depends on:
  # 1. Variable type (continuous, ordinal, binary, categorical)
  # 2. Sample size (rf needs larger samples)
  # 3. Assumptions (pmm more flexible than parametric)
  # 4. Computational resources (rf slower than cart)

  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  for (var in imp_vars) {
    if (var %in% names(method_vector)) {
      method_vector[var] <- "{{MICE_METHOD}}"  # TODO: Verify this is appropriate
    }
  }

  cat("\\nmice Configuration:\\n")
  cat("  Imputations: 1 (chained approach)\\n")
  cat("  Iterations: 5\\n")
  cat("  Method: {{MICE_METHOD}}\\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\\n")
  cat("  remove.collinear: FALSE\\n")

  # Step 6: Run MICE
  cat("\\n[INFO] Running mice imputation...\\n")

  set.seed(seed + m)  # CRITICAL: seed + m, not just seed

  mice_result <- mice::mice(
    data = dat_mice,
    m = 1,
    method = method_vector,
    predictorMatrix = predictor_matrix,
    maxit = 5,
    remove.collinear = FALSE,
    printFlag = FALSE
  )

  cat("  [OK] mice imputation complete\\n")

  # Step 7: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 8: Save each variable to Feather (only originally-missing records)
  for (var in {{DOMAIN}}_vars) {
    save_{{DOMAIN}}_feather(completed_m, dat_m, m, output_dir, var)
  }

  # Step 9: Derive and save composite scores (if applicable)
  # TODO: [DOMAIN LOGIC] Call derived variable function if needed
  # derive_{{DOMAIN}}_total(completed_m, base_data, m, output_dir)

  cat(sprintf("\\n[OK] Imputation m=%d complete\\n", m))
}

cat("\\n", strrep("=", 60), "\\n")
cat("{{DOMAIN_TITLE}} Imputation Complete!\\n")
cat(strrep("=", 60), "\\n")

cat("\\nImputation Summary:\\n")
cat(sprintf("  Imputations generated: %d\\n", M))
cat(sprintf("  Variables imputed: %s\\n", paste({{DOMAIN}}_vars, collapse = ", ")))
cat(sprintf("  Method: {{MICE_METHOD}}\\n"))
cat(sprintf("  Output directory: %s\\n", output_dir))
cat(sprintf("  Total output files: %d\\n", length({{DOMAIN}}_vars) * M))

cat("\\nNext steps:\\n")
cat("  1. Run: python scripts/imputation/{{STUDY_ID}}/{{STAGE_NUMBER}}b_insert_{{DOMAIN}}.py\\n")
cat(strrep("=", 60), "\\n")
```

---

## Python Script Template

```python
"""
Insert {{DOMAIN_TITLE}} Imputations into DuckDB

Reads Feather files generated by {{STAGE_NUMBER}}_impute_{{DOMAIN}}.R
and inserts imputed/derived values into DuckDB tables.

This script handles {{N_VARIABLES}} {{DOMAIN}} variables:
{{PYTHON_VARIABLE_DESCRIPTIONS}}

Usage:
    python scripts/imputation/{{STUDY_ID}}/{{STAGE_NUMBER}}b_insert_{{DOMAIN}}.py
"""

import sys
from pathlib import Path
import pandas as pd

# Add project root to path
# CRITICAL: Use correct parent chain for your file location
# __file__ is scripts/imputation/{{STUDY_ID}}/{{STAGE_NUMBER}}b_insert_{{DOMAIN}}.py
# parent = {{STUDY_ID}}/, parent.parent = imputation/, parent.parent.parent = scripts/,
# parent.parent.parent.parent = project_root
project_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
from python.imputation.config import get_study_config, get_table_prefix


def load_feather_files(feather_dir: Path, variable_name: str, n_imputations: int, required: bool = True):
    """
    Load Feather files for a single variable across all imputations

    Parameters
    ----------
    feather_dir : Path
        Directory containing Feather files
    variable_name : str
        Name of variable (e.g., "{{EXAMPLE_VARIABLE}}")
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
                f"No Feather files found for variable '{variable_name}' in {feather_dir}\\n"
                f"Expected pattern: {pattern}\\n"
                f"Run {{DOMAIN}} imputation script first: scripts/imputation/{{STUDY_ID}}/{{STAGE_NUMBER}}_impute_{{DOMAIN}}.R"
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


def create_{{DOMAIN}}_tables(db: DatabaseManager, study_id: str):
    """
    Create database tables for {{DOMAIN}} imputations

    Following pattern: separate table per variable with naming:
    {study_id}_imputed_{variable_name}

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier (e.g., "ne25")
    """
    print(f"\\n[INFO] Creating {{DOMAIN}} imputation tables...")

    table_prefix = get_table_prefix(study_id)

    with db.get_connection() as conn:
        # TODO: [DATA TYPE] Create table for each variable with appropriate data type
        # Common data types:
        # - INTEGER: For binary (0/1) or count variables
        # - DOUBLE: For continuous or Likert scale (0-3, 0-4, etc.)
        # - BOOLEAN: For true/false variables
        # - VARCHAR: For categorical variables (rare in imputation)

{{TABLE_CREATION_STATEMENTS}}

        # Create indexes for query performance
        {{DOMAIN}}_vars = [{{VARIABLE_NAMES_QUOTED_PYTHON}}]
        for var in {{DOMAIN}}_vars:
            conn.execute(f"""
                CREATE INDEX IF NOT EXISTS idx_{table_prefix}_{var}_pid_record
                ON {table_prefix}_{var} (pid, record_id)
            """)
            conn.execute(f"""
                CREATE INDEX IF NOT EXISTS idx_{table_prefix}_{var}_imputation
                ON {table_prefix}_{var} (imputation_m)
            """)

    print(f"  [OK] Created {{N_VARIABLES}} {{DOMAIN}} tables with indexes")


def insert_{{DOMAIN}}_imputations(db: DatabaseManager, study_id: str, feather_dir: Path, n_imputations: int):
    """
    Insert {{DOMAIN}} imputations from Feather files into database

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
    print(f"\\n[INFO] Inserting {{DOMAIN}} imputations into database...")

    table_prefix = get_table_prefix(study_id)
    {{DOMAIN}}_vars = [{{VARIABLE_NAMES_QUOTED_PYTHON}}]

    total_rows_inserted = 0

    for variable in {{DOMAIN}}_vars:
        print(f"\\n[INFO] Processing {variable}...")

        # Load Feather files
        imputations = load_feather_files(feather_dir, variable, n_imputations, required=True)

        variable_rows = 0

        # Insert each imputation
        for m, df in sorted(imputations.items()):
            with db.get_connection() as conn:
                # TODO: [VALIDATION RULE] Add data type and range validation
                # Example validations:
                # - Binary: check unique values are only 0 or 1
                # - Likert 0-3: check min >= 0 and max <= 3
                # - Count: check values are non-negative integers
                #
                # if variable in ['binary_var1', 'binary_var2']:
                #     unique_vals = df[variable].unique()
                #     if not set(unique_vals).issubset({0, 1}):
                #         raise ValueError(f"Invalid binary values in {variable}: {unique_vals}")

                # Insert into table
                table_name = f"{table_prefix}_{variable}"
                df.to_sql(table_name, conn, if_exists='append', index=False)

                variable_rows += len(df)
                print(f"  [OK] Inserted {len(df)} rows for imputation m={m}")

        total_rows_inserted += variable_rows
        print(f"  [OK] Total for {variable}: {variable_rows} rows")

    print(f"\\n[OK] All {{DOMAIN}} imputations inserted: {total_rows_inserted} total rows across {{N_VARIABLES}} tables")


def update_metadata(
    db: DatabaseManager,
    study_id: str,
    variable_name: str,
    n_imputations: int,
    n_records: int,
    imputation_method: str,
    variable_type: str = "imputed"
):
    """
    Update or insert metadata for imputed/derived variable

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier (e.g., "ne25")
    variable_name : str
        Name of variable
    n_imputations : int
        Number of imputations generated
    n_records : int
        Number of records in database
    imputation_method : str
        Method used (e.g., "cart", "rf", "derived")
    variable_type : str
        "imputed" or "derived"
    """
    with db.get_connection() as conn:
        # Check if metadata exists
        exists = conn.execute(f"""
            SELECT COUNT(*) as count
            FROM imputation_metadata
            WHERE study_id = '{study_id}' AND variable_name = '{variable_name}'
        """).df()

        notes = f"{'Derived' if variable_type == 'derived' else 'Imputed'} via {{DOMAIN}} pipeline ({n_records} total records)"

        if exists['count'].iloc[0] > 0:
            # Update existing
            conn.execute(f"""
                UPDATE imputation_metadata
                SET n_imputations = {n_imputations},
                    imputation_method = '{imputation_method}',
                    created_date = CURRENT_TIMESTAMP,
                    created_by = '{{STAGE_NUMBER}}b_insert_{{DOMAIN}}.py',
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
                    '{{STAGE_NUMBER}}b_insert_{{DOMAIN}}.py',
                    '{notes}'
                )
            """)


def validate_{{DOMAIN}}_tables(db: DatabaseManager, study_id: str, n_imputations: int):
    """
    Validate {{DOMAIN}} imputation tables

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier
    n_imputations : int
        Expected number of imputations (M)
    """
    print(f"\\n[INFO] Validating {{DOMAIN}} imputation tables...")

    table_prefix = get_table_prefix(study_id)
    {{DOMAIN}}_vars = [{{VARIABLE_NAMES_QUOTED_PYTHON}}]

    with db.get_connection(read_only=True) as conn:
        for variable in {{DOMAIN}}_vars:
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

            # TODO: [VALIDATION RULE] Add domain-specific validation
            # Example patterns:
            #
            # if variable in ['binary_var1', 'binary_var2']:
            #     result = conn.execute(f"SELECT DISTINCT {variable} FROM {table_name}").fetchall()
            #     unique_vals = [row[0] for row in result]
            #     if set(unique_vals) != {0, 1}:
            #         print(f"  [WARN] {variable}: Non-binary values: {unique_vals}")
            #     else:
            #         print(f"  [OK] {variable}: Binary values (0, 1)")
            #
            # elif variable in ['likert_var1', 'likert_var2']:
            #     result = conn.execute(f"SELECT MIN({variable}), MAX({variable}) FROM {table_name}").fetchone()
            #     min_val, max_val = result[0], result[1]
            #     if min_val < 0 or max_val > 3:
            #         print(f"  [WARN] {variable}: Out of range ({min_val}-{max_val}), expected 0-3")
            #     else:
            #         print(f"  [OK] {variable}: Valid range ({min_val}-{max_val})")

    print(f"\\n[OK] Validation complete")


def main():
    """Main execution function"""
    print("=" * 60)
    print("{{DOMAIN_TITLE}} Imputation Database Insertion")
    print("=" * 60)

    # Configuration
    study_id = "{{STUDY_ID}}"
    study_config = get_study_config(study_id)
    n_imputations = 5  # TODO: [CONFIGURATION] Get from config if needed

    # Feather directory
    feather_dir = Path(study_config['data_dir']) / "{{DOMAIN}}_feather"

    print(f"\\nConfiguration:")
    print(f"  Study ID: {study_id}")
    print(f"  Feather directory: {feather_dir}")
    print(f"  Number of imputations: {n_imputations}")

    if not feather_dir.exists():
        raise FileNotFoundError(
            f"Feather directory not found: {feather_dir}\\n"
            f"Run {{DOMAIN}} imputation script first: scripts/imputation/{study_id}/{{STAGE_NUMBER}}_impute_{{DOMAIN}}.R"
        )

    # Initialize database connection
    db = DatabaseManager()

    try:
        # Step 1: Create tables
        create_{{DOMAIN}}_tables(db, study_id)

        # Step 2: Insert imputations
        insert_{{DOMAIN}}_imputations(db, study_id, feather_dir, n_imputations)

        # Step 3: Update metadata
        {{DOMAIN}}_vars = [{{VARIABLE_NAMES_QUOTED_PYTHON}}]
        for var in {{DOMAIN}}_vars:
            # TODO: [CONFIGURATION] Get row count for this variable
            # This is approximate - you may want to query the actual count
            n_rows = 0  # Placeholder
            update_metadata(db, study_id, var, n_imputations, n_rows, "{{MICE_METHOD}}")

        # Step 4: Validate tables
        validate_{{DOMAIN}}_tables(db, study_id, n_imputations)

        print("\\n" + "=" * 60)
        print("{{DOMAIN_TITLE}} Imputation Database Insertion Complete!")
        print("=" * 60)

        print("\\nNext steps:")
        print("  1. Query {{DOMAIN}} via helper functions:")
        print("     from python.imputation.helpers import get_{{DOMAIN}}_imputations")
        print("     data = get_{{DOMAIN}}_imputations(study_id='{{STUDY_ID}}', imputation_number=1)")
        print("  2. Update pipeline orchestrator to include Stage {{STAGE_NUMBER}}")
        print("  3. Update documentation")

    except Exception as e:
        print(f"\\n[ERROR] Database insertion failed: {e}")
        raise


if __name__ == "__main__":
    main()
```

---

## Variable Substitution Guide

When generating files, the agent should substitute these placeholders:

### Core Substitutions

| Placeholder | Example | Description |
|-------------|---------|-------------|
| `{{STUDY_ID}}` | `ne25` | Study identifier (lowercase) |
| `{{STUDY_ID_UPPER}}` | `NE25` | Study identifier (uppercase) |
| `{{STAGE_NUMBER}}` | `07` | Two-digit stage number |
| `{{DOMAIN}}` | `adult_health` | Domain name (lowercase, underscores) |
| `{{DOMAIN_TITLE}}` | `Adult Health` | Domain name (title case, spaces) |
| `{{MICE_METHOD}}` | `cart` | MICE imputation method |
| `{{N_VARIABLES}}` | `9` | Number of variables to impute |
| `{{N_DERIVED}}` | `2` | Number of derived variables |
| `{{N_AUXILIARY}}` | `7` | Number of auxiliary variables |

### List Substitutions

| Placeholder | Example | Description |
|-------------|---------|-------------|
| `{{VARIABLES_LIST}}` | `phq9_1, phq9_2, ..., phq9_9` | Comma-separated variable names |
| `{{VARIABLE_NAMES_QUOTED}}` | `"phq9_1", "phq9_2", "phq9_3"` | R quoted variable vector |
| `{{VARIABLE_NAMES_QUOTED_PYTHON}}` | `"phq9_1", "phq9_2", "phq9_3"` | Python quoted variable list |
| `{{EXAMPLE_VARIABLE}}` | `phq9_1` | First variable (for examples) |

### Multi-Line Substitutions

**`{{VARIABLE_DESCRIPTIONS}}`** (R comment format):
```r
#   - phq9_1 (cart) - Little interest or pleasure (0-3 scale)
#   - phq9_2 (cart) - Feeling down/depressed (0-3 scale)
#   - phq9_3 (cart) - Trouble sleeping (0-3 scale)
```

**`{{PYTHON_VARIABLE_DESCRIPTIONS}}`** (Python comment format):
```python
# - phq9_1: DOUBLE (Little interest or pleasure, 0-3 scale)
# - phq9_2: DOUBLE (Feeling down/depressed, 0-3 scale)
# - phq9_3: DOUBLE (Trouble sleeping, 0-3 scale)
```

**`{{SELECT_VARIABLES}}`** (SQL SELECT format):
```sql
      phq9_1,
      phq9_2,
      phq9_3,
      phq9_4,
```

**`{{TABLE_CREATION_STATEMENTS}}`** (SQL DDL format):
```python
        # phq9_1 (DOUBLE - 0-3 Likert scale)
        # TODO: [DATA TYPE] Verify DOUBLE is appropriate for phq9_1
        conn.execute(f"""
            DROP TABLE IF EXISTS {table_prefix}_phq9_1
        """)
        conn.execute(f"""
            CREATE TABLE {table_prefix}_phq9_1 (
                study_id VARCHAR NOT NULL,
                pid INTEGER NOT NULL,
                record_id INTEGER NOT NULL,
                imputation_m INTEGER NOT NULL,
                phq9_1 DOUBLE NOT NULL,
                PRIMARY KEY (study_id, pid, record_id, imputation_m)
            )
        """)
```

### Data Type Mapping

Map user-specified data types to SQL types:

| User Input | SQL Type | Use Case |
|------------|----------|----------|
| `"0-3 likert"`, `"0-4 likert"` | `DOUBLE` | Ordinal scales |
| `"continuous"`, `"numeric"` | `DOUBLE` | Continuous variables |
| `"binary"`, `"0/1"` | `INTEGER` | Binary indicators |
| `"count"`, `"integer"` | `INTEGER` | Count variables |
| `"boolean"`, `"true/false"` | `BOOLEAN` | Boolean flags |
| `"categorical"`, `"factor"` | `VARCHAR` | Categorical (rare) |

---

## TODO Marker Examples

### Example 1: Predictor Matrix Configuration

```r
# TODO: [DOMAIN LOGIC] Configure predictor matrix
#
# Decision points:
# 1. Which auxiliary variables should predict phq9_1?
#    Available: puma (geography), raceG, income, educ_a1 (sociodem),
#               age_in_days, female (demographics), authentic.x (quality)
#
# 2. Should PHQ-9 items predict each other?
#    - Pros: Items are related (depression construct), may improve imputation
#    - Cons: Could introduce circularity if relationships are too strong
#    - Common practice: Include for mental health scales
#
# 3. Review correlation matrix:
#    Run this before finalizing: cor(dat_m[, c(imp_vars, aux_vars)], use="pairwise.complete.obs")
#
# Resources:
# - Similar implementation: scripts/imputation/ne25/05_impute_adult_mental_health.R (lines 524-545)
# - Theory: PHQ-9 items typically correlate 0.5-0.7 with each other
#
for (var in imp_vars) {
  predictor_matrix[var, aux_vars_existing] <- 1  # Use auxiliary variables
  predictor_matrix[var, setdiff(imp_vars, var)] <- 1  # TODO: Use other PHQ-9 items?
}
```

### Example 2: MICE Method Selection

```r
# TODO: [STATISTICAL DECISION] Verify MICE method is appropriate
#
# Current method: cart (classification and regression trees)
#
# Considerations for PHQ-9 items (0-3 ordinal):
# 1. Variable type: Ordinal (0-3 scale)
#    - cart: ✅ Handles ordinal data well
#    - rf: ✅ Also good, but slower
#    - pmm: ✅ Preserves distribution
#    - polr: Could use for ordinal, but more assumptions
#
# 2. Sample size: N = {{N}} after filtering
#    - cart: ✅ Works with moderate N
#    - rf: Needs larger N (rule of thumb: 10*p obs per tree)
#
# 3. Assumptions:
#    - cart: ✅ No distributional assumptions
#    - Handles non-linearity and interactions automatically
#
# 4. Computational cost:
#    - cart: Fast (good for 9 variables × 5 imputations)
#    - rf: Slower but may not add much for simple scales
#
# Recommendation: cart is appropriate for PHQ-9 given ordinal nature
# and moderate sample size. Consider rf if N > 1000 and you suspect
# complex interactions.
#
method_vector[var] <- "cart"  # TODO: Confirm based on analysis
```

### Example 3: Validation Rule

```python
# TODO: [VALIDATION RULE] Add value range validation for phq9_total
#
# Expected properties:
# - Range: 0-27 (sum of 9 items, each 0-3)
# - Distribution: Right-skewed (most people low scores)
# - Missing: Should be imputed for any record where ANY PHQ-9 item was missing
#
# Common issues to check:
# - Values > 27: Summation error
# - Values < 0: Invalid imputation
# - All values = 0: Imputation failed
# - Strange distribution: Check for systematically wrong imputations
#
# Example validation:
if variable == "phq9_total":
    # Check range
    result = conn.execute(f"SELECT MIN({variable}), MAX({variable}) FROM {table_name}").fetchone()
    min_val, max_val = result[0], result[1]
    if min_val < 0 or max_val > 27:
        print(f"  [ERROR] {variable}: Invalid range ({min_val}-{max_val}), expected 0-27")
    else:
        print(f"  [OK] {variable}: Valid range ({min_val}-{max_val})")

    # Check distribution
    result = conn.execute(f"SELECT AVG({variable}), STDDEV({variable}) FROM {table_name}").fetchone()
    mean_val, std_val = result[0], result[1]
    print(f"  [INFO] {variable}: mean={mean_val:.2f}, sd={std_val:.2f}")
    if mean_val > 15:  # Unusually high for general population
        print(f"  [WARN] {variable}: Mean is unusually high - check imputation")
```

---

**For usage, see:** `docs/imputation/ADDING_IMPUTATION_STAGES.md`

*Last Updated: October 2025 | Version: 1.0.0*
