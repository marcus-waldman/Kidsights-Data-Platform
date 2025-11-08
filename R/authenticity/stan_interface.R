#' Stan Interface for Authenticity Screening GLMM
#'
#' Functions to compile and fit the authenticity screening Stan model

library(cmdstanr)

#' Compile the authenticity GLMM Stan model
#'
#' @param stan_file Path to .stan file (default: models/authenticity_glmm.stan)
#' @param force_recompile Force recompilation even if model exists
#' @return cmdstan_model object
#' @export
compile_authenticity_model <- function(stan_file = "models/authenticity_glmm.stan",
                                        force_recompile = FALSE) {

  cat("Compiling Stan model...\n")
  cat("  File:", stan_file, "\n")

  model <- cmdstanr::cmdstan_model(
    stan_file = stan_file,
    compile = TRUE,
    force_recompile = force_recompile
  )

  cat("[OK] Model compiled successfully\n")
  return(model)
}

#' Fit authenticity GLMM using L-BFGS optimization
#'
#' @param stan_data List with M, N, J, ivec, jvec, yvec, age, K
#' @param model Compiled cmdstan_model object (or NULL to compile)
#' @param init_values Optional list of starting values
#' @param algorithm Optimization algorithm ("lbfgs" or "bfgs")
#' @param max_iterations Maximum optimization iterations
#' @param tol_obj Objective function tolerance
#' @param tol_rel_obj Relative objective function tolerance
#' @param tol_grad Gradient tolerance
#' @param tol_rel_grad Relative gradient tolerance
#' @param tol_param Parameter tolerance
#' @param history_size L-BFGS history size
#' @param refresh Progress update frequency (0 = no output)
#' @return cmdstan_optimize object with fitted results
#' @export
fit_authenticity_glmm <- function(stan_data,
                                   model = NULL,
                                   init_values = NULL,
                                   algorithm = "lbfgs",
                                   max_iterations = 10000,
                                   tol_obj = 1e-12,
                                   tol_rel_obj = 1,
                                   tol_grad = 1e-8,
                                   tol_rel_grad = 1e3,
                                   tol_param = 1e-8,
                                   history_size = 5,
                                   refresh = 100) {

  # Compile model if not provided
  if (is.null(model)) {
    model <- compile_authenticity_model()
  }

  cat("\nFitting authenticity GLMM...\n")
  cat("  Algorithm:", algorithm, "\n")
  cat("  Observations (M):", stan_data$M, "\n")
  cat("  Persons (N):", stan_data$N, "\n")
  cat("  Items (J):", stan_data$J, "\n")

  # Wrap init_values in list if provided (CmdStanR requirement)
  if (!is.null(init_values)) {
    init_values <- list(init_values)
  } else {
    init_values = 0
  }

  # Fit model using optimization
  fit <- model$optimize(
    data = stan_data,
    init = init_values,
    algorithm = algorithm,
    iter = max_iterations,
    tol_obj = tol_obj,
    tol_rel_obj = tol_rel_obj,
    tol_grad = tol_grad,
    tol_rel_grad = tol_rel_grad,
    tol_param = tol_param,
    history_size = history_size,
    refresh = refresh
  )

  cat("\n[OK] Model fitting complete\n")

  # Print convergence info
  cat("\nConvergence diagnostics:\n")
  cat("  Return code:", fit$return_codes(), "\n")

  return(fit)
}

#' Extract parameter estimates from fitted model
#'
#' @param fit cmdstan_optimize object
#' @return List with tau, beta1, delta, sigma, eta
#' @export
extract_parameters <- function(fit) {

  # Get parameter draws as data frame
  draws_df <- fit$draws(format = "df")

  # Extract vectors/scalars
  params <- list(
    tau = as.numeric(draws_df[1, grepl("^tau\\[", names(draws_df))]),
    beta1 = as.numeric(draws_df[1, grepl("^beta1\\[", names(draws_df))]),
    delta = as.numeric(draws_df$delta[1]),
    eta = as.numeric(draws_df[1, grepl("^eta\\[", names(draws_df))])
  )

  return(params)
}

#' Extract person-level log-likelihoods
#'
#' @param fit cmdstan_optimize object
#' @return Vector of log-likelihoods (length N)
#' @export
extract_log_lik <- function(fit) {

  draws_df <- fit$draws(format = "df")

  log_lik_cols <- grepl("^log_lik\\[", names(draws_df))
  log_lik <- as.numeric(draws_df[1, log_lik_cols])

  return(log_lik)
}

#' Create starting values for Stan model
#'
#' Conservative initial values to avoid numerical issues
#'
#' @param J Number of items
#' @param N Number of persons
#' @param seed Random seed
#' @return List of starting values
#' @export
create_init_values <- function(J, N, seed = 123) {

  set.seed(seed)

  # Create sum-to-zero person effects
  eta_init <- rnorm(N, 0, 0.1)
  eta_init <- eta_init - mean(eta_init)  # Enforce sum-to-zero

  init <- list(
    tau = rnorm(J, 0, 0.5),      # More conservative threshold spread
    beta1 = rnorm(J, 0, 0.1),    # Smaller age effects initially
    delta = 0.5,                  # Fixed moderate spacing
    eta = eta_init                # Sum-to-zero person effects
  )

  return(init)
}

#' Create starting values from previous fit (for LOOCV warm starts)
#'
#' @param params List of parameter estimates from previous fit
#' @param exclude_person Person index to exclude (for LOOCV)
#' @return List of starting values
#' @export
create_warm_start <- function(params, exclude_person = NULL) {

  init <- list(
    tau = params$tau,
    beta1 = params$beta1,
    delta = params$delta,
    eta = params$eta
  )

  # If excluding a person, remove their eta
  if (!is.null(exclude_person)) {
    init$eta <- init$eta[-exclude_person]
  }

  return(init)
}
