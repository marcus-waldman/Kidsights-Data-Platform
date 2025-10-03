#' NHIS Data Loading Module
#'
#' Load raw NHIS data from Feather files created by Python extraction pipeline.
#' Preserves all IPUMS variable names and coding schemes without transformation.
#'
#' @description
#' This module provides functions to load NHIS data extracted via IPUMS API.
#' **IMPORTANT**: No transformations or recoding are applied. All IPUMS variables
#' are preserved in original form (AGE, SEX, RACENEW, HISPETH, parent variables, etc.).
#'
#' @section Functions:
#' - load_nhis_feather(): Load raw NHIS data from Feather file
#' - get_nhis_file_path(): Construct path to NHIS Feather file
#' - list_available_nhis_extracts(): List available NHIS extracts
#'
#' @section Required Packages:
#' - arrow: For reading Feather files
#' - dplyr: For data manipulation
#'
#' @examples
#' \dontrun{
#' # Load NHIS 2019-2024 data
#' nhis_data <- load_nhis_feather("2019-2024")
#'
#' # Check structure
#' str(nhis_data)
#'
#' # List available extracts
#' list_available_nhis_extracts()
#' }


#' Get path to NHIS Feather file
#'
#' Construct file path for NHIS Feather data file based on year range.
#' Uses project structure: data/nhis/{year_range}/raw.feather
#'
#' @param year_range Character. Year range (e.g., "2019-2024")
#' @param base_dir Character. Base directory for NHIS data (default: "data/nhis")
#' @param filename Character. Feather filename (default: "raw.feather")
#'
#' @return Character. Full path to Feather file
#'
#' @examples
#' get_nhis_file_path("2019-2024")
#' # Returns: "data/nhis/2019-2024/raw.feather"
#'
#' @export
get_nhis_file_path <- function(year_range,
                                base_dir = "data/nhis",
                                filename = "raw.feather") {

  # Validate inputs
  if (missing(year_range) || is.null(year_range) || year_range == "") {
    stop("year_range argument is required and cannot be empty")
  }

  # Construct path
  file_path <- file.path(base_dir, year_range, filename)

  return(file_path)
}


#' Load NHIS data from Feather file
#'
#' Load raw NHIS data extracted from IPUMS API. Preserves all IPUMS variable
#' names and coding schemes without transformation. Adds metadata columns
#' for year_range and loaded_at timestamp.
#'
#' @param year_range Character. Year range for NHIS extract (e.g., "2019-2024")
#' @param base_dir Character. Base directory for NHIS data (default: "data/nhis")
#' @param add_metadata Logical. Add metadata columns (year_range, loaded_at)?
#'   Default: TRUE
#' @param validate Logical. Perform basic validation checks? Default: TRUE
#'
#' @return data.frame with raw IPUMS variables plus metadata columns
#'
#' @details
#' **IPUMS Variables Preserved:**
#' - All variables maintain original IPUMS names (AGE, SEX, RACENEW, HISPETH, etc.)
#' - Parent variables included directly (PAR1AGE, PAR2AGE, EDUCPARENT, etc.)
#' - IPUMS coding schemes unchanged
#' - Categorical variables loaded as R factors
#'
#' **Metadata Columns Added (if add_metadata=TRUE):**
#' - year_range: Year range of NHIS samples
#' - loaded_at: Timestamp when data was loaded
#'
#' **No Transformations Applied:**
#' - NO recoding of race/ethnicity
#' - NO harmonization with Kidsights variables
#' - NO derived variable creation
#' - Raw IPUMS data only
#'
#' @examples
#' \dontrun{
#' # Load NHIS 2019-2024 data
#' nhis_data <- load_nhis_feather("2019-2024")
#'
#' # Check dimensions
#' dim(nhis_data)
#'
#' # View variable names (all IPUMS originals)
#' names(nhis_data)
#'
#' # Check factor levels for SEX
#' levels(nhis_data$SEX)
#'
#' # Load without metadata columns
#' nhis_raw <- load_nhis_feather("2019-2024", add_metadata = FALSE)
#' }
#'
#' @export
load_nhis_feather <- function(year_range,
                               base_dir = "data/nhis",
                               add_metadata = TRUE,
                               validate = TRUE) {

  # Get file path
  file_path <- get_nhis_file_path(year_range, base_dir)

  # Check file exists
  if (!file.exists(file_path)) {
    stop(sprintf(
      "NHIS Feather file not found: %s\n\nPlease run extraction pipeline first:\n  python pipelines/python/nhis/extract_nhis_data.py --year-range %s",
      file_path,
      year_range
    ))
  }

  # Log loading
  message(sprintf("Loading NHIS data: %s", year_range))
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
    data$year_range <- year_range
    data$loaded_at <- as.character(Sys.time())

    message("  Added metadata columns: year_range, loaded_at")
  }

  # Basic validation if requested
  if (validate) {
    # Check for critical IPUMS variables
    critical_vars <- c("SERIAL", "PERNUM", "YEAR")
    missing_critical <- setdiff(critical_vars, names(data))

    if (length(missing_critical) > 0) {
      warning(sprintf(
        "Missing critical IPUMS variables: %s",
        paste(missing_critical, collapse = ", ")
      ))
    }

    # Check for duplicate person records
    if (all(c("SERIAL", "PERNUM") %in% names(data))) {
      n_dups <- sum(duplicated(data[, c("SERIAL", "PERNUM")]))
      if (n_dups > 0) {
        warning(sprintf(
          "Found %s duplicate SERIAL+PERNUM records",
          format(n_dups, big.mark = ",")
        ))
      }
    }

    # Check for sampling weight
    if ("SAMPWEIGHT" %in% names(data)) {
      n_missing_wt <- sum(is.na(data$SAMPWEIGHT) | data$SAMPWEIGHT <= 0)
      if (n_missing_wt > 0) {
        warning(sprintf(
          "%s records have missing or zero SAMPWEIGHT",
          format(n_missing_wt, big.mark = ",")
        ))
      }
    } else {
      warning("SAMPWEIGHT variable not found (required for survey analysis)")
    }

    # Check survey design variables
    design_vars <- c("STRATA", "PSU")
    missing_design <- setdiff(design_vars, names(data))
    if (length(missing_design) > 0) {
      warning(sprintf(
        "Missing survey design variables: %s (required for variance estimation)",
        paste(missing_design, collapse = ", ")
      ))
    }
  }

  message(sprintf("✓ NHIS data loaded successfully: %s", year_range))

  return(data)
}


#' List available NHIS extracts
#'
#' Scan data/nhis/ directory for available year range extracts.
#'
#' @param base_dir Character. Base directory for NHIS data (default: "data/nhis")
#'
#' @return data.frame with columns: year_range, file_path, file_size_mb, file_date
#'
#' @examples
#' \dontrun{
#' available <- list_available_nhis_extracts()
#' print(available)
#' }
#'
#' @export
list_available_nhis_extracts <- function(base_dir = "data/nhis") {

  if (!dir.exists(base_dir)) {
    message(sprintf("NHIS data directory does not exist: %s", base_dir))
    return(data.frame(
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
    message("No NHIS extracts found")
    return(data.frame(
      year_range = character(0),
      file_path = character(0),
      file_size_mb = numeric(0),
      file_date = character(0)
    ))
  }

  # Parse paths to extract year_range
  results <- lapply(feather_files, function(file_path) {
    # Split path: data/nhis/{year_range}/raw.feather
    path_parts <- strsplit(file_path, .Platform$file.sep)[[1]]

    # Find "nhis" in path
    nhis_idx <- which(path_parts == "nhis")

    if (length(nhis_idx) > 0 && length(path_parts) >= nhis_idx + 1) {
      year_range <- path_parts[nhis_idx + 1]

      # Get file info
      file_info <- file.info(file_path)

      data.frame(
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

  # Sort by year_range
  if (!is.null(results) && nrow(results) > 0) {
    results <- results[order(results$year_range), ]
    rownames(results) <- NULL
  }

  message(sprintf("Found %s NHIS extract(s)", nrow(results)))

  return(results)
}


#' Get NHIS variable names
#'
#' Extract variable names from loaded NHIS data, optionally filtering
#' for specific patterns (e.g., parent variables, mental health).
#'
#' @param data data.frame. NHIS data loaded via load_nhis_feather()
#' @param pattern Character. Optional regex pattern to filter variables
#' @param exclude_metadata Logical. Exclude metadata columns (year_range, loaded_at)?
#'   Default: TRUE
#'
#' @return Character vector of variable names
#'
#' @examples
#' \dontrun{
#' nhis_data <- load_nhis_feather("2019-2024")
#'
#' # All IPUMS variables
#' all_vars <- get_nhis_variable_names(nhis_data)
#'
#' # Only parent variables
#' parent_vars <- get_nhis_variable_names(nhis_data, pattern = "^PAR")
#'
#' # Mental health variables (GAD-7, PHQ-8)
#' mh_vars <- get_nhis_variable_names(nhis_data, pattern = "^(GAD|PHQ)")
#'
#' # ACE variables
#' ace_vars <- get_nhis_variable_names(nhis_data, pattern = "(VIOLEN|JAIL|MENTDEP|ALCDRUGEV)")
#' }
#'
#' @export
get_nhis_variable_names <- function(data,
                                     pattern = NULL,
                                     exclude_metadata = TRUE) {

  var_names <- names(data)

  # Exclude metadata columns if requested
  if (exclude_metadata) {
    metadata_cols <- c("year_range", "loaded_at")
    var_names <- setdiff(var_names, metadata_cols)
  }

  # Apply pattern filter if provided
  if (!is.null(pattern)) {
    var_names <- grep(pattern, var_names, value = TRUE)
  }

  return(var_names)
}
