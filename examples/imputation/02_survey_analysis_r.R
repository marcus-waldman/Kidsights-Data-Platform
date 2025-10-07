#!/usr/bin/env Rscript
#
# Survey Analysis with Multiple Imputation - R Examples
#
# Demonstrates survey-weighted analysis with multiply imputed data
# using the survey and mitools packages.

# Load required packages
library(survey)
library(mitools)
library(dplyr)

# Source imputation helpers
source("R/imputation/helpers.R")

cat(paste(rep("=", 70), collapse = ""), "\n")
cat("EXAMPLE 1: Simple Survey Analysis (Single Imputation)\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

# Get completed dataset for imputation m=1
df <- get_completed_dataset(
  imputation_m = 1,
  variables = c("puma", "county", "female", "raceG"),
  base_table = "ne25_transformed",
  study_id = "ne25"
)

cat(sprintf("[OK] Loaded %d records with %d columns\n\n", nrow(df), ncol(df)))

# Create simple survey design (replace with actual weights when available)
df$weight <- 1  # Placeholder - use actual survey weights
design <- survey::svydesign(
  ids = ~1,
  weights = ~weight,
  data = df
)

# Estimate proportions
cat("[INFO] Estimating sex distribution:\n")
sex_est <- survey::svymean(~factor(female), design, na.rm = TRUE)
print(sex_est)

cat("\n[INFO] Estimating race/ethnicity distribution:\n")
race_est <- survey::svymean(~factor(raceG), design, na.rm = TRUE)
print(race_est)

cat("\n", paste(rep("=", 70), collapse = ""), "\n")
cat("EXAMPLE 2: Multiple Imputation with Rubin's Rules\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

# Get list of all M=5 imputations
imp_list <- get_imputation_list(
  variables = c("puma", "county", "female", "raceG"),
  base_table = "ne25_transformed",
  study_id = "ne25",
  max_m = 5
)

cat(sprintf("[OK] Loaded %d imputed datasets\n\n", length(imp_list)))

# Add placeholder weights to each imputation
imp_list <- lapply(imp_list, function(df) {
  df$weight <- 1  # Replace with actual weights
  return(df)
})

# Create survey designs for each imputation
designs <- lapply(imp_list, function(df) {
  survey::svydesign(ids = ~1, weights = ~weight, data = df)
})

cat("[INFO] Created survey designs for M=5 imputations\n\n")

# Estimate sex distribution across all imputations
cat("[INFO] Estimating sex distribution with MI:\n")
sex_results <- lapply(designs, function(d) {
  survey::svymean(~factor(female), d, na.rm = TRUE)
})

# Combine results using Rubin's rules
sex_combined <- mitools::MIcombine(sex_results)
print(summary(sex_combined))

cat("\n[INFO] Estimating race/ethnicity with MI:\n")
race_results <- lapply(designs, function(d) {
  survey::svymean(~factor(raceG), d, na.rm = TRUE)
})

race_combined <- mitools::MIcombine(race_results)
print(summary(race_combined))

cat("\n", paste(rep("=", 70), collapse = ""), "\n")
cat("EXAMPLE 3: Analyze Geographic Variability\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

# Get all imputations in long format
df_long <- get_all_imputations(
  variables = c("puma", "county"),
  base_table = "ne25_transformed",
  study_id = "ne25"
)

cat(sprintf("[OK] Loaded %d records (M=5 imputations)\n\n", nrow(df_long)))

# Calculate variability for each record
variability <- df_long %>%
  dplyr::group_by(pid, record_id) %>%
  dplyr::summarise(
    n_puma_values = dplyr::n_distinct(puma),
    n_county_values = dplyr::n_distinct(county),
    .groups = "drop"
  )

# Count records with geographic uncertainty
uncertain_puma <- sum(variability$n_puma_values > 1)
uncertain_county <- sum(variability$n_county_values > 1)

cat("[INFO] Geographic uncertainty summary:\n")
cat(sprintf("  Records with varying PUMA: %d (%.1f%%)\n",
            uncertain_puma, 100 * uncertain_puma / nrow(variability)))
cat(sprintf("  Records with varying county: %d (%.1f%%)\n",
            uncertain_county, 100 * uncertain_county / nrow(variability)))

# Show examples of uncertain records
cat("\n[INFO] Example records with PUMA uncertainty:\n")
uncertain_records <- variability %>%
  dplyr::filter(n_puma_values > 1) %>%
  dplyr::slice_head(n = 5)

for (i in seq_len(nrow(uncertain_records))) {
  row <- uncertain_records[i, ]
  record_data <- df_long %>%
    dplyr::filter(pid == row$pid, record_id == row$record_id)

  puma_values <- paste(unique(record_data$puma), collapse = ", ")
  cat(sprintf("  PID %d, Record %d: %d PUMAs (%s)\n",
              row$pid, row$record_id, row$n_puma_values, puma_values))
}

cat("\n", paste(rep("=", 70), collapse = ""), "\n")
cat("EXAMPLE 4: Metadata and Validation\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

# Get imputation metadata
meta <- get_imputation_metadata()
ne25_meta <- meta[meta$study_id == "ne25", ]

cat(sprintf("[OK] Found %d imputed variables for ne25\n\n", nrow(ne25_meta)))
cat("Variable details:\n")
for (i in seq_len(nrow(ne25_meta))) {
  row <- ne25_meta[i, ]
  cat(sprintf("  %s: %d imputations, method=%s\n",
              row$variable_name, row$n_imputations, row$imputation_method))
}

# Validate all imputations
cat("\n[INFO] Running validation checks...\n")
results <- validate_imputations(study_id = "ne25")

if (results$all_valid) {
  cat(sprintf("\n[OK] All %d variables validated successfully!\n",
              results$variables_checked))
} else {
  cat("\n[WARN] Validation issues found:\n")
  for (issue in results$issues) {
    cat(sprintf("  - %s\n", issue))
  }
}

cat("\n", paste(rep("=", 70), collapse = ""), "\n")
cat("[OK] All examples completed successfully\n")
cat(paste(rep("=", 70), collapse = ""), "\n")
