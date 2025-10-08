# Phase 4, Tasks 4.6-4.8: Validate and Save NSCH Estimates
# 4 estimands, 24 rows total (3 from 2023 + 1 from 2022)

library(dplyr)

cat("\n========================================\n")
cat("Tasks 4.6-4.8: Validate & Save NSCH Estimates\n")
cat("========================================\n\n")

# 1. Load estimates
cat("[1] Loading NSCH estimates...\n")
nsch_2023 <- readRDS("data/raking/ne25/nsch_estimates_raw_glm2.rds")
childcare_2022 <- readRDS("data/raking/ne25/childcare_2022_estimates.rds")

cat("    NSCH 2023 estimates:", nrow(nsch_2023), "rows (3 estimands)\n")
cat("    Child care 2022:", nrow(childcare_2022), "rows (1 estimand)\n")

# Combine
nsch_est <- dplyr::bind_rows(nsch_2023, childcare_2022)

cat("    Combined total:", nrow(nsch_est), "rows\n")
cat("    Total estimands:", length(unique(nsch_est$estimand)), "\n\n")

# 2. Validation checks
cat("[2] Running validation checks...\n\n")

validation_passed <- TRUE

# Check 2.1: Total rows
cat("  [2.1] Row count check:\n")
if (nrow(nsch_est) != 24) {
  cat("    [ERROR] Expected 24 rows, got", nrow(nsch_est), "\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] 24 rows (4 estimands × 6 ages)\n")
}

# Check 2.2: All ages present
cat("\n  [2.2] Age coverage check:\n")
ages_present <- sort(unique(nsch_est$age))
if (!all(ages_present == 0:5)) {
  cat("    [ERROR] Not all ages 0-5 present\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] All ages 0-5 present\n")
}

# Check 2.3: Range checks (0-1 or NA)
cat("\n  [2.3] Range checks:\n")
non_na <- nsch_est$estimate[!is.na(nsch_est$estimate)]
if (any(non_na < 0 | non_na > 1)) {
  cat("    [ERROR] Some estimates outside [0, 1] range\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] All non-NA estimates in [0, 1] range\n")
}

# Check 2.4: Age pattern check (should vary, not be constant)
cat("\n  [2.4] Age pattern check (estimates should vary by age):\n")
for (est_name in unique(nsch_est$estimand)) {
  est_vals <- nsch_est %>%
    dplyr::filter(estimand == est_name) %>%
    dplyr::pull(estimate)

  # Remove NAs for variance check
  est_vals_no_na <- est_vals[!is.na(est_vals)]

  if (length(est_vals_no_na) > 1) {
    variance <- var(est_vals_no_na)
    if (variance < 1e-10) {
      cat("    [WARN]", est_name, "is constant across ages (variance =",
          round(variance, 8), ")\n")
    } else {
      cat("    [OK]", est_name, "varies by age (variance =",
          round(variance, 5), ")\n")
    }
  }
}

# Check 2.5: NA pattern for emotional/behavioral (ages 0-2 should be NA)
cat("\n  [2.5] NA pattern check for Emotional/Behavioral Problems:\n")
emot_data <- nsch_est %>%
  dplyr::filter(estimand == "Emotional/Behavioral Problems")

na_ages_02 <- emot_data %>%
  dplyr::filter(age %in% 0:2) %>%
  dplyr::pull(estimate) %>%
  is.na() %>%
  all()

na_ages_35 <- emot_data %>%
  dplyr::filter(age %in% 3:5) %>%
  dplyr::pull(estimate) %>%
  is.na() %>%
  any()

if (!na_ages_02) {
  cat("    [ERROR] Ages 0-2 should be NA for Emotional/Behavioral\n")
  validation_passed <- FALSE
} else if (na_ages_35) {
  cat("    [ERROR] Ages 3-5 should NOT be NA for Emotional/Behavioral\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] Ages 0-2 = NA, ages 3-5 = non-NA\n")
}

# Check 2.6: Plausibility checks
cat("\n  [2.6] Plausibility checks:\n")

# ACE exposure: Should increase with age
ace_data <- nsch_est %>%
  dplyr::filter(estimand == "Child ACE Exposure (1+ ACEs)") %>%
  dplyr::arrange(age)

ace_trend <- cor(ace_data$age, ace_data$estimate, method = "spearman")
if (ace_trend < 0) {
  cat("    [WARN] ACE exposure decreases with age (expected increase)\n")
} else {
  cat("    [OK] ACE exposure increases with age (r =", round(ace_trend, 3), ")\n")
}

# Excellent health: Should be 50-90%
health_data <- nsch_est %>%
  dplyr::filter(estimand == "Excellent Health Rating")

health_range <- range(health_data$estimate)
if (health_range[1] < 0.5 | health_range[2] > 0.9) {
  cat("    [WARN] Excellent health outside typical 50-90% range:",
      round(health_range[1]*100, 1), "-", round(health_range[2]*100, 1), "%\n")
} else {
  cat("    [OK] Excellent health in plausible range:",
      round(health_range[1]*100, 1), "-", round(health_range[2]*100, 1), "%\n")
}

cat("\n")

# 3. Summary
cat("[3] Validation Summary:\n")
if (validation_passed) {
  cat("    Status: PASSED\n")
  cat("    All validation checks passed\n\n")
} else {
  cat("    Status: FAILED\n")
  cat("    Some validation checks failed\n\n")
}

# 4. Display estimates by estimand
cat("[4] NSCH Estimates Summary:\n\n")

for (est_name in unique(nsch_est$estimand)) {
  cat("  ", est_name, ":\n", sep = "")
  est_subset <- nsch_est %>%
    dplyr::filter(estimand == est_name) %>%
    dplyr::arrange(age)

  for (i in 1:nrow(est_subset)) {
    if (is.na(est_subset$estimate[i])) {
      cat("    Age", est_subset$age[i], ": NA\n")
    } else {
      cat("    Age", est_subset$age[i], ":",
          round(est_subset$estimate[i], 4),
          "(", round(est_subset$estimate[i]*100, 1), "%)\n")
    }
  }
  cat("\n")
}

# 5. Save final estimates
cat("[5] Saving final NSCH estimates...\n")
saveRDS(nsch_est, "data/raking/ne25/nsch_estimates.rds")

cat("    Saved to: data/raking/ne25/nsch_estimates.rds\n")
cat("    Dimensions:", nrow(nsch_est), "rows x", ncol(nsch_est), "columns\n\n")

cat("========================================\n")
cat("Tasks 4.6-4.8 Complete\n")
cat("========================================\n\n")

validation_passed
