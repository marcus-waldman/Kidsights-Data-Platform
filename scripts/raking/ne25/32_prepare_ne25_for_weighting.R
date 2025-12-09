# ==============================================================================
# Script: 32_prepare_ne25_for_weighting.R
# Purpose: Create M=1 harmonized NE25 dataset matching unified moment structure
#          for KL divergence weighting using single CART imputation
#
# Overview:
#     1. Load base NE25 data (meets_inclusion=TRUE, n=2,785)
#     2. Preprocess CBSA and PUMA (extract first value from semicolon-delimited strings)
#     3. Impute missing values using CART (mice package, M=1)
#     4. Harmonize to 24-variable structure (7 demo + 14 PUMA + 2 mental health + 1 outcome)
#     5. Validate data quality
#     6. Save ne25_harmonized_m1.feather
#
# Output:
#   - ne25_harmonized_m1.feather (2,785 rows × 27 columns)
#   - Columns: pid, record_id, study_id + 24 harmonized variables
#
# Dependencies:
#   - ne25_transformed table (base data)
#   - mice package (for CART imputation)
#   - harmonize_puma.R (PUMA binary dummies)
#   - harmonize_ne25_demographics.R
#   - harmonize_ne25_outcomes.R
#
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup and Configuration
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(mice)  # For CART imputation

# Source utility functions
source("scripts/raking/ne25/utils/harmonize_puma.R")
source("scripts/raking/ne25/utils/harmonize_ne25_demographics.R")
source("scripts/raking/ne25/utils/harmonize_ne25_outcomes.R")

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

cat("[1] Loading base NE25 data...\n")

con <- dbConnect(duckdb(), db_path)

# Load records with meets_inclusion filter
# Select only variables needed for harmonization
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
    puma,
    phq2_total,
    gad2_total,
    child_ace_total,
    mmi100
  FROM ne25_transformed
  WHERE meets_inclusion = TRUE
")

dbDisconnect(con)

cat(sprintf("    ✓ Loaded %d records (meets_inclusion=TRUE)\n", nrow(base_data)))

# Report missing data before imputation
cat("\n[1.1] Missing data summary (before imputation):\n")
missing_counts <- colSums(is.na(base_data))
missing_pct <- round(missing_counts / nrow(base_data) * 100, 2)
for (var in names(missing_counts)[missing_counts > 0]) {
  cat(sprintf("      %s: %d (%.1f%%)\n", var, missing_counts[var], missing_pct[var]))
}

# ==============================================================================
# SECTION 2: Preprocess CBSA (Extract First Value from Semicolon-Delimited)
# ==============================================================================

cat("\n[2] Preprocessing CBSA (extract first value)...\n")

# CBSA can have semicolon-delimited values (e.g., "30700; 13100")
# Extract first CBSA code for harmonization
base_data$cbsa_clean <- sapply(base_data$cbsa, function(x) {
  if (is.na(x)) return(NA_character_)
  # Split by semicolon and take first value
  first_val <- stringr::str_split(x, ";")[[1]][1]
  return(stringr::str_trim(first_val))
})

cat(sprintf("    ✓ Extracted first CBSA for %d records\n",
            sum(!is.na(base_data$cbsa_clean))))

# ==============================================================================
# SECTION 2.5: Preprocess PUMA (Extract First Value from Semicolon-Delimited)
# ==============================================================================

cat("\n[2.5] Preprocessing PUMA (extract first value)...\n")

# PUMA can have semicolon-delimited values (e.g., "00100; 00200")
# Extract first PUMA code for harmonization
base_data$puma_clean <- sapply(base_data$puma, function(x) {
  if (is.na(x)) return(NA_character_)
  # Split by semicolon and take first value
  first_val <- stringr::str_split(x, ";")[[1]][1]
  return(stringr::str_trim(first_val))
})

cat(sprintf("    ✓ Extracted first PUMA for %d records\n",
            sum(!is.na(base_data$puma_clean))))

# ==============================================================================
# SECTION 3: Impute Missing Values with CART
# ==============================================================================

cat("\n[3] Imputing missing values using CART...\n")

# Prepare data for mice
# Exclude CBSA from imputation (it's already preprocessed)
# Exclude identifiers
impute_data <- base_data %>%
  dplyr::select(years_old, female, raceG, educ_mom, fpl,
                phq2_total, gad2_total, child_ace_total, mmi100)

# Run mice with CART method, M=1 imputation
set.seed(20251209)  # For reproducibility

cat("    Running mice (CART, M=1, maxit=5)...\n")
imputed <- mice::mice(
  impute_data,
  m = 1,                    # Single imputation
  method = "cart",          # CART method for all variables
  maxit = 5,                # 5 iterations
  printFlag = FALSE         # Suppress iteration output
)

cat("    ✓ Imputation complete\n")

# Extract completed data
imputed_data <- mice::complete(imputed, 1)

# Add back identifiers, CBSA, and PUMA
imputed_data$pid <- base_data$pid
imputed_data$record_id <- base_data$record_id
imputed_data$cbsa <- base_data$cbsa_clean  # Use preprocessed CBSA
imputed_data$puma <- base_data$puma_clean  # Use preprocessed PUMA
imputed_data$study_id <- "ne25"
imputed_data$authenticity_weight <- 1.0  # Placeholder

# Report missing data after imputation (CBSA may still have NAs)
cat("\n[3.1] Missing data summary (after imputation):\n")
missing_after <- colSums(is.na(imputed_data))
if (sum(missing_after) == 0) {
  cat("      ✓ No missing values remaining\n")
} else {
  cat("      Note: Some variables may retain missing values:\n")
  for (var in names(missing_after)[missing_after > 0]) {
    pct <- round(missing_after[var] / nrow(imputed_data) * 100, 1)
    cat(sprintf("        %s: %d (%.1f%%)\n", var, missing_after[var], pct))
  }
}

# ==============================================================================
# SECTION 4: Harmonize to 24-Variable Structure
# ==============================================================================

cat("\n[4] Harmonizing to 24-variable structure...\n")

# Block 1: Demographics (7 variables) + PUMA (14 binary dummies) = 21 variables
cat("    Harmonizing Block 1 (demographics + PUMA)...\n")

block1_input <- dplyr::tibble(
  female = imputed_data$female,
  years_old = imputed_data$years_old,
  raceG = imputed_data$raceG,
  educ_mom = imputed_data$educ_mom,
  fpl = imputed_data$fpl,
  cbsa = imputed_data$cbsa
)

# Harmonize demographics (7 variables)
block1_demo_full <- harmonize_ne25_block1(block1_input)
block1_demo <- dplyr::select(block1_demo_full, -principal_city)  # 7 variables

# Harmonize PUMA to 14 binary dummies (ACS-only)
block1_puma <- harmonize_puma(imputed_data$puma)  # 14 variables

# Combine: demographics (1-7) + PUMA (8-21) = 21 variables
block1 <- dplyr::bind_cols(block1_demo, block1_puma)

# Block 2: Mental Health (2 variables)
cat("    Harmonizing Block 2 (mental health)...\n")

block2 <- dplyr::tibble(
  phq2_total = imputed_data$phq2_total,
  gad2_total = imputed_data$gad2_total
)

# Block 3: Child Outcome (1 variable, no ACEs)
cat("    Harmonizing Block 3 (child outcome)...\n")

block3 <- dplyr::tibble(
  excellent_health = harmonize_ne25_excellent_health(imputed_data$mmi100)
)

# Combine all blocks
harmonized <- dplyr::bind_cols(
  dplyr::select(imputed_data, pid, record_id, study_id),
  block1,
  block2,
  block3
)

cat("    ✓ Harmonization complete\n")

# ==============================================================================
# SECTION 5: Validation
# ==============================================================================

cat("\n[5] Validating harmonized data...\n")

# Check completeness
missing_harmonized <- colSums(is.na(harmonized))
if (sum(missing_harmonized) > 0) {
  cat("    ⚠ Warning: Missing values in harmonized data:\n")
  for (var in names(missing_harmonized)[missing_harmonized > 0]) {
    pct <- round(missing_harmonized[var] / nrow(harmonized) * 100, 2)
    cat(sprintf("      %s: %d (%.1f%%)\n", var, missing_harmonized[var], pct))
  }
} else {
  cat("    ✓ No missing values in harmonized data\n")
}

# Check variable ranges
cat("\n[5.1] Range validation:\n")

range_checks <- list(
  male = c(0, 1),
  age = c(0, 6),
  white_nh = c(0, 1),
  black = c(0, 1),
  hispanic = c(0, 1),
  educ_years = c(2, 20),
  poverty_ratio = c(50, 400),  # NSCH standard range
  phq2_total = c(0, 6),
  gad2_total = c(0, 6),
  excellent_health = c(0, 1)
)

range_issues <- 0
for (var in names(range_checks)) {
  if (var %in% names(harmonized)) {
    vals <- harmonized[[var]][!is.na(harmonized[[var]])]
    if (length(vals) > 0) {
      min_val <- min(vals)
      max_val <- max(vals)
      expected_min <- range_checks[[var]][1]
      expected_max <- range_checks[[var]][2]

      if (min_val < expected_min || max_val > expected_max) {
        cat(sprintf("      ⚠ %s: [%.2f, %.2f] outside expected [%d, %d]\n",
                    var, min_val, max_val, expected_min, expected_max))
        range_issues <- range_issues + 1
      }
    }
  }
}

if (range_issues == 0) {
  cat("    ✓ All variables within expected ranges\n")
}

# Check PUMA dummies
cat("\n[5.2] PUMA consistency check:\n")
puma_cols <- grep("^puma_", names(harmonized), value = TRUE)
if (length(puma_cols) > 0) {
  # Each row should have at most one PUMA = 1 (or all NA)
  puma_sums <- rowSums(harmonized[, puma_cols], na.rm = TRUE)
  invalid_puma <- sum(puma_sums > 1, na.rm = TRUE)
  if (invalid_puma > 0) {
    cat(sprintf("      ⚠ %d records with multiple PUMA = 1\n", invalid_puma))
  } else {
    cat("      ✓ PUMA dummies are mutually exclusive (0 or 1 per record)\n")
  }

  # Check range [0, 1]
  puma_range_invalid <- 0
  for (col in puma_cols) {
    vals <- harmonized[[col]][!is.na(harmonized[[col]])]
    if (any(vals < 0 | vals > 1)) {
      puma_range_invalid <- puma_range_invalid + 1
    }
  }
  if (puma_range_invalid == 0) {
    cat("      ✓ All PUMA variables in range [0, 1]\n")
  }
} else {
  cat("      ⚠ No PUMA variables found\n")
}

# Check dimensions
cat(sprintf("\n[5.3] Final dimensions: %d rows × %d columns\n",
            nrow(harmonized), ncol(harmonized)))

puma_codes <- c(100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904)
puma_names <- sprintf("puma_%d", puma_codes)
expected_cols <- c("pid", "record_id", "study_id",
                   "male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio",
                   puma_names,
                   "phq2_total", "gad2_total",
                   "excellent_health")

if (length(setdiff(expected_cols, names(harmonized))) == 0) {
  cat("    ✓ All expected columns present\n")
} else {
  cat("    ⚠ Missing columns:\n")
  print(setdiff(expected_cols, names(harmonized)))
}

# ==============================================================================
# SECTION 6: Save Output
# ==============================================================================

cat("\n[6] Saving harmonized dataset...\n")

output_path <- file.path(output_dir, "ne25_harmonized_m1.feather")
arrow::write_feather(harmonized, output_path)

file_size_mb <- file.size(output_path) / (1024^2)
cat(sprintf("    ✓ Saved: %s (%.1f MB)\n", output_path, file_size_mb))

# ==============================================================================
# SECTION 7: Final Summary
# ==============================================================================

cat("\n========================================\n")
cat("✓ NE25 Harmonization Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat(sprintf("  Sample size: %d\n", nrow(harmonized)))
cat(sprintf("  Total variables: %d\n", ncol(harmonized)))
cat("  Structure:\n")
cat("    - 3 identifiers (pid, record_id, study_id)\n")
cat("    - 21 Block 1 (7 demographics + 14 PUMA dummies)\n")
cat("    - 2 Block 2 (phq2_total, gad2_total)\n")
cat("    - 1 Block 3 (excellent_health)\n")
cat(sprintf("  Imputation method: CART (M=1)\n"))
cat(sprintf("  Output: %s\n", output_path))
cat("\nReady for Phase 2: KL divergence weighting (script 33_compute_kl_weights_ne25.R)\n")
