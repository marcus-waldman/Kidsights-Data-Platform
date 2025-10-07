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


#' Load Study-Specific Imputation Configuration
#'
#' Load study-specific imputation configuration from YAML file via Python
#'
#' @param study_id Study identifier (e.g., "ne25", "ia26", "co27")
#'
#' @return List with study-specific configuration parameters including:
#'   \itemize{
#'     \item study_id: Character, study identifier
#'     \item study_name: Character, full study name
#'     \item table_prefix: Character, database table prefix (e.g., "ne25_imputed")
#'     \item data_dir: Character, study-specific data directory
#'     \item scripts_dir: Character, study-specific scripts directory
#'     \item n_imputations: Integer, number of imputations (M)
#'     \item ... (all other config fields)
#'   }
#'
#' @examples
#' config <- get_study_config("ne25")
#' cat("Study:", config$study_name, "\n")
#' cat("Table prefix:", config$table_prefix, "\n")
#' cat("Data directory:", config$data_dir, "\n")
#'
#' @export
get_study_config <- function(study_id = "ne25") {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_study_config(study_id = study_id))
}


#' Get Database Table Prefix for Study
#'
#' Get the database table prefix for a specific study via Python
#'
#' @param study_id Study identifier (e.g., "ne25", "ia26", "co27")
#'
#' @return Character, table prefix (e.g., "ne25_imputed")
#'
#' @examples
#' prefix <- get_table_prefix("ne25")
#' cat("Table prefix:", prefix, "\n")
#'
#' # Construct table name
#' table_name <- paste0(get_table_prefix("ne25"), "_female")
#' cat("Full table name:", table_name, "\n")
#'
#' @export
get_table_prefix <- function(study_id = "ne25") {
  py_imputation <- .get_python_imputation()
  return(py_imputation$get_table_prefix(study_id = study_id))
}


#' Construct Full Table Name for Imputed Variable
#'
#' Construct full database table name for an imputed variable
#'
#' @param variable_name Variable name (e.g., "female", "puma", "raceG")
#' @param study_id Study identifier (e.g., "ne25", "ia26", "co27")
#'
#' @return Character, full table name (e.g., "ne25_imputed_female")
#'
#' @examples
#' table_name <- get_table_name("female", "ne25")
#' cat("Table name:", table_name, "\n")  # "ne25_imputed_female"
#'
#' table_name <- get_table_name("puma", "ne25")
#' cat("Table name:", table_name, "\n")  # "ne25_imputed_puma"
#'
#' @export
get_table_name <- function(variable_name, study_id = "ne25") {
  prefix <- get_table_prefix(study_id)
  return(paste0(prefix, "_", variable_name))
}


#' Get Study-Specific Data Directory
#'
#' Get the data directory path for a specific study
#'
#' @param study_id Study identifier (e.g., "ne25", "ia26", "co27")
#'
#' @return Character, data directory path (e.g., "data/imputation/ne25")
#'
#' @examples
#' data_dir <- get_data_dir("ne25")
#' cat("Data directory:", data_dir, "\n")
#'
#' # Construct path to feather files
#' feather_dir <- file.path(data_dir, "sociodem_feather")
#' cat("Feather directory:", feather_dir, "\n")
#'
#' @export
get_data_dir <- function(study_id = "ne25") {
  config <- get_study_config(study_id)
  return(config$data_dir)
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
