#' ACS Data Loading Module
#'
#' Load raw ACS data from Feather files created by Python extraction pipeline.
#' Preserves all IPUMS variable names and coding schemes without transformation.
#'
#' @description
#' This module provides functions to load ACS data extracted via IPUMS API.
#' **IMPORTANT**: No transformations or recoding are applied. All IPUMS variables
#' are preserved in original form (AGE, SEX, RACE, EDUC_mom, EDUC_pop, etc.).
#'
#' @section Functions:
#' - load_acs_feather(): Load raw ACS data from Feather file
#' - get_acs_file_path(): Construct path to ACS Feather file
#' - list_available_acs_extracts(): List available ACS extracts
#'
#' @section Required Packages:
#' - arrow: For reading Feather files
#' - dplyr: For data manipulation
#' - here: For project-relative paths (optional)
#'
#' @examples
#' \dontrun{
#' # Load Nebraska 2019-2023 ACS data
#' ne_data <- load_acs_feather("nebraska", "2019-2023")
#'
#' # Check structure
#' str(ne_data)
#'
#' # List available extracts
#' list_available_acs_extracts()
#' }


#' Get path to ACS Feather file
#'
#' Construct file path for ACS Feather data file based on state and year range.
#' By default uses project structure: data/acs/{state}/{year_range}/raw.feather
#'
#' @param state Character. State name (lowercase, e.g., "nebraska")
#' @param year_range Character. Year range (e.g., "2019-2023")
#' @param base_dir Character. Base directory for ACS data (default: "data/acs")
#' @param filename Character. Feather filename (default: "raw.feather")
#'
#' @return Character. Full path to Feather file
#'
#' @examples
#' get_acs_file_path("nebraska", "2019-2023")
#' # Returns: "data/acs/nebraska/2019-2023/raw.feather"
#'
#' @export
get_acs_file_path <- function(state,
                               year_range,
                               base_dir = "data/acs",
                               filename = "raw.feather") {

  # Validate inputs
  if (missing(state) || is.null(state) || state == "") {
    stop("state argument is required and cannot be empty")
  }

  if (missing(year_range) || is.null(year_range) || year_range == "") {
    stop("year_range argument is required and cannot be empty")
  }

  # Construct path
  file_path <- file.path(base_dir, state, year_range, filename)

  return(file_path)
}


#' Load ACS data from Feather file
#'
#' Load raw ACS data extracted from IPUMS API. Preserves all IPUMS variable
#' names and coding schemes without transformation. Adds metadata columns
#' for state, year_range, and extract_date.
#'
#' @param state Character. State name (lowercase, e.g., "nebraska", "iowa")
#' @param year_range Character. Year range for 5-year ACS (e.g., "2019-2023")
#' @param base_dir Character. Base directory for ACS data (default: "data/acs")
#' @param add_metadata Logical. Add metadata columns (state, year_range, extract_date)?
#'   Default: TRUE
#' @param validate Logical. Perform basic validation checks? Default: TRUE
#'
#' @return data.frame with raw IPUMS variables plus metadata columns
#'
#' @details
#' **IPUMS Variables Preserved:**
#' - All variables maintain original IPUMS names (AGE, SEX, RACE, HISPAN, etc.)
#' - Attached characteristics preserved (EDUC_mom, EDUC_pop, MARST_head, etc.)
#' - IPUMS coding schemes unchanged (e.g., SEX: 1=Male, 2=Female)
#' - Categorical variables loaded as R factors
#'
#' **Metadata Columns Added (if add_metadata=TRUE):**
#' - state: State name
#' - year_range: Year range of ACS sample
#' - extract_date: Current date (when data was loaded)
#'
#' **No Transformations Applied:**
#' - NO recoding of race/ethnicity
#' - NO harmonization with Kidsights variables
#' - NO derived variable creation
#' - Raw IPUMS data only
#'
#' @examples
#' \dontrun{
#' # Load Nebraska 2019-2023 data
#' ne_acs <- load_acs_feather("nebraska", "2019-2023")
#'
#' # Check dimensions
#' dim(ne_acs)
#'
#' # View variable names (all IPUMS originals)
#' names(ne_acs)
#'
#' # Check factor levels for SEX
#' levels(ne_acs$SEX)
#'
#' # Load without metadata columns
#' ne_acs_raw <- load_acs_feather("nebraska", "2019-2023", add_metadata = FALSE)
#' }
#'
#' @export
load_acs_feather <- function(state,
                              year_range,
                              base_dir = "data/acs",
                              add_metadata = TRUE,
                              validate = TRUE) {

  # Get file path
  file_path <- get_acs_file_path(state, year_range, base_dir)

  # Check file exists
  if (!file.exists(file_path)) {
    stop(sprintf(
      "ACS Feather file not found: %s\n\nPlease run extraction pipeline first:\n  python pipelines/python/acs/extract_acs_data.py --state %s --year-range %s",
      file_path,
      state,
      year_range
    ))
  }

  # Log loading
  message(sprintf("Loading ACS data: %s %s", state, year_range))
  message(sprintf("  File: %s", file_path))

  # Read Feather file using arrow package
  # Feather format preserves categorical variables as R factors
  data <- arrow::read_feather(file_path)

  # Convert to regular data.frame (from Arrow Table)
  data <- as.data.frame(data)

  message(sprintf("  Loaded: %s records, %s variables",
                  format(nrow(data), big.mark = ","),
                  ncol(data)))

  # Add metadata columns if requested
  if (add_metadata) {
    data$state <- state
    data$year_range <- year_range
    data$extract_date <- as.character(Sys.Date())

    message("  Added metadata columns: state, year_range, extract_date")
  }

  # Basic validation if requested
  if (validate) {
    # Check for critical IPUMS variables
    critical_vars <- c("SERIAL", "PERNUM")
    missing_critical <- setdiff(critical_vars, names(data))

    if (length(missing_critical) > 0) {
      warning(sprintf(
        "Missing critical IPUMS variables: %s",
        paste(missing_critical, collapse = ", ")
      ))
    }

    # Check for duplicate person records
    if (all(critical_vars %in% names(data))) {
      n_dups <- sum(duplicated(data[, c("SERIAL", "PERNUM")]))
      if (n_dups > 0) {
        warning(sprintf(
          "Found %s duplicate SERIAL+PERNUM records",
          format(n_dups, big.mark = ",")
        ))
      }
    }

    # Check for sampling weights
    if ("PERWT" %in% names(data)) {
      n_missing_wt <- sum(is.na(data$PERWT) | data$PERWT <= 0)
      if (n_missing_wt > 0) {
        warning(sprintf(
          "%s records have missing or zero PERWT",
          format(n_missing_wt, big.mark = ",")
        ))
      }
    }
  }

  message(sprintf("✓ ACS data loaded successfully: %s %s", state, year_range))

  return(data)
}


#' List available ACS extracts
#'
#' Scan data/acs/ directory for available state/year extracts.
#'
#' @param base_dir Character. Base directory for ACS data (default: "data/acs")
#'
#' @return data.frame with columns: state, year_range, file_path, file_size_mb, file_date
#'
#' @examples
#' \dontrun{
#' available <- list_available_acs_extracts()
#' print(available)
#' }
#'
#' @export
list_available_acs_extracts <- function(base_dir = "data/acs") {

  if (!dir.exists(base_dir)) {
    message(sprintf("ACS data directory does not exist: %s", base_dir))
    return(data.frame(
      state = character(0),
      year_range = character(0),
      file_path = character(0),
      file_size_mb = numeric(0),
      file_date = character(0)
    ))
  }

  # Find all raw.feather files
  feather_files <- list.files(
    path = base_dir,
    pattern = "raw\\.feather$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (length(feather_files) == 0) {
    message("No ACS extracts found")
    return(data.frame(
      state = character(0),
      year_range = character(0),
      file_path = character(0),
      file_size_mb = numeric(0),
      file_date = character(0)
    ))
  }

  # Parse paths to extract state and year_range
  results <- lapply(feather_files, function(file_path) {
    # Split path: data/acs/{state}/{year_range}/raw.feather
    path_parts <- strsplit(file_path, .Platform$file.sep)[[1]]

    # Find "acs" in path
    acs_idx <- which(path_parts == "acs")

    if (length(acs_idx) > 0 && length(path_parts) >= acs_idx + 2) {
      state <- path_parts[acs_idx + 1]
      year_range <- path_parts[acs_idx + 2]

      # Get file info
      file_info <- file.info(file_path)

      data.frame(
        state = state,
        year_range = year_range,
        file_path = file_path,
        file_size_mb = round(file_info$size / (1024^2), 2),
        file_date = as.character(as.Date(file_info$mtime)),
        stringsAsFactors = FALSE
      )
    } else {
      NULL
    }
  })

  # Combine results
  results <- do.call(rbind, results[!sapply(results, is.null)])

  # Sort by state and year_range
  if (!is.null(results) && nrow(results) > 0) {
    results <- results[order(results$state, results$year_range), ]
    rownames(results) <- NULL
  }

  message(sprintf("Found %s ACS extract(s)", nrow(results)))

  return(results)
}


#' Get ACS variable names
#'
#' Extract variable names from loaded ACS data, optionally filtering
#' for specific patterns (e.g., attached characteristics).
#'
#' @param data data.frame. ACS data loaded via load_acs_feather()
#' @param pattern Character. Optional regex pattern to filter variables
#' @param exclude_metadata Logical. Exclude metadata columns (state, year_range, extract_date)?
#'   Default: TRUE
#'
#' @return Character vector of variable names
#'
#' @examples
#' \dontrun{
#' ne_acs <- load_acs_feather("nebraska", "2019-2023")
#'
#' # All IPUMS variables
#' all_vars <- get_acs_variable_names(ne_acs)
#'
#' # Only attached characteristics (_mom, _pop, _head)
#' attached_vars <- get_acs_variable_names(ne_acs, pattern = "_(mom|pop|head)$")
#'
#' # Education variables
#' educ_vars <- get_acs_variable_names(ne_acs, pattern = "^EDUC")
#' }
#'
#' @export
get_acs_variable_names <- function(data,
                                    pattern = NULL,
                                    exclude_metadata = TRUE) {

  var_names <- names(data)

  # Exclude metadata columns if requested
  if (exclude_metadata) {
    metadata_cols <- c("state", "year_range", "extract_date")
    var_names <- setdiff(var_names, metadata_cols)
  }

  # Apply pattern filter if provided
  if (!is.null(pattern)) {
    var_names <- grep(pattern, var_names, value = TRUE)
  }

  return(var_names)
}
