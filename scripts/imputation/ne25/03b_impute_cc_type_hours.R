# Childcare Stage 2: Conditional Imputation of cc_primary_type and cc_hours_per_week
#
# Generates M=5 imputations for childcare type and hours using CART method.
# ONLY imputes for records where cc_receives_care = "Yes" (from Stage 1).
#
# Usage:
#   Rscript scripts/imputation/ne25/03b_impute_cc_type_hours.R
#
# Variables Imputed:
#   - cc_primary_type (CART) - Type of primary childcare provider (6 categories)
#   - cc_hours_per_week (CART) - Hours per week in childcare (continuous, 0-168)
#
# Conditional Logic:
#   - Load completed cc_receives_care from Stage 1
#   - Filter to ONLY records with cc_receives_care = "Yes"
#   - Impute type and hours for this filtered subset
#   - Records with cc_receives_care = "No" are skipped (type/hours remain NULL)
#
# Auxiliary Variables (9 total):
#   - puma (from geography imputation m)
#   - female, raceG, educ_mom, educ_a2, income, family_size, fplcat (from sociodem imputation m)
#   - cc_receives_care (from Stage 1 imputation m)

# =============================================================================
# SETUP
# =============================================================================

cat("Childcare Stage 2: Conditional Imputation of Type and Hours\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

# Load safe join utilities
source("R/utils/safe_joins.R")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

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
cat("  Variables to impute: cc_primary_type, cc_hours_per_week\n")
cat("  Method: CART (both variables)\n")
cat("  Conditional: Only for cc_receives_care = 'Yes'\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load completed cc_receives_care from Stage 1 Feather files
#'
#' @param feather_dir Path to childcare Feather directory
#' @param m Integer, imputation number (1 to M)
#'
#' @return data.frame with completed cc_receives_care for imputation m
load_cc_receives_care_imputation <- function(feather_dir, m) {
  cat(sprintf("\n[INFO] Loading cc_receives_care imputation m=%d...\n", m))

  # Load imputed values from Feather
  feather_path <- file.path(feather_dir, sprintf("cc_receives_care_m%d.feather", m))

  if (!file.exists(feather_path)) {
    stop(sprintf("Feather file not found: %s\nRun 03a_impute_cc_receives_care.R first", feather_path))
  }

  cc_receives_imp <- arrow::read_feather(feather_path)

  cat(sprintf("  [OK] Loaded %d imputed cc_receives_care values\n", nrow(cc_receives_imp)))

  return(cc_receives_imp)
}


#' Load base childcare data from DuckDB (type and hours)
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to eligible == TRUE
#'
#' @return data.frame with base childcare type and hours data
load_base_childcare_type_hours <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base childcare type/hours data from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Build query
  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      'ne25' as study_id,

      -- Variables to impute
      cc_primary_type,
      cc_hours_per_week,

      -- Also get cc_receives_care (observed values)
      cc_receives_care,

      -- Auxiliary variables (complete or mostly complete)
      age_in_days,
      consent_date,

      -- Eligibility flag
      \"eligible\"

    FROM ne25_transformed
  "

  if (eligible_only) {
    query <- paste0(query, "\n    WHERE meets_inclusion = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  cat("  [OK] Loaded", nrow(dat), "records\n")

  # =============================================================================
  # DATA CLEANING: Cap cc_hours_per_week at 168 hours/week (max possible)
  # =============================================================================
  # This prevents impossible values from being used as donors during mice PMM
  # Root cause: 1 observed record has cc_hours_per_week = 15000 (likely typo)
  # Without cleaning, mice uses this as a donor and propagates to other records

  if (any(!is.na(dat$cc_hours_per_week) & dat$cc_hours_per_week > 168)) {
    n_outliers <- sum(!is.na(dat$cc_hours_per_week) & dat$cc_hours_per_week > 168, na.rm = TRUE)
    max_value <- max(dat$cc_hours_per_week[!is.na(dat$cc_hours_per_week) & dat$cc_hours_per_week > 168])

    cat(sprintf("  [WARN] Found %d record(s) with cc_hours_per_week > 168 (max = %.0f)\n",
                n_outliers, max_value))
    cat("  [INFO] Setting outlier values to NA (will be imputed with plausible values)\n")

    # Set impossible values to NA so mice can impute plausible values
    dat$cc_hours_per_week[!is.na(dat$cc_hours_per_week) & dat$cc_hours_per_week > 168] <- NA
  }

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


#' Merge base data with completed imputations and filter to cc_receives_care = "Yes"
#'
#' @param base_data data.frame with base childcare type/hours data
#' @param puma_imp data.frame with PUMA imputation
#' @param sociodem_imp data.frame with sociodem imputations
#' @param cc_receives_imp data.frame with cc_receives_care imputation
#' @param db_path Path to DuckDB database
#'
#' @return data.frame with merged data, filtered to cc_receives_care = "Yes"
merge_and_filter_data <- function(base_data, puma_imp, sociodem_imp, cc_receives_imp, db_path) {
  cat("\n[INFO] Merging and filtering data...\n")

  # Merge PUMA
  dat_merged <- base_data %>%
    safe_left_join(puma_imp, by_vars = c("pid", "record_id"))

  # Fill missing PUMA from ne25_transformed (for records without geography ambiguity)
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

  # Fill missing sociodem from ne25_transformed
  sociodem_vars <- c("female", "raceG", "educ_mom", "educ_a2", "income", "family_size", "fplcat")

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

  # Merge cc_receives_care imputation (this adds completed values for originally missing)
  dat_merged <- dat_merged %>%
    safe_left_join(
      cc_receives_imp %>% dplyr::select(pid, record_id, cc_receives_care_imp = cc_receives_care),
      by_vars = c("pid", "record_id")
    )

  # Use imputed cc_receives_care if observed is missing
  dat_merged <- dat_merged %>%
    dplyr::mutate(
      cc_receives_care = ifelse(is.na(cc_receives_care), cc_receives_care_imp, cc_receives_care)
    ) %>%
    dplyr::select(-cc_receives_care_imp)

  # Fill remaining missing cc_receives_care from ne25_transformed (for observed values)
  if (any(is.na(dat_merged$cc_receives_care))) {
    con_cc <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con_cc, shutdown = FALSE), add = TRUE)

    cc_observed <- DBI::dbGetQuery(con_cc, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        CAST(cc_receives_care AS VARCHAR) as cc_receives_care_observed
      FROM ne25_transformed
    ")

    dat_merged <- dat_merged %>%
      safe_left_join(cc_observed, by_vars = c("pid", "record_id")) %>%
      dplyr::mutate(
        cc_receives_care = ifelse(
          is.na(cc_receives_care),
          as.character(cc_receives_care_observed) == "Yes",  # Convert observed to boolean
          cc_receives_care
        )
      ) %>%
      dplyr::select(-cc_receives_care_observed)
  }

  # CRITICAL FIX: Ensure cc_receives_care is boolean (TRUE/FALSE)
  dat_merged$cc_receives_care <- as.logical(dat_merged$cc_receives_care)

  cat(sprintf("  [OK] Merged data: %d records before filtering\n", nrow(dat_merged)))

  # CRITICAL: Filter to ONLY records with cc_receives_care = TRUE
  dat_filtered <- dat_merged %>%
    dplyr::filter(cc_receives_care == TRUE)

  cat(sprintf("  [OK] Filtered to cc_receives_care = TRUE: %d records\n", nrow(dat_filtered)))

  return(dat_filtered)
}


#' Save childcare type/hours imputations to Feather
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
save_type_hours_feather <- function(completed_data, original_data, m, output_dir) {
  cat(sprintf("\n[INFO] Saving type/hours imputations m=%d to Feather...\n", m))

  # Save cc_primary_type (only originally missing)
  originally_missing_type <- is.na(original_data$cc_primary_type)

  if (sum(originally_missing_type) > 0) {
    imputed_type <- completed_data[originally_missing_type, c("study_id", "pid", "record_id", "cc_primary_type")]
    imputed_type$imputation_m <- m

    # FILTER OUT records where imputation failed (value still NA)
    # This happens for records with missing predictor variables (e.g., no geography, sociodem)
    successfully_imputed_type <- !is.na(imputed_type$cc_primary_type)
    imputed_type <- imputed_type[successfully_imputed_type, ]

    if (nrow(imputed_type) > 0) {
      imputed_type <- imputed_type[, c("study_id", "pid", "record_id", "imputation_m", "cc_primary_type")]

      type_path <- file.path(output_dir, sprintf("cc_primary_type_m%d.feather", m))
      arrow::write_feather(imputed_type, type_path)

      cat(sprintf("  [OK] cc_primary_type: %d values -> %s\n", nrow(imputed_type), basename(type_path)))
    } else {
      cat("  [WARN] cc_primary_type: No successfully imputed values\n")
    }
  } else {
    cat("  [INFO] cc_primary_type: No missing values to impute\n")
  }

  # Save cc_hours_per_week (only originally missing)
  originally_missing_hours <- is.na(original_data$cc_hours_per_week)

  if (sum(originally_missing_hours) > 0) {
    imputed_hours <- completed_data[originally_missing_hours, c("study_id", "pid", "record_id", "cc_hours_per_week")]
    imputed_hours$imputation_m <- m

    # FILTER OUT records where imputation failed (value still NA)
    # This happens for records with missing predictor variables (e.g., no geography, sociodem)
    successfully_imputed_hours <- !is.na(imputed_hours$cc_hours_per_week)
    imputed_hours <- imputed_hours[successfully_imputed_hours, ]

    if (nrow(imputed_hours) > 0) {
      imputed_hours <- imputed_hours[, c("study_id", "pid", "record_id", "imputation_m", "cc_hours_per_week")]

      hours_path <- file.path(output_dir, sprintf("cc_hours_per_week_m%d.feather", m))
      arrow::write_feather(imputed_hours, hours_path)

      cat(sprintf("  [OK] cc_hours_per_week: %d values -> %s\n", nrow(imputed_hours), basename(hours_path)))
    } else {
      cat("  [WARN] cc_hours_per_week: No successfully imputed values\n")
    }
  } else {
    cat("  [INFO] cc_hours_per_week: No missing values to impute\n")
  }

  return(invisible(NULL))
}

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Childcare Stage 2 Conditional Imputation\n")
cat(strrep("=", 60), "\n")

# Setup study-specific directories
feather_dir <- file.path(study_config$data_dir, "childcare_feather")
if (!dir.exists(feather_dir)) {
  stop("Feather directory not found. Run 03a_impute_cc_receives_care.R first")
}

db_path <- config$database$db_path

# Load base data once
base_data <- load_base_childcare_type_hours(db_path, eligible_only = TRUE)

# Check missing data in full dataset (before filtering)
n_missing_type <- sum(is.na(base_data$cc_primary_type))
n_missing_hours <- sum(is.na(base_data$cc_hours_per_week))
cat(sprintf("\nMissing data (all eligible records):\n"))
cat(sprintf("  cc_primary_type: %d missing\n", n_missing_type))
cat(sprintf("  cc_hours_per_week: %d missing\n", n_missing_hours))

# LOOP OVER IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load cc_receives_care imputation from Stage 1
  cc_receives_m <- load_cc_receives_care_imputation(feather_dir, m)

  # Step 2: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 3: Load sociodem imputations m
  sociodem_m <- load_sociodem_imputations(db_path, m)

  # Step 4: Merge all data and filter to cc_receives_care = "Yes"
  dat_m <- merge_and_filter_data(base_data, puma_m, sociodem_m, cc_receives_m, db_path)

  # Check if we have any records to impute after filtering
  if (nrow(dat_m) == 0) {
    cat("\n[WARN] No records with cc_receives_care = 'Yes'. Skipping imputation.\n")
    next
  }

  # Step 5: Prepare data for mice
  # Variables: cc_primary_type, cc_hours_per_week (to impute) + 11 auxiliary variables
  imp_vars <- c("cc_primary_type", "cc_hours_per_week")
  aux_vars <- c("puma", "authentic", "age_in_days", "female", "raceG", "educ_mom", "educ_a2",
                "income", "family_size", "fplcat", "cc_receives_care")

  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables actually exist in dat_m
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\n[WARN] Missing columns (will skip): %s\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Check missing data in filtered subset
  missing_counts <- sapply(dat_mice[imp_vars], function(x) sum(is.na(x)))
  cat("\nMissing data in cc_receives_care = 'Yes' subset:\n")
  for (var in names(missing_counts)) {
    pct_missing <- 100 * missing_counts[var] / nrow(dat_mice)
    cat(sprintf("  %s: %d (%.1f%%)\n", var, missing_counts[var], pct_missing))
  }

  # Step 6: Configure mice
  # Set up predictor matrix
  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # cc_primary_type uses all auxiliary variables
  predictor_matrix["cc_primary_type", ] <- 0
  predictor_matrix["cc_primary_type", aux_vars_existing] <- 1
  predictor_matrix["cc_primary_type", "cc_hours_per_week"] <- 1  # Can also use hours

  # cc_hours_per_week uses all auxiliary variables + cc_primary_type
  predictor_matrix["cc_hours_per_week", ] <- 0
  predictor_matrix["cc_hours_per_week", aux_vars_existing] <- 1
  predictor_matrix["cc_hours_per_week", "cc_primary_type"] <- 1

  # Auxiliary variables are NOT imputed
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  method_vector["cc_primary_type"] <- "cart"
  method_vector["cc_hours_per_week"] <- "cart"

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations: 5\n")
  cat("  Methods: CART (both variables)\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\n")

  # Step 7: Run mice
  cat("\n[INFO] Running mice imputation...\n")

  set.seed(seed + m)

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

  # Step 8: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 9: Save to Feather (only originally missing values)
  save_type_hours_feather(completed_m, dat_m, m, feather_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Childcare Stage 2 Conditional Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variables imputed: cc_primary_type, cc_hours_per_week\n"))
cat(sprintf("  Method: CART (both variables)\n"))
cat(sprintf("  Conditional filter: cc_receives_care = 'Yes' only\n"))
cat(sprintf("  Output directory: %s\n", feather_dir))

cat("\nNext steps:\n")
cat("  1. Run: Rscript scripts/imputation/ne25/03c_derive_childcare_10hrs.R\n")
cat(strrep("=", 60), "\n")
