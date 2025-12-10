################################################################################
# Phase 2c: Generate Imputed Item Data Using Rasch Models
################################################################################

library(dplyr)
library(mirt)

message("=== Phase 2c: Imputing Missing Values Using Rasch Models ===\n")

# ==============================================================================
# 1. LOAD RASCH MODELS AND DOMAIN DATA
# ==============================================================================
message("1. Loading Rasch models and domain data...")

rasch_models <- readRDS("scripts/hrtl/hrtl_rasch_models.rds")
domain_datasets <- readRDS("scripts/hrtl/hrtl_domain_datasets.rds")

message(sprintf("  [OK] Loaded %d Rasch models\n", length(rasch_models)))
message(sprintf("  [OK] Loaded %d domain datasets\n", length(domain_datasets)))

# ==============================================================================
# 2. GENERATE IMPUTED DATA FOR EACH DOMAIN
# ==============================================================================
message("2. Generating imputed item data using Rasch models...\n")

imputed_data_list <- list()

for (domain in names(rasch_models)) {
  message(sprintf("\nDomain: %s", domain))
  message(sprintf("%s", strrep("-", 70)))

  rasch_model <- rasch_models[[domain]]
  domain_data <- domain_datasets[[domain]]$data
  item_vars <- domain_datasets[[domain]]$variables

  # Extract only the item columns (exclude auxiliary columns)
  item_data <- domain_data[, item_vars]

  message(sprintf("  Original data: %d children × %d items",
                  nrow(item_data), ncol(item_data)))

  # Count missing values before imputation
  n_missing_before <- sum(is.na(item_data))
  pct_missing_before <- 100 * n_missing_before / (nrow(item_data) * ncol(item_data))
  message(sprintf("  Missing before: %d (%.2f%%)", n_missing_before, pct_missing_before))

  # ==============================================================================
  # IMPUTE USING RASCH MODEL
  # ==============================================================================
  message("  Imputing missing values using Rasch model...")

  tryCatch({
    # Extract covariates from domain data for fscores
    domain_covdata <- domain_data[, c("kidsights_2022", "general_gsed_pf_2022")]

    # Estimate Theta (ability) for each child using EAP method
    # This gives us a matrix with 1 column (unidimensional model)
    theta_eap <- mirt::fscores(rasch_model,
                              method = "EAP",
                              full.scores = TRUE,
                              full.scores.SE = FALSE, 
                              covdata = domain_covdata)

    # Ensure theta_eap is a matrix
    if (is.vector(theta_eap)) {
      theta_eap <- matrix(theta_eap, ncol = 1)
    } else if (ncol(theta_eap) > 1) {
      # If multiple columns (theta + SE), take only the first column
      theta_eap <- matrix(theta_eap[, 1], ncol = 1)
    }

    # Use mirt::imputeMissing() with Theta to fill missing data
    imputed_items <- mirt::imputeMissing(rasch_model,
                                        Theta = theta_eap)

    # Verify output
    n_missing_after <- sum(is.na(imputed_items))
    pct_missing_after <- 100 * n_missing_after / (nrow(imputed_items) * ncol(imputed_items))
    message(sprintf("  Missing after: %d (%.2f%%)", n_missing_after, pct_missing_after))

    # Store in list
    imputed_data_list[[domain]] <- imputed_items

    message(sprintf("  [OK] %s: Imputation complete\n", domain))

  }, error = function(e) {
    message(sprintf("  [ERROR] Failed to impute %s: %s", domain, e$message))
    message("  Storing original data without imputation")
    imputed_data_list[[domain]] <<- item_data
  })
}

# ==============================================================================
# 3. SAVE IMPUTED DATA
# ==============================================================================
message("\n", strrep("=", 70))
message("SAVING IMPUTED DATA")
message(strrep("=", 70), "\n")

saveRDS(imputed_data_list, "scripts/hrtl/hrtl_data_imputed_allages.rds")

message("Saved: hrtl_data_imputed_allages.rds")
message(sprintf("  Domains with imputed data: %d", length(imputed_data_list)))

for (domain in names(imputed_data_list)) {
  imputed <- imputed_data_list[[domain]]
  n_missing <- sum(is.na(imputed))
  message(sprintf("    - %s: %d × %d (missing: %d)",
                  domain, nrow(imputed), ncol(imputed), n_missing))
}

message("\nPhase 2c complete - Imputed item data ready for production scoring")
