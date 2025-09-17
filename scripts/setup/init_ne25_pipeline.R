#' NE25 Pipeline Setup and Initialization Script
#'
#' One-time setup script to:
#' - Install required R packages
#' - Initialize DuckDB database
#' - Create initial schema
#' - Test connections

#' Install required packages if not already installed
install_required_packages <- function() {
  required_packages <- c(
    "duckdb",        # Database
    "DBI",           # Database interface
    "dplyr",         # Data manipulation
    "readr",         # File reading
    "yaml",          # Configuration files
    "REDCapR",       # REDCap API
    "httr",          # HTTP requests
    "purrr",         # Functional programming
    "stringr",       # String manipulation
    "tidyr",         # Data tidying
    "labelled"       # Variable labels
  )

  missing_packages <- required_packages[!required_packages %in% installed.packages()[,"Package"]]

  if (length(missing_packages) > 0) {
    message("Installing missing packages:", paste(missing_packages, collapse = ", "))
    install.packages(missing_packages, dependencies = TRUE)
  } else {
    message("All required packages are already installed")
  }

  # Load packages to verify installation
  success <- TRUE
  for (pkg in required_packages) {
    tryCatch({
      library(pkg, character.only = TRUE)
    }, error = function(e) {
      message(paste("Failed to load package:", pkg, "-", e$message))
      success <<- FALSE
    })
  }

  if (success) {
    message("✅ All packages loaded successfully")
  } else {
    stop("❌ Some packages failed to load")
  }

  return(success)
}

#' Load API credentials from CSV file and set as environment variables
#'
#' @param csv_path Path to CSV file with API credentials
load_api_credentials_setup <- function(csv_path) {

  if (!file.exists(csv_path)) {
    stop(paste("API credentials file not found:", csv_path))
  }

  # Read the CSV file
  api_data <- readr::read_csv(csv_path, show_col_types = FALSE)

  # Validate required columns
  required_cols <- c("project", "pid", "api_code")
  missing_cols <- setdiff(required_cols, names(api_data))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in API file:", paste(missing_cols, collapse = ", ")))
  }

  # Set environment variables for each project
  for (i in 1:nrow(api_data)) {
    pid <- api_data$pid[i]
    api_token <- api_data$api_code[i]
    env_var_name <- paste0("KIDSIGHTS_API_TOKEN_", pid)

    # Set the environment variable properly
    do.call(Sys.setenv, setNames(list(api_token), env_var_name))
    message(paste("Set environment variable:", env_var_name))
  }

  message(paste("Loaded", nrow(api_data), "API credentials"))
}

#' Test REDCap API connectivity
#'
#' @param config_path Path to configuration file
test_redcap_connectivity <- function(config_path = "config/sources/ne25.yaml") {

  message("Testing REDCap API connectivity...")

  if (!file.exists(config_path)) {
    stop(paste("Configuration file not found:", config_path))
  }

  config <- yaml::read_yaml(config_path)

  # Load API credentials first
  load_api_credentials_setup(config$redcap$api_credentials_file)

  # Test each project
  for (project_info in config$redcap$projects) {
    project_name <- project_info$name
    message(paste("Testing project:", project_name))

    tryCatch({
      # Get API token from environment variable
      api_token <- Sys.getenv(project_info$token_env)
      if (api_token == "") {
        message(paste("  ❌", project_name, "- API token not found in environment"))
        next
      }

      # Simple API test - get project info
      result <- REDCapR::redcap_read(
        redcap_uri = config$redcap$url,
        token = api_token,
        raw_or_label = "raw",
        export_data_access_groups = FALSE
      )

      if (result$success) {
        message(paste("  ✅", project_name, "- Connected successfully,", nrow(result$data), "records"))
      } else {
        message(paste("  ❌", project_name, "- Connection failed:", result$outcome_message))
      }

    }, error = function(e) {
      message(paste("  ❌", project_name, "- Error:", e$message))
    })

    Sys.sleep(1)  # Rate limiting
  }
}

#' Initialize DuckDB database and schema
#'
#' @param db_path Path to DuckDB database file
#' @param schema_file Path to SQL schema file
initialize_database <- function(db_path = "data/duckdb/kidsights_local.duckdb",
                               schema_file = "schemas/landing/ne25.sql") {

  message("Initializing DuckDB database...")

  # Create directory if it doesn't exist
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE)
    message(paste("Created directory:", db_dir))
  }

  # Test DuckDB connection
  tryCatch({
    source("R/duckdb/connection.R")
    con <- connect_kidsights_db(db_path)

    # Initialize schema
    schema_success <- init_ne25_schema(con, schema_file)

    if (schema_success) {
      # Test basic functionality
      test_query <- "SELECT COUNT(*) as n FROM ne25_raw"
      result <- DBI::dbGetQuery(con, test_query)
      message(paste("✅ Database initialized successfully. Current records:", result$n))

      # List all tables
      tables <- DBI::dbListTables(con)
      message(paste("Tables created:", paste(tables, collapse = ", ")))

    } else {
      stop("Failed to initialize database schema")
    }

    disconnect_kidsights_db(con)

  }, error = function(e) {
    message(paste("❌ Database initialization failed:", e$message))
    stop(e)
  })
}

#' Run complete setup process
#'
#' @param test_redcap Logical, whether to test REDCap connectivity
#' @param force_reinstall Logical, whether to force package reinstallation
setup_ne25_pipeline <- function(test_redcap = TRUE, force_reinstall = FALSE) {

  message("=== NE25 Pipeline Setup ===")
  message(paste("Start time:", Sys.time()))

  # Step 1: Install packages
  message("\n--- Step 1: Installing Required Packages ---")
  if (force_reinstall) {
    # Force reinstall of key packages
    install.packages(c("duckdb", "REDCapR", "dplyr"), force = TRUE)
  }
  package_success <- install_required_packages()

  if (!package_success) {
    stop("Package installation failed")
  }

  # Step 2: Test file structure
  message("\n--- Step 2: Checking File Structure ---")
  required_files <- c(
    "config/sources/ne25.yaml",
    "schemas/landing/ne25.sql",
    "R/extract/ne25.R",
    "R/harmonize/ne25_eligibility.R",
    "R/harmonize/ne25_transformer.R",
    "R/duckdb/connection.R"
  )

  missing_files <- required_files[!file.exists(required_files)]
  if (length(missing_files) > 0) {
    message("❌ Missing required files:")
    for (file in missing_files) {
      message(paste("  -", file))
    }
    stop("Please ensure all required files are present")
  } else {
    message("✅ All required files present")
  }

  # Step 3: Test REDCap connectivity
  if (test_redcap) {
    message("\n--- Step 3: Testing REDCap Connectivity ---")
    tryCatch({
      test_redcap_connectivity()
      message("✅ REDCap connectivity test completed")
    }, error = function(e) {
      message(paste("⚠️ REDCap connectivity test failed:", e$message))
      message("Pipeline can still be set up, but data extraction may fail")
    })
  }

  # Step 4: Initialize database
  message("\n--- Step 4: Initializing Database ---")
  initialize_database()

  # Step 5: Final verification
  message("\n--- Step 5: Final Verification ---")
  verification_success <- verify_setup()

  if (verification_success) {
    message("\n🎉 Setup completed successfully!")
    message("You can now run the pipeline with: source('run_ne25_pipeline.R')")
  } else {
    message("\n❌ Setup completed with warnings. Please check the messages above.")
  }

  return(verification_success)
}

#' Verify setup is complete and working
verify_setup <- function() {

  success <- TRUE

  # Check packages
  required_packages <- c("duckdb", "REDCapR", "dplyr", "yaml")
  for (pkg in required_packages) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      message(paste("❌ Package not available:", pkg))
      success <- FALSE
    }
  }

  # Check database
  tryCatch({
    source("R/duckdb/connection.R")
    con <- connect_kidsights_db()
    tables <- DBI::dbListTables(con)
    expected_tables <- c("ne25_raw", "ne25_eligibility", "ne25_harmonized")
    missing_tables <- setdiff(expected_tables, tables)

    if (length(missing_tables) > 0) {
      message(paste("❌ Missing database tables:", paste(missing_tables, collapse = ", ")))
      success <- FALSE
    }

    disconnect_kidsights_db(con)

  }, error = function(e) {
    message(paste("❌ Database verification failed:", e$message))
    success <- FALSE
  })

  # Check configuration
  if (!file.exists("config/sources/ne25.yaml")) {
    message("❌ Configuration file missing")
    success <- FALSE
  }

  if (success) {
    message("✅ All verification checks passed")
  }

  return(success)
}

# Interactive setup function
if (interactive()) {
  message("Run setup_ne25_pipeline() to begin setup process")
}