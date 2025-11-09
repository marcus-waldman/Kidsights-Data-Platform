# Adult Mental Health & Parenting Stage: Impute PHQ-2, GAD-2, and q1502 for NE25
#
# Generates M=5 imputations for adult mental health screening items (PHQ-2, GAD-2)
# and parenting self-efficacy (q1502) using CART method.
# Uses chained imputation approach where each mice run uses geography + sociodem
# from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/ne25/05_impute_adult_mental_health.R
#
# Variables Imputed (5 total):
#   - phq2_interest (CART) - Little interest or pleasure (0-3 scale)
#   - phq2_depressed (CART) - Feeling down/depressed (0-3 scale)
#   - gad2_nervous (CART) - Feeling nervous/anxious (0-3 scale)
#   - gad2_worry (CART) - Unable to stop worrying (0-3 scale)
#   - q1502 (CART) - Handling day-to-day demands of raising children (0-3 scale)
#
# Derived Variables (2 total, computed after imputation):
#   - phq2_positive - PHQ-2 positive screen (sum >= 3)
#   - gad2_positive - GAD-2 positive screen (sum >= 3)
#
# Auxiliary Variables (7 total):
#   - puma (from geography imputation m)
#   - a1_raceG, educ_a1, income (from sociodem imputation m if imputed, else base)
#   - authentic (from base data, also used as defensive filter)
#   - female_a1, a1_years_old (from base data)

# =============================================================================
# SETUP
# =============================================================================

cat("Adult Mental Health & Parenting Imputation for NE25\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(arrow)

# Load safe join utilities
source("R/utils/safe_joins.R")

cat("Adult Mental Health & Parenting: Impute PHQ-2, GAD-2, q1502 for NE25\n")
cat(strrep("=", 60), "\n")

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
cat("  Variables to impute: phq2_interest, phq2_depressed, gad2_nervous, gad2_worry, q1502\n")
cat("  Method: CART (all 5 variables)\n")
cat("  Defensive filtering: meets_inclusion = TRUE\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base mental health data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to meets_inclusion == TRUE
#'
#' @return data.frame with base mental health data
load_base_mental_health_data <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base mental health data from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Build query
  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      'ne25' as study_id,

      -- Variables to impute (5 total)
      phq2_interest,
      phq2_depressed,
      gad2_nervous,
      gad2_worry,
      q1502,

      -- Derived positive screens (for tracking which records need derivation)
      phq2_positive,
      gad2_positive,

      -- Auxiliary variables (complete or mostly complete)
      \"authentic\",
      age_in_days,
      consent_date,

      -- Adult predictors from base data
      female_a1,
      a1_years_old,

      -- Eligibility flag
      \"eligible\"

    FROM ne25_transformed
  "

  if (eligible_only) {
    # DEFENSIVE FILTERING: meets_inclusion (eligible with non-NA authenticity_weight)
    query <- paste0(query, "\n    WHERE meets_inclusion = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  cat("  [OK] Loaded", nrow(dat), "records (defensive filtering applied)\n")

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


#' Load sociodemographic imputations for mental health imputation
#'
#' Loads a1_raceG, educ_a1, income from imputed tables if they exist.
#' For records without imputations (observed values), will fall back to base data.
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with adult sociodem variables for imputation m
load_sociodem_imputations_for_mental_health <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading sociodem imputations m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Adult sociodem variables (may or may not be imputed)
  # NOTE: a1_raceG and educ_a1 may not be in imputed tables if they were complete in base data
  sociodem_vars <- c("income")  # income is always imputed
  adult_vars <- c("a1_raceG", "educ_a1")  # May be imputed or observed

  # Load income (always imputed)
  income_query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      income
    FROM ne25_imputed_income
    WHERE imputation_m = %d AND study_id = '%s'
  ", m, study_id)

  sociodem_data <- DBI::dbGetQuery(con, income_query)

  # Try to load a1_raceG and educ_a1 from imputed tables
  # If tables don't exist or records missing, will fill from base data later
  for (var in adult_vars) {
    table_name <- paste0(study_id, "_imputed_", var)

    # Check if table exists
    table_exists_query <- sprintf("
      SELECT COUNT(*) as n
      FROM information_schema.tables
      WHERE table_name = '%s'
    ", table_name)

    table_exists <- DBI::dbGetQuery(con, table_exists_query)$n > 0

    if (table_exists) {
      var_query <- sprintf("
        SELECT
          CAST(pid AS INTEGER) as pid,
          CAST(record_id AS INTEGER) as record_id,
          \"%s\"
        FROM %s
        WHERE imputation_m = %d AND study_id = '%s'
      ", var, table_name, m, study_id)

      var_imp <- DBI::dbGetQuery(con, var_query)

      if (nrow(var_imp) > 0) {
        sociodem_data <- safe_left_join(sociodem_data, var_imp, by_vars = c("pid", "record_id"))
      }
    }
  }

  cat(sprintf("  [OK] Loaded sociodem variable imputations\n"))

  return(sociodem_data)
}


#' Merge base data with geography and sociodem imputations
#'
#' @param base_data data.frame with base mental health data
#' @param puma_imp data.frame with PUMA imputation
#' @param sociodem_imp data.frame with sociodem imputations
#' @param db_path Path to DuckDB database (for filling observed values if missing)
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
      WHERE meets_inclusion = TRUE
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
  sociodem_vars <- c("a1_raceG", "educ_a1", "income")

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
            \"%s\" as %s_observed
          FROM ne25_transformed
          WHERE meets_inclusion = TRUE
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


#' Save mental health imputation to Feather (single variable)
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#' @param variable_name Character, name of variable to save
#'
#' @return Invisible NULL
save_mental_health_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  cat(sprintf("\n[INFO] Saving %s imputation m=%d to Feather...\n", variable_name, m))

  # Save ONLY originally-missing records (space-efficient design)
  originally_missing <- is.na(original_data[[variable_name]])

  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", variable_name)]
  imputed_records$imputation_m <- m

  # DEFENSIVE FILTERING: Remove records where imputation failed (value still NA)
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\n", n_null_filtered))
  }

  if (nrow(imputed_records) > 0) {
    # Reorder columns: study_id, pid, record_id, imputation_m, [variable]
    imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", variable_name)]

    # Save to Feather file
    output_path <- file.path(output_dir, sprintf("%s_m%d.feather", variable_name, m))
    arrow::write_feather(imputed_records, output_path)

    cat(sprintf("  [OK] %s: %d values -> %s\n", variable_name, nrow(imputed_records), basename(output_path)))
  } else {
    cat(sprintf("  [WARN] %s: No imputed values to save\n", variable_name))
  }

  return(invisible(NULL))
}


#' Derive and save positive screening indicators (phq2_positive, gad2_positive)
#'
#' @param completed_data data.frame with completed PHQ-2/GAD-2 items
#' @param base_data data.frame with base data to identify which records need derivation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
derive_positive_screens <- function(completed_data, base_data, m, output_dir) {
  cat(sprintf("\n[INFO] Deriving positive screening indicators for m=%d...\n", m))

  # Calculate PHQ-2 total and positive screen (>= 3)
  completed_data$phq2_total <- completed_data$phq2_interest + completed_data$phq2_depressed
  completed_data$phq2_positive <- completed_data$phq2_total >= 3

  # Calculate GAD-2 total and positive screen (>= 3)
  completed_data$gad2_total <- completed_data$gad2_nervous + completed_data$gad2_worry
  completed_data$gad2_positive <- completed_data$gad2_total >= 3

  # Report prevalence (for all completed records)
  phq2_prev <- 100 * mean(completed_data$phq2_positive, na.rm = TRUE)
  gad2_prev <- 100 * mean(completed_data$gad2_positive, na.rm = TRUE)

  cat(sprintf("  PHQ-2+ prevalence (all completed): %.1f%%\n", phq2_prev))
  cat(sprintf("  GAD-2+ prevalence (all completed): %.1f%%\n", gad2_prev))

  # CRITICAL FIX: Only save records where base phq2_positive was NULL
  # This matches the imputation storage convention used throughout the platform
  # where we only store values that needed imputation, not observed values

  # Create identifier for base records with NULL phq2_positive
  base_null_phq2 <- base_data[is.na(base_data$phq2_positive), c("pid", "record_id")]

  # Only proceed if there are records that need derivation
  if (nrow(base_null_phq2) > 0) {
    base_null_phq2$needs_derivation <- TRUE

    # Merge with completed data to identify which records need derived values
    phq2_positive_data <- safe_left_join(
      completed_data[, c("study_id", "pid", "record_id", "phq2_positive")],
      base_null_phq2,
      by = c("pid", "record_id")
    )

    # Filter to only records that needed derivation
    phq2_positive_data <- phq2_positive_data[!is.na(phq2_positive_data$needs_derivation), ]
    phq2_positive_data <- phq2_positive_data[, c("study_id", "pid", "record_id", "phq2_positive")]

    # DEFENSIVE FILTERING: Remove NULL values before adding imputation_m column
    phq2_positive_data <- phq2_positive_data[!is.na(phq2_positive_data$phq2_positive), ]

    if (nrow(phq2_positive_data) > 0) {
      phq2_positive_data$imputation_m <- m
      phq2_positive_data <- phq2_positive_data[, c("study_id", "pid", "record_id", "imputation_m", "phq2_positive")]
      output_path_phq2 <- file.path(output_dir, sprintf("phq2_positive_m%d.feather", m))
      arrow::write_feather(phq2_positive_data, output_path_phq2)
      cat(sprintf("  [OK] phq2_positive: %d derived values -> %s\n", nrow(phq2_positive_data), basename(output_path_phq2)))
    } else {
      cat("  [INFO] No phq2_positive values needed derivation (all filtered due to NULL)\n")
    }
  } else {
    cat("  [INFO] No phq2_positive values needed derivation (all have observed values)\n")
  }

  # Create identifier for base records with NULL gad2_positive
  base_null_gad2 <- base_data[is.na(base_data$gad2_positive), c("pid", "record_id")]

  # Only proceed if there are records that need derivation
  if (nrow(base_null_gad2) > 0) {
    base_null_gad2$needs_derivation <- TRUE

    # Merge with completed data to identify which records need derived values
    gad2_positive_data <- safe_left_join(
      completed_data[, c("study_id", "pid", "record_id", "gad2_positive")],
      base_null_gad2,
      by = c("pid", "record_id")
    )

    # Filter to only records that needed derivation
    gad2_positive_data <- gad2_positive_data[!is.na(gad2_positive_data$needs_derivation), ]
    gad2_positive_data <- gad2_positive_data[, c("study_id", "pid", "record_id", "gad2_positive")]

    # DEFENSIVE FILTERING: Remove NULL values before adding imputation_m column
    gad2_positive_data <- gad2_positive_data[!is.na(gad2_positive_data$gad2_positive), ]

    if (nrow(gad2_positive_data) > 0) {
      gad2_positive_data$imputation_m <- m
      gad2_positive_data <- gad2_positive_data[, c("study_id", "pid", "record_id", "imputation_m", "gad2_positive")]
      output_path_gad2 <- file.path(output_dir, sprintf("gad2_positive_m%d.feather", m))
      arrow::write_feather(gad2_positive_data, output_path_gad2)
      cat(sprintf("  [OK] gad2_positive: %d derived values -> %s\n", nrow(gad2_positive_data), basename(output_path_gad2)))
    } else {
      cat("  [INFO] No gad2_positive values needed derivation (all filtered due to NULL)\n")
    }
  } else {
    cat("  [INFO] No gad2_positive values needed derivation (all have observed values)\n")
  }

  return(invisible(NULL))
}

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Adult Mental Health & Parenting Imputation\n")
cat(strrep("=", 60), "\n")

# Setup study-specific output directory
output_dir <- file.path(study_config$data_dir, "mental_health_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\n")
}

# Load base data once
db_path <- config$database$db_path
base_data <- load_base_mental_health_data(db_path, eligible_only = TRUE)

# Check missing data
mental_health_vars <- c("phq2_interest", "phq2_depressed", "gad2_nervous", "gad2_worry", "q1502")

cat("\nMissing data summary:\n")
for (var in mental_health_vars) {
  n_missing <- sum(is.na(base_data[[var]]))
  pct_missing <- 100 * n_missing / nrow(base_data)
  cat(sprintf("  %s: %d of %d (%.1f%%)\n", var, n_missing, nrow(base_data), pct_missing))
}

# LOOP OVER GEOGRAPHY/SOCIODEM IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load sociodem imputations m (income, a1_raceG, educ_a1)
  sociodem_m <- load_sociodem_imputations_for_mental_health(db_path, m)

  # Step 3: Merge all data
  dat_m <- merge_imputed_data(base_data, puma_m, sociodem_m, db_path)

  # Step 4: Prepare data for mice
  # Variables: 5 mental health variables (to impute) + 7 auxiliary variables
  imp_vars <- c("phq2_interest", "phq2_depressed", "gad2_nervous", "gad2_worry", "q1502")
  aux_vars <- c("puma", "a1_raceG", "educ_a1", "income", "authentic", "female_a1", "a1_years_old")

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

  # Each mental health variable can use all auxiliary variables as predictors
  for (var in imp_vars) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0  # Reset row
      predictor_matrix[var, aux_vars_existing] <- 1
    }
  }

  # Auxiliary variables are NOT imputed (use complete cases or pre-imputed)
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector (CART for all 5 mental health variables)
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  for (var in imp_vars) {
    if (var %in% names(method_vector)) {
      method_vector[var] <- "cart"
    }
  }

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations: 5\n")
  cat("  Method: CART (all 5 variables)\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\n")
  cat("  remove.collinear: FALSE (CART handles multicollinearity)\n")

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

  # Step 8: Save each mental health variable to Feather (only originally-missing records)
  for (var in mental_health_vars) {
    save_mental_health_feather(completed_m, dat_m, m, output_dir, var)
  }

  # Step 9: Derive and save positive screening indicators
  # Pass base_data so we only save records where phq2_positive/gad2_positive was NULL in base
  derive_positive_screens(completed_m, base_data, m, output_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Adult Mental Health & Parenting Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variables imputed: %s\n", paste(mental_health_vars, collapse = ", ")))
cat(sprintf("  Derived variables: phq2_positive, gad2_positive\n"))
cat(sprintf("  Method: CART (all variables)\n"))
cat(sprintf("  Output directory: %s\n", output_dir))
cat(sprintf("  Total output files: %d (5 items × M + 2 derived × M)\n", 7 * M))

cat("\nNext steps:\n")
cat("  1. Run: python scripts/imputation/ne25/05b_insert_mental_health_imputations.py\n")
cat(strrep("=", 60), "\n")
