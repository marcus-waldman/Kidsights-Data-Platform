################################################################################
# HRTL Item-Level Imputation Using mirt::imputeMissing() - All Ages
################################################################################
# Imputes missing HRTL item responses using mirt::imputeMissing()
# Applied to the FULL dataset (all ages, meets_inclusion=TRUE)
# Then subset to 3-5 years for HRTL scoring
################################################################################

library(dplyr)
library(mirt)

message("=== HRTL Item-Level Imputation (mirt::imputeMissing, All Ages) ===\n")

# Load data
domain_datasets <- readRDS("scripts/temp/hrtl_domain_datasets.rds")
rasch_models <- readRDS("scripts/temp/hrtl_rasch_models.rds")

domains <- c("Early Learning Skills", "Social-Emotional Development",
             "Self-Regulation", "Motor Development", "Health")

# Store imputed datasets
hrtl_data_imputed_allages <- list()

for (domain in domains) {
  message(sprintf("Imputing %s (mirt::imputeMissing)...", domain))

  domain_data <- domain_datasets[[domain]]$data
  domain_items <- domain_datasets[[domain]]$variables
  rasch_fit <- rasch_models[[domain]]

  if (is.null(domain_data) || is.null(rasch_fit)) {
    message(sprintf("  [SKIP] Missing model or data\n"))
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
    hrtl_data_imputed_allages[[domain]] <- item_data
    next
  }

  # Use mirt::imputeMissing() with the fitted Rasch model
  message(sprintf("  Running mirt::imputeMissing() (using fitted model)...\n"))

  tryCatch({
    # Compute Theta (ability estimates) from the fitted model
    theta_scores <- mirt::fscores(rasch_fit, method = "EAP", full.scores = TRUE)
    if (!is.matrix(theta_scores)) {
      theta_scores <- as.matrix(theta_scores)
    }

    # imputeMissing imputes based on the fitted model and Theta
    imputed_data <- mirt::imputeMissing(rasch_fit, Theta = theta_scores, Emap = FALSE)

    # Convert to data frame if needed
    imputed_data <- as.data.frame(imputed_data)
    colnames(imputed_data) <- colnames(item_data)

    # Verify imputation worked
    n_missing_after <- colSums(is.na(imputed_data))
    message(sprintf("  Missing data after imputation: %d", sum(n_missing_after)))

    if (sum(n_missing_after) > 0) {
      message(sprintf("  [WARN] Still has missing values:"))
      for (item in names(n_missing_after)[n_missing_after > 0]) {
        message(sprintf("    %s: %d", item, n_missing_after[[item]]))
      }
    }

    hrtl_data_imputed_allages[[domain]] <- as.data.frame(imputed_data)
    message(sprintf("  [OK] Imputation successful\n"))

  }, error = function(e) {
    stop(sprintf("\n[FATAL ERROR] mirt::imputeMissing() failed for %s: %s\nNo fallback - please diagnose the error.", domain, e$message))
  })
}

# Save imputed datasets (all ages)
message("Saving imputed datasets (all ages)...")
saveRDS(hrtl_data_imputed_allages, "scripts/temp/hrtl_data_imputed_allages.rds")
message("[OK] Saved to scripts/temp/hrtl_data_imputed_allages.rds\n")

# Summary statistics
message("\n=== IMPUTATION SUMMARY (All Ages) ===\n")
for (domain in domains) {
  if (!is.null(hrtl_data_imputed_allages[[domain]])) {
    imputed_df <- hrtl_data_imputed_allages[[domain]]
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

message("[OK] All-ages imputation complete!")
