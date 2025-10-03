#' NHIS Data Validation Module
#'
#' Validate raw NHIS data from IPUMS extracts for quality and completeness.
#' Performs validation only - NO transformations or recoding.
#'
#' @description
#' This module validates that IPUMS NHIS extracts meet expected criteria:
#' - All expected variables present (66 NHIS variables)
#' - Expected years present (2019-2024)
#' - Survey design variables valid (STRATA, PSU)
#' - Sampling weights valid (SAMPWEIGHT)
#' - ACE variables in expected ranges
#' - Mental health variables present (GAD-7, PHQ-8)
#' - No duplicate person records
#'
#' **IMPORTANT**: This module performs validation ONLY. It does not modify,
#' recode, or transform any IPUMS variables.
#'
#' @section Functions:
#' - validate_nhis_raw_data(): Main validation function
#' - check_variable_presence(): Check expected variables exist
#' - check_years_present(): Verify expected years present
#' - check_survey_design(): Check STRATA and PSU variables
#' - check_sampling_weights(): Validate SAMPWEIGHT
#' - check_ace_variables(): Check ACE variable ranges
#' - check_mental_health(): Check GAD-7 and PHQ-8 variables
#' - check_critical_variables(): Check SERIAL, PERNUM
#' - print_validation_report(): Print formatted validation report
#'
#' @section Required Packages:
#' - dplyr: For data manipulation
#'
#' @examples
#' \dontrun{
#' # Load data
#' nhis_data <- load_nhis_feather("2019-2024")
#'
#' # Validate
#' validation <- validate_nhis_raw_data(nhis_data, year_range = "2019-2024")
#'
#' # Print report
#' print_validation_report(validation)
#' }


#' Check for expected variable presence
#'
#' Verify that expected IPUMS NHIS variables are present in the dataset.
#'
#' @param data data.frame. NHIS data to validate
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
      paste(head(missing_vars, 10), collapse = ", ")
    )
  } else {
    result$message <- sprintf("All %s expected variables present", length(expected_vars))
  }

  return(result)
}


#' Check expected years present
#'
#' Verify that expected survey years are present in the data.
#'
#' @param data data.frame. NHIS data to validate
#' @param expected_years Integer vector. Expected years (default: 2019:2024)
#'
#' @return List with check results
#'
#' @keywords internal
check_years_present <- function(data, expected_years = 2019:2024) {

  result <- list(
    check_name = "Year Coverage",
    passed = TRUE,
    observed_years = integer(0),
    missing_years = integer(0),
    message = ""
  )

  if (!"YEAR" %in% names(data)) {
    result$passed <- FALSE
    result$message <- "YEAR variable not found - cannot verify year coverage"
    return(result)
  }

  observed_years <- sort(unique(data$YEAR))
  missing_years <- setdiff(expected_years, observed_years)
  extra_years <- setdiff(observed_years, expected_years)

  result$observed_years <- observed_years

  messages <- character(0)

  if (length(missing_years) > 0) {
    result$passed <- FALSE
    result$missing_years <- missing_years
    messages <- c(messages, sprintf(
      "Missing %s expected year(s): %s",
      length(missing_years),
      paste(missing_years, collapse = ", ")
    ))
  }

  if (length(extra_years) > 0) {
    messages <- c(messages, sprintf(
      "Found %s unexpected year(s): %s",
      length(extra_years),
      paste(extra_years, collapse = ", ")
    ))
  }

  if (length(missing_years) == 0 && length(extra_years) == 0) {
    messages <- c(messages, sprintf(
      "All expected years present: %s",
      paste(range(expected_years), collapse = "-")
    ))
  } else if (length(missing_years) == 0) {
    messages <- c(messages, sprintf(
      "All expected years present (%s) plus extras",
      paste(range(expected_years), collapse = "-")
    ))
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check survey design variables
#'
#' Verify that STRATA and PSU variables are present and valid.
#' These are critical for complex survey analysis and variance estimation.
#'
#' @param data data.frame. NHIS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_survey_design <- function(data) {

  result <- list(
    check_name = "Survey Design Variables",
    passed = TRUE,
    issues = list(),
    message = ""
  )

  messages <- character(0)

  # Check STRATA
  if (!"STRATA" %in% names(data)) {
    result$passed <- FALSE
    result$issues$missing_strata <- TRUE
    messages <- c(messages, "STRATA variable missing (required for variance estimation)")
  } else {
    n_strata <- length(unique(data$STRATA))
    messages <- c(messages, sprintf("STRATA present (%s unique strata)", n_strata))
  }

  # Check PSU
  if (!"PSU" %in% names(data)) {
    result$passed <- FALSE
    result$issues$missing_psu <- TRUE
    messages <- c(messages, "PSU variable missing (required for variance estimation)")
  } else {
    n_psu <- length(unique(data$PSU))
    messages <- c(messages, sprintf("PSU present (%s unique PSUs)", n_psu))
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check sampling weights
#'
#' Verify that SAMPWEIGHT is present and valid.
#' SAMPWEIGHT is the primary weight for NHIS analysis.
#'
#' @param data data.frame. NHIS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_sampling_weights <- function(data) {

  result <- list(
    check_name = "Sampling Weights",
    passed = TRUE,
    issues = list(),
    message = ""
  )

  messages <- character(0)

  # Check SAMPWEIGHT (primary weight)
  if (!"SAMPWEIGHT" %in% names(data)) {
    result$passed <- FALSE
    result$issues$missing_sampweight <- TRUE
    messages <- c(messages, "SAMPWEIGHT missing (primary sampling weight)")
  } else {
    n_invalid <- sum(is.na(data$SAMPWEIGHT) | data$SAMPWEIGHT <= 0)

    if (n_invalid > 0) {
      pct_invalid <- round(100 * n_invalid / nrow(data), 2)
      result$issues$invalid_sampweight <- n_invalid
      messages <- c(messages, sprintf(
        "WARNING: SAMPWEIGHT has %s invalid values (%s%%)",
        format(n_invalid, big.mark = ","),
        pct_invalid
      ))
    } else {
      messages <- c(messages, "SAMPWEIGHT present and valid (all positive)")
    }
  }

  # Check LONGWEIGHT and PARTWT (2020 specific, optional)
  optional_weights <- c("LONGWEIGHT", "PARTWT")
  present_optional <- intersect(optional_weights, names(data))

  if (length(present_optional) > 0) {
    messages <- c(messages, sprintf(
      "Optional weights present: %s",
      paste(present_optional, collapse = ", ")
    ))
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check ACE variables
#'
#' Verify that ACE (Adverse Childhood Experiences) variables are in expected ranges.
#' ACE variables should typically be 0-9 or missing/refused.
#'
#' @param data data.frame. NHIS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_ace_variables <- function(data) {

  result <- list(
    check_name = "ACE Variables",
    passed = TRUE,
    issues = list(),
    message = ""
  )

  # ACE variables from config
  ace_vars <- c(
    "VIOLENEV", "JAILEV", "MENTDEPEV", "ALCDRUGEV",
    "ADLTPUTDOWN", "UNFAIRRACE", "UNFAIRSEXOR", "BASENEED"
  )

  present_ace <- intersect(ace_vars, names(data))

  if (length(present_ace) == 0) {
    result$message <- "No ACE variables found (may not be in this extract)"
    return(result)
  }

  messages <- character(0)
  messages <- c(messages, sprintf("Found %s ACE variable(s)", length(present_ace)))

  # Check for out-of-range values (should be 0-9 or missing)
  for (var in present_ace) {
    if (is.numeric(data[[var]])) {
      out_of_range <- sum(!is.na(data[[var]]) & (data[[var]] < 0 | data[[var]] > 9))

      if (out_of_range > 0) {
        result$passed <- FALSE
        result$issues[[var]] <- out_of_range
        messages <- c(messages, sprintf(
          "WARNING: %s has %s out-of-range values",
          var,
          format(out_of_range, big.mark = ",")
        ))
      }
    }
  }

  if (result$passed && length(present_ace) > 0) {
    messages <- c(messages, "All ACE variables in valid range")
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check mental health variables
#'
#' Verify that GAD-7 (anxiety) and PHQ-8 (depression) variables are present.
#' Note: These variables are only available in specific years (2019, 2022).
#'
#' @param data data.frame. NHIS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_mental_health <- function(data) {

  result <- list(
    check_name = "Mental Health Variables",
    passed = TRUE,
    found = list(),
    message = ""
  )

  # GAD-7 anxiety variables
  gad7_vars <- c(
    "GADANX", "GADWORCTRL", "GADWORMUCH", "GADRELAX",
    "GADRSTLS", "GADANNOY", "GADFEAR", "GADCAT"
  )

  # PHQ-8 depression variables
  phq8_vars <- c(
    "PHQINTR", "PHQDEP", "PHQSLEEP", "PHQENGY",
    "PHQEAT", "PHQBAD", "PHQCONC", "PHQMOVE", "PHQCAT"
  )

  present_gad7 <- intersect(gad7_vars, names(data))
  present_phq8 <- intersect(phq8_vars, names(data))

  result$found$gad7 <- present_gad7
  result$found$phq8 <- present_phq8

  messages <- character(0)

  if (length(present_gad7) > 0) {
    messages <- c(messages, sprintf(
      "GAD-7: %s/%s variables present",
      length(present_gad7),
      length(gad7_vars)
    ))
  }

  if (length(present_phq8) > 0) {
    messages <- c(messages, sprintf(
      "PHQ-8: %s/%s variables present",
      length(present_phq8),
      length(phq8_vars)
    ))
  }

  if (length(present_gad7) == 0 && length(present_phq8) == 0) {
    messages <- c(messages, "No mental health variables found (GAD-7/PHQ-8 only in 2019, 2022)")
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Check critical IPUMS variables
#'
#' Verify presence and validity of critical IPUMS variables (SERIAL, PERNUM).
#'
#' @param data data.frame. NHIS data to validate
#'
#' @return List with check results
#'
#' @keywords internal
check_critical_variables <- function(data) {

  result <- list(
    check_name = "Critical ID Variables",
    passed = TRUE,
    issues = list(),
    message = ""
  )

  messages <- character(0)

  # Check SERIAL, PERNUM, and NHISPID
  critical_ids <- c("SERIAL", "PERNUM", "NHISPID")
  missing_ids <- setdiff(critical_ids, names(data))

  if (length(missing_ids) > 0) {
    result$passed <- FALSE
    result$issues$missing_ids <- missing_ids
    messages <- c(messages, sprintf(
      "Missing critical ID variables: %s",
      paste(missing_ids, collapse = ", ")
    ))
  } else {
    # Check for duplicates using NHISPID (true unique person identifier)
    # Note: SERIAL+PERNUM is NOT unique in NHIS (multiple record types per person)
    # NHISPID is the unique person identifier across all record types
    # Exclude missing values (-999998 = not in universe / non-sample persons)
    valid_nhispid <- data$NHISPID[!is.na(data$NHISPID) & data$NHISPID > 0]
    n_dups <- sum(duplicated(valid_nhispid))
    n_missing <- sum(is.na(data$NHISPID) | data$NHISPID < 0)

    if (n_dups > 0) {
      result$passed <- FALSE
      result$issues$duplicate_records <- n_dups
      messages <- c(messages, sprintf(
        "Found %s duplicate NHISPID records (among %s valid)",
        format(n_dups, big.mark = ","),
        format(length(valid_nhispid), big.mark = ",")
      ))
    } else {
      messages <- c(messages, sprintf(
        "NHISPID uniqueness OK (%s valid, %s not-in-universe)",
        format(length(valid_nhispid), big.mark = ","),
        format(n_missing, big.mark = ",")
      ))
    }
  }

  result$message <- paste(messages, collapse = "; ")

  return(result)
}


#' Validate NHIS raw data
#'
#' Comprehensive validation of raw IPUMS NHIS data. Checks variable presence,
#' year coverage, survey design variables, sampling weights, and data quality.
#'
#' @param data data.frame. NHIS data to validate (from load_nhis_feather())
#' @param year_range Character. Year range for documentation (optional)
#' @param expected_years Integer vector. Expected years (default: 2019:2024)
#' @param expected_vars Character vector. Expected variable names (optional, defaults to 66 NHIS vars)
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
#' # Load NHIS data
#' nhis_data <- load_nhis_feather("2019-2024")
#'
#' # Validate with year range
#' validation <- validate_nhis_raw_data(
#'   nhis_data,
#'   year_range = "2019-2024",
#'   expected_years = 2019:2024
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
validate_nhis_raw_data <- function(data,
                                    year_range = NULL,
                                    expected_years = 2019:2024,
                                    expected_vars = NULL,
                                    verbose = TRUE) {

  if (verbose) {
    message(strrep("=", 60))
    message("NHIS Data Validation")
    if (!is.null(year_range)) message(sprintf("Year Range: %s", year_range))
    message(strrep("=", 60))
  }

  # Default expected variables (64 NHIS variables from config - excludes 2020-specific weights)
  if (is.null(expected_vars)) {
    expected_vars <- c(
      # Identifiers (9)
      "YEAR", "SERIAL", "STRATA", "PSU", "NHISHID", "PERNUM", "NHISPID", "HHX",
      "SAMPWEIGHT",  # LONGWEIGHT and PARTWT excluded (2020-specific)
      # Geographic (2)
      "REGION", "URBRRL",
      # Demographics (2)
      "AGE", "SEX",
      # Parent info (13)
      "ISPARENTSC", "PAR1REL", "PAR2REL", "PAR1AGE", "PAR2AGE", "PAR1SEX", "PAR2SEX",
      "PARRELTYPE", "PAR1MARST", "PAR2MARST", "PAR1MARSTAT", "PAR2MARSTAT", "EDUCPARENT",
      # Race/Ethnicity (2)
      "RACENEW", "HISPETH",
      # Education (1)
      "EDUC",
      # Economic (5)
      "FAMTOTINC", "POVERTY", "FSATELESS", "FSBALANC", "OWNERSHIP",
      # ACEs (8)
      "VIOLENEV", "JAILEV", "MENTDEPEV", "ALCDRUGEV", "ADLTPUTDOWN",
      "UNFAIRRACE", "UNFAIRSEXOR", "BASENEED",
      # Mental Health GAD-7 (8)
      "GADANX", "GADWORCTRL", "GADWORMUCH", "GADRELAX", "GADRSTLS",
      "GADANNOY", "GADFEAR", "GADCAT",
      # Mental Health PHQ-8 (9)
      "PHQINTR", "PHQDEP", "PHQSLEEP", "PHQENGY", "PHQEAT",
      "PHQBAD", "PHQCONC", "PHQMOVE", "PHQCAT",
      # Flags (5)
      "SASCRESP", "ASTATFLG", "CSTATFLG", "HHRESP", "RELATIVERESPC"
    )
  }

  # Collect data info
  data_info <- list(
    n_rows = nrow(data),
    n_cols = ncol(data),
    variable_names = names(data),
    year_range = year_range
  )

  # Run all validation checks
  checks <- list()

  # 1. Variable presence
  checks$variable_presence <- check_variable_presence(data, expected_vars)

  # 2. Year coverage
  checks$year_coverage <- check_years_present(data, expected_years)

  # 3. Survey design variables
  checks$survey_design <- check_survey_design(data)

  # 4. Sampling weights
  checks$sampling_weights <- check_sampling_weights(data)

  # 5. Critical ID variables
  checks$critical_variables <- check_critical_variables(data)

  # 6. ACE variables
  checks$ace_variables <- check_ace_variables(data)

  # 7. Mental health variables
  checks$mental_health <- check_mental_health(data)

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
#' @param validation List. Validation result from validate_nhis_raw_data()
#'
#' @return NULL (prints to console)
#'
#' @examples
#' \dontrun{
#' validation <- validate_nhis_raw_data(nhis_data)
#' print_validation_report(validation)
#' }
#'
#' @export
print_validation_report <- function(validation) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("NHIS VALIDATION REPORT\n")
  cat(strrep("=", 60), "\n")

  # Data info
  cat(sprintf("\nDataset: %s records, %s variables\n",
              format(validation$data_info$n_rows, big.mark = ","),
              validation$data_info$n_cols))

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
  cat(strrep("-", 60), "\n")
  cat("Individual Checks:\n")
  cat(strrep("-", 60), "\n")

  for (check_name in names(validation$checks)) {
    check <- validation$checks[[check_name]]

    status <- if (check$passed) "✓ PASS" else "✗ FAIL"
    cat(sprintf("\n%s: %s\n", check$check_name, status))
    cat(sprintf("  %s\n", check$message))
  }

  cat("\n")
  cat(strrep("=", 60), "\n")

  invisible(NULL)
}
