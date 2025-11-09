# Childcare Stage 3: Derive childcare_10hrs_nonfamily
#
# Derives the final childcare outcome variable from completed variables in Stages 1 and 2.
# This is a DERIVATION (not imputation) - applies logic to completed data.
#
# Usage:
#   Rscript scripts/imputation/ne25/03c_derive_childcare_10hrs.R
#
# Variable Derived:
#   - childcare_10hrs_nonfamily (BOOLEAN) - Child receives >=10 hrs/week childcare from non-family
#
# Derivation Logic:
#   - FALSE if cc_receives_care = "No"
#   - TRUE if cc_hours_per_week >= 10 AND cc_primary_type != "Relative care"
#   - FALSE otherwise (< 10 hrs OR relative care)
#
# Input Variables (from Stages 1 and 2):
#   - cc_receives_care (from Stage 1 Feather files)
#   - cc_primary_type (from Stage 2 Feather files OR ne25_transformed if observed)
#   - cc_hours_per_week (from Stage 2 Feather files OR ne25_transformed if observed)

# =============================================================================
# SETUP
# =============================================================================

cat("Childcare Stage 3: Derive childcare_10hrs_nonfamily\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(arrow)

# Load safe join utilities
source("R/utils/safe_joins.R")
library(dplyr)
library(arrow)

if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
}
if (!requireNamespace("dplyr", quietly = TRUE)) {
  stop("Package 'dplyr' is required. Install with: install.packages('dplyr')")
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
cat("  Data directory:", study_config$data_dir, "\n")
cat("  Variable to derive: childcare_10hrs_nonfamily\n")

M <- config$n_imputations

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base eligible records from DuckDB
#'
#' @param db_path Path to DuckDB database
#'
#' @return data.frame with all eligible records (pid, record_id, study_id)
load_base_eligible_records <- function(db_path) {
  cat("\n[INFO] Loading base eligible records from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      'ne25' as study_id,
      cc_receives_care,
      cc_primary_type,
      cc_hours_per_week
    FROM ne25_transformed
    WHERE meets_inclusion = TRUE
  "

  dat <- DBI::dbGetQuery(con, query)

  cat("  [OK] Loaded", nrow(dat), "eligible records\n")

  return(dat)
}


#' Load completed cc_receives_care from Stage 1
#'
#' @param feather_dir Path to childcare Feather directory
#' @param m Integer, imputation number
#'
#' @return data.frame with completed cc_receives_care for imputation m
load_cc_receives_care_completed <- function(feather_dir, m) {
  cat(sprintf("\n[INFO] Loading completed cc_receives_care m=%d...\n", m))

  feather_path <- file.path(feather_dir, sprintf("cc_receives_care_m%d.feather", m))

  if (!file.exists(feather_path)) {
    stop(sprintf("Feather file not found: %s\nRun 03a_impute_cc_receives_care.R first", feather_path))
  }

  cc_receives_imp <- arrow::read_feather(feather_path)

  cat(sprintf("  [OK] Loaded %d imputed cc_receives_care values\n", nrow(cc_receives_imp)))

  return(cc_receives_imp)
}


#' Load completed cc_primary_type from Stage 2 (if exists)
#'
#' @param feather_dir Path to childcare Feather directory
#' @param m Integer, imputation number
#'
#' @return data.frame with completed cc_primary_type for imputation m (or NULL if file doesn't exist)
load_cc_primary_type_completed <- function(feather_dir, m) {
  cat(sprintf("\n[INFO] Loading completed cc_primary_type m=%d...\n", m))

  feather_path <- file.path(feather_dir, sprintf("cc_primary_type_m%d.feather", m))

  if (!file.exists(feather_path)) {
    cat("  [WARN] Feather file not found (may not be needed if all values were observed)\n")
    return(NULL)
  }

  cc_type_imp <- arrow::read_feather(feather_path)

  cat(sprintf("  [OK] Loaded %d imputed cc_primary_type values\n", nrow(cc_type_imp)))

  return(cc_type_imp)
}


#' Load completed cc_hours_per_week from Stage 2 (if exists)
#'
#' @param feather_dir Path to childcare Feather directory
#' @param m Integer, imputation number
#'
#' @return data.frame with completed cc_hours_per_week for imputation m (or NULL if file doesn't exist)
load_cc_hours_per_week_completed <- function(feather_dir, m) {
  cat(sprintf("\n[INFO] Loading completed cc_hours_per_week m=%d...\n", m))

  feather_path <- file.path(feather_dir, sprintf("cc_hours_per_week_m%d.feather", m))

  if (!file.exists(feather_path)) {
    cat("  [WARN] Feather file not found (may not be needed if all values were observed)\n")
    return(NULL)
  }

  cc_hours_imp <- arrow::read_feather(feather_path)

  cat(sprintf("  [OK] Loaded %d imputed cc_hours_per_week values\n", nrow(cc_hours_imp)))

  return(cc_hours_imp)
}


#' Merge all completed childcare variables
#'
#' @param base_data data.frame with base eligible records
#' @param cc_receives_imp data.frame with cc_receives_care imputations
#' @param cc_type_imp data.frame with cc_primary_type imputations (or NULL)
#' @param cc_hours_imp data.frame with cc_hours_per_week imputations (or NULL)
#'
#' @return data.frame with all completed childcare variables
merge_all_childcare_variables <- function(base_data, cc_receives_imp, cc_type_imp, cc_hours_imp) {
  cat("\n[INFO] Merging all childcare variables...\n")

  # Start with base data
  dat_merged <- base_data

  # Merge cc_receives_care imputations
  dat_merged <- dat_merged %>%
    safe_left_join(
      cc_receives_imp %>% dplyr::select(pid, record_id, cc_receives_care_imp = cc_receives_care),
      by_vars = c("pid", "record_id")
    )

  # Use imputed cc_receives_care if observed is missing
  # Convert observed values to boolean (TRUE = "Yes", FALSE = "No")
  dat_merged <- dat_merged %>%
    dplyr::mutate(
      cc_receives_care_observed_bool = as.character(cc_receives_care) == "Yes",
      cc_receives_care = ifelse(is.na(cc_receives_care), cc_receives_care_imp, cc_receives_care_observed_bool)
    ) %>%
    dplyr::select(-cc_receives_care_imp, -cc_receives_care_observed_bool)

  # Merge cc_primary_type imputations (if available)
  if (!is.null(cc_type_imp)) {
    dat_merged <- dat_merged %>%
      safe_left_join(
        cc_type_imp %>% dplyr::select(pid, record_id, cc_primary_type_imp = cc_primary_type),
        by_vars = c("pid", "record_id")
      )

    # Use imputed cc_primary_type if observed is missing
    dat_merged <- dat_merged %>%
      dplyr::mutate(
        cc_primary_type = ifelse(is.na(cc_primary_type), cc_primary_type_imp, cc_primary_type)
      ) %>%
      dplyr::select(-cc_primary_type_imp)
  }

  # Merge cc_hours_per_week imputations (if available)
  if (!is.null(cc_hours_imp)) {
    dat_merged <- dat_merged %>%
      safe_left_join(
        cc_hours_imp %>% dplyr::select(pid, record_id, cc_hours_per_week_imp = cc_hours_per_week),
        by_vars = c("pid", "record_id")
      )

    # Use imputed cc_hours_per_week if observed is missing
    dat_merged <- dat_merged %>%
      dplyr::mutate(
        cc_hours_per_week = ifelse(is.na(cc_hours_per_week), cc_hours_per_week_imp, cc_hours_per_week)
      ) %>%
      dplyr::select(-cc_hours_per_week_imp)
  }

  cat(sprintf("  [OK] Merged %d records with all childcare variables\n", nrow(dat_merged)))

  return(dat_merged)
}


#' Derive childcare_10hrs_nonfamily from completed variables
#'
#' @param dat data.frame with completed cc_receives_care, cc_primary_type, cc_hours_per_week
#'
#' @return data.frame with added childcare_10hrs_nonfamily column
derive_childcare_10hrs_nonfamily <- function(dat) {
  cat("\n[INFO] Deriving childcare_10hrs_nonfamily...\n")

  # Convert cc_receives_care to boolean if needed
  if (!is.logical(dat$cc_receives_care)) {
    dat$cc_receives_care <- as.character(dat$cc_receives_care) == "Yes"
  }

  dat_derived <- dat %>%
    dplyr::mutate(
      childcare_10hrs_nonfamily = dplyr::case_when(
        # No childcare received
        cc_receives_care == FALSE ~ FALSE,

        # Childcare from non-family, >= 10 hours
        cc_receives_care == TRUE &
          !is.na(cc_hours_per_week) &
          !is.na(cc_primary_type) &
          cc_hours_per_week >= 10 &
          cc_primary_type != "Relative care" ~ TRUE,

        # Childcare from family OR < 10 hours
        cc_receives_care == TRUE &
          !is.na(cc_hours_per_week) &
          !is.na(cc_primary_type) &
          (cc_hours_per_week < 10 | cc_primary_type == "Relative care") ~ FALSE,

        # Legitimate NULLs: cc_receives_care = TRUE but type/hours missing
        # This occurs when records lack complete auxiliary variables for mice imputation
        cc_receives_care == TRUE &
          (is.na(cc_hours_per_week) | is.na(cc_primary_type)) ~ NA,

        # cc_receives_care is NA (no observed or imputed value available)
        # Occurs when record lacks complete auxiliary variables for Stage 1 imputation
        is.na(cc_receives_care) ~ NA,

        # Default fallback
        TRUE ~ NA
      )
    )

  # Count results
  n_true <- sum(dat_derived$childcare_10hrs_nonfamily == TRUE, na.rm = TRUE)
  n_false <- sum(dat_derived$childcare_10hrs_nonfamily == FALSE, na.rm = TRUE)
  n_na <- sum(is.na(dat_derived$childcare_10hrs_nonfamily))

  cat(sprintf("  [OK] Derived childcare_10hrs_nonfamily:\n"))
  cat(sprintf("    TRUE: %d (%.1f%%)\n", n_true, 100 * n_true / nrow(dat_derived)))
  cat(sprintf("    FALSE: %d (%.1f%%)\n", n_false, 100 * n_false / nrow(dat_derived)))
  cat(sprintf("    NA: %d (%.1f%%) [legitimate missing - incomplete auxiliary variables]\n", n_na, 100 * n_na / nrow(dat_derived)))

  if (n_na > 300) {
    cat(sprintf("  [INFO] %d records lack complete auxiliary variables for imputation\n", n_na))
    cat("  [INFO] This is expected behavior - these records will have NULL in database\n")
  }

  return(dat_derived)
}


#' Save derived childcare_10hrs_nonfamily to Feather
#'
#' @param dat data.frame with derived childcare_10hrs_nonfamily
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
save_childcare_10hrs_feather <- function(dat, m, output_dir) {
  cat(sprintf("\n[INFO] Saving childcare_10hrs_nonfamily m=%d to Feather...\n", m))

  # FILTER OUT records where derivation failed (value still NA)
  # This happens when upstream variables (cc_receives_care, type, hours) are missing
  # Those upstream values could not be imputed due to missing predictor variables
  derived_complete <- dat[!is.na(dat$childcare_10hrs_nonfamily), ]

  derived_subset <- derived_complete[, c("study_id", "pid", "record_id", "childcare_10hrs_nonfamily")]
  derived_subset$imputation_m <- m

  # Reorder columns
  derived_subset <- derived_subset[, c("study_id", "pid", "record_id", "imputation_m", "childcare_10hrs_nonfamily")]

  # Save to Feather
  output_path <- file.path(output_dir, sprintf("childcare_10hrs_nonfamily_m%d.feather", m))
  arrow::write_feather(derived_subset, output_path)

  cat(sprintf("  [OK] Saved %d complete records (filtered %d NULL) -> %s\n",
              nrow(derived_subset),
              nrow(dat) - nrow(derived_subset),
              basename(output_path)))

  return(invisible(NULL))
}

# =============================================================================
# MAIN DERIVATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Childcare Stage 3 Derivation\n")
cat(strrep("=", 60), "\n")

# Setup directories
feather_dir <- file.path(study_config$data_dir, "childcare_feather")
if (!dir.exists(feather_dir)) {
  stop("Feather directory not found. Run 03a and 03b first")
}

db_path <- config$database$db_path

# Load base eligible records once
base_data <- load_base_eligible_records(db_path)

# LOOP OVER IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("DERIVATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load completed cc_receives_care from Stage 1
  cc_receives_m <- load_cc_receives_care_completed(feather_dir, m)

  # Step 2: Load completed cc_primary_type from Stage 2 (if exists)
  cc_type_m <- load_cc_primary_type_completed(feather_dir, m)

  # Step 3: Load completed cc_hours_per_week from Stage 2 (if exists)
  cc_hours_m <- load_cc_hours_per_week_completed(feather_dir, m)

  # Step 4: Merge all completed childcare variables
  dat_m <- merge_all_childcare_variables(base_data, cc_receives_m, cc_type_m, cc_hours_m)

  # Step 5: Derive childcare_10hrs_nonfamily
  dat_derived <- derive_childcare_10hrs_nonfamily(dat_m)

  # Step 6: Save to Feather (ALL eligible records)
  save_childcare_10hrs_feather(dat_derived, m, feather_dir)

  cat(sprintf("\n[OK] Derivation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Childcare Stage 3 Derivation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nDerivation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variable derived: childcare_10hrs_nonfamily\n"))
cat(sprintf("  Records per imputation: %d (all eligible)\n", nrow(base_data)))
cat(sprintf("  Output directory: %s\n", feather_dir))

cat("\nNext steps:\n")
cat("  1. Run: python scripts/imputation/ne25/04_insert_childcare_imputations.py\n")
cat(strrep("=", 60), "\n")
