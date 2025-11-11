# =============================================================================
# Generate Kidsights Mplus MODEL Syntax
# =============================================================================
# Purpose: Main orchestrator for IRT calibration syntax generation
#          Integrates with Kidsights codebook and calibration dataset
#
# Version: 1.0
# Created: November 2025
# =============================================================================

# Source dependencies
source("scripts/irt_scoring/calibration/write_syntax2.R")
source("scripts/irt_scoring/calibration/helpers/build_equate_table.R")
source("scripts/irt_scoring/calibration/helpers/combine_inp_sections.R")

#' Generate Kidsights Mplus MODEL Syntax
#'
#' Main orchestrator function for IRT item calibration syntax generation.
#' Loads codebook, extracts constraints, loads calibration dataset,
#' and generates MODEL, MODEL CONSTRAINT, and MODEL PRIOR syntax.
#'
#' @param scale_name Scale name (default: "kidsights")
#'   Currently not used for filtering - all items with equate lexicon included
#' @param codebook_path Path to codebook.json (default: "codebook/data/codebook.json")
#' @param db_path Path to DuckDB database (default: "data/duckdb/kidsights_local.duckdb")
#' @param calibration_table Name of calibration table in database (default: "calibration_dataset_2020_2025_restructured")
#' @param output_xlsx Path for Excel output (default: "mplus/generated_syntax.xlsx")
#' @param output_inp Path for .inp output (default: NULL, no .inp generated)
#'   Set to path like "mplus/calibration.inp" to generate complete Mplus input file
#' @param template_inp Path to existing .inp template (default: NULL, generate basic template)
#'   If provided, will use this template's TITLE/DATA/VARIABLE/ANALYSIS sections
#' @param dat_file_path Path to .dat file relative to .inp location (default: "calibdat.dat")
#'   Used when generating .inp file (for DATA section FILE path)
#' @param apply_1pl Logical, apply 1-PL/Rasch constraints to unconstrained items (default: FALSE)
#'   - TRUE: All unconstrained items share equal discrimination parameters
#'   - FALSE: Each item gets unique discrimination parameter (2-PL model)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return List with components:
#'   - model: Data frame with MODEL section syntax
#'   - constraint: Data frame with MODEL CONSTRAINT section syntax
#'   - prior: Data frame with MODEL PRIOR section syntax
#'   - excel_path: Path to written Excel file
#'   - codebook_df: Codebook data frame used (for debugging)
#'   - equate: Equate table used (for debugging)
#'
#' @details
#' This function orchestrates the complete syntax generation workflow:
#'
#' 1. Load codebook.json and build equate table (jid ↔ lex_equate)
#' 2. Build codebook_df with param_constraints
#' 3. Load calibration dataset from DuckDB
#' 4. Call write_syntax2() to generate syntax
#' 5. Write Excel file with MODEL, CONSTRAINT, PRIOR sheets
#' 6. Optionally generate complete .inp file (if output_inp specified)
#'
#' The calibration dataset should have:
#' - study, study_num, id, years columns
#' - Item columns matching lex_equate names from codebook
#' - 47,084 records across 6 studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24)
#'
#' @examples
#' # Generate Excel only
#' syntax <- generate_kidsights_model_syntax(
#'   scale_name = "kidsights",
#'   output_xlsx = "mplus/generated_syntax.xlsx"
#' )
#'
#' # Generate both Excel and .inp file
#' syntax <- generate_kidsights_model_syntax(
#'   scale_name = "kidsights",
#'   output_xlsx = "mplus/generated_syntax.xlsx",
#'   output_inp = "mplus/calibration.inp"
#' )
#'
#' @export
generate_kidsights_model_syntax <- function(
  scale_name = "kidsights",
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb",
  calibration_table = "calibration_dataset_2020_2025_restructured",
  output_xlsx = "mplus/generated_syntax.xlsx",
  output_inp = NULL,
  template_inp = NULL,
  dat_file_path = "calibdat.dat",
  apply_1pl = FALSE,
  verbose = TRUE
) {

  if (verbose) {
    cat("\n", strrep("=", 80), "\n")
    cat("KIDSIGHTS IRT CALIBRATION SYNTAX GENERATION\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("Scale: %s\n", scale_name))
    cat(sprintf("Codebook: %s\n", codebook_path))
    cat(sprintf("Database: %s\n", db_path))
    cat(sprintf("Calibration table: %s\n", calibration_table))
    cat(sprintf("Output: %s\n\n", output_xlsx))
  }

  # ---------------------------------------------------------------------------
  # Step 1: Load codebook and build equate table
  # ---------------------------------------------------------------------------

  if (verbose) cat("[1/4] Loading codebook and building equate table...\n\n")

  equate <- build_equate_table_from_codebook(
    codebook_path = codebook_path,
    verbose = verbose
  )

  # Load full codebook for param_constraints
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Build codebook_df
  codebook_df <- build_codebook_df(
    codebook = codebook,
    equate = equate,
    scale_name = scale_name
  )

  if (verbose) {
    cat(sprintf("Codebook_df rows: %d\n", nrow(codebook_df)))
    cat(sprintf("Items with constraints: %d\n\n", sum(!is.na(codebook_df$param_constraints))))
  }

  # ---------------------------------------------------------------------------
  # Step 2: Load calibration dataset from DuckDB
  # ---------------------------------------------------------------------------

  if (verbose) cat("[2/4] Loading calibration dataset from DuckDB...\n\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database file not found: %s\n\nPlease run prepare_calibration_dataset.R first.", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)

  # Check if table exists
  tables <- DBI::dbListTables(conn)
  if (!(calibration_table %in% tables)) {
    DBI::dbDisconnect(conn)
    stop(sprintf("Table '%s' not found in database.\n\nAvailable tables: %s\n\nPlease run prepare_calibration_dataset.R first.",
                 calibration_table,
                 paste(tables, collapse = ", ")))
  }

  # Load calibration dataset
  calibdat <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s", calibration_table))
  DBI::dbDisconnect(conn)

  if (verbose) {
    cat(sprintf("Calibration dataset loaded:\n"))
    cat(sprintf("  Rows: %s\n", format(nrow(calibdat), big.mark = ",")))
    cat(sprintf("  Columns: %d\n", ncol(calibdat)))

    # Show study breakdown
    if ("study" %in% names(calibdat)) {
      study_counts <- calibdat %>%
        dplyr::group_by(study) %>%
        dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
        dplyr::arrange(study)

      cat("\n  Study breakdown:\n")
      for (i in 1:nrow(study_counts)) {
        cat(sprintf("    %s: %s records\n",
                    study_counts$study[i],
                    format(study_counts$n[i], big.mark = ",")))
      }
    }
    cat("\n")
  }

  # ---------------------------------------------------------------------------
  # Step 3: Generate Mplus syntax
  # ---------------------------------------------------------------------------

  if (verbose) cat("[3/4] Generating Mplus MODEL syntax...\n")

  syntax_result <- write_syntax2(
    codebook_df = codebook_df,
    calibdat = calibdat,
    output_xlsx = output_xlsx,
    apply_1pl = apply_1pl,
    verbose = verbose
  )

  # ---------------------------------------------------------------------------
  # Step 4: Optionally generate .inp file
  # ---------------------------------------------------------------------------

  if (!is.null(output_inp)) {

    if (verbose) cat("[4/5] Generating complete .inp file...\n\n")

    # Get variable names from calibration dataset
    variable_names <- names(calibdat)

    combine_inp_sections(
      template_inp = template_inp,
      model_syntax = syntax_result$model$MODEL,
      constraint_syntax = syntax_result$constraint[[1]],
      prior_syntax = syntax_result$prior[[1]],
      data_file_path = dat_file_path,
      variable_names = variable_names,
      output_inp = output_inp,
      title = sprintf("%s IRT Calibration", stringr::str_to_title(scale_name)),
      verbose = verbose
    )

  }

  # ---------------------------------------------------------------------------
  # Step 5: Return results
  # ---------------------------------------------------------------------------

  if (verbose) {
    cat(sprintf("[%d/%d] Syntax generation complete!\n\n", ifelse(is.null(output_inp), 4, 5), ifelse(is.null(output_inp), 4, 5)))
    cat(strrep("=", 80), "\n")
    cat("OUTPUT FILES\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("Excel file: %s\n", output_xlsx))
    cat("  Sheets:\n")
    cat("    - MODEL: Factor loadings and thresholds\n")
    cat("    - MODEL CONSTRAINT: Parameter constraints and 1-PL equations\n")
    cat("    - MODEL PRIOR: Bayesian priors (N(1,1) for discriminations)\n\n")

    if (!is.null(output_inp)) {
      cat(sprintf("Mplus .inp file: %s\n", output_inp))
      cat("  Complete Mplus input file ready for execution\n\n")
    }

    cat("Next steps:\n")
    if (is.null(output_inp)) {
      cat("  1. Open Excel file to review generated syntax\n")
      cat("  2. Verify constraints are correctly specified\n")
      cat("  3. Copy syntax sections into Mplus .inp file\n")
      cat("  4. Run Mplus calibration\n\n")
    } else {
      cat("  1. Review Excel file for syntax correctness\n")
      cat("  2. Open .inp file in Mplus\n")
      cat("  3. Run → Run Mplus\n")
      cat("  4. Check .out file for convergence and fit\n\n")
    }
  }

  # Return syntax result with additional metadata
  result <- syntax_result
  result$codebook_df <- codebook_df
  result$equate <- equate
  result$scale_name <- scale_name

  return(invisible(result))

}
