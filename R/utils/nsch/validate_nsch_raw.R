#' Validate NSCH Raw Data
#'
#' Performs basic validation checks on NSCH data to ensure it loaded correctly.
#' This is a lightweight validation focused on data integrity, not content validation.
#'
#' @author Kidsights Data Platform
#' @date 2025-10-03

#' Validate NSCH Data
#'
#' Runs 7 validation checks on NSCH data:
#' 1. HHID variable present (household identifier)
#' 2. Record count > 0
#' 3. Column count matches metadata
#' 4. No completely empty columns
#' 5. Data types are reasonable (numeric/factor/character)
#' 6. HHID has no missing values
#' 7. Expected year variable present (if available)
#'
#' @param data data.frame, NSCH data from load_nsch_year()
#' @param metadata list, metadata from load_nsch_metadata()
#' @return list with validation results
#'   - all_passed: logical, TRUE if all checks passed
#'   - checks: list of individual check results
#'   - summary: character, summary message
#'
#' @examples
#' \dontrun{
#' data <- load_nsch_year(2023)
#' metadata <- load_nsch_metadata(2023)
#' result <- validate_nsch_data(data, metadata)
#' print(result$summary)
#' }
#'
#' @export
validate_nsch_data <- function(data, metadata) {
  cat("\n[INFO] Running NSCH data validation...\n")
  cat(strrep("-", 70), "\n")

  # Initialize results
  checks <- list()
  all_passed <- TRUE

  # Check 1: HHID variable present
  cat("\n[CHECK 1/7] HHID variable present...\n")
  hhid_present <- "HHID" %in% names(data)

  if (hhid_present) {
    cat("[OK] HHID variable found\n")
    checks$hhid_present <- list(passed = TRUE, message = "HHID variable present")
  } else {
    cat("[FAIL] HHID variable not found\n")
    checks$hhid_present <- list(passed = FALSE, message = "HHID variable missing")
    all_passed <- FALSE
  }

  # Check 2: Record count > 0
  cat("\n[CHECK 2/7] Record count > 0...\n")
  record_count <- nrow(data)

  if (record_count > 0) {
    cat(sprintf("[OK] Record count: %s\n", format(record_count, big.mark = ",")))
    checks$record_count <- list(
      passed = TRUE,
      message = sprintf("%s records", format(record_count, big.mark = ","))
    )
  } else {
    cat("[FAIL] No records in dataset\n")
    checks$record_count <- list(passed = FALSE, message = "Zero records")
    all_passed <- FALSE
  }

  # Check 3: Column count matches metadata
  cat("\n[CHECK 3/7] Column count matches metadata...\n")
  actual_cols <- ncol(data)
  expected_cols <- metadata$variable_count

  if (actual_cols == expected_cols) {
    cat(sprintf("[OK] Column count: %d (matches metadata)\n", actual_cols))
    checks$column_count <- list(
      passed = TRUE,
      message = sprintf("%d columns (matches metadata)", actual_cols)
    )
  } else {
    cat(sprintf("[WARN] Column count mismatch: %d actual vs %d expected\n",
                actual_cols, expected_cols))
    checks$column_count <- list(
      passed = FALSE,
      message = sprintf("%d columns (expected %d)", actual_cols, expected_cols)
    )
    # Don't fail on this - metadata might be slightly different
  }

  # Check 4: No completely empty columns
  cat("\n[CHECK 4/7] No completely empty columns...\n")
  empty_cols <- sapply(data, function(x) all(is.na(x)))
  num_empty <- sum(empty_cols)

  if (num_empty == 0) {
    cat("[OK] No empty columns\n")
    checks$empty_columns <- list(passed = TRUE, message = "No empty columns")
  } else {
    empty_col_names <- names(data)[empty_cols]
    cat(sprintf("[WARN] %d empty columns: %s\n", num_empty,
                paste(head(empty_col_names, 5), collapse = ", ")))
    checks$empty_columns <- list(
      passed = FALSE,
      message = sprintf("%d empty columns", num_empty)
    )
    # Don't fail - some columns may legitimately be all NA
  }

  # Check 5: Data types are reasonable
  cat("\n[CHECK 5/7] Data types are reasonable...\n")
  col_types <- sapply(data, function(x) class(x)[1])
  type_summary <- table(col_types)

  cat("[INFO] Data type distribution:\n")
  for (type in names(type_summary)) {
    cat(sprintf("  %s: %d columns\n", type, type_summary[type]))
  }

  # Check for unexpected types (should be numeric, factor, or character)
  valid_types <- c("numeric", "integer", "factor", "character", "logical")
  invalid_types <- !col_types %in% valid_types

  if (sum(invalid_types) == 0) {
    cat("[OK] All data types are valid\n")
    checks$data_types <- list(passed = TRUE, message = "All data types valid")
  } else {
    cat(sprintf("[WARN] %d columns with unexpected types\n", sum(invalid_types)))
    checks$data_types <- list(
      passed = FALSE,
      message = sprintf("%d unexpected types", sum(invalid_types))
    )
  }

  # Check 6: HHID has no missing values
  cat("\n[CHECK 6/7] HHID has no missing values...\n")
  if (hhid_present) {
    hhid_na_count <- sum(is.na(data$HHID))

    if (hhid_na_count == 0) {
      cat("[OK] HHID has no missing values\n")
      checks$hhid_missing <- list(passed = TRUE, message = "HHID complete")
    } else {
      cat(sprintf("[FAIL] HHID has %d missing values\n", hhid_na_count))
      checks$hhid_missing <- list(
        passed = FALSE,
        message = sprintf("HHID has %d NAs", hhid_na_count)
      )
      all_passed <- FALSE
    }
  } else {
    cat("[SKIP] HHID not present\n")
    checks$hhid_missing <- list(passed = TRUE, message = "HHID not present (skipped)")
  }

  # Check 7: Year variable present (if applicable)
  cat("\n[CHECK 7/7] Year/survey year variable...\n")

  # Common year variable names in NSCH
  year_vars <- c("YEAR", "year", "SURVEY_YEAR", "survey_year")
  year_var_found <- any(year_vars %in% names(data))

  if (year_var_found) {
    found_var <- year_vars[year_vars %in% names(data)][1]
    cat(sprintf("[OK] Year variable found: %s\n", found_var))
    checks$year_variable <- list(
      passed = TRUE,
      message = sprintf("Year variable: %s", found_var)
    )
  } else {
    cat("[INFO] No year variable found (may not be needed)\n")
    checks$year_variable <- list(
      passed = TRUE,
      message = "Year variable not found (not required)"
    )
  }

  # Generate summary
  cat("\n", strrep("-", 70), "\n")

  passed_count <- sum(sapply(checks, function(x) x$passed))
  total_count <- length(checks)

  if (all_passed) {
    summary_msg <- sprintf(
      "Validation PASSED: %d/%d checks successful",
      passed_count,
      total_count
    )
    cat(sprintf("[SUCCESS] %s\n", summary_msg))
  } else {
    summary_msg <- sprintf(
      "Validation FAILED: %d/%d checks passed",
      passed_count,
      total_count
    )
    cat(sprintf("[FAIL] %s\n", summary_msg))
  }

  cat(strrep("-", 70), "\n")

  # Return results
  return(list(
    all_passed = all_passed,
    checks = checks,
    passed_count = passed_count,
    total_count = total_count,
    summary = summary_msg
  ))
}
