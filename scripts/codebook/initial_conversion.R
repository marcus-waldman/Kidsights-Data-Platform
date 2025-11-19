#' Initial CSV to JSON Codebook Conversion
#'
#' This script performs the one-time conversion of the legacy CSV codebook
#' to the new JSON format with enhanced structure and metadata.

library(tidyverse)
library(jsonlite)
library(yaml)
library(lubridate)

# Load configuration
config <- read_yaml("config/codebook_config.yaml")

#' Detect if response options match a standard set, otherwise parse
#' @param resp_string String like "1 = Yes; 0 = No; -9 = Don't Know"
#' @return Either a string reference to response set or parsed options
detect_response_set_or_parse <- function(resp_string) {
  if (is.na(resp_string) || resp_string == "") {
    return(NULL)
  }

  # Check if it's a response set name (no "=" character, just alphanumeric + underscore)
  if (!stringr::str_detect(resp_string, "=")) {
    # It's a response set reference name - return as-is
    return(resp_string)
  }

  # Normalize the string for comparison - remove spaces and punctuation but keep letters
  normalized <- str_to_lower(str_replace_all(resp_string, "[[:space:]'\"]+", ""))

  # Check for standard binary pattern (Yes/No/Don't Know)
  if (str_detect(normalized, "1=yes") && str_detect(normalized, "0=no") && str_detect(normalized, "-9=")) {
    return("standard_binary")
  }

  # Check for 5-point Likert pattern
  if (str_detect(normalized, "1=never") && str_detect(normalized, "5=always")) {
    return("likert_5")
  }

  # Check for PS frequency pattern (Never or Almost Never; Sometimes; Often; Don't Know)
  if (str_detect(normalized, "0=neveroralmosnever") && str_detect(normalized, "1=sometimes") &&
      str_detect(normalized, "2=often") && str_detect(normalized, "-9=dontknow")) {
    return("ps_frequency")
  }

  # If no standard pattern detected, parse normally
  return(parse_response_options(resp_string))
}

#' Parse response options string into structured format
#' @param resp_string String like "1 = Yes; 0 = No; -9 = Don't Know"
#' @return List of response options
parse_response_options <- function(resp_string) {
  if (is.na(resp_string) || resp_string == "") {
    return(NULL)
  }

  # Split by semicolon and clean
  options <- str_split(resp_string, ";")[[1]]
  options <- str_trim(options)

  # Parse each option
  parsed_options <- map(options, function(opt) {
    if (str_detect(opt, "=")) {
      parts <- str_split(opt, "=", n = 2)[[1]]
      value <- str_trim(parts[1])
      label <- str_trim(parts[2])

      # Convert value to numeric if possible
      numeric_value <- suppressWarnings(as.numeric(value))
      if (!is.na(numeric_value)) {
        value <- numeric_value
      }

      # Check if it's a missing value indicator
      is_missing <- value %in% c(-9, -99, 9, 99) ||
                   str_detect(label, regex("don't know|missing|refuse", ignore_case = TRUE))

      result <- list(value = value, label = label)
      if (is_missing) {
        result$missing <- TRUE
      }

      return(result)
    }
    return(NULL)
  })

  # Remove NULL entries
  parsed_options[!sapply(parsed_options, is.null)]
}

#' Determine which studies an item appears in based on identifiers
#' @param item_row Single row from CSV
#' @return Character vector of study names
determine_studies <- function(item_row) {
  studies <- character()

  # Check each study identifier
  study_mappings <- list(
    NE25 = "lex_ne25",
    NE22 = "lex_ne22",
    NE20 = "lex_ne20",
    CAHMI22 = "lex_cahmi22",
    CAHMI21 = "lex_cahmi21",
    ECDI = "lex_ecdi",
    CREDI = "lex_credi",
    GSED = "lex_gsed"
  )

  for (study in names(study_mappings)) {
    column <- study_mappings[[study]]
    if (column %in% names(item_row) &&
        !is.na(item_row[[column]]) &&
        item_row[[column]] != "") {
      studies <- c(studies, study)
    }
  }

  return(studies)
}

#' Determine correct reverse coding for an item
#' @param item_row Single row from CSV data frame
#' @return Logical indicating if item should be reverse coded
determine_reverse_coding <- function(item_row) {
  # Items identified as needing reverse coding correction
  items_to_reverse <- c("DD221", "EG25a", "EG26a", "EG26b")

  # Check if this item needs reverse coding correction
  if (item_row$lex_equate %in% items_to_reverse) {
    return(TRUE)
  }

  # Otherwise use the original reverse coding from CSV
  return(as.logical(item_row$reverse %||% FALSE))
}

#' Create study-specific IRT parameters structure
#' @param studies Character vector of study names
#' @return List of IRT parameters by study with template structure
create_irt_parameters_by_study <- function(studies) {

  irt_params <- list()

  # Template structure for each study
  template <- list(
    factors = list(),     # Factor names for multidimensional models
    loadings = list(),    # Factor loadings (a-parameters)
    thresholds = list(),  # Difficulty/threshold parameters
    constraints = list()  # Parameter constraints for IRT calibration
  )

  # Create template for each study
  for (study in studies) {
    irt_params[[study]] <- template
  }

  return(irt_params)
}

#' Convert single CSV row to JSON item structure
#' @param item_row Single row from CSV data frame
#' @return List representing JSON item structure
convert_csv_row_to_json <- function(item_row) {

  # Base item structure
  item <- list(
    id = as.integer(item_row$jid),
    studies = determine_studies(item_row),

    lexicons = list(
      equate = item_row$lex_equate %||% NA,
      kidsight = item_row$lex_kidsight %||% NA,
      ne25 = item_row$lex_ne25 %||% NA,
      ne22 = item_row$lex_ne22 %||% NA,
      ne20 = item_row$lex_ne20 %||% NA,
      cahmi22 = item_row$lex_cahmi22 %||% NA,
      cahmi21 = item_row$lex_cahmi21 %||% NA,
      ecdi = item_row$lex_ecdi %||% NA,
      credi = item_row$lex_credi %||% NA,
      gsed = item_row$lex_gsed %||% NA
    ),

    content = list(
      stems = list(
        combined = item_row$stem_combined %||% NA,
        ne25 = item_row$stem_25 %||% NA,
        ne22 = item_row$stem_22 %||% NA
      ),
      response_options = list()
    ),

    domains = list(
      kidsights = list(
        value = item_row$domain3 %||% NA,
        studies = c("NE20", "NE22", "NE25")
      ),
      cahmi = list(
        value = item_row$domain_hrtl %||% NA,
        studies = c("CAHMI22", "CAHMI21")
      )
    ),

    age_range = c(0, 72),  # Default age range in months

    scoring = list(
      reverse = determine_reverse_coding(item_row),
      discrepancy = item_row$discrepancy %||% NA,
      equate_group = item_row$equate_group %||% NA
    ),

    psychometric = list(
      calibration_item = as.logical(item_row$hrtl_calibration_item %||% FALSE),
      param_constraints = item_row$param_constraints %||% NA,
      irt_parameters = create_irt_parameters_by_study(determine_studies(item_row)),
      sample_size = NA,
      calibration_date = NA
    ),

    metadata = list(
      added_date = as.character(today()),
      modified_date = as.character(today()),
      notes = NA
    )
  )

  # Parse response options with reference detection
  if (!is.na(item_row$resp_opts25) && item_row$resp_opts25 != "") {
    item$content$response_options$ne25 <- detect_response_set_or_parse(item_row$resp_opts25)
  }

  if (!is.na(item_row$resp_opts20) && item_row$resp_opts20 != "") {
    item$content$response_options$ne20 <- detect_response_set_or_parse(item_row$resp_opts20)
  }

  # Migrate param_constraints to NE25 param_constraints if present
  if (!is.na(item$psychometric$param_constraints) && "NE25" %in% item$studies) {
    item$psychometric$irt_parameters$NE25$param_constraints <- list(item$psychometric$param_constraints)
  }

  # Remove NA values to keep JSON clean
  item <- remove_na_recursive(item)

  return(item)
}

#' Remove NA values recursively from nested list
#' @param x List or vector
#' @return Clean list without NA values
remove_na_recursive <- function(x) {
  if (is.list(x)) {
    # Remove NA values and recursively clean sublists
    x <- x[!is.na(x)]
    lapply(x, remove_na_recursive)
  } else {
    x
  }
}

#' Parse PS items from CSV for GSED_PF study
#' @param ps_csv_path Path to PS items CSV file
#' @return List of PS items in codebook format
parse_ps_items <- function(ps_csv_path = "temp/archive_2025/ne25_ps_items.csv") {

  message("Parsing PS items from: ", ps_csv_path)

  # Read PS items CSV
  ps_data <- read_csv(ps_csv_path, show_col_types = FALSE)

  # Remove empty rows
  ps_data <- ps_data %>% filter(!is.na(lex_ne25))

  ps_items <- list()

  for (i in 1:nrow(ps_data)) {
    item_row <- ps_data[i, ]

    # Create PS item structure
    ps_item <- list(
      id = as.integer(i + 2000),  # Generate unique integer IDs starting at 2001
      studies = list("GSED_PF"),

      lexicons = list(
        equate = item_row$lex_ne25,  # Use lex_ne25 as primary identifier
        ne25 = item_row$lex_ne25
      ),

      domains = list(
        kidsights = list(
          value = "psychosocial_problems_general",
          studies = list("GSED_PF")
        )
      ),

      age_range = list(
        min_months = 0,
        max_months = 60,
        note = "Early childhood developmental assessment"
      ),

      content = list(
        stems = list(
          combined = item_row$stem
        ),
        response_options = list(
          gsed_pf = "ps_frequency"  # Reference to our new response set
        )
      ),

      scoring = list(
        reverse = FALSE,  # PS items are not reverse coded
        equate_group = "GSED_PF"
      ),

      psychometric = list(
        calibration_item = FALSE,
        irt_parameters = create_irt_parameters_by_study(list("GSED_PF"))
      ),

      metadata = list(
        tier_followup = as.integer(item_row$tier_followup),
        item_order = as.integer(item_row$item_order),
        last_modified = item_row$last_modified,
        type = item_row$type,
        notes = item_row$notes %||% ""
      )
    )

    # Clean NA values
    ps_item <- remove_na_recursive(ps_item)

    # Use lex_ne25 as the key
    ps_items[[item_row$lex_ne25]] <- ps_item
  }

  message("Parsed ", length(ps_items), " PS items")
  return(ps_items)
}

#' Main conversion function
#' @param csv_path Path to CSV file
#' @param json_path Path for output JSON file
convert_csv_to_json <- function(
  csv_path = "codebook/data/codebook.csv",
  json_path = "codebook/data/codebook.json"
) {

  message("Starting CSV to JSON conversion...")

  # Read CSV with proper encoding handling
  message("Reading CSV file: ", csv_path)

  # Try different encodings
  csv_data <- tryCatch({
    read_csv(csv_path, locale = locale(encoding = "UTF-8"))
  }, error = function(e) {
    message("UTF-8 failed, trying Windows-1252...")
    read_csv(csv_path, locale = locale(encoding = "Windows-1252"))
  })

  # Handle encoding issues by converting problematic characters
  csv_data <- csv_data %>%
    mutate(across(where(is.character), ~ {
      # Convert to UTF-8 and handle problematic characters
      cleaned <- iconv(.x, to = "UTF-8", sub = "")
      # Replace common problematic characters
      cleaned <- str_replace_all(cleaned, "â€™", "'")  # Smart quote
      cleaned <- str_replace_all(cleaned, "â€œ", '"')  # Opening quote
      cleaned <- str_replace_all(cleaned, "â€\u009d", '"')  # Closing quote
      cleaned <- str_replace_all(cleaned, "Â", "")     # Extra characters
      return(cleaned)
    }))

  message("Found ", nrow(csv_data), " items in CSV")

  # Convert each row
  message("Converting items...")
  items_list <- list()

  for (i in 1:nrow(csv_data)) {
    row <- csv_data[i, ]

    # Skip rows without equate identifier
    if (is.na(row$lex_equate) || row$lex_equate == "") {
      next
    }

    item_json <- convert_csv_row_to_json(row)
    items_list[[row$lex_equate]] <- item_json

    if (i %% 10 == 0) {
      message("Processed ", i, " items...")
    }
  }

  message("Converted ", length(items_list), " items")

  # Add PS items for GSED_PF study
  message("Adding PS items for GSED_PF study...")
  ps_items <- parse_ps_items()
  items_list <- c(items_list, ps_items)
  message("Added ", length(ps_items), " PS items")

  # Sort items by natural alphanumeric order
  message("Sorting items in natural alphanumeric order...")
  if (!require(gtools, quietly = TRUE)) {
    install.packages("gtools")
    library(gtools)
  }
  sorted_keys <- mixedsort(names(items_list))
  items_list <- items_list[sorted_keys]
  message("Items sorted by equate ID")

  # Create full JSON structure
  codebook_json <- list(
    metadata = list(
      version = "2.0",
      generated_date = as.character(now()),
      source_file = basename(csv_path),
      total_items = length(items_list),
      conversion_script = "scripts/codebook/initial_conversion.R"
    ),

    items = items_list,

    response_sets = config$response_sets,

    domains = list(
      socemo = list(
        label = "Social-Emotional",
        hrtl_label = "social_emotional",
        description = "Social and emotional development items"
      ),
      motor = list(
        label = "Motor",
        hrtl_label = "motor",
        description = "Gross and fine motor development"
      ),
      coglan = list(
        label = "Cognitive-Language",
        hrtl_label = "early_learning",
        description = "Cognitive and language development"
      )
    ),

    irt_models = list(
      configurations = list(
        primary_calibration = list(
          model_type = "multidimensional",
          dimensions = c("social_emotional", "cognitive", "motor", "self_regulation", "early_learning"),
          estimation_method = "MHRM",
          software = "mirt",
          version = "1.38"
        )
      )
    )
  )

  # Write JSON
  message("Writing JSON file: ", json_path)

  # Ensure directory exists
  dir.create(dirname(json_path), recursive = TRUE, showWarnings = FALSE)

  # Write with pretty formatting
  write_json(
    codebook_json,
    json_path,
    pretty = TRUE,
    auto_unbox = TRUE,
    na = "null"
  )

  message("Conversion complete!")
  message("JSON codebook written to: ", json_path)
  message("Total items: ", length(items_list))

  # Create backup of CSV in codebook directory
  csv_backup_path <- "codebook/data/codebook.csv"
  if (!file.exists(csv_backup_path)) {
    file.copy(csv_path, csv_backup_path)
    message("CSV backup created at: ", csv_backup_path)
  }

  return(json_path)
}

# Helper operator for cleaner NA handling
`%||%` <- function(x, y) if (is.na(x) || is.null(x) || x == "") y else x

# Run conversion if script is executed directly
if (!interactive()) {
  convert_csv_to_json()
}