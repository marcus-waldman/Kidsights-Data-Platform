# Phase 2, Task 2.1a: Create Shared ACS Bootstrap Design
# Purpose: Generate ONE set of bootstrap replicate weights for all ACS estimands
# This ensures all 25 ACS estimands share the same sampling uncertainty structure

library(survey)
library(svrep)

cat("\n========================================\n")
cat("Task 2.1a: Create Shared ACS Bootstrap Design\n")
cat("========================================\n\n")

# Bootstrap configuration
# Check if n_boot is passed from parent script, otherwise use default
if (!exists("n_boot")) {
  n_boot <- 96  # Default for standalone execution
  cat("[INFO] Using default n_boot = 96 (set via run_bootstrap_pipeline.R for production)\n\n")
}

cat("Bootstrap configuration:\n")
cat("  Method: Rao-Wu-Yue-Beaumont\n")
cat("  Replicates:", n_boot, "\n")

if (n_boot < 100) {
  cat("  [WARNING] Using test mode with", n_boot, "replicates\n")
  cat("           Change n_boot to 4096 for production run\n\n")
} else {
  cat("  [PRODUCTION MODE] Using", n_boot, "replicates\n\n")
}

# 1. Load base ACS survey design
cat("[1] Loading base ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

cat("    Survey design loaded:\n")
cat("      Observations:", nrow(acs_design$variables), "\n")
cat("      Clusters:", length(unique(acs_design$cluster[[1]])), "\n")
cat("      Strata:", length(unique(acs_design$strata[[1]])), "\n\n")

# 2. Create bootstrap design with replicate weights
cat("[2] Generating bootstrap replicate weights...\n")
cat("    This creates ONE set of replicate weights for ALL estimands\n")
cat("    Method: Rao-Wu-Yue-Beaumont bootstrap\n")
cat("    Replicates:", n_boot, "\n\n")

# Generate bootstrap design
boot_design <- svrep::as_bootstrap_design(
  design = acs_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = n_boot
)

cat("    Bootstrap design created successfully\n\n")

# 3. Verify bootstrap design structure
cat("[3] Verifying bootstrap design structure...\n")

# Check replicate weights matrix
if ("repweights" %in% names(boot_design)) {
  rep_dims <- dim(boot_design$repweights)
  cat("    Replicate weights matrix: ", rep_dims[1], " observations × ",
      rep_dims[2], " replicates\n", sep = "")

  if (rep_dims[2] == n_boot) {
    cat("    [OK] Correct number of replicates\n")
  } else {
    cat("    [ERROR] Expected", n_boot, "replicates, got", rep_dims[2], "\n")
  }

  # Check for any missing weights
  n_missing <- sum(is.na(boot_design$repweights))
  if (n_missing == 0) {
    cat("    [OK] No missing replicate weights\n")
  } else {
    cat("    [WARN]", n_missing, "missing replicate weights\n")
  }

} else {
  cat("    [ERROR] Replicate weights not found in bootstrap design\n")
}

cat("\n")

# 4. Summary statistics
cat("[4] Bootstrap replicate weight summary...\n")

# Get some summary statistics
rep_means <- colMeans(boot_design$repweights)
rep_sds <- apply(boot_design$repweights, 2, sd)

cat("    Replicate weight means (first 4):\n")
for (i in 1:min(4, n_boot)) {
  cat("      Replicate", i, ":", round(rep_means[i], 2), "\n")
}

cat("\n    Replicate weight std devs (first 4):\n")
for (i in 1:min(4, n_boot)) {
  cat("      Replicate", i, ":", round(rep_sds[i], 2), "\n")
}

cat("\n")

# 5. Save bootstrap design
cat("[5] Saving shared bootstrap design...\n")

saveRDS(boot_design, "data/raking/ne25/acs_bootstrap_design.rds")

cat("    Saved to: data/raking/ne25/acs_bootstrap_design.rds\n")
cat("    File size:", round(file.size("data/raking/ne25/acs_bootstrap_design.rds") / 1024 / 1024, 2), "MB\n\n")

# 6. Important notes
cat("[6] Implementation notes:\n")
cat("    - This bootstrap design will be loaded by ALL ACS estimation scripts (02-07)\n")
cat("    - All 25 ACS estimands will share these SAME replicate weights\n")
cat("    - This ensures correct propagation of sampling uncertainty\n")
cat("    - Enables computation of bootstrap covariances between estimands\n\n")

cat("========================================\n")
cat("Task 2.1a Complete\n")
cat("========================================\n\n")

cat("Next steps:\n")
cat("  1. Update bootstrap_helpers.R to accept boot_design parameter\n")
cat("  2. Update scripts 02-07 to load and use this shared bootstrap design\n")
cat("  3. Re-run all estimation scripts to generate corrected bootstrap estimates\n\n")
