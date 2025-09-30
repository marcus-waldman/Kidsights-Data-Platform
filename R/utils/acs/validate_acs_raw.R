#' ACS Data Validation Module
#'
#' Validate raw ACS data from IPUMS extracts for quality and completeness.
#' Performs validation only - NO transformations or recoding.
#'
#' @description
#' This module validates that IPUMS ACS extracts meet expected criteria:
#' - All expected variables present
#' - Attached characteristics exist (EDUC_mom, EDUC_pop, etc.)
#' - Filters were applied correctly (AGE 0-5, correct STATEFIP)
#' - Critical variables present and valid (SERIAL, PERNUM, weights)
#' - No duplicate person records
#' - Sampling weights are valid
#'
#' **IMPORTANT**: This module performs validation ONLY. It does not modify,
#' recode, or transform any IPUMS variables.
#'
#' @section Functions:
#' - validate_acs_raw_data(): Main validation function
#' - check_variable_presence(): Check expected variables exist
#' - check_attached_characteristics(): Verify attached characteristics
#' - check_filters_applied(): Verify age and state filters
#' - check_critical_variables(): Check SERIAL, PERNUM, weights
#' - print_validation_report(): Print formatted validation report
#'
#' @section Required Packages:
#' - dplyr: For data manipulation
#'
#' @examples
#' \dontrun{
#' # Load data
#' ne_acs <- load_acs_feather("nebraska", "2019-2023")
#'
#' # Validate
#' validation <- validate_acs_raw_data(ne_acs, state_fip = 31, state = "nebraska")
#'
#' # Print report
#' print_validation_report(validation)
#' }


#' Check for expected variable presence
#'
#' Verify that expected IPUMS variables are present in the dataset.
#'
#' @param data data.frame. ACS data to validate
#' @param expected_vars Character vector. Expected variable names (optional)
#'
#' @return List with: passed (logical), missing_vars (character vector), message (character)
#'
#' @keywords internal
check_variable_presence <- function(data, expected_vars = NULL) {

  result <- list(
    check_name = "Variable Presence",
    passed = TRUE,
    missing_vars = character(0),
    message = "All expected variables present"
  )

  if (is.null(expected_vars) || length(expected_vars) == 0) {
    # No specific expectations, just check we have some variables
    if (ncol(data) == 0) {
      result$passed <- FALSE
      result$message <- "Dataset has no variables"
    } else {
      result$message <- sprintf("Dataset has %s variables (no specific expectations)", ncol(data))
    }
    return(result)
  }

  # Check for missing expected variables
  missing_vars <- setdiff(expected_vars, names(data))

  if (length(missing_vars) > 0) {
    result$passed <- FALSE
    result$missing_vars <- missing_vars
    result$message <- sprintf(
      "Missing %s expected variable(s): %s",
      length(missing_vars),
      paste(head(missing_vars, 5), collapse = ", ")
    )
  }

  return(result)
}


#' Check attached characteristics
#'
#' Verify that attached characteristics variables exist (e.g., EDUC_mom, EDUC_pop).
#'
#' @param data data.frame. ACS data to validate
#' @param required_attached Character vector. Required attached characteristic suffixes
#'   (default: c("_mom", "_pop"))
#'
#' @return List with check results
#'
#' @keywords internal
check_attached_characteristics <- function(data, required_attached = c("_mom", "_pop")) {

  result <- list(
    check_name = "Attached Characteristics",
    passed = TRUE,
    found_attached = character(0),
    missing_attached = character(0),
    message = ""
  )

  # Find all variables with attached characteristic suffixes
  all_var_names <- names(data)

  found_attached <- character(0)
  for (suffix in required_attached) {
    vars_with_suffix <- grep(paste0(suffix, "$"), all_var_names, value = TRUE)
    found_attached <- c(found_attached, vars_with_suffix)
  }

  result$found_attached <- unique(found_attached)

  if (length(found_attached) == 0) {
    result$passed <- FALSE
    result$message <- sprintf(
      "No attached characteristics found (expected suffixes: %s)",
      paste(required_attached, collapse = ", ")
    )
  } else {
    result$message <- sprintf(
      "Found %s attached characteristic variable(s): %s",
      length(found_attached),
      paste(head(found_attached, 5), collapse = ", ")
    )
  }

  return(result)
}


#' Check filters were applied
#'
#' Verify that age and state filters were correctly applied during extraction.
#'
#' @param data data.frame. ACS data to validate
#' @param expected_ages Integer vector. Expected age values (default: 0:5)
#' @param expected_statefip Integer. Expected state FIPS code (optional)
#' @param state Character. State name for error messages (optional)
#'
#' @return List with check results
#'
#' @keywords internal
check_filters_applied <- function(data,
                                   expected_ages = 0:5,
                                   expected_statefip = NULL,
                                   state = NULL) {

  result <- list(
    check_name = "Filter Application",
    passed = TRUE,
    age_check = list(),
    state_check = list(),
    message = ""
  )

  messages <- character(0)

  # Check AGE filter
  if ("AGE" %in% names(data)) {
    observed_ages <- unique(data$AGE)
    unexpected_ages <- setdiff(observed_ages, expected_ages)

    if (length(unexpected_ages) > 0) {
      result$passed <- FALSE
      result$age_check$unexpected_ages <- unexpected_ages
      messages <- c(messages, sprintf(
        "Unexpected ages found: %s (expected only %s)",
        paste(head(sort(unexpected_ages), 10), collapse = ", "),
        paste(range(expected_ages), collapse = "-")
      ))
    } else {
      result$age_check$all_expected <- TRUE
      messages <- c(messages, sprintf(
        "AGE filter OK: all records are ages %s",
        paste(range(expected_ages), collapse = "-")
      ))
    }
  } else {
    result$passed <- FALSE
    messages <- c(messages, "AGE variable not found - cannot verify age filter")
  }

  # Check STATEFIP filter
  if (!is.null(expected_statefip) && "STATEFIP" %in% names(data)) {
    observed_fips <- unique(data$STATEFIP)

    if (length(observed_fips) != 1 || observed_fips[1] != expected_statefip) {
      result$passed <- FALSE
      result$state_check$observed_fips <- observed_fips
      state_msg <- if (!is.null(state)) sprintf(" (%s)", state) else ""
      messages <- c(messages, sprintf(
        "STATEFIP mismatch: expected %s%s, found %s",
        expected_statefip,
        state_msg,
        paste(observed_fips, collapse = ", ")
      ))
    } else {
      result$state_check$all_expected <- TRUE
      state_msg <- if (!is.null(state)) sprintf(" (%s)", state) else ""
      messages <- c(messages, sprintf(
        "STATEFIP filter OK: all records are FIPS %s%s",
        expected_statefip,
        state_msg
      ))
    }
  } else if (!is.null(expected_statefip)) {
    result$passed <- FALSE
    messages <- c(messages, "STATEFIP variable not found - cannot verify state filter")
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check critical IPUMS variables
#'
#' Verify presence and validity of critical IPUMS variables (SERIAL, PERNUM, weights).
#'
#' @param data data.frame. ACS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_critical_variables <- function(data) {

  result <- list(
    check_name = "Critical Variables",
    passed = TRUE,
    issues = list(),
    message = ""
  )

  messages <- character(0)

  # Check SERIAL and PERNUM
  critical_ids <- c("SERIAL", "PERNUM")
  missing_ids <- setdiff(critical_ids, names(data))

  if (length(missing_ids) > 0) {
    result$passed <- FALSE
    result$issues$missing_ids <- missing_ids
    messages <- c(messages, sprintf(
      "Missing critical ID variables: %s",
      paste(missing_ids, collapse = ", ")
    ))
  } else {
    # Check for duplicates
    n_dups <- sum(duplicated(data[, c("SERIAL", "PERNUM")]))

    if (n_dups > 0) {
      result$passed <- FALSE
      result$issues$duplicate_records <- n_dups
      messages <- c(messages, sprintf(
        "Found %s duplicate SERIAL+PERNUM records",
        format(n_dups, big.mark = ",")
      ))
    } else {
      messages <- c(messages, "SERIAL+PERNUM uniqueness OK (no duplicates)")
    }
  }

  # Check sampling weights
  weight_vars <- c("HHWT", "PERWT")
  present_weights <- intersect(weight_vars, names(data))

  if (length(present_weights) == 0) {
    result$passed <- FALSE
    result$issues$missing_weights <- weight_vars
    messages <- c(messages, "Missing sampling weights (HHWT, PERWT)")
  } else {
    # Check for missing/invalid weights
    for (wt_var in present_weights) {
      n_invalid <- sum(is.na(data[[wt_var]]) | data[[wt_var]] <= 0)

      if (n_invalid > 0) {
        pct_invalid <- round(100 * n_invalid / nrow(data), 2)
        messages <- c(messages, sprintf(
          "WARNING: %s has %s invalid values (%s%%)",
          wt_var,
          format(n_invalid, big.mark = ","),
          pct_invalid
        ))
        # Note: Don't fail validation for invalid weights, just warn
      }
    }

    if (length(present_weights) == length(weight_vars)) {
      messages <- c(messages, "Sampling weights present (HHWT, PERWT)")
    }
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Validate ACS raw data
#'
#' Comprehensive validation of raw IPUMS ACS data. Checks variable presence,
#' attached characteristics, filter application, and data quality.
#'
#' @param data data.frame. ACS data to validate (from load_acs_feather())
#' @param state_fip Integer. Expected state FIPS code (optional but recommended)
#' @param state Character. State name for better error messages (optional)
#' @param year_range Character. Year range for documentation (optional)
#' @param expected_vars Character vector. Expected variable names (optional)
#' @param expected_ages Integer vector. Expected age range (default: 0:5)
#' @param verbose Logical. Print detailed messages? (default: TRUE)
#'
#' @return List containing:
#'   - overall_passed: Logical, TRUE if all checks passed
#'   - n_checks: Integer, number of checks performed
#'   - n_passed: Integer, number of checks passed
#'   - n_failed: Integer, number of checks failed
#'   - checks: List of individual check results
#'   - summary: Character, summary message
#'   - data_info: List with dataset info (rows, columns, etc.)
#'
#' @examples
#' \dontrun{
#' # Load Nebraska data
#' ne_acs <- load_acs_feather("nebraska", "2019-2023")
#'
#' # Validate with state FIPS
#' validation <- validate_acs_raw_data(
#'   ne_acs,
#'   state_fip = 31,
#'   state = "nebraska",
#'   year_range = "2019-2023"
#' )
#'
#' # Check if validation passed
#' if (validation$overall_passed) {
#'   message("✓ All validation checks passed")
#' } else {
#'   warning("⚠ Some validation checks failed")
#'   print_validation_report(validation)
#' }
#' }
#'
#' @export
validate_acs_raw_data <- function(data,
                                   state_fip = NULL,
                                   state = NULL,
                                   year_range = NULL,
                                   expected_vars = NULL,
                                   expected_ages = 0:5,
                                   verbose = TRUE) {

  if (verbose) {
    message("=" * 60)
    message("ACS Data Validation")
    if (!is.null(state)) message(sprintf("State: %s", state))
    if (!is.null(year_range)) message(sprintf("Year Range: %s", year_range))
    message("=" * 60)
  }

  # Collect data info
  data_info <- list(
    n_rows = nrow(data),
    n_cols = ncol(data),
    variable_names = names(data),
    state = state,
    year_range = year_range
  )

  # Run all validation checks
  checks <- list()

  # 1. Variable presence
  checks$variable_presence <- check_variable_presence(data, expected_vars)

  # 2. Attached characteristics
  checks$attached_characteristics <- check_attached_characteristics(data)

  # 3. Filter application
  checks$filters <- check_filters_applied(data, expected_ages, state_fip, state)

  # 4. Critical variables
  checks$critical_variables <- check_critical_variables(data)

  # Aggregate results
  all_passed <- sapply(checks, function(x) x$passed)
  n_checks <- length(checks)
  n_passed <- sum(all_passed)
  n_failed <- sum(!all_passed)

  overall_passed <- all(all_passed)

  # Build summary
  if (overall_passed) {
    summary_msg <- sprintf(
      "✓ All %s validation checks PASSED",
      n_checks
    )
  } else {
    summary_msg <- sprintf(
      "⚠ %s of %s validation checks FAILED",
      n_failed,
      n_checks
    )
  }

  # Create validation result
  validation_result <- list(
    overall_passed = overall_passed,
    n_checks = n_checks,
    n_passed = n_passed,
    n_failed = n_failed,
    checks = checks,
    summary = summary_msg,
    data_info = data_info,
    timestamp = Sys.time()
  )

  # Print summary if verbose
  if (verbose) {
    print_validation_report(validation_result)
  }

  return(validation_result)
}


#' Print validation report
#'
#' Print formatted validation report to console.
#'
#' @param validation List. Validation result from validate_acs_raw_data()
#'
#' @return NULL (prints to console)
#'
#' @examples
#' \dontrun{
#' validation <- validate_acs_raw_data(ne_acs, state_fip = 31)
#' print_validation_report(validation)
#' }
#'
#' @export
print_validation_report <- function(validation) {

  cat("\n")
  cat("=" * 60, "\n")
  cat("VALIDATION REPORT\n")
  cat("=" * 60, "\n")

  # Data info
  cat(sprintf("\nDataset: %s records, %s variables\n",
              format(validation$data_info$n_rows, big.mark = ","),
              validation$data_info$n_cols))

  if (!is.null(validation$data_info$state)) {
    cat(sprintf("State: %s\n", validation$data_info$state))
  }

  if (!is.null(validation$data_info$year_range)) {
    cat(sprintf("Year Range: %s\n", validation$data_info$year_range))
  }

  # Overall result
  cat("\n")
  cat("Overall Result: ")
  if (validation$overall_passed) {
    cat("✓ PASS\n")
  } else {
    cat("✗ FAIL\n")
  }

  cat(sprintf("Checks: %s passed, %s failed (total: %s)\n",
              validation$n_passed,
              validation$n_failed,
              validation$n_checks))

  # Individual check results
  cat("\n")
  cat("-" * 60, "\n")
  cat("Individual Checks:\n")
  cat("-" * 60, "\n")

  for (check_name in names(validation$checks)) {
    check <- validation$checks[[check_name]]

    status <- if (check$passed) "✓ PASS" else "✗ FAIL"
    cat(sprintf("\n%s: %s\n", check$check_name, status))
    cat(sprintf("  %s\n", check$message))
  }

  cat("\n")
  cat("=" * 60, "\n")

  invisible(NULL)
}
