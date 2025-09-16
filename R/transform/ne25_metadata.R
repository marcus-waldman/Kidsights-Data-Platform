# NE25 Metadata Generation Functions
# Ported from Kidsights Dashboard utils-etl.R

# Function to create comprehensive variable metadata
create_variable_metadata <- function(dat, dict, my_API = NULL, what = "all") {

  library(labelled)
  library(jsonlite)
  library(dplyr)

  # Helper function to get detailed variable info
  get_variable_info <- function(var, var_name) {
    info <- list(
      variable_name = var_name,
      label = attr(var, "label") %||% "",
      data_type = class(var)[1],
      storage_mode = mode(var),
      length = length(var),
      n_missing = sum(is.na(var)),
      missing_percentage = round(sum(is.na(var))/length(var) * 100, 2)
    )

    # Add type-specific information
    if (is.factor(var)) {
      info$factor_info <- list(
        n_levels = nlevels(var),
        levels = levels(var),
        level_counts = as.list(table(var, useNA = "ifany"))
      )
    } else if (is.numeric(var)) {
      info$numeric_info <- list(
        min = ifelse(all(is.na(var)), NA, min(var, na.rm = TRUE)),
        max = ifelse(all(is.na(var)), NA, max(var, na.rm = TRUE)),
        mean = ifelse(all(is.na(var)), NA, mean(var, na.rm = TRUE)),
        median = ifelse(all(is.na(var)), NA, median(var, na.rm = TRUE)),
        sd = ifelse(all(is.na(var)), NA, sd(var, na.rm = TRUE))
      )
    } else if (is.logical(var)) {
      info$logical_info <- list(
        n_true = sum(var == TRUE, na.rm = TRUE),
        n_false = sum(var == FALSE, na.rm = TRUE),
        proportion_true = mean(var, na.rm = TRUE)
      )
    } else if (is.character(var)) {
      info$character_info <- list(
        unique_values = length(unique(var[!is.na(var)])),
        max_length = max(nchar(var), na.rm = TRUE)
      )
    }

    return(info)
  }

  # Get the category descriptions
  category_descriptions <- list(
    "include" = "Meets all criteria for inclusion in the study",
    "race" = "Race and ethnicity variables for children and primary caregivers, including combined race/ethnicity categories",
    "caregiver relationship" = "Variables describing the relationship between caregivers and children, including gender and maternal status indicators",
    "education" = "Education level variables for caregivers in multiple category systems (4, 6, and 8 categories), including maximum household education and maternal education",
    "sex" = "Child's biological sex and gender indicator variables",
    "age" = "Child and primary caregiver age",
    "income" = "Household income variables including CPI-adjusted values, family size, federal poverty level calculations and categories"
  )

  # Define variable categories based on transformation types
  if(what == "all") {
    vars <- c("include", "race", "caregiver relationship", "education", "sex", "age", "income")
  } else {
    vars <- what
  }

  # Initialize metadata structure
  metadata <- list(
    dataset_info = list(
      name = "NE25 Transformed Data",
      description = "Fully transformed and harmonized data from the Nebraska 2025 childhood development study",
      n_observations = nrow(dat),
      n_variables = ncol(dat),
      creation_date = Sys.time(),
      source = "REDCap API extraction with comprehensive transformations"
    ),
    variable_categories = list()
  )

  # Process each variable category
  for(category_name in vars) {

    # Get variables that belong to this category
    category_vars <- get_category_variables(dat, category_name)

    if(length(category_vars) > 0) {

      category_metadata <- list(
        category_name = category_name,
        description = category_descriptions[[category_name]] %||% "No description available",
        n_variables = length(category_vars),
        variables = list()
      )

      # Process each variable in the category
      for(var_name in category_vars) {
        if(var_name %in% names(dat)) {
          var_info <- get_variable_info(dat[[var_name]], var_name)
          category_metadata$variables[[var_name]] <- var_info
        }
      }

      metadata$variable_categories[[category_name]] <- category_metadata
    }
  }

  return(metadata)
}

# Helper function to identify which variables belong to each category
get_category_variables <- function(dat, category) {
  all_vars <- names(dat)

  category_patterns <- list(
    "include" = c("eligible", "authentic", "include"),
    "race" = c("hisp", "race", "raceG", "a1_hisp", "a1_race", "a1_raceG"),
    "caregiver relationship" = c("relation1", "relation2", "female_a1", "mom_a1"),
    "education" = c("educ_max", "educ_a1", "educ_a2", "educ_mom",
                   "educ4_max", "educ4_a1", "educ4_a2", "educ4_mom",
                   "educ6_max", "educ6_a1", "educ6_a2", "educ6_mom"),
    "sex" = c("sex", "female"),
    "age" = c("days_old", "years_old", "months_old", "a1_years_old"),
    "income" = c("income", "inc99", "family_size", "federal_poverty_threshold", "fpl", "fplcat")
  )

  if(category %in% names(category_patterns)) {
    # Find variables that match the patterns for this category
    pattern_vars <- category_patterns[[category]]
    return(intersect(all_vars, pattern_vars))
  }

  return(character(0))
}

# Function to export metadata as JSON
export_metadata_json <- function(metadata, filename = "variable_metadata.json") {
  jsonlite::write_json(
    metadata,
    filename,
    pretty = TRUE,
    auto_unbox = TRUE,
    na = "null"
  )
  message(paste("Metadata exported to:", filename))
}

# Function to create a summary table of all variables
create_variable_summary_table <- function(metadata) {

  summary_rows <- list()

  for(category_name in names(metadata$variable_categories)) {
    category <- metadata$variable_categories[[category_name]]

    for(var_name in names(category$variables)) {
      var_info <- category$variables[[var_name]]

      row <- data.frame(
        category = category_name,
        variable_name = var_name,
        label = var_info$label,
        data_type = var_info$data_type,
        n_missing = var_info$n_missing,
        missing_pct = var_info$missing_percentage,
        stringsAsFactors = FALSE
      )

      # Add type-specific summary info
      if(!is.null(var_info$factor_info)) {
        row$n_levels <- var_info$factor_info$n_levels
        row$summary_info <- paste("Factor with", var_info$factor_info$n_levels, "levels")
      } else if(!is.null(var_info$numeric_info)) {
        row$n_levels <- NA
        row$summary_info <- paste("Mean:", round(var_info$numeric_info$mean, 2),
                                  "| Range:", round(var_info$numeric_info$min, 2), "-", round(var_info$numeric_info$max, 2))
      } else if(!is.null(var_info$logical_info)) {
        row$n_levels <- 2
        row$summary_info <- paste("Prop. TRUE:", round(var_info$logical_info$proportion_true, 3))
      } else if(!is.null(var_info$character_info)) {
        row$n_levels <- var_info$character_info$unique_values
        row$summary_info <- paste("Unique values:", var_info$character_info$unique_values)
      } else {
        row$n_levels <- NA
        row$summary_info <- ""
      }

      summary_rows[[length(summary_rows) + 1]] <- row
    }
  }

  if(length(summary_rows) > 0) {
    return(do.call(rbind, summary_rows))
  } else {
    return(data.frame())
  }
}

# Function to convert metadata to data frame for database storage
metadata_to_dataframe <- function(metadata) {

  metadata_rows <- list()

  for(category_name in names(metadata$variable_categories)) {
    category <- metadata$variable_categories[[category_name]]

    for(var_name in names(category$variables)) {
      var_info <- category$variables[[var_name]]

      # Convert complex structures to JSON strings
      value_labels_json <- ""
      if(!is.null(var_info$factor_info)) {
        value_labels_json <- jsonlite::toJSON(var_info$factor_info$level_counts, auto_unbox = TRUE)
      }

      summary_stats_json <- ""
      if(!is.null(var_info$numeric_info)) {
        summary_stats_json <- jsonlite::toJSON(var_info$numeric_info, auto_unbox = TRUE)
      } else if(!is.null(var_info$logical_info)) {
        summary_stats_json <- jsonlite::toJSON(var_info$logical_info, auto_unbox = TRUE)
      } else if(!is.null(var_info$character_info)) {
        summary_stats_json <- jsonlite::toJSON(var_info$character_info, auto_unbox = TRUE)
      }

      row <- data.frame(
        variable_name = var_name,
        category = category_name,
        variable_label = var_info$label,
        data_type = var_info$data_type,
        storage_mode = var_info$storage_mode,
        n_total = var_info$length,
        n_missing = var_info$n_missing,
        missing_percentage = var_info$missing_percentage,
        value_labels = value_labels_json,
        summary_statistics = summary_stats_json,
        min_value = if(!is.null(var_info$numeric_info)) var_info$numeric_info$min else NA,
        max_value = if(!is.null(var_info$numeric_info)) var_info$numeric_info$max else NA,
        mean_value = if(!is.null(var_info$numeric_info)) var_info$numeric_info$mean else NA,
        unique_values = if(!is.null(var_info$factor_info)) var_info$factor_info$n_levels else if(!is.null(var_info$character_info)) var_info$character_info$unique_values else NA,
        creation_date = Sys.time(),
        stringsAsFactors = FALSE
      )

      metadata_rows[[length(metadata_rows) + 1]] <- row
    }
  }

  if(length(metadata_rows) > 0) {
    return(do.call(rbind, metadata_rows))
  } else {
    return(data.frame())
  }
}