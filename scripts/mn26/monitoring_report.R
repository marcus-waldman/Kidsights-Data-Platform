#' MN26 Sample Monitoring Report
#'
#' Standalone script for NORC researchers to monitor MN26 recruitment progress
#' and demographic distribution during data collection.
#'
#' TEMPLATE STATUS: Currently uses NE25 data as template
#' Once MN26 data collection begins, update the variables marked with [MN26 TODO]
#'
#' [MN26 TODO] MULTI-CHILD HOUSEHOLDS: MN26 allows up to 2 children per household.
#' The current code assumes 1 child per record (NE25 structure). When MN26 data is
#' available, the child demographics and eligibility logic must be updated to handle
#' multiple children per record. This may require pivoting to long format (1 row per
#' child) or adding child-specific columns (e.g., age_in_days_child1, age_in_days_child2).
#' The REDCap structure (repeating instruments vs. separate fields) will determine approach.
#'
#' [MN26 TODO] GEOGRAPHY: Participant mailing addresses (where invitations were sent)
#' can be linked via pid + record_id from a separate address dataset. Future versions
#' may add geocoding (tidygeocoder + Census Bureau geocoder) to derive lat/long, county,
#' census tract, PUMA, and urban/rural classifications for geographic monitoring.
#'
#' Usage:
#'   source("scripts/mn26/monitoring_report.R")
#'   monitoring_data <- generate_monitoring_report(csv_path = "C:/path/to/mn26_api.csv")
#'
#' Returns:
#'   List with 5 data frames:
#'     - screener_status: Screener completion (eligibility known/unknown)
#'     - eligibility: Eligibility determination (4 criteria)
#'     - survey_completion: Survey module completion status
#'     - child_demographics: Child age and sex
#'     - parent_demographics: Parent age, sex, race/ethnicity, education, marital status

# ============================================================================
# SETUP
# ============================================================================

# Load required packages
library(dplyr)
library(tidyr)
library(REDCapR)
library(httr)

# ============================================================================
# LOAD UTILITY FUNCTIONS
# ============================================================================

# Get the directory where this script is located
script_dir <- if (sys.nframe() == 0) {
  # Running interactively or via source()
  dirname(sys.frame(1)$ofile)
} else {
  # Running via Rscript
  dirname(normalizePath(sys.frame(1)$ofile))
}

# Source utility files (self-contained, no external dependencies)
source(file.path(script_dir, "utils", "safe_joins.R"))
source(file.path(script_dir, "utils", "redcap_utils.R"))
source(file.path(script_dir, "utils", "data_transforms.R"))

# ============================================================================
# STUDY-SPECIFIC FUNCTIONS
# ============================================================================

#' Calculate eligibility status
#'
#' Determines eligibility based on 4 criteria:
#' 1. Parent age >= 19
#' 2. Child age 0-5 years
#' 3. Primary caregiver = Yes
#' 4. Lives in Minnesota
#'
#' [MN26 TODO] Update variable names once MN26 data dictionary is available
#'
#' @param data Raw or transformed REDCap data
#' @return Data frame with eligibility columns
calculate_eligibility <- function(data) {

  message("Calculating eligibility...")

  # [MN26 TODO] Update these variable names to match MN26 REDCap structure
  eligibility_df <- data %>%
    dplyr::mutate(
      # Criterion 1: Parent age >= 19
      parent_age_eligible = (eq003 == 1) & !is.na(eq003),

      # Criterion 2: Child age 0-5 years (1825 days)
      # [MN26 TODO] MN26 cutoff: 1825 days (5 years) vs NE25's 2191 days (6 years)
      # [MN26 TODO] MULTI-CHILD: Check age eligibility per child (up to 2 per household)
      child_age_eligible = (age_in_days <= 1825) & !is.na(age_in_days),

      # Criterion 3: Primary caregiver = Yes
      primary_caregiver_eligible = (eq002 == 1) & !is.na(eq002),

      # Criterion 4: Lives in state
      # [MN26 TODO] Update to Minnesota state code
      state_eligible = (eqstate == 1) & !is.na(eqstate),

      # Overall eligibility
      eligible = parent_age_eligible & child_age_eligible &
                 primary_caregiver_eligible & state_eligible
    ) %>%
    dplyr::select(
      pid, record_id,
      parent_age_eligible, child_age_eligible,
      primary_caregiver_eligible, state_eligible,
      eligible
    )

  message("[OK] Eligibility: ",
          sum(eligibility_df$eligible, na.rm = TRUE), " eligible, ",
          sum(!eligibility_df$eligible, na.rm = TRUE), " not eligible")

  return(eligibility_df)
}

#' Calculate screener completion status
#'
#' Screener is "complete" if eligibility is known (not missing)
#'
#' @param eligibility_data Data frame from calculate_eligibility()
#' @return Data frame with screener completion status
calculate_screener_status <- function(eligibility_data) {

  message("Calculating screener completion status...")

  screener_df <- eligibility_data %>%
    dplyr::mutate(
      screener_complete = !is.na(eligible),
      screener_status = ifelse(screener_complete, "Complete", "Incomplete")
    ) %>%
    dplyr::select(pid, record_id, screener_complete, screener_status)

  message("[OK] Screener: ",
          sum(screener_df$screener_complete, na.rm = TRUE), " complete, ",
          sum(!screener_df$screener_complete, na.rm = TRUE), " incomplete")

  return(screener_df)
}

#' Calculate survey completion status
#'
#' Survey is "complete" if all required modules are marked as complete (status = 2)
#'
#' [MN26 TODO] Update module list to match MN26 survey structure
#'
#' @param data Raw REDCap data
#' @return Data frame with survey completion status
calculate_survey_completion <- function(data) {

  message("Calculating survey completion status...")

  # [MN26 TODO] Update module list to match MN26 survey structure
  required_modules <- paste0("module_", c(2, 3, 4, 5, 6, 7, 9), "_complete")
  available_modules <- intersect(required_modules, names(data))

  if (length(available_modules) == 0) {
    warning("No module completion fields found in data. Survey completion cannot be determined.")
    return(data %>%
             dplyr::select(pid, record_id) %>%
             dplyr::mutate(survey_complete = NA, survey_status = "Unknown"))
  }

  # Module numbers in order for "last complete" tracking
  # [MN26 TODO] Update module numbers to match MN26 survey structure
  module_numbers <- c(2, 3, 4, 5, 6, 7, 9)
  n_required <- length(available_modules)

  completion_df <- data %>%
    dplyr::select(pid, record_id, dplyr::all_of(available_modules)) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      modules_complete = sum(dplyr::c_across(dplyr::all_of(available_modules)) == 2, na.rm = TRUE),
      pct_complete = round(modules_complete / n_required * 100, 1),
      survey_complete = (modules_complete == n_required),
      survey_status = ifelse(survey_complete, "Complete", "Incomplete")
    ) %>%
    dplyr::ungroup()

  # Determine last completed module per participant
  # Walk modules in order; the last one with status == 2 is the "last complete"
  last_module <- rep(NA_character_, nrow(completion_df))
  for (j in seq_along(available_modules)) {
    col <- available_modules[j]
    is_complete <- !is.na(completion_df[[col]]) & completion_df[[col]] == 2
    last_module[is_complete] <- paste0("Module ", module_numbers[j])
  }
  completion_df$last_module_complete <- last_module

  completion_df <- completion_df %>%
    dplyr::select(pid, record_id, modules_complete, pct_complete,
                  last_module_complete, survey_complete, survey_status)

  message("[OK] Survey: ",
          sum(completion_df$survey_complete, na.rm = TRUE), " complete, ",
          sum(!completion_df$survey_complete, na.rm = TRUE), " incomplete")

  return(completion_df)
}

#' Extract child demographics
#'
#' [MN26 TODO] MULTI-CHILD: MN26 allows up to 2 children per household.
#' This function currently returns 1 row per record (1 child). For MN26,
#' pivot to long format so each child gets its own row, with a child_number
#' column (1 or 2) to distinguish them. Child-level eligibility (age 0-5)
#' should also be checked per child.
#'
#' @param data Transformed data
#' @return Data frame with child age and sex
extract_child_demographics <- function(data) {

  message("Extracting child demographics...")

  child_demo <- data %>%
    dplyr::select(pid, record_id,
                  age_years = years_old,
                  sex)

  message("[OK] Child demographics: ", nrow(child_demo), " records")
  return(child_demo)
}

#' Extract parent demographics
#'
#' @param data Transformed data
#' @return Data frame with parent demographics
extract_parent_demographics <- function(data) {

  message("Extracting parent demographics...")

  parent_demo <- data %>%
    dplyr::select(pid, record_id,
                  age_years = a1_years_old,
                  female = female_a1,
                  race_ethnicity = a1_raceG,
                  education = educ_a1,
                  marital_status_label)

  message("[OK] Parent demographics: ", nrow(parent_demo), " records")
  return(parent_demo)
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

#' Generate monitoring report
#'
#' Main function that orchestrates all monitoring components.
#' Pass the path to your API credentials CSV and it does everything.
#'
#' @param csv_path Path to API credentials CSV file (columns: project, pid, api_code)
#' @param redcap_url REDCap API URL (defaults to Nebraska URL as template)
#' @return List with 5 data frames
#' @export
generate_monitoring_report <- function(csv_path,
                                      redcap_url = "https://unmcredcap.unmc.edu/redcap/api/") {

  cat("\n=== MN26 SAMPLE MONITORING REPORT ===\n\n")

  # Step 1: Load API credentials
  credentials <- load_api_credentials(csv_path)

  # Step 2: Pull raw data from REDCap
  api_result <- pull_redcap_data(credentials, redcap_url)
  raw_data <- api_result$data
  dictionary <- api_result$dictionary

  # Step 3: Transform raw data into monitoring variables
  transformed_data <- transform_raw_data(raw_data, dictionary)

  # Step 4: Calculate eligibility
  eligibility <- calculate_eligibility(raw_data)

  # Step 5: Calculate screener completion
  screener_status <- calculate_screener_status(eligibility)

  # Step 6: Calculate survey completion
  survey_completion <- calculate_survey_completion(raw_data)

  # Step 7: Extract demographics
  child_demographics <- extract_child_demographics(transformed_data)
  parent_demographics <- extract_parent_demographics(transformed_data)

  # Return organized results
  results <- list(
    screener_status = screener_status,
    eligibility = eligibility,
    survey_completion = survey_completion,
    child_demographics = child_demographics,
    parent_demographics = parent_demographics
  )

  cat("\n=== MONITORING REPORT COMPLETE ===\n")
  cat("Access data frames:\n")
  cat("  - $screener_status (", nrow(screener_status), " records)\n", sep = "")
  cat("  - $eligibility (", nrow(eligibility), " records)\n", sep = "")
  cat("  - $survey_completion (", nrow(survey_completion), " records)\n", sep = "")
  cat("  - $child_demographics (", nrow(child_demographics), " records)\n", sep = "")
  cat("  - $parent_demographics (", nrow(parent_demographics), " records)\n\n", sep = "")

  return(results)
}

# ============================================================================
# EXAMPLE USAGE (uncomment to run)
# ============================================================================
#
# # 1. Create API credentials CSV file (see mn26_redcap_api_template.csv)
# #    Format: project,pid,api_code
# #    Example: mn26_main_survey,7679,ABC123XYZ...
#
# csv_file_path = "C:/Users/marcu/my-APIs/kidsights_redcap_api.csv"
#
# # 2. Generate monitoring report
# monitoring_data <- generate_monitoring_report(csv_path = csv_file_path)
#
# # View screener completion summary
# table(monitoring_data$screener_status$screener_status)
#
# # View eligibility summary
# table(monitoring_data$eligibility$eligible)
#
# # View survey completion summary
# table(monitoring_data$survey_completion$survey_status)
#
# # View child demographics
# head(monitoring_data$child_demographics)
# summary(monitoring_data$child_demographics$age_years)
# table(monitoring_data$child_demographics$sex)
#
# # View parent demographics
# head(monitoring_data$parent_demographics)
# summary(monitoring_data$parent_demographics$age_years)
# table(monitoring_data$parent_demographics$race_ethnicity)
# table(monitoring_data$parent_demographics$education)
# table(monitoring_data$parent_demographics$marital_status_label)
