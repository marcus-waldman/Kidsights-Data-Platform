#' Harmonize NSCH 2021 Data
#'
#' Wrapper function for harmonizing NSCH 2021 data with CAHMI21 lexicons.
#' Maps CAHMI21 variable names to lex_equate naming convention.
#'
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#'
#' @return Data frame with columns:
#'   - HHID: Numeric household ID
#'   - {lex_equate items}: ~30 harmonized items (0-based, reverse coded)
#'
#' @details
#' This function calls harmonize_nsch_core() with year=2021 and study="cahmi21".
#' All transformation logic is codebook-driven:
#' - Missing values recoded using response_sets
#' - Reverse coding based on reverse_by_study.cahmi21 (with fallback to default)
#' - All values 0-based (minimum = 0)
#'
#' @examples
#' \dontrun{
#' # Harmonize NSCH 2021 data
#' nsch21 <- harmonize_nsch_2021()
#'
#' # Check output
#' dim(nsch21)  # Should be ~50,892 rows, ~31 columns (HHID + 30 items)
#' summary(nsch21)
#' }
#'
#' @seealso \code{\link{harmonize_nsch_core}}
harmonize_nsch_2021 <- function(db_path = "data/duckdb/kidsights_local.duckdb",
                                 codebook_path = "codebook/data/codebook.json") {

  # Source core function
  source("R/transform/nsch/harmonize_nsch_core.R")

  # Call core with CAHMI21 parameters
  message("=== NSCH 2021 Harmonization (CAHMI21 lexicons) ===")
  result <- harmonize_nsch_core(
    year = 2021,
    study = "cahmi21",
    db_path = db_path,
    codebook_path = codebook_path
  )

  message("===================================================")
  return(result)
}
