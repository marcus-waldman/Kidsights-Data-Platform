#' ACS Data Quality Validator
#'
#' Comprehensive data quality validation for ACS extracts with advanced checks:
#' - Value range validation (AGE, SEX, RACE, etc.)
#' - Attached characteristics completeness
#' - Sample size comparison to Census estimates
#' - Distribution anomaly detection
#'
#' Usage:
#'   Rscript scripts/acs/validate_acs_data.R \
#'     --state nebraska \
#'     --year-range 2019-2023 \
#'     --state-fip 31
#'
#' Output:
#'   - Comprehensive validation report
#'   - Data quality score
#'   - Anomaly warnings
#'
#' Author: Kidsights Data Platform
#' Date: 2025-09-30

# Load required packages
suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
})

# Source utility modules
source("R/load/acs/load_acs_data.R")
source("R/utils/acs/validate_acs_raw.R")


#' Check value ranges for IPUMS variables
#'
#' Validates that IPUMS variables fall within expected ranges based on IPUMS coding.
#'
#' @param data data.frame. ACS data to validate
#'
#' @return List with validation results
check_value_ranges <- function(data) {

  result <- list(
    check_name = "Value Ranges",
    passed = TRUE,
    issues = list(),
    message = "All variables within expected ranges"
  )

  # Define expected ranges for key variables
  range_checks <- list(
    # AGE should be 0-5 (our filter)
    AGE = list(min = 0, max = 5),

    # SEX: 1 = Male, 2 = Female
    SEX = list(min = 1, max = 2),

    # RACE: 1-9 (detailed codes vary, but should be single digit generally)
    # Allow up to 99 for detailed codes
    RACE = list(min = 1, max = 99),

    # HISPAN: 0 = Not Hispanic, 1-4 = Hispanic origins, 9 = Not reported
    HISPAN = list(min = 0, max = 9),

    # METRO: 0-4 (metropolitan status)
    METRO = list(min = 0, max = 4),

    # RELATE: 1-13 (relationship to household head)
    RELATE = list(min = 1, max = 13),

    # EDUC: 0-13 (educational attainment general codes)
    EDUC = list(min = 0, max = 13),
    EDUC_mom = list(min = 0, max = 13),
    EDUC_pop = list(min = 0, max = 13),

    # MARST: 1-6 (marital status)
    MARST = list(min = 1, max = 6),
    MARST_head = list(min = 1, max = 6),

    # FOODSTMP: 0-2 (SNAP participation)
    FOODSTMP = list(min = 0, max = 2),

    # HINSCAID: 0-2 (Medicaid coverage)
    HINSCAID = list(min = 0, max = 2),

    # HCOVANY: 0-2 (any health insurance)
    HCOVANY = list(min = 0, max = 2)
  )

  # Check each variable
  for (var_name in names(range_checks)) {
    if (!var_name %in% names(data)) {
      # Variable not present (will be caught by other checks)
      next
    }

    var_data <- data[[var_name]]
    range_def <- range_checks[[var_name]]

    # Remove NAs for range checking
    var_data_clean <- var_data[!is.na(var_data)]

    if (length(var_data_clean) == 0) {
      # All NAs - note but don't fail
      result$issues <- append(result$issues, list(list(
        variable = var_name,
        issue = "All values are NA",
        severity = "warning"
      )))
      next
    }

    # Check min/max
    actual_min <- min(var_data_clean, na.rm = TRUE)
    actual_max <- max(var_data_clean, na.rm = TRUE)

    if (actual_min < range_def$min || actual_max > range_def$max) {
      result$passed <- FALSE
      result$issues <- append(result$issues, list(list(
        variable = var_name,
        issue = sprintf(
          "Values outside expected range: [%s, %s] (actual: [%s, %s])",
          range_def$min, range_def$max, actual_min, actual_max
        ),
        severity = "error"
      )))
    }
  }

  if (length(result$issues) > 0) {
    result$message <- sprintf("Found %s value range issue(s)", length(result$issues))
  }

  return(result)
}


#' Check attached characteristics completeness
#'
#' Validates that attached characteristics are present and have reasonable coverage.
#'
#' @param data data.frame. ACS data to validate
#'
#' @return List with validation results
check_attached_completeness <- function(data) {

  result <- list(
    check_name = "Attached Characteristics Completeness",
    passed = TRUE,
    coverage = list(),
    message = "Attached characteristics have adequate coverage"
  )

  # Define attached characteristics to check
  attached_vars <- c("EDUC_mom", "EDUC_pop", "EDUCD_mom", "EDUCD_pop", "MARST_head")

  for (var_name in attached_vars) {
    if (!var_name %in% names(data)) {
      result$passed <- FALSE
      result$message <- sprintf("Missing attached characteristic: %s", var_name)
      next
    }

    var_data <- data[[var_name]]

    # Calculate coverage (non-missing percentage)
    total <- length(var_data)
    non_missing <- sum(!is.na(var_data) & var_data != 0)  # 0 often means N/A
    coverage_pct <- (non_missing / total) * 100

    result$coverage[[var_name]] <- coverage_pct

    # Warn if coverage is very low (< 50%)
    if (coverage_pct < 50) {
      result$passed <- FALSE
      result$message <- sprintf(
        "Low coverage for %s: %.1f%% (expected > 50%%)",
        var_name, coverage_pct
      )
    }
  }

  return(result)
}


#' Compare sample sizes to Census estimates
#'
#' Compares ACS sample counts to approximate Census population estimates
#' for basic reasonableness checks.
#'
#' @param data data.frame. ACS data to validate
#' @param state Character. State name
#' @param year_range Character. Year range
#'
#' @return List with validation results
check_sample_size <- function(data, state, year_range) {

  result <- list(
    check_name = "Sample Size Comparison",
    passed = TRUE,
    sample_size = nrow(data),
    message = "Sample size is reasonable"
  )

  # Approximate children 0-5 populations for states (2020 Census estimates)
  # Source: US Census Bureau, 2020 ACS 5-year estimates
  state_populations <- list(
    nebraska = 128000,  # ~128k children 0-5
    iowa = 195000,      # ~195k children 0-5
    kansas = 185000,    # ~185k children 0-5
    missouri = 380000,  # ~380k children 0-5
    south_dakota = 60000 # ~60k children 0-5
  )

  # Get expected population
  expected_pop <- state_populations[[tolower(state)]]

  if (is.null(expected_pop)) {
    result$message <- sprintf(
      "No population estimate available for %s (sample: %s)",
      state, format(nrow(data), big.mark = ",")
    )
    return(result)
  }

  # ACS 5-year sample is ~1% of population (varies by state)
  # Allow for 0.5% to 2% sampling rate
  min_expected <- expected_pop * 0.005
  max_expected <- expected_pop * 0.020

  sample_size <- nrow(data)

  if (sample_size < min_expected || sample_size > max_expected) {
    result$passed <- FALSE
    result$message <- sprintf(
      "Sample size (%s) outside expected range [%s, %s] for %s children 0-5",
      format(sample_size, big.mark = ","),
      format(round(min_expected), big.mark = ","),
      format(round(max_expected), big.mark = ","),
      state
    )
  } else {
    result$message <- sprintf(
      "Sample size (%s) is within expected range for %s (pop ~%s)",
      format(sample_size, big.mark = ","),
      state,
      format(expected_pop, big.mark = ",")
    )
  }

  return(result)
}


#' Detect distribution anomalies
#'
#' Flags unusual distributions in key demographic variables.
#'
#' @param data data.frame. ACS data to validate
#'
#' @return List with validation results
check_distribution_anomalies <- function(data) {

  result <- list(
    check_name = "Distribution Anomalies",
    passed = TRUE,
    anomalies = list(),
    message = "No distribution anomalies detected"
  )

  # Check age distribution (should be relatively uniform for 0-5)
  if ("AGE" %in% names(data)) {
    age_counts <- table(data$AGE)
    age_props <- prop.table(age_counts)

    # Each age should be roughly 1/6 = 0.167 (allowing for variance)
    # Flag if any age is < 10% or > 25%
    for (age in names(age_props)) {
      prop <- age_props[age]
      if (prop < 0.10 || prop > 0.25) {
        result$anomalies <- append(result$anomalies, list(list(
          variable = "AGE",
          value = age,
          proportion = sprintf("%.1f%%", prop * 100),
          issue = sprintf("Age %s represents %.1f%% (expected ~16.7%%)", age, prop * 100)
        )))
      }
    }
  }

  # Check sex distribution (should be roughly 50/50)
  if ("SEX" %in% names(data)) {
    sex_counts <- table(data$SEX)
    sex_props <- prop.table(sex_counts)

    # Flag if either sex is < 45% or > 55%
    for (sex in names(sex_props)) {
      prop <- sex_props[sex]
      if (prop < 0.45 || prop > 0.55) {
        result$anomalies <- append(result$anomalies, list(list(
          variable = "SEX",
          value = sex,
          proportion = sprintf("%.1f%%", prop * 100),
          issue = sprintf("Sex %s represents %.1f%% (expected ~50%%)", sex, prop * 100)
        )))
      }
    }
  }

  # Check for excessive missing weights
  if ("PERWT" %in% names(data)) {
    missing_perwt <- sum(is.na(data$PERWT) | data$PERWT == 0)
    missing_pct <- (missing_perwt / nrow(data)) * 100

    if (missing_pct > 1) {  # More than 1% missing weights is unusual
      result$anomalies <- append(result$anomalies, list(list(
        variable = "PERWT",
        value = "Missing/Zero",
        proportion = sprintf("%.1f%%", missing_pct),
        issue = sprintf("%.1f%% of records have missing/zero PERWT", missing_pct)
      )))
    }
  }

  if (length(result$anomalies) > 0) {
    result$passed <- FALSE
    result$message <- sprintf("Found %s distribution anomaly/anomalies", length(result$anomalies))
  }

  return(result)
}


#' Run comprehensive validation
#'
#' Runs all validation checks and generates report.
#'
#' @param data data.frame. ACS data to validate
#' @param state Character. State name
#' @param state_fip Integer. State FIPS code
#' @param year_range Character. Year range
#'
#' @return List with all validation results
run_comprehensive_validation <- function(data, state, state_fip, year_range) {

  cat("======================================================================\n")
  cat("ACS DATA QUALITY VALIDATION\n")
  cat("======================================================================\n")
  cat(sprintf("State: %s\n", state))
  cat(sprintf("Year Range: %s\n", year_range))
  cat(sprintf("Records: %s\n", format(nrow(data), big.mark = ",")))
  cat("\n")

  # Run all checks
  checks <- list()

  # Basic validation from utility module
  cat("[CHECK 1/6] Basic variable validation...\n")
  basic_validation <- validate_acs_raw_data(
    data = data,
    state_fip = state_fip,
    state = state,
    year_range = year_range,
    expected_ages = 0:5,
    verbose = FALSE
  )
  checks$basic <- basic_validation

  # Value range checks
  cat("[CHECK 2/6] Value range validation...\n")
  checks$ranges <- check_value_ranges(data)

  # Attached characteristics completeness
  cat("[CHECK 3/6] Attached characteristics completeness...\n")
  checks$attached <- check_attached_completeness(data)

  # Sample size comparison
  cat("[CHECK 4/6] Sample size comparison...\n")
  checks$sample_size <- check_sample_size(data, state, year_range)

  # Distribution anomalies
  cat("[CHECK 5/6] Distribution anomaly detection...\n")
  checks$anomalies <- check_distribution_anomalies(data)

  # Overall quality score
  cat("[CHECK 6/6] Calculating quality score...\n\n")

  # Calculate overall pass/fail
  all_passed <- TRUE
  if (!is.null(checks$basic) && !all(sapply(checks$basic, `[[`, "passed"))) {
    all_passed <- FALSE
  }
  if (!checks$ranges$passed) all_passed <- FALSE
  if (!checks$attached$passed) all_passed <- FALSE
  if (!checks$sample_size$passed) all_passed <- FALSE
  if (!checks$anomalies$passed) all_passed <- FALSE

  checks$overall_passed <- all_passed

  return(checks)
}


#' Print validation report
#'
#' Prints formatted validation report to console.
#'
#' @param checks List. Validation results from run_comprehensive_validation()
print_validation_report <- function(checks) {

  cat("======================================================================\n")
  cat("VALIDATION REPORT\n")
  cat("======================================================================\n\n")

  # Basic validation
  if (!is.null(checks$basic)) {
    cat("[BASIC VALIDATION]\n")
    for (check in checks$basic) {
      status <- if (check$passed) "[OK]" else "[FAIL]"
      cat(sprintf("  %s %s: %s\n", status, check$check_name, check$message))
    }
    cat("\n")
  }

  # Value ranges
  cat("[VALUE RANGES]\n")
  if (checks$ranges$passed) {
    cat(sprintf("  [OK] %s\n", checks$ranges$message))
  } else {
    cat(sprintf("  [FAIL] %s\n", checks$ranges$message))
    for (issue in checks$ranges$issues) {
      cat(sprintf("    - %s: %s\n", issue$variable, issue$issue))
    }
  }
  cat("\n")

  # Attached characteristics
  cat("[ATTACHED CHARACTERISTICS]\n")
  if (checks$attached$passed) {
    cat(sprintf("  [OK] %s\n", checks$attached$message))
  } else {
    cat(sprintf("  [FAIL] %s\n", checks$attached$message))
  }
  # Show coverage
  for (var_name in names(checks$attached$coverage)) {
    coverage <- checks$attached$coverage[[var_name]]
    cat(sprintf("    - %s: %.1f%% coverage\n", var_name, coverage))
  }
  cat("\n")

  # Sample size
  cat("[SAMPLE SIZE]\n")
  status <- if (checks$sample_size$passed) "[OK]" else "[WARN]"
  cat(sprintf("  %s %s\n", status, checks$sample_size$message))
  cat("\n")

  # Anomalies
  cat("[DISTRIBUTION ANOMALIES]\n")
  if (checks$anomalies$passed) {
    cat(sprintf("  [OK] %s\n", checks$anomalies$message))
  } else {
    cat(sprintf("  [WARN] %s\n", checks$anomalies$message))
    for (anomaly in checks$anomalies$anomalies) {
      cat(sprintf("    - %s\n", anomaly$issue))
    }
  }
  cat("\n")

  # Overall
  cat("======================================================================\n")
  if (checks$overall_passed) {
    cat("[OK] VALIDATION PASSED\n")
  } else {
    cat("[FAIL] VALIDATION FAILED\n")
  }
  cat("======================================================================\n")
}


#' Parse command-line arguments
#'
#' @return List with parsed arguments
parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    cat("Usage: Rscript scripts/acs/validate_acs_data.R --state <state> --year-range <year> --state-fip <fip>\n")
    cat("\nExample:\n")
    cat("  Rscript scripts/acs/validate_acs_data.R --state nebraska --year-range 2019-2023 --state-fip 31\n\n")
    quit(status = 1)
  }

  parsed <- list(
    state = NULL,
    year_range = NULL,
    state_fip = NULL
  )

  i <- 1
  while (i <= length(args)) {
    if (args[i] == "--state") {
      parsed$state <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--year-range") {
      parsed$year_range <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--state-fip") {
      parsed$state_fip <- as.integer(args[i + 1])
      i <- i + 2
    } else {
      i <- i + 1
    }
  }

  # Validate required args
  if (is.null(parsed$state) || is.null(parsed$year_range) || is.null(parsed$state_fip)) {
    stop("Missing required arguments: --state, --year-range, --state-fip")
  }

  return(parsed)
}


#' Main validation workflow
main <- function() {

  # Parse arguments
  args <- parse_args()

  # Load data
  cat(sprintf("[LOADING] %s %s data from processed Feather file...\n\n", args$state, args$year_range))

  data <- load_acs_feather(
    state = args$state,
    year_range = args$year_range,
    base_dir = "data/acs",
    source_file = "processed",  # Use validated processed file
    add_metadata = FALSE,       # Don't need metadata columns
    validate = FALSE            # Will do comprehensive validation below
  )

  # Run comprehensive validation
  checks <- run_comprehensive_validation(
    data = data,
    state = args$state,
    state_fip = args$state_fip,
    year_range = args$year_range
  )

  # Print report
  print_validation_report(checks)

  # Exit with appropriate code
  if (checks$overall_passed) {
    quit(status = 0)
  } else {
    quit(status = 1)
  }
}


# Run if executed as script
if (!interactive()) {
  main()
}
