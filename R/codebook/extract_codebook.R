#' Codebook Data Extraction Functions
#'
#' Functions for extracting and transforming codebook data into analysis-ready dataframes
#'
#' @name extract_codebook
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Required libraries with explicit namespacing
library(tidyverse)
library(purrr)

#' Extract lexicon crosswalk dataframe
#'
#' Creates a tidy dataframe mapping item IDs across different lexicons/studies.
#' Useful for creating crosswalk tables between different study naming conventions.
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param studies Optional character vector to filter by specific studies
#' @param include_missing Logical, whether to include items with missing lexicon mappings (default: TRUE)
#' @return A tibble with columns: lex_equate, equate, ne25, ne22, ne20, credi, gsed, kidsight
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get full crosswalk
#' crosswalk <- codebook_extract_lexicon_crosswalk(codebook)
#'
#' # Get crosswalk for specific studies
#' ne_crosswalk <- codebook_extract_lexicon_crosswalk(codebook, studies = c("NE25", "NE22"))
#' }
#' @export
codebook_extract_lexicon_crosswalk <- function(codebook, studies = NULL, include_missing = TRUE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object created with load_codebook()")
  }

  items_list <- codebook$items

  # Extract lexicon mappings for all items
  lexicon_data <- purrr::map_df(names(items_list), function(item_id) {
    item <- items_list[[item_id]]
    lexicons <- item$lexicons

    # Extract all available lexicon fields
    tibble::tibble(
      lex_equate = item_id,
      equate = lexicons$equate %||% NA_character_,
      kidsight = lexicons$kidsight %||% NA_character_,
      ne25 = lexicons$ne25 %||% NA_character_,
      ne22 = lexicons$ne22 %||% NA_character_,
      ne20 = lexicons$ne20 %||% NA_character_,
      credi = lexicons$credi %||% NA_character_,
      gsed = lexicons$gsed %||% NA_character_
    )
  })

  # Filter by studies if specified
  if (!is.null(studies)) {
    # Get items that appear in the specified studies
    study_items <- purrr::map(names(items_list), function(item_id) {
      item <- items_list[[item_id]]
      if (any(studies %in% item$studies)) {
        return(item_id)
      }
      return(NULL)
    }) %>%
      purrr::compact() %>%
      unlist()

    lexicon_data <- lexicon_data %>%
      dplyr::filter(lex_equate %in% study_items)
  }

  # Remove rows with all missing lexicons if requested
  if (!include_missing) {
    lexicon_data <- lexicon_data %>%
      dplyr::filter(!dplyr::if_all(c(equate, kidsight, ne25, ne22, ne20, credi, gsed), is.na))
  }

  return(lexicon_data)
}

#' Extract IRT parameters for a specific study
#'
#' Extracts IRT parameters (discriminations, thresholds) for items in a study.
#' Handles both unidimensional and multidimensional (bifactor) models.
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param study Character string specifying the study (e.g., "NE22", "NE25")
#' @param format Character string: "long" (default) or "wide" format output
#' @param include_empty Logical, whether to include items without parameters (default: FALSE)
#' @return A tibble with IRT parameters. Long format: lex_equate, study, factor, loading, threshold_num, threshold_value. Wide format: lex_equate, study, factor_1...factor_n, loading_1...loading_n, threshold_1...threshold_n.
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get NE22 parameters in long format
#' ne22_params <- codebook_extract_irt_parameters(codebook, "NE22")
#'
#' # Get parameters in wide format for analysis
#' ne22_wide <- codebook_extract_irt_parameters(codebook, "NE22", format = "wide")
#' }
#' @export
codebook_extract_irt_parameters <- function(codebook, study, format = "long", include_empty = FALSE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object created with load_codebook()")
  }

  if (length(study) != 1) {
    stop("Please specify exactly one study")
  }

  items_list <- codebook$items

  # Extract IRT parameters for the specified study
  irt_data <- purrr::map_df(names(items_list), function(item_id) {
    item <- items_list[[item_id]]

    # Check if item appears in the study
    if (!study %in% item$studies) {
      return(NULL)
    }

    # Get IRT parameters for this study
    irt_params <- item$psychometric$irt_parameters[[study]]

    if (is.null(irt_params) || (length(irt_params$factors) == 0 && !include_empty)) {
      return(NULL)
    }

    # Handle case where parameters exist
    if (length(irt_params$factors) > 0) {
      # Create long format data
      n_factors <- length(irt_params$factors)
      n_thresholds <- length(irt_params$thresholds)

      # Base data
      base_data <- tibble::tibble(
        lex_equate = item_id,
        study = study,
        factor = irt_params$factors,
        loading = irt_params$loadings[1:n_factors]
      )

      # Add thresholds (expand to match factors if needed)
      if (n_thresholds > 0) {
        # For each factor, add all thresholds
        expanded_data <- purrr::map_df(1:n_factors, function(f) {
          purrr::map_df(1:n_thresholds, function(t) {
            tibble::tibble(
              lex_equate = item_id,
              study = study,
              factor = irt_params$factors[f],
              loading = irt_params$loadings[f],
              threshold_num = t,
              threshold_value = irt_params$thresholds[t]
            )
          })
        })
        return(expanded_data)
      } else {
        # No thresholds, just return factor/loading info
        base_data %>%
          dplyr::mutate(
            threshold_num = NA_integer_,
            threshold_value = NA_real_
          )
      }
    } else if (include_empty) {
      # Return empty row for items without parameters
      tibble::tibble(
        lex_equate = item_id,
        study = study,
        factor = NA_character_,
        loading = NA_real_,
        threshold_num = NA_integer_,
        threshold_value = NA_real_
      )
    }
  }) %>%
    dplyr::bind_rows()

  # Convert to wide format if requested
  if (format == "wide") {
    # First get unique combinations of lex_equate and study
    irt_data <- irt_data %>%
      dplyr::group_by(lex_equate, study) %>%
      dplyr::summarise(
        factors = list(unique(factor[!is.na(factor)])),
        loadings = list(unique(loading[!is.na(loading)])),
        thresholds = list(unique(threshold_value[!is.na(threshold_value)])),
        .groups = "drop"
      )

    # Determine max factors and thresholds to avoid empty columns
    max_factors <- max(purrr::map_int(irt_data$factors, length), na.rm = TRUE)
    max_thresholds <- max(purrr::map_int(irt_data$thresholds, length), na.rm = TRUE)

    # Handle edge case where all values are empty
    if (!is.finite(max_factors)) max_factors <- 0
    if (!is.finite(max_thresholds)) max_thresholds <- 0

    # Create wide format with proper column ordering
    irt_data <- irt_data %>%
      dplyr::rowwise() %>%
      dplyr::mutate(
        # Create factor columns (only if max_factors > 0)
        factor_1 = if (max_factors >= 1 && length(factors) >= 1) factors[[1]][1] else NA_character_,
        factor_2 = if (max_factors >= 2 && length(factors) >= 2) factors[[1]][2] else NA_character_,
        factor_3 = if (max_factors >= 3 && length(factors) >= 3) factors[[1]][3] else NA_character_,

        # Create loading columns (only if max_factors > 0)
        loading_1 = if (max_factors >= 1 && length(loadings) >= 1) loadings[[1]][1] else NA_real_,
        loading_2 = if (max_factors >= 2 && length(loadings) >= 2) loadings[[1]][2] else NA_real_,
        loading_3 = if (max_factors >= 3 && length(loadings) >= 3) loadings[[1]][3] else NA_real_,

        # Create threshold columns (only if max_thresholds > 0)
        threshold_1 = if (max_thresholds >= 1 && length(thresholds) >= 1) thresholds[[1]][1] else NA_real_,
        threshold_2 = if (max_thresholds >= 2 && length(thresholds) >= 2) thresholds[[1]][2] else NA_real_,
        threshold_3 = if (max_thresholds >= 3 && length(thresholds) >= 3) thresholds[[1]][3] else NA_real_
      ) %>%
      dplyr::select(-factors, -loadings, -thresholds) %>%
      dplyr::ungroup()

    # Remove columns that are all NA
    all_na_cols <- purrr::map_lgl(irt_data, ~ all(is.na(.x)))
    irt_data <- irt_data[, !all_na_cols]
  }

  return(irt_data)
}

#' Extract response sets information
#'
#' Creates a dataframe of response options for items, including value labels and missing data flags.
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param study Optional character string to filter by specific study
#' @param response_set Optional character string to filter by specific response set name
#' @return A tibble with columns: lex_equate, study, response_set, value, label, missing
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get all response sets
#' response_data <- codebook_extract_response_sets(codebook)
#'
#' # Get response sets for NE25 only
#' ne25_responses <- codebook_extract_response_sets(codebook, study = "NE25")
#'
#' # Get specific response set
#' binary_responses <- codebook_extract_response_sets(codebook, response_set = "standard_binary_ne25")
#' }
#' @export
codebook_extract_response_sets <- function(codebook, study = NULL, response_set = NULL) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object created with load_codebook()")
  }

  items_list <- codebook$items
  response_sets <- codebook$response_sets

  # Extract response options for each item
  response_data <- purrr::map_df(names(items_list), function(item_id) {
    item <- items_list[[item_id]]
    response_options <- item$content$response_options

    if (is.null(response_options) || length(response_options) == 0) {
      return(NULL)
    }

    # For each study that has response options defined
    purrr::map_df(names(response_options), function(study_name) {
      response_set_name <- response_options[[study_name]]

      # Skip if empty or is a list (some items have inline arrays)
      if (is.null(response_set_name) || length(response_set_name) == 0 || is.list(response_set_name)) {
        return(NULL)
      }

      # Convert to character if needed
      response_set_name <- as.character(response_set_name)

      # Get the response set definition
      response_set_def <- response_sets[[response_set_name]]

      if (is.null(response_set_def)) {
        # Handle inline response options (should be rare after v2.8.0)
        return(tibble::tibble(
          lex_equate = item_id,
          study = study_name,
          response_set = "inline",
          value = NA_integer_,
          label = NA_character_,
          missing = NA
        ))
      }

      # Extract response options
      purrr::map_df(response_set_def, function(option) {
        tibble::tibble(
          lex_equate = item_id,
          study = study_name,
          response_set = response_set_name,
          value = option$value,
          label = option$label,
          missing = option$missing %||% FALSE
        )
      })
    })
  }) %>%
    dplyr::bind_rows()

  # Filter by study if specified (case-insensitive)
  if (!is.null(study)) {
    response_data <- response_data %>%
      dplyr::filter(tolower(study) %in% tolower(!!study))
  }

  # Filter by response set if specified
  if (!is.null(response_set)) {
    response_data <- response_data %>%
      dplyr::filter(response_set %in% !!response_set)
  }

  return(response_data)
}

#' Extract item stems and metadata
#'
#' Creates a dataframe with item stems, domains, age ranges, and other content metadata.
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param studies Optional character vector to filter by specific studies
#' @param domains Optional character vector to filter by specific domains
#' @param study_group Which study group domains to use: "kidsights" (default) or "cahmi"
#' @return A tibble with columns: lex_equate, studies, stem, domain, age_min, age_max, reverse_scored
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get all item stems
#' item_stems <- codebook_extract_item_stems(codebook)
#'
#' # Get stems for motor domain items
#' motor_stems <- codebook_extract_item_stems(codebook, domains = "motor")
#'
#' # Get stems for NE25 items
#' ne25_stems <- codebook_extract_item_stems(codebook, studies = "NE25")
#' }
#' @export
codebook_extract_item_stems <- function(codebook, studies = NULL, domains = NULL, study_group = "kidsights") {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object created with load_codebook()")
  }

  items_list <- codebook$items

  # Extract content for all items
  content_data <- purrr::map_df(names(items_list), function(item_id) {
    item <- items_list[[item_id]]

    # Get domain information
    domain_info <- item$domains[[study_group]]
    domain_value <- if (is.list(domain_info$value)) {
      paste(domain_info$value, collapse = "; ")
    } else {
      domain_info$value %||% NA_character_
    }

    # Get age range
    age_range <- item$age_range
    age_min <- if (is.list(age_range)) {
      age_range$min_months %||% NA_integer_
    } else if (is.numeric(age_range) && length(age_range) >= 1) {
      age_range[1]
    } else {
      NA_integer_
    }

    age_max <- if (is.list(age_range)) {
      age_range$max_months %||% NA_integer_
    } else if (is.numeric(age_range) && length(age_range) >= 2) {
      age_range[2]
    } else {
      NA_integer_
    }

    # Get combined stem
    stem <- item$content$stems$combined %||%
            item$content$stems$ne25 %||%
            item$content$stems$ne22 %||%
            NA_character_

    # Create result
    tibble::tibble(
      lex_equate = item_id,
      studies = list(item$studies),
      stem = stem,
      domain = domain_value,
      age_min = age_min,
      age_max = age_max,
      reverse_scored = item$scoring$reverse %||% FALSE
    )
  })

  # Filter by studies if specified
  if (!is.null(studies)) {
    content_data <- content_data %>%
      dplyr::filter(purrr::map_lgl(studies, ~ any(.x %in% !!studies)))
  }

  # Filter by domains if specified
  if (!is.null(domains)) {
    content_data <- content_data %>%
      dplyr::filter(stringr::str_detect(domain, paste(domains, collapse = "|")))
  }

  # Expand studies list to character vector for easier viewing
  content_data <- content_data %>%
    dplyr::mutate(studies = purrr::map_chr(studies, ~ paste(.x, collapse = ", ")))

  return(content_data)
}

#' Extract study summary statistics
#'
#' Creates summary statistics for a study including item counts, domain coverage, and parameter availability.
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param study Character string specifying the study (e.g., "NE22", "NE25")
#' @param study_group Which study group domains to use: "kidsights" (default) or "cahmi"
#' @return A tibble with summary statistics for the study
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get NE25 summary
#' ne25_summary <- codebook_extract_study_summary(codebook, "NE25")
#'
#' # Get all studies summaries
#' all_studies <- c("NE25", "NE22", "NE20", "CREDI", "GSED")
#' summaries <- purrr::map_df(all_studies, ~ codebook_extract_study_summary(codebook, .x))
#' }
#' @export
codebook_extract_study_summary <- function(codebook, study, study_group = "kidsights") {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object created with load_codebook()")
  }

  if (length(study) != 1) {
    stop("Please specify exactly one study")
  }

  items_list <- codebook$items

  # Get items for this study
  study_items <- purrr::keep(items_list, ~ study %in% .x$studies)

  if (length(study_items) == 0) {
    warning(paste("No items found for study:", study))
    return(tibble::tibble(
      study = study,
      total_items = 0L,
      items_with_irt = 0L,
      items_with_thresholds = 0L,
      domains = NA_character_,
      response_sets = NA_character_
    ))
  }

  # Count items with IRT parameters
  items_with_irt <- sum(purrr::map_lgl(study_items, function(item) {
    irt_params <- item$psychometric$irt_parameters[[study]]
    !is.null(irt_params) && length(irt_params$factors) > 0
  }))

  # Count items with thresholds
  items_with_thresholds <- sum(purrr::map_lgl(study_items, function(item) {
    irt_params <- item$psychometric$irt_parameters[[study]]
    !is.null(irt_params) && length(irt_params$thresholds) > 0
  }))

  # Get unique domains
  domains <- purrr::map(study_items, function(item) {
    domain_info <- item$domains[[study_group]]
    if (is.list(domain_info$value)) {
      domain_info$value
    } else {
      domain_info$value
    }
  }) %>%
    purrr::compact() %>%
    unlist() %>%
    unique() %>%
    sort()

  # Get unique response sets
  response_sets <- purrr::map(study_items, function(item) {
    response_options <- item$content$response_options
    response_options[[study]]
  }) %>%
    purrr::compact() %>%
    unlist() %>%
    unique() %>%
    sort()

  # Create summary
  tibble::tibble(
    study = study,
    total_items = length(study_items),
    items_with_irt = items_with_irt,
    items_with_thresholds = items_with_thresholds,
    irt_coverage = round(items_with_irt / length(study_items), 3),
    threshold_coverage = round(items_with_thresholds / length(study_items), 3),
    domains = paste(domains, collapse = ", "),
    n_domains = length(domains),
    response_sets = paste(response_sets, collapse = ", "),
    n_response_sets = length(response_sets)
  )
}

#' Pivot IRT parameters to wide format
#'
#' Convenience function to convert IRT parameters from long to wide format for analysis.
#' This is a wrapper around codebook_extract_irt_parameters with format="wide".
#'
#' @param codebook Codebook object loaded with load_codebook()
#' @param study Character string specifying the study (e.g., "NE22", "NE25")
#' @param max_factors Maximum number of factors to include as columns (default: 3)
#' @param max_thresholds Maximum number of thresholds to include as columns (default: 5)
#' @return A tibble with IRT parameters in wide format
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' # Get NE22 parameters in wide format
#' ne22_wide <- codebook_pivot_irt_to_wide(codebook, "NE22")
#' }
#' @export
codebook_pivot_irt_to_wide <- function(codebook, study, max_factors = 3, max_thresholds = 5) {
  # This is a convenience wrapper
  codebook_extract_irt_parameters(codebook, study, format = "wide", include_empty = TRUE)
}