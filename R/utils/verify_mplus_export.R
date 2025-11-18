#' Verify Mplus Export File Format
#'
#' Validates that exported .dat file meets Mplus format requirements.
#' Checks for numeric types, missing value encoding, and file structure.
#'
#' @param dat_file Path to .dat file to validate
#' @param expected_n Expected number of records (optional)
#' @param expected_vars Expected number of variables (optional)
#' @param verbose Logical. Print detailed output? Default: TRUE
#' @param stop_on_error Logical. Stop execution if validation fails? Default: TRUE
#'
#' @return List with validation results:
#'   - passed: Logical, TRUE if all checks passed
#'   - errors: Character vector of error messages
#'   - warnings: Character vector of warning messages
#'   - file_info: List with file size, record count, variable count
#'
#' @details
#' This function checks:
#' 1. File exists and is readable
#' 2. File size is reasonable (> 1 MB for calibration dataset)
#' 3. Record count matches expected (if provided)
#' 4. All values are numeric or missing value placeholder (.)
#' 5. No invalid characters in file
#' 6. Column count is consistent across rows
#'
#' Mplus format requirements:
#' - Space-delimited numeric values
#' - Missing values coded as "."
#' - No header row
#' - Consistent number of columns per row
#'
#' @examples
#' \dontrun{
#' # Verify calibration dataset export
#' verification <- verify_mplus_export(
#'   dat_file = "mplus/calibdat.dat",
#'   expected_n = 47084,
#'   expected_vars = 419,
#'   verbose = TRUE
#' )
#'
#' if (!verification$passed) {
#'   cat("Errors:\n")
#'   print(verification$errors)
#' }
#' }
#'
#' @export
verify_mplus_export <- function(dat_file,
                                 expected_n = NULL,
                                 expected_vars = NULL,
                                 verbose = TRUE,
                                 stop_on_error = TRUE) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("VERIFYING MPLUS EXPORT FORMAT\n")
    cat(strrep("=", 80), "\n\n")
  }

  errors <- character()
  warnings <- character()
  file_info <- list()

  # Check 1: File exists
  if (!file.exists(dat_file)) {
    msg <- sprintf("File not found: %s", dat_file)
    errors <- c(errors, msg)
    if (verbose) cat(sprintf("[ERROR] %s\n\n", msg))

    result <- list(
      passed = FALSE,
      errors = errors,
      warnings = warnings,
      file_info = file_info
    )

    if (stop_on_error) {
      stop("Mplus export file not found: ", dat_file)
    }

    return(invisible(result))
  }

  if (verbose) cat(sprintf("[INFO] File: %s\n", dat_file))

  # Check 2: File size
  file_size_bytes <- file.info(dat_file)$size
  file_size_mb <- file_size_bytes / (1024^2)

  file_info$file_size_bytes <- file_size_bytes
  file_info$file_size_mb <- file_size_mb

  if (verbose) {
    cat(sprintf("[INFO] File size: %.2f MB (%s bytes)\n\n",
                file_size_mb, format(file_size_bytes, big.mark = ",")))
  }

  if (file_size_mb < 1) {
    msg <- sprintf("File size too small: %.2f MB (expected > 1 MB for calibration dataset)", file_size_mb)
    warnings <- c(warnings, msg)
    if (verbose) cat(sprintf("[WARNING] %s\n\n", msg))
  }

  # Check 3: Read first 10 lines to validate format
  if (verbose) cat("[INFO] Reading sample lines to validate format...\n")

  sample_lines <- readLines(dat_file, n = 10)

  # Check for valid numeric format
  for (i in seq_along(sample_lines)) {
    line <- sample_lines[i]

    # Split by whitespace
    values <- strsplit(line, "\\s+")[[1]]
    values <- values[values != ""]  # Remove empty strings

    # Check each value is numeric or "."
    for (val in values) {
      if (val != "." && !grepl("^-?[0-9]+(\\.[0-9]+)?$", val)) {
        msg <- sprintf("Invalid value in line %d: '%s' (not numeric or '.')", i, val)
        errors <- c(errors, msg)
        if (verbose) cat(sprintf("[ERROR] %s\n", msg))
      }
    }
  }

  if (verbose && length(errors) == 0) {
    cat("[OK] Sample lines contain only valid numeric values and '.'\n\n")
  }

  # Check 4: Count total lines (records)
  if (verbose) cat("[INFO] Counting total records...\n")

  # For large files, use system command for speed
  if (.Platform$OS.type == "windows") {
    n_lines <- length(readLines(dat_file))
  } else {
    n_lines <- as.integer(system(sprintf("wc -l < '%s'", dat_file), intern = TRUE))
  }

  file_info$n_records <- n_lines

  if (verbose) {
    cat(sprintf("[INFO] Total records: %s\n\n", format(n_lines, big.mark = ",")))
  }

  # Check 5: Verify expected record count
  if (!is.null(expected_n)) {
    if (n_lines != expected_n) {
      msg <- sprintf("Record count mismatch: found %d, expected %d (diff: %+d)",
                     n_lines, expected_n, n_lines - expected_n)
      errors <- c(errors, msg)
      if (verbose) cat(sprintf("[ERROR] %s\n\n", msg))
    } else {
      if (verbose) cat("[OK] Record count matches expected\n\n")
    }
  }

  # Check 6: Count variables (columns) from first line
  first_line <- readLines(dat_file, n = 1)
  vars <- strsplit(first_line, "\\s+")[[1]]
  vars <- vars[vars != ""]  # Remove empty strings

  n_vars <- length(vars)
  file_info$n_vars <- n_vars

  if (verbose) {
    cat(sprintf("[INFO] Variables per record: %d\n\n", n_vars))
  }

  # Check 7: Verify expected variable count
  if (!is.null(expected_vars)) {
    if (n_vars != expected_vars) {
      msg <- sprintf("Variable count mismatch: found %d, expected %d (diff: %+d)",
                     n_vars, expected_vars, n_vars - expected_vars)
      errors <- c(errors, msg)
      if (verbose) cat(sprintf("[ERROR] %s\n\n", msg))
    } else {
      if (verbose) cat("[OK] Variable count matches expected\n\n")
    }
  }

  # Check 8: Verify consistent column count (sample 100 lines)
  if (verbose) cat("[INFO] Checking column count consistency (sample 100 lines)...\n")

  if (n_lines > 100) {
    # Sample lines throughout file
    sample_idx <- seq(1, n_lines, length.out = 100)
    sample_idx <- round(sample_idx)
  } else {
    sample_idx <- 1:n_lines
  }

  all_lines <- readLines(dat_file)
  sampled_lines <- all_lines[sample_idx]

  column_counts <- sapply(sampled_lines, function(line) {
    vals <- strsplit(line, "\\s+")[[1]]
    length(vals[vals != ""])
  })

  if (length(unique(column_counts)) > 1) {
    msg <- sprintf("Inconsistent column counts across rows: %s",
                   paste(unique(column_counts), collapse = ", "))
    errors <- c(errors, msg)
    if (verbose) cat(sprintf("[ERROR] %s\n\n", msg))
  } else {
    if (verbose) cat("[OK] Column count consistent across rows\n\n")
  }

  # Summary
  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("VALIDATION SUMMARY\n")
    cat(strrep("=", 80), "\n\n")

    cat(sprintf("  File: %s\n", basename(dat_file)))
    cat(sprintf("  Size: %.2f MB\n", file_size_mb))
    cat(sprintf("  Records: %s\n", format(n_lines, big.mark = ",")))
    cat(sprintf("  Variables: %d\n\n", n_vars))

    cat(sprintf("  Errors: %d\n", length(errors)))
    cat(sprintf("  Warnings: %d\n\n", length(warnings)))
  }

  # Determine pass/fail
  passed <- length(errors) == 0

  if (!passed && verbose) {
    cat("[VALIDATION FAILED]\n")
    cat("The Mplus export file has format errors that must be corrected.\n\n")
  } else if (passed && verbose) {
    cat("[OK] Mplus export file passed all validation checks\n\n")
  }

  if (verbose) {
    cat(strrep("=", 80), "\n\n")
  }

  # Create result object
  result <- list(
    passed = passed,
    errors = errors,
    warnings = warnings,
    file_info = file_info
  )

  # Stop execution if errors and stop_on_error = TRUE
  if (!passed && stop_on_error) {
    stop(sprintf("Mplus export validation failed: %d errors detected. ",
                 length(errors)),
         "Fix errors before proceeding with Mplus calibration.")
  }

  return(invisible(result))
}
