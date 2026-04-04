################################################################################
# HRTL Item-Level Imputation: Hybrid Approach
################################################################################
# Uses AUGMENTED Motor Development model (NE25 + NSCH 2022)
# Uses NE25-only models for other 4 domains
# Applied to full NE25 dataset (all ages)
# Then filter to 3-5 years for HRTL scoring
################################################################################

library(dplyr)
library(mirt)

message("=== HRTL Item-Level Imputation (Hybrid: Augmented Motor + NE25 Other Domains) ===\n")

# Load data
message("1. Loading models and domain datasets...\n")
domain_datasets <- readRDS("scripts/temp/hrtl_domain_datasets.rds")
rasch_models <- readRDS("scripts/temp/hrtl_rasch_models.rds")
motor_rasch_augmented <- readRDS("scripts/temp/hrtl_rasch_motor_augmented.rds")

domains <- c("Early Learning Skills", "Social-Emotional Development",
             "Self-Regulation", "Motor Development", "Health")

# Store imputed datasets
hrtl_data_imputed <- list()

for (domain in domains) {
  message(sprintf("Imputing %s...", domain))

  domain_data <- domain_datasets[[domain]]$data
  domain_items <- domain_datasets[[domain]]$variables

  if (is.null(domain_data)) {
    message(sprintf("  [SKIP] Missing domain data\n"))
    next
  }

  # Extract just the item columns
  item_data <- domain_data %>%
    dplyr::select(all_of(domain_items))

  # Check missing data pattern
  n_missing <- colSums(is.na(item_data))
  n_total <- nrow(item_data)
  pct_missing <- 100 * n_missing / n_total

  message(sprintf("  Sample size: %d children (all ages)", n_total))
  message(sprintf("  Items: %d", length(domain_items)))
  message(sprintf("  Missing data before imputation:"))
  for (item in domain_items) {
    message(sprintf("    %s: %d (%.1f%%)",
                   item, n_missing[[item]], pct_missing[[item]]))
  }

  # If no missing data, skip imputation
  total_missing <- sum(n_missing)
  if (total_missing == 0) {
    message(sprintf("  [OK] No missing data - skipping imputation\n"))
    hrtl_data_imputed[[domain]] <- item_data
    next
  }

  # ===========================================================================
  # SELECT MODEL BASED ON DOMAIN
  # ===========================================================================
  if (domain == "Motor Development") {
    # Use AUGMENTED Motor Development model
    message(sprintf("  Using AUGMENTED Motor Development model (NE25 + NSCH 2022)\n"))
    rasch_fit <- motor_rasch_augmented$model
    n_ne25_in_augmented <- motor_rasch_augmented$n_ne25
  } else {
    # Use NE25-only model for other domains
    rasch_fit <- rasch_models[[domain]]
    n_ne25_in_augmented <- NULL
  }

  if (is.null(rasch_fit)) {
    message(sprintf("  [ERROR] Model not found for %s\n", domain))
    next
  }

  # ===========================================================================
  # IMPUTE USING mirt::imputeMissing()
  # ===========================================================================
  tryCatch({
    # Compute Theta (ability estimates) from the fitted model
    theta_scores <- mirt::fscores(rasch_fit, method = "EAP", full.scores = TRUE)
    if (!is.matrix(theta_scores)) {
      theta_scores <- as.matrix(theta_scores)
    }

    # imputeMissing imputes based on the fitted model and Theta
    imputed_all <- mirt::imputeMissing(rasch_fit, Theta = theta_scores, Emap = FALSE)

    # Convert to data frame if needed
    imputed_all <- as.data.frame(imputed_all)
    colnames(imputed_all) <- colnames(item_data)

    # For augmented Motor model, extract ONLY the NE25 portion (first n rows)
    if (!is.null(n_ne25_in_augmented)) {
      message(sprintf("  Extracting NE25 portion from augmented model (%d/%d rows)\n",
                     n_ne25_in_augmented, nrow(imputed_all)))
      imputed_data <- imputed_all[1:n_ne25_in_augmented, ]
    } else {
      imputed_data <- imputed_all
    }

    # Verify imputation worked
    n_missing_after <- colSums(is.na(imputed_data))
    message(sprintf("  Missing data after imputation: %d", sum(n_missing_after)))

    if (sum(n_missing_after) > 0) {
      message(sprintf("  [WARN] Still has missing values:"))
      for (item in names(n_missing_after)[n_missing_after > 0]) {
        message(sprintf("    %s: %d", item, n_missing_after[[item]]))
      }
    }

    hrtl_data_imputed[[domain]] <- as.data.frame(imputed_data)
    message(sprintf("  [OK] Imputation successful\n"))

  }, error = function(e) {
    stop(sprintf("\n[FATAL ERROR] mirt::imputeMissing() failed for %s: %s\nNo fallback - please diagnose the error.", domain, e$message))
  })
}

# Save imputed datasets
message("Saving imputed datasets...\n")
saveRDS(hrtl_data_imputed, "scripts/temp/hrtl_data_imputed_hybrid.rds")
message("[OK] Saved to scripts/temp/hrtl_data_imputed_hybrid.rds\n")

# Summary statistics
message("\n=== IMPUTATION SUMMARY (Hybrid Approach) ===\n")
for (domain in domains) {
  if (!is.null(hrtl_data_imputed[[domain]])) {
    imputed_df <- hrtl_data_imputed[[domain]]
    missing_after <- colSums(is.na(imputed_df))
    message(sprintf("%s:", domain))
    message(sprintf("  Rows: %d (all ages)", nrow(imputed_df)))
    message(sprintf("  Cols: %d items", ncol(imputed_df)))
    message(sprintf("  Missing data after imputation: %d", sum(missing_after)))
    if (sum(missing_after) > 0) {
      message(sprintf("  Items with missing: %s",
                     paste(names(missing_after)[missing_after > 0], collapse=", ")))
    }
    message()
  }
}

message("[OK] Hybrid imputation complete!")
