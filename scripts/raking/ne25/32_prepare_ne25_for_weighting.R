# ==============================================================================
# Script: 32_prepare_ne25_for_weighting.R
# Purpose: Create M=5 harmonized NE25 datasets matching unified moment structure
#          for KL divergence weighting
#
# Overview:
#   For each imputation m=1 to m=5:
#     1. Load base NE25 data (meets_inclusion=TRUE, n=2,831)
#     2. Merge 30 imputed variable tables (geography, sociodem, mental health, ACEs)
#     3. Harmonize to 13-variable structure (8 Block 1 + 2 Block 2 + 3 Block 3)
#     4. Validate data quality
#     5. Save ne25_harmonized_m#.feather
#
# Output:
#   - ne25_harmonized_m1.feather through ne25_harmonized_m5.feather
#   - Each: 2,831 rows × 16 columns (pid, record_id, study_id + 13 vars)
#
# Dependencies:
#   - ne25_transformed table (base data)
#   - ne25_imputed_* tables (M=5 imputations for 30 variables)
#   - harmonize_ne25_demographics.R
#   - harmonize_ne25_outcomes.R
#   - R/utils/safe_joins.R
#
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup and Configuration
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(stringr)

# Source utility functions
source("scripts/raking/ne25/utils/harmonize_ne25_demographics.R")
source("scripts/raking/ne25/utils/harmonize_ne25_outcomes.R")
source("R/utils/safe_joins.R")

# Database path (from environment or default)
db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") {
  db_path <- "data/duckdb/kidsights_local.duckdb"
}

# Output directory
output_dir <- "data/raking/ne25/ne25_harmonized"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

cat("========================================\n")
cat("Phase 1: Prepare NE25 for KL Weighting\n")
cat("========================================\n\n")

# ==============================================================================
# SECTION 1: Load Base NE25 Data
# ==============================================================================

load_base_ne25 <- function(db_path) {
  cat("[1] Loading base NE25 data...\n")

  con <- dbConnect(duckdb(), db_path)

  # Load records with meets_inclusion filter (eligible + non-NA authenticity_weight)
  base_data <- dbGetQuery(con, "
    SELECT
      pid,
      record_id,
      years_old,
      female,
      raceG,
      educ_mom,
      fpl,
      cbsa,
      phq2_total,
      gad2_total,
      child_ace_total,
      mmi100
    FROM ne25_transformed
    WHERE meets_inclusion = TRUE
  ")

  # Add constants
  base_data$study_id <- "ne25"
  base_data$authenticity_weight <- 1.0  # Placeholder - all weights = 1 for now

  dbDisconnect(con)

  cat(sprintf("    ✓ Loaded %d records (meets_inclusion=TRUE)\n", nrow(base_data)))

  return(as.data.frame(base_data))
}

# ==============================================================================
# SECTION 2: Merge Imputed Variables for Imputation m
# ==============================================================================

merge_imputations_m <- function(base_data, db_path, m) {
  cat(sprintf("  [2.%d] Merging imputations for m=%d...\n", m, m))

  con <- dbConnect(duckdb(), db_path)

  # Helper function to safely query imputed table
  get_imputed_var <- function(con, var_name, m, base_ids) {
    query <- sprintf("
      SELECT
        pid,
        record_id,
        %s as %s
      FROM ne25_imputed_%s
      WHERE imputation_m = %d AND study_id = 'ne25'
    ", var_name, var_name, var_name, m)

    tryCatch(
      dbGetQuery(con, query),
      error = function(e) {
        cat(sprintf("      Warning: Could not load ne25_imputed_%s\n", var_name))
        return(NULL)
      }
    )
  }

  # Define imputed variables by category
  geo_vars <- c("puma", "county", "census_tract")
  sociodem_vars <- c("female", "raceG", "educ_mom", "income", "family_size", "fplcat")
  mh_vars <- c("phq2_interest", "phq2_depressed", "gad2_nervous", "gad2_worry")
  ace_vars <- c("child_ace_total")

  all_imputed_vars <- c(geo_vars, sociodem_vars, mh_vars, ace_vars)

  # Load and join each imputed variable
  merged_data <- base_data

  for (var in all_imputed_vars) {
    imputed_df <- get_imputed_var(con, var, m, base_data[, c("pid", "record_id")])

    if (!is.null(imputed_df) && nrow(imputed_df) > 0) {
      # Use safe_left_join to handle collisions
      merged_data <- safe_left_join(
        merged_data,
        imputed_df,
        by_vars = c("pid", "record_id"),
        allow_collision = FALSE,
        auto_fix = TRUE
      )
    }
  }

  dbDisconnect(con)

  cat(sprintf("      ✓ Merged %d imputed variables for m=%d\n",
              length(all_imputed_vars), m))

  return(merged_data)
}

# ==============================================================================
# SECTION 3: Harmonize to 13-Variable Structure
# ==============================================================================

harmonize_block1 <- function(data_m) {
  cat("      Harmonizing Block 1 (demographics)...\n")

  # Handle observed vs imputed preference for base variables
  # Prefer observed from base table, use imputed if missing

  harmonized_block1 <- dplyr::tibble(
    # Use base female if available, else imputed
    female = coalesce(data_m$female.x, data_m$female.y),
    years_old = data_m$years_old,
    # Use base raceG if available, else imputed
    raceG = coalesce(data_m$raceG.x, data_m$raceG.y),
    educ_mom = data_m$educ_mom,
    fpl = data_m$fpl,
    cbsa = data_m$cbsa
  )

  # Apply harmonization functions to create 8 Block 1 variables
  block1 <- harmonize_ne25_block1(harmonized_block1)

  return(block1)
}

harmonize_block2 <- function(data_m) {
  cat("      Harmonizing Block 2 (mental health)...\n")

  # Create PHQ-2 and GAD-2 totals with observed/imputed preference
  block2_data <- dplyr::tibble(
    phq2_total_observed = data_m$phq2_total,
    phq2_interest_imputed = data_m$phq2_interest,
    phq2_depressed_imputed = data_m$phq2_depressed,
    gad2_total_observed = data_m$gad2_total,
    gad2_nervous_imputed = data_m$gad2_nervous,
    gad2_worry_imputed = data_m$gad2_worry
  )

  block2 <- harmonize_ne25_mental_health(
    phq2_total_observed = block2_data$phq2_total_observed,
    phq2_interest_imputed = block2_data$phq2_interest_imputed,
    phq2_depressed_imputed = block2_data$phq2_depressed_imputed,
    gad2_total_observed = block2_data$gad2_total_observed,
    gad2_nervous_imputed = block2_data$gad2_nervous_imputed,
    gad2_worry_imputed = block2_data$gad2_worry_imputed
  )

  return(block2)
}

harmonize_block3 <- function(data_m) {
  cat("      Harmonizing Block 3 (child outcomes)...\n")

  # Create child ACE binary categories and health status
  block3 <- dplyr::bind_cols(
    harmonize_ne25_child_aces(data_m$child_ace_total),
    dplyr::tibble(
      excellent_health = harmonize_ne25_excellent_health(data_m$mmi100)
    )
  )

  return(block3)
}

# ==============================================================================
# SECTION 4: Validation
# ==============================================================================

validate_harmonized_data <- function(harmonized_m, m) {
  cat(sprintf("      Validating m=%d...\n", m))

  # Check Block 1 (demographics) completeness
  block1_vars <- c("male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio", "principal_city")
  block1_missing <- colSums(is.na(harmonized_m[, block1_vars, drop = FALSE]))

  block1_pct_missing <- (block1_missing / nrow(harmonized_m)) * 100

  if (any(block1_pct_missing > 5)) {
    warning_vars <- names(block1_pct_missing[block1_pct_missing > 5])
    cat(sprintf("        ⚠ Block 1 vars with >5%% missing: %s\n",
                paste(warning_vars, collapse = ", ")))
  }

  # Check Block 2 (mental health) missingness
  block2_vars <- c("phq2_total", "gad2_total")
  block2_missing <- colSums(is.na(harmonized_m[, block2_vars, drop = FALSE]))
  block2_pct_missing <- (block2_missing / nrow(harmonized_m)) * 100

  cat(sprintf("        Block 2 missingness: phq2_total=%.1f%%, gad2_total=%.1f%%\n",
              block2_pct_missing["phq2_total"],
              block2_pct_missing["gad2_total"]))

  # Check Block 3 (child outcomes) missingness
  block3_vars <- c("child_ace_1", "child_ace_2plus", "excellent_health")
  block3_missing <- colSums(is.na(harmonized_m[, block3_vars, drop = FALSE]))
  block3_pct_missing <- (block3_missing / nrow(harmonized_m)) * 100

  cat(sprintf("        Block 3 missingness: ace_1=%.1f%%, ace_2plus=%.1f%%, excellent=%.1f%%\n",
              block3_pct_missing["child_ace_1"],
              block3_pct_missing["child_ace_2plus"],
              block3_pct_missing["excellent_health"]))

  # Check variable ranges
  range_checks <- list(
    male = c(0, 1),
    age = c(0, 6),
    white_nh = c(0, 1),
    black = c(0, 1),
    hispanic = c(0, 1),
    educ_years = c(2, 20),
    poverty_ratio = c(0, 999),
    principal_city = c(0, 1),
    phq2_total = c(0, 6),
    gad2_total = c(0, 6),
    child_ace_1 = c(0, 1),
    child_ace_2plus = c(0, 1),
    excellent_health = c(0, 1)
  )

  for (var in names(range_checks)) {
    if (var %in% names(harmonized_m)) {
      vals <- harmonized_m[[var]][!is.na(harmonized_m[[var]])]
      if (length(vals) > 0) {
        min_val <- min(vals)
        max_val <- max(vals)
        expected_min <- range_checks[[var]][1]
        expected_max <- range_checks[[var]][2]

        if (min_val < expected_min || max_val > expected_max) {
          warning(sprintf("Variable %s has values outside expected range [%d, %d]: found [%d, %d]",
                          var, expected_min, expected_max, min_val, max_val))
        }
      }
    }
  }

  cat(sprintf("        ✓ Validation complete for m=%d\n", m))
}

# ==============================================================================
# SECTION 5: Main Loop (M=5 Imputations)
# ==============================================================================

cat("\nProcessing M=5 imputations...\n\n")

for (m in 1:5) {
  cat(sprintf("=== IMPUTATION m=%d ===\n", m))

  # Load base
  base <- load_base_ne25(db_path)

  # Merge imputations
  merged <- merge_imputations_m(base, db_path, m)

  # Harmonize
  cat("  [3] Harmonizing to 13-variable structure...\n")

  block1 <- harmonize_block1(merged)
  block2 <- harmonize_block2(merged)
  block3 <- harmonize_block3(merged)

  # Combine all blocks
  harmonized <- dplyr::bind_cols(
    dplyr::select(base, pid, record_id, study_id),
    block1,
    block2,
    block3
  )

  # Validate
  cat("  [4] Validating...\n")
  validate_harmonized_data(harmonized, m)

  # Save
  cat("  [5] Saving...\n")
  output_path <- sprintf("%s/ne25_harmonized_m%d.feather", output_dir, m)
  arrow::write_feather(harmonized, output_path)

  cat(sprintf("      ✓ Saved: %s (%d rows × %d cols)\n\n",
              output_path, nrow(harmonized), ncol(harmonized)))
}

cat("========================================\n")
cat("✓ All M=5 harmonized datasets created\n")
cat("========================================\n\n")

cat("Output files:\n")
for (m in 1:5) {
  output_path <- sprintf("%s/ne25_harmonized_m%d.feather", output_dir, m)
  if (file.exists(output_path)) {
    file_size_mb <- file.size(output_path) / (1024^2)
    cat(sprintf("  [m=%d] %s (%.1f MB)\n", m, output_path, file_size_mb))
  }
}

cat("\nReady for Phase 2: KL divergence weighting (script 33_compute_kl_weights_ne25.R)\n")
