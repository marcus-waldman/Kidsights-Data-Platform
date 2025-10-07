# Configuration loader for imputation pipeline (R)
# Provides single source of truth by calling Python functions via reticulate

#' Get Python imputation config module
#'
#' @keywords internal
.get_python_imputation <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
  }

  # Import Python imputation.config module
  tryCatch({
    reticulate::import("python.imputation.config")
  }, error = function(e) {
    stop(
      "Failed to import python.imputation.config module.\n",
      "Make sure you are in the project root directory.\n",
      "Error: ", e$message
    )
  })
}


#' Load Imputation Configuration
#'
#' Load imputation configuration from YAML file via Python
#'
#' @param config_path Path to config file. If NULL, uses default location.
#'
#' @return List with configuration parameters
#'
#' @examples
#' config <- get_imputation_config()
#' cat("Number of imputations:", config$n_imputations, "\n")
#'
#' @export
get_imputation_config <- function(config_path = NULL) {
  py_imputation <- .get_python_imputation()

  if (is.null(config_path)) {
    config <- py_imputation$get_imputation_config()
  } else {
    config <- py_imputation$get_imputation_config(config_path = config_path)
  }

  return(config)
}


#' Get Number of Imputations
#'
#' Get the number of imputations (M) from config via Python
#'
#' @return Integer, number of imputations to generate
#'
#' @examples
#' M <- get_n_imputations()
#' cat("M =", M, "\n")
#'
#' @export
get_n_imputations <- function() {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_n_imputations())
}


#' Get Random Seed
#'
#' Get the random seed for reproducibility via Python
#'
#' @return Integer or NULL, random seed value
#'
#' @examples
#' seed <- get_random_seed()
#' if (!is.null(seed)) {
#'   set.seed(seed)
#' }
#'
#' @export
get_random_seed <- function() {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_random_seed())
}


#' Get Sociodemographic Imputation Configuration
#'
#' Get sociodemographic imputation settings from config via Python
#'
#' @return List with sociodemographic imputation parameters including:
#'   \itemize{
#'     \item variables: Character vector of variables to impute
#'     \item auxiliary_variables: Character vector of predictor variables
#'     \item eligible_only: Logical, filter to eligible records
#'     \item mice_method: Named list mapping variables to imputation methods
#'     \item rf_package: Character, Random Forest package name
#'     \item remove_collinear: Logical, whether to remove collinear predictors
#'     \item maxit: Integer, maximum iterations for mice
#'     \item chained: Logical, whether to use chained imputation
#'   }
#'
#' @examples
#' sociodem <- get_sociodem_config()
#' cat("Variables to impute:", paste(sociodem$variables, collapse = ", "), "\n")
#' cat("Chained imputation:", sociodem$chained, "\n")
#'
#' @export
get_sociodem_config <- function() {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_sociodem_config())
}


#' Get Sociodemographic Variables to Impute
#'
#' Get list of sociodemographic variables to impute via Python
#'
#' @return Character vector of variable names
#'
#' @examples
#' vars_to_impute <- get_sociodem_variables()
#' cat("Imputing", length(vars_to_impute), "variables\n")
#'
#' @export
get_sociodem_variables <- function() {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_sociodem_variables())
}


#' Get Auxiliary Predictor Variables
#'
#' Get list of auxiliary predictor variables for sociodem imputation via Python
#'
#' @return Character vector of auxiliary variable names
#'
#' @examples
#' aux_vars <- get_auxiliary_variables()
#' cat("Using", length(aux_vars), "auxiliary predictors\n")
#'
#' @export
get_auxiliary_variables <- function() {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_auxiliary_variables())
}


# Test if run directly
if (interactive()) {
  config <- get_imputation_config()
  cat("Imputation Configuration:\n")
  cat("  Number of imputations (M):", config$n_imputations, "\n")
  cat("  Random seed:", config$random_seed, "\n")
  cat("  Geography variables:", paste(config$geography$variables, collapse = ", "), "\n")
  cat("  Sociodem variables:", paste(config$sociodemographic$variables, collapse = ", "), "\n")
  cat("  Auxiliary variables:", paste(config$sociodemographic$auxiliary_variables, collapse = ", "), "\n")
  cat("  Eligible only:", config$sociodemographic$eligible_only, "\n")
  cat("  Chained imputation:", config$sociodemographic$chained, "\n")
  cat("  Database path:", config$database$db_path, "\n")
}
