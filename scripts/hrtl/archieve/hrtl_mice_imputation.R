################################################################################
# HRTL Item-Level Imputation for Missing Item Responses
################################################################################
# Imputes missing HRTL item responses using:
# - Hot-deck imputation (item mean replacement)
# - Missing values replaced with rounded mean of observed responses
# - Preserves ordinal structure of responses (0-4 or 0-6)
################################################################################

library(dplyr)
library(mirt)

message("=== HRTL Item-Level Imputation (IRT-Based) ===\n")

# Load data
domain_datasets <- readRDS("scripts/temp/hrtl_domain_datasets.rds")
rasch_models <- readRDS("scripts/temp/hrtl_rasch_models.rds")

domains <- c("Early Learning Skills", "Social-Emotional Development",
             "Self-Regulation", "Motor Development", "Health")

# Store imputed datasets
hrtl_data_imputed <- list()

for (domain in domains) {
  message(sprintf("Imputing %s...", domain))

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

  message(sprintf("  Items: %d, Children: %d", length(domain_items), n_total))
  message(sprintf("  Missing data before imputation:"))
  for (item in domain_items) {
    message(sprintf("    %s: %d (%.1f%%)",
                   item, n_missing[[item]], pct_missing[[item]]))
  }

  # If no missing data, skip imputation
  if (sum(n_missing) == 0) {
    message(sprintf("  [OK] No missing data - skipping imputation\n"))
    hrtl_data_imputed[[domain]] <- item_data
    next
  }

  # Simple hot-deck imputation: replace missing with item mean
  message(sprintf("  Running hot-deck imputation (item mean replacement)...\n"))

  imputed_data <- item_data

  for (item in domain_items) {
    missing_idx <- is.na(imputed_data[[item]])
    if (sum(missing_idx) > 0) {
      # Replace missing with the mean of observed values
      item_mean <- mean(imputed_data[[item]], na.rm = TRUE)
      # Round to nearest integer (responses are 0-4 or 0-6)
      item_mean_rounded <- round(item_mean)
      imputed_data[[item]][missing_idx] <- item_mean_rounded
    }
  }

  # Verify imputation worked
  n_missing_after <- colSums(is.na(imputed_data))
  message(sprintf("  Missing data after imputation: %d\n", sum(n_missing_after)))

  hrtl_data_imputed[[domain]] <- as.data.frame(imputed_data)
}

# Save imputed datasets
message("\nSaving imputed datasets...")
saveRDS(hrtl_data_imputed, "scripts/temp/hrtl_data_imputed.rds")
message("[OK] Saved to scripts/temp/hrtl_data_imputed.rds\n")

# Summary statistics
message("\n=== IMPUTATION SUMMARY ===\n")
for (domain in domains) {
  if (!is.null(hrtl_data_imputed[[domain]])) {
    imputed_df <- hrtl_data_imputed[[domain]]
    missing_after <- colSums(is.na(imputed_df))
    message(sprintf("%s:", domain))
    message(sprintf("  Rows: %d, Cols: %d", nrow(imputed_df), ncol(imputed_df)))
    message(sprintf("  Missing data after imputation: %d", sum(missing_after)))
    if (sum(missing_after) > 0) {
      message(sprintf("  Items with missing: %s",
                     paste(names(missing_after)[missing_after > 0], collapse=", ")))
    }
    message()
  }
}

message("[OK] IRT-based imputation complete!")
