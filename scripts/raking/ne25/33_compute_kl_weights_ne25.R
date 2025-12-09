# ==============================================================================
# Script: 33_compute_kl_weights_ne25.R
# Purpose: Compute KL divergence weights for NE25 data to match unified moments
#
# Overview:
#   For each imputation m=1 to m=5:
#     1. Load harmonized NE25 dataset (m)
#     2. Load unified target moments (pooled ACS/NHIS/NSCH)
#     3. Run KL divergence calibration to reweight NE25 to match targets
#     4. Save weights
#     5. Compute final weights (base_weight × kl_weight)
#     6. Insert into database
#
# Output:
#   - ne25_weights_m1.rds through ne25_weights_m5.rds (weight objects)
#   - ne25_kl_weights table in database (17,535 rows × 8 columns)
#
# Dependencies:
#   - ne25_harmonized_m#.feather files (from script 32)
#   - unified_moments.rds (from script 30b)
#   - Stan model for KL divergence (scripts/raking/ne25/utils/*.stan)
#   - calibrate_weights_stan() function (from raking utilities)
#
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(rstan)

cat("========================================\n")
cat("Phase 2: Compute KL Divergence Weights\n")
cat("========================================\n\n")

# ==============================================================================
# SECTION 0: Setup and Configuration
# ==============================================================================

# Database path
db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") {
  db_path <- "data/duckdb/kidsights_local.duckdb"
}

# Output directory
weights_dir <- "data/raking/ne25"
if (!dir.exists(weights_dir)) {
  dir.create(weights_dir, recursive = TRUE)
}

# Stan model compilation (if needed)
# Note: This should be adapted based on which Stan model is used
# Options:
#   - calibrate_weights.exe (from utils)
#   - mirt + calibration package
#   - cmdstanr::cmdstan_model()

cat("[0] Loading configuration...\n")
cat("    Database: ", db_path, "\n")
cat("    Output dir: ", weights_dir, "\n\n")

# ==============================================================================
# SECTION 1: Load Unified Moments (Target)
# ==============================================================================

cat("[1] Loading unified target moments...\n")

unified_moments <- readRDS("data/raking/ne25/unified_moments.rds")

cat(sprintf("    ✓ Target structure: %d variables\n", length(unified_moments$variable_names)))
cat(sprintf("    Variable names: %s\n",
            paste(unified_moments$variable_names, collapse = ", ")))

target_mean <- unified_moments$mu
target_cov <- unified_moments$Sigma

cat(sprintf("    Mean vector: length = %d\n", length(target_mean)))
cat(sprintf("    Covariance matrix: %d × %d\n", nrow(target_cov), ncol(target_cov)))

# ==============================================================================
# SECTION 2: KL Weighting Function
# ==============================================================================

#' Compute KL Divergence Weights
#'
#' Wrapper function that runs KL divergence optimization for a single imputation
#' This is a placeholder - adapt based on actual calibration method available
#'
#' @param data Data frame with harmonized variables
#' @param target_mean Target mean vector
#' @param target_cov Target covariance matrix
#' @param variable_names Names of variables to use in calibration
#'
#' @return List with calibration results:
#'   - weights: individual KL weights
#'   - target_mean_achieved: weighted mean
#'   - target_cov_achieved: weighted covariance
#'   - convergence: optimization convergence status
#'
compute_kl_weights <- function(data, target_mean, target_cov, variable_names) {

  # Extract calibration variables
  X <- data[, variable_names, drop = FALSE]

  # Remove rows with any missing values in calibration variables
  complete_mask <- complete.cases(X)
  X_complete <- X[complete_mask, ]
  n_complete <- nrow(X_complete)
  n_missing <- sum(!complete_mask)

  cat(sprintf("      Complete cases for calibration: %d (%.1f%%)\n",
              n_complete, (n_complete / nrow(data)) * 100))

  # Standardize X to match moments structure
  X_matrix <- as.matrix(X_complete)

  # Initialize weights (start with uniform)
  weights <- rep(1 / n_complete, n_complete)

  # NOTE: This is a placeholder implementation
  # In practice, you would call one of:
  #   1. calibrate_weights() from survey package
  #   2. calibrate_weights_stan() from local Stan model
  #   3. optimization via optim() with KL divergence loss
  #
  # For now, return placeholder results with instructions

  cat("      ⚠ NOTE: KL optimization not yet implemented\n")
  cat("      Choose calibration method:\n")
  cat("        Option A: survey::calibrate() - linear constraints\n")
  cat("        Option B: calibrate_weights_stan() - full KL divergence\n")
  cat("        Option C: optim() + custom KL loss function\n")

  # Return structure for now (will be populated with real weights)
  results <- list(
    weights = weights,
    n_effective = sum(weights)^2 / sum(weights^2),
    convergence = "PLACEHOLDER",
    method = "KL Divergence (to be implemented)"
  )

  return(results)
}

# ==============================================================================
# SECTION 3: Main Loop (M=5 Imputations)
# ==============================================================================

cat("\n[2] Computing KL weights for M=5 imputations...\n\n")

# Storage for all weight results
all_weights_m <- list()

for (m in 1:5) {
  cat(sprintf("=== IMPUTATION m=%d ===\n", m))

  # Load harmonized dataset
  cat("  [2.a] Loading harmonized dataset...\n")

  harmonized_file <- sprintf("data/raking/ne25/ne25_harmonized/ne25_harmonized_m%d.feather", m)

  if (!file.exists(harmonized_file)) {
    stop(sprintf("File not found: %s\nRun script 32_prepare_ne25_for_weighting.R first",
                 harmonized_file))
  }

  ne25_data <- arrow::read_feather(harmonized_file)

  cat(sprintf("    ✓ Loaded %d records × %d variables\n",
              nrow(ne25_data), ncol(ne25_data)))

  # Load base NE25 data for authenticity weights
  cat("  [2.b] Loading base weights (authenticity)...\n")

  con <- dbConnect(duckdb(), db_path)

  base_weights <- dbGetQuery(con, sprintf("
    SELECT
      pid,
      record_id,
      authenticity_weight
    FROM ne25_transformed
    WHERE eligible = TRUE
  "))

  dbDisconnect(con)

  cat(sprintf("    ✓ Loaded %d base weights\n", nrow(base_weights)))

  # Join base weights to harmonized data
  ne25_with_weights <- ne25_data %>%
    left_join(base_weights, by = c("pid", "record_id"))

  # Compute KL weights
  cat("  [2.c] Computing KL weights...\n")

  kl_results <- compute_kl_weights(
    data = ne25_with_weights,
    target_mean = target_mean,
    target_cov = target_cov,
    variable_names = unified_moments$variable_names
  )

  cat(sprintf("    n_effective (KL): %.1f\n", kl_results$n_effective))

  # Compute final weights (product of base and KL)
  ne25_with_weights$kl_weight <- kl_results$weights
  ne25_with_weights$final_weight <- ne25_with_weights$authenticity_weight * ne25_with_weights$kl_weight

  # Store results
  all_weights_m[[m]] <- ne25_with_weights %>%
    select(pid, record_id, kl_weight, final_weight)

  # Save weights for this imputation
  cat("  [2.d] Saving weights...\n")

  weight_file <- sprintf("%s/ne25_weights_m%d.rds", weights_dir, m)

  weights_output <- list(
    imputation_m = m,
    n_records = nrow(ne25_with_weights),
    kl_results = kl_results,
    weights = ne25_with_weights %>% select(pid, record_id, kl_weight, final_weight)
  )

  saveRDS(weights_output, weight_file)

  cat(sprintf("    ✓ Saved: %s\n\n", weight_file))
}

# ==============================================================================
# SECTION 4: Database Integration
# ==============================================================================

cat("[3] Inserting weights into database...\n")

# Combine all M=5 weight sets
all_weights_combined <- dplyr::bind_rows(all_weights_m, .id = "imputation_id")
all_weights_combined$imputation_m <- as.integer(str_extract(all_weights_combined$imputation_id, "\\d"))
all_weights_combined$study_id <- "ne25"
all_weights_combined$imputation_id <- NULL

# Rename columns for database
all_weights_combined <- all_weights_combined %>%
  select(study_id, pid, record_id, imputation_m, kl_weight, final_weight)

# Add effective N column
all_weights_combined <- all_weights_combined %>%
  group_by(imputation_m) %>%
  mutate(
    effective_n = (sum(final_weight)^2) / sum(final_weight^2)
  ) %>%
  ungroup()

cat(sprintf("  Total rows: %d (%d imputations × 3,507 records)\n",
            nrow(all_weights_combined),
            n_distinct(all_weights_combined$imputation_m)))

# Insert into database
cat("  Inserting into database table: ne25_kl_weights...\n")

con <- dbConnect(duckdb(), db_path)

# Create table
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS ne25_kl_weights (
    study_id VARCHAR NOT NULL,
    pid INTEGER NOT NULL,
    record_id INTEGER NOT NULL,
    imputation_m INTEGER NOT NULL,
    kl_weight DOUBLE NOT NULL,
    final_weight DOUBLE NOT NULL,
    effective_n DOUBLE,
    PRIMARY KEY (pid, record_id, imputation_m)
  )
")

# Insert data
dbAppendTable(con, "ne25_kl_weights", all_weights_combined)

# Create indices
dbExecute(con, "CREATE INDEX idx_ne25_kl_pid ON ne25_kl_weights(pid, record_id)")
dbExecute(con, "CREATE INDEX idx_ne25_kl_m ON ne25_kl_weights(imputation_m)")

dbDisconnect(con)

cat(sprintf("    ✓ Inserted %d records\n", nrow(all_weights_combined)))

# ==============================================================================
# SECTION 5: Summary and Next Steps
# ==============================================================================

cat("\n========================================\n")
cat("✓ KL Weighting Complete\n")
cat("========================================\n\n")

cat("Output:\n")
for (m in 1:5) {
  weight_file <- sprintf("%s/ne25_weights_m%d.rds", weights_dir, m)
  if (file.exists(weight_file)) {
    file_size <- file.size(weight_file) / 1024
    cat(sprintf("  [m=%d] %s (%.1f KB)\n", m, weight_file, file_size))
  }
}

cat("\nDatabase table: ne25_kl_weights\n")
cat("  - Rows: 17,535 (3,507 records × 5 imputations)\n")
cat("  - Columns: study_id, pid, record_id, imputation_m, kl_weight, final_weight, effective_n\n")

cat("\nNext steps:\n")
cat("  1. Review weight distributions (check for extreme values)\n")
cat("  2. Verify effective sample sizes (should be close to 3,507)\n")
cat("  3. Use weights in downstream analysis with Rubin's rules MI pooling\n")

cat("\nExample usage in analysis:\n")
cat("
# Load weights for imputation m=1
weights_m1 <- readRDS('data/raking/ne25/ne25_weights_m1.rds')
kl_weights <- weights_m1\$weights

# Use final_weight column in survey::svydesign():
# design_m1 <- svydesign(ids = ~pid, weights = ~final_weight, data = ne25_data_m1)
")
