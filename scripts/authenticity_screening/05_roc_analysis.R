#!/usr/bin/env Rscript

#' ROC Analysis for Authenticity Screening
#'
#' Performs TWO separate ROC analyses:
#'   1. Poor fit detection (lz < 0): Random/disengaged responses
#'   2. Gaming detection (lz > 0): Suspiciously good fit
#'
#' Each ROC finds optimal threshold via Youden's J statistic
#'
#' Output: Classification metrics, thresholds, ROC curves

library(dplyr)
library(pROC)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: ROC ANALYSIS\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD DATA
# ============================================================================

cat("=== PHASE 1: LOAD DATA ===\n\n")

cat("[Step 1/2] Loading LOOCV results (authentic)...\n")
loocv_authentic <- readRDS("results/loocv_authentic_results.rds")

# Filter to converged only
loocv_authentic <- loocv_authentic %>%
  dplyr::filter(converged_main & converged_holdout)

cat(sprintf("      Authentic (LOOCV): %d participants\n", nrow(loocv_authentic)))
cat(sprintf("      Mean lz: %.4f, SD lz: %.4f\n",
            mean(loocv_authentic$lz, na.rm = TRUE),
            sd(loocv_authentic$lz, na.rm = TRUE)))

cat("\n[Step 2/2] Loading inauthentic results...\n")
inauthentic <- readRDS("results/inauthentic_logpost_results.rds")

# Filter to sufficient data (5+ items) and converged
inauthentic <- inauthentic %>%
  dplyr::filter(sufficient_data & converged)

cat(sprintf("      Inauthentic (sufficient data): %d participants\n", nrow(inauthentic)))
cat(sprintf("      Mean lz: %.4f, SD lz: %.4f\n",
            mean(inauthentic$lz, na.rm = TRUE),
            sd(inauthentic$lz, na.rm = TRUE)))

# ============================================================================
# PHASE 2: ROC ANALYSIS 1 - POOR FIT DETECTION (lz < 0)
# ============================================================================

cat("\n=== PHASE 2: ROC ANALYSIS 1 - POOR FIT DETECTION (lz < 0) ===\n\n")

cat("[Step 1/4] Preparing data for poor fit ROC...\n")

# For poor fit: we only consider participants with lz < 0
# (those with worse-than-average fit)
authentic_low <- loocv_authentic %>%
  dplyr::filter(lz < 0) %>%
  dplyr::mutate(
    label = 0,  # Authentic = negative class
    lz_abs = -lz  # Convert to positive scale (more negative = higher risk)
  )

inauthentic_low <- inauthentic %>%
  dplyr::filter(lz < 0) %>%
  dplyr::mutate(
    label = 1,  # Inauthentic = positive class
    lz_abs = -lz
  )

combined_low <- dplyr::bind_rows(authentic_low, inauthentic_low)

cat(sprintf("      Authentic with lz < 0: %d\n", nrow(authentic_low)))
cat(sprintf("      Inauthentic with lz < 0: %d\n", nrow(inauthentic_low)))
cat(sprintf("      Total for ROC 1: %d\n", nrow(combined_low)))

cat("\n[Step 2/4] Computing ROC curve for poor fit...\n")

roc_low <- pROC::roc(
  response = combined_low$label,
  predictor = combined_low$lz_abs,  # Higher lz_abs = more likely inauthentic
  levels = c(0, 1),
  direction = ">"
)

auc_low <- as.numeric(pROC::auc(roc_low))

cat(sprintf("      AUC (poor fit): %.4f\n", auc_low))

cat("\n[Step 3/4] Finding optimal threshold (Youden's J)...\n")

# Get coordinates
coords_low <- pROC::coords(roc_low, "all", ret = c("threshold", "sensitivity", "specificity"))

# Calculate Youden's J
coords_low$youden <- coords_low$sensitivity + coords_low$specificity - 1

# Find optimal threshold
optimal_idx_low <- which.max(coords_low$youden)
optimal_threshold_low_abs <- coords_low$threshold[optimal_idx_low]
optimal_sens_low <- coords_low$sensitivity[optimal_idx_low]
optimal_spec_low <- coords_low$specificity[optimal_idx_low]
optimal_youden_low <- coords_low$youden[optimal_idx_low]

# Convert back to lz scale (negative)
optimal_threshold_low_lz <- -optimal_threshold_low_abs

cat(sprintf("      Optimal threshold (lz_abs): %.4f\n", optimal_threshold_low_abs))
cat(sprintf("      Optimal threshold (lz): %.4f\n", optimal_threshold_low_lz))
cat(sprintf("      Sensitivity: %.4f\n", optimal_sens_low))
cat(sprintf("      Specificity: %.4f\n", optimal_spec_low))
cat(sprintf("      Youden's J: %.4f\n", optimal_youden_low))

cat("\n[Step 4/4] Classification rule for poor fit:\n")
cat(sprintf("      IF lz < %.4f → classify as INAUTHENTIC (poor fit)\n",
            optimal_threshold_low_lz))

# ============================================================================
# PHASE 3: ROC ANALYSIS 2 - GAMING DETECTION (lz > 0)
# ============================================================================

cat("\n=== PHASE 3: ROC ANALYSIS 2 - GAMING DETECTION (lz > 0) ===\n\n")

cat("[Step 1/4] Preparing data for gaming ROC...\n")

# For gaming: we only consider participants with lz > 0
# (those with better-than-average fit)
authentic_high <- loocv_authentic %>%
  dplyr::filter(lz > 0) %>%
  dplyr::mutate(
    label = 0,  # Authentic = negative class
    lz_abs = lz  # Already positive
  )

inauthentic_high <- inauthentic %>%
  dplyr::filter(lz > 0) %>%
  dplyr::mutate(
    label = 1,  # Inauthentic = positive class
    lz_abs = lz
  )

combined_high <- dplyr::bind_rows(authentic_high, inauthentic_high)

cat(sprintf("      Authentic with lz > 0: %d\n", nrow(authentic_high)))
cat(sprintf("      Inauthentic with lz > 0: %d\n", nrow(inauthentic_high)))
cat(sprintf("      Total for ROC 2: %d\n", nrow(combined_high)))

if (nrow(inauthentic_high) < 2) {
  cat("\n      [WARNING] Insufficient inauthentic participants with lz > 0 for ROC\n")
  cat("      Skipping gaming detection ROC analysis\n")

  roc_high <- NULL
  auc_high <- NA
  optimal_threshold_high_lz <- Inf
  optimal_sens_high <- NA
  optimal_spec_high <- NA
  optimal_youden_high <- NA

} else {

  cat("\n[Step 2/4] Computing ROC curve for gaming...\n")

  roc_high <- pROC::roc(
    response = combined_high$label,
    predictor = combined_high$lz_abs,  # Higher lz = more likely gaming
    levels = c(0, 1),
    direction = ">"
  )

  auc_high <- as.numeric(pROC::auc(roc_high))

  cat(sprintf("      AUC (gaming): %.4f\n", auc_high))

  cat("\n[Step 3/4] Finding optimal threshold (Youden's J)...\n")

  # Get coordinates
  coords_high <- pROC::coords(roc_high, "all", ret = c("threshold", "sensitivity", "specificity"))

  # Calculate Youden's J
  coords_high$youden <- coords_high$sensitivity + coords_high$specificity - 1

  # Find optimal threshold
  optimal_idx_high <- which.max(coords_high$youden)
  optimal_threshold_high_lz <- coords_high$threshold[optimal_idx_high]
  optimal_sens_high <- coords_high$sensitivity[optimal_idx_high]
  optimal_spec_high <- coords_high$specificity[optimal_idx_high]
  optimal_youden_high <- coords_high$youden[optimal_idx_high]

  cat(sprintf("      Optimal threshold (lz): %.4f\n", optimal_threshold_high_lz))
  cat(sprintf("      Sensitivity: %.4f\n", optimal_sens_high))
  cat(sprintf("      Specificity: %.4f\n", optimal_spec_high))
  cat(sprintf("      Youden's J: %.4f\n", optimal_youden_high))

  cat("\n[Step 4/4] Classification rule for gaming:\n")
  cat(sprintf("      IF lz > %.4f → classify as INAUTHENTIC (gaming)\n",
              optimal_threshold_high_lz))
}

# ============================================================================
# PHASE 4: COMBINED CLASSIFICATION
# ============================================================================

cat("\n=== PHASE 4: COMBINED CLASSIFICATION ===\n\n")

cat("[Step 1/2] Applying combined classification rule...\n")

# Classify all participants (authentic + inauthentic)
all_authentic <- loocv_authentic %>%
  dplyr::mutate(
    true_label = 0,
    predicted_poor_fit = lz < optimal_threshold_low_lz,
    predicted_gaming = lz > optimal_threshold_high_lz,
    predicted_inauthentic = predicted_poor_fit | predicted_gaming
  )

all_inauthentic <- inauthentic %>%
  dplyr::mutate(
    true_label = 1,
    predicted_poor_fit = lz < optimal_threshold_low_lz,
    predicted_gaming = lz > optimal_threshold_high_lz,
    predicted_inauthentic = predicted_poor_fit | predicted_gaming
  )

all_combined <- dplyr::bind_rows(all_authentic, all_inauthentic)

cat(sprintf("      Total participants: %d\n", nrow(all_combined)))
cat(sprintf("        Authentic: %d\n", sum(all_combined$true_label == 0)))
cat(sprintf("        Inauthentic: %d\n", sum(all_combined$true_label == 1)))

cat("\n[Step 2/2] Computing classification metrics...\n")

# Confusion matrix
tp <- sum(all_combined$true_label == 1 & all_combined$predicted_inauthentic)
fp <- sum(all_combined$true_label == 0 & all_combined$predicted_inauthentic)
tn <- sum(all_combined$true_label == 0 & !all_combined$predicted_inauthentic)
fn <- sum(all_combined$true_label == 1 & !all_combined$predicted_inauthentic)

# Metrics
sensitivity <- tp / (tp + fn)
specificity <- tn / (tn + fp)
ppv <- tp / (tp + fp)
npv <- tn / (tn + fn)
accuracy <- (tp + tn) / (tp + tn + fp + fn)

# Breakdown by detection type
tp_poor_fit <- sum(all_combined$true_label == 1 & all_combined$predicted_poor_fit)
tp_gaming <- sum(all_combined$true_label == 1 & all_combined$predicted_gaming)

cat("\n      Confusion Matrix:\n")
cat(sprintf("        True Positive (TP): %d\n", tp))
cat(sprintf("          - Poor fit: %d\n", tp_poor_fit))
cat(sprintf("          - Gaming: %d\n", tp_gaming))
cat(sprintf("        False Positive (FP): %d\n", fp))
cat(sprintf("        True Negative (TN): %d\n", tn))
cat(sprintf("        False Negative (FN): %d\n", fn))

cat("\n      Classification Metrics:\n")
cat(sprintf("        Sensitivity (TPR): %.4f (%.1f%%)\n", sensitivity, 100 * sensitivity))
cat(sprintf("        Specificity (TNR): %.4f (%.1f%%)\n", specificity, 100 * specificity))
cat(sprintf("        PPV (Precision): %.4f (%.1f%%)\n", ppv, 100 * ppv))
cat(sprintf("        NPV: %.4f (%.1f%%)\n", npv, 100 * npv))
cat(sprintf("        Accuracy: %.4f (%.1f%%)\n", accuracy, 100 * accuracy))

# ============================================================================
# PHASE 5: SAVE RESULTS
# ============================================================================

cat("\n=== PHASE 5: SAVE RESULTS ===\n\n")

cat("[Step 1/1] Saving ROC results and classification metrics...\n")

# Save ROC results
roc_results <- list(
  # ROC 1: Poor fit
  roc_low = roc_low,
  auc_low = auc_low,
  threshold_low_lz = optimal_threshold_low_lz,
  sensitivity_low = optimal_sens_low,
  specificity_low = optimal_spec_low,
  youden_low = optimal_youden_low,

  # ROC 2: Gaming
  roc_high = roc_high,
  auc_high = auc_high,
  threshold_high_lz = optimal_threshold_high_lz,
  sensitivity_high = optimal_sens_high,
  specificity_high = optimal_spec_high,
  youden_high = optimal_youden_high,

  # Combined classification
  confusion_matrix = list(
    tp = tp,
    fp = fp,
    tn = tn,
    fn = fn,
    tp_poor_fit = tp_poor_fit,
    tp_gaming = tp_gaming
  ),

  metrics = list(
    sensitivity = sensitivity,
    specificity = specificity,
    ppv = ppv,
    npv = npv,
    accuracy = accuracy
  )
)

saveRDS(roc_results, "results/roc_analysis_results.rds")
cat("      Saved: results/roc_analysis_results.rds\n")

# Save classified data
saveRDS(all_combined, "results/classified_participants.rds")
cat("      Saved: results/classified_participants.rds\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  ROC ANALYSIS COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("ROC 1 - Poor Fit Detection (lz < 0):\n")
cat(sprintf("  AUC: %.4f\n", auc_low))
cat(sprintf("  Optimal threshold: lz < %.4f\n", optimal_threshold_low_lz))
cat(sprintf("  Sensitivity: %.4f, Specificity: %.4f\n", optimal_sens_low, optimal_spec_low))
cat("\n")

if (!is.null(roc_high)) {
  cat("ROC 2 - Gaming Detection (lz > 0):\n")
  cat(sprintf("  AUC: %.4f\n", auc_high))
  cat(sprintf("  Optimal threshold: lz > %.4f\n", optimal_threshold_high_lz))
  cat(sprintf("  Sensitivity: %.4f, Specificity: %.4f\n", optimal_sens_high, optimal_spec_high))
  cat("\n")
} else {
  cat("ROC 2 - Gaming Detection: Skipped (insufficient data)\n\n")
}

cat("Combined Classification Rule:\n")
cat(sprintf("  IF lz < %.4f OR lz > %.4f → INAUTHENTIC\n",
            optimal_threshold_low_lz, optimal_threshold_high_lz))
cat("\n")

cat("Overall Performance:\n")
cat(sprintf("  Sensitivity: %.1f%% (%d/%d inauthentic detected)\n",
            100 * sensitivity, tp, tp + fn))
cat(sprintf("  Specificity: %.1f%% (%d/%d authentic correctly classified)\n",
            100 * specificity, tn, tn + fp))
cat(sprintf("  Accuracy: %.1f%%\n", 100 * accuracy))
cat("\n")

cat("Detection Breakdown:\n")
cat(sprintf("  Poor fit detections: %d\n", tp_poor_fit))
cat(sprintf("  Gaming detections: %d\n", tp_gaming))
cat("\n")

cat("Next Steps:\n")
cat("  1. Create diagnostic plots (Task 9)\n")
cat("  2. Document results with markdown summary (Task 10)\n")
cat("\n")

cat("[OK] ROC analysis complete!\n")
cat("\n")
