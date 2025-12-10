################################################################################
# Phase 2b (Motor Only): Fit Rasch Model for Motor Development on Augmented Data
################################################################################
# Fits Rasch model to Motor Development using NE25 + NSCH 2022 combined dataset
# to improve calibrations for DrawFace, DrawPerson, BounceBall
################################################################################

library(dplyr)
library(mirt)

message("=== Phase 2b (Motor Only): Rasch Model with Augmented Data ===\n")

# Load the augmented Motor Development dataset
message("1. Loading augmented Motor Development data...\n")
augmented_motor <- readRDS("scripts/temp/hrtl_augmented_motor_ne25_nsch2022.rds")

message(sprintf("  Total records: %d\n", nrow(augmented_motor)))
message(sprintf("  NE25: %d\n", sum(augmented_motor$source == "ne25")))
message(sprintf("  NSCH: %d\n", sum(augmented_motor$source == "nsch_2022")))

# ==============================================================================
# 2. PREPARE DATA FOR MIRT
# ==============================================================================
message("\n2. Preparing Motor Development data for Rasch modeling...\n")

motor_items <- c("nom042x", "nom029x", "nom033x", "nom034x")

# Extract item matrix
item_matrix <- as.matrix(augmented_motor[, motor_items])

# Check missing data
n_missing <- sum(is.na(item_matrix))
pct_missing <- 100 * n_missing / (nrow(item_matrix) * ncol(item_matrix))
message(sprintf("  Items: %d", length(motor_items)))
message(sprintf("  Missing data: %d (%.2f%%)\n", n_missing, pct_missing))

# ==============================================================================
# 3. FIT RASCH MODEL
# ==============================================================================
message("3. Fitting Rasch model (1PL with SC_AGE_YEARS covariate)...\n")

tryCatch({
  # Create constraint for equal slopes across all items (1PL Rasch model)
  pars <- mirt(item_matrix, 1, itemtype = 'graded', pars = 'values')
  slopes <- pars[pars$name == 'a1', 'parnum']

  # Fit 1PL Rasch model with equal slopes (no latent regression for now)
  rasch_fit <- mirt(
    data = item_matrix,
    model = 1,
    itemtype = 'graded',
    constrain = list(slopes),
    verbose = FALSE,
    SE = TRUE,
    SE.type = 'Richardson'
  )

  message("  [OK] Rasch model fitted successfully\n")

  # ==============================================================================
  # 4. EXTRACT ABILITY ESTIMATES
  # ==============================================================================
  message("4. Computing ability estimates...\n")

  theta_scores <- mirt::fscores(rasch_fit, method = "EAP", full.scores = TRUE)
  if (!is.matrix(theta_scores)) {
    theta_scores <- as.matrix(theta_scores)
  }

  message(sprintf("  EAP theta range: [%.2f, %.2f]\n", min(theta_scores), max(theta_scores)))

  # ==============================================================================
  # 5. SAVE RASCH MODEL
  # ==============================================================================
  message("5. Saving Motor Development Rasch model...\n")

  motor_rasch_model <- list(
    model = rasch_fit,
    items = motor_items,
    n_records = nrow(augmented_motor),
    n_ne25 = sum(augmented_motor$source == "ne25"),
    n_nsch = sum(augmented_motor$source == "nsch_2022")
  )

  saveRDS(motor_rasch_model, "scripts/temp/hrtl_rasch_motor_augmented.rds")
  message("[OK] Saved to scripts/temp/hrtl_rasch_motor_augmented.rds\n")

  message("[OK] Motor Development Rasch model complete!")

}, error = function(e) {
  stop(sprintf("\n[FATAL ERROR] Rasch model fitting failed: %s", e$message))
})
