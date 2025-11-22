# Gauss-Hermite Quadrature Utilities for Authenticity Screening CV
#
# Provides functions for:
#   - Generating GH nodes and weights for N(0,1) integration
#   - Preparing data for CV Stan model
#   - Creating stratified folds

#' Generate Gauss-Hermite Nodes and Weights for N(0,1)
#'
#' Computes nodes and weights for numerical integration over N(0,1) using
#' Gauss-Hermite quadrature. The standard GH quadrature integrates with respect
#' to exp(-x^2), so we need to transform for N(0,1) = (1/sqrt(2π)) exp(-x^2/2).
#'
#' @param n_nodes Number of quadrature points (default: 21, recommended 15-25)
#' @return List with:
#'   - nodes: Vector of length n_nodes, quadrature nodes
#'   - weights: Vector of length n_nodes, quadrature weights (sum to sqrt(pi))
#'
#' @details
#' For integrating f(x) with respect to N(0,1):
#'   ∫ f(x) × φ(x) dx ≈ Σ w_k × f(x_k)
#' where φ(x) is standard normal PDF.
#'
#' The transformation from standard GH (for exp(-x^2)) to N(0,1) is:
#'   x_transformed = sqrt(2) × x_standard
#'   w_transformed = w_standard / sqrt(pi)
#'
#' @examples
#' gh <- get_gh_nodes_weights(21)
#' # Verify: integral of φ(x) should be 1
#' sum(gh$weights * dnorm(gh$nodes))  # Should be ≈ 1.0
get_gh_nodes_weights <- function(n_nodes = 21) {

  if (!requireNamespace("fastGHQuad", quietly = TRUE)) {
    stop("Package 'fastGHQuad' required. Install with: install.packages('fastGHQuad')")
  }

  # Get standard GH nodes/weights (for exp(-x^2))
  gh_standard <- fastGHQuad::gaussHermiteData(n_nodes)

  # Transform to N(0,1)
  # Standard GH: ∫ f(x) exp(-x^2) dx ≈ Σ w_k f(x_k)
  # N(0,1): ∫ f(x) (1/sqrt(2π)) exp(-x^2/2) dx
  # Transformation: x_new = sqrt(2) × x_old, w_new = w_old / sqrt(π)
  nodes <- sqrt(2) * gh_standard$x
  weights <- gh_standard$w / sqrt(pi)

  # Verify sum of weights (should be close to 1.0 for N(0,1))
  weight_sum <- sum(weights)
  if (abs(weight_sum - 1.0) > 1e-10) {
    warning(sprintf("GH weights sum to %.12f (expected 1.0). Check transformation.", weight_sum))
  }

  cat(sprintf("[OK] Generated %d GH nodes for N(0,1) integration\n", n_nodes))
  cat(sprintf("     Node range: [%.3f, %.3f]\n", min(nodes), max(nodes)))
  cat(sprintf("     Weights sum: %.12f\n", weight_sum))

  return(list(nodes = nodes, weights = weights))
}


#' Create Stratified Folds for Cross-Validation
#'
#' Creates K stratified folds by sorting participants by logitwgt (primary)
#' and age (secondary), then numbering off consecutively. Ensures balanced
#' distribution of authenticity weights and ages across folds.
#'
#' @param logitwgt Vector of logit-scale weights (length N)
#' @param age Vector of ages (length N)
#' @param n_folds Number of folds (default: 16)
#' @return Integer vector of length N with fold assignments (1 to n_folds)
#'
#' @details
#' Stratification procedure:
#'   1. Sort participants by logitwgt (primary), age (secondary)
#'   2. Number off consecutively: 1, 2, 3, ..., n_folds, 1, 2, 3, ...
#'   3. Result: Each fold has similar weight/age distribution
#'
#' This prevents fold imbalance where all inauthentic participants cluster
#' in one fold, which would give misleading CV estimates.
#'
#' @examples
#' logitwgt <- rnorm(1000, 0, 2)
#' age <- runif(1000, 0, 6)
#' folds <- create_stratified_folds(logitwgt, age, n_folds = 16)
#' table(folds)  # Should be balanced (62-63 per fold)
create_stratified_folds <- function(logitwgt, age, n_folds = 16) {

  if (length(logitwgt) != length(age)) {
    stop("logitwgt and age must have same length")
  }

  N <- length(logitwgt)

  # Create data frame for sorting
  df <- data.frame(
    id = 1:N,
    logitwgt = logitwgt,
    age = age
  )

  # Sort by logitwgt (primary), age (secondary)
  df_sorted <- df[order(df$logitwgt, df$age), ]

  # Number off consecutively
  df_sorted$fold <- rep(1:n_folds, length.out = N)

  # Restore original order
  df_sorted <- df_sorted[order(df_sorted$id), ]

  folds <- df_sorted$fold

  # Diagnostics
  fold_counts <- table(folds)
  cat(sprintf("[OK] Created %d stratified folds (N=%d)\n", n_folds, N))
  cat(sprintf("     Fold sizes: %d to %d participants\n",
              min(fold_counts), max(fold_counts)))

  # Check balance of weights across folds
  fold_mean_wgt <- tapply(logitwgt, folds, mean)
  cat(sprintf("     Mean logitwgt by fold: %.3f to %.3f (range: %.3f)\n",
              min(fold_mean_wgt), max(fold_mean_wgt),
              diff(range(fold_mean_wgt))))

  return(folds)
}


#' Prepare Data for CV Stan Model (Integrated or Joint Posterior)
#'
#' Splits data into training and holdout sets for one CV fold, formats for
#' authenticity_glmm_cv_integrated.stan or authenticity_glmm_cv_joint.stan.
#'
#' @param M_data Data frame with columns: person_id, item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param folds Vector of fold assignments (length = number of unique person_ids)
#' @param holdout_fold Which fold to hold out (1 to n_folds)
#' @param gh List with nodes and weights from get_gh_nodes_weights()
#' @return List suitable for passing to rstan::optimizing()
#'
#' @details
#' This function prepares data for the NEW CV models (Phase 3 refactor):
#'   - NO lambda_skew or sigma_sum_w (penalties only used in Phase 1b)
#'   - Data already filtered to w > 0.5 (no weight parameters needed)
#'   - Includes kvec and dimvec for efficient item lookups
#'
#' NOTE: M_data uses person_id (1:N) as unique identifier.
#' This is created in 00_prepare_cv_data.R by mapping (pid, record_id) → person_id.
#'
#' @examples
#' \dontrun{
#' gh <- get_gh_nodes_weights(21)
#' stan_data <- prepare_cv_stan_data(
#'   M_data = responses,
#'   J_data = items,
#'   folds = folds,
#'   holdout_fold = 1,
#'   gh = gh
#' )
#' fit <- rstan::optimizing(stan_model_integrated, data = stan_data, iter = 10000)
#' }
prepare_cv_stan_data <- function(M_data, J_data, folds, holdout_fold, gh) {

  # Get unique person_ids
  unique_person_ids <- unique(M_data$person_id)
  N_total <- length(unique_person_ids)

  if (length(folds) != N_total) {
    stop(sprintf("folds length (%d) != number of unique person_ids (%d)",
                 length(folds), N_total))
  }

  # Create person_id to fold mapping
  person_to_fold <- data.frame(person_id = unique_person_ids, fold = folds)

  # Split into training and holdout
  train_person_ids <- person_to_fold$person_id[person_to_fold$fold != holdout_fold]
  holdout_person_ids <- person_to_fold$person_id[person_to_fold$fold == holdout_fold]

  # Filter observations
  M_train <- M_data[M_data$person_id %in% train_person_ids, ]
  M_holdout <- M_data[M_data$person_id %in% holdout_person_ids, ]

  # Re-index persons (1:N_train and 1:N_holdout)
  train_person_map <- data.frame(
    person_id = train_person_ids,
    new_id = 1:length(train_person_ids)
  )
  holdout_person_map <- data.frame(
    person_id = holdout_person_ids,
    new_id = 1:length(holdout_person_ids)
  )

  M_train$ivec <- train_person_map$new_id[match(M_train$person_id, train_person_map$person_id)]
  M_holdout$ivec <- holdout_person_map$new_id[match(M_holdout$person_id, holdout_person_map$person_id)]

  # Get age vectors
  age_train <- M_train %>%
    dplyr::group_by(ivec) %>%
    dplyr::summarise(age = dplyr::first(age), .groups = "drop") %>%
    dplyr::arrange(ivec) %>%
    dplyr::pull(age)

  age_holdout <- M_holdout %>%
    dplyr::group_by(ivec) %>%
    dplyr::summarise(age = dplyr::first(age), .groups = "drop") %>%
    dplyr::arrange(ivec) %>%
    dplyr::pull(age)

  # Prepare Stan data
  stan_data <- list(
    # Training data
    M_train = nrow(M_train),
    N_train = length(train_person_ids),
    J = nrow(J_data),
    ivec_train = M_train$ivec,
    jvec_train = M_train$item_id,
    yvec_train = M_train$response,
    age_train = age_train,

    # Holdout data
    M_holdout = nrow(M_holdout),
    N_holdout = length(holdout_person_ids),
    ivec_holdout = M_holdout$ivec,
    jvec_holdout = M_holdout$item_id,
    yvec_holdout = M_holdout$response,
    age_holdout = age_holdout,

    # Item metadata
    K = J_data$K,
    dimension = J_data$dimension,
    kvec = J_data$K,        # Lookup: category count per item (same as K)
    dimvec = J_data$dimension,  # Lookup: dimension per item (same as dimension)

    # Gauss-Hermite quadrature
    n_nodes = length(gh$nodes),
    gh_nodes = gh$nodes,
    gh_weights = gh$weights
  )

  cat(sprintf("[OK] Prepared CV data for fold %d (holdout)\n", holdout_fold))
  cat(sprintf("     Training: N=%d, M=%d observations\n",
              stan_data$N_train, stan_data$M_train))
  cat(sprintf("     Holdout:  N=%d, M=%d observations\n",
              stan_data$N_holdout, stan_data$M_holdout))

  return(stan_data)
}


#' Aggregate CV Results Across Folds
#'
#' @param cv_fits List of Stan fit objects, one per fold
#' @return Data frame with columns: fold, fold_loss, N_holdout
aggregate_cv_results <- function(cv_fits) {

  results <- data.frame(
    fold = integer(),
    fold_loss = numeric(),
    N_holdout = integer()
  )

  for (k in seq_along(cv_fits)) {
    fit <- cv_fits[[k]]
    fold_loss <- fit$par["fold_loss"]
    # For optimization, N_holdout should be passed separately or extracted from data
    # Assuming it's available in the fit object's theta_tilde or data
    N_holdout <- length(fit$par[startsWith(names(fit$par), "holdout_deviance")])

    results <- rbind(results, data.frame(
      fold = k,
      fold_loss = fold_loss,  # Direct value from optimization
      N_holdout = N_holdout
    ))
  }

  # Compute overall CV loss
  cv_loss <- mean(results$fold_loss)

  cat(sprintf("[OK] CV loss across %d folds: %.4f\n", nrow(results), cv_loss))
  cat(sprintf("     Fold loss range: %.4f to %.4f\n",
              min(results$fold_loss), max(results$fold_loss)))

  return(list(
    cv_loss = cv_loss,
    fold_results = results
  ))
}
