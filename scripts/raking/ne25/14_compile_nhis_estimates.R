# Phase 3, Task 3.3: Compile NHIS Estimates
# 1 estimand (PHQ-2 depression) expanded to 6 rows (ages 0-5)

library(dplyr)

cat("\n========================================\n")
cat("Task 3.3: Compile NHIS Estimates\n")
cat("========================================\n\n")

# 1. Load PHQ-2 estimate
cat("[1] Loading PHQ-2 estimate...\n")
phq2_est <- readRDS("data/raking/ne25/phq2_estimate.rds")

cat("    PHQ-2 estimate loaded\n")
cat("    Rows:", nrow(phq2_est), "\n")
cat("    Estimand:", unique(phq2_est$estimand), "\n")
cat("    Estimate:", round(phq2_est$estimate[1], 4), "\n\n")

# 2. Verify structure
cat("[2] Verifying structure...\n")
if (nrow(phq2_est) != 6) {
  stop("ERROR: PHQ-2 estimate should have 6 rows (ages 0-5)")
}
if (!all(phq2_est$age == 0:5)) {
  stop("ERROR: PHQ-2 estimate should have ages 0-5")
}
if (length(unique(phq2_est$estimate)) != 1) {
  stop("ERROR: PHQ-2 estimate should be constant across ages")
}

cat("    Structure verified\n")
cat("    All ages 0-5 present: YES\n")
cat("    Constant across ages: YES\n\n")

# 3. Create final NHIS estimates
cat("[3] Creating final NHIS estimates...\n")
nhis_estimates <- phq2_est

cat("    Final dimensions:", nrow(nhis_estimates), "rows x", ncol(nhis_estimates), "columns\n")
cat("    Estimands:", length(unique(nhis_estimates$estimand)), "\n\n")

# 4. Display summary
cat("[4] Summary of NHIS estimates:\n")
summary_table <- nhis_estimates %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    estimate = dplyr::first(estimate),
    .groups = "drop"
  )

print(summary_table)

cat("\n========================================\n")
cat("Task 3.3 Complete\n")
cat("========================================\n")
cat("\nNHIS Estimates Ready:\n")
cat("  - PHQ-2 Depression:", round(phq2_est$estimate[1] * 100, 1), "%\n")
cat("  - Total rows:", nrow(nhis_estimates), "\n\n")

# Return for next script
nhis_estimates
