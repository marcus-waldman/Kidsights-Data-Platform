#' Load NSCH Data Functions
#'
#' Functions for loading NSCH Feather files and metadata into R.
#'
#' @author Kidsights Data Platform
#' @date 2025-10-03

#' Load NSCH Data for a Specific Year
#'
#' Loads the raw Feather file for a given NSCH survey year.
#'
#' @param year Integer, survey year (2016-2023)
#' @return data.frame with NSCH data
#'
#' @examples
#' \dontrun{
#' data_2023 <- load_nsch_year(2023)
#' print(dim(data_2023))
#' }
#'
#' @export
load_nsch_year <- function(year) {
  # Validate year
  if (!year %in% 2016:2023) {
    stop(sprintf("Invalid year: %d. Must be 2016-2023.", year))
  }

  # Construct file path
  feather_file <- sprintf("data/nsch/%d/raw.feather", year)

  # Check file exists
  if (!file.exists(feather_file)) {
    stop(sprintf("Feather file not found: %s", feather_file))
  }

  # Load Feather file using arrow
  cat(sprintf("[INFO] Loading NSCH %d data from: %s\n", year, feather_file))

  data <- arrow::read_feather(feather_file)

  cat(sprintf("[OK] Data loaded: %s rows, %d columns\n",
              format(nrow(data), big.mark = ","),
              ncol(data)))

  return(data)
}


#' Load NSCH Metadata for a Specific Year
#'
#' Loads the metadata JSON file containing variable labels and value labels.
#'
#' @param year Integer, survey year (2016-2023)
#' @return list with metadata structure
#'
#' @examples
#' \dontrun{
#' metadata <- load_nsch_metadata(2023)
#' print(metadata$variable_count)
#' }
#'
#' @export
load_nsch_metadata <- function(year) {
  # Validate year
  if (!year %in% 2016:2023) {
    stop(sprintf("Invalid year: %d. Must be 2016-2023.", year))
  }

  # Construct file path
  metadata_file <- sprintf("data/nsch/%d/metadata.json", year)

  # Check file exists
  if (!file.exists(metadata_file)) {
    stop(sprintf("Metadata file not found: %s", metadata_file))
  }

  # Load JSON file
  cat(sprintf("[INFO] Loading NSCH %d metadata from: %s\n", year, metadata_file))

  metadata <- jsonlite::fromJSON(metadata_file)

  cat(sprintf("[OK] Metadata loaded: %d variables\n", metadata$variable_count))

  return(metadata)
}


#' Get Variable Label from Metadata
#'
#' Retrieves the descriptive label for a specific variable.
#'
#' @param metadata list, metadata object from load_nsch_metadata()
#' @param variable_name character, name of variable
#' @return character, variable label or empty string if not found
#'
#' @examples
#' \dontrun{
#' metadata <- load_nsch_metadata(2023)
#' label <- get_variable_label(metadata, "HHID")
#' print(label)
#' }
#'
#' @export
get_variable_label <- function(metadata, variable_name) {
  if (!variable_name %in% names(metadata$variables)) {
    return("")
  }

  label <- metadata$variables[[variable_name]]$label

  return(ifelse(is.null(label), "", label))
}


#' Get Value Labels for a Variable
#'
#' Retrieves the value-to-label mapping for a categorical variable.
#'
#' @param metadata list, metadata object from load_nsch_metadata()
#' @param variable_name character, name of variable
#' @return named list of value labels, or NULL if variable has no labels
#'
#' @examples
#' \dontrun{
#' metadata <- load_nsch_metadata(2023)
#' labels <- get_value_labels(metadata, "FIPSST")
#' print(labels)
#' }
#'
#' @export
get_value_labels <- function(metadata, variable_name) {
  if (!variable_name %in% names(metadata$variables)) {
    return(NULL)
  }

  var_info <- metadata$variables[[variable_name]]

  if (is.null(var_info$value_labels)) {
    return(NULL)
  }

  return(var_info$value_labels)
}
