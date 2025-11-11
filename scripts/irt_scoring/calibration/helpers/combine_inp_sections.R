# =============================================================================
# Combine Mplus .inp File Sections
# =============================================================================
# Purpose: Combine generated MODEL syntax with TITLE/DATA/VARIABLE/ANALYSIS
#          sections to create complete Mplus .inp files
#
# Version: 1.0
# Created: November 2025
# =============================================================================

# Source dependencies
source("scripts/irt_scoring/helpers/modify_mplus_template.R")

#' Generate Basic Mplus Template Sections
#'
#' Creates TITLE, DATA, VARIABLE, and ANALYSIS sections for Mplus .inp file
#' Used when no template is provided
#'
#' @param data_file_path Path to .dat file (relative to .inp location)
#' @param variable_names Character vector of variable names (in order)
#' @param title Title for TITLE section (default: "Kidsights IRT Calibration")
#' @param grouping_var Name of grouping variable for multi-group analysis (default: "study")
#' @param n_groups Number of groups (default: 6 for NE20, NE22, NE25, NSCH21, NSCH22, USA24)
#'
#' @return Character vector with template sections (one line per element)
#'
#' @details
#' Generates standard IRT calibration template with:
#' - TITLE: User-specified title
#' - DATA: FILE path
#' - VARIABLE: NAMES, MISSING, CATEGORICAL, GROUPING
#' - ANALYSIS: TYPE = GENERAL, ESTIMATOR = WLSMV, PARAMETERIZATION = THETA
#'
#' @examples
#' template <- generate_basic_mplus_template(
#'   data_file_path = "calibdat.dat",
#'   variable_names = c("study", "id", "years", "AA102", "AA104", "AA105"),
#'   title = "Test IRT Calibration"
#' )
#'
#' @export
generate_basic_mplus_template <- function(
  data_file_path,
  variable_names,
  title = "Kidsights IRT Calibration",
  grouping_var = "study",
  n_groups = 6
) {

  # Separate metadata variables from item variables
  metadata_vars <- c("study", "study_num", "id", "years", "wgt")
  item_vars <- setdiff(variable_names, metadata_vars)

  # Build NAMES list (all variables)
  names_str <- paste(variable_names, collapse = " ")

  # Build USEVARIABLES list (items only, no metadata)
  usevariables_str <- paste(item_vars, collapse = " ")

  # Build CATEGORICAL list (all items are categorical for IRT)
  categorical_str <- paste(item_vars, collapse = " ")

  # Build GROUPING statement
  # Assuming study_num is 1=NE20, 2=NE22, 3=NE25, 5=NSCH21, 6=NSCH22, 7=USA24
  grouping_str <- "study_num (1=NE20 2=NE22 3=NE25 5=NSCH21 6=NSCH22 7=USA24)"

  # Create template sections
  template_lines <- c(
    "TITLE:",
    paste0("  ", title),
    "",
    "DATA:",
    paste0("  FILE = \"", data_file_path, "\";"),
    "",
    "VARIABLE:",
    paste0("  NAMES = ", names_str, ";"),
    "",
    paste0("  USEVARIABLES = ", usevariables_str, ";"),
    "",
    "  MISSING = ALL (.);",
    "",
    paste0("  CATEGORICAL = ", categorical_str, ";"),
    "",
    paste0("  GROUPING = ", grouping_str, ";"),
    "",
    "ANALYSIS:",
    "  TYPE = GENERAL;",
    "  ESTIMATOR = WLSMV;",
    "  PARAMETERIZATION = THETA;",
    ""
  )

  return(template_lines)

}


#' Combine Mplus .inp File Sections
#'
#' Combines template sections (TITLE, DATA, VARIABLE, ANALYSIS) with
#' generated MODEL syntax to create complete Mplus .inp file
#'
#' @param template_inp Path to existing .inp template (optional)
#'   If NULL, generates basic template using generate_basic_mplus_template()
#' @param model_syntax Character vector with MODEL section syntax
#' @param constraint_syntax Character vector with MODEL CONSTRAINT section syntax
#' @param prior_syntax Character vector with MODEL PRIOR section syntax
#' @param data_file_path Path to .dat file (required if template_inp is NULL)
#' @param variable_names Character vector of variable names (required if template_inp is NULL)
#' @param output_inp Path for output .inp file
#' @param title Title for TITLE section (used if template_inp is NULL)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return Path to written .inp file (invisibly)
#'
#' @details
#' Two modes of operation:
#'
#' 1. **With template_inp:** Reads existing .inp file, replaces MODEL section,
#'    appends CONSTRAINT and PRIOR sections
#'
#' 2. **Without template_inp:** Generates basic template, then adds MODEL,
#'    CONSTRAINT, and PRIOR sections
#'
#' @examples
#' # Mode 1: Use existing template
#' combine_inp_sections(
#'   template_inp = "mplus/my_template.inp",
#'   model_syntax = result$model$MODEL,
#'   constraint_syntax = result$constraint[[1]],
#'   prior_syntax = result$prior[[1]],
#'   output_inp = "mplus/calibration.inp"
#' )
#'
#' # Mode 2: Generate template automatically
#' combine_inp_sections(
#'   template_inp = NULL,
#'   model_syntax = result$model$MODEL,
#'   constraint_syntax = result$constraint[[1]],
#'   prior_syntax = result$prior[[1]],
#'   data_file_path = "calibdat.dat",
#'   variable_names = names(calibdat),
#'   output_inp = "mplus/calibration.inp"
#' )
#'
#' @export
combine_inp_sections <- function(
  template_inp = NULL,
  model_syntax,
  constraint_syntax,
  prior_syntax,
  data_file_path = NULL,
  variable_names = NULL,
  output_inp,
  title = "Kidsights IRT Calibration",
  verbose = TRUE
) {

  if (verbose) {
    cat("\n", strrep("=", 70), "\n")
    cat("COMBINING MPLUS .INP FILE SECTIONS\n")
    cat(strrep("=", 70), "\n\n")
  }

  # ---------------------------------------------------------------------------
  # Step 1: Get template sections (from file or generate)
  # ---------------------------------------------------------------------------

  if (!is.null(template_inp)) {

    if (verbose) cat("[1/4] Reading existing template...\n")

    if (!file.exists(template_inp)) {
      stop(sprintf("Template file not found: %s", template_inp))
    }

    # Read template using modify_mplus_template.R
    template_obj <- read_mplus_template(template_inp)
    template_lines <- template_obj$syntax_lines

    if (verbose) {
      cat(sprintf("     Template: %s\n", template_inp))
      cat(sprintf("     Lines: %d\n\n", length(template_lines)))
    }

  } else {

    if (verbose) cat("[1/4] Generating basic template...\n")

    # Validate required parameters
    if (is.null(data_file_path)) {
      stop("data_file_path is required when template_inp is NULL")
    }
    if (is.null(variable_names)) {
      stop("variable_names is required when template_inp is NULL")
    }

    # Generate template
    template_lines <- generate_basic_mplus_template(
      data_file_path = data_file_path,
      variable_names = variable_names,
      title = title
    )

    if (verbose) {
      cat(sprintf("     Generated basic template\n"))
      cat(sprintf("     Lines: %d\n\n", length(template_lines)))
    }

  }

  # ---------------------------------------------------------------------------
  # Step 2: Add MODEL section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[2/4] Adding MODEL section...\n")

  # Convert model_syntax to character vector if it's a data frame
  if (is.data.frame(model_syntax)) {
    model_lines <- as.character(model_syntax[[1]])
  } else {
    model_lines <- as.character(model_syntax)
  }

  model_section <- c(
    "MODEL:",
    "  ! Factor structure and thresholds",
    paste0("  ", model_lines),
    ""
  )

  if (verbose) {
    cat(sprintf("     MODEL lines: %d\n\n", length(model_lines)))
  }

  # ---------------------------------------------------------------------------
  # Step 3: Add MODEL CONSTRAINT section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[3/4] Adding MODEL CONSTRAINT section...\n")

  # Convert constraint_syntax to character vector
  if (is.data.frame(constraint_syntax)) {
    constraint_lines <- as.character(constraint_syntax[[1]])
  } else {
    constraint_lines <- as.character(constraint_syntax)
  }

  constraint_section <- c(
    "MODEL CONSTRAINT:",
    "  ! Parameter constraints",
    paste0("  ", constraint_lines),
    ""
  )

  if (verbose) {
    cat(sprintf("     CONSTRAINT lines: %d\n\n", length(constraint_lines)))
  }

  # ---------------------------------------------------------------------------
  # Step 4: Add MODEL PRIOR section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[4/4] Adding MODEL PRIOR section...\n")

  # Convert prior_syntax to character vector
  if (is.data.frame(prior_syntax)) {
    prior_lines <- as.character(prior_syntax[[1]])
  } else {
    prior_lines <- as.character(prior_syntax)
  }

  prior_section <- c(
    "MODEL PRIOR:",
    "  ! Bayesian priors for regularization",
    paste0("  ", prior_lines),
    ""
  )

  if (verbose) {
    cat(sprintf("     PRIOR lines: %d\n\n", length(prior_lines)))
  }

  # ---------------------------------------------------------------------------
  # Step 5: Combine all sections and write file
  # ---------------------------------------------------------------------------

  if (verbose) cat("Writing .inp file...\n")

  # Combine all sections
  complete_inp <- c(
    template_lines,
    model_section,
    constraint_section,
    prior_section
  )

  # Create output directory if needed
  output_dir <- dirname(output_inp)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Write file
  writeLines(complete_inp, output_inp)

  if (verbose) {
    cat(sprintf("\n[OK] .inp file created successfully!\n"))
    cat(sprintf("     Output: %s\n", output_inp))
    cat(sprintf("     Total lines: %d\n\n", length(complete_inp)))
    cat("File structure:\n")
    cat(sprintf("  TITLE/DATA/VARIABLE/ANALYSIS: %d lines\n", length(template_lines)))
    cat(sprintf("  MODEL: %d lines\n", length(model_section)))
    cat(sprintf("  MODEL CONSTRAINT: %d lines\n", length(constraint_section)))
    cat(sprintf("  MODEL PRIOR: %d lines\n\n", length(prior_section)))
  }

  return(invisible(output_inp))

}
