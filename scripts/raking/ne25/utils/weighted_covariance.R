# Weighted Covariance Utility
# Computes weighted mean vectors and covariance matrices for survey-weighted data

#' Compute Weighted Mean and Covariance Matrix
#'
#' Calculates weighted mean vector and covariance matrix from design matrix.
#' Properly handles survey weights to estimate population parameters.
#'
#' @param X Numeric matrix (n × p) containing observed values
#'          Rows = observations, Columns = variables
#'          Missing values should be removed before calling this function
#' @param weights Numeric vector (length n) of survey weights
#'                Should be strictly positive. Will be normalized internally.
#'
#' @return List containing:
#'   \item{mu}{Weighted mean vector (p × 1)}
#'   \item{Sigma}{Weighted covariance matrix (p × p)}
#'   \item{n}{Number of observations}
#'   \item{n_eff}{Effective sample size based on Kish design effect}
#'   \item{weight_sum}{Sum of weights (population total)}
#'
#' @details
#' **Weighted Covariance Calculation:**
#'
#' Given weights w_i (e.g., survey design weights):
#'
#' 1. Weighted mean: μ = Σ(w_i * X_i) / Σ(w_i)
#' 2. Center data: X̃ = X - μ
#' 3. Weighted covariance: Σ = (Σ(w_i * X̃_i * X̃_i^T)) / Σ(w_i)
#'
#' This uses the "standard" estimator (divides by sum of weights, not Bessel correction).
#' Appropriate for survey data with known population weights.
#'
#' **Effective Sample Size (Kish, 1965):**
#'
#' n_eff = (Σ w_i)^2 / Σ(w_i^2)
#'
#' This measures efficiency loss from unequal weighting.
#' If all weights equal: n_eff = n
#' If weights highly variable: n_eff << n (efficiency loss)
#'
#' **Common Support Check (for Propensity Weighting):**
#'
#' After propensity score reweighting, you should verify:
#' - n_eff / n > 0.5 (retain at least 50% effective sample)
#' - Propensity scores overlap between target and source population
#'
#' @examples
#' \dontrun{
#' # Simple example
#' X <- matrix(rnorm(100 * 5), nrow = 100, ncol = 5)
#' w <- rexp(100)  # Positive weights
#'
#' moments <- compute_weighted_moments(X, w)
#' cat("Weighted mean:\n")
#' print(moments$mu)
#' cat("\nWeighted covariance:\n")
#' print(moments$Sigma)
#' cat("\nEffective sample size:", moments$n_eff, "out of", moments$n, "\n")
#' }
compute_weighted_moments <- function(X, weights) {
  # Input validation
  if (!is.matrix(X)) {
    X <- as.matrix(X)
  }

  n <- nrow(X)
  p <- ncol(X)

  if (length(weights) != n) {
    stop("Length of weights (", length(weights), ") must match nrow(X) (", n, ")")
  }

  if (any(is.na(weights))) {
    stop("weights contains NA values. Remove rows with missing weights before calling.")
  }

  if (any(weights <= 0)) {
    stop("All weights must be strictly positive. Found ", sum(weights <= 0), " non-positive weights.")
  }

  # Normalize weights to sum to 1 for numerical stability
  w_normalized <- weights / sum(weights)
  weight_sum <- sum(weights)

  # Compute weighted mean
  mu <- colSums(X * w_normalized)

  # Center data
  X_centered <- sweep(X, 2, mu, "-")

  # Compute weighted covariance matrix
  # Σ = Σ(w_i * X̃_i * X̃_i^T) / Σ(w_i) = (X̃^T * diag(w) * X̃) / Σ(w)
  # Using crossprod for numerical stability: crossprod(A, B) = A^T * B
  Sigma <- crossprod(X_centered * sqrt(w_normalized)) / sum(w_normalized)

  # Effective sample size (Kish, 1965)
  # n_eff = (Σ w_i)^2 / Σ(w_i^2)
  n_eff <- weight_sum^2 / sum(weights^2)

  list(
    mu = as.vector(mu),
    Sigma = Sigma,
    n = n,
    n_eff = n_eff,
    weight_sum = weight_sum
  )
}

#' Compute Correlation Matrix from Covariance
#'
#' Converts covariance matrix to correlation matrix.
#' Useful for diagnostic comparisons across data sources.
#'
#' @param Sigma Covariance matrix (p × p)
#' @return Correlation matrix (p × p) with 1s on diagonal
#'
#' @details
#' Correlation is computed as: ρ_ij = Σ_ij / (√(Σ_ii) * √(Σ_jj))
cor_from_cov <- function(Sigma) {
  # Get standard deviations from diagonal
  std_dev <- sqrt(diag(Sigma))

  # Correlation matrix: divide covariance by product of std devs
  Sigma / (std_dev %*% t(std_dev))
}

#' Compute Effective Sample Size for Reweighting
#'
#' Evaluates efficiency of propensity score or other reweighting scheme.
#' After reweighting, you should have n_eff / n_raw > 0.5 (retain 50%+ of sample).
#'
#' @param raw_weights Original survey weights (before reweighting)
#' @param adjusted_weights Reweighted values (after propensity adjustment)
#'
#' @return List with:
#'   \item{n_raw}{Original sample size}
#'   \item{n_eff_original}{Effective N from original weights}
#'   \item{n_eff_adjusted}{Effective N from adjusted weights}
#'   \item{efficiency}{Efficiency after reweighting: n_eff_adjusted / n_raw}
#'   \item{warning}{Flag if efficiency < 0.5 (significant loss)}
#'
evaluate_reweighting_efficiency <- function(raw_weights, adjusted_weights) {
  n_raw <- length(raw_weights)
  weight_sum_raw <- sum(raw_weights)
  weight_sum_adj <- sum(adjusted_weights)

  n_eff_original <- weight_sum_raw^2 / sum(raw_weights^2)
  n_eff_adjusted <- weight_sum_adj^2 / sum(adjusted_weights^2)

  efficiency <- n_eff_adjusted / n_raw

  warning_flag <- efficiency < 0.5

  list(
    n_raw = n_raw,
    n_eff_original = n_eff_original,
    n_eff_adjusted = n_eff_adjusted,
    efficiency = efficiency,
    warning = warning_flag
  )
}

#' Check for Missing Data in Design Matrix
#'
#' Validates that design matrix has no missing values.
#' Critical before computing covariance matrices.
#'
#' @param X Design matrix (n × p)
#' @param var_names Optional vector of variable names for reporting
#'
#' @return Logical: TRUE if all values are non-missing
#'
#' @details
#' Returns TRUE/FALSE. If FALSE, will also print summary of missing values by column.
check_missing_data <- function(X, var_names = NULL) {
  missing_per_col <- colSums(is.na(X))
  missing_total <- sum(is.na(X))

  if (missing_total == 0) {
    return(TRUE)
  }

  # Print diagnostic
  if (!is.null(var_names)) {
    for (i in which(missing_per_col > 0)) {
      cat("  Variable '", var_names[i], "': ", missing_per_col[i], " missing\n", sep = "")
    }
  } else {
    for (i in which(missing_per_col > 0)) {
      cat("  Column", i, ":", missing_per_col[i], "missing\n")
    }
  }

  cat("  Total missing:", missing_total, "/ ", nrow(X) * ncol(X), "\n")
  return(FALSE)
}

#' Compute Block-Factored Covariance Matrix
#'
#' Computes weighted covariance matrix with block structure, handling missing data
#' within blocks (complete-case per block, not global complete-case).
#'
#' @param X Design matrix (n × p) with all variables
#' @param weights Survey weights (length n)
#' @param block_indices List of variable indices for each block
#'        e.g., list(block1 = 1:8, block2 = 9:10, block3 = 11)
#'
#' @return List:
#'   \item{mu}{Weighted mean vector (p × 1)}
#'   \item{Sigma}{Block-factored covariance matrix (p × p)}
#'   \item{n_eff_block}{Effective N for each block (vector)}
#'   \item{block_sample_sizes}{Actual N used for each block (vector)}
#'   \item{cross_block_n}{Matrix showing joint sample sizes for cross-blocks}
#'
#' @details
#' **Block Structure:**
#'
#' Variables are organized into blocks based on joint availability:
#' - Block 1 (Demographics): Available in all sources
#' - Block 2 (Mental Health): NHIS only
#' - Block 3 (Parental ACEs): NHIS only
#' - Block 4 (Child Outcomes): NSCH only
#'
#' **Missing Data Handling:**
#'
#' Complete-case filtering is applied WITHIN each block:
#' 1. For within-block covariances: Use observations complete on that block
#' 2. For cross-block covariances: Use observations complete on BOTH blocks
#' 3. Missing cross-block covariances (different sources): Set to 0 or NA
#'
#' This approach maximizes sample size while respecting data availability patterns.
#'
#' **Algorithm:**
#'
#' 1. For each block b: Compute Σ_bb using complete cases on block b
#' 2. For each block pair (b1, b2): Compute Σ_b1,b2 using joint complete cases
#' 3. Assemble full covariance matrix with block structure
#'
#' **Advantages over Global Complete-Case:**
#'
#' - Preserves sample size for well-measured blocks
#' - Allows partial participation (e.g., demographics + ACEs, missing mental health)
#' - Efficient use of all available data
#'
#' @examples
#' \dontrun{
#' # 3-block example: Demographics (1-8), Mental Health (9-10), ACEs (11)
#' X <- matrix(rnorm(100 * 11), nrow = 100, ncol = 11)
#' X[1:20, 9:10] <- NA  # Missing mental health for some
#' w <- rexp(100)
#'
#' block_idx <- list(block1 = 1:8, block2 = 9:10, block3 = 11)
#'
#' result <- compute_block_covariance(X, w, block_idx)
#'
#' # Block 1: All 100 observations
#' # Block 2: 80 observations (excluding 20 with missing)
#' # Block 3: All 100 observations
#' # Cross-block (1,2): 80 joint observations
#' }
compute_block_covariance <- function(X, weights, block_indices) {

  # Input validation
  if (!is.matrix(X)) {
    X <- as.matrix(X)
  }

  p <- ncol(X)
  n <- nrow(X)

  if (length(weights) != n) {
    stop("Length of weights (", length(weights), ") must match nrow(X) (", n, ")")
  }

  if (any(is.na(weights) | weights <= 0)) {
    stop("All weights must be strictly positive and non-missing")
  }

  # Initialize moments
  mu <- numeric(p)
  Sigma <- matrix(NA_real_, nrow = p, ncol = p)

  n_blocks <- length(block_indices)
  n_eff_block <- numeric(n_blocks)
  block_n <- numeric(n_blocks)
  names(n_eff_block) <- names(block_indices)
  names(block_n) <- names(block_indices)

  # Matrix to track joint sample sizes
  cross_block_n <- matrix(0, nrow = n_blocks, ncol = n_blocks)
  rownames(cross_block_n) <- names(block_indices)
  colnames(cross_block_n) <- names(block_indices)

  # STEP 1: Compute within-block moments
  cat("    Computing within-block covariances...\n")
  for (b in seq_along(block_indices)) {
    block_name <- names(block_indices)[b]
    idx <- block_indices[[b]]

    # Complete cases for this block
    X_block <- X[, idx, drop = FALSE]
    complete_rows <- complete.cases(X_block)

    X_block_complete <- X_block[complete_rows, , drop = FALSE]
    w_block <- weights[complete_rows]

    block_n[b] <- sum(complete_rows)
    cross_block_n[b, b] <- block_n[b]

    if (block_n[b] < 30) {
      warning("Block ", block_name, " has only ", block_n[b], " complete observations (< 30)")
    }

    # Compute moments for this block
    block_moments <- compute_weighted_moments(X_block_complete, w_block)

    # Store in overall matrices
    mu[idx] <- block_moments$mu
    Sigma[idx, idx] <- block_moments$Sigma
    n_eff_block[b] <- block_moments$n_eff

    cat("      Block", b, "(", block_name, "):",
        length(idx), "variables,",
        block_n[b], "complete cases,",
        "n_eff =", round(n_eff_block[b], 1), "\n")
  }

  # STEP 2: Compute cross-block covariances
  cat("\n    Computing cross-block covariances...\n")
  for (b1 in seq_along(block_indices)) {
    for (b2 in seq_along(block_indices)) {
      if (b1 >= b2) next  # Skip diagonal (already computed) and lower triangle

      block1_name <- names(block_indices)[b1]
      block2_name <- names(block_indices)[b2]

      idx1 <- block_indices[[b1]]
      idx2 <- block_indices[[b2]]

      # Joint complete cases for both blocks
      X_joint <- X[, c(idx1, idx2), drop = FALSE]
      complete_rows <- complete.cases(X_joint)

      n_joint <- sum(complete_rows)
      cross_block_n[b1, b2] <- n_joint
      cross_block_n[b2, b1] <- n_joint

      if (n_joint < 30) {
        cat("      [WARN] Blocks", block1_name, "×", block2_name, ": Only", n_joint,
            "joint observations (< 30). Setting cross-covariance to 0.\n")
        Sigma[idx1, idx2] <- 0
        Sigma[idx2, idx1] <- 0
        next
      }

      if (n_joint == 0) {
        cat("      Blocks", block1_name, "×", block2_name, ": No joint observations.",
            "Setting cross-covariance to 0.\n")
        Sigma[idx1, idx2] <- 0
        Sigma[idx2, idx1] <- 0
        next
      }

      X_joint_complete <- X_joint[complete_rows, , drop = FALSE]
      w_joint <- weights[complete_rows]

      # Compute cross-covariances
      joint_moments <- compute_weighted_moments(X_joint_complete, w_joint)

      # Extract off-diagonal blocks
      n1 <- length(idx1)
      n2 <- length(idx2)

      cross_cov <- joint_moments$Sigma[1:n1, (n1+1):(n1+n2), drop = FALSE]

      Sigma[idx1, idx2] <- cross_cov
      Sigma[idx2, idx1] <- t(cross_cov)  # Symmetry

      cat("      Blocks", block1_name, "×", block2_name, ":",
          n_joint, "joint cases\n")
    }
  }

  list(
    mu = mu,
    Sigma = Sigma,
    n_eff_block = n_eff_block,
    block_sample_sizes = block_n,
    cross_block_n = cross_block_n
  )
}
