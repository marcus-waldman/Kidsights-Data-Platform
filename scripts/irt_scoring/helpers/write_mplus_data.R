# =============================================================================
# Mplus Data File Writing Functions
# =============================================================================
# Purpose: Write datasets to Mplus .dat format
#          Free format, whitespace delimited, missing as "."
#
# Usage: Called by prepare_mplus_calibration.R or standalone
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

#' Write Mplus .dat File
#'
#' Main function to write data frame to Mplus-compatible .dat file
#' Free format (whitespace delimited), NA converted to ".", no headers
#'
#' @param data Data frame to write
#' @param output_path Path for output .dat file
#' @param identifier_cols Character vector of identifier column names to exclude
#' @param validate_before_write Logical, validate data before writing (default TRUE)
#' @return Path to written file (invisibly)
#' @export
write_dat_file <- function(data,
                           output_path,
                           identifier_cols = c("study_id", "pid", "record_id"),
                           validate_before_write = TRUE) {

  cat("\n", strrep("=", 70), "\n")
  cat("WRITING MPLUS .DAT FILE\n")
  cat(strrep("=", 70), "\n\n")

  cat(sprintf("Output file: %s\n", output_path))
  cat(sprintf("Records: %d\n", nrow(data)))
  cat(sprintf("Columns: %d\n\n", ncol(data)))

  # ---------------------------------------------------------------------------
  # Step 1: Validate data (optional)
  # ---------------------------------------------------------------------------

  if (validate_before_write) {
    cat(strrep("-", 70), "\n")
    cat("STEP 1: VALIDATE DATA\n")
    cat(strrep("-", 70), "\n\n")

    validation_result <- validate_mplus_data(data, identifier_cols)

    if (!validation_result$valid) {
      cat("\n[ERROR] Validation failed. Fix issues before writing.\n\n")
      return(invisible(NULL))
    }

    cat("[OK] Validation passed\n\n")
  }

  # ---------------------------------------------------------------------------
  # Step 2: Exclude identifier columns
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 2: PREPARE DATA FOR MPLUS\n")
  cat(strrep("-", 70), "\n\n")

  # Get columns to write (exclude identifiers)
  all_cols <- names(data)
  item_cols <- setdiff(all_cols, identifier_cols)

  cat(sprintf("Excluding %d identifier columns: %s\n",
              length(identifier_cols), paste(identifier_cols, collapse = ", ")))
  cat(sprintf("Writing %d item columns\n\n", length(item_cols)))

  data_to_write <- data[, item_cols, drop = FALSE]

  # ---------------------------------------------------------------------------
  # Step 3: Format missing values
  # ---------------------------------------------------------------------------

  cat("Formatting missing values (NA -> '.')...\n")
  data_formatted <- format_missing_values(data_to_write)

  missing_count <- sum(data_formatted == ".", na.rm = TRUE)
  total_cells <- nrow(data_formatted) * ncol(data_formatted)
  missing_pct <- 100 * missing_count / total_cells

  cat(sprintf("  Missing values: %d (%.1f%% of cells)\n\n", missing_count, missing_pct))

  # ---------------------------------------------------------------------------
  # Step 4: Write .dat file
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 3: WRITE .DAT FILE\n")
  cat(strrep("-", 70), "\n\n")

  cat("Writing data...\n")

  # Create output directory if needed
  output_dir <- dirname(output_path)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # Write data (no row names, no column names, space delimited)
  utils::write.table(
    data_formatted,
    file = output_path,
    row.names = FALSE,
    col.names = FALSE,
    quote = FALSE,
    sep = " ",
    na = "."  # Backup: any remaining NAs become "."
  )

  file_size <- file.info(output_path)$size
  file_size_mb <- file_size / (1024 * 1024)

  cat(sprintf("[OK] File written: %s\n", output_path))
  cat(sprintf("     Size: %.2f MB\n\n", file_size_mb))

  # ---------------------------------------------------------------------------
  # Step 5: Create variable names file
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 4: CREATE VARIABLE NAMES FILE\n")
  cat(strrep("-", 70), "\n\n")

  varnames_path <- sub("\\.dat$", "_varnames.txt", output_path)
  write_variable_names_file(item_cols, varnames_path)

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  cat(strrep("=", 70), "\n")
  cat("FILE WRITING COMPLETE\n")
  cat(strrep("=", 70), "\n\n")

  cat("Files created:\n")
  cat(sprintf("  Data file: %s (%d rows, %d cols)\n", output_path, nrow(data_formatted), ncol(data_formatted)))
  cat(sprintf("  Variable names: %s (%d variables)\n", varnames_path, length(item_cols)))
  cat("\n")

  cat("Next steps:\n")
  cat("  1. Copy variable names into Mplus syntax (NAMES section)\n")
  cat("  2. Update DATA: FILE = statement with .dat file path\n")
  cat("  3. Verify variable order matches item order in .dat file\n")
  cat("\n")

  invisible(output_path)
}

#' Format Missing Values
#'
#' Convert NA values to "." for Mplus
#' All columns converted to character to allow "." placeholder
#'
#' @param data Data frame with numeric items
#' @return Data frame with character columns, NAs replaced with "."
#' @export
format_missing_values <- function(data) {

  # Convert all columns to character
  data_char <- as.data.frame(lapply(data, as.character), stringsAsFactors = FALSE)

  # Replace NA with "."
  data_char[is.na(data_char)] <- "."

  return(data_char)
}

#' Create Variable Name List
#'
#' Generate variable names for Mplus NAMES command
#' Returns both space-delimited (for syntax) and one-per-line (for reference)
#'
#' @param variable_names Character vector of variable names
#' @return List with space_delimited and line_delimited versions
#' @export
create_variable_name_list <- function(variable_names) {

  space_delimited <- paste(variable_names, collapse = " ")
  line_delimited <- paste(variable_names, collapse = "\n")

  return(list(
    space_delimited = space_delimited,
    line_delimited = line_delimited,
    n_variables = length(variable_names)
  ))
}

#' Write Variable Names File
#'
#' Write variable names to text file for reference
#' One variable per line for easy copy-paste into Mplus
#'
#' @param variable_names Character vector of variable names
#' @param output_path Path for output text file
#' @return Path to written file (invisibly)
#' @export
write_variable_names_file <- function(variable_names, output_path) {

  varnames_list <- create_variable_name_list(variable_names)

  cat("Writing variable names file...\n")

  # Write header
  output_text <- c(
    strrep("=", 70),
    "MPLUS VARIABLE NAMES",
    strrep("=", 70),
    sprintf("Generated: %s", Sys.time()),
    sprintf("Number of variables: %d", varnames_list$n_variables),
    "",
    strrep("-", 70),
    "NAMES (one per line):",
    strrep("-", 70),
    "",
    varnames_list$line_delimited,
    "",
    strrep("-", 70),
    "NAMES (space-delimited for Mplus syntax):",
    strrep("-", 70),
    "",
    varnames_list$space_delimited,
    ""
  )

  writeLines(output_text, output_path)

  cat(sprintf("[OK] Variable names file: %s\n", output_path))
  cat(sprintf("     Variables: %d\n", varnames_list$n_variables))

  invisible(output_path)
}

#' Validate Mplus Data
#'
#' Check for issues before writing .dat file
#' Catches common problems that cause Mplus errors
#'
#' @param data Data frame to validate
#' @param identifier_cols Identifier columns to exclude from checks
#' @return List with valid (logical) and issues (character vector)
#' @export
validate_mplus_data <- function(data, identifier_cols = c("study_id", "pid", "record_id")) {

  issues <- character(0)

  # Get item columns (exclude identifiers)
  item_cols <- setdiff(names(data), identifier_cols)
  item_data <- data[, item_cols, drop = FALSE]

  # ---------------------------------------------------------------------------
  # Check 1: No empty columns
  # ---------------------------------------------------------------------------

  empty_cols <- names(item_data)[colSums(!is.na(item_data)) == 0]
  if (length(empty_cols) > 0) {
    issues <- c(issues, sprintf("Empty columns (all NA): %s", paste(empty_cols, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Check 2: No zero-variance columns
  # ---------------------------------------------------------------------------

  zero_var_cols <- character(0)
  for (col in names(item_data)) {
    if (is.numeric(item_data[[col]])) {
      col_var <- stats::var(item_data[[col]], na.rm = TRUE)
      if (!is.na(col_var) && col_var == 0) {
        zero_var_cols <- c(zero_var_cols, col)
      }
    }
  }

  if (length(zero_var_cols) > 0) {
    issues <- c(issues, sprintf("Zero variance columns: %s", paste(zero_var_cols, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Check 3: Variable names valid for Mplus
  # ---------------------------------------------------------------------------

  # Mplus variable names: max 8 characters, alphanumeric + underscore
  invalid_names <- character(0)

  for (varname in names(item_data)) {
    # Check length
    if (nchar(varname) > 8) {
      invalid_names <- c(invalid_names, sprintf("%s (length %d > 8)", varname, nchar(varname)))
    }

    # Check characters (alphanumeric + underscore only)
    if (!grepl("^[A-Za-z0-9_]+$", varname)) {
      invalid_names <- c(invalid_names, sprintf("%s (invalid characters)", varname))
    }
  }

  if (length(invalid_names) > 0) {
    issues <- c(issues, sprintf("Invalid Mplus variable names: %s", paste(invalid_names, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Check 4: Reasonable missing data levels
  # ---------------------------------------------------------------------------

  high_missing_cols <- character(0)
  for (col in names(item_data)) {
    missing_pct <- 100 * sum(is.na(item_data[[col]])) / nrow(item_data)
    if (missing_pct > 50) {
      high_missing_cols <- c(high_missing_cols, sprintf("%s (%.1f%% missing)", col, missing_pct))
    }
  }

  if (length(high_missing_cols) > 0) {
    issues <- c(issues, sprintf("[WARN] High missingness (>50%%): %s", paste(high_missing_cols, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Check 5: No duplicate variable names
  # ---------------------------------------------------------------------------

  duplicate_names <- item_cols[duplicated(item_cols)]
  if (length(duplicate_names) > 0) {
    issues <- c(issues, sprintf("Duplicate variable names: %s", paste(duplicate_names, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Report results
  # ---------------------------------------------------------------------------

  valid <- length(issues) == 0

  if (valid) {
    cat("[OK] Data validation passed\n")
    cat(sprintf("  %d variables checked\n", length(item_cols)))
    cat(sprintf("  %d records checked\n", nrow(data)))
  } else {
    cat(sprintf("[ERROR] Data validation failed (%d issues):\n", length(issues)))
    for (i in seq_along(issues)) {
      cat(sprintf("  %d. %s\n", i, issues[i]))
    }
  }

  return(list(
    valid = valid,
    issues = issues,
    n_issues = length(issues)
  ))
}

#' Generate Mplus Syntax Template
#'
#' Create basic Mplus syntax template for calibration
#' User must fill in model specifications
#'
#' @param variable_names Character vector of variable names
#' @param dat_file_path Path to .dat file
#' @param scale_name Scale name for title
#' @return Character vector with Mplus syntax lines
#' @export
generate_mplus_syntax_template <- function(variable_names, dat_file_path, scale_name) {

  varnames_list <- create_variable_name_list(variable_names)

  syntax <- c(
    "TITLE:",
    sprintf("  %s IRT Calibration", scale_name),
    "",
    "DATA:",
    sprintf("  FILE = \"%s\";", dat_file_path),
    "",
    "VARIABLE:",
    sprintf("  NAMES = %s;", varnames_list$space_delimited),
    sprintf("  USEVARIABLES = %s;", varnames_list$space_delimited),
    "  MISSING = .;",
    sprintf("  ! Number of variables: %d", varnames_list$n_variables),
    "",
    "ANALYSIS:",
    "  ESTIMATOR = WLSMV;  ! Weighted least squares for ordinal items",
    "  PARAMETERIZATION = THETA;  ! IRT parameterization",
    "",
    "MODEL:",
    "  ! Specify your IRT model here",
    "  ! Example unidimensional:",
    "  !   F BY item1* item2 item3 ...;",
    "  !   F@1;  ! Fix factor variance",
    "  ",
    "  ! Example bifactor:",
    "  !   GEN BY item1-item44*;",
    "  !   EAT BY item1-item8;",
    "  !   ... (other specific factors)",
    "  !   GEN@1; EAT@1; ... (fix variances)",
    "",
    "OUTPUT:",
    "  STANDARDIZED;  ! Standardized loadings",
    "  RESIDUAL;      ! Residual correlations",
    "  MODINDICES;    ! Modification indices",
    ""
  )

  return(syntax)
}

#' Write Mplus Syntax Template File
#'
#' Write Mplus syntax template to .inp file
#'
#' @param variable_names Character vector of variable names
#' @param dat_file_path Path to .dat file
#' @param scale_name Scale name for title
#' @param output_path Path for output .inp file
#' @return Path to written file (invisibly)
#' @export
write_mplus_syntax_template <- function(variable_names, dat_file_path, scale_name, output_path) {

  cat("\n", strrep("-", 70), "\n")
  cat("GENERATING MPLUS SYNTAX TEMPLATE\n")
  cat(strrep("-", 70), "\n\n")

  syntax <- generate_mplus_syntax_template(variable_names, dat_file_path, scale_name)

  writeLines(syntax, output_path)

  cat(sprintf("[OK] Mplus syntax template: %s\n", output_path))
  cat(sprintf("     Lines: %d\n", length(syntax)))
  cat("\n")
  cat("Note: This is a TEMPLATE. You must:\n")
  cat("  1. Specify the MODEL section with your factor structure\n")
  cat("  2. Review ANALYSIS options (estimator, parameterization)\n")
  cat("  3. Add any additional specifications (constraints, etc.)\n")
  cat("\n")

  invisible(output_path)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Assume you have calibration data from mplus_dataset_prep.R
# kidsights_data <- extract_items_for_calibration(...)
#
# # Write .dat file
# write_dat_file(
#   data = kidsights_data,
#   output_path = "mplus/kidsights_calibration.dat",
#   identifier_cols = c("study_id", "pid", "record_id")
# )
#
# # Write Mplus syntax template
# write_mplus_syntax_template(
#   variable_names = setdiff(names(kidsights_data), c("study_id", "pid", "record_id")),
#   dat_file_path = "kidsights_calibration.dat",
#   scale_name = "Kidsights",
#   output_path = "mplus/kidsights_calibration.inp"
# )
