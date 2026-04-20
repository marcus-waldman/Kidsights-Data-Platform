# Phase 3, Task 3.3: Estimate Maternal ACEs
# 3 estimands: 0 ACEs, 1 ACE, 2+ ACEs (multinomial)
# Using IRT/Rasch model with EAPsum scoring to handle missing data

library(survey)
library(dplyr)
library(mirt)

cat("\n========================================\n")
cat("Task 3.3: Estimate Maternal ACEs\n")
cat("========================================\n\n")

# 1. Load ACE data
cat("[1] Loading ACE data...\n")
ace_data <- readRDS("data/raking/ne25/nhis_ace_data.rds")
cat("    Total parent-child pairs:", nrow(ace_data), "\n")
cat("    Years:", paste(sort(unique(ace_data$YEAR)), collapse = ", "), "\n")

# 2. Prepare ACE binary matrix
cat("\n[2] Preparing ACE binary items (8 items)...\n")

ace_vars <- c("VIOLENEV_parent", "JAILEV_parent", "MENTDEPEV_parent", "ALCDRUGEV_parent",
              "ADLTPUTDOWN_parent", "UNFAIRRACE_parent", "UNFAIRSEXOR_parent", "BASENEED_parent")

# Create binary matrix: 1=Yes (experienced ACE), 0=No, NA=Missing
ace_items <- matrix(NA, nrow = nrow(ace_data), ncol = 8)
colnames(ace_items) <- c("Violence", "Incarceration", "MentalIllness", "SubstanceAbuse",
                         "PutDown", "RaceDiscrim", "SexDiscrim", "BasicNeeds")

for (i in 1:8) {
  var <- ace_vars[i]
  # Check actual value distribution
  cat("      ", colnames(ace_items)[i], " values: ",
      paste(sort(unique(ace_data[[var]])), collapse = ", "), "\n", sep = "")

  # The values appear to already be 0/1/NA (not IPUMS 1/2 codes)
  # Just copy them directly
  ace_items[, i] <- as.numeric(ace_data[[var]])
}

# Check missingness pattern
cat("    Item-level missingness:\n")
for (i in 1:8) {
  n_valid <- sum(!is.na(ace_items[, i]))
  pct <- round(n_valid / nrow(ace_items) * 100, 1)
  cat("      ", colnames(ace_items)[i], ": ", n_valid, " (", pct, "%)\n", sep = "")
}

# Count respondents with at least 1 item
n_any_data <- sum(rowSums(!is.na(ace_items)) > 0)
cat("\n    Respondents with at least 1 ACE item:", n_any_data, "\n")

# 3. Fit Rasch model
cat("\n[3] Fitting Rasch model to ACE items...\n")

ace_model <- mirt::mirt(
  data = ace_items,
  model = 1,
  itemtype = 'Rasch',
  verbose = FALSE
)

cat("    Rasch model fitted successfully\n")

# 4. Extract EAPsum scores
cat("\n[4] Extracting EAPsum scores (handles missing data via IRT)...\n")

ace_eapsum <- mirt::fscores(ace_model, method = "EAPsum")

cat("    EAPsum scores extracted for all", nrow(ace_eapsum), "respondents\n")

cat("\n    EAPsum distribution:\n")
cat("      Min:", round(min(ace_eapsum, na.rm = TRUE), 2), "\n")
cat("      Max:", round(max(ace_eapsum, na.rm = TRUE), 2), "\n")
cat("      Mean:", round(mean(ace_eapsum, na.rm = TRUE), 2), "\n")
cat("      Median:", round(median(ace_eapsum, na.rm = TRUE), 2), "\n")

# 5. Categorize into 0, 1, 2+ ACEs
cat("\n[5] Categorizing into ACE groups (0, 1, 2+)...\n")

ace_data$ace_eapsum <- ace_eapsum[, 1]

ace_data <- ace_data %>%
  dplyr::mutate(
    ace_category = dplyr::case_when(
      ace_eapsum < 0.5 ~ "0 ACEs",
      ace_eapsum < 1.5 ~ "1 ACE",
      ace_eapsum >= 1.5 ~ "2+ ACEs",
      TRUE ~ NA_character_
    )
  )

cat("    ACE category distribution:\n")
print(table(ace_data$ace_category, useNA = "ifany"))

# Filter to cases with valid EAPsum
ace_data_complete <- ace_data %>% dplyr::filter(!is.na(ace_category))
cat("\n    Valid cases:", nrow(ace_data_complete), "\n")
cat("    Excluded:", nrow(ace_data) - nrow(ace_data_complete), "\n")

# 6. Create survey design
cat("\n[6] Creating survey design...\n")
ace_design <- survey::svydesign(
  ids = ~PSU_child,
  strata = ~STRATA_child,
  weights = ~SAMPWEIGHT_parent,
  data = ace_data_complete,
  nest = TRUE
)
cat("    Sample size:", nrow(ace_design), "\n")

# 7. Estimate ACE categories with year main effects
cat("\n[7] Estimating ACE categories (survey-weighted, year main effects)...\n")

categories <- c("0 ACEs", "1 ACE", "2+ ACEs")
ace_raw_estimates <- numeric(3)

for (i in 1:3) {
  cat("    Fitting model for", categories[i], "...\n")
  ace_design$variables$current_cat <- as.numeric(ace_design$variables$ace_category == categories[i])

  model <- survey::svyglm(
    current_cat ~ YEAR,
    design = ace_design,
    family = quasibinomial()
  )

  # Predict at 2023
  pred <- predict(model, newdata = data.frame(YEAR = 2023), type = "response")[1]
  ace_raw_estimates[i] <- pred
}

# Normalize to sum to 1.0
ace_estimates_normalized <- ace_raw_estimates / sum(ace_raw_estimates)

cat("\n    Normalized estimates (at 2023):\n")
for (i in 1:3) {
  cat("      ", categories[i], ": ", round(ace_estimates_normalized[i], 4),
      " (", round(ace_estimates_normalized[i] * 100, 1), "%)\n", sep = "")
}

cat("\n    Sum check:", round(sum(ace_estimates_normalized), 6), "\n")

# 8. Create results data frame
cat("\n[8] Creating results data frame...\n")

ace_result <- data.frame(
  age = rep(0:5, each = 3),
  estimand = rep(categories, 6),
  estimate = rep(ace_estimates_normalized, 6)
)

cat("    Sample rows (age 0):\n")
print(ace_result[1:3, ])

# 9. Validate
cat("\n[9] Validation...\n")

# Check sum to 1.0 for each age
age_sums <- ace_result %>%
  dplyr::group_by(age) %>%
  dplyr::summarise(sum = sum(estimate), .groups = "drop")

if (all(abs(age_sums$sum - 1.0) < 0.001)) {
  cat("    \u2713 All age groups sum to 1.0\n")
} else {
  cat("    \u2717 ERROR: Some sums deviate from 1.0\n")
}

# Plausibility check
cat("\n    Plausibility (national ACE rates):\n")
cat("      0 ACEs:", round(ace_estimates_normalized[1] * 100, 1), "% (expect ~40-60%)\n")
cat("      1 ACE:", round(ace_estimates_normalized[2] * 100, 1), "% (expect ~20-30%)\n")
cat("      2+ ACEs:", round(ace_estimates_normalized[3] * 100, 1), "% (expect ~20-30%)\n")

# 10. Save
cat("\n[10] Saving ACE estimates...\n")
saveRDS(ace_result, "data/raking/ne25/ace_estimates.rds")
cat("    Saved to: data/raking/ne25/ace_estimates.rds\n")

# Save scored data
saveRDS(ace_data_complete, "data/raking/ne25/nhis_ace_scored.rds")
cat("    Saved scored data to: data/raking/ne25/nhis_ace_scored.rds\n")

cat("\n========================================\n")
cat("Task 3.3 Complete\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Sample size:", nrow(ace_data_complete), "cases (IRT/EAPsum scoring)\n")
cat("  - Method: Rasch model with EAPsum (handles missing items)\n")
cat("  - 0 ACEs:", round(ace_estimates_normalized[1] * 100, 1), "%\n")
cat("  - 1 ACE:", round(ace_estimates_normalized[2] * 100, 1), "%\n")
cat("  - 2+ ACEs:", round(ace_estimates_normalized[3] * 100, 1), "%\n\n")
