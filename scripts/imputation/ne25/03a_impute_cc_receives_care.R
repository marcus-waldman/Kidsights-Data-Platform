# Childcare Stage 1: Impute cc_receives_care for NE25
#
# Generates M=5 imputations for cc_receives_care (Yes/No) using CART method.
# Uses chained imputation approach where each mice run uses geography + sociodem
# from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/ne25/03a_impute_cc_receives_care.R
#
# Variable Imputed:
#   - cc_receives_care (CART) - Does child receive any childcare? (Yes/No)
#
# Auxiliary Variables (10 total):
#   - puma (from geography imputation m)
#   - age_in_days (from base data)
#   - female, raceG, educ_mom, educ_a2, income, family_size, fplcat (from sociodem imputation m)

# =============================================================================
# SETUP
# =============================================================================

cat("Childcare Stage 1: Impute cc_receives_care for NE25\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

# Load safe join utilities
source("R/utils/safe_joins.R")

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
if (!requireNamespace("reticulate", quietly = TRUE)) {
  stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
}

# Source configuration
source("R/utils/environment_config.R")
source("R/imputation/config.R")

# Configure reticulate to use .env Python executable
python_path <- get_python_path()
reticulate::use_python(python_path, required = TRUE)

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

study_id <- "ne25"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

cat("\nConfiguration:\n")
cat("  Study ID:", study_id, "\n")
cat("  Study Name:", study_config$study_name, "\n")
cat("  Number of imputations (M):", config$n_imputations, "\n")
cat("  Random seed:", config$random_seed, "\n")
cat("  Data directory:", study_config$data_dir, "\n")
cat("  Variable to impute: cc_receives_care\n")
cat("  Method: CART\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base childcare data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to meets_inclusion == TRUE
#'
#' @return data.frame with base childcare data
load_base_childcare_data <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base childcare data from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Build query
  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      'ne25' as study_id,

      -- Variable to impute
      cc_receives_care,

      -- Auxiliary variables (complete or mostly complete)
      age_in_days,
      consent_date,

      -- Eligibility flag
      eligible

    FROM ne25_transformed
  "

  if (eligible_only) {
    query <- paste0(query, "\n    WHERE meets_inclusion = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  cat("  [OK] Loaded", nrow(dat), "records\n")

  return(dat)
}


#' Load PUMA imputation from database
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with PUMA for imputation m
load_puma_imputation <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading PUMA imputation m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  puma_query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      puma
    FROM ne25_imputed_puma
    WHERE imputation_m = %d AND study_id = '%s'
  ", m, study_id)

  puma_imp <- DBI::dbGetQuery(con, puma_query)

  cat(sprintf("  [OK] Loaded %d PUMA imputations\n", nrow(puma_imp)))

  return(puma_imp)
}


#' Load sociodemographic imputations from database
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with 7 sociodem variables for imputation m
load_sociodem_imputations <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading sociodem imputations m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # List of sociodem variables to load
  sociodem_vars <- c("female", "raceG", "educ_mom", "educ_a2", "income", "family_size", "fplcat")

  # Load each variable and merge
  sociodem_data <- NULL

  for (var in sociodem_vars) {
    table_name <- paste0(study_id, "_imputed_", var)

    var_query <- sprintf("
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        %s
      FROM %s
      WHERE imputation_m = %d AND study_id = '%s'
    ", var, table_name, m, study_id)

    var_imp <- DBI::dbGetQuery(con, var_query)

    if (is.null(sociodem_data)) {
      sociodem_data <- var_imp
    } else {
      sociodem_data <- safe_left_join(sociodem_data, var_imp, by_vars = c("pid", "record_id"))
    }
  }

  cat(sprintf("  [OK] Loaded %d sociodem variable imputations\n", length(sociodem_vars)))

  return(sociodem_data)
}


#' Merge base data with geography and sociodem imputations
#'
#' @param base_data data.frame with base childcare data
#' @param puma_imp data.frame with PUMA imputation
#' @param sociodem_imp data.frame with sociodem imputations
#' @param db_path Path to DuckDB database (for filling observed PUMA if missing)
#'
#' @return data.frame with merged data
merge_imputed_data <- function(base_data, puma_imp, sociodem_imp, db_path) {
  cat("\n[INFO] Merging base data with imputations...\n")

  # Merge PUMA
  dat_merged <- base_data %>%
    safe_left_join(puma_imp, by_vars = c("pid", "record_id"))

  # For records without geography ambiguity, fill from ne25_transformed
  if (any(is.na(dat_merged$puma))) {
    con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

    geo_observed <- DBI::dbGetQuery(con, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        puma as puma_observed
      FROM ne25_transformed
    ")

    dat_merged <- dat_merged %>%
      safe_left_join(geo_observed, by_vars = c("pid", "record_id")) %>%
      dplyr::mutate(puma = ifelse(is.na(puma), puma_observed, puma)) %>%
      dplyr::select(-puma_observed)
  }

  # Merge sociodem imputations
  dat_merged <- dat_merged %>%
    safe_left_join(sociodem_imp, by_vars = c("pid", "record_id"))

  # Fill missing sociodem values from ne25_transformed (for records with observed values)
  sociodem_vars <- c("female", "raceG", "educ_mom", "educ_a2", "income", "family_size", "fplcat")

  # Create single connection for all sociodem variables
  has_missing_sociodem <- any(sapply(sociodem_vars, function(v) any(is.na(dat_merged[[v]]))))

  if (has_missing_sociodem) {
    con_sociodem <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con_sociodem, shutdown = FALSE), add = TRUE)

    for (var in sociodem_vars) {
      if (any(is.na(dat_merged[[var]]))) {
        query <- sprintf("
          SELECT
            CAST(pid AS INTEGER) as pid,
            CAST(record_id AS INTEGER) as record_id,
            %s as %s_observed
          FROM ne25_transformed
        ", var, var)

        var_observed <- DBI::dbGetQuery(con_sociodem, query)

        dat_merged <- dat_merged %>%
          safe_left_join(var_observed, by_vars = c("pid", "record_id")) %>%
          dplyr::mutate(!!var := ifelse(is.na(.data[[var]]), .data[[paste0(var, "_observed")]], .data[[var]])) %>%
          dplyr::select(-!!paste0(var, "_observed"))
      }
    }
  }

  cat(sprintf("  [OK] Merged data: %d records with %d columns\n", nrow(dat_merged), ncol(dat_merged)))

  return(dat_merged)
}


#' Save cc_receives_care imputation to Feather
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
save_cc_receives_care_feather <- function(completed_data, original_data, m, output_dir) {
  cat(sprintf("\n[INFO] Saving cc_receives_care imputation m=%d to Feather...\n", m))

  # Save ONLY originally-missing records (space-efficient design)
  # Matches sociodem pattern: only store imputed values, not observed values
  # Helper functions use COALESCE(imputed, observed) to merge at query time
  originally_missing <- is.na(original_data$cc_receives_care)

  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", "cc_receives_care")]
  imputed_records$imputation_m <- m

  # FILTER OUT records where imputation failed (value still NA)
  # This happens for records with missing predictor variables (e.g., no geography, sociodem)
  successfully_imputed <- !is.na(imputed_records$cc_receives_care)
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\n", n_null_filtered))
  }

  if (nrow(imputed_records) > 0) {
    # Reorder columns: study_id, pid, record_id, imputation_m, cc_receives_care
    imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", "cc_receives_care")]

    # Save to Feather file
    output_path <- file.path(output_dir, sprintf("cc_receives_care_m%d.feather", m))
    arrow::write_feather(imputed_records, output_path)

    cat(sprintf("  [OK] cc_receives_care: %d values -> %s\n", nrow(imputed_records), basename(output_path)))
  } else {
    cat(sprintf("  [WARN] cc_receives_care: No imputed values to save\n"))
  }

  return(invisible(NULL))
}

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Childcare Stage 1 Imputation\n")
cat(strrep("=", 60), "\n")

# Setup study-specific output directory
output_dir <- file.path(study_config$data_dir, "childcare_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\n")
}

# Load base data once
db_path <- config$database$db_path
base_data <- load_base_childcare_data(db_path, eligible_only = TRUE)

# Check missing data
n_missing <- sum(is.na(base_data$cc_receives_care))
pct_missing <- 100 * n_missing / nrow(base_data)
cat(sprintf("\nMissing cc_receives_care: %d of %d (%.1f%%)\n", n_missing, nrow(base_data), pct_missing))

# LOOP OVER GEOGRAPHY/SOCIODEM IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load sociodem imputations m
  sociodem_m <- load_sociodem_imputations(db_path, m)

  # Step 3: Merge all data
  dat_m <- merge_imputed_data(base_data, puma_m, sociodem_m, db_path)

  # Step 4: Prepare data for mice
  # Variables: cc_receives_care (to impute) + 10 auxiliary variables
  imp_vars <- c("cc_receives_care")
  aux_vars <- c("puma", "authentic", "age_in_days", "female", "raceG", "educ_mom", "educ_a2", "income", "family_size", "fplcat")

  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables actually exist in dat_m
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\n[WARN] Missing columns (will skip): %s\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Step 5: Configure mice
  # Set up predictor matrix (which variables predict which)
  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  # Get auxiliary variables that actually exist in the data
  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # cc_receives_care can use all auxiliary variables as predictors
  predictor_matrix["cc_receives_care", ] <- 0  # Reset row
  predictor_matrix["cc_receives_care", aux_vars_existing] <- 1

  # Auxiliary variables are NOT imputed (use complete cases or pre-imputed)
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  method_vector["cc_receives_care"] <- "cart"

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations: 5\n")
  cat("  Method: CART\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\n")

  # Step 6: Run mice
  cat("\n[INFO] Running mice imputation...\n")

  set.seed(seed + m)  # Unique seed for each imputation

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

  # Step 7b: Convert cc_receives_care to boolean (TRUE = "Yes", FALSE = "No")
  completed_m$cc_receives_care <- as.character(completed_m$cc_receives_care) == "Yes"

  # Step 8: Save to Feather (only originally-missing records)
  save_cc_receives_care_feather(completed_m, dat_m, m, output_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Childcare Stage 1 Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variable imputed: cc_receives_care\n"))
cat(sprintf("  Method: CART\n"))
cat(sprintf("  Records with missing cc_receives_care: %d (%.1f%%)\n", n_missing, pct_missing))
cat(sprintf("  Output directory: %s\n", output_dir))

cat("\nNext steps:\n")
cat("  1. Run: Rscript scripts/imputation/ne25/03b_impute_cc_type_hours.R\n")
cat(strrep("=", 60), "\n")
