# Phase 4.2: Estimate NSCH Outcomes (GLM2 Version)
# 3 estimands: Child ACEs, Emotional/Behavioral, Excellent Health
# Refactored to use glm2::glm2() instead of survey::svyglm()

library(dplyr)
library(glm2)

cat("\n========================================\n")
cat("NSCH Outcomes: GLM2 Version\n")
cat("========================================\n\n")

# Load configuration and helper functions
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

# ========================================
# SECTION 1: LOAD SHARED BOOTSTRAP DESIGN
# ========================================
cat("[1] Loading shared NSCH bootstrap design...\n")

# Load the shared bootstrap design created by 17a_create_nsch_bootstrap_design.R
# This design already includes MICE-imputed ACE data and bootstrap replicate weights
boot_design_full <- readRDS("data/raking/ne25/nsch_bootstrap_design.rds")
replicate_weights_full <- boot_design_full$repweights

cat("    Bootstrap design loaded\n")
cat("    Sample size:", nrow(boot_design_full$variables), "\n")
cat("    Number of replicates:", ncol(replicate_weights_full), "\n\n")

# Extract data from bootstrap design
nsch_data <- boot_design_full$variables

# ========================================
# SECTION 2: CREATE OUTCOME VARIABLES
# ========================================
cat("[2] Creating outcome variables...\n")

nsch_data <- nsch_data %>%
  dplyr::mutate(
    # ACE 1+ exposure (any ACE indicator = 1)
    ace_1plus = as.numeric(
      ACE1_binary == 1 | ACE3_binary == 1 | ACE4_binary == 1 |
      ACE5_binary == 1 | ACE6_binary == 1 | ACE7_binary == 1 |
      ACE8_binary == 1 | ACE9_binary == 1 | ACE10_binary == 1 |
      ACE11_binary == 1
    ),

    # Emotional/behavioral problems (MEDB10ScrQ5: 1=Yes, 2=No)
    emot_behav_prob = dplyr::case_when(
      MEDB10ScrQ5 == 1 ~ 1,
      MEDB10ScrQ5 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # Excellent health (K2Q01: 1=Excellent, 2-5=Other)
    excellent_health = dplyr::case_when(
      K2Q01 == 1 ~ 1,  # Excellent
      K2Q01 %in% 2:5 ~ 0,  # Good, Fair, Poor
      TRUE ~ NA_real_
    )
  )

cat("    Outcome variables created:\n")
cat("      - ace_1plus\n")
cat("      - emot_behav_prob (ages 3-5 only)\n")
cat("      - excellent_health\n\n")

# ========================================
# SECTION 3: ACE EXPOSURE MODEL (AGES 0-5)
# ========================================
cat("[3] Estimating ACE Exposure (1+ ACEs) for ages 0-5...\n")

# Filter to complete cases for ACE outcome
ace_data <- nsch_data %>%
  dplyr::filter(!is.na(ace_1plus))

cat("    Sample size:", nrow(ace_data), "\n")

# Subset replicate weights to match filtered data
ace_indicator <- !is.na(nsch_data$ace_1plus)
replicate_weights_ace <- replicate_weights_full[ace_indicator, ]

# Respect bootstrap config
n_boot <- BOOTSTRAP_CONFIG$n_boot
if (ncol(replicate_weights_ace) > n_boot) {
  cat("    [INFO] Using first", n_boot, "replicates (from", ncol(replicate_weights_ace), "available)\n")
  replicate_weights_ace <- replicate_weights_ace[, 1:n_boot]
}

# Prediction data: year 2023 for ages 0-5
pred_data_ace <- data.frame(
  SC_AGE_YEARS = 0:5,
  survey_year = 2023
)

# Fit main model with glm2
cat("    Fitting ACE model with glm2...\n")

# Add weights as column
ace_modeling <- ace_data
ace_modeling$.weights <- ace_data$FWC

# Fit model
model_ace <- glm2::glm2(
  ace_1plus ~ as.factor(SC_AGE_YEARS) + survey_year,
  data = ace_modeling,
  weights = ace_modeling$.weights,
  family = binomial()
)

cat("    Model converged in", model_ace$iter, "iterations\n")

# Predict for year 2023
ace_predictions <- predict(model_ace, newdata = pred_data_ace, type = "response")

# Format point estimates
ace_estimates <- data.frame(
  age = 0:5,
  estimand = "Child ACE Exposure (1+ ACEs)",
  estimate = as.numeric(ace_predictions)
)

# Generate bootstrap
cat("    Generating bootstrap replicates...\n")
boot_result_ace <- generate_bootstrap_glm2(
  data = ace_modeling,
  formula = ace_1plus ~ as.factor(SC_AGE_YEARS) + survey_year,
  replicate_weights = replicate_weights_ace,
  pred_data = pred_data_ace
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(ace_estimates$estimate[i], 3), "\n")
}
cat("\n")

# Format bootstrap results
ace_boot <- data.frame(
  age = rep(0:5, times = n_boot),
  estimand = "ace_exposure",
  replicate = rep(1:n_boot, each = 6),
  estimate = as.vector(boot_result_ace$boot_estimates)
)

cat("    Bootstrap rows:", nrow(ace_boot), "(6 ages x", n_boot, "replicates)\n\n")

# Save bootstrap replicates
saveRDS(ace_boot, "data/raking/ne25/ace_exposure_boot_glm2.rds")
cat("    Saved to: data/raking/ne25/ace_exposure_boot_glm2.rds\n\n")

# ========================================
# SECTION 4: EMOTIONAL/BEHAVIORAL MODEL (AGES 3-5 ONLY)
# ========================================
cat("[4] Estimating Emotional/Behavioral Problems for ages 3-5...\n")

# Filter to ages 3-5 with complete outcome data
emot_data <- nsch_data %>%
  dplyr::filter(!is.na(emot_behav_prob) & SC_AGE_YEARS >= 3)

cat("    Sample size (ages 3-5):", nrow(emot_data), "\n")

# Subset replicate weights
emot_indicator <- !is.na(nsch_data$emot_behav_prob) & nsch_data$SC_AGE_YEARS >= 3
replicate_weights_emot <- replicate_weights_full[emot_indicator, ]

if (ncol(replicate_weights_emot) > n_boot) {
  replicate_weights_emot <- replicate_weights_emot[, 1:n_boot]
}

# Prediction data: year 2023 for ages 3-5
pred_data_emot <- data.frame(
  SC_AGE_YEARS = 3:5,
  survey_year = 2023
)

# Fit main model with glm2
cat("    Fitting emotional/behavioral model with glm2...\n")

# Add weights as column
emot_modeling <- emot_data
emot_modeling$.weights <- emot_data$FWC

# Fit model
model_emot <- glm2::glm2(
  emot_behav_prob ~ as.factor(SC_AGE_YEARS) + survey_year,
  data = emot_modeling,
  weights = emot_modeling$.weights,
  family = binomial()
)

cat("    Model converged in", model_emot$iter, "iterations\n")

# Predict for year 2023
emot_predictions <- predict(model_emot, newdata = pred_data_emot, type = "response")

# Create estimates with NA for ages 0-2
emot_estimates <- data.frame(
  age = 0:5,
  estimand = "Emotional/Behavioral Problems",
  estimate = c(rep(NA_real_, 3), as.numeric(emot_predictions))  # NA for ages 0-2
)

# Generate bootstrap
cat("    Generating bootstrap replicates...\n")
boot_result_emot <- generate_bootstrap_glm2(
  data = emot_modeling,
  formula = emot_behav_prob ~ as.factor(SC_AGE_YEARS) + survey_year,
  replicate_weights = replicate_weights_emot,
  pred_data = pred_data_emot
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  if (is.na(emot_estimates$estimate[i])) {
    cat("      Age", i-1, ": NA (not measured for ages 0-2)\n")
  } else {
    cat("      Age", i-1, ":", round(emot_estimates$estimate[i], 3), "\n")
  }
}
cat("\n")

# Format bootstrap with NA for ages 0-2
emot_boot_ages35 <- data.frame(
  age = rep(3:5, times = n_boot),
  estimand = "emotional_behavioral",
  replicate = rep(1:n_boot, each = 3),
  estimate = as.vector(boot_result_emot$boot_estimates)
)

emot_boot_ages02 <- data.frame(
  age = rep(0:2, times = n_boot),
  estimand = "emotional_behavioral",
  replicate = rep(1:n_boot, each = 3),
  estimate = NA_real_
)

emot_boot <- dplyr::bind_rows(emot_boot_ages02, emot_boot_ages35) %>%
  dplyr::arrange(replicate, age)

cat("    Bootstrap rows:", nrow(emot_boot), "(6 ages x", n_boot, "replicates, NA for ages 0-2)\n\n")

# Save bootstrap replicates
saveRDS(emot_boot, "data/raking/ne25/emotional_behavioral_boot_glm2.rds")
cat("    Saved to: data/raking/ne25/emotional_behavioral_boot_glm2.rds\n\n")

# ========================================
# SECTION 5: EXCELLENT HEALTH MODEL (AGES 0-5)
# ========================================
cat("[5] Estimating Excellent Health Rating for ages 0-5...\n")

# Filter to complete cases
health_data <- nsch_data %>%
  dplyr::filter(!is.na(excellent_health))

cat("    Sample size:", nrow(health_data), "\n")

# Subset replicate weights
health_indicator <- !is.na(nsch_data$excellent_health)
replicate_weights_health <- replicate_weights_full[health_indicator, ]

if (ncol(replicate_weights_health) > n_boot) {
  replicate_weights_health <- replicate_weights_health[, 1:n_boot]
}

# Prediction data: year 2023 for ages 0-5
pred_data_health <- data.frame(
  SC_AGE_YEARS = 0:5,
  survey_year = 2023
)

# Fit main model with glm2
cat("    Fitting excellent health model with glm2...\n")

# Add weights as column
health_modeling <- health_data
health_modeling$.weights <- health_data$FWC

# Fit model
model_health <- glm2::glm2(
  excellent_health ~ as.factor(SC_AGE_YEARS) + survey_year,
  data = health_modeling,
  weights = health_modeling$.weights,
  family = binomial()
)

cat("    Model converged in", model_health$iter, "iterations\n")

# Predict for year 2023
health_predictions <- predict(model_health, newdata = pred_data_health, type = "response")

# Format point estimates
health_estimates <- data.frame(
  age = 0:5,
  estimand = "Excellent Health Rating",
  estimate = as.numeric(health_predictions)
)

# Generate bootstrap
cat("    Generating bootstrap replicates...\n")
boot_result_health <- generate_bootstrap_glm2(
  data = health_modeling,
  formula = excellent_health ~ as.factor(SC_AGE_YEARS) + survey_year,
  replicate_weights = replicate_weights_health,
  pred_data = pred_data_health
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(health_estimates$estimate[i], 3), "\n")
}
cat("\n")

# Format bootstrap results
health_boot <- data.frame(
  age = rep(0:5, times = n_boot),
  estimand = "excellent_health",
  replicate = rep(1:n_boot, each = 6),
  estimate = as.vector(boot_result_health$boot_estimates)
)

cat("    Bootstrap rows:", nrow(health_boot), "(6 ages x", n_boot, "replicates)\n\n")

# Save bootstrap replicates
saveRDS(health_boot, "data/raking/ne25/excellent_health_boot_glm2.rds")
cat("    Saved to: data/raking/ne25/excellent_health_boot_glm2.rds\n\n")

# ========================================
# SECTION 6: COMBINE AND SAVE RESULTS
# ========================================
cat("[6] Combining all NSCH estimates...\n")

nsch_estimates <- dplyr::bind_rows(
  ace_estimates,
  emot_estimates,
  health_estimates
)

cat("    Total rows:", nrow(nsch_estimates), "\n")
cat("    Estimands:", length(unique(nsch_estimates$estimand)), "\n")
cat("    Ages per estimand: 6 (0-5)\n\n")

# Verify structure
cat("    Estimate ranges:\n")
for (est in unique(nsch_estimates$estimand)) {
  est_data <- nsch_estimates$estimate[nsch_estimates$estimand == est]
  est_data <- est_data[!is.na(est_data)]  # Remove NAs for range
  cat("      ", est, ":", round(min(est_data), 3), "-", round(max(est_data), 3), "\n")
}
cat("\n")

# Save results
cat("[6.2] Saving NSCH estimates...\n")
saveRDS(nsch_estimates, "data/raking/ne25/nsch_estimates_raw_glm2.rds")
cat("    Saved to: data/raking/ne25/nsch_estimates_raw_glm2.rds\n\n")

cat("========================================\n")
cat("NSCH OUTCOMES ESTIMATION COMPLETE (GLM2)\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - 3 estimands: ACE exposure, Emotional/behavioral, Excellent health\n")
cat("  - Multi-year data pooling (2020-2023)\n")
cat("  - MICE-imputed ACE indicators (from bootstrap design)\n")
cat("  - GLM2 models with year main effects\n")
cat("  - Predictions at year 2023\n")
cat("  - Bootstrap replicates:", n_boot, "\n")
cat("  - Total bootstrap rows:", nrow(ace_boot) + nrow(emot_boot) + nrow(health_boot), "\n\n")
