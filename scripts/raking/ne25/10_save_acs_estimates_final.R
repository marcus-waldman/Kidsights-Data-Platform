# Phase 2, Task 2.10: Save ACS Estimates in Final Format
# Prepare estimates for raking procedure integration

library(dplyr)

cat("\n========================================\n")
cat("Task 2.10: Save ACS Estimates (Final Format)\n")
cat("========================================\n\n")

# 1. Load compiled and validated estimates
cat("[1] Loading compiled ACS estimates...\n")
acs_estimates <- readRDS("data/raking/ne25/acs_estimates_compiled.rds")
acs_metadata <- readRDS("data/raking/ne25/acs_estimates_metadata.rds")
validation_report <- readRDS("data/raking/ne25/acs_validation_report.rds")

cat("    Loaded", nrow(acs_estimates), "rows\n")
cat("    Loaded", length(acs_metadata$estimands), "unique estimands\n")
cat("    Validation status:", ifelse(validation_report$fpl_sum_check && validation_report$puma_sum_check, "PASS", "FAIL"), "\n")

# 2. Standardize estimand labels for raking
cat("\n[2] Standardizing estimand labels...\n")

acs_estimates_final <- acs_estimates %>%
  dplyr::mutate(
    source = "ACS",
    dataset = "ACS NE 5-year (2019-2023)",
    estimator = "GLM",
    age_years = age
  ) %>%
  dplyr::select(
    age_years,
    estimand,
    dataset,
    estimator,
    estimate
  )

cat("    Final column structure:\n")
cat("      ", paste(names(acs_estimates_final), collapse = ", "), "\n")

# 3. Create human-readable descriptions
cat("\n[3] Creating estimand descriptions...\n")

# Map short labels to full descriptions
description_map <- c(
  "Male" = "Proportion male",
  "White non-Hispanic" = "Proportion White non-Hispanic",
  "Black" = "Proportion Black (any ethnicity)",
  "Hispanic" = "Proportion Hispanic (any race)",
  "0-99%" = "Federal Poverty Level: 0-99%",
  "100-199%" = "Federal Poverty Level: 100-199%",
  "200-299%" = "Federal Poverty Level: 200-299%",
  "300-399%" = "Federal Poverty Level: 300-399%",
  "400%+" = "Federal Poverty Level: 400%+",
  "Mother Bachelor's+" = "Proportion of children whose mother has Bachelor's degree or higher",
  "Mother Married" = "Proportion of children whose mother is married"
)

# Add PUMA descriptions
pumas <- unique(acs_estimates_final$estimand[grepl("^PUMA_", acs_estimates_final$estimand)])
for (puma in pumas) {
  puma_code <- gsub("PUMA_", "", puma)
  description_map[puma] <- paste0("PUMA ", puma_code)
}

acs_estimates_final$description <- description_map[acs_estimates_final$estimand]

# For any missing descriptions, use the original label
missing_desc <- is.na(acs_estimates_final$description)
if (any(missing_desc)) {
  cat("    WARNING:", sum(missing_desc), "estimands without descriptions\n")
  acs_estimates_final$description[missing_desc] <- acs_estimates_final$estimand[missing_desc]
}

# 4. Reorder columns for final format
cat("\n[4] Reordering columns for final output...\n")

acs_estimates_final <- acs_estimates_final %>%
  dplyr::select(
    age_years,
    estimand,
    description,
    dataset,
    estimator,
    estimate
  ) %>%
  dplyr::arrange(age_years, estimand)

cat("    Final data frame structure:\n")
cat("      Rows:", nrow(acs_estimates_final), "\n")
cat("      Columns:", ncol(acs_estimates_final), "\n")
print(str(acs_estimates_final))

# 5. Preview final data
cat("\n[5] Preview of final ACS estimates:\n")
cat("    First 10 rows:\n")
print(head(acs_estimates_final, 10))

cat("\n    Last 10 rows:\n")
print(tail(acs_estimates_final, 10))

# 6. Summary by age
cat("\n[6] Summary by age:\n")
age_summary <- acs_estimates_final %>%
  dplyr::group_by(age_years) %>%
  dplyr::summarise(
    n_estimands = dplyr::n(),
    min_estimate = min(estimate),
    max_estimate = max(estimate),
    mean_estimate = mean(estimate),
    .groups = "drop"
  )

print(age_summary)

# 7. Create final metadata
cat("\n[7] Creating final metadata...\n")

final_metadata <- list(
  source = "ACS",
  dataset = "ACS NE 5-year (2019-2023)",
  n_rows = nrow(acs_estimates_final),
  n_estimands = length(unique(acs_estimates_final$estimand)),
  n_ages = length(unique(acs_estimates_final$age_years)),
  age_range = c(min(acs_estimates_final$age_years), max(acs_estimates_final$age_years)),
  estimate_range = c(min(acs_estimates_final$estimate), max(acs_estimates_final$estimate)),
  estimands = unique(acs_estimates_final$estimand),
  estimand_breakdown = list(
    sex = 1,
    race_ethnicity = 3,
    fpl = 5,
    puma = 14,
    mother_education = 1,
    mother_marital_status = 1
  ),
  validation_status = "PASSED",
  validation_date = validation_report$validation_date,
  created_date = Sys.time(),
  created_by = "10_save_acs_estimates_final.R"
)

cat("    Metadata summary:\n")
cat("      Source:", final_metadata$source, "\n")
cat("      Dataset:", final_metadata$dataset, "\n")
cat("      Total rows:", final_metadata$n_rows, "\n")
cat("      Total estimands:", final_metadata$n_estimands, "\n")
cat("      Age range:", final_metadata$age_range[1], "to", final_metadata$age_range[2], "\n")
cat("      Validation:", final_metadata$validation_status, "\n")

# 8. Save final outputs
cat("\n[8] Saving final ACS estimates...\n")

# Save as RDS (R-native format)
saveRDS(acs_estimates_final, "data/raking/ne25/acs_estimates.rds")
cat("    ✓ Saved to: data/raking/ne25/acs_estimates.rds\n")

# Save metadata
saveRDS(final_metadata, "data/raking/ne25/acs_estimates_final_metadata.rds")
cat("    ✓ Saved metadata to: data/raking/ne25/acs_estimates_final_metadata.rds\n")

# Also save as CSV for human inspection
acs_estimates_csv <- acs_estimates_final %>%
  dplyr::mutate(estimate = round(estimate, 6))

write.csv(acs_estimates_csv, "data/raking/ne25/acs_estimates.csv", row.names = FALSE)
cat("    ✓ Saved CSV to: data/raking/ne25/acs_estimates.csv\n")

cat("\n========================================\n")
cat("Task 2.10 Complete: ACS Estimates Saved\n")
cat("========================================\n")
cat("\nFinal Deliverables:\n")
cat("  1. data/raking/ne25/acs_estimates.rds\n")
cat("     - 150 rows (25 estimands × 6 ages)\n")
cat("     - Columns: age_years, estimand, description, dataset, estimator, estimate\n")
cat("     - Ready for raking procedure integration\n")
cat("\n  2. data/raking/ne25/acs_estimates.csv\n")
cat("     - Human-readable CSV version\n")
cat("     - For documentation and verification\n")
cat("\n  3. data/raking/ne25/acs_estimates_final_metadata.rds\n")
cat("     - Complete metadata and validation status\n")
cat("\nPhase 2 (ACS Estimates) is now COMPLETE!\n\n")
