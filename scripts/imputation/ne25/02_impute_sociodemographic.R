# Sociodemographic Imputation for NE25
#
# Generates M=5 imputations for sociodemographic variables using CART + Random Forest
# via the mice package. Uses chained imputation approach where each mice run uses
# geography from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/02_impute_sociodemographic.R
#
# Variables Imputed:
#   - female (CART)
#   - raceG (CART)
#   - educ_mom (Random Forest)
#   - educ_a2 (Random Forest)
#   - income (CART)
#   - family_size (CART)
#   - fplcat (DERIVED from income + family_size)

# =============================================================================
# SETUP
# =============================================================================

cat("Sociodemographic Imputation for NE25\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(ranger)

# Load safe join utilities
source("R/utils/safe_joins.R")
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
if (!requireNamespace("ranger", quietly = TRUE)) {
  stop("Package 'ranger' is required. Install with: install.packages('ranger')")
}
if (!requireNamespace("arrow", quietly = TRUE)) {
  stop("Package 'arrow' is required. Install with: install.packages('arrow')")
}
if (!requireNamespace("reticulate", quietly = TRUE)) {
  stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
}

# Source configuration loader
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
sociodem_config <- get_sociodem_config()

cat("\nConfiguration:\n")
cat("  Study ID:", study_id, "\n")
cat("  Study Name:", study_config$study_name, "\n")
cat("  Number of imputations (M):", config$n_imputations, "\n")
cat("  Random seed:", config$random_seed, "\n")
cat("  Data directory:", study_config$data_dir, "\n")
cat("  Variables to impute:", paste(sociodem_config$variables, collapse = ", "), "\n")
cat("  Auxiliary variables:", paste(sociodem_config$auxiliary_variables, collapse = ", "), "\n")
cat("  Eligible only:", sociodem_config$eligible_only, "\n")
cat("  Chained imputation:", sociodem_config$chained, "\n")
cat("  mice maxit:", sociodem_config$maxit, "\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to meets_inclusion == TRUE
#'
#' @return data.frame with base sociodemographic data
load_base_data <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base data from DuckDB...\n")

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
      female,
      raceG,
      educ_mom,
      educ_a2,
      income,
      family_size,

      -- Auxiliary variables (complete or mostly complete)
      age_in_days,
      consent_date,
      mom_a1,
      relation1,

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


#' Merge geography imputation m into base data
#'
#' @param base_data data.frame with base sociodemographic data
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#'
#' @return data.frame with puma and county from imputation m merged
merge_geography_imputation <- function(base_data, db_path, m) {
  cat(sprintf("\n[INFO] Loading geography imputation m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Load PUMA imputation m
  puma_query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      puma
    FROM ne25_imputed_puma
    WHERE imputation_m = %d AND study_id = 'ne25'
  ", m)

  puma_imp <- DBI::dbGetQuery(con, puma_query)

  # Load County imputation m
  county_query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      county
    FROM ne25_imputed_county
    WHERE imputation_m = %d AND study_id = 'ne25'
  ", m)

  county_imp <- DBI::dbGetQuery(con, county_query)

  cat(sprintf("  [OK] Loaded %d PUMA and %d county imputations\n",
              nrow(puma_imp), nrow(county_imp)))

  # Merge with base data
  dat_merged <- base_data %>%
    safe_left_join(puma_imp, by_vars = c("pid", "record_id")) %>%
    safe_left_join(county_imp, by_vars = c("pid", "record_id"))

  # For records without geography ambiguity, fill from ne25_transformed
  # (This handles records that weren't in imputed_puma/county tables)
  if (any(is.na(dat_merged$puma))) {
    con2 <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con2, shutdown = FALSE), add = TRUE)

    geo_observed <- DBI::dbGetQuery(con2, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        puma as puma_observed,
        county as county_observed
      FROM ne25_transformed
    ")

    dat_merged <- dat_merged %>%
      safe_left_join(geo_observed, by_vars = c("pid", "record_id")) %>%
      dplyr::mutate(
        puma = ifelse(is.na(puma), puma_observed, puma),
        county = ifelse(is.na(county), county_observed, county)
      ) %>%
      dplyr::select(-puma_observed, -county_observed)
  }

  cat(sprintf("  [OK] Merged geography: %d records with puma, %d with county\n",
              sum(!is.na(dat_merged$puma)), sum(!is.na(dat_merged$county))))

  return(dat_merged)
}


#' Calculate Federal Poverty Level category
#'
#' @param income Family income in dollars
#' @param family_size Household size (1-99)
#' @param consent_date Survey consent date
#'
#' @return Character vector of FPL categories
calculate_fpl_category <- function(income, family_size, consent_date) {
  # Placeholder - will implement full FPL thresholds
  # For now, return simple brackets

  # 2023 Federal Poverty Guidelines (for NE25 consents in 2023-2024)
  # Source: https://aspe.hhs.gov/topics/poverty-economic-mobility/poverty-guidelines

  fpl_thresholds <- c(
    "1" = 14580,
    "2" = 19720,
    "3" = 24860,
    "4" = 30000,
    "5" = 35140,
    "6" = 40280,
    "7" = 45420,
    "8" = 50560
  )

  # For families > 8, add $5140 per additional person
  fpl_base <- ifelse(
    family_size <= 8,
    fpl_thresholds[as.character(pmin(family_size, 8))],
    fpl_thresholds["8"] + (family_size - 8) * 5140
  )

  fpl_ratio <- income / fpl_base

  fplcat <- dplyr::case_when(
    is.na(income) | is.na(family_size) ~ NA_character_,
    fpl_ratio < 1 ~ "<100% FPL",
    fpl_ratio < 2 ~ "100-199% FPL",
    fpl_ratio < 4 ~ "200-399% FPL",
    fpl_ratio >= 4 ~ "400%+ FPL",
    TRUE ~ NA_character_
  )

  return(fplcat)
}


#' Save imputation results to Feather files
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
save_imputation_feather <- function(completed_data, original_data, m, output_dir) {
  cat(sprintf("\n[INFO] Saving imputation m=%d to Feather...\n", m))

  # Identify which records had missing values originally
  vars_imputed <- c("female", "raceG", "educ_mom", "educ_a2", "income", "family_size", "fplcat")

  total_rows_saved <- 0

  # Save each variable to its own Feather file
  for (var in vars_imputed) {
    if (var == "fplcat") {
      # fplcat is always derived, store all values (where not NA)
      originally_missing <- rep(TRUE, nrow(original_data))
    } else {
      # Check which records were originally missing
      originally_missing <- is.na(original_data[[var]])
    }

    if (sum(originally_missing) > 0) {
      # Extract imputed values for originally missing records
      imputed_subset <- completed_data[originally_missing, c("study_id", "pid", "record_id", var)]
      imputed_subset$imputation_m <- m

      # FILTER OUT records where imputation failed (value still NA)
      # This happens for records with missing predictor variables (e.g., no geography)
      successfully_imputed <- !is.na(imputed_subset[[var]])
      imputed_subset <- imputed_subset[successfully_imputed, ]

      if (nrow(imputed_subset) > 0) {
        # Reorder columns: study_id, pid, record_id, imputation_m, variable_value
        imputed_subset <- imputed_subset[, c("study_id", "pid", "record_id", "imputation_m", var)]

        # Save to separate Feather file per variable
        output_path <- file.path(output_dir, sprintf("%s_m%d.feather", var, m))
        arrow::write_feather(imputed_subset, output_path)

        cat(sprintf("  [OK] %s: %d values -> %s\n", var, nrow(imputed_subset), basename(output_path)))
        total_rows_saved <- total_rows_saved + nrow(imputed_subset)
      } else {
        cat(sprintf("  [WARN] %s: No successfully imputed values\n", var))
      }
    }
  }

  cat(sprintf("  [OK] Saved %d total imputed values across %d files\n", total_rows_saved, length(vars_imputed)))

  return(invisible(NULL))
}

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Chained Imputation\n")
cat(strrep("=", 60), "\n")

# Setup study-specific output directory
output_dir <- file.path(study_config$data_dir, "sociodem_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\n")
}

# Load base data once
db_path <- config$database$db_path
base_data <- load_base_data(db_path, eligible_only = sociodem_config$eligible_only)

# Configure mice methods
mice_methods <- unlist(sociodem_config$mice_method)

cat("\nmice Imputation Methods:\n")
for (var in names(mice_methods)) {
  cat(sprintf("  %s: %s\n", var, mice_methods[var]))
}

# Variables to impute and auxiliary variables
imp_vars <- sociodem_config$variables
aux_vars <- sociodem_config$auxiliary_variables

# LOOP OVER GEOGRAPHY IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Merge geography imputation m
  dat_m <- merge_geography_imputation(base_data, db_path, m)

  # Step 2: Prepare data for mice
  # Select variables to impute + auxiliary variables
  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables actually exist in dat_m
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\n[WARN] Missing columns (will skip): %s\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Check missing data patterns
  missing_counts <- sapply(dat_mice[imp_vars], function(x) sum(is.na(x)))
  cat("\nMissing data before imputation:\n")
  for (var in names(missing_counts)) {
    pct_missing <- 100 * missing_counts[var] / nrow(dat_mice)
    cat(sprintf("  %s: %d (%.1f%%)\n", var, missing_counts[var], pct_missing))
  }

  # Step 3: Configure mice
  # Set up predictor matrix (which variables predict which)
  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  # Get auxiliary variables that actually exist in the data
  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # Variables to impute can use all auxiliary variables as predictors
  for (var in imp_vars) {
    predictor_matrix[var, ] <- 0  # Reset row
    # Only set predictors for auxiliary variables that exist
    predictor_matrix[var, aux_vars_existing] <- 1
    # Also allow imputed variables to predict each other
    predictor_matrix[var, setdiff(imp_vars, var)] <- 1
  }

  # Auxiliary variables are NOT imputed (use complete cases or pre-imputed)
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)

  for (var in imp_vars) {
    method_vector[var] <- mice_methods[var]
  }

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations:", sociodem_config$maxit, "\n")
  cat("  RF package:", sociodem_config$rf_package, "\n")
  cat("  Remove collinear:", sociodem_config$remove_collinear, "\n")

  # Step 4: Run mice
  cat("\n[INFO] Running mice imputation...\n")

  set.seed(seed + m)  # Unique seed for each geography imputation

  mice_result <- mice::mice(
    data = dat_mice,
    m = 1,
    method = method_vector,
    predictorMatrix = predictor_matrix,
    maxit = sociodem_config$maxit,
    rfPackage = sociodem_config$rf_package,
    remove.collinear = sociodem_config$remove_collinear,
    printFlag = FALSE
  )

  cat("  [OK] mice imputation complete\n")

  # Step 5: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 6: Calculate derived FPL category
  cat("\n[INFO] Calculating FPL category...\n")
  completed_m$fplcat <- calculate_fpl_category(
    completed_m$income,
    completed_m$family_size,
    completed_m$consent_date
  )

  n_fplcat <- sum(!is.na(completed_m$fplcat))
  cat(sprintf("  [OK] Calculated FPL category for %d records\n", n_fplcat))

  # Step 7: Save to Feather (only originally missing values)
  save_imputation_feather(completed_m, dat_m, m, output_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Sociodemographic Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variables imputed: %d (%s)\n",
            length(imp_vars), paste(imp_vars, collapse = ", ")))
cat(sprintf("  Derived variables: 1 (fplcat)\n"))
cat(sprintf("  Output directory: %s\n", output_dir))

# Count total imputed values across all Feather files
feather_files <- list.files(output_dir, pattern = "sociodem_imputation_m.*\\.feather$", full.names = TRUE)
if (length(feather_files) > 0) {
  total_imputed_values <- 0
  for (f in feather_files) {
    df_temp <- arrow::read_feather(f)
    total_imputed_values <- total_imputed_values + nrow(df_temp)
  }
  cat(sprintf("  Total imputed values stored: %d\n", total_imputed_values))
}

cat("\nNext steps:\n")
cat("  1. Run: python scripts/imputation/02b_insert_sociodem_imputations.py\n")
cat("  2. Validate: python -m python.imputation.helpers\n")
cat(strrep("=", 60), "\n")
