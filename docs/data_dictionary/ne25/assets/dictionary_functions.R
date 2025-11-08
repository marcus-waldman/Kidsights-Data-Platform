# NE25 Interactive Data Dictionary Functions
# Functions to extract and format data dictionary information from JSON file
# Updated to use JSON source instead of direct database connections

library(dplyr)
library(DT)
library(knitr)
library(tidyr)
library(jsonlite)

# Load data dictionary from JSON file
load_dictionary_json <- function(json_path = "ne25_dictionary.json") {
  # Load the comprehensive data dictionary from JSON file
  #
  # Args:
  #   json_path: Path to the ne25_dictionary.json file
  #
  # Returns:
  #   List containing all dictionary data and metadata

  # Try multiple possible paths for the JSON file
  possible_paths <- c(
    json_path,
    file.path("ne25_dictionary.json"),
    file.path("docs", "data_dictionary", "ne25", "ne25_dictionary.json"),
    file.path("..", "..", "..", "docs", "data_dictionary", "ne25", "ne25_dictionary.json")
  )

  json_file <- NULL
  for (path in possible_paths) {
    if (file.exists(path)) {
      json_file <- path
      break
    }
  }

  if (is.null(json_file)) {
    stop("JSON dictionary file not found. Tried paths: ", paste(possible_paths, collapse = ", "))
  }

  tryCatch({
    cat("[INFO] Loading dictionary from:", json_file, "\n")
    dict_data <- jsonlite::fromJSON(json_file, simplifyDataFrame = TRUE)

    # Validate JSON structure
    required_sections <- c("metadata", "raw_variables", "transformed_variables",
                          "variable_project_matrix", "transformation_mappings")
    missing_sections <- setdiff(required_sections, names(dict_data))

    if (length(missing_sections) > 0) {
      warning("JSON file missing sections: ", paste(missing_sections, collapse = ", "))
    }

    # Print metadata for verification
    if ("metadata" %in% names(dict_data)) {
      cat("[SUCCESS] Dictionary loaded successfully\n")
      cat("   Generated:", dict_data$metadata$generated, "\n")
      cat("   Raw variables:", dict_data$metadata$total_raw_variables, "\n")
      cat("   Transformed variables:", dict_data$metadata$total_transformed_variables, "\n")
      cat("   Projects:", length(dict_data$metadata$project_pids), "\n")
    }

    return(dict_data)

  }, error = function(e) {
    stop("Failed to load JSON dictionary: ", e$message)
  })
}

# Validate JSON freshness and warn if stale
validate_json_freshness <- function(dict_data, max_age_hours = 24) {
  # Check if the JSON dictionary is recent and warn if it might be stale
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON
  #   max_age_hours: Maximum age in hours before warning
  #
  # Returns:
  #   List with validation results

  if (!"metadata" %in% names(dict_data) || !"generated_timestamp" %in% names(dict_data$metadata)) {
    warning("No generation timestamp found in JSON metadata")
    return(list(valid = FALSE, message = "No timestamp available"))
  }

  tryCatch({
    generated_time <- as.POSIXct(dict_data$metadata$generated_timestamp)
    current_time <- Sys.time()
    age_hours <- as.numeric(difftime(current_time, generated_time, units = "hours"))

    if (age_hours > max_age_hours) {
      message <- paste0("⚠️  JSON dictionary is ", round(age_hours, 1), " hours old. Consider regenerating.")
      warning(message)
      return(list(valid = TRUE, stale = TRUE, age_hours = age_hours, message = message))
    } else {
      return(list(valid = TRUE, stale = FALSE, age_hours = age_hours,
                 message = paste0("✅ JSON dictionary is fresh (", round(age_hours, 1), " hours old)")))
    }

  }, error = function(e) {
    warning("Could not parse generation timestamp: ", e$message)
    return(list(valid = FALSE, message = paste0("Timestamp error: ", e$message)))
  })
}

# DEPRECATED: Legacy database connection (kept for backward compatibility)
connect_to_database <- function() {
  warning("Database connection function is deprecated. Use load_dictionary_json() instead.")
  # Use relative path from project root
  db_path <- file.path("..", "..", "..", "data", "duckdb", "kidsights_local.duckdb")

  if (!file.exists(db_path)) {
    stop("DuckDB file not found at: ", db_path)
  }

  library(DBI)
  library(duckdb)
  con <- dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  return(con)
}

# Get raw variables with project information from JSON
get_raw_variables_data <- function(dict_data = NULL) {
  # Get raw variables data from JSON dictionary
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   Data frame with raw variables data

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  # Validate freshness
  freshness <- validate_json_freshness(dict_data)
  if (!is.null(freshness) && length(freshness) > 0 && "stale" %in% names(freshness) && freshness$stale) {
    cat(freshness$message, "\n")
  }

  if (!"raw_variables" %in% names(dict_data) || length(dict_data$raw_variables$data) == 0) {
    warning("No raw variables data found in JSON")
    return(data.frame())
  }

  raw_vars <- as.data.frame(dict_data$raw_variables$data)

  # Ensure proper data types
  if (nrow(raw_vars) > 0) {
    raw_vars$column_id <- as.integer(raw_vars$column_id)
    raw_vars$pid <- as.character(raw_vars$pid)
  }

  return(raw_vars)
}

# Get transformed variables data from JSON
get_transformed_variables_data <- function(dict_data = NULL) {
  # Get transformed variables data from JSON dictionary
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   Data frame with transformed variables data

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  # Validate freshness
  freshness <- validate_json_freshness(dict_data)
  if (!is.null(freshness) && length(freshness) > 0 && "stale" %in% names(freshness) && freshness$stale) {
    cat(freshness$message, "\n")
  }

  if (!"transformed_variables" %in% names(dict_data) || length(dict_data$transformed_variables$data) == 0) {
    warning("No transformed variables data found in JSON")
    return(data.frame())
  }

  transformed_vars <- as.data.frame(dict_data$transformed_variables$data)

  # Ensure proper data types
  if (nrow(transformed_vars) > 0) {
    transformed_vars$missing_percentage <- as.numeric(transformed_vars$missing_percentage)
    transformed_vars$n_total <- as.integer(transformed_vars$n_total)
    transformed_vars$n_missing <- as.integer(transformed_vars$n_missing)
  }

  return(transformed_vars)
}

# DEPRECATED: Legacy database versions (kept for backward compatibility)
get_raw_variables_data_legacy <- function(con) {
  warning("Legacy database function. Use get_raw_variables_data() instead.")
  # Query the data dictionary table which contains field information with PID
  # Add column_id based on row number within each PID to preserve REDCap order
  query <- "
  SELECT
    ROW_NUMBER() OVER (PARTITION BY pid ORDER BY field_name) as column_id,
    pid,
    field_name,
    field_label,
    field_type,
    select_choices_or_calculations,
    field_note,
    form_name
  FROM ne25_data_dictionary
  WHERE field_name NOT IN ('record_id', 'pid', 'redcap_event_name', 'redcap_survey_identifier',
                          'retrieved_date', 'source_project', 'extraction_id')
  ORDER BY pid, column_id
  "

  raw_vars <- dbGetQuery(con, query)
  return(raw_vars)
}

get_transformed_variables_data_legacy <- function(con) {
  warning("Legacy database function. Use get_transformed_variables_data() instead.")
  # Query the metadata table for transformed variables
  query <- "
  SELECT
    variable_name,
    variable_label,
    category,
    data_type,
    value_labels,
    transformation_notes,
    n_total,
    n_missing,
    missing_percentage
  FROM ne25_metadata
  ORDER BY category, variable_name
  "

  transformed_vars <- dbGetQuery(con, query)
  return(transformed_vars)
}

# Create variable-project matrix from JSON data
create_variable_project_matrix <- function(dict_data = NULL) {
  # Create variable-project matrix from JSON dictionary data
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   Data frame with variable-project matrix

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  # Check if pre-computed matrix is available in JSON
  if ("variable_project_matrix" %in% names(dict_data) &&
      length(dict_data$variable_project_matrix$data) > 0) {
    # Use pre-computed matrix from JSON
    matrix_data <- as.data.frame(dict_data$variable_project_matrix$data)
    return(matrix_data)
  }

  # Fallback: compute matrix from raw variables if not pre-computed
  raw_vars_data <- get_raw_variables_data(dict_data)

  if (nrow(raw_vars_data) == 0) {
    warning("No raw variables data available for matrix creation")
    return(data.frame())
  }

  # Use the PID field directly from the data
  var_project <- raw_vars_data %>%
    select(field_name, field_label, pid) %>%
    distinct()

  # Get project PIDs from config
  project_pids <- c("7679", "7943", "7999", "8014")

  # Create matrix structure
  matrix_data <- var_project %>%
    # Create a presence indicator
    mutate(present = TRUE) %>%
    # Convert PID to character for consistency
    mutate(pid = as.character(pid)) %>%
    # Pivot to create matrix
    select(field_name, field_label, pid, present) %>%
    pivot_wider(
      names_from = pid,
      values_from = present,
      values_fill = FALSE,
      names_prefix = "PID_"
    ) %>%
    # Ensure all PID columns exist
    {
      for (pid in project_pids) {
        col_name <- paste0("PID_", pid)
        if (!col_name %in% names(.)) {
          .[[col_name]] <- FALSE
        }
      }
      .
    } %>%
    # Reorder columns
    select(field_name, field_label, all_of(paste0("PID_", project_pids))) %>%
    arrange(field_name)

  return(matrix_data)
}

# Format variable-project matrix for display
format_variable_project_matrix <- function(matrix_data) {
  # Convert boolean values to checkmarks
  formatted_matrix <- matrix_data %>%
    mutate(
      across(starts_with("PID_"), ~ ifelse(.x, "✓", ""))
    )

  # Create DT table
  dt_table <- DT::datatable(
    formatted_matrix,
    colnames = c("Variable", "Label", "7679", "7943", "7999", "8014"),
    options = list(
      pageLength = 25,
      scrollX = TRUE,
      columnDefs = list(
        list(className = "dt-center", targets = 2:5),
        list(width = "200px", targets = 0),
        list(width = "400px", targets = 1),
        list(width = "50px", targets = 2:5)
      ),
      dom = 'Bfrtip',
      buttons = c('copy', 'csv', 'excel')
    ),
    class = "table table-striped matrix-table",
    rownames = FALSE,
    escape = FALSE
  ) %>%
    DT::formatStyle(
      columns = 2:5,
      textAlign = "center"
    ) %>%
    DT::formatStyle(
      columns = 2:5,
      color = DT::styleEqual("✓", "#27ae60"),
      fontWeight = DT::styleEqual("✓", "bold")
    )

  return(dt_table)
}

# Format raw variables table
format_raw_variables_table <- function(raw_vars_data) {
  # Process the data for display - maintain column order and show PIDs
  formatted_data <- raw_vars_data %>%
    # Get unique variables (remove duplicates across projects) but maintain column order
    group_by(field_name) %>%
    summarise(
      column_id = min(column_id),  # Use minimum column_id for ordering
      field_label = first(field_label),
      field_type = first(field_type),
      select_choices_or_calculations = first(select_choices_or_calculations),
      field_note = first(field_note),
      form_name = first(form_name),
      projects = paste(unique(as.character(pid)), collapse = ", "),
      .groups = "drop"
    ) %>%
    # Clean up value labels for display
    mutate(
      value_labels = case_when(
        !is.na(select_choices_or_calculations) & select_choices_or_calculations != "" ~
          substr(select_choices_or_calculations, 1, 200),
        TRUE ~ ""
      ),
      value_labels = ifelse(nchar(value_labels) == 200,
                           paste0(value_labels, "..."),
                           value_labels)
    ) %>%
    select(column_id, field_name, field_label, field_type, value_labels, projects, form_name, field_note) %>%
    arrange(column_id)  # Order by column_id to maintain REDCap order

  # Create DT table
  dt_table <- DT::datatable(
    formatted_data,
    colnames = c("Column ID", "Variable", "Label", "Type", "Value Labels", "PIDs", "Form", "Notes"),
    options = list(
      pageLength = 25,
      scrollX = TRUE,
      columnDefs = list(
        list(width = "80px", targets = 0),
        list(width = "120px", targets = 1),
        list(width = "250px", targets = 2),
        list(width = "80px", targets = 3),
        list(width = "200px", targets = 4),
        list(width = "100px", targets = 5),
        list(width = "120px", targets = 6),
        list(width = "150px", targets = 7)
      ),
      dom = 'Bfrtip',
      buttons = c('copy', 'csv', 'excel')
    ),
    class = "table table-striped",
    rownames = FALSE,
    escape = FALSE
  )

  return(dt_table)
}

# Get transformation mappings from JSON data
get_transformation_mappings <- function(dict_data = NULL) {
  # Get transformation mappings from JSON dictionary
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   List with transformation mappings documentation

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  # Use mappings from JSON if available
  if ("transformation_mappings" %in% names(dict_data) &&
      length(dict_data$transformation_mappings$data) > 0) {
    return(dict_data$transformation_mappings$data)
  }

  # Fallback to hardcoded mappings if not in JSON
  warning("Transformation mappings not found in JSON, using fallback definitions")
  mappings <- list(
    "Race/Ethnicity" = list(
      description = "Child and caregiver race/ethnicity variables created from checkbox responses",
      raw_variables = c("cqr010_1___1 through cqr010_15___1", "cqr011", "sq002_1___1 through sq002_15___1", "sq003"),
      transformed_variables = c("hisp", "race", "raceG", "a1_hisp", "a1_race", "a1_raceG"),
      process = "Multiple race checkboxes are collapsed into categories; Hispanic ethnicity is combined with race to create composite variables"
    ),

    "Education Categories" = list(
      description = "Education levels recoded into 4, 6, and 8 category systems",
      raw_variables = c("education-related fields from surveys"),
      transformed_variables = c("educ4_*", "educ6_*", "educ8_*", "educ_max", "educ_mom"),
      process = "Raw education responses are mapped to standardized categories for analysis"
    ),

    "Income and Poverty" = list(
      description = "Federal Poverty Level calculations based on income and family size",
      raw_variables = c("household income fields", "family size fields"),
      transformed_variables = c("income", "inc99", "family_size", "federal_poverty_threshold", "fpl", "fplcat"),
      process = "Income is adjusted for inflation; FPL calculated using HHS poverty guidelines; categorical FPL groups created"
    ),

    "Age Variables" = list(
      description = "Age calculations in multiple units",
      raw_variables = c("child_dob", "age_in_days", "caregiver_dob"),
      transformed_variables = c("years_old", "months_old", "days_old", "a1_years_old"),
      process = "Dates converted to age in years, months, and days; age groups created for analysis"
    ),

    "Eligibility Flags" = list(
      description = "Eligibility determination based on 9 criteria (CID1-CID9)",
      raw_variables = c("eq001", "eq002", "eq003", "compensation acknowledgment fields", "geographic fields", "survey completion fields"),
      transformed_variables = c("eligible", "authentic", "include"),
      process = "Multiple eligibility criteria evaluated; overall inclusion flags created"
    )
  )

  return(mappings)
}

# Parse and format factor levels for display
format_factor_levels <- function(factor_levels_json, max_display = 3) {
  # Parse factor levels JSON and create user-friendly display
  #
  # Args:
  #   factor_levels_json: JSON string containing factor level information (can be vectorized)
  #   max_display: Maximum number of levels to show in preview
  #
  # Returns:
  #   Formatted string for display (vectorized)

  # Handle vectorized input
  if (length(factor_levels_json) > 1) {
    return(sapply(factor_levels_json, format_factor_levels, max_display = max_display, USE.NAMES = FALSE))
  }

  # Handle single value
  if (length(factor_levels_json) == 0 || is.na(factor_levels_json) || factor_levels_json == "" || factor_levels_json == "{}") {
    return("")
  }

  tryCatch({
    # Parse the factor levels (expecting array of level objects)
    factor_levels <- jsonlite::fromJSON(factor_levels_json, simplifyDataFrame = TRUE)

    if (length(factor_levels) == 0) {
      return("")
    }

    # Extract code-label pairs for display
    if (is.data.frame(factor_levels)) {
      # Format: display first few levels with counts
      preview_levels <- head(factor_levels, max_display)
      level_text <- paste0(preview_levels$code, "=", preview_levels$label,
                          " (n=", preview_levels$count, ")")

      result <- paste(level_text, collapse=", ")

      # Add indicator if there are more levels
      if (nrow(factor_levels) > max_display) {
        remaining <- nrow(factor_levels) - max_display
        result <- paste0(result, " [+", remaining, " more]")
      }

      return(result)
    }

    return("")

  }, error = function(e) {
    return("")
  })
}

# Parse value labels JSON for simple display
format_value_labels_preview <- function(value_labels_json, max_display = 3) {
  # Create a simple preview of value labels
  #
  # Args:
  #   value_labels_json: JSON string with value labels (can be vectorized)
  #   max_display: Maximum number of labels to show
  #
  # Returns:
  #   Formatted preview string (vectorized)

  # Handle vectorized input
  if (length(value_labels_json) > 1) {
    return(sapply(value_labels_json, format_value_labels_preview, max_display = max_display, USE.NAMES = FALSE))
  }

  # Handle single value
  if (length(value_labels_json) == 0 || is.na(value_labels_json) || value_labels_json == "" || value_labels_json == "{}") {
    return("")
  }

  tryCatch({
    value_labels <- jsonlite::fromJSON(value_labels_json, simplifyDataFrame = FALSE)

    if (length(value_labels) == 0) {
      return("")
    }

    # Take first few labels for preview
    preview_labels <- head(names(value_labels), max_display)
    label_text <- paste0(preview_labels, "=", unlist(value_labels[preview_labels]))

    result <- paste(label_text, collapse=", ")

    # Add indicator if there are more
    if (length(value_labels) > max_display) {
      remaining <- length(value_labels) - max_display
      result <- paste0(result, " [+", remaining, " more]")
    }

    return(result)

  }, error = function(e) {
    return("")
  })
}

# Create factor details for expandable display
create_factor_details_html <- function(var_name, factor_levels_json, value_labels_json,
                                      ordered_factor, reference_level, factor_type) {
  # Create detailed HTML for factor variable information
  #
  # Args:
  #   var_name: Variable name
  #   factor_levels_json: JSON with factor level details
  #   value_labels_json: JSON with value labels
  #   ordered_factor: Boolean indicating if factor is ordered
  #   reference_level: Reference level for modeling
  #   factor_type: Type of factor (demographic, socioeconomic, etc.)
  #
  # Returns:
  #   HTML string for detailed factor display

  if (is.na(factor_levels_json) || factor_levels_json == "" || factor_levels_json == "{}") {
    return("")
  }

  tryCatch({
    factor_levels <- jsonlite::fromJSON(factor_levels_json, simplifyDataFrame = TRUE)

    if (length(factor_levels) == 0) {
      return("")
    }

    # Create header
    ordered_icon <- if (!is.na(ordered_factor) && ordered_factor) "↕️" else "•"
    factor_type_display <- if (!is.na(factor_type)) factor_type else "other"

    html <- paste0(
      "<div class='factor-details' style='margin: 10px 0; padding: 10px; background-color: #f8f9fa; border-radius: 5px;'>",
      "<h6 style='margin: 0 0 10px 0; color: #495057;'>📊 ", var_name, " (Factor Variable)</h6>",
      "<p style='margin: 0 0 10px 0; font-size: 0.9em; color: #6c757d;'>",
      "Type: ", factor_type_display, " | Ordered: ", if (!is.na(ordered_factor) && ordered_factor) "Yes" else "No", " ", ordered_icon
    )

    if (!is.na(reference_level)) {
      html <- paste0(html, " | Reference: ", reference_level)
    }

    html <- paste0(html, "</p><div style='margin-top: 10px;'><strong>Value Mappings:</strong><ul style='margin: 5px 0; padding-left: 20px;'>")

    # Add factor levels
    if (is.data.frame(factor_levels)) {
      for (i in 1:nrow(factor_levels)) {
        level <- factor_levels[i, ]
        ref_indicator <- if (!is.na(reference_level) && level$code == reference_level) " ★" else ""

        html <- paste0(html,
          "<li style='margin: 2px 0;'>", level$code, " → ", level$label,
          " (n=", level$count, ", ", level$percentage, "%)", ref_indicator, "</li>"
        )
      }
    }

    html <- paste0(html, "</ul></div></div>")

    return(html)

  }, error = function(e) {
    return("")
  })
}

# Format transformed variables table
format_transformed_variables_table <- function(transformed_vars_data, transformation_mappings) {
  # Create comprehensive category mapping
  category_mapping <- list(
    "age" = "Age Variables",
    "caregiver relationship" = "Caregiver Relationships",
    "education" = "Education Categories",
    "race" = "Race/Ethnicity",
    "sex" = "Sex and Gender",
    "income" = "Income and Poverty",
    "eligibility" = "Eligibility Flags",
    "geography" = "Geographic Variables"
  )

  # Add source variable information
  mapping_lookup <- tibble()
  for (category in names(transformation_mappings)) {
    trans_vars <- transformation_mappings[[category]]$transformed_variables
    raw_vars <- transformation_mappings[[category]]$raw_variables

    for (var in trans_vars) {
      mapping_lookup <- bind_rows(mapping_lookup, tibble(
        variable_name = var,
        transformation_type = category,
        source_vars = paste(raw_vars, collapse = "; ")
      ))
    }
  }

  # Join with transformed variables data and fix categories
  formatted_data <- transformed_vars_data %>%
    mutate(
      # Round missing percentage to nearest tenth
      missing_percentage = round(missing_percentage, 1),
      # Map database categories to user-friendly names
      category_mapped = case_when(
        category == "age" ~ "Age Variables",
        category == "caregiver relationship" ~ "Caregiver Relationships",
        category == "education" ~ "Education Categories",
        category == "race" ~ "Race/Ethnicity",
        category == "sex" ~ "Sex and Gender",
        category == "income" ~ "Income and Poverty",
        category == "eligibility" ~ "Eligibility Flags",
        category == "geography" ~ "Geographic Variables",
        TRUE ~ category
      )
    ) %>%
    safe_left_join(mapping_lookup, by_vars = "variable_name") %>%
    mutate(
      source_vars = ifelse(is.na(source_vars), "Direct transformation", source_vars),
      # Use transformation_type if available, otherwise use mapped category
      final_category = case_when(
        !is.na(transformation_type) ~ transformation_type,
        TRUE ~ category_mapped
      ),
      # Create factor information display
      factor_info = case_when(
        data_type == "factor" & !is.na(factor_levels) & factor_levels != "" & factor_levels != "{}" ~
          format_value_labels_preview(value_labels, max_display = 2),
        data_type == "factor" & !is.na(value_labels) & value_labels != "" & value_labels != "{}" ~
          format_value_labels_preview(value_labels, max_display = 2),
        TRUE ~ ""
      ),
      # Add ordering indicator for factors
      ordered_indicator = case_when(
        data_type == "factor" & !is.na(ordered_factor) & ordered_factor ~ "↕️",
        data_type == "factor" ~ "•",
        TRUE ~ ""
      ),
      # Combine data type with factor info
      data_type_display = case_when(
        data_type == "factor" & factor_info != "" ~
          paste0("factor ", ordered_indicator, " (", factor_info, ")"),
        data_type == "factor" ~
          paste0("factor ", ordered_indicator),
        TRUE ~ data_type
      )
    ) %>%
    select(variable_name, variable_label, final_category, data_type_display,
           source_vars, transformation_notes, n_total, missing_percentage,
           # Keep original fields for detailed display
           data_type, factor_levels, value_labels, ordered_factor, reference_level, factor_type) %>%
    arrange(final_category, variable_name)

  # Create DT table with multi-select filter (display only relevant columns)
  display_data <- formatted_data %>%
    select(variable_name, variable_label, final_category, data_type_display,
           source_vars, transformation_notes, n_total, missing_percentage)

  dt_table <- DT::datatable(
    display_data,
    colnames = c("Variable", "Label", "Category", "Type", "Source Variables", "Notes", "N", "Missing %"),
    extensions = c('Buttons'),
    filter = 'top',
    options = list(
      pageLength = 25,
      scrollX = TRUE,
      initComplete = DT::JS("
        function(settings, json) {
          // Add multi-select for Category column (index 2)
          this.api().columns([2]).every(function() {
            var column = this;
            var header = $(column.header());

            // Get unique values
            var uniqueVals = column.data().unique().sort().toArray();

            // Create multi-select dropdown
            var select = $('<select multiple style=\"width: 100%; height: 60px;\" title=\"Hold Ctrl/Cmd to select multiple categories\"></select>');

            // Add all option
            select.append('<option value=\"\" selected>All Categories</option>');

            // Add individual options (all selected by default)
            uniqueVals.forEach(function(val) {
              if (val) {
                select.append('<option value=\"' + val + '\" selected>' + val + '</option>');
              }
            });

            // Replace the filter input with our multi-select
            $(header).find('input').replaceWith(select);

            // Handle selection changes
            select.on('change', function() {
              var selectedVals = $(this).val() || [];

              // If 'All Categories' is selected or nothing selected, show all
              if (selectedVals.includes('') || selectedVals.length === 0) {
                column.search('').draw();
              } else {
                // Create regex for selected values
                var searchTerm = '^(' + selectedVals.map(function(val) {
                  return $.fn.dataTable.util.escapeRegex(val);
                }).join('|') + ')$';
                column.search(searchTerm, true, false).draw();
              }
            });
          });
        }
      "),
      columnDefs = list(
        list(width = "120px", targets = 0),
        list(width = "200px", targets = 1),
        list(width = "150px", targets = 2),
        list(width = "80px", targets = 3),
        list(width = "200px", targets = 4),
        list(width = "150px", targets = 5),
        list(width = "60px", targets = 6),
        list(width = "80px", targets = 7)
      ),
      dom = 'Bfrtip',
      buttons = c('copy', 'csv', 'excel')
    ),
    class = "table table-striped",
    rownames = FALSE,
    escape = FALSE
  )

  return(dt_table)
}

# Create factor variables summary table
format_factor_variables_table <- function(transformed_vars_data) {
  # Create a specialized table showing only factor variables with enhanced detail
  #
  # Args:
  #   transformed_vars_data: Data frame with transformed variables including factor metadata
  #
  # Returns:
  #   DT table formatted for factor variable display

  # Filter to factor variables only
  factor_vars <- transformed_vars_data %>%
    filter(data_type == "factor") %>%
    mutate(
      # Create comprehensive factor display
      factor_summary = case_when(
        !is.na(factor_levels) & factor_levels != "" & factor_levels != "{}" ~
          format_factor_levels(factor_levels, max_display = 4),
        !is.na(value_labels) & value_labels != "" & value_labels != "{}" ~
          format_value_labels_preview(value_labels, max_display = 4),
        TRUE ~ "No value labels available"
      ),
      # Format factor properties
      factor_properties = paste0(
        ifelse(!is.na(factor_type), paste0("Type: ", factor_type), "Type: unspecified"),
        " | ",
        ifelse(!is.na(ordered_factor) & ordered_factor, "Ordered: Yes ↕️", "Ordered: No •"),
        ifelse(!is.na(reference_level), paste0(" | Ref: ", reference_level), "")
      ),
      # Round missing percentage
      missing_percentage = round(missing_percentage, 1)
    ) %>%
    select(variable_name, variable_label, factor_properties, factor_summary,
           n_total, missing_percentage) %>%
    arrange(variable_name)

  if (nrow(factor_vars) == 0) {
    return(DT::datatable(
      data.frame(Message = "No factor variables found in the dataset"),
      options = list(pageLength = 5, searching = FALSE, paging = FALSE, info = FALSE),
      rownames = FALSE
    ))
  }

  # Create specialized DT table for factors
  dt_table <- DT::datatable(
    factor_vars,
    colnames = c("Variable", "Label", "Factor Properties", "Value Labels", "N", "Missing %"),
    extensions = c('Buttons'),
    options = list(
      pageLength = 15,
      scrollX = TRUE,
      columnDefs = list(
        list(width = "120px", targets = 0),
        list(width = "200px", targets = 1),
        list(width = "200px", targets = 2),
        list(width = "300px", targets = 3),
        list(width = "60px", targets = 4),
        list(width = "80px", targets = 5)
      ),
      dom = 'Bfrtip',
      buttons = c('copy', 'csv', 'excel')
    ),
    class = "table table-striped",
    rownames = FALSE,
    escape = FALSE
  )

  return(dt_table)
}

# Get factor variables count summary
get_factor_variables_summary <- function(transformed_vars_data) {
  # Create summary statistics for factor variables
  #
  # Args:
  #   transformed_vars_data: Data frame with transformed variables
  #
  # Returns:
  #   Data frame with factor variable summary statistics

  factor_vars <- transformed_vars_data %>%
    filter(data_type == "factor")

  if (nrow(factor_vars) == 0) {
    return(data.frame(
      "Statistic" = "No factor variables found",
      "Count" = 0,
      stringsAsFactors = FALSE
    ))
  }

  # Calculate summary statistics
  total_factors <- nrow(factor_vars)
  ordered_factors <- sum(!is.na(factor_vars$ordered_factor) & factor_vars$ordered_factor, na.rm = TRUE)
  unordered_factors <- total_factors - ordered_factors

  # Factor type summary
  factor_types <- factor_vars %>%
    filter(!is.na(factor_type)) %>%
    count(factor_type, name = "count") %>%
    arrange(desc(count))

  # Create summary table
  summary_data <- data.frame(
    "Statistic" = c(
      "Total factor variables",
      "Ordered factors (↕️)",
      "Unordered factors (•)",
      "Factors with complete metadata"
    ),
    "Count" = c(
      total_factors,
      ordered_factors,
      unordered_factors,
      sum(!is.na(factor_vars$factor_levels) & factor_vars$factor_levels != "" & factor_vars$factor_levels != "{}")
    ),
    stringsAsFactors = FALSE
  )

  return(summary_data)
}

# Export comprehensive dictionary data to JSON using Python script
export_dictionary_json <- function(output_path = "ne25_dictionary.json") {
  tryCatch({
    # Find Python script path - navigate from current working directory to root
    root_dirs <- c(".", "..", "../..", "../../..")
    script_path <- NULL

    for (root in root_dirs) {
      potential_path <- file.path(root, "scripts", "documentation", "generate_interactive_dictionary_json.py")
      if (file.exists(potential_path)) {
        script_path <- normalizePath(potential_path)
        break
      }
    }

    if (is.null(script_path)) {
      stop("Python script not found in expected locations")
    }

    # Determine output directory from output_path
    output_dir <- dirname(output_path)
    if (output_dir == ".") {
      output_dir <- getwd()
    }

    # Build Python command
    python_cmd <- paste0("python \"", script_path, "\" --output-dir \"", output_dir, "\"")

    message("[INFO] Calling Python script for JSON export...")
    message(paste("[INFO] Script path:", script_path))
    message(paste("[INFO] Output directory:", output_dir))

    # Execute Python script with minimal output capture to avoid memory issues
    result <- system(python_cmd, intern = FALSE, wait = TRUE)

    # Check exit code
    if (result != 0) {
      stop("Python script failed with exit code: ", result)
    }

    # Check if the output file was created
    expected_output <- file.path(output_dir, "ne25_dictionary.json")

    if (file.exists(expected_output)) {
      # Copy to specified output path if different
      if (normalizePath(expected_output) != normalizePath(output_path)) {
        file.copy(expected_output, output_path, overwrite = TRUE)
      }

      message(paste("[SUCCESS] JSON dictionary exported to:", output_path))

      # Try to get file size for reporting
      file_size_mb <- round(file.info(output_path)$size / 1024 / 1024, 2)
      message(paste("[INFO] File size:", file_size_mb, "MB"))

      return(output_path)
    } else {
      stop("Python script completed but output file not found at: ", expected_output)
    }

  }, error = function(e) {
    warning("JSON export via Python failed: ", e$message)
    message("[WARNING] Falling back to basic R export...")

    # Simple fallback that just creates basic structure without large data
    fallback_json <- list(
      metadata = list(
        generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        study = "ne25",
        status = "export_failed",
        error = e$message,
        generated_by = "Kidsights Data Platform - R Fallback"
      ),
      note = "Full JSON export failed. Please use Python script directly."
    )

    # Write simple fallback
    json_output <- jsonlite::toJSON(fallback_json, pretty = TRUE, auto_unbox = TRUE)
    writeLines(json_output, output_path)

    message(paste("[WARNING] Fallback JSON written to:", output_path))
    return(output_path)
  })
}

# Get summary data from JSON (for display in Quarto)
get_summary_data <- function(dict_data = NULL) {
  # Get pre-computed summary statistics from JSON
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   List with summary statistics

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  if ("summaries" %in% names(dict_data)) {
    return(dict_data$summaries)
  } else {
    warning("No summary data found in JSON")
    return(list())
  }
}

# Convenience function to display freshness warning in Quarto
display_freshness_warning <- function(dict_data = NULL) {
  # Display freshness warning banner for use in Quarto documents
  #
  # Args:
  #   dict_data: Dictionary data loaded from JSON (if NULL, will load from file)
  #
  # Returns:
  #   HTML string for display

  if (is.null(dict_data)) {
    dict_data <- load_dictionary_json()
  }

  freshness <- validate_json_freshness(dict_data, max_age_hours = 12)

  if (freshness$stale) {
    warning_html <- paste0(
      '<div class="alert alert-warning" role="alert">',
      '<strong>⚠️ Data Dictionary Notice:</strong> ',
      'This dictionary was generated ', round(freshness$age_hours, 1), ' hours ago. ',
      'The data may not reflect the most recent database updates.',
      '</div>'
    )
    return(warning_html)
  } else {
    return("")
  }
}

# Initialize dictionary data for use across multiple functions in Quarto
initialize_dictionary <- function() {
  # Load and validate dictionary data once for use across multiple functions
  #
  # Returns:
  #   Dictionary data with validation results

  dict_data <- load_dictionary_json()
  freshness <- validate_json_freshness(dict_data)

  # Attach freshness info to the data
  dict_data$freshness_info <- freshness

  return(dict_data)
}

# DEPRECATED: Legacy database disconnect (kept for backward compatibility)
disconnect_database <- function(con) {
  warning("Database disconnect function is deprecated in JSON-based workflow.")
  if (!missing(con) && !is.null(con)) {
    tryCatch({
      dbDisconnect(con)
    }, error = function(e) {
      warning("Error disconnecting from database: ", e$message)
    })
  }
}