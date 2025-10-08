# Phase 3, Task 3.1a: Create Shared NHIS Bootstrap Design
# Generate ONE bootstrap design for NHIS PHQ-2 estimand
# This design will be used by 13_estimate_phq2.R

library(survey)
library(svrep)
library(dplyr)

cat("\n========================================\n")
cat("Create Shared NHIS Bootstrap Design\n")
cat("========================================\n\n")

# Load bootstrap configuration from centralized config
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot

cat("[CONFIG] Bootstrap replicates:", n_boot, "\n")
cat("         Mode:", get_bootstrap_mode(), "\n\n")

# 1. Load PHQ-2 data (complete cases only)
cat("[1] Loading PHQ-2 scored data...\n")

phq_data <- readRDS("data/raking/ne25/nhis_phq2_scored.rds")

cat("    Sample size:", nrow(phq_data), "parent-child pairs\n")
cat("    Years:", paste(sort(unique(phq_data$YEAR)), collapse = ", "), "\n")
cat("    Number of PSUs:", length(unique(phq_data$PSU_child)), "\n")
cat("    Number of strata:", length(unique(phq_data$STRATA_child)), "\n\n")

# 2. Create base survey design
cat("[2] Creating base NHIS survey design...\n")

nhis_design <- survey::svydesign(
  ids = ~PSU_child,
  strata = ~STRATA_child,
  weights = ~SAMPWEIGHT_parent,
  data = phq_data,
  nest = TRUE
)

cat("    Survey design created\n")
cat("    Design type: Stratified cluster sample\n")
cat("    Clustering variable: PSU_child\n")
cat("    Strata variable: STRATA_child\n")
cat("    Weight variable: SAMPWEIGHT_parent\n\n")

# 3. Generate bootstrap replicate weights
cat("[3] Generating bootstrap replicate weights...\n")
cat("    Method: Rao-Wu-Yue-Beaumont\n")
cat("    Number of replicates:", n_boot, "\n\n")

# Create bootstrap design with replicate weights
boot_design <- svrep::as_bootstrap_design(
  design = nhis_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = n_boot
)

cat("    Bootstrap design created successfully\n")
cat("    Replicate weights matrix:", nrow(boot_design$repweights), "observations x",
    ncol(boot_design$repweights), "replicates\n\n")

# 4. Verify bootstrap design structure
cat("[4] Verifying bootstrap design structure...\n")

# Check that repweights matrix exists and has correct dimensions
if (!is.null(boot_design$repweights)) {
  cat("    [OK] Replicate weights matrix exists\n")

  if (ncol(boot_design$repweights) == n_boot) {
    cat("    [OK] Correct number of replicates (", n_boot, ")\n", sep = "")
  } else {
    stop("ERROR: Expected ", n_boot, " replicates, got ", ncol(boot_design$repweights))
  }

  if (nrow(boot_design$repweights) == nrow(phq_data)) {
    cat("    [OK] Replicate weights match sample size (", nrow(phq_data), " rows)\n", sep = "")
  } else {
    stop("ERROR: Replicate weights have ", nrow(boot_design$repweights),
         " rows, expected ", nrow(phq_data))
  }
} else {
  stop("ERROR: Replicate weights matrix not found in bootstrap design")
}

# Check for missing values
n_missing <- sum(is.na(boot_design$repweights))
if (n_missing == 0) {
  cat("    [OK] No missing values in replicate weights\n")
} else {
  cat("    [WARN] Found", n_missing, "missing values in replicate weights\n")
}

cat("\n")

# 5. Summary statistics
cat("[5] Bootstrap design summary statistics...\n")

cat("    Original weights (SAMPWEIGHT_parent):\n")
cat("      Min:", min(phq_data$SAMPWEIGHT_parent), "\n")
cat("      Max:", max(phq_data$SAMPWEIGHT_parent), "\n")
cat("      Mean:", round(mean(phq_data$SAMPWEIGHT_parent), 0), "\n\n")

cat("    Replicate weight 1 (example):\n")
cat("      Min:", round(min(boot_design$repweights[, 1]), 2), "\n")
cat("      Max:", round(max(boot_design$repweights[, 1]), 2), "\n")
cat("      Mean:", round(mean(boot_design$repweights[, 1]), 2), "\n\n")

# 6. Save bootstrap design
cat("[6] Saving NHIS bootstrap design...\n")

saveRDS(boot_design, "data/raking/ne25/nhis_bootstrap_design.rds")

# Get file size
file_info <- file.info("data/raking/ne25/nhis_bootstrap_design.rds")
file_size_mb <- round(file_info$size / 1024^2, 2)

cat("    Saved to: data/raking/ne25/nhis_bootstrap_design.rds\n")
cat("    File size:", file_size_mb, "MB\n")
cat("    Dimensions:", nrow(boot_design$repweights), "observations x",
    ncol(boot_design$repweights), "replicates\n\n")

cat("========================================\n")
cat("NHIS Bootstrap Design Creation Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Sample size:", nrow(phq_data), "parent-child pairs\n")
cat("  - Bootstrap method: Rao-Wu-Yue-Beaumont\n")
cat("  - Number of replicates:", n_boot, "\n")
cat("  - File size:", file_size_mb, "MB\n")
cat("  - Shared design ready for use in 13_estimate_phq2.R\n\n")

if (n_boot < 100) {
  cat("NOTE: Running in TEST MODE with", n_boot, "replicates\n")
  cat("      For production, change n_boot to 4096 and re-run\n\n")
}

# Return design for inspection
boot_design
