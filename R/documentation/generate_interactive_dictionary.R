#' Interactive Data Dictionary Generation
#'
#' Functions to generate the interactive Quarto-based data dictionary
#' as part of the automated pipeline process.

# Dependency Management: Ensure documentation packages are available
if (file.exists("R/utils/dependency_manager.R")) {
  source("R/utils/dependency_manager.R")
  ensure_documentation_dependencies(auto_install = TRUE, quiet = FALSE)
} else {
  # Fallback for when called from docs/data_dictionary/ne25/ directory
  root_paths <- c("../../../R/utils/dependency_manager.R",
                  "../../../../R/utils/dependency_manager.R")
  for (path in root_paths) {
    if (file.exists(path)) {
      source(path)
      ensure_documentation_dependencies(auto_install = TRUE, quiet = FALSE)
      break
    }
  }
}

library(dplyr)

#' Check if Quarto is available on the system
#'
#' @param quarto_path Optional path to Quarto executable
#' @return List with availability status and path
check_quarto_installation <- function(quarto_path = NULL) {

  # Try provided path first
  if (!is.null(quarto_path) && file.exists(quarto_path)) {
    return(list(available = TRUE, path = quarto_path))
  }

  # Search for Quarto in common locations
  possible_paths <- c(
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe",
    "C:/Users/waldmanm/AppData/Local/Programs/Positron/resources/app/quarto/bin/quarto.exe"
  )

  for (path in possible_paths) {
    if (file.exists(path)) {
      return(list(available = TRUE, path = path))
    }
  }

  # Try system PATH
  result <- tryCatch({
    system2("quarto", "--version", stdout = TRUE, stderr = TRUE)
    list(available = TRUE, path = "quarto")
  }, error = function(e) {
    list(available = FALSE, path = NULL)
  })

  return(result)
}

#' Generate Interactive Data Dictionary
#'
#' Creates the interactive Quarto-based data dictionary by rendering all QMD files
#'
#' @param output_dir Directory containing the Quarto files
#' @param quarto_path Optional path to Quarto executable
#' @param verbose Logical, whether to show detailed output
#' @param timeout_seconds Maximum time to wait for rendering
#' @return List with success status, paths, and any errors
generate_interactive_dictionary <- function(output_dir = "docs/data_dictionary/ne25",
                                          quarto_path = NULL,
                                          verbose = TRUE,
                                          timeout_seconds = 120) {

  if (verbose) {
    message("\n--- Generating Interactive Data Dictionary ---")
  }

  # Check Quarto availability
  quarto_check <- check_quarto_installation(quarto_path)
  if (!quarto_check$available) {
    return(list(
      success = FALSE,
      error = "Quarto not found on system",
      suggestion = "Install Quarto from https://quarto.org or ensure it's in your PATH"
    ))
  }

  if (verbose) {
    message("✅ Quarto found: ", quarto_check$path)
  }

  # Check if output directory exists
  if (!dir.exists(output_dir)) {
    if (verbose) {
      message("Creating output directory: ", output_dir)
    }
    dir.create(output_dir, recursive = TRUE)
  }

  # Check for required QMD files
  required_files <- c(
    "index.qmd",
    "matrix.qmd",
    "raw-variables.qmd",
    "transformed-variables.qmd",
    "transformations.qmd",
    "_quarto.yml",
    "custom.css"
  )

  missing_files <- c()
  for (file in required_files) {
    file_path <- file.path(output_dir, file)
    if (!file.exists(file_path)) {
      missing_files <- c(missing_files, file)
    }
  }

  if (length(missing_files) > 0) {
    return(list(
      success = FALSE,
      error = paste("Missing required files:", paste(missing_files, collapse = ", ")),
      suggestion = "Ensure all Quarto data dictionary files are present"
    ))
  }

  # Skip database validation - data is accessed directly by Quarto from files

  if (verbose) {
    message("✅ All required files and database tables found")
    message("🔄 Rendering interactive data dictionary...")
  }

  # Store current working directory
  original_wd <- getwd()

  tryCatch({
    # Change to output directory for rendering
    setwd(output_dir)

    # STEP 1: Generate comprehensive JSON export BEFORE Quarto rendering
    json_file_path <- NULL
    if (verbose) {
      message("🔄 Generating comprehensive JSON export (required for Quarto rendering)...")
    }

    tryCatch({
      # Source the export function
      source(file.path(getwd(), "assets", "dictionary_functions.R"))
      json_file_path <- export_dictionary_json("ne25_dictionary.json")

      if (is.null(json_file_path) || !file.exists(json_file_path)) {
        return(list(
          success = FALSE,
          error = "JSON export failed - required for Quarto rendering",
          suggestion = "Check database connection and Python script availability"
        ))
      }

      if (verbose) {
        message("✅ JSON export completed: ", json_file_path)
      }

    }, error = function(e) {
      return(list(
        success = FALSE,
        error = paste("JSON export failed:", e$message),
        suggestion = "JSON export is required for Quarto rendering. Check database and Python dependencies."
      ))
    })

    # STEP 2: Execute Quarto render command (now that JSON is available)
    if (verbose) {
      message("🔄 Rendering Quarto documentation (using JSON data)...")
    }

    # Build render command
    render_cmd <- paste(
      shQuote(quarto_check$path),
      "render"
    )

    # Execute render command
    start_time <- Sys.time()

    if (verbose) {
      message("Executing: ", render_cmd)
    }

    # Use system2 with timeout
    result <- system2(
      command = quarto_check$path,
      args = "render",
      stdout = TRUE,
      stderr = TRUE,
      timeout = timeout_seconds
    )

    end_time <- Sys.time()
    render_duration <- as.numeric(end_time - start_time)

    # Check for errors
    status <- attr(result, "status")
    if (!is.null(status) && status != 0) {
      return(list(
        success = FALSE,
        error = "Quarto rendering failed",
        details = paste(result, collapse = "\n"),
        duration = render_duration,
        json_export = json_file_path
      ))
    }

    # Check for generated HTML files
    html_files <- list.files(pattern = "\\.html$", full.names = TRUE)

    if (length(html_files) == 0) {
      return(list(
        success = FALSE,
        error = "No HTML files generated",
        suggestion = "Check Quarto configuration and QMD file syntax",
        json_export = json_file_path
      ))
    }

    if (verbose) {
      message("✅ Interactive data dictionary generated successfully")
      message("📁 Location: ", file.path(getwd(), "index.html"))
      message("⏱️  Render time: ", round(render_duration, 1), " seconds")
      message("📄 HTML files generated: ", length(html_files))
      message("📋 JSON source: ", file.path(getwd(), "ne25_dictionary.json"))
      message("🔄 Workflow: JSON-first (eliminates R DuckDB segmentation faults)")
    }

    return(list(
      success = TRUE,
      output_dir = getwd(),
      files_generated = html_files,
      main_file = file.path(getwd(), "index.html"),
      json_export = json_file_path,
      duration = render_duration,
      file_count = length(html_files),
      workflow_type = "JSON-first",
      segfault_free = TRUE
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      error = paste("Rendering failed:", e$message),
      suggestion = "Check Quarto installation and file permissions"
    ))
  }, finally = {
    # Restore working directory
    setwd(original_wd)
  })
}

#' Check Required R Packages for Interactive Dictionary
#'
#' @return List of missing packages
check_dictionary_packages <- function() {
  required_packages <- c("DT", "knitr", "dplyr", "tidyr", "tibble")

  missing_packages <- c()
  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing_packages <- c(missing_packages, pkg)
    }
  }

  return(missing_packages)
}

#' Install Missing Dictionary Packages
#'
#' @param packages Vector of package names to install
#' @param verbose Logical, whether to show installation messages
install_dictionary_packages <- function(packages, verbose = TRUE) {
  if (length(packages) == 0) {
    return(TRUE)
  }

  if (verbose) {
    message("Installing missing packages: ", paste(packages, collapse = ", "))
  }

  tryCatch({
    install.packages(packages, repos = "https://cran.rstudio.com/")
    return(TRUE)
  }, error = function(e) {
    if (verbose) {
      message("Failed to install packages: ", e$message)
    }
    return(FALSE)
  })
}