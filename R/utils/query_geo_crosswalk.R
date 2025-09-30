#' Query Geographic Crosswalk from DuckDB
#'
#' Safely queries geographic crosswalk reference tables from DuckDB using
#' the hybrid Python→Feather→R approach to avoid segmentation faults.
#'
#' @param table_name Name of the crosswalk table to query (e.g., "geo_zip_to_puma")
#' @param temp_dir Directory for temporary Feather files (default: tempdir())
#' @param python_path Path to Python executable (default: python)
#'
#' @return Data frame with crosswalk data, or NULL on error
#'
#' @examples
#' \dontrun{
#' puma_data <- query_geo_crosswalk("geo_zip_to_puma")
#' county_data <- query_geo_crosswalk("geo_zip_to_county")
#' }
#'
#' @export
query_geo_crosswalk <- function(
  table_name,
  temp_dir = NULL,
  python_path = "python"
) {

  # Use default temp dir if not specified
  if (is.null(temp_dir)) {
    temp_dir <- tempdir()
  }

  # Create unique temp file path
  temp_file <- file.path(temp_dir, paste0(table_name, "_", Sys.getpid(), ".feather"))

  # Clean up temp file on exit
  on.exit({
    if (file.exists(temp_file)) {
      unlink(temp_file)
    }
  }, add = TRUE)

  # Build Python command
  python_script <- "python/db/query_geo_crosswalk.py"

  # Check if script exists
  if (!file.exists(python_script)) {
    stop(paste("Python script not found:", python_script))
  }

  cmd <- sprintf(
    '%s %s --table "%s" --output "%s"',
    python_path,
    python_script,
    table_name,
    temp_file
  )

  # Execute Python script
  result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)

  # Check if temp file was created
  if (!file.exists(temp_file)) {
    stop(paste("Failed to query", table_name, "from database"))
  }

  # Read Feather file
  crosswalk_data <- arrow::read_feather(temp_file)

  # Validate result
  if (nrow(crosswalk_data) == 0) {
    warning(paste("Table", table_name, "is empty"))
    return(NULL)
  }

  return(crosswalk_data)
}


#' Get Available Geographic Crosswalk Tables
#'
#' Returns a character vector of available geographic crosswalk table names.
#'
#' @return Character vector of table names
#'
#' @export
get_geo_crosswalk_tables <- function() {
  c(
    "geo_zip_to_puma",
    "geo_zip_to_county",
    "geo_zip_to_tract",
    "geo_zip_to_cbsa",
    "geo_zip_to_urban_rural",
    "geo_zip_to_school_dist",
    "geo_zip_to_state_leg_lower",
    "geo_zip_to_state_leg_upper",
    "geo_zip_to_congress",
    "geo_zip_to_native_lands"
  )
}
