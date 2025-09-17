#' Query and Filter Codebook Functions
#'
#' Functions for searching, filtering, and extracting information from the codebook

library(tidyverse)

#' Filter items by study
#'
#' @param codebook Codebook object
#' @param study Study name(s) to filter by
#' @return List of items that appear in the specified study/studies
#' @examples
#' \dontrun{
#' ne25_items <- filter_items_by_study(codebook, "NE25")
#' current_studies <- filter_items_by_study(codebook, c("NE25", "NE22"))
#' }
filter_items_by_study <- function(codebook, study) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  study <- as.character(study)
  filtered_items <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    if (any(study %in% item$studies)) {
      filtered_items[[item_id]] <- item
    }
  }

  return(filtered_items)
}

#' Filter items by domain
#'
#' @param codebook Codebook object
#' @param domain Domain name(s) to filter by
#' @param study_group Which study group domains to use: "kidsights" (default) or "cahmi"
#' @return List of items in the specified domain(s)
#' @examples
#' \dontrun{
#' motor_items <- filter_items_by_domain(codebook, "motor")
#' socemo_items <- filter_items_by_domain(codebook, "social_emotional", study_group = "cahmi")
#' }
filter_items_by_domain <- function(codebook, domain, study_group = "kidsights") {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  domain <- as.character(domain)
  filtered_items <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    item_domain <- if (study_group == "cahmi") {
      item$domains$cahmi$value
    } else {
      item$domains$kidsights$value
    }

    if (!is.null(item_domain) && item_domain %in% domain) {
      filtered_items[[item_id]] <- item
    }
  }

  return(filtered_items)
}

#' Search items by text content
#'
#' @param codebook Codebook object
#' @param pattern Search pattern (regular expression)
#' @param fields Which fields to search in (default: c("stems", "response_options"))
#' @param ignore_case Whether to ignore case (default: TRUE)
#' @return List of items matching the search pattern
#' @examples
#' \dontrun{
#' walking_items <- search_items(codebook, "walk")
#' emotion_items <- search_items(codebook, "happy|sad|angry")
#' }
search_items <- function(codebook, pattern,
                        fields = c("stems", "response_options"),
                        ignore_case = TRUE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  matched_items <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    found_match <- FALSE

    # Search in stems
    if ("stems" %in% fields && !is.null(item$content$stems)) {
      stem_text <- paste(unlist(item$content$stems), collapse = " ")
      if (grepl(pattern, stem_text, ignore.case = ignore_case)) {
        found_match <- TRUE
      }
    }

    # Search in response options
    if ("response_options" %in% fields && !is.null(item$content$response_options)) {
      for (study_responses in item$content$response_options) {
        if (is.list(study_responses)) {
          response_text <- paste(sapply(study_responses, function(x) x$label), collapse = " ")
          if (grepl(pattern, response_text, ignore.case = ignore_case)) {
            found_match <- TRUE
            break
          }
        }
      }
    }

    if (found_match) {
      matched_items[[item_id]] <- item
    }
  }

  return(matched_items)
}

#' Get single item by ID
#'
#' @param codebook Codebook object
#' @param item_id Item identifier (equate ID)
#' @return Single item or NULL if not found
#' @examples
#' \dontrun{
#' item <- get_item(codebook, "AA102")
#' }
get_item <- function(codebook, item_id) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  if (item_id %in% names(codebook$items)) {
    return(codebook$items[[item_id]])
  } else {
    warning("Item '", item_id, "' not found in codebook")
    return(NULL)
  }
}

#' Convert items list to data frame for analysis
#'
#' @param items List of items (from filter/search functions) or full codebook
#' @param flatten_identifiers Whether to create separate columns for each identifier (default: TRUE)
#' @return Data frame with item information
#' @examples
#' \dontrun{
#' motor_items <- filter_items_by_domain(codebook, "motor")
#' motor_df <- items_to_dataframe(motor_items)
#' }
items_to_dataframe <- function(items, flatten_identifiers = TRUE) {

  # Handle full codebook input
  if (inherits(items, "codebook")) {
    items <- items$items
  }

  if (length(items) == 0) {
    return(data.frame())
  }

  # Extract basic information
  df <- map_dfr(items, function(item) {
    data.frame(
      item_id = item$lexicons$equate %||% NA,
      id = item$id %||% NA,
      domain_kidsights = item$domains$kidsights$value %||% NA,
      domain_cahmi = item$domains$cahmi$value %||% NA,
      studies = paste(if(is.null(item$studies) || length(item$studies) == 0) "" else item$studies, collapse = ";"),
      stem_combined = item$content$stems$combined %||% NA,
      stem_ne25 = item$content$stems$ne25 %||% NA,
      stem_ne22 = item$content$stems$ne22 %||% NA,
      reverse = item$scoring$reverse %||% FALSE,
      calibration_item = item$psychometric$calibration_item %||% FALSE,
      has_irt_params = !is.null(item$psychometric$irt_parameters) &&
                      length(item$psychometric$irt_parameters) > 0 &&
                      any(sapply(item$psychometric$irt_parameters, function(x) {
                        length(x$factors) > 0 || length(x$loadings) > 0 || length(x$thresholds) > 0
                      })),
      has_response_opts = !is.null(item$content$response_options) &&
                         length(item$content$response_options) > 0,
      stringsAsFactors = FALSE
    )
  }, .id = "row_id")

  # Add flattened lexicons if requested
  if (flatten_identifiers) {
    lexicon_df <- map_dfr(items, function(item) {
      lexicons <- item$lexicons %||% list()
      # Ensure all lexicon columns exist
      standard_ids <- c("kidsight", "ne25", "ne22", "ne20", "cahmi22", "cahmi21",
                       "ecdi", "credi", "gsed")
      for (id_name in standard_ids) {
        if (!id_name %in% names(lexicons)) {
          lexicons[[id_name]] <- NA
        }
      }
      as.data.frame(lexicons, stringsAsFactors = FALSE)
    })

    # Combine with main data frame
    df <- bind_cols(df, lexicon_df %>% select(-equate))  # Remove duplicate equate (already in item_id)
  }

  return(df)
}

#' Get study coverage matrix
#'
#' @param codebook Codebook object
#' @return Matrix showing which items appear in which studies
#' @examples
#' \dontrun{
#' coverage <- get_study_coverage(codebook)
#' heatmap(coverage)
#' }
get_study_coverage <- function(codebook) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Get all items and studies
  item_ids <- names(codebook$items)
  all_studies <- unique(unlist(sapply(codebook$items, function(x) x$studies)))

  # Create matrix
  coverage_matrix <- matrix(0, nrow = length(item_ids), ncol = length(all_studies))
  rownames(coverage_matrix) <- item_ids
  colnames(coverage_matrix) <- all_studies

  # Fill matrix
  for (i in seq_along(item_ids)) {
    item_id <- item_ids[i]
    item_studies <- codebook$items[[item_id]]$studies
    if (!is.null(item_studies)) {
      coverage_matrix[item_id, item_studies] <- 1
    }
  }

  return(coverage_matrix)
}

#' Get domain × study crosstab
#'
#' @param codebook Codebook object
#' @param hrtl_domain Whether to use HRTL domain classification (default: FALSE)
#' @return Data frame with domain × study counts
#' @examples
#' \dontrun{
#' crosstab <- get_domain_study_crosstab(codebook)
#' }
get_domain_study_crosstab <- function(codebook, hrtl_domain = FALSE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Convert to data frame for easier manipulation
  df <- items_to_dataframe(codebook, flatten_identifiers = FALSE)

  # Parse studies column
  df$studies_list <- str_split(df$studies, ";")

  # Expand to long format
  df_long <- df %>%
    select(item_id, domain_kidsights, domain_cahmi, studies_list) %>%
    unnest(studies_list) %>%
    filter(studies_list != "")

  # Choose domain column
  domain_col <- if (hrtl_domain) "domain_cahmi" else "domain_kidsights"

  # Create crosstab
  crosstab <- df_long %>%
    count(.data[[domain_col]], studies_list, name = "n_items") %>%
    pivot_wider(names_from = studies_list, values_from = n_items, values_fill = 0)

  return(crosstab)
}

#' Get IRT parameters for an item by study
#' @param item Single item object
#' @param study Study name (default: NULL returns all studies)
#' @return IRT parameters for specified study or all studies
#' @examples
#' \\dontrun{
#' item <- get_item(codebook, "AA4")
#' ne25_irt <- get_irt_parameters(item, "NE25")
#' all_irt <- get_irt_parameters(item)
#' }
get_irt_parameters <- function(item, study = NULL) {
  if (is.null(item$psychometric$irt_parameters)) {
    return(NULL)
  }

  if (is.null(study)) {
    return(item$psychometric$irt_parameters)
  }

  if (study %in% names(item$psychometric$irt_parameters)) {
    return(item$psychometric$irt_parameters[[study]])
  } else {
    warning("Study '", study, "' not found in IRT parameters")
    return(NULL)
  }
}

#' Filter items that have IRT parameters for a specific study
#' @param codebook Codebook object
#' @param study Study name (default: NULL for any study)
#' @return Named list of items with IRT parameters
#' @examples
#' \\dontrun{
#' ne25_irt_items <- filter_items_with_irt(codebook, "NE25")
#' any_irt_items <- filter_items_with_irt(codebook)
#' }
filter_items_with_irt <- function(codebook, study = NULL) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  items_with_irt <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    irt_params <- item$psychometric$irt_parameters

    if (is.null(irt_params) || length(irt_params) == 0) {
      next
    }

    if (is.null(study)) {
      # Any study with parameters
      has_params <- any(sapply(irt_params, function(x) {
        length(x$factors) > 0 || length(x$loadings) > 0 || length(x$thresholds) > 0
      }))
      if (has_params) {
        items_with_irt[[item_id]] <- item
      }
    } else {
      # Specific study
      if (study %in% names(irt_params)) {
        study_params <- irt_params[[study]]
        has_params <- length(study_params$factors) > 0 ||
                     length(study_params$loadings) > 0 ||
                     length(study_params$thresholds) > 0
        if (has_params) {
          items_with_irt[[item_id]] <- item
        }
      }
    }
  }

  return(items_with_irt)
}

#' Get IRT parameter coverage matrix
#' @param codebook Codebook object
#' @return Matrix showing which items have IRT parameters for which studies
#' @examples
#' \\dontrun{
#' coverage <- get_irt_coverage(codebook)
#' }
get_irt_coverage <- function(codebook) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Get all items and all studies
  item_ids <- names(codebook$items)
  all_studies <- unique(unlist(lapply(codebook$items, function(x) names(x$psychometric$irt_parameters))))

  # Create matrix
  coverage_matrix <- matrix(FALSE, nrow = length(item_ids), ncol = length(all_studies))
  rownames(coverage_matrix) <- item_ids
  colnames(coverage_matrix) <- all_studies

  # Fill matrix
  for (item_id in item_ids) {
    item <- codebook$items[[item_id]]
    irt_params <- item$psychometric$irt_parameters

    if (!is.null(irt_params)) {
      for (study in names(irt_params)) {
        if (study %in% all_studies) {
          # Check if study has any actual parameters
          study_params <- irt_params[[study]]
          has_params <- length(study_params$factors) > 0 ||
                       length(study_params$loadings) > 0 ||
                       length(study_params$thresholds) > 0
          coverage_matrix[item_id, study] <- has_params
        }
      }
    }
  }

  return(coverage_matrix)
}

#' Helper operator for cleaner NA handling
`%||%` <- function(x, y) {
  if (is.null(x)) return(y)
  if (length(x) == 0) return(y)
  if (length(x) == 1 && is.na(x)) return(y)
  return(x)
}