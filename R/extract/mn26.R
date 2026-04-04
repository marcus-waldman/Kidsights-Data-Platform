# ==============================================================================
# MN26 REDCap Data Extraction Functions
# ==============================================================================
# Extracts data and dictionary from the Minnesota 2026 (MN26) REDCap project.
# Ported from kidsights-norc/progress-monitoring/mn26/utils/redcap_utils.R
# with adaptations for the Kidsights Data Platform pipeline architecture.
#
# Key differences from NE25 extraction:
#   - Single REDCap project (vs NE25's 4 projects)
#   - Uses exclude_hidden=TRUE for active dictionary (pipeline transforms)
#   - Also captures full dictionary for audit trail
# ==============================================================================

library(REDCapR)
library(httr)
library(dplyr)

#' Load MN26 API credentials from CSV file
#'
#' CSV format: project, pid, api_code
#'
#' @param csv_path Path to API credentials CSV file. If NULL, checks
#'   REDCAP_API_CREDENTIALS_PATH_MN26 env var, then falls back to config.
#' @param config Optional config list (from mn26.yaml) for fallback path
#' @return Data frame with credentials (project, pid, api_code columns)
load_mn26_credentials <- function(csv_path = NULL, config = NULL) {

  # Resolve credentials path
  if (is.null(csv_path)) {
    csv_path <- Sys.getenv("REDCAP_API_CREDENTIALS_PATH_MN26", "")
    if (csv_path == "" && !is.null(config)) {
      csv_path <- config$redcap$api_credentials_file
    }
  }

  if (is.null(csv_path) || csv_path == "" || !file.exists(csv_path)) {
    stop("MN26 API credentials file not found. Set REDCAP_API_CREDENTIALS_PATH_MN26 ",
         "in .env or provide csv_path argument.\n  Tried: ", csv_path)
  }

  credentials <- read.csv(csv_path, stringsAsFactors = FALSE)

  required_cols <- c("project", "pid", "api_code")
  missing_cols <- setdiff(required_cols, names(credentials))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in credentials file: ",
         paste(missing_cols, collapse = ", "))
  }

  message("[OK] Loaded ", nrow(credentials), " MN26 API credential(s)")
  return(credentials)
}

#' Extract MN26 data dictionary from REDCap API
#'
#' Pulls the metadata (data dictionary) from the MN26 REDCap project.
#' Returns a named list keyed by field_name.
#'
#' @param redcap_url REDCap API URL
#' @param token API token
#' @param exclude_hidden Logical, whether to exclude @HIDDEN fields (default TRUE)
#' @return Named list where each element is a field's metadata
extract_mn26_dictionary <- function(redcap_url, token, exclude_hidden = TRUE) {

  resp <- httr::POST(
    redcap_url,
    body = list(token = token, content = "metadata",
                format = "json", returnFormat = "json"),
    encode = "form"
  )

  if (httr::status_code(resp) != 200) {
    stop("REDCap metadata API error: HTTP ", httr::status_code(resp))
  }

  dict_list <- httr::content(resp)

  if (exclude_hidden) {
    dict_list <- Filter(function(d) {
      ann <- d$field_annotation
      is.null(ann) || !grepl("@HIDDEN", ann)
    }, dict_list)
  }

  dict_named <- list()
  for (d in dict_list) {
    dict_named[[d$field_name]] <- d
  }

  message("[OK] MN26 dictionary: ", length(dict_named), " fields",
          if (exclude_hidden) " (after excluding @HIDDEN)" else "")
  return(dict_named)
}

#' Convert dictionary list to data frame
#'
#' @param dict_list Named list from extract_mn26_dictionary()
#' @return Data frame with standard REDCap dictionary columns
dictionary_to_dataframe <- function(dict_list) {
  rows <- lapply(names(dict_list), function(fname) {
    d <- dict_list[[fname]]
    data.frame(
      field_name      = fname,
      form_name       = if (is.null(d$form_name)) NA_character_ else d$form_name,
      section_header  = if (is.null(d$section_header)) NA_character_ else d$section_header,
      field_type      = if (is.null(d$field_type)) NA_character_ else d$field_type,
      field_label     = if (is.null(d$field_label)) NA_character_ else d$field_label,
      select_choices_or_calculations = if (is.null(d$select_choices_or_calculations)) NA_character_ else d$select_choices_or_calculations,
      field_note      = if (is.null(d$field_note)) NA_character_ else d$field_note,
      text_validation_type_or_show_slider_number = if (is.null(d$text_validation_type_or_show_slider_number)) NA_character_ else d$text_validation_type_or_show_slider_number,
      text_validation_min = if (is.null(d$text_validation_min)) NA_character_ else d$text_validation_min,
      text_validation_max = if (is.null(d$text_validation_max)) NA_character_ else d$text_validation_max,
      identifier      = if (is.null(d$identifier)) NA_character_ else d$identifier,
      branching_logic = if (is.null(d$branching_logic)) NA_character_ else d$branching_logic,
      required_field  = if (is.null(d$required_field)) NA_character_ else d$required_field,
      field_annotation = if (is.null(d$field_annotation)) NA_character_ else d$field_annotation,
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

#' Extract MN26 data from REDCap API
#'
#' Pulls raw data from one or more MN26 REDCap projects. Supports multi-project
#' extraction with dictionary validation across projects.
#'
#' @param credentials Data frame from load_mn26_credentials()
#' @param redcap_url REDCap API URL (default: UNMC REDCap)
#' @param timeout Connection timeout in seconds (default: 300)
#' @return List with $data (combined data frame), $dictionary (active fields),
#'   $dictionary_full (including @HIDDEN), $extraction_metadata
extract_mn26_data <- function(credentials,
                              redcap_url = "https://unmcredcap.unmc.edu/redcap/api/",
                              timeout = 300) {

  message("Extracting MN26 data from REDCap API...")
  message("  REDCap URL: ", redcap_url)
  message("  Projects: ", nrow(credentials))

  all_data <- list()
  all_dicts <- list()
  all_dicts_full <- list()

  for (i in 1:nrow(credentials)) {
    project_name <- credentials$project[i]
    api_token    <- credentials$api_code[i]
    project_pid  <- credentials$pid[i]

    message("  Extracting: ", project_name, " (PID ", project_pid, ")")

    # Pull data
    result <- tryCatch({
      REDCapR::redcap_read(
        redcap_uri = redcap_url,
        token = api_token,
        raw_or_label = "raw",
        raw_or_label_headers = "raw",
        export_checkbox_label = FALSE,
        export_survey_fields = TRUE,
        export_data_access_groups = FALSE,
        config_options = list(connecttimeout = timeout, timeout = timeout)
      )
    }, error = function(e) {
      warning("Failed to extract from ", project_name, ": ", e$message)
      return(NULL)
    })

    if (is.null(result) || !result$success) {
      warning("Skipping project: ", project_name)
      next
    }

    # Add metadata columns
    project_data <- result$data %>%
      dplyr::mutate(
        source_project = project_name,
        pid = as.character(project_pid),
        retrieved_date = Sys.time(),
        extraction_id = paste0("mn26_", format(Sys.time(), "%Y%m%d_%H%M%S"))
      )

    all_data[[project_name]] <- project_data
    message("    [OK] ", nrow(project_data), " records, ", ncol(project_data), " columns")

    # Pull dictionaries (active and full)
    dict_active <- tryCatch(
      extract_mn26_dictionary(redcap_url, api_token, exclude_hidden = TRUE),
      error = function(e) { warning("Dict pull failed: ", e$message); NULL }
    )
    dict_full <- tryCatch(
      extract_mn26_dictionary(redcap_url, api_token, exclude_hidden = FALSE),
      error = function(e) { warning("Full dict pull failed: ", e$message); NULL }
    )

    if (!is.null(dict_active)) all_dicts[[project_name]] <- dict_active
    if (!is.null(dict_full)) all_dicts_full[[project_name]] <- dict_full

    # Brief pause between projects
    if (i < nrow(credentials)) Sys.sleep(1)
  }

  if (length(all_data) == 0) {
    stop("No data retrieved from any MN26 REDCap project")
  }

  # Combine data from all projects
  combined_data <- dplyr::bind_rows(all_data)

  # Ensure ZIP codes are character (preserve leading zeros)
  if ("sq001" %in% names(combined_data)) {
    combined_data$sq001 <- as.character(combined_data$sq001)
  }

  message("[OK] MN26 extraction complete: ", nrow(combined_data), " records, ",
          ncol(combined_data), " columns")

  return(list(
    data            = combined_data,
    dictionary      = if (length(all_dicts) > 0) all_dicts[[1]] else list(),
    dictionary_full = if (length(all_dicts_full) > 0) all_dicts_full[[1]] else list(),
    extraction_metadata = list(
      extracted_at = Sys.time(),
      projects     = credentials$project,
      n_records    = nrow(combined_data),
      n_columns    = ncol(combined_data)
    )
  ))
}
