#' Data Dictionary Generation Functions
#'
#' R wrapper functions to generate data dictionaries from metadata stored in DuckDB.
#' These functions call the Python script for maximum flexibility and formatting options.

library(dplyr)

#' Generate data dictionary from metadata
#'
#' Creates a comprehensive Markdown data dictionary by calling the Python generator script.
#' This ensures consistency between the actual data and documentation.
#'
#' @param db_path Path to DuckDB database file
#' @param output_dir Directory to save generated files
#' @param format Format type: "full" (detailed tables) or "summary" (variable lists)
#' @param export_json Logical, whether to also generate JSON export
#' @param export_html Logical, whether to also generate HTML export
#' @param python_path Path to Python executable (auto-detected if NULL)
#' @return Path to generated data dictionary file
#' @examples
#' \dontrun{
#' # Generate full data dictionary
#' dict_path <- generate_data_dictionary()
#'
#' # Generate summary version with JSON and HTML export
#' dict_path <- generate_data_dictionary(format = "summary", export_json = TRUE, export_html = TRUE)
#' }
generate_data_dictionary <- function(
    db_path = "data/duckdb/kidsights_local.duckdb",
    output_dir = "docs/data_dictionary",
    format = "full",
    export_json = FALSE,
    export_html = FALSE,
    python_path = NULL
) {

  # Auto-detect Python if not provided
  if (is.null(python_path)) {
    python_path <- find_python()
  }

  # Check if database exists
  if (!file.exists(db_path)) {
    stop(paste("Database file not found:", db_path))
  }

  # Build Python script path
  script_path <- file.path("scripts", "documentation", "generate_data_dictionary.py")
  if (!file.exists(script_path)) {
    stop(paste("Python script not found:", script_path))
  }

  # Build command arguments
  args <- c(
    script_path,
    "--db-path", shQuote(db_path),
    "--output-dir", shQuote(output_dir),
    "--format", format
  )

  if (export_json) {
    args <- c(args, "--export-json")
  }

  if (export_html) {
    args <- c(args, "--export-html")
  }

  # Execute Python script
  message("Generating data dictionary...")
  message(paste("Database:", db_path))
  message(paste("Output:", output_dir))
  message(paste("Format:", format))

  result <- tryCatch({
    system2(python_path, args, stdout = TRUE, stderr = TRUE)
  }, error = function(e) {
    stop(paste("Failed to execute Python script:", e$message))
  })

  # Check for errors
  if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
    stop(paste("Python script failed:", paste(result, collapse = "\n")))
  }

  # Print output
  message(paste(result, collapse = "\n"))

  # Return path to generated file
  filename <- paste0("ne25_data_dictionary_", format, ".md")
  generated_path <- file.path(output_dir, filename)

  if (file.exists(generated_path)) {
    message(paste("✅ Data dictionary generated successfully:", generated_path))
    return(generated_path)
  } else {
    warning("Data dictionary generation completed but file not found at expected location")
    return(NULL)
  }
}

#' Find Python executable
#'
#' Attempts to locate a suitable Python executable on the system
#'
#' @return Path to Python executable
find_python <- function() {

  # Common Python paths to try
  python_candidates <- c(
    "python3",
    "python",
    "C:/Python*/python.exe",
    "C:/Users/*/AppData/Local/Programs/Python/Python*/python.exe",
    "/usr/bin/python3",
    "/usr/bin/python",
    "/usr/local/bin/python3",
    "/opt/anaconda3/bin/python",
    "/opt/miniconda3/bin/python"
  )

  # Check each candidate
  for (candidate in python_candidates) {
    # Handle wildcards for Windows paths
    if (grepl("\\*", candidate)) {
      expanded_paths <- Sys.glob(candidate)
      for (path in expanded_paths) {
        if (file.exists(path)) {
          return(path)
        }
      }
    } else {
      # Test if command works
      result <- tryCatch({
        system2(candidate, "--version", stdout = TRUE, stderr = TRUE)
        candidate
      }, error = function(e) NULL)

      if (!is.null(result)) {
        return(candidate)
      }
    }
  }

  stop("Python executable not found. Please install Python or specify python_path manually.")
}

#' Check Python dependencies
#'
#' Verifies that required Python packages are installed
#'
#' @param python_path Path to Python executable
#' @return Logical indicating if all dependencies are available
check_python_dependencies <- function(python_path = NULL) {

  if (is.null(python_path)) {
    python_path <- find_python()
  }

  required_packages <- c("duckdb", "pandas", "markdown2")

  message("Checking Python dependencies...")

  missing_packages <- character()

  for (package in required_packages) {
    result <- tryCatch({
      system2(python_path, c("-c", paste0("import ", package)),
              stdout = TRUE, stderr = TRUE)
      TRUE
    }, error = function(e) FALSE)

    if (!result) {
      missing_packages <- c(missing_packages, package)
    }
  }

  if (length(missing_packages) > 0) {
    message("❌ Missing Python packages:", paste(missing_packages, collapse = ", "))
    message("Install with: pip install", paste(missing_packages, collapse = " "))
    return(FALSE)
  } else {
    message("✅ All Python dependencies available")
    return(TRUE)
  }
}

#' Install Python dependencies
#'
#' Attempts to install required Python packages using pip
#'
#' @param python_path Path to Python executable
#' @return Logical indicating success
install_python_dependencies <- function(python_path = NULL) {

  if (is.null(python_path)) {
    python_path <- find_python()
  }

  required_packages <- c("duckdb", "pandas", "markdown2")

  message("Installing Python dependencies...")

  # Try to find pip
  pip_path <- gsub("python(\\.exe)?$", "pip\\1", python_path, ignore.case = TRUE)

  # Install packages
  install_cmd <- c("-m", "pip", "install", required_packages)

  result <- tryCatch({
    system2(python_path, install_cmd, stdout = TRUE, stderr = TRUE)
  }, error = function(e) {
    stop(paste("Failed to install Python packages:", e$message))
  })

  # Check if installation was successful
  if (check_python_dependencies(python_path)) {
    message("✅ Python dependencies installed successfully")
    return(TRUE)
  } else {
    warning("Python dependency installation may have failed")
    return(FALSE)
  }
}

#' Generate data dictionary and integrate with pipeline
#'
#' Wrapper function specifically for pipeline integration that handles
#' all error checking and provides appropriate feedback
#'
#' @param con DuckDB connection object (optional, for validation)
#' @param format Format type for dictionary
#' @return Path to generated dictionary or NULL if failed
generate_pipeline_data_dictionary <- function(con = NULL, format = "full") {

  message("\\n--- Generating Data Dictionary ---")

  tryCatch({

    # Check if metadata exists in database
    if (!is.null(con)) {
      tables <- DBI::dbListTables(con)
      if (!"ne25_metadata" %in% tables) {
        warning("Metadata table not found in database. Skipping data dictionary generation.")
        return(NULL)
      }

      # Check if metadata has content
      metadata_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM ne25_metadata")$n
      if (metadata_count == 0) {
        warning("No metadata records found. Skipping data dictionary generation.")
        return(NULL)
      }

      message(paste("Found", metadata_count, "metadata records"))
    }

    # Check Python dependencies
    if (!check_python_dependencies()) {
      message("Attempting to install Python dependencies...")
      install_python_dependencies()
    }

    # Generate dictionary with all export formats
    dict_path <- generate_data_dictionary(format = format, export_json = TRUE, export_html = TRUE)

    if (!is.null(dict_path)) {
      message(paste("Data dictionary generated:", dict_path))
      return(dict_path)
    } else {
      warning("Data dictionary generation failed")
      return(NULL)
    }

  }, error = function(e) {
    warning(paste("Data dictionary generation failed:", e$message))
    return(NULL)
  })
}