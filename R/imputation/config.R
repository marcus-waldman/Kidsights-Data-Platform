# Configuration loader for imputation pipeline (R)
# Provides single source of truth by calling Python functions via reticulate

#' Get Python imputation module
#'
#' @keywords internal
.get_python_imputation <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
  }

  # Import Python imputation module
  tryCatch({
    reticulate::import("python.imputation")
  }, error = function(e) {
    stop(
      "Failed to import python.imputation module.\n",
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


# Test if run directly
if (interactive()) {
  config <- get_imputation_config()
  cat("Imputation Configuration:\n")
  cat("  Number of imputations (M):", config$n_imputations, "\n")
  cat("  Random seed:", config$random_seed, "\n")
  cat("  Geography variables:", paste(config$geography$variables, collapse = ", "), "\n")
  cat("  Database path:", config$database$db_path, "\n")
}
