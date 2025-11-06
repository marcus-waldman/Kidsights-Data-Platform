#' NE25 Eligibility Validation Functions
#'
#' Port of eligibility checking functions from the dashboard utils-eligibility.R
#' Implements the 9 eligibility criteria (CID1-CID9) for the NE25 study
#'
#' All participants must pass eligibility AND authenticity checks for inclusion

# Automatic package installation and loading
install_and_load_packages <- function() {
  # Required packages for eligibility validation (CID8 removed - no more IRT analysis)
  required_packages <- c(
    # Basic data manipulation
    "dplyr",      # Data manipulation
    "stringr",    # String operations
    "tidyr",      # Data tidying
    "plyr",       # For mapvalues (load before dplyr to avoid conflicts)

    # Additional packages that may be needed
    "readxl",     # For ZIP code data
    "zipcodeR",   # ZIP code utilities
    "knitr"       # For table formatting
  )

  # Check which packages are missing
  missing_packages <- setdiff(required_packages, installed.packages()[,"Package"])

  # Install missing packages
  if(length(missing_packages) > 0) {
    message("Installing missing packages for eligibility validation: ",
            paste(missing_packages, collapse = ", "))

    # Install from CRAN with dependencies
    install.packages(missing_packages,
                    dependencies = TRUE,
                    repos = "https://cran.rstudio.com/",
                    quiet = TRUE)

    message("Package installation completed.")
  }

  # Load packages in correct order (plyr before dplyr to avoid conflicts)
  load_order <- c("plyr", setdiff(required_packages, "plyr"))

  for(pkg in load_order) {
    if(pkg %in% installed.packages()[,"Package"]) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    } else {
      warning(paste("Package", pkg, "failed to install and could not be loaded"))
    }
  }

  return(list(
    installed = required_packages,
    missing = missing_packages
  ))
}

# Initialize packages
package_status <- install_and_load_packages()

#' Check CID1: Compensation acknowledgment
#'
#' Validates that participants acknowledged all compensation terms
#'
#' @param data Data frame with compensation acknowledgment fields
#' @return Data frame with CID1 pass/fail status
check_cid1_compensation <- function(data) {

  required_fields <- c(
    "state_law_requires_that_kidsights_data_collect_my_name___1",
    "financial_compensation_be_sent_to_a_nebraska_residential_address___1",
    "state_law_prohibits_sending_compensation_electronically___1",
    "kidsights_data_reviews_all_responses_for_quality___1"
  )

  cid1_result <- data %>%
    dplyr::select(pid, record_id, any_of(required_fields)) %>%
    rowwise() %>%
    dplyr::mutate(
      pass_cid1 = sum(c_across(all_of(intersect(required_fields, names(.)))), na.rm = TRUE) == 4
    ) %>%
    ungroup() %>%
    dplyr::select(pid, record_id, pass_cid1)

  return(cid1_result)
}

#' Check CID2: Informed consent
#'
#' Validates that informed consent was provided
#'
#' @param data Data frame with consent field (eq001)
#' @return Data frame with CID2 pass/fail status
check_cid2_consent <- function(data) {

  cid2_result <- data %>%
    dplyr::select(pid, record_id, eq001) %>%
    dplyr::mutate(
      pass_cid2 = eq001 == 1 & !is.na(eq001)
    ) %>%
    dplyr::select(pid, record_id, pass_cid2)

  return(cid2_result)
}

#' Check CID3: Caregiver age and status
#'
#' Validates that respondent is 19+ years old and primary caregiver
#'
#' @param data Data frame with caregiver fields (eq002, eq003)
#' @return Data frame with CID3 pass/fail status
check_cid3_caregiver <- function(data) {

  cid3_result <- data %>%
    dplyr::select(pid, record_id, eq003, eq002) %>%
    dplyr::mutate(
      pass_cid3 = (eq002 == 1 & eq003 == 1) & !is.na(eq002) & !is.na(eq003)
    ) %>%
    dplyr::select(pid, record_id, pass_cid3)

  return(cid3_result)
}

#' Check CID4: Child age restriction
#'
#' Validates that child is 2191 days (6 years) or younger
#'
#' @param data Data frame with age_in_days field
#' @return Data frame with CID4 pass/fail status
check_cid4_child_age <- function(data) {

  cid4_result <- data %>%
    dplyr::select(pid, record_id, age_in_days) %>%
    dplyr::mutate(
      pass_cid4 = (age_in_days <= 2191) & !is.na(age_in_days)
    ) %>%
    dplyr::select(pid, record_id, pass_cid4)

  return(cid4_result)
}

#' Check CID5: Nebraska residence
#'
#' Validates that participant currently lives in Nebraska
#'
#' @param data Data frame with state field (eqstate)
#' @return Data frame with CID5 pass/fail status
check_cid5_nebraska <- function(data) {

  cid5_result <- data %>%
    dplyr::select(pid, record_id, eqstate) %>%
    dplyr::mutate(
      pass_cid5 = (eqstate == 1) & !is.na(eqstate)
    ) %>%
    dplyr::select(pid, record_id, pass_cid5)

  return(cid5_result)
}

#' Check CID6: ZIP code and county consistency
#'
#' Validates that ZIP code matches reported county
#'
#' @param data Data frame with ZIP (sq001) and county (fq001) fields
#' @param data_dictionary REDCap data dictionary for value labels
#' @return Data frame with CID6 pass/fail status
check_cid6_zip_county <- function(data, data_dictionary) {

  # Extract county labels from data dictionary
  county_labels <- extract_value_labels("fq001", data_dictionary)

  cid6_result <- data %>%
    dplyr::select(pid, record_id, sq001, fq001) %>%
    # Ensure both fields are character for consistent joining
    dplyr::mutate(
      sq001 = as.character(sq001),  # ZIP code as character
      fq001 = as.character(fq001)   # County code as character
    ) %>%
    # Map county codes to labels
    safe_left_join(
      county_labels %>%
        dplyr::rename(fq001 = value, county_name = label) %>%
        dplyr::mutate(fq001 = as.character(fq001)),  # Ensure same type
      by_vars = "fq001"
    ) %>%
    # Get acceptable ZIP codes for each county
    safe_left_join(
      get_nebraska_zip_county_crosswalk(),
      by_vars = c("sq001" = "zip_code")
    ) %>%
    dplyr::mutate(
      # Check if reported county is in the acceptable counties for this ZIP
      # Use fixed() to ensure literal string matching
      pass_cid6 = !is.na(county_name) & !is.na(acceptable_counties) &
                  stringr::str_detect(acceptable_counties, stringr::fixed(county_name))
    ) %>%
    dplyr::select(pid, record_id, pass_cid6)

  return(cid6_result)
}

#' Check CID7: Birthday confirmation
#'
#' Validates that child's birthday was confirmed
#'
#' @param data Data frame with dob_match field
#' @return Data frame with CID7 pass/fail status
check_cid7_birthday <- function(data) {

  cid7_result <- data %>%
    dplyr::select(pid, record_id, dob_match) %>%
    dplyr::mutate(
      pass_cid7 = (dob_match == 1) & !is.na(dob_match)
    ) %>%
    dplyr::select(pid, record_id, pass_cid7)

  return(cid7_result)
}


#' Check CID8: Survey completion
#'
#' Validates that all required survey modules were completed
#' (ported from Dashboard version, renumbered from CID9 after CID8 removal)
#'
#' @param data Data frame with completion status fields
#' @return Data frame with CID8 pass/fail status
check_cid8_completion <- function(data) {

  # Dashboard implementation: looks for module_2 through module_9 completion
  tmp <- data %>%
    select(pid, record_id, starts_with("module_"))

  # Convert to long format
  tmp <- tmp %>%
    tidyr::pivot_longer(
      cols = contains("_complete"),
      names_to = "name",
      values_to = "value"
    ) %>%
    mutate(module = as.integer(stringr::str_extract(name, "(?<=module_)\\d+"))) %>%
    group_by(pid, record_id, module) %>%
    reframe(value = max(value, na.rm = TRUE))

  # Get rid of follow up information (module 8)
  tmp <- tmp %>% filter(module != 8)

  # Convert back to wide format
  tmp <- tmp %>%
    mutate(
      module = paste("module", module, sep = "_"),
      value = as.integer(value == 2)  # 2 = Complete in REDCap
    ) %>%
    tidyr::pivot_wider(names_from = module, values_from = value)

  # Check completion
  df <- tmp %>%
    rowwise() %>%
    dplyr::mutate(
      pass_cid8 = ifelse(
        all(c("module_2", "module_3", "module_4", "module_5",
              "module_6", "module_7", "module_9") %in% names(.)),
        mean(c_across(module_2:module_9), na.rm = TRUE) == 1,
        FALSE
      )
    ) %>%
    ungroup() %>%
    dplyr::select(pid, record_id, pass_cid8)

  return(df)
}

#' Master eligibility checking function
#'
#' Applies all 8 eligibility criteria and generates summary
#' Note: CID8 (KMT quality) removed - IRT analysis inappropriate for early filtering
#'
#' @param data Raw NE25 survey data
#' @param data_dictionary REDCap data dictionary
#' @return List with eligibility summary and details
check_ne25_eligibility <- function(data, data_dictionary) {

  message("DEBUG: Starting eligibility validation with 8 criteria (CID8 removed)")
  message("DEBUG: Input data: ", nrow(data), " records, ", ncol(data), " columns")

  # Apply all eligibility checks (excluding CID8)
  cid_results <- data %>%
    dplyr::select(pid, record_id, retrieved_date) %>%
    safe_left_join(check_cid1_compensation(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid2_consent(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid3_caregiver(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid4_child_age(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid5_nebraska(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid6_zip_county(data, data_dictionary), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid7_birthday(data), by_vars = c("pid", "record_id")) %>%
    safe_left_join(check_cid8_completion(data), by_vars = c("pid", "record_id"))

  message("DEBUG: CID results computed, dimensions: ", nrow(cid_results), " x ", ncol(cid_results))

  # Convert to long format for detailed analysis
  eligibility_long <- cid_results %>%
    tidyr::pivot_longer(
      cols = dplyr::starts_with("pass_cid"),
      names_to = "cid",
      values_to = "pass"
    ) %>%
    dplyr::mutate(
      cid_number = as.integer(stringr::str_extract(cid, "\\d+"))
    ) %>%
    safe_left_join(
      get_eligibility_criteria_definitions(),
      by_vars = c("cid_number" = "cid")
    )

  # Create summary by category
  eligibility_summary <- eligibility_long %>%
    dplyr::group_by(retrieved_date, pid, record_id, category) %>%
    dplyr::summarise(
      status = ifelse(all(pass, na.rm = TRUE), "Pass", "Fail"),
      .groups = "drop"
    ) %>%
    tidyr::pivot_wider(
      names_from = category,
      values_from = status
    ) %>%
    dplyr::rename_with(tolower) %>%
    dplyr::relocate(retrieved_date, pid, record_id, eligibility, authenticity, compensation)

  # Get mailing addresses for eligible participants
  mailing_info <- data %>%
    dplyr::select(pid, record_id, dplyr::matches("q139[4-8]")) # q1394:q1398

  return(list(
    summary = eligibility_summary,
    details = eligibility_long,
    mailing = mailing_info,
    criteria_definitions = get_eligibility_criteria_definitions()
  ))
}

#' Apply eligibility results to dataset
#'
#' Adds eligibility flags to the main dataset
#'
#' @param data Main NE25 dataset
#' @param eligibility_results Results from check_ne25_eligibility()
#' @return Data frame with eligibility columns added
apply_ne25_eligibility <- function(data, eligibility_results) {
  cat("\n=== APPLY_NE25_ELIGIBILITY DEBUG ===\n")
  cat("Input data dimensions:", nrow(data), "x", ncol(data), "\n")
  cat("Data columns (first 10):", paste(head(names(data), 10), collapse=", "), "\n")

  cat("Eligibility results structure:\n")
  cat("- Names:", paste(names(eligibility_results), collapse=", "), "\n")

  if (!is.null(eligibility_results$summary)) {
    cat("Summary dimensions:", nrow(eligibility_results$summary), "x", ncol(eligibility_results$summary), "\n")
    cat("Summary columns:", paste(names(eligibility_results$summary), collapse=", "), "\n")
  } else {
    cat("WARNING: eligibility_results$summary is NULL\n")
  }

  cat("Attempting left join...\n")
  data_with_eligibility <- tryCatch({
    data %>%
      safe_left_join(
        eligibility_results$summary,
        by_vars = c("retrieved_date", "pid", "record_id")
      ) %>%
      dplyr::mutate(
        # Overall inclusion flag
        eligible = eligibility == "Pass",
        authentic = authenticity == "Pass",
        include = eligible & authentic
      )
  }, error = function(e) {
    cat("ERROR in apply_ne25_eligibility:\n")
    cat("- Message:", e$message, "\n")
    cat("- Call:", deparse(e$call), "\n")
    stop(e)
  })

  cat("Apply eligibility completed. Result dimensions:", nrow(data_with_eligibility), "x", ncol(data_with_eligibility), "\n")
  return(data_with_eligibility)
}

#' Filter data to include only eligible participants
#'
#' @param data Data frame with eligibility flags
#' @return Filtered data frame
filter_eligible_ne25 <- function(data) {
  data %>%
    filter(eligibility == "Pass", authenticity == "Pass")
}

# Helper functions

#' Extract value labels from REDCap data dictionary
#'
#' @param field_name Field name to extract labels for
#' @param dictionary REDCap data dictionary
#' @return Data frame with value and label columns
extract_value_labels <- function(field_name, dictionary) {

  cat("=== EXTRACT_VALUE_LABELS DEBUG ===\n")
  cat("Field name:", field_name, "\n")
  cat("Dictionary names (first 5):", paste(head(names(dictionary), 5), collapse=", "), "\n")

  # Save test data for rapid debugging
  test_data_dir <- "temp/value_labels_test_data"
  if (!dir.exists(test_data_dir)) dir.create(test_data_dir, recursive = TRUE)

  saveRDS(field_name, file.path(test_data_dir, "field_name.rds"))
  saveRDS(dictionary, file.path(test_data_dir, "dictionary.rds"))
  cat("Value labels test data saved to:", test_data_dir, "\n")

  if (!field_name %in% names(dictionary)) {
    warning(paste("Field", field_name, "not found in dictionary"))
    return(data.frame(value = character(), label = character()))
  }

  choices_string <- dictionary[[field_name]]$select_choices_or_calculations
  cat("Choices string type:", class(choices_string), "\n")
  cat("Choices string length:", length(choices_string), "\n")
  cat("Choices string content (first 100 chars):", substr(paste(choices_string, collapse=" | "), 1, 100), "\n")

  if (is.null(choices_string) || all(choices_string == "")) {
    return(data.frame(value = character(), label = character()))
  }

  # Parse choices string (format: "1, Choice 1 | 2, Choice 2")
  cat("About to call str_split_1 with choices_string...\n")
  choices <- tryCatch({
    stringr::str_split_1(choices_string, " \\| ")
  }, error = function(e) {
    cat("ERROR in str_split_1:", e$message, "\n")
    cat("Choices string causing error:", choices_string, "\n")
    stop(e)
  })

  result <- data.frame(value = character(), label = character())

  for (choice in choices) {
    cat("Processing choice:", choice, "\n")
    parts <- tryCatch({
      stringr::str_split_1(choice, ", ")
    }, error = function(e) {
      cat("ERROR in str_split_1 for choice:", choice, "\n")
      cat("Error message:", e$message, "\n")
      stop(e)
    })
    if (length(parts) >= 2) {
      value <- parts[1]
      label <- paste(parts[-1], collapse = ", ")
      result <- rbind(result, data.frame(value = value, label = label))
    }
  }

  return(result)
}

#' Get Nebraska ZIP code to county crosswalk
#'
#' Queries the database for ZIP/county mapping data
#'
#' @return Data frame mapping ZIP codes to acceptable counties
get_nebraska_zip_county_crosswalk <- function() {
  # Query from database instead of loading Excel file
  tryCatch({
    conn <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

    result <- DBI::dbGetQuery(conn, "SELECT zip_code, acceptable_counties FROM ne_zip_county_crosswalk")

    DBI::dbDisconnect(conn, shutdown = TRUE)

    if (nrow(result) > 0) {
      message("Loaded ", nrow(result), " ZIP codes from database")
      return(result)
    } else {
      warning("ne_zip_county_crosswalk table is empty")
      return(data.frame(
        zip_code = character(),
        acceptable_counties = character(),
        stringsAsFactors = FALSE
      ))
    }

  }, error = function(e) {
    warning("Error loading ZIP code data from database: ", e$message)
    warning("Run scripts/setup/load_zip_crosswalk.R to load crosswalk data")
    return(data.frame(
      zip_code = character(),
      acceptable_counties = character(),
      stringsAsFactors = FALSE
    ))
  })
}


#' Get eligibility criteria definitions (matching Dashboard categorization)
#'
#' @return Data frame with criteria definitions
get_eligibility_criteria_definitions <- function() {

  # Updated to 8 criteria with CID8 (KMT quality) removed
  # Original CID9 is now CID8
  definitions <- data.frame(
    cid = 1:8,
    category = c("Compensation", "Eligibility", "Eligibility", "Eligibility",
                 "Eligibility", "Authenticity", "Authenticity", "Compensation"),
    action = c("Exclusion", "Exclusion", "Inclusion", "Inclusion", "Inclusion",
               "Exclusion", "Exclusion", "Exclusion"),
    description = c(
      "Failed to acknowledge compensation terms and conditions",
      "Failed to provide informed consent",
      "Respondent is 19 years or older and a primary caregiver",
      "Child is 2191 days or younger",
      "Currently lives in the state of Nebraska",
      "ZIP code does not match reported county",
      "Child's birthday failed to be confirmed",
      "Did not complete all required modules of survey"
    ),
    stringsAsFactors = FALSE
  )

  return(definitions)
}

#' Load Kidsights ZIP code data
#'
#' Loads the ZIP code to county crosswalk data
#' @param data_dir Directory containing ZIP code data file
#' @return Data frame with ZIP codes and acceptable counties
load_kidsights_zip_data <- function(data_dir = "data") {

  zip_file <- file.path(data_dir, "Zip_County_Code_UPDATED10.18.xlsx")

  if(file.exists(zip_file) && "readxl" %in% loadedNamespaces()) {
    tryCatch({
      zipcodes_df <- readxl::read_excel(
        path = zip_file,
        sheet = "Master"
      ) %>%
        mutate(County = stringr::str_remove_all(County, " County")) %>%
        group_by(ZipCode) %>%
        reframe(acceptable_counties = paste(County, collapse = "; ")) %>%
        mutate(ZipCode = as.character(ZipCode))

      return(zipcodes_df)
    }, error = function(e) {
      warning("Could not load ZIP code data: ", e$message)
      return(get_nebraska_zip_county_crosswalk())
    })
  } else {
    if(!file.exists(zip_file)) {
      warning("ZIP code data file not found: ", zip_file)
    }
    return(get_nebraska_zip_county_crosswalk())
  }
}