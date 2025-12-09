# Raking Utility: Iterative Proportional Fitting (IPF)
# Purpose: Reweight survey data to match population control totals (marginals)
# Method: Rake NHIS/NSCH to match ACS Nebraska demographic marginals

library(dplyr)

# ============================================================================
# Iterative Proportional Fitting (Raking)
# ============================================================================

rake_to_targets <- function(data, target_marginals, max_iterations = 100,
                            tolerance = 1e-6, weight_name = "base_weight") {

  # Accept both parameter names for backward compatibility
  target_means <- target_marginals

  cat("\n========================================\n")
  cat("Raking Survey Data to Target Marginals\n")
  cat("========================================\n\n")

  # Validate inputs
  if (!weight_name %in% names(data)) {
    stop(sprintf("Weight variable '%s' not found in data", weight_name))
  }

  missing_targets <- setdiff(names(target_means), names(data))
  if (length(missing_targets) > 0) {
    stop(sprintf("Target variables not in data: %s", paste(missing_targets, collapse = ", ")))
  }

  # Initialize raking weights
  data$raking_weight <- data[[weight_name]]
  n_vars <- length(target_means)
  n_iter <- 0
  converged <- FALSE

  cat("[1] Initialization:\n")
  cat("    Variables to rake:", n_vars, "\n")
  cat("    Target variables:", paste(names(target_means), collapse = ", "), "\n")
  cat("    Initial sample size:", nrow(data), "\n")
  cat("    Initial weighted N:", round(sum(data$raking_weight, na.rm = TRUE)), "\n\n")

  cat("[2] Target marginals:\n")
  for (var in names(target_means)) {
    cat("    ", var, ":", round(target_means[[var]], 4), "\n")
  }
  cat("\n")

  # Iterative proportional fitting
  cat("[3] Beginning IPF iterations...\n\n")

  iteration_log <- data.frame(
    iteration = integer(),
    variable = character(),
    max_diff = numeric(),
    stringsAsFactors = FALSE
  )

  for (iter in 1:max_iterations) {
    max_diff_overall <- 0

    for (var in names(target_means)) {
      target <- target_means[[var]]

      # Compute weighted mean of this variable
      current_mean <- weighted.mean(data[[var]], data$raking_weight, na.rm = TRUE)

      # Skip if current_mean is NA (no valid data for this variable)
      if (is.na(current_mean)) {
        cat("    WARNING: Variable", var, "has no valid data in iteration", iter, "\n")
        next
      }

      # Compute difference
      diff <- abs(current_mean - target)
      max_diff_overall <- max(max_diff_overall, diff)

      # Raking adjustment factor
      # If current_mean < target, need to upweight those with high values
      adjustment_factor <- target / current_mean

      # Apply adjustment to weights
      data$raking_weight <- data$raking_weight * adjustment_factor

      iteration_log <- rbind(iteration_log, data.frame(
        iteration = iter,
        variable = var,
        max_diff = diff
      ))
    }

    # Check convergence
    if (max_diff_overall < tolerance) {
      converged <- TRUE
      n_iter <- iter
      cat("    ✓ Convergence achieved at iteration", iter, "\n")
      cat("    Max marginal difference:", sprintf("%.2e", max_diff_overall), "\n\n")
      break
    }

    if (iter %% 10 == 0) {
      cat("    Iteration", iter, "- Max diff:", sprintf("%.2e", max_diff_overall), "\n")
    }

    n_iter <- iter
  }

  if (!converged) {
    cat("    ⚠ WARNING: IPF did not converge after", max_iterations, "iterations\n")
    cat("    Final max difference:", sprintf("%.2e", max_diff_overall), "\n")
    cat("    Consider increasing tolerance or max_iterations\n\n")
  }

  # Validation: check final marginals
  cat("[4] Final marginal verification:\n\n")

  final_check <- data.frame(
    Variable = names(target_means),
    Target = unlist(target_means),
    Achieved = NA_real_,
    Difference = NA_real_,
    Percent_Diff = NA_real_
  )

  for (i in seq_along(target_means)) {
    var <- names(target_means)[i]
    target <- target_means[[var]]
    achieved <- weighted.mean(data[[var]], data$raking_weight, na.rm = TRUE)
    diff <- abs(achieved - target)
    pct_diff <- (diff / target) * 100

    final_check$Achieved[i] <- achieved
    final_check$Difference[i] <- diff
    final_check$Percent_Diff[i] <- pct_diff
  }

  print(final_check)

  cat("\n[5] Raking weight diagnostics:\n")
  cat("    Min weight:", round(min(data$raking_weight), 4), "\n")
  cat("    Max weight:", round(max(data$raking_weight), 4), "\n")
  cat("    Mean weight:", round(mean(data$raking_weight), 4), "\n")
  cat("    Median weight:", round(median(data$raking_weight), 4), "\n")
  cat("    Weight ratio (max/min):", round(max(data$raking_weight) / min(data$raking_weight), 2), "\n")

  # Calculate effective sample size
  weight_sum <- sum(data$raking_weight, na.rm = TRUE)
  weight_sum_sq <- sum(data$raking_weight^2, na.rm = TRUE)
  n_eff <- weight_sum^2 / weight_sum_sq

  cat("    Weighted N:", round(weight_sum, 0), "\n")
  cat("    Effective N (Kish):", round(n_eff, 1), "\n")
  cat("    Efficiency:", round(n_eff / nrow(data) * 100, 1), "%\n\n")

  cat("========================================\n")
  cat("Raking Complete\n")
  cat("========================================\n\n")

  list(
    data = data,
    raking_weight = data$raking_weight,
    converged = converged,
    n_iterations = n_iter,
    final_marginals = final_check,
    effective_n = n_eff,
    weight_ratio = max(data$raking_weight) / min(data$raking_weight),
    iteration_log = iteration_log
  )
}

# ============================================================================
# Create Target Marginals from Population Data
# ============================================================================

create_target_marginals <- function(data, variables) {

  cat("Creating target marginals from population data...\n\n")

  targets <- list()

  for (var in variables) {
    if (!(var %in% names(data))) {
      stop(sprintf("Variable '%s' not found in data", var))
    }

    # For continuous variables: use mean
    # For binary variables: use proportion of 1s

    if (all(data[[var]] %in% c(0, 1, NA), na.rm = TRUE)) {
      # Binary variable: target is proportion of 1s
      targets[[var]] <- mean(data[[var]] == 1, na.rm = TRUE)
      cat("  ", var, "(binary):", round(targets[[var]], 4), "\n")
    } else {
      # Continuous variable: target is mean
      targets[[var]] <- mean(data[[var]], na.rm = TRUE)
      cat("  ", var, "(continuous):", round(targets[[var]], 4), "\n")
    }
  }

  cat("\n")
  targets
}
