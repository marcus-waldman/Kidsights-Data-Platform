#' REDCap API Utilities
#'
#' Functions for loading API credentials and extracting data from REDCap projects.

#' Load API credentials from CSV file
#'
#' CSV format: project, pid, api_code
#'
#' @param csv_path Path to API credentials CSV file
#' @return Data frame with credentials
load_api_credentials <- function(csv_path) {

  if (!file.exists(csv_path)) {
    stop(paste("API credentials file not found:", csv_path))
  }

  credentials <- read.csv(csv_path, stringsAsFactors = FALSE)

  required_cols <- c("project", "pid", "api_code")
  missing_cols <- setdiff(required_cols, names(credentials))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in credentials file:", paste(missing_cols, collapse = ", ")))
  }

  message("[OK] Loaded ", nrow(credentials), " API credential(s)")
  return(credentials)
}

#' Pull raw data from REDCap API
#'
#' Uses the same API parameters as the NE25 pipeline for reliable extraction.
#'
#' [MN26 TODO] Update redcap_url to MN26 project URL once available
#'
#' @param credentials API credentials data frame
#' @param redcap_url REDCap API URL
#' @return List with $data (combined data frame) and $dictionary (from first project)
pull_redcap_data <- function(credentials, redcap_url) {

  message("Pulling data from REDCap API...")
  message("REDCap URL: ", redcap_url)

  all_data <- list()
  all_dictionaries <- list()

  for (i in 1:nrow(credentials)) {
    project_name <- credentials$project[i]
    api_token <- credentials$api_code[i]

    message("  - Extracting from project: ", project_name)

    # Use redcap_read() with NE25 pipeline parameters (not redcap_read_oneshot)
    result <- tryCatch({
      REDCapR::redcap_read(
        redcap_uri = redcap_url,
        token = api_token,
        raw_or_label = "raw",
        raw_or_label_headers = "raw",
        export_checkbox_label = FALSE,
        export_survey_fields = TRUE,
        export_data_access_groups = FALSE,
        config_options = list(connecttimeout = 300, timeout = 300)
      )
    }, error = function(e) {
      warning("Failed to pull from ", project_name, ": ", e$message)
      return(NULL)
    })

    if (is.null(result) || !result$success) {
      warning("Skipping project: ", project_name)
      next
    }

    # Add source project metadata
    project_data <- result$data %>%
      dplyr::mutate(source_project = project_name)

    all_data[[project_name]] <- project_data

    # Also pull the data dictionary (metadata) for the first project
    if (length(all_dictionaries) == 0) {
      dict_result <- tryCatch({
        resp <- httr::POST(
          redcap_url,
          body = list(token = api_token, content = "metadata",
                      format = "json", returnFormat = "json"),
          encode = "form"
        )
        dict_list <- httr::content(resp)
        dict_named <- list()
        for (d in dict_list) {
          dict_named[[d$field_name]] <- d
        }
        dict_named
      }, error = function(e) {
        warning("Could not pull data dictionary: ", e$message)
        NULL
      })
      all_dictionaries <- dict_result
    }

    message("    [OK] Retrieved ", nrow(project_data), " records")

    # Brief pause between projects
    Sys.sleep(1)
  }

  if (length(all_data) == 0) {
    stop("No data retrieved from any REDCap projects")
  }

  combined_data <- dplyr::bind_rows(all_data)
  message("[OK] Total records across all projects: ", nrow(combined_data))

  return(list(data = combined_data, dictionary = all_dictionaries))
}
