# Validation Utilities: Covariance Matrix Validation
# Purpose: Validate that weighted covariance matrices are mathematically valid
# These functions check positive definiteness, correlation bounds, sample size, etc.

library(dplyr)

# ============================================================================
# Covariance Matrix Validation
# ============================================================================

validate_covariance_matrix <- function(moments, source_name = "Unknown") {
  cat("\n========================================\n")
  cat("Covariance Matrix Validation:", source_name, "\n")
  cat("========================================\n\n")

  issues <- list()

  # 1. Check positive definiteness (all eigenvalues > 0)
  cat("[1] Positive definiteness check:\n")

  eig <- eigen(moments$Sigma, symmetric = TRUE, only.values = TRUE)
  eigenvalues <- eig$values
  min_eigenvalue <- min(eigenvalues)
  max_eigenvalue <- max(eigenvalues)
  condition_number <- max_eigenvalue / min_eigenvalue

  cat("    Min eigenvalue:", sprintf("%.6e", min_eigenvalue), "\n")
  cat("    Max eigenvalue:", sprintf("%.6e", max_eigenvalue), "\n")
  cat("    Condition number:", sprintf("%.2f", condition_number), "\n")

  if (min_eigenvalue <= 0) {
    issues$not_pos_def <- sprintf("Covariance matrix not positive definite (min eigenvalue: %.6e)", min_eigenvalue)
    cat("    ✗ ERROR: Matrix is NOT positive definite\n")
  } else if (min_eigenvalue < 1e-10) {
    issues$near_singular <- sprintf("Covariance matrix near-singular (min eigenvalue: %.6e)", min_eigenvalue)
    cat("    ✗ WARNING: Matrix is near-singular (very small eigenvalue)\n")
  } else {
    cat("    ✓ Matrix is positive definite\n")
  }

  # 2. Check correlation matrix diagonal == 1.0
  cat("\n[2] Correlation matrix diagonal check:\n")

  if (!is.null(moments$correlation)) {
    diag_corr <- diag(moments$correlation)
    diag_errors <- abs(diag_corr - 1.0)
    max_diag_error <- max(diag_errors, na.rm = TRUE)

    cat("    Max diagonal deviation from 1.0:", sprintf("%.2e", max_diag_error), "\n")

    if (max(diag_errors, na.rm = TRUE) > 1e-10) {
      issues$corr_diag <- "Correlation matrix diagonal != 1.0"
      cat("    ✗ ERROR: Diagonal elements not equal to 1.0\n")
    } else {
      cat("    ✓ All diagonal elements = 1.0\n")
    }
  }

  # 3. Check for perfect collinearity (|correlation| >= 0.99)
  cat("\n[3] Collinearity check:\n")

  if (!is.null(moments$correlation)) {
    corr_upper <- moments$correlation[upper.tri(moments$correlation)]
    max_corr <- max(abs(corr_upper), na.rm = TRUE)
    min_corr <- min(abs(corr_upper), na.rm = TRUE)

    cat("    Min |correlation|:", round(min_corr, 4), "\n")
    cat("    Max |correlation|:", round(max_corr, 4), "\n")

    if (max_corr >= 0.99) {
      issues$high_corr <- sprintf("Near-perfect collinearity detected (max |corr|: %.4f)", max_corr)
      cat("    ✗ WARNING: Near-perfect collinearity (|r| >= 0.99)\n")
    } else if (max_corr >= 0.95) {
      cat("    ! Note: Some high correlations (0.95-0.99), but acceptable\n")
    } else {
      cat("    ✓ No perfect collinearity (max |r| < 0.99)\n")
    }
  }

  # 4. Check for sensible variance estimates
  cat("\n[4] Variance estimates:\n")

  if (!is.null(moments$Sigma)) {
    variances <- diag(moments$Sigma)

    var_df <- data.frame(
      Variable = names(variances),
      Variance = round(variances, 4),
      SD = round(sqrt(variances), 3)
    )

    print(var_df)

    # Flag if any variance is suspiciously small (<1e-6) or large (>100)
    if (any(variances < 1e-6, na.rm = TRUE)) {
      issues$tiny_var <- sprintf("Suspiciously small variance detected (min: %.2e)", min(variances, na.rm = TRUE))
      cat("    ✗ WARNING: Very small variance detected\n")
    }

    if (any(variances > 100, na.rm = TRUE)) {
      issues$large_var <- sprintf("Suspiciously large variance detected (max: %.2f)", max(variances, na.rm = TRUE))
      cat("    ✗ WARNING: Very large variance detected\n")
    }

    if (!("tiny_var" %in% names(issues)) && !("large_var" %in% names(issues))) {
      cat("    ✓ All variances in sensible range\n")
    }
  }

  # 5. Check effective sample size and efficiency
  cat("\n[5] Sample size diagnostics:\n")

  cat("    Raw N:", moments$n, "\n")
  cat("    Effective N:", round(moments$n_eff, 1), "\n")
  cat("    Efficiency:", round(moments$n_eff / moments$n * 100, 1), "%\n")

  if (moments$n_eff < 100) {
    issues$low_n_eff <- sprintf("Low effective sample size (n_eff = %.1f)", moments$n_eff)
    cat("    ✗ WARNING: Effective N < 100 (small sample)\n")
  }

  if (moments$n_eff / moments$n < 0.10) {
    issues$very_low_efficiency <- sprintf("Very low efficiency (%.1f%%)", moments$n_eff / moments$n * 100)
    cat("    ✗ WARNING: Very low efficiency (< 10%)\n")
  } else if (moments$n_eff / moments$n < 0.50) {
    cat("    ! Note: Moderate efficiency (10-50%); may reflect weighting adjustment\n")
  } else {
    cat("    ✓ Good efficiency (≥ 50%)\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All covariance matrix checks PASSED\n\n")
  } else {
    cat("✗ WARNING: Covariance matrix validation issues detected:\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    issues = issues,
    eigenvalues = eigenvalues,
    condition_number = condition_number
  )
}
