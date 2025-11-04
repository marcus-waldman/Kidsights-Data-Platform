# =============================================================================
# Mplus Template Modification Functions
# =============================================================================
# Purpose: Read, parse, and update existing Mplus syntax templates
#          Reconcile variable names and file paths for new datasets
#
# Usage: Called by prepare_mplus_calibration.R or standalone
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

#' Read Mplus Template
#'
#' Read existing Mplus .inp file and parse structure
#' Returns list with sections and line numbers for modification
#'
#' @param template_path Path to existing .inp file
#' @return List with syntax_lines, data_section, variable_section, etc.
#' @export
read_mplus_template <- function(template_path) {

  cat("\n", strrep("=", 70), "\n")
  cat("READING MPLUS TEMPLATE\n")
  cat(strrep("=", 70), "\n\n")

  if (!file.exists(template_path)) {
    stop(sprintf("Template file not found: %s", template_path))
  }

  syntax_lines <- readLines(template_path, warn = FALSE)
  cat(sprintf("[OK] Read template: %s\n", template_path))
  cat(sprintf("     Lines: %d\n\n", length(syntax_lines)))

  # Parse sections
  sections <- parse_mplus_sections(syntax_lines)

  result <- list(
    template_path = template_path,
    syntax_lines = syntax_lines,
    sections = sections
  )

  # Display detected sections
  cat("Detected sections:\n")
  for (section_name in names(sections)) {
    section_info <- sections[[section_name]]
    if (!is.null(section_info$start)) {
      cat(sprintf("  %s: lines %d-%d\n", section_name, section_info$start, section_info$end))
    }
  }
  cat("\n")

  return(result)
}

#' Parse Mplus Sections
#'
#' Identify major sections in Mplus syntax (TITLE, DATA, VARIABLE, MODEL, etc.)
#' Case-insensitive, handles variations in spacing
#'
#' @param syntax_lines Character vector of syntax lines
#' @return List with section information (start/end line numbers)
#' @export
parse_mplus_sections <- function(syntax_lines) {

  sections <- list(
    TITLE = list(start = NULL, end = NULL),
    DATA = list(start = NULL, end = NULL),
    VARIABLE = list(start = NULL, end = NULL),
    ANALYSIS = list(start = NULL, end = NULL),
    MODEL = list(start = NULL, end = NULL),
    OUTPUT = list(start = NULL, end = NULL)
  )

  section_names <- names(sections)
  current_section <- NULL

  for (i in seq_along(syntax_lines)) {
    line <- trimws(syntax_lines[i])

    # Check if line starts a new section
    for (section_name in section_names) {
      pattern <- sprintf("^%s\\s*:", section_name)
      if (grepl(pattern, line, ignore.case = TRUE)) {
        # End previous section
        if (!is.null(current_section)) {
          sections[[current_section]]$end <- i - 1
        }

        # Start new section
        sections[[section_name]]$start <- i
        current_section <- section_name
        break
      }
    }
  }

  # End final section
  if (!is.null(current_section)) {
    sections[[current_section]]$end <- length(syntax_lines)
  }

  return(sections)
}

#' Parse Variable Names from Template
#'
#' Extract variable names from NAMES section of Mplus syntax
#' Handles multi-line continuations and various spacing
#'
#' @param template_obj Template object from read_mplus_template()
#' @return Character vector of variable names
#' @export
parse_variable_names <- function(template_obj) {

  cat(strrep("-", 70), "\n")
  cat("PARSING VARIABLE NAMES FROM TEMPLATE\n")
  cat(strrep("-", 70), "\n\n")

  syntax_lines <- template_obj$syntax_lines
  variable_section <- template_obj$sections$VARIABLE

  if (is.null(variable_section$start)) {
    cat("[WARN] No VARIABLE section found in template\n\n")
    return(character(0))
  }

  # Extract VARIABLE section lines
  var_lines <- syntax_lines[variable_section$start:variable_section$end]

  # Find NAMES statement
  names_start <- NULL
  names_end <- NULL

  for (i in seq_along(var_lines)) {
    line <- var_lines[i]

    # Start of NAMES
    if (grepl("^\\s*NAMES\\s*=", line, ignore.case = TRUE)) {
      names_start <- i
    }

    # End of NAMES (semicolon)
    if (!is.null(names_start) && is.null(names_end) && grepl(";", line)) {
      names_end <- i
      break
    }
  }

  if (is.null(names_start) || is.null(names_end)) {
    cat("[WARN] NAMES statement not found in VARIABLE section\n\n")
    return(character(0))
  }

  # Extract NAMES text
  names_lines <- var_lines[names_start:names_end]
  names_text <- paste(names_lines, collapse = " ")

  # Remove "NAMES =" and ";" and comments
  names_text <- gsub("NAMES\\s*=", "", names_text, ignore.case = TRUE)
  names_text <- gsub(";", "", names_text)
  names_text <- gsub("!.*$", "", names_text)  # Remove comments

  # Split by whitespace
  varnames <- unlist(strsplit(trimws(names_text), "\\s+"))
  varnames <- varnames[nchar(varnames) > 0]  # Remove empty strings

  cat(sprintf("[OK] Parsed %d variable names from template\n", length(varnames)))
  cat(sprintf("     First 5: %s\n", paste(head(varnames, 5), collapse = ", ")))
  cat(sprintf("     Last 5: %s\n\n", paste(tail(varnames, 5), collapse = ", ")))

  return(varnames)
}

#' Parse USEVARIABLES from Template
#'
#' Extract variable names from USEVARIABLES section
#' May differ from NAMES if only subset of variables used
#'
#' @param template_obj Template object from read_mplus_template()
#' @return Character vector of usevariables
#' @export
parse_usevariables <- function(template_obj) {

  syntax_lines <- template_obj$syntax_lines
  variable_section <- template_obj$sections$VARIABLE

  if (is.null(variable_section$start)) {
    return(character(0))
  }

  var_lines <- syntax_lines[variable_section$start:variable_section$end]

  # Find USEVARIABLES statement
  use_start <- NULL
  use_end <- NULL

  for (i in seq_along(var_lines)) {
    line <- var_lines[i]

    if (grepl("^\\s*USEVARIABLES\\s*=", line, ignore.case = TRUE)) {
      use_start <- i
    }

    if (!is.null(use_start) && is.null(use_end) && grepl(";", line)) {
      use_end <- i
      break
    }
  }

  if (is.null(use_start) || is.null(use_end)) {
    return(character(0))
  }

  # Extract USEVARIABLES text
  use_lines <- var_lines[use_start:use_end]
  use_text <- paste(use_lines, collapse = " ")

  use_text <- gsub("USEVARIABLES\\s*=", "", use_text, ignore.case = TRUE)
  use_text <- gsub(";", "", use_text)
  use_text <- gsub("!.*$", "", use_text)

  use_vars <- unlist(strsplit(trimws(use_text), "\\s+"))
  use_vars <- use_vars[nchar(use_vars) > 0]

  return(use_vars)
}

#' Detect Naming Mismatches
#'
#' Compare template variable names to data column names
#' Reports differences in: case, order, missing vars, extra vars
#'
#' @param template_varnames Character vector of variable names from template
#' @param data_varnames Character vector of variable names from data
#' @return List with mismatch information and reconciliation suggestions
#' @export
detect_naming_mismatches <- function(template_varnames, data_varnames) {

  cat("\n", strrep("=", 70), "\n")
  cat("DETECTING NAMING MISMATCHES\n")
  cat(strrep("=", 70), "\n\n")

  cat(sprintf("Template variables: %d\n", length(template_varnames)))
  cat(sprintf("Data variables: %d\n\n", length(data_varnames)))

  mismatches <- list(
    case_differences = character(0),
    order_differences = FALSE,
    missing_in_data = character(0),
    extra_in_data = character(0),
    needs_update = FALSE
  )

  # ---------------------------------------------------------------------------
  # Check 1: Case differences
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("CHECK 1: CASE DIFFERENCES\n")
  cat(strrep("-", 70), "\n\n")

  # Case-insensitive comparison
  template_lower <- tolower(template_varnames)
  data_lower <- tolower(data_varnames)

  for (i in seq_along(template_varnames)) {
    template_var <- template_varnames[i]
    template_var_lower <- template_lower[i]

    # Find matching data variable
    match_idx <- which(data_lower == template_var_lower)

    if (length(match_idx) > 0) {
      data_var <- data_varnames[match_idx[1]]

      if (template_var != data_var) {
        mismatches$case_differences <- c(
          mismatches$case_differences,
          sprintf("'%s' (template) vs '%s' (data)", template_var, data_var)
        )
      }
    }
  }

  if (length(mismatches$case_differences) > 0) {
    cat(sprintf("[WARN] Found %d case differences:\n", length(mismatches$case_differences)))
    for (diff in head(mismatches$case_differences, 10)) {
      cat(sprintf("  %s\n", diff))
    }
    if (length(mismatches$case_differences) > 10) {
      cat(sprintf("  ... and %d more\n", length(mismatches$case_differences) - 10))
    }
    cat("\n")
    mismatches$needs_update <- TRUE
  } else {
    cat("[OK] No case differences\n\n")
  }

  # ---------------------------------------------------------------------------
  # Check 2: Order differences
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("CHECK 2: ORDER DIFFERENCES\n")
  cat(strrep("-", 70), "\n\n")

  # Compare order (case-insensitive)
  template_sorted <- sort(template_lower)
  data_sorted <- sort(data_lower)

  if (!identical(template_lower, data_lower) && identical(template_sorted, data_sorted)) {
    cat("[WARN] Variable order differs between template and data\n")
    cat("       Variables must be in same order in .dat file and NAMES statement\n\n")
    mismatches$order_differences <- TRUE
    mismatches$needs_update <- TRUE
  } else {
    cat("[OK] Variable order matches (or variables differ entirely)\n\n")
  }

  # ---------------------------------------------------------------------------
  # Check 3: Missing variables
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("CHECK 3: VARIABLES IN TEMPLATE BUT NOT IN DATA\n")
  cat(strrep("-", 70), "\n\n")

  missing_in_data <- template_varnames[!template_lower %in% data_lower]

  if (length(missing_in_data) > 0) {
    cat(sprintf("[WARN] %d variables in template but not in data:\n", length(missing_in_data)))
    for (var in head(missing_in_data, 20)) {
      cat(sprintf("  %s\n", var))
    }
    if (length(missing_in_data) > 20) {
      cat(sprintf("  ... and %d more\n", length(missing_in_data) - 20))
    }
    cat("\n")
    mismatches$missing_in_data <- missing_in_data
    mismatches$needs_update <- TRUE
  } else {
    cat("[OK] All template variables found in data\n\n")
  }

  # ---------------------------------------------------------------------------
  # Check 4: Extra variables
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("CHECK 4: VARIABLES IN DATA BUT NOT IN TEMPLATE\n")
  cat(strrep("-", 70), "\n\n")

  extra_in_data <- data_varnames[!data_lower %in% template_lower]

  if (length(extra_in_data) > 0) {
    cat(sprintf("[INFO] %d variables in data but not in template:\n", length(extra_in_data)))
    for (var in head(extra_in_data, 20)) {
      cat(sprintf("  %s\n", var))
    }
    if (length(extra_in_data) > 20) {
      cat(sprintf("  ... and %d more\n", length(extra_in_data) - 20))
    }
    cat("\n")
    mismatches$extra_in_data <- extra_in_data
    # This is not necessarily a problem - user may want to add new items
  } else {
    cat("[OK] No extra variables in data\n\n")
  }

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  cat(strrep("=", 70), "\n")
  cat("MISMATCH SUMMARY\n")
  cat(strrep("=", 70), "\n\n")

  if (mismatches$needs_update) {
    cat("[ACTION NEEDED] Template requires updates:\n")
    if (length(mismatches$case_differences) > 0) {
      cat(sprintf("  - Update case for %d variables\n", length(mismatches$case_differences)))
    }
    if (mismatches$order_differences) {
      cat("  - Reorder variables to match data\n")
    }
    if (length(mismatches$missing_in_data) > 0) {
      cat(sprintf("  - Remove %d variables not in data\n", length(mismatches$missing_in_data)))
    }
    if (length(mismatches$extra_in_data) > 0) {
      cat(sprintf("  - Consider adding %d new variables from data\n", length(mismatches$extra_in_data)))
    }
  } else {
    cat("[OK] No mismatches detected\n")
  }
  cat("\n")

  return(mismatches)
}

#' Update Data File Path
#'
#' Update FILE = statement in DATA section with new .dat file path
#'
#' @param template_obj Template object from read_mplus_template()
#' @param new_dat_path Path to new .dat file
#' @return Updated syntax lines
#' @export
update_data_file_path <- function(template_obj, new_dat_path) {

  syntax_lines <- template_obj$syntax_lines
  data_section <- template_obj$sections$DATA

  if (is.null(data_section$start)) {
    cat("[WARN] No DATA section found, cannot update file path\n")
    return(syntax_lines)
  }

  # Find FILE = line
  data_lines_idx <- data_section$start:data_section$end

  for (i in data_lines_idx) {
    line <- syntax_lines[i]

    if (grepl("^\\s*FILE\\s*=", line, ignore.case = TRUE)) {
      # Replace with new path
      syntax_lines[i] <- sprintf("  FILE = \"%s\";", new_dat_path)
      cat(sprintf("[OK] Updated FILE path: %s\n", new_dat_path))
      break
    }
  }

  return(syntax_lines)
}

#' Update Variable Names Section
#'
#' Replace NAMES statement with new variable names
#' Maintains formatting and comments
#'
#' @param template_obj Template object from read_mplus_template()
#' @param new_varnames Character vector of new variable names
#' @return Updated syntax lines
#' @export
update_variable_names <- function(template_obj, new_varnames) {

  syntax_lines <- template_obj$syntax_lines
  variable_section <- template_obj$sections$VARIABLE

  if (is.null(variable_section$start)) {
    cat("[WARN] No VARIABLE section found\n")
    return(syntax_lines)
  }

  # Find NAMES statement lines
  var_lines_idx <- variable_section$start:variable_section$end
  names_start_idx <- NULL
  names_end_idx <- NULL

  for (i in var_lines_idx) {
    line <- syntax_lines[i]

    if (grepl("^\\s*NAMES\\s*=", line, ignore.case = TRUE)) {
      names_start_idx <- i
    }

    if (!is.null(names_start_idx) && is.null(names_end_idx) && grepl(";", line)) {
      names_end_idx <- i
      break
    }
  }

  if (is.null(names_start_idx) || is.null(names_end_idx)) {
    cat("[WARN] NAMES statement not found\n")
    return(syntax_lines)
  }

  # Create new NAMES statement
  varnames_text <- paste(new_varnames, collapse = " ")
  new_names_line <- sprintf("  NAMES = %s;", varnames_text)

  # Replace old NAMES lines with new single line
  syntax_lines_before <- syntax_lines[1:(names_start_idx - 1)]
  syntax_lines_after <- syntax_lines[(names_end_idx + 1):length(syntax_lines)]

  updated_lines <- c(syntax_lines_before, new_names_line, syntax_lines_after)

  cat(sprintf("[OK] Updated NAMES statement with %d variables\n", length(new_varnames)))

  return(updated_lines)
}

#' Update USEVARIABLES Section
#'
#' Replace USEVARIABLES statement with new variable names
#' Typically same as NAMES unless subsetting
#'
#' @param syntax_lines Character vector of syntax lines
#' @param new_varnames Character vector of new variable names
#' @param variable_section_start Start line of VARIABLE section
#' @param variable_section_end End line of VARIABLE section
#' @return Updated syntax lines
#' @export
update_usevariables <- function(syntax_lines, new_varnames, variable_section_start, variable_section_end) {

  # Find USEVARIABLES statement
  use_start_idx <- NULL
  use_end_idx <- NULL

  for (i in variable_section_start:variable_section_end) {
    line <- syntax_lines[i]

    if (grepl("^\\s*USEVARIABLES\\s*=", line, ignore.case = TRUE)) {
      use_start_idx <- i
    }

    if (!is.null(use_start_idx) && is.null(use_end_idx) && grepl(";", line)) {
      use_end_idx <- i
      break
    }
  }

  if (is.null(use_start_idx) || is.null(use_end_idx)) {
    # No USEVARIABLES found - this is OK
    return(syntax_lines)
  }

  # Create new USEVARIABLES statement
  varnames_text <- paste(new_varnames, collapse = " ")
  new_use_line <- sprintf("  USEVARIABLES = %s;", varnames_text)

  # Replace
  syntax_lines_before <- syntax_lines[1:(use_start_idx - 1)]
  syntax_lines_after <- syntax_lines[(use_end_idx + 1):length(syntax_lines)]

  updated_lines <- c(syntax_lines_before, new_use_line, syntax_lines_after)

  cat(sprintf("[OK] Updated USEVARIABLES statement with %d variables\n", length(new_varnames)))

  return(updated_lines)
}

#' Write Modified Template
#'
#' Write updated Mplus syntax to new .inp file
#'
#' @param syntax_lines Character vector of updated syntax lines
#' @param output_path Path for output .inp file
#' @return Path to written file (invisibly)
#' @export
write_modified_template <- function(syntax_lines, output_path) {

  cat("\n", strrep("-", 70), "\n")
  cat("WRITING MODIFIED TEMPLATE\n")
  cat(strrep("-", 70), "\n\n")

  # Create output directory if needed
  output_dir <- dirname(output_path)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  writeLines(syntax_lines, output_path)

  cat(sprintf("[OK] Modified template written: %s\n", output_path))
  cat(sprintf("     Lines: %d\n\n", length(syntax_lines)))

  invisible(output_path)
}

#' Reconcile Template with Data
#'
#' Main orchestrator: read template, detect mismatches, update, write
#' Interactive prompts for user decisions on ambiguous cases
#'
#' @param template_path Path to existing Mplus .inp file
#' @param data_varnames Character vector of variable names from new data
#' @param new_dat_path Path to new .dat file
#' @param output_path Path for output .inp file
#' @return Path to reconciled template (invisibly)
#' @export
reconcile_template_with_data <- function(template_path, data_varnames, new_dat_path, output_path) {

  cat("\n", strrep("=", 70), "\n")
  cat("RECONCILING TEMPLATE WITH NEW DATA\n")
  cat(strrep("=", 70), "\n\n")

  # Step 1: Read template
  template_obj <- read_mplus_template(template_path)

  # Step 2: Parse variable names
  template_varnames <- parse_variable_names(template_obj)

  # Step 3: Detect mismatches
  mismatches <- detect_naming_mismatches(template_varnames, data_varnames)

  # Step 4: Update template if needed
  if (mismatches$needs_update) {
    cat("\n", strrep("-", 70), "\n")
    cat("UPDATING TEMPLATE\n")
    cat(strrep("-", 70), "\n\n")

    # Use data variable names (authoritative)
    updated_lines <- update_variable_names(template_obj, data_varnames)

    # Update USEVARIABLES
    variable_section <- template_obj$sections$VARIABLE
    updated_lines <- update_usevariables(
      updated_lines,
      data_varnames,
      variable_section$start,
      variable_section$end
    )

    # Update data file path
    template_obj$syntax_lines <- updated_lines
    updated_lines <- update_data_file_path(template_obj, new_dat_path)

    # Write modified template
    write_modified_template(updated_lines, output_path)

  } else {
    cat("\n[INFO] No updates needed, template matches data\n")
    cat("       Copying template to output location...\n\n")

    # Just update file path and write
    updated_lines <- update_data_file_path(template_obj, new_dat_path)
    write_modified_template(updated_lines, output_path)
  }

  cat(strrep("=", 70), "\n")
  cat("RECONCILIATION COMPLETE\n")
  cat(strrep("=", 70), "\n\n")

  invisible(output_path)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Assume you have extracted data
# kidsights_data <- extract_items_for_calibration(...)
# data_varnames <- setdiff(names(kidsights_data), c("study_id", "pid", "record_id"))
#
# # Reconcile existing NE22 template with new NE25 data
# reconcile_template_with_data(
#   template_path = "mplus/templates/ne22_kidsights.inp",
#   data_varnames = data_varnames,
#   new_dat_path = "kidsights_ne25_calibration.dat",
#   output_path = "mplus/ne25_kidsights_calibration.inp"
# )
