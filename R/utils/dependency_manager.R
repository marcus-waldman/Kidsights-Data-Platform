#' Kidsights Pipeline Dependency Management
#'
#' Centralized dependency checking and automatic installation system
#' for the Kidsights Data Platform pipeline.
#'
#' This module provides functions to:
#' - Check for required packages
#' - Automatically install missing packages
#' - Verify package functionality
#' - Handle different package sets for different pipeline components

#' Master List of All Pipeline Dependencies
#'
#' Organized by functionality to make maintenance easier
get_pipeline_dependencies <- function() {
  list(
    # Core pipeline packages (always required)
    core = c(
      "dplyr",         # Data manipulation
      "yaml",          # Configuration files
      "REDCapR",       # REDCap API
      "purrr",         # Functional programming
      "stringr",       # String manipulation
      "tidyr"          # Data tidying
    ),

    # Database packages (for data storage)
    database = c(
      "duckdb",        # Database
      "DBI",           # Database interface
      "arrow"          # Feather/Parquet files
    ),

    # Web/API packages
    web = c(
      "httr",          # HTTP requests
      "curl"           # Alternative HTTP client
    ),

    # Data processing packages
    processing = c(
      "labelled",      # Variable labels
      "readr",         # File reading
      "lubridate"      # Date/time handling
    ),

    # Documentation packages (for Quarto rendering)
    documentation = c(
      "DT",            # Interactive data tables
      "knitr",         # Document generation
      "htmltools",     # HTML utilities
      "tibble"         # Modern data frames
    ),

    # Visualization packages (for codebook dashboard)
    visualization = c(
      "plotly",        # Interactive plots
      "networkD3",     # Network diagrams
      "visNetwork"     # Network visualization
    ),

    # Meta-packages that include multiple dependencies
    meta = c(
      "tidyverse"      # Comprehensive data science toolkit
    )
  )
}

#' Get Required Packages for Specific Pipeline Component
#'
#' @param component Character vector of component names
#' @return Character vector of package names
#' @examples
#' get_required_packages("core")
#' get_required_packages(c("core", "database"))
get_required_packages <- function(component = "core") {
  deps <- get_pipeline_dependencies()

  # Handle special case for "all"
  if (length(component) == 1 && component == "all") {
    return(unique(unlist(deps)))
  }

  # Get packages for specified components
  required <- character(0)
  for (comp in component) {
    if (comp %in% names(deps)) {
      required <- c(required, deps[[comp]])
    } else {
      warning(paste("Unknown component:", comp))
    }
  }

  return(unique(required))
}

#' Check Which Packages Are Missing
#'
#' @param packages Character vector of package names to check
#' @param quiet Logical, whether to suppress messages
#' @return Character vector of missing package names
check_missing_packages <- function(packages, quiet = FALSE) {
  missing <- character(0)

  for (pkg in packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing <- c(missing, pkg)
    }
  }

  if (!quiet && length(missing) > 0) {
    message("Missing packages: ", paste(missing, collapse = ", "))
  } else if (!quiet) {
    message("All required packages are available")
  }

  return(missing)
}

#' Install Missing Packages
#'
#' @param packages Character vector of package names to install
#' @param repos CRAN repository URL
#' @param dependencies Whether to install dependencies
#' @param quiet Logical, whether to suppress installation messages
#' @return Logical, TRUE if all installations succeeded
install_missing_packages <- function(packages,
                                   repos = "https://cran.rstudio.com/",
                                   dependencies = TRUE,
                                   quiet = FALSE) {

  if (length(packages) == 0) {
    if (!quiet) message("No packages to install")
    return(TRUE)
  }

  if (!quiet) {
    message("Installing packages: ", paste(packages, collapse = ", "))
    message("This may take a few minutes...")
  }

  tryCatch({
    install.packages(
      packages,
      repos = repos,
      dependencies = dependencies,
      quiet = quiet
    )
    return(TRUE)
  }, error = function(e) {
    if (!quiet) {
      message("Installation failed: ", e$message)
    }
    return(FALSE)
  })
}

#' Verify Package Functionality
#'
#' Attempts to load each package to verify it works correctly
#'
#' @param packages Character vector of package names to verify
#' @param quiet Logical, whether to suppress messages
#' @return Named logical vector indicating which packages loaded successfully
verify_packages <- function(packages, quiet = FALSE) {
  results <- logical(length(packages))
  names(results) <- packages

  for (pkg in packages) {
    tryCatch({
      # Try to load the package
      suppressPackageStartupMessages(
        requireNamespace(pkg, quietly = TRUE)
      )
      results[pkg] <- TRUE
      if (!quiet) message("✅ ", pkg, " loaded successfully")
    }, error = function(e) {
      results[pkg] <- FALSE
      if (!quiet) message("❌ ", pkg, " failed to load: ", e$message)
    })
  }

  return(results)
}

#' Main Function: Ensure Dependencies Are Available
#'
#' This is the main function that should be called at the beginning
#' of pipeline scripts to ensure all required packages are available.
#'
#' @param component Character vector of component names (or "all")
#' @param auto_install Logical, whether to automatically install missing packages
#' @param verify Logical, whether to verify packages load correctly
#' @param quiet Logical, whether to suppress messages
#' @return Logical, TRUE if all dependencies are satisfied
ensure_dependencies <- function(component = "core",
                              auto_install = TRUE,
                              verify = TRUE,
                              quiet = FALSE) {

  if (!quiet) {
    message("🔍 Checking dependencies for: ", paste(component, collapse = ", "))
  }

  # Get required packages
  required_packages <- get_required_packages(component)

  if (!quiet) {
    message("Required packages (", length(required_packages), "): ",
            paste(head(required_packages, 5), collapse = ", "),
            if (length(required_packages) > 5) "..." else "")
  }

  # Check for missing packages
  missing_packages <- check_missing_packages(required_packages, quiet = quiet)

  # Install missing packages if requested
  if (length(missing_packages) > 0) {
    if (auto_install) {
      if (!quiet) {
        message("🔧 Installing ", length(missing_packages), " missing packages...")
      }

      install_success <- install_missing_packages(missing_packages, quiet = quiet)

      if (!install_success) {
        stop("Failed to install required packages: ", paste(missing_packages, collapse = ", "))
      }

      # Re-check after installation
      still_missing <- check_missing_packages(required_packages, quiet = TRUE)
      if (length(still_missing) > 0) {
        stop("Packages still missing after installation: ", paste(still_missing, collapse = ", "))
      }

    } else {
      stop("Missing required packages: ", paste(missing_packages, collapse = ", "),
           "\nSet auto_install=TRUE to install them automatically.")
    }
  }

  # Verify packages work if requested
  if (verify) {
    if (!quiet) message("✅ Verifying package functionality...")

    verification_results <- verify_packages(required_packages, quiet = quiet)
    failed_packages <- names(verification_results)[!verification_results]

    if (length(failed_packages) > 0) {
      stop("Packages failed verification: ", paste(failed_packages, collapse = ", "))
    }
  }

  if (!quiet) {
    message("🎉 All dependencies satisfied!")
  }

  return(TRUE)
}

#' Quick Setup Function for Common Use Cases
#'
#' Convenience functions for specific pipeline components
ensure_core_dependencies <- function(auto_install = TRUE, quiet = FALSE) {
  ensure_dependencies("core", auto_install = auto_install, quiet = quiet)
}

ensure_database_dependencies <- function(auto_install = TRUE, quiet = FALSE) {
  ensure_dependencies(c("core", "database"), auto_install = auto_install, quiet = quiet)
}

ensure_documentation_dependencies <- function(auto_install = TRUE, quiet = FALSE) {
  ensure_dependencies(c("core", "documentation"), auto_install = auto_install, quiet = quiet)
}

ensure_full_pipeline_dependencies <- function(auto_install = TRUE, quiet = FALSE) {
  ensure_dependencies("all", auto_install = auto_install, quiet = quiet)
}

#' Create Dependency Report
#'
#' Generate a report of current package status
#'
#' @param component Character vector of component names to check
#' @return Data frame with package status information
create_dependency_report <- function(component = "all") {
  required_packages <- get_required_packages(component)

  report <- data.frame(
    package = required_packages,
    installed = sapply(required_packages, function(pkg) {
      requireNamespace(pkg, quietly = TRUE)
    }),
    stringsAsFactors = FALSE
  )

  # Add version information for installed packages
  report$version <- sapply(required_packages, function(pkg) {
    if (report$installed[report$package == pkg]) {
      tryCatch({
        as.character(packageVersion(pkg))
      }, error = function(e) "unknown")
    } else {
      NA_character_
    }
  })

  return(report)
}

#' Print Dependency Status
#'
#' Print a formatted status report
print_dependency_status <- function(component = "all") {
  report <- create_dependency_report(component)

  cat("📦 Dependency Status Report\n")
  cat("==========================\n\n")

  installed_count <- sum(report$installed)
  total_count <- nrow(report)

  cat("Overall Status: ", installed_count, "/", total_count, " packages installed\n\n")

  if (any(report$installed)) {
    cat("✅ Installed Packages:\n")
    installed_pkgs <- report[report$installed, ]
    for (i in 1:nrow(installed_pkgs)) {
      cat("  ", installed_pkgs$package[i], " (", installed_pkgs$version[i], ")\n", sep = "")
    }
    cat("\n")
  }

  if (any(!report$installed)) {
    cat("❌ Missing Packages:\n")
    missing_pkgs <- report[!report$installed, ]
    for (i in 1:nrow(missing_pkgs)) {
      cat("  ", missing_pkgs$package[i], "\n", sep = "")
    }
    cat("\n")
    cat("💡 Run ensure_dependencies() with auto_install=TRUE to install missing packages.\n")
  }

  invisible(report)
}