#' Harmonize NSCH 2022 Data
#'
#' Wrapper function for harmonizing NSCH 2022 data with CAHMI22 lexicons.
#' Maps CAHMI22 variable names to lex_equate naming convention.
#'
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#'
#' @return Data frame with columns:
#'   - HHID: Numeric household ID
#'   - {lex_equate items}: ~42 harmonized items (0-based, reverse coded)
#'
#' @details
#' This function calls harmonize_nsch_core() with year=2022 and study="cahmi22".
#' All transformation logic is codebook-driven:
#' - Missing values recoded using response_sets
#' - Reverse coding based on reverse_by_study.cahmi22 (with fallback to default)
#' - All values 0-based (minimum = 0)
#'
#' @examples
#' \dontrun{
#' # Harmonize NSCH 2022 data
#' nsch22 <- harmonize_nsch_2022()
#'
#' # Check output
#' dim(nsch22)  # Should be ~54,103 rows, ~43 columns (HHID + 42 items)
#' summary(nsch22)
#' }
#'
#' @seealso \code{\link{harmonize_nsch_core}}
harmonize_nsch_2022 <- function(db_path = "data/duckdb/kidsights_local.duckdb",
                                 codebook_path = "codebook/data/codebook.json") {

  # Source core function
  source("R/transform/nsch/harmonize_nsch_core.R")

  # Call core with CAHMI22 parameters
  message("=== NSCH 2022 Harmonization (CAHMI22 lexicons) ===")
  result <- harmonize_nsch_core(
    year = 2022,
    study = "cahmi22",
    db_path = db_path,
    codebook_path = codebook_path
  )

  message("===================================================")
  return(result)
}
