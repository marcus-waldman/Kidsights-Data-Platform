# Helper functions for working with multiple imputations (R)
# Single source of truth: calls Python functions via reticulate

#' Get Python imputation helpers module
#'
#' @keywords internal
.get_python_helpers <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
  }

  # Import Python imputation module
  tryCatch({
    reticulate::import("python.imputation.helpers")
  }, error = function(e) {
    stop(
      "Failed to import python.imputation.helpers module.\n",
      "Make sure you are in the project root directory.\n",
      "Error: ", e$message
    )
  })
}


#' Get Completed Dataset for Imputation m
#'
#' Construct a completed dataset for a specific imputation by calling Python
#'
#' @param imputation_m Integer, which imputation to retrieve (1 to M)
#' @param variables Character vector of imputed variable names. NULL = all.
#' @param base_table Character, base table name. Default: "ne25_transformed"
#' @param study_id Character, study identifier. Default: "ne25"
#' @param include_observed Logical, include base observed data. Default: TRUE
#'
#' @return data.frame with observed + imputed values
#'
#' @examples
#' # Get imputation 3 with geography only
#' df <- get_completed_dataset(3, variables = c("puma", "county"))
#'
#' # Get all imputed variables for imputation 5
#' df <- get_completed_dataset(5)
#'
#' # Use with survey package
#' library(survey)
#' df1 <- get_completed_dataset(1)
#' design1 <- svydesign(ids = ~1, weights = ~weight, data = df1)
#'
#' @export
get_completed_dataset <- function(
    imputation_m,
    variables = NULL,
    base_table = "ne25_transformed",
    study_id = "ne25",
    include_observed = TRUE
) {
  py_helpers <- .get_python_helpers()

  # Call Python function
  df_py <- py_helpers$get_completed_dataset(
    imputation_m = as.integer(imputation_m),
    variables = variables,
    base_table = base_table,
    study_id = study_id,
    include_observed = include_observed
  )

  # Convert to R data.frame
  df_r <- reticulate::py_to_r(df_py)

  return(df_r)
}


#' Get All Imputations in Long Format
#'
#' Get all M imputations for specified variables in long format via Python
#'
#' @param variables Character vector of imputed variables. NULL = all.
#' @param base_table Character, base table name. Default: "ne25_transformed"
#' @param study_id Character, study identifier. Default: "ne25"
#'
#' @return data.frame with imputation_m column
#'
#' @examples
#' # Get all geography imputations
#' df_long <- get_all_imputations(variables = c("puma", "county"))
#'
#' # Analyze across imputations
#' library(dplyr)
#' df_long %>%
#'   dplyr::group_by(imputation_m, puma) %>%
#'   dplyr::summarise(count = dplyr::n())
#'
#' @export
get_all_imputations <- function(
    variables = NULL,
    base_table = "ne25_transformed",
    study_id = "ne25"
) {
  py_helpers <- .get_python_helpers()

  # Call Python function
  df_py <- py_helpers$get_all_imputations(
    variables = variables,
    base_table = base_table,
    study_id = study_id
  )

  # Convert to R data.frame
  df_r <- reticulate::py_to_r(df_py)

  return(df_r)
}


#' Get Imputation List for mitools/survey Packages
#'
#' Get all M imputations as a list of data.frames for use with survey::withReplicates()
#' or mitools::MIcombine()
#'
#' @param variables Character vector of imputed variables. NULL = all.
#' @param base_table Character, base table name. Default: "ne25_transformed"
#' @param study_id Character, study identifier. Default: "ne25"
#' @param max_m Integer, maximum imputation number. NULL = auto-detect.
#'
#' @return List of M data.frames, each a completed dataset
#'
#' @examples
#' # Get list of 5 imputed datasets
#' imp_list <- get_imputation_list()
#'
#' # Analyze with survey package
#' library(survey)
#' library(mitools)
#'
#' results <- lapply(imp_list, function(df) {
#'   design <- svydesign(ids = ~1, weights = ~weight, data = df)
#'   svymean(~factor(puma), design)
#' })
#'
#' combined <- mitools::MIcombine(results)
#' summary(combined)
#'
#' @export
get_imputation_list <- function(
    variables = NULL,
    base_table = "ne25_transformed",
    study_id = "ne25",
    max_m = NULL
) {
  # Get max_m from config if not specified
  if (is.null(max_m)) {
    source(file.path("R", "imputation", "config.R"))
    max_m <- get_n_imputations()
  }

  # Generate list of completed datasets
  imp_list <- lapply(1:max_m, function(m) {
    get_completed_dataset(
      imputation_m = m,
      variables = variables,
      base_table = base_table,
      study_id = study_id
    )
  })

  return(imp_list)
}


#' Get Imputation Metadata
#'
#' Get metadata about all imputed variables via Python
#'
#' @return data.frame with metadata
#'
#' @examples
#' meta <- get_imputation_metadata()
#' print(meta[, c("variable_name", "n_imputations", "imputation_method")])
#'
#' @export
get_imputation_metadata <- function() {
  py_helpers <- .get_python_helpers()

  # Call Python function
  meta_py <- py_helpers$get_imputation_metadata()

  # Convert to R data.frame
  meta_r <- reticulate::py_to_r(meta_py)

  return(meta_r)
}


#' Get Imputed Variable Summary
#'
#' Get summary statistics for an imputed variable across all imputations via Python
#'
#' @param variable_name Character, name of the imputed variable
#' @param study_id Character, study identifier. Default: "ne25"
#'
#' @return data.frame with summary statistics
#'
#' @examples
#' summary <- get_imputed_variable_summary("puma", study_id = "ne25")
#' print(summary)
#'
#' @export
get_imputed_variable_summary <- function(variable_name, study_id = "ne25") {
  py_helpers <- .get_python_helpers()

  # Call Python function
  summary_py <- py_helpers$get_imputed_variable_summary(
    variable_name = variable_name,
    study_id = study_id
  )

  # Convert to R data.frame
  summary_r <- reticulate::py_to_r(summary_py)

  return(summary_r)
}


#' Validate Imputations
#'
#' Validate imputation tables for completeness and consistency via Python
#'
#' @param study_id Character, study identifier. Default: "ne25"
#'
#' @return List with validation results
#'
#' @examples
#' results <- validate_imputations(study_id = "ne25")
#' if (results$all_valid) {
#'   cat("All imputations valid!\n")
#' } else {
#'   cat("Issues detected:\n")
#'   for (issue in results$issues) {
#'     cat("  -", issue, "\n")
#'   }
#' }
#'
#' @export
validate_imputations <- function(study_id = "ne25") {
  py_helpers <- .get_python_helpers()

  # Call Python function
  results_py <- py_helpers$validate_imputations(study_id = study_id)

  # Convert to R list
  results_r <- reticulate::py_to_r(results_py)

  return(results_r)
}


# Test if run directly
if (interactive()) {
  cat("Testing imputation helper functions (via reticulate)...\n")
  cat("=" * 60, "\n")

  # Test 1: Get metadata
  tryCatch({
    meta <- get_imputation_metadata()
    cat("[OK] Metadata table has", nrow(meta), "variables\n")
    if (nrow(meta) > 0) {
      cat("     Variables:", paste(meta$variable_name, collapse = ", "), "\n")
    }
  }, error = function(e) {
    cat("[FAIL] get_imputation_metadata:", e$message, "\n")
  })

  # Test 2: Validate
  tryCatch({
    results <- validate_imputations()
    if (results$all_valid) {
      cat("[OK] All", results$variables_checked, "variables validated\n")
    } else {
      cat("[WARN] Validation issues found:\n")
      for (issue in results$issues) {
        cat("     -", issue, "\n")
      }
    }
  }, error = function(e) {
    cat("[INFO] Validation skipped (no imputations yet):", e$message, "\n")
  })

  cat("\n", "=" * 60, "\n")
  cat("Helper functions ready!\n")
}
