# Pooling utilities for multiple imputation (Rubin's Rules)
# Helper functions for criterion validity report

#' Pool Multiple Imputation Results Using Rubin's Rules
#'
#' Applies Rubin's (1987) combining rules to pool estimates across M imputations
#'
#' @param model_list List of M fitted models (one per imputation)
#' @return List with pooled coefficients, variance components, and diagnostics
#'
#' @details
#' Implements Rubin's combining rules:
#' - Pooled estimate: Q_bar = mean(Q_m)
#' - Within-imputation variance: U_bar = mean(U_m)
#' - Between-imputation variance: B = var(Q_m)
#' - Total variance: T = U_bar + (1 + 1/M) * B
#' - Relative increase in variance: r = [(1 + 1/M) * B] / U_bar
#' - Fraction of missing information: lambda = (r + 2/(df+3)) / (1+r)
#'
#' @references Rubin, D. B. (1987). Multiple Imputation for Nonresponse in Surveys.
#'
#' @export
pool_mi_results <- function(model_list) {
  # Use mitools::MIcombine for standard pooling
  pooled <- mitools::MIcombine(model_list)

  # Extract key components
  M <- length(model_list)

  # Get coefficients from each imputation
  coefs_mat <- sapply(model_list, function(m) coef(m))

  # Ensure coefs_mat is a matrix (handle single predictor case)
  if (!is.matrix(coefs_mat)) {
    coefs_mat <- matrix(coefs_mat, nrow = 1)
    rownames(coefs_mat) <- names(coef(model_list[[1]]))
  }

  # Get variance-covariance matrices from each imputation
  vcov_list <- lapply(model_list, vcov)

  # Pooled coefficients (Q_bar)
  coef_pooled <- apply(coefs_mat, 1, mean)

  # Within-imputation variance (U_bar)
  # Average of variance-covariance matrices
  U_bar <- Reduce("+", vcov_list) / M

  # Between-imputation variance (B)
  # Variance of point estimates across imputations
  B <- apply(coefs_mat, 1, var)

  # Total variance (T)
  # Diagonal elements: U_bar + (1 + 1/M) * B
  T_diag <- diag(U_bar) + (1 + 1/M) * B

  # Relative increase in variance due to nonresponse (r)
  r <- ((1 + 1/M) * B) / diag(U_bar)

  # Degrees of freedom (for small M, use Barnard-Rubin adjustment)
  # Simplified version: use infinity for large samples
  df_complete <- Inf  # Complete-data degrees of freedom (use Inf for large N)
  df_observed <- (M - 1) * (1 + 1/r)^2

  # Fraction of missing information (lambda)
  # Adjusted formula from Rubin (1987)
  lambda <- (r + 2/(df_observed + 3)) / (1 + r)

  # Calculate t-statistics and p-values
  se_vec <- sqrt(T_diag)
  t_stat <- coef_pooled / se_vec
  p_values <- 2 * pt(abs(t_stat), df = df_observed, lower.tail = FALSE)

  # Create result object
  result <- list(
    coefficients = coef_pooled,
    vcov = vcov(pooled),
    se = se_vec,
    t_stat = t_stat,
    p_values = p_values,
    df = df_observed,
    diagnostics = list(
      M = M,
      between_var = B,
      within_var = diag(U_bar),
      total_var = T_diag,
      relative_increase = r,
      frac_missing_info = lambda,
      df_observed = df_observed
    ),
    mitools_obj = pooled  # Keep original mitools object for compatibility
  )

  return(result)
}


#' Extract MI Diagnostics from Pooled Results
#'
#' Extract key multiple imputation quality metrics from pooled results
#'
#' @param pooled_result Output from pool_mi_results()
#' @return data.frame with MI diagnostics per coefficient
#'
#' @export
extract_mi_diagnostics <- function(pooled_result) {
  diag <- pooled_result$diagnostics

  # Create diagnostic table
  diag_df <- data.frame(
    Parameter = names(pooled_result$coefficients),
    M = diag$M,
    Between_Var = diag$between_var,
    Within_Var = diag$within_var,
    Total_Var = diag$total_var,
    Rel_Increase = diag$relative_increase,
    Frac_Missing_Info = diag$frac_missing_info,
    DF_Observed = diag$df_observed,
    stringsAsFactors = FALSE
  )

  return(diag_df)
}


#' Format MI Diagnostics Table for Reporting
#'
#' Create formatted table of MI quality metrics suitable for appendix
#'
#' @param pooled_result Output from pool_mi_results()
#' @param digits Number of decimal places. Default: 3
#' @return data.frame formatted for knitr::kable()
#'
#' @export
format_mi_diagnostics_table <- function(pooled_result, digits = 3) {
  diag_df <- extract_mi_diagnostics(pooled_result)

  # Round numeric columns
  diag_df$Rel_Increase <- round(diag_df$Rel_Increase, digits)
  diag_df$Frac_Missing_Info <- round(diag_df$Frac_Missing_Info, digits)

  # Keep only key columns for reporting
  report_df <- diag_df[, c("Parameter", "Rel_Increase", "Frac_Missing_Info")]
  colnames(report_df) <- c("Parameter", "r (Relative Increase)", "lambda (Frac. Missing Info)")

  return(report_df)
}


#' Check MI Quality Metrics
#'
#' Validate MI quality: lambda < 0.3 and r < 0.5 are considered good
#'
#' @param pooled_result Output from pool_mi_results()
#' @param lambda_threshold Threshold for fraction of missing information. Default: 0.3
#' @param r_threshold Threshold for relative variance increase. Default: 0.5
#' @return List with pass/fail status and flagged parameters
#'
#' @export
check_mi_quality <- function(pooled_result, lambda_threshold = 0.3, r_threshold = 0.5) {
  diag <- pooled_result$diagnostics

  # Identify problematic parameters
  lambda_flags <- diag$frac_missing_info > lambda_threshold
  r_flags <- diag$relative_increase > r_threshold

  # Get parameter names
  param_names <- names(pooled_result$coefficients)

  # Create result
  result <- list(
    all_pass = !any(lambda_flags | r_flags),
    lambda_pass = !any(lambda_flags),
    r_pass = !any(r_flags),
    flagged_params = list(
      high_lambda = param_names[lambda_flags],
      high_r = param_names[r_flags]
    ),
    thresholds = list(
      lambda = lambda_threshold,
      r = r_threshold
    ),
    diagnostics_summary = data.frame(
      Parameter = param_names,
      Lambda = round(diag$frac_missing_info, 3),
      R = round(diag$relative_increase, 3),
      Lambda_Flag = lambda_flags,
      R_Flag = r_flags,
      stringsAsFactors = FALSE
    )
  )

  return(result)
}


#' Print MI Quality Check Results
#'
#' @param quality_check Output from check_mi_quality()
#' @export
print_mi_quality <- function(quality_check) {
  cat("=== Multiple Imputation Quality Check ===\n\n")
  cat(sprintf("Thresholds: lambda < %.2f, r < %.2f\n\n",
              quality_check$thresholds$lambda,
              quality_check$thresholds$r))

  if (quality_check$all_pass) {
    cat("[OK] All parameters pass quality thresholds\n")
  } else {
    cat("[WARN] Some parameters exceed quality thresholds:\n\n")

    if (!quality_check$lambda_pass) {
      cat("  High fraction of missing information (lambda):\n")
      for (p in quality_check$flagged_params$high_lambda) {
        lambda_val <- quality_check$diagnostics_summary$Lambda[
          quality_check$diagnostics_summary$Parameter == p
        ]
        cat(sprintf("    - %s: %.3f\n", p, lambda_val))
      }
      cat("\n")
    }

    if (!quality_check$r_pass) {
      cat("  High relative variance increase (r):\n")
      for (p in quality_check$flagged_params$high_r) {
        r_val <- quality_check$diagnostics_summary$R[
          quality_check$diagnostics_summary$Parameter == p
        ]
        cat(sprintf("    - %s: %.3f\n", p, r_val))
      }
    }
  }

  cat("\n")
  invisible(quality_check)
}
