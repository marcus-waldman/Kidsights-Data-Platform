# =============================================================================
# Interactive Mplus Calibration Preparation
# =============================================================================
# Purpose: Interactive workflow to prepare datasets for Mplus IRT calibration
#          Guides user through extraction, filtering, and syntax preparation
#
# Usage:
#   source("scripts/irt_scoring/prepare_mplus_calibration.R")
#   prepare_mplus_calibration()
#
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

# Source helper functions
source("scripts/irt_scoring/helpers/mplus_dataset_prep.R")
source("scripts/irt_scoring/helpers/write_mplus_data.R")
source("scripts/irt_scoring/helpers/modify_mplus_template.R")

#' Interactive Mplus Calibration Preparation
#'
#' Main interactive workflow for preparing Mplus calibration datasets
#' Guides user through all steps with human-in-the-loop oversight
#'
#' @param codebook_path Path to codebook.json (default: "codebook/data/codebook.json")
#' @param db_path Path to DuckDB database (default: "data/duckdb/kidsights_local.duckdb")
#' @return NULL (creates files as side effect)
#' @export
prepare_mplus_calibration <- function(codebook_path = "codebook/data/codebook.json",
                                      db_path = "data/duckdb/kidsights_local.duckdb") {

  cat("\n", strrep("=", 80), "\n")
  cat("INTERACTIVE MPLUS CALIBRATION PREPARATION\n")
  cat(strrep("=", 80), "\n\n")

  cat("This workflow will:\n")
  cat("  1. Extract items from database for calibration\n")
  cat("  2. Apply sample filters (eligible, age ranges, etc.)\n")
  cat("  3. Write Mplus .dat data file\n")
  cat("  4. Create/update Mplus .inp syntax file\n")
  cat("\n")

  # ---------------------------------------------------------------------------
  # Step 1: Scale selection
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 1: SCALE SELECTION\n")
  cat(strrep("=", 80), "\n\n")

  cat("Which scale do you want to prepare for calibration?\n")
  cat("  [1] Kidsights developmental scale (unidimensional, 203 items)\n")
  cat("  [2] Psychosocial scale (bifactor, 44 items)\n")
  cat("  [3] Cancel\n\n")

  scale_choice <- readline(prompt = "Enter choice (1-3): ")
  scale_choice <- as.integer(scale_choice)

  if (is.na(scale_choice) || scale_choice < 1 || scale_choice > 3) {
    cat("\n[ERROR] Invalid choice\n")
    return(invisible(NULL))
  }

  if (scale_choice == 3) {
    cat("\n[INFO] Workflow cancelled\n")
    return(invisible(NULL))
  }

  scale_name <- if (scale_choice == 1) "kidsights" else "psychosocial"
  cat(sprintf("\n[OK] Selected scale: %s\n\n", scale_name))

  # ---------------------------------------------------------------------------
  # Step 2: Sample filter specification
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 2: SAMPLE FILTER SPECIFICATION\n")
  cat(strrep("=", 80), "\n\n")

  cat("Do you want to apply sample filters?\n")
  cat("  [1] Yes, use standard filters (eligible=TRUE, authentic=TRUE)\n")
  cat("  [2] Yes, customize filters\n")
  cat("  [3] No, use full dataset\n\n")

  filter_choice <- readline(prompt = "Enter choice (1-3): ")
  filter_choice <- as.integer(filter_choice)

  sample_filters <- NULL

  if (filter_choice == 1) {
    sample_filters <- list(eligible = TRUE, authentic = TRUE)
    cat("\n[OK] Using standard filters: eligible=TRUE, authentic=TRUE\n\n")

  } else if (filter_choice == 2) {
    cat("\n[INFO] Custom filters not yet implemented\n")
    cat("[INFO] Using standard filters instead\n\n")
    sample_filters <- list(eligible = TRUE, authentic = TRUE)
  }

  # Age range filter
  cat("Do you want to apply an age range filter?\n")
  cat("  [1] Yes, specify age range in months\n")
  cat("  [2] No, include all ages\n\n")

  age_choice <- readline(prompt = "Enter choice (1-2): ")
  age_choice <- as.integer(age_choice)

  age_range <- NULL

  if (age_choice == 1) {
    min_age <- readline(prompt = "Minimum age in months: ")
    max_age <- readline(prompt = "Maximum age in months: ")

    min_age <- as.integer(min_age)
    max_age <- as.integer(max_age)

    if (!is.na(min_age) && !is.na(max_age) && min_age < max_age) {
      age_range <- c(min_age, max_age)
      cat(sprintf("\n[OK] Age range: %d to %d months\n\n", min_age, max_age))
    } else {
      cat("\n[WARN] Invalid age range, skipping age filter\n\n")
    }
  }

  # ---------------------------------------------------------------------------
  # Step 3: Extract items from database
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 3: EXTRACT ITEMS FROM DATABASE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Extracting items...\n")

  calibration_data <- extract_items_for_calibration(
    scale_name = scale_name,
    sample_filters = sample_filters,
    age_range = age_range,
    codebook_path = codebook_path,
    db_path = db_path
  )

  if (is.null(calibration_data) || nrow(calibration_data) == 0) {
    cat("\n[ERROR] No data extracted. Check filters and try again.\n")
    return(invisible(NULL))
  }

  # Get item column names (exclude identifiers)
  item_cols <- setdiff(names(calibration_data), c("study_id", "pid", "record_id"))

  # ---------------------------------------------------------------------------
  # Step 4: Output file path specification
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 4: OUTPUT FILE SPECIFICATION\n")
  cat(strrep("=", 80), "\n\n")

  # Suggest default path
  default_dat_path <- sprintf("mplus/%s_calibration.dat", scale_name)
  cat(sprintf("Suggested .dat file path: %s\n", default_dat_path))
  cat("Press Enter to accept, or type custom path:\n")

  dat_path <- readline(prompt = "> ")
  dat_path <- trimws(dat_path)

  if (nchar(dat_path) == 0) {
    dat_path <- default_dat_path
  }

  cat(sprintf("\n[OK] .dat file path: %s\n\n", dat_path))

  # ---------------------------------------------------------------------------
  # Step 5: Template decision
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 5: MPLUS SYNTAX TEMPLATE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Do you have an existing Mplus template to update?\n")
  cat("  [1] Yes, I have an existing .inp file to reconcile\n")
  cat("  [2] No, create new template from scratch\n\n")

  template_choice <- readline(prompt = "Enter choice (1-2): ")
  template_choice <- as.integer(template_choice)

  use_template <- FALSE
  template_path <- NULL

  if (template_choice == 1) {
    cat("\nEnter path to existing .inp template:\n")
    template_path <- readline(prompt = "> ")
    template_path <- trimws(template_path)

    if (file.exists(template_path)) {
      use_template <- TRUE
      cat(sprintf("\n[OK] Using template: %s\n\n", template_path))
    } else {
      cat(sprintf("\n[WARN] Template not found: %s\n", template_path))
      cat("[INFO] Will create new template instead\n\n")
      use_template <- FALSE
    }
  }

  # Output .inp path
  default_inp_path <- sprintf("mplus/%s_calibration.inp", scale_name)
  cat(sprintf("Suggested .inp file path: %s\n", default_inp_path))
  cat("Press Enter to accept, or type custom path:\n")

  inp_path <- readline(prompt = "> ")
  inp_path <- trimws(inp_path)

  if (nchar(inp_path) == 0) {
    inp_path <- default_inp_path
  }

  cat(sprintf("\n[OK] .inp file path: %s\n\n", inp_path))

  # ---------------------------------------------------------------------------
  # Step 6: Write .dat file
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 6: WRITE .DAT FILE\n")
  cat(strrep("=", 80), "\n\n")

  write_dat_file(
    data = calibration_data,
    output_path = dat_path,
    identifier_cols = c("study_id", "pid", "record_id"),
    validate_before_write = TRUE
  )

  # ---------------------------------------------------------------------------
  # Step 7: Create/update .inp file
  # ---------------------------------------------------------------------------

  cat(strrep("=", 80), "\n")
  cat("STEP 7: CREATE/UPDATE .INP FILE\n")
  cat(strrep("=", 80), "\n\n")

  if (use_template) {
    # Reconcile existing template with new data
    cat("Reconciling existing template with new data...\n\n")

    reconcile_template_with_data(
      template_path = template_path,
      data_varnames = item_cols,
      new_dat_path = basename(dat_path),  # Relative path for Mplus syntax
      output_path = inp_path
    )

  } else {
    # Create new template from scratch
    cat("Creating new Mplus syntax template...\n\n")

    write_mplus_syntax_template(
      variable_names = item_cols,
      dat_file_path = basename(dat_path),
      scale_name = scale_name,
      output_path = inp_path
    )
  }

  # ---------------------------------------------------------------------------
  # Final summary
  # ---------------------------------------------------------------------------

  cat("\n", strrep("=", 80), "\n")
  cat("MPLUS CALIBRATION PREPARATION COMPLETE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Files created:\n")
  cat(sprintf("  Data file (.dat): %s\n", dat_path))
  cat(sprintf("  Syntax file (.inp): %s\n", inp_path))
  cat(sprintf("  Variable names: %s\n", sub("\\.dat$", "_varnames.txt", dat_path)))
  cat("\n")

  cat("Sample information:\n")
  cat(sprintf("  Scale: %s\n", scale_name))
  cat(sprintf("  Records: %d\n", nrow(calibration_data)))
  cat(sprintf("  Items: %d\n", length(item_cols)))
  if (!is.null(sample_filters)) {
    cat(sprintf("  Filters: %s\n", paste(names(sample_filters), "=", sample_filters, collapse = ", ")))
  }
  if (!is.null(age_range)) {
    cat(sprintf("  Age range: %d-%d months\n", age_range[1], age_range[2]))
  }
  cat("\n")

  cat("Next steps:\n")
  cat("  1. Open the .inp file in a text editor\n")
  if (!use_template) {
    cat("  2. Specify your IRT model in the MODEL section\n")
    cat("     - For unidimensional: F BY item1* item2 item3 ...; F@1;\n")
    cat("     - For bifactor: GEN BY all_items*; SPEC1 BY subset1; ...\n")
  } else {
    cat("  2. Review the updated NAMES and USEVARIABLES sections\n")
    cat("  3. Verify MODEL section still matches your factor structure\n")
  }
  cat(sprintf("  %d. Run Mplus with the .inp file\n", if (use_template) 4 else 3))
  cat(sprintf("  %d. Review output for model fit and parameter estimates\n", if (use_template) 5 else 4))
  cat(sprintf("  %d. Use R/codebook/update_irt_parameters.R to update codebook\n", if (use_template) 6 else 5))
  cat("\n")

  cat(strrep("=", 80), "\n\n")

  invisible(NULL)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Run interactive workflow
# prepare_mplus_calibration()
#
# # Or with custom paths
# prepare_mplus_calibration(
#   codebook_path = "path/to/codebook.json",
#   db_path = "path/to/database.duckdb"
# )
