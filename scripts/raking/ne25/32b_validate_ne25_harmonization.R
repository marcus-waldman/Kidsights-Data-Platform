# ==============================================================================
# Script: 32b_validate_ne25_harmonization.R
# Purpose: Comprehensive validation and diagnostics for NE25 harmonized datasets
#
# Overview:
#   1. Load M=5 harmonized datasets
#   2. Perform quality checks (completeness, ranges, consistency)
#   3. Compare distributions to unified moments targets
#   4. Generate diagnostic report
#   5. Output summary to ne25_harmonization_summary.txt
#
# Output:
#   - data/raking/ne25/ne25_harmonization_summary.txt (text report)
#   - Diagnostic plots (optional, saved to figures/raking/)
#
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(stringr)

cat("========================================\n")
cat("Validation: NE25 Harmonized Datasets\n")
cat("========================================\n\n")

# Database path (for reference, not needed for validation)
db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") {
  db_path <- "data/duckdb/kidsights_local.duckdb"
}

# ==============================================================================
# SECTION 1: Load Harmonized Datasets
# ==============================================================================

cat("[1] Loading harmonized datasets...\n")

harmonized_dir <- "data/raking/ne25/ne25_harmonized"
harmonized_files <- sprintf("%s/ne25_harmonized_m%d.feather", harmonized_dir, 1:5)

# Check if all files exist
missing_files <- harmonized_files[!file.exists(harmonized_files)]
if (length(missing_files) > 0) {
  stop(sprintf("Missing harmonized files:\n  %s\n\nRun script 32_prepare_ne25_for_weighting.R first",
               paste(missing_files, collapse = "\n  ")))
}

# Load all imputations
harmonized_list <- lapply(harmonized_files, function(f) {
  m <- as.integer(str_extract(basename(f), "\\d$"))
  dat <- arrow::read_feather(f)
  dat$imputation_m <- m
  return(dat)
})

names(harmonized_list) <- sprintf("m%d", 1:5)

cat(sprintf("  ✓ Loaded %d harmonized datasets\n", length(harmonized_list)))

# Combine all imputations for pooled analysis
harmonized_all <- dplyr::bind_rows(harmonized_list)

cat(sprintf("  ✓ Combined: %d total rows (3,507 × 5 imputations)\n", nrow(harmonized_all)))

# ==============================================================================
# SECTION 2: Quality Checks
# ==============================================================================

cat("\n[2] Performing quality checks...\n\n")

# Define variable blocks
block1_vars <- c("male", "age", "white_nh", "black", "hispanic",
                 "educ_years", "poverty_ratio", "principal_city")
block2_vars <- c("phq2_total", "gad2_total")
block3_vars <- c("child_ace_1", "child_ace_2plus", "excellent_health")
all_vars <- c(block1_vars, block2_vars, block3_vars)

# Check 1: Completeness
cat("  [2a] Completeness check:\n")

completeness <- data.frame(
  Variable = all_vars,
  Block = rep(c("1", "2", "3"), times = c(8, 2, 3)),
  N_Total = NA,
  N_Missing = NA,
  Pct_Missing = NA
)

for (i in seq_along(all_vars)) {
  var <- all_vars[i]
  total <- nrow(harmonized_all)
  missing <- sum(is.na(harmonized_all[[var]]))
  pct <- (missing / total) * 100

  completeness$N_Total[i] <- total
  completeness$N_Missing[i] <- missing
  completeness$Pct_Missing[i] <- pct
}

# Print completeness by block
cat("    Block 1 (Demographics) - Expected <5% missing:\n")
block1_completeness <- completeness[completeness$Block == "1", ]
for (i in seq_len(nrow(block1_completeness))) {
  var <- block1_completeness$Variable[i]
  pct <- block1_completeness$Pct_Missing[i]
  flag <- if (pct > 5) "  ⚠" else "  ✓"
  cat(sprintf("%s %s: %.1f%% missing\n", flag, var, pct))
}

cat("\n    Block 2 (Mental Health) - Expected ~55% missing:\n")
block2_completeness <- completeness[completeness$Block == "2", ]
for (i in seq_len(nrow(block2_completeness))) {
  var <- block2_completeness$Variable[i]
  pct <- block2_completeness$Pct_Missing[i]
  cat(sprintf("      %s: %.1f%% missing\n", var, pct))
}

cat("\n    Block 3 (Child Outcomes) - Expected ~15% missing:\n")
block3_completeness <- completeness[completeness$Block == "3", ]
for (i in seq_len(nrow(block3_completeness))) {
  var <- block3_completeness$Variable[i]
  pct <- block3_completeness$Pct_Missing[i]
  cat(sprintf("      %s: %.1f%% missing\n", var, pct))
}

# Check 2: Variable ranges
cat("\n  [2b] Range validation:\n")

range_spec <- data.frame(
  Variable = all_vars,
  Expected_Min = c(0, 0, 0, 0, 0, 2, 0, 0,    # Block 1
                   0, 0,                         # Block 2
                   0, 0, 0),                     # Block 3
  Expected_Max = c(1, 6, 1, 1, 1, 20, 999, 1, # Block 1
                   6, 6,                         # Block 2
                   1, 1, 1),                     # Block 3
  stringsAsFactors = FALSE
)

all_in_range <- TRUE
for (i in seq_along(all_vars)) {
  var <- all_vars[i]
  vals <- harmonized_all[[var]][!is.na(harmonized_all[[var]])]

  if (length(vals) > 0) {
    min_val <- min(vals, na.rm = TRUE)
    max_val <- max(vals, na.rm = TRUE)
    exp_min <- range_spec$Expected_Min[i]
    exp_max <- range_spec$Expected_Max[i]

    if (min_val < exp_min || max_val > exp_max) {
      cat(sprintf("    ⚠ %s: observed [%.1f, %.1f], expected [%.1f, %.1f]\n",
                  var, min_val, max_val, exp_min, exp_max))
      all_in_range <- FALSE
    }
  }
}

if (all_in_range) {
  cat("    ✓ All variables within expected ranges\n")
}

# Check 3: Consistency rules
cat("\n  [2c] Consistency rules:\n")

# Rule 1: Race dummies should sum to ≤ 1 (mutually exclusive)
race_sum <- harmonized_all$white_nh + harmonized_all$black + harmonized_all$hispanic
invalid_race <- sum(race_sum > 1, na.rm = TRUE)

if (invalid_race > 0) {
  cat(sprintf("    ⚠ %d records with race dummies summing > 1\n", invalid_race))
} else {
  cat("    ✓ Race dummies mutually exclusive\n")
}

# Rule 2: Child ACE dummies should sum to ≤ 1
ace_sum <- harmonized_all$child_ace_1 + harmonized_all$child_ace_2plus
invalid_ace <- sum(ace_sum > 1, na.rm = TRUE)

if (invalid_ace > 0) {
  cat(sprintf("    ⚠ %d records with ACE dummies summing > 1\n", invalid_ace))
} else {
  cat("    ✓ Child ACE dummies mutually exclusive\n")
}

# ==============================================================================
# SECTION 3: Distribution Comparison
# ==============================================================================

cat("\n[3] Distribution comparison (pooled M=5 vs unified moments targets):\n\n")

# Load unified moments for comparison
unified_moments <- readRDS("data/raking/ne25/unified_moments.rds")

# Compare means
cat("  Block 1 Demographics (Pooled Means):\n")
cat("  ────────────────────────────────────\n")

comparison_stats <- data.frame(
  Variable = all_vars,
  NE25_Mean = NA,
  Target_Mean = NA,
  Difference = NA,
  Pct_Diff = NA
)

for (i in seq_along(block1_vars)) {
  var <- block1_vars[i]
  ne25_mean <- mean(harmonized_all[[var]], na.rm = TRUE)
  target_mean <- unified_moments$mu[i]
  diff <- ne25_mean - target_mean
  pct_diff <- (diff / target_mean) * 100

  cat(sprintf("  %s\n", var))
  cat(sprintf("    NE25: %.4f  |  Target: %.4f  |  Difference: %.4f (%.1f%%)\n",
              ne25_mean, target_mean, diff, pct_diff))

  comparison_stats$NE25_Mean[i] <- ne25_mean
  comparison_stats$Target_Mean[i] <- target_mean
  comparison_stats$Difference[i] <- diff
  comparison_stats$Pct_Diff[i] <- pct_diff
}

cat("\n  Block 2 Mental Health (informational, ~55% missing):\n")
cat("  ─────────────────────────────────────────────────\n")

for (i in seq_along(block2_vars)) {
  var <- block2_vars[i]
  idx <- 8 + i  # Offset for Block 1
  ne25_mean <- mean(harmonized_all[[var]], na.rm = TRUE)
  target_mean <- unified_moments$mu[idx]

  cat(sprintf("  %s: NE25 = %.4f, Target = %.4f\n", var, ne25_mean, target_mean))
}

cat("\n  Block 3 Child Outcomes (informational, ~15% missing):\n")
cat("  ──────────────────────────────────────────────────\n")

for (i in seq_along(block3_vars)) {
  var <- block3_vars[i]
  idx <- 10 + i  # Offset for Block 1 + Block 2
  ne25_mean <- mean(harmonized_all[[var]], na.rm = TRUE)
  target_mean <- unified_moments$mu[idx]

  cat(sprintf("  %s: NE25 = %.4f, Target = %.4f\n", var, ne25_mean, target_mean))
}

# ==============================================================================
# SECTION 4: Generate Summary Report
# ==============================================================================

cat("\n[4] Generating summary report...\n")

report_file <- "data/raking/ne25/ne25_harmonization_summary.txt"

report_text <- sprintf(
  "NE25 HARMONIZATION VALIDATION REPORT\n%s\n\nGenerated: %s\n\n",
  strrep("=", 50),
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

report_text <- paste0(report_text, sprintf(
  "SAMPLE INFORMATION\n%s\n\nBase eligible records: 3,507\nImputations (M): 5\nTotal dataset rows: 17,535\n\n",
  strrep("─", 30)
))

report_text <- paste0(report_text, sprintf(
  "COMPLETENESS BY BLOCK\n%s\n\nBlock 1 (Demographics) - Expected <5%% missing:\n",
  strrep("─", 30)
))

for (i in seq_len(nrow(block1_completeness))) {
  var <- block1_completeness$Variable[i]
  pct <- block1_completeness$Pct_Missing[i]
  flag <- if (pct > 5) "[WARN]" else "[OK]"
  report_text <- paste0(report_text, sprintf("  %s %s: %.2f%%\n", flag, var, pct))
}

report_text <- paste0(report_text, sprintf(
  "\nBlock 2 (Mental Health) - Expected ~55%% missing:\n"
))

for (i in seq_len(nrow(block2_completeness))) {
  var <- block2_completeness$Variable[i]
  pct <- block2_completeness$Pct_Missing[i]
  report_text <- paste0(report_text, sprintf("  %s: %.2f%%\n", var, pct))
}

report_text <- paste0(report_text, sprintf(
  "\nBlock 3 (Child Outcomes) - Expected ~15%% missing:\n"
))

for (i in seq_len(nrow(block3_completeness))) {
  var <- block3_completeness$Variable[i]
  pct <- block3_completeness$Pct_Missing[i]
  report_text <- paste0(report_text, sprintf("  %s: %.2f%%\n", var, pct))
}

report_text <- paste0(report_text, sprintf(
  "\n\nVARIABLE RANGES\n%s\n\nAll variables within expected ranges: %s\n\n",
  strrep("─", 30),
  if (all_in_range) "YES" else "NO"
))

report_text <- paste0(report_text, sprintf(
  "CONSISTENCY CHECKS\n%s\n\nRace dummies mutually exclusive: %s\n",
  strrep("─", 30),
  if (invalid_race == 0) "YES" else sprintf("NO (%d violations)", invalid_race)
))

report_text <- paste0(report_text, sprintf(
  "Child ACE dummies mutually exclusive: %s\n\n",
  if (invalid_ace == 0) "YES" else sprintf("NO (%d violations)", invalid_ace)
))

report_text <- paste0(report_text, sprintf(
  "READY FOR KL WEIGHTING: %s\n",
  if (all_in_range && invalid_race == 0 && invalid_ace == 0) "YES ✓" else "NO ⚠"
))

# Write report
writeLines(report_text, report_file)

cat(sprintf("  ✓ Report saved to: %s\n", report_file))

# ==============================================================================
# SECTION 5: Summary Output
# ==============================================================================

cat("\n========================================\n")
cat("✓ Validation Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat(sprintf("  Block 1 completeness: %.1f%% (n_missing = %d)\n",
            100 - mean(block1_completeness$Pct_Missing),
            sum(block1_completeness$N_Missing)))

cat(sprintf("  Block 2 completeness: %.1f%% (n_missing = %d)\n",
            100 - mean(block2_completeness$Pct_Missing),
            sum(block2_completeness$N_Missing)))

cat(sprintf("  Block 3 completeness: %.1f%% (n_missing = %d)\n",
            100 - mean(block3_completeness$Pct_Missing),
            sum(block3_completeness$N_Missing)))

cat("\nNext step: Run script 33_compute_kl_weights_ne25.R for KL divergence weighting\n")
