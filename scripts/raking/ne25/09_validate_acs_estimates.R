# Phase 2, Task 2.9: Validate ACS Estimates
# Comprehensive validation: range checks, sum checks, age patterns

library(dplyr)

cat("\n========================================\n")
cat("Task 2.9: Validate ACS Estimates\n")
cat("========================================\n\n")

# 1. Load compiled estimates
cat("[1] Loading compiled ACS estimates...\n")
acs_estimates <- readRDS("data/raking/ne25/acs_estimates_compiled.rds")
acs_metadata <- readRDS("data/raking/ne25/acs_estimates_metadata.rds")

cat("    Loaded", nrow(acs_estimates), "rows\n")
cat("    Loaded", length(acs_metadata$estimands), "unique estimands\n")

# 2. Structural validation
cat("\n[2] Structural validation...\n")

# Check required columns
required_cols <- c("age", "estimand", "estimate")
missing_cols <- setdiff(required_cols, names(acs_estimates))

if (length(missing_cols) == 0) {
  cat("    ✓ All required columns present:", paste(required_cols, collapse = ", "), "\n")
} else {
  cat("    ✗ ERROR: Missing columns:", paste(missing_cols, collapse = ", "), "\n")
  stop("Missing required columns")
}

# Check for duplicates
duplicates <- acs_estimates %>%
  dplyr::group_by(age, estimand) %>%
  dplyr::filter(dplyr::n() > 1)

if (nrow(duplicates) == 0) {
  cat("    ✓ No duplicate (age, estimand) pairs\n")
} else {
  cat("    ✗ ERROR:", nrow(duplicates), "duplicate rows found\n")
  print(duplicates)
}

# Check age completeness
ages_expected <- 0:5
estimands <- unique(acs_estimates$estimand)

cat("    Checking age completeness for each estimand...\n")
incomplete_estimands <- c()

for (est in estimands) {
  est_data <- acs_estimates[acs_estimates$estimand == est, ]
  ages_present <- sort(unique(est_data$age))

  if (!all(ages_expected %in% ages_present)) {
    incomplete_estimands <- c(incomplete_estimands, est)
    cat("      ✗ Missing ages for", est, ":", setdiff(ages_expected, ages_present), "\n")
  }
}

if (length(incomplete_estimands) == 0) {
  cat("    ✓ All estimands have complete age coverage (0-5)\n")
} else {
  cat("    ✗ ERROR:", length(incomplete_estimands), "estimands with incomplete age coverage\n")
}

# 3. Range validation
cat("\n[3] Range validation (all estimates should be in [0, 1])...\n")

out_of_range <- acs_estimates[acs_estimates$estimate < 0 | acs_estimates$estimate > 1, ]

if (nrow(out_of_range) == 0) {
  cat("    ✓ All estimates in valid range [0, 1]\n")
} else {
  cat("    ✗ ERROR:", nrow(out_of_range), "estimates out of range\n")
  print(out_of_range)
}

cat("    Overall range:", round(min(acs_estimates$estimate), 4), "to",
    round(max(acs_estimates$estimate), 4), "\n")

# 4. Missing value validation
cat("\n[4] Missing value validation...\n")

missing_estimates <- sum(is.na(acs_estimates$estimate))
missing_ages <- sum(is.na(acs_estimates$age))
missing_estimands <- sum(is.na(acs_estimates$estimand))

cat("    Missing estimates:", missing_estimates, "\n")
cat("    Missing ages:", missing_ages, "\n")
cat("    Missing estimand labels:", missing_estimands, "\n")

if (missing_estimates == 0 && missing_ages == 0 && missing_estimands == 0) {
  cat("    ✓ No missing values detected\n")
} else {
  cat("    ✗ ERROR: Missing values detected\n")
}

# 5. Multinomial sum validation
cat("\n[5] Multinomial sum validation (FPL and PUMA should sum to 1.0)...\n")

# Check FPL categories sum to 1.0
cat("    Validating FPL categories...\n")
fpl_categories <- c("0-99%", "100-199%", "200-299%", "300-399%", "400%+")
fpl_data <- acs_estimates[acs_estimates$estimand %in% fpl_categories, ]

fpl_sums <- fpl_data %>%
  dplyr::group_by(age) %>%
  dplyr::summarise(sum = sum(estimate), .groups = "drop")

cat("      FPL sums by age:\n")
for (i in 1:nrow(fpl_sums)) {
  cat("        Age", fpl_sums$age[i], ":", round(fpl_sums$sum[i], 6), "\n")
}

if (all(abs(fpl_sums$sum - 1.0) < 0.001)) {
  cat("      ✓ All FPL sums within 0.001 of 1.0\n")
} else {
  cat("      ✗ WARNING: Some FPL sums deviate from 1.0\n")
}

# Check PUMA categories sum to 1.0
cat("\n    Validating PUMA categories...\n")
puma_data <- acs_estimates[grepl("^PUMA_", acs_estimates$estimand), ]

puma_sums <- puma_data %>%
  dplyr::group_by(age) %>%
  dplyr::summarise(sum = sum(estimate), .groups = "drop")

cat("      PUMA sums by age:\n")
for (i in 1:nrow(puma_sums)) {
  cat("        Age", puma_sums$age[i], ":", round(puma_sums$sum[i], 6), "\n")
}

if (all(abs(puma_sums$sum - 1.0) < 0.001)) {
  cat("      ✓ All PUMA sums within 0.001 of 1.0\n")
} else {
  cat("      ✗ WARNING: Some PUMA sums deviate from 1.0\n")
}

# 6. Age pattern validation
cat("\n[6] Age pattern validation...\n")

# Identify which estimands vary by age
cat("    Identifying age-varying vs. age-constant estimands...\n")

age_variation <- acs_estimates %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    min_est = min(estimate),
    max_est = max(estimate),
    range = max_est - min_est,
    sd = sd(estimate),
    .groups = "drop"
  ) %>%
  dplyr::arrange(dplyr::desc(range))

cat("\n    Estimands by age variation (range across ages 0-5):\n")
cat("      Estimand                       Range       SD\n")
cat("      ----------------------------------------  -------  -------\n")
for (i in 1:nrow(age_variation)) {
  cat("      ", sprintf("%-35s", age_variation$estimand[i]),
      sprintf("%7.4f", age_variation$range[i]),
      sprintf("%7.4f", age_variation$sd[i]), "\n", sep = "")
}

# Expected age-varying: Mother's education, Mother's marital status
expected_varying <- c("Mother Bachelor's+", "Mother Married")
expected_constant <- setdiff(estimands, expected_varying)

cat("\n    Expected age-varying estimands:\n")
for (est in expected_varying) {
  range_val <- age_variation$range[age_variation$estimand == est]
  if (range_val > 0.01) {
    cat("      ✓", est, "- Range:", round(range_val, 4), "(>0.01)\n")
  } else {
    cat("      ⚠", est, "- Range:", round(range_val, 4), "(<0.01, low variation)\n")
  }
}

# 7. Plausibility checks
cat("\n[7] Plausibility checks for Nebraska demographics...\n")

# Check sex ratio
sex_estimate <- mean(acs_estimates$estimate[acs_estimates$estimand == "Male"])
cat("    Sex ratio (male):", round(sex_estimate, 3), "\n")
if (sex_estimate >= 0.48 && sex_estimate <= 0.53) {
  cat("      ✓ Plausible (expect ~0.51)\n")
} else {
  cat("      ⚠ Outside typical range [0.48, 0.53]\n")
}

# Check race/ethnicity totals
race_categories <- c("White non-Hispanic", "Black", "Hispanic")
race_total <- sum(acs_estimates$estimate[acs_estimates$estimand %in% race_categories & acs_estimates$age == 0])
cat("\n    Race/ethnicity total (age 0):", round(race_total, 3), "\n")
cat("      Note: These are non-exclusive (Hispanic can be any race), so sum > 1.0 is expected\n")

# Check poverty rate
poverty_est <- mean(acs_estimates$estimate[acs_estimates$estimand == "0-99%"])
cat("\n    Below poverty (0-99%):", round(poverty_est * 100, 1), "%\n")
if (poverty_est >= 0.10 && poverty_est <= 0.20) {
  cat("      ✓ Plausible for Nebraska (expect ~12-18%)\n")
} else {
  cat("      ⚠ Outside typical Nebraska range [10%, 20%]\n")
}

# Check mother's education
mom_educ_est <- mean(acs_estimates$estimate[acs_estimates$estimand == "Mother Bachelor's+"])
cat("\n    Mother's education (Bachelor's+):", round(mom_educ_est * 100, 1), "%\n")
if (mom_educ_est >= 0.40 && mom_educ_est <= 0.50) {
  cat("      ✓ Plausible for Nebraska (expect ~44-47%)\n")
} else {
  cat("      ⚠ Outside typical Nebraska range [40%, 50%]\n")
}

# Check mother's marital status
mom_married_est <- mean(acs_estimates$estimate[acs_estimates$estimand == "Mother Married"])
cat("\n    Mother's marital status (married):", round(mom_married_est * 100, 1), "%\n")
if (mom_married_est >= 0.70 && mom_married_est <= 0.85) {
  cat("      ✓ Plausible for Nebraska (expect ~79-84%)\n")
} else {
  cat("      ⚠ Outside typical Nebraska range [70%, 85%]\n")
}

# 8. Summary report
cat("\n========================================\n")
cat("Validation Summary\n")
cat("========================================\n\n")

validation_summary <- list(
  total_rows = nrow(acs_estimates),
  total_estimands = length(estimands),
  age_range = c(min(acs_estimates$age), max(acs_estimates$age)),
  estimate_range = c(min(acs_estimates$estimate), max(acs_estimates$estimate)),
  missing_values = missing_estimates + missing_ages + missing_estimands,
  out_of_range_values = nrow(out_of_range),
  duplicate_rows = nrow(duplicates),
  fpl_sum_check = all(abs(fpl_sums$sum - 1.0) < 0.001),
  puma_sum_check = all(abs(puma_sums$sum - 1.0) < 0.001),
  validation_date = Sys.time()
)

cat("Total rows:", validation_summary$total_rows, "\n")
cat("Total estimands:", validation_summary$total_estimands, "\n")
cat("Age range:", validation_summary$age_range[1], "to", validation_summary$age_range[2], "\n")
cat("Estimate range:", round(validation_summary$estimate_range[1], 4), "to",
    round(validation_summary$estimate_range[2], 4), "\n")
cat("\nData Quality Checks:\n")
cat("  Missing values:", validation_summary$missing_values, "\n")
cat("  Out-of-range values:", validation_summary$out_of_range_values, "\n")
cat("  Duplicate rows:", validation_summary$duplicate_rows, "\n")
cat("  FPL sum check:", ifelse(validation_summary$fpl_sum_check, "PASS", "FAIL"), "\n")
cat("  PUMA sum check:", ifelse(validation_summary$puma_sum_check, "PASS", "FAIL"), "\n")

# Determine overall validation status
all_checks_pass <- (
  validation_summary$missing_values == 0 &&
  validation_summary$out_of_range_values == 0 &&
  validation_summary$duplicate_rows == 0 &&
  validation_summary$fpl_sum_check &&
  validation_summary$puma_sum_check
)

if (all_checks_pass) {
  cat("\n✓ ALL VALIDATION CHECKS PASSED\n")
} else {
  cat("\n⚠ SOME VALIDATION CHECKS FAILED - Review output above\n")
}

# 9. Save validation report
cat("\n[9] Saving validation report...\n")
saveRDS(validation_summary, "data/raking/ne25/acs_validation_report.rds")
cat("    Saved to: data/raking/ne25/acs_validation_report.rds\n")

cat("\n========================================\n")
cat("Task 2.9 Complete\n")
cat("========================================\n\n")
