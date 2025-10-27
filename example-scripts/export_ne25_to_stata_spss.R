#' Export NE25 Data from DuckDB to SPSS, RDS, and CSV Formats
#'
#' This script exports NE25 tables from the Kidsights DuckDB database to
#' SPSS (.sav) and R (.rds) formats with full variable and value labels,
#' plus a comprehensive data dictionary in CSV format.
#'
#' USAGE:
#'   source("example-scripts/export_ne25_to_stata_spss.R")
#'
#' WHAT IT DOES:
#'   1. Prompts user to select export directory via GUI dialog
#'   2. Connects to data/duckdb/kidsights_local.duckdb
#'   3. Exports data dictionary to CSV (all variable metadata)
#'   4. Exports two tables with labels:
#'      - ne25_raw: Raw REDCap data (4,962 records, 6 variables)
#'      - ne25_transformed: Derived variables (4,962 records, 641 variables)
#'   5. Creates 5 files total (2 .sav + 2 .rds + 1 .csv dictionary)
#'
#' OUTPUT FILES:
#'   - ne25_data_dictionary.csv: Complete variable documentation
#'   - ne25_raw.sav: SPSS format with labels
#'   - ne25_raw.rds: R native format (preserves all attributes)
#'   - ne25_transformed.sav: SPSS format with labels (shortened names)
#'   - ne25_transformed.rds: R native format (original names)
#'
#' REQUIREMENTS:
#'   - R 4.5.1+
#'   - Packages: duckdb, DBI, haven, labelled, dplyr (auto-installed)
#'   - Kidsights database must exist at data/duckdb/kidsights_local.duckdb
#'
#' AUTHOR: Kidsights Data Platform Team
#' UPDATED: October 2025

# ============================================================================
# PACKAGE INSTALLATION AND LOADING
# ============================================================================

#' Install and Load Required Packages
#'
#' Automatically installs missing packages and loads them
ensure_packages <- function() {
  required_packages <- c("duckdb", "DBI", "haven", "labelled", "dplyr")

  cat("[INFO] Checking required packages...\n")

  # Check which packages need installation
  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

  # Install missing packages
  if (length(missing_packages) > 0) {
    cat("[INFO] Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
    install.packages(missing_packages, dependencies = TRUE, repos = "https://cran.r-project.org")
  }

  # Load all packages
  for (pkg in required_packages) {
    library(pkg, character.only = TRUE, quietly = TRUE)
  }

  cat("[OK] All required packages loaded\n\n")
}

# Install and load packages
ensure_packages()

# ============================================================================
# GUI DIRECTORY PICKER
# ============================================================================

#' Select Export Directory via GUI Dialog
#'
#' Opens a cross-platform file picker dialog for user to select where
#' to save the exported files
#'
#' @return Character string with selected directory path
select_export_directory <- function() {
  cat("===========================================\n")
  cat("  NE25 Data Export to SPSS & RDS\n")
  cat("===========================================\n\n")
  cat("[INFO] Please select export directory in the dialog window...\n\n")

  # Use tcltk for cross-platform GUI (part of base R)
  if (requireNamespace("tcltk", quietly = TRUE)) {
    export_dir <- tcltk::tk_choose.dir(
      default = getwd(),
      caption = "Select directory to save NE25 exports (SPSS .sav & R .rds files)"
    )

    # Handle user cancellation
    if (is.na(export_dir) || length(export_dir) == 0) {
      cat("[WARN] No directory selected. Using current working directory.\n")
      export_dir <- getwd()
    }
  } else {
    # Fallback if tcltk not available
    cat("[WARN] GUI not available. Using current working directory.\n")
    export_dir <- getwd()
  }

  cat("[OK] Export directory selected:\n")
  cat("    ", export_dir, "\n\n")

  return(export_dir)
}

# ============================================================================
# DATABASE CONNECTION
# ============================================================================

#' Connect to Kidsights DuckDB Database
#'
#' @return DBI connection object
connect_to_database <- function() {
  db_path <- "data/duckdb/kidsights_local.duckdb"

  if (!file.exists(db_path)) {
    stop("[ERROR] Database not found at: ", db_path, "\n",
         "Please run the NE25 pipeline first to create the database.")
  }

  cat("[INFO] Connecting to database...\n")
  conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  cat("[OK] Connected to:", db_path, "\n\n")

  return(conn)
}

# ============================================================================
# LABEL EXTRACTION AND PARSING
# ============================================================================

#' Parse REDCap Choice String to Named Vector
#'
#' Converts REDCap format "1, Label A | 2, Label B" to named vector
#'
#' @param choice_string Character string in REDCap format
#' @return Named character vector for haven::labelled()
parse_redcap_choices <- function(choice_string) {
  if (is.na(choice_string) || nchar(trimws(choice_string)) == 0) {
    return(NULL)
  }

  # Split by pipe
  choices <- strsplit(choice_string, "\\|")[[1]]
  choices <- trimws(choices)

  # Parse each choice: "value, label"
  parsed <- list()
  for (choice in choices) {
    parts <- strsplit(choice, ",", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      value <- trimws(parts[1])
      label <- trimws(paste(parts[-1], collapse = ","))
      parsed[[value]] <- label
    }
  }

  if (length(parsed) == 0) {
    return(NULL)
  }

  # Convert to named vector
  labels <- unlist(parsed)
  names(labels) <- names(parsed)

  return(labels)
}

#' Extract Variable and Value Labels from Data Dictionary
#'
#' Queries ne25_data_dictionary table to get labels
#'
#' @param conn DBI connection object
#' @return List with variable_labels and value_labels
extract_labels_from_dictionary <- function(conn) {
  cat("[INFO] Extracting labels from data dictionary...\n")

  # Query data dictionary
  dict_query <- "
    SELECT
      field_name,
      field_label,
      field_type,
      select_choices_or_calculations
    FROM ne25_data_dictionary
    WHERE field_label IS NOT NULL
  "

  dict <- DBI::dbGetQuery(conn, dict_query)

  # Create variable labels (field_name -> field_label)
  variable_labels <- stats::setNames(dict$field_label, dict$field_name)

  # Create value labels (field_name -> named vector of choices)
  value_labels <- list()
  for (i in seq_len(nrow(dict))) {
    field <- dict$field_name[i]
    choices <- dict$select_choices_or_calculations[i]

    # Only parse if field has choices (radio, dropdown, checkbox)
    if (!is.na(choices) && nchar(trimws(choices)) > 0) {
      parsed_labels <- parse_redcap_choices(choices)
      if (!is.null(parsed_labels)) {
        value_labels[[field]] <- parsed_labels
      }
    }
  }

  cat("[OK] Extracted labels for", length(variable_labels), "variables\n")
  cat("[OK] Extracted value labels for", length(value_labels), "variables\n\n")

  return(list(
    variable_labels = variable_labels,
    value_labels = value_labels
  ))
}

# ============================================================================
# DATA EXPORT FUNCTIONS
# ============================================================================

#' Shorten Variable Names for SPSS Compatibility
#'
#' SPSS has a 64-character limit for variable names. This function shortens
#' names that exceed the limit while ensuring uniqueness.
#'
#' @param names Character vector of variable names
#' @return Character vector of shortened variable names
shorten_spss_names <- function(names) {
  needs_shortening <- nchar(names) > 64

  if (!any(needs_shortening)) {
    return(names)
  }

  shortened <- names
  for (i in which(needs_shortening)) {
    # Reserve 5 characters for suffix (_####)
    suffix <- sprintf("_%04d", i)
    max_prefix_length <- 64 - nchar(suffix)
    shortened[i] <- paste0(substr(names[i], 1, max_prefix_length), suffix)
  }

  # Ensure uniqueness (shouldn't be necessary, but safety check)
  shortened <- make.unique(shortened, sep = "_")

  return(shortened)
}

#' Apply Labels to Data Frame
#'
#' Applies variable labels and value labels to data frame
#'
#' @param df Data frame to label
#' @param labels List with variable_labels and value_labels
#' @return Labeled data frame
apply_labels_to_data <- function(df, labels) {
  # Apply variable labels
  for (var in names(df)) {
    if (var %in% names(labels$variable_labels)) {
      attr(df[[var]], "label") <- labels$variable_labels[[var]]
    }
  }

  # Apply value labels using haven::labelled()
  for (var in names(df)) {
    if (var %in% names(labels$value_labels)) {
      value_map <- labels$value_labels[[var]]

      # Skip if value_map is empty or NULL
      if (is.null(value_map) || length(value_map) == 0) {
        next
      }

      # Try to apply labels, but skip if there's a type mismatch
      tryCatch({
        if (is.numeric(df[[var]])) {
          # Numeric variable - try to match numeric labels
          numeric_labels <- suppressWarnings(as.numeric(names(value_map)))
          if (!any(is.na(numeric_labels))) {
            # Create numeric value map
            numeric_value_map <- stats::setNames(value_map, numeric_labels)
            df[[var]] <- haven::labelled(df[[var]], labels = numeric_value_map)
          }
        } else if (is.character(df[[var]])) {
          # Character variable - match character labels
          df[[var]] <- haven::labelled(df[[var]], labels = value_map)
        }
      }, error = function(e) {
        # Skip this variable if labeling fails (type mismatch)
        # Variable label will still be applied from earlier step
      })
    }
  }

  return(df)
}

#' Export Data Dictionary to CSV
#'
#' Creates a comprehensive data dictionary documenting all variables,
#' their labels, and value mappings
#'
#' @param conn DBI connection object
#' @param export_dir Directory to save files
#' @param labels List with variable_labels and value_labels
export_data_dictionary <- function(conn, export_dir, labels) {
  cat("[INFO] Exporting data dictionary...\n")

  # Query full data dictionary from database
  dict_query <- "
    SELECT
      field_name,
      form_name,
      section_header,
      field_type,
      field_label,
      select_choices_or_calculations,
      field_note,
      text_validation_type_or_show_slider_number,
      text_validation_min,
      text_validation_max,
      identifier,
      branching_logic,
      required_field,
      field_annotation
    FROM ne25_data_dictionary
    ORDER BY form_name, field_name
  "

  dict <- DBI::dbGetQuery(conn, dict_query)

  cat("       Total variables documented:", nrow(dict), "\n")

  # Export to CSV
  csv_file <- file.path(export_dir, "ne25_data_dictionary.csv")
  tryCatch({
    write.csv(dict, csv_file, row.names = FALSE, na = "")
    cat("[OK]   Created:", csv_file, "\n\n")
  }, error = function(e) {
    cat("[ERROR] Data dictionary export failed:", conditionMessage(e), "\n\n")
  })
}

#' Export Table to SPSS and RDS Formats
#'
#' Exports a single table with labels to .sav and .rds formats
#'
#' @param conn DBI connection object
#' @param table_name Name of table in database
#' @param export_dir Directory to save files
#' @param labels List with variable_labels and value_labels
export_table <- function(conn, table_name, export_dir, labels) {
  cat("[INFO] Exporting", table_name, "...\n")

  # Query all data from table
  query <- paste0("SELECT * FROM ", table_name)
  data <- DBI::dbGetQuery(conn, query)

  cat("       Records:", nrow(data), "| Variables:", ncol(data), "\n")

  # Apply labels
  data <- apply_labels_to_data(data, labels)

  # Export to SPSS (.sav)
  spss_file <- file.path(export_dir, paste0(table_name, ".sav"))
  tryCatch({
    # Create copy for SPSS export (to preserve original names for RDS)
    data_spss <- data

    # Shorten variable names if needed for SPSS (64 char limit)
    original_names <- names(data_spss)
    shortened_names <- shorten_spss_names(original_names)

    if (!identical(original_names, shortened_names)) {
      names(data_spss) <- shortened_names
      n_shortened <- sum(nchar(original_names) > 64)
      cat("[INFO] Shortened", n_shortened, "variable names for SPSS compatibility\n")
    }

    haven::write_sav(data_spss, spss_file)
    cat("[OK]   Created:", spss_file, "\n")
  }, error = function(e) {
    cat("[ERROR] SPSS export failed:", conditionMessage(e), "\n")
    cat("       Error details:", conditionMessage(e), "\n")
  })

  # Export to RDS (.rds) - native R format, preserves all attributes
  rds_file <- file.path(export_dir, paste0(table_name, ".rds"))
  tryCatch({
    saveRDS(data, rds_file, compress = "xz")
    cat("[OK]   Created:", rds_file, "\n\n")
  }, error = function(e) {
    cat("[ERROR] RDS export failed:", conditionMessage(e), "\n")
    cat("       Error details:", conditionMessage(e), "\n\n")
  })
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main <- function() {
  # Start timer
  start_time <- Sys.time()

  # Get export directory from user
  export_dir <- select_export_directory()

  # Connect to database
  conn <- connect_to_database()

  # Ensure connection is closed on exit
  on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

  # Extract labels from data dictionary
  labels <- extract_labels_from_dictionary(conn)

  # Export data dictionary
  cat("===========================================\n")
  cat("  Exporting Data Dictionary\n")
  cat("===========================================\n\n")

  tryCatch({
    export_data_dictionary(conn, export_dir, labels)
  }, error = function(e) {
    cat("[ERROR] Failed to export data dictionary:", conditionMessage(e), "\n\n")
  })

  # Export two main tables (raw and transformed)
  cat("===========================================\n")
  cat("  Exporting NE25 Tables\n")
  cat("===========================================\n\n")

  tables_to_export <- c("ne25_raw", "ne25_transformed")

  for (table in tables_to_export) {
    tryCatch({
      export_table(conn, table, export_dir, labels)
    }, error = function(e) {
      cat("[ERROR] Failed to export", table, ":", conditionMessage(e), "\n\n")
    })
  }

  # Summary
  elapsed <- difftime(Sys.time(), start_time, units = "secs")

  cat("===========================================\n")
  cat("  Export Complete!\n")
  cat("===========================================\n")
  cat("Files saved to:", export_dir, "\n")
  cat("Total files created: 5 (2 .sav + 2 .rds + 1 .csv dictionary)\n")
  cat("Execution time:", round(elapsed, 2), "seconds\n")
  cat("===========================================\n")
}

# Run the export
main()
