# Phase 3, Task 3.5: Save NHIS Estimates
# Save to data/raking/ne25/nhis_estimates.rds

library(dplyr)

cat("\n========================================\n")
cat("Task 3.5: Save NHIS Estimates\n")
cat("========================================\n\n")

# 1. Load PHQ-2 estimate
cat("[1] Loading PHQ-2 estimate...\n")
phq2_est <- readRDS("data/raking/ne25/phq2_estimate.rds")

cat("    Loaded:", nrow(phq2_est), "rows\n\n")

# 2. Create final NHIS estimates
cat("[2] Creating final NHIS estimates...\n")
nhis_estimates <- phq2_est

cat("    Total rows:", nrow(nhis_estimates), "\n")
cat("    Estimands:", length(unique(nhis_estimates$estimand)), "\n\n")

# 3. Save
cat("[3] Saving to data/raking/ne25/nhis_estimates.rds...\n")
saveRDS(nhis_estimates, "data/raking/ne25/nhis_estimates.rds")

cat("    Saved successfully\n\n")

# 4. Verify saved file
cat("[4] Verifying saved file...\n")
test_load <- readRDS("data/raking/ne25/nhis_estimates.rds")

if (nrow(test_load) != nrow(nhis_estimates)) {
  stop("ERROR: Saved file has different number of rows")
}

if (!all(names(test_load) == names(nhis_estimates))) {
  stop("ERROR: Saved file has different column names")
}

cat("    Verification successful\n")
cat("    Rows:", nrow(test_load), "\n")
cat("    Columns:", paste(names(test_load), collapse = ", "), "\n\n")

# 5. Display final summary
cat("[5] Final NHIS Estimates Summary:\n")
summary_table <- nhis_estimates %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    estimate = dplyr::first(estimate),
    estimate_pct = round(dplyr::first(estimate) * 100, 1),
    .groups = "drop"
  )

print(summary_table)

cat("\n========================================\n")
cat("Task 3.5 Complete\n")
cat("========================================\n")
cat("\nNHIS estimates saved to:\n")
cat("  data/raking/ne25/nhis_estimates.rds\n\n")
