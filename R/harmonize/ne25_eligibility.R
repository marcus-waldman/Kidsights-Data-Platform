#' NE25 Eligibility Validation Functions
#'
#' Port of eligibility checking functions from the dashboard utils-eligibility.R
#' Implements the 9 eligibility criteria (CID1-CID9) for the NE25 study
#'
#' All participants must pass eligibility AND authenticity checks for inclusion

library(dplyr)
library(stringr)
library(tidyr)

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
    select(pid, record_id, any_of(required_fields)) %>%
    rowwise() %>%
    mutate(
      pass_cid1 = sum(c_across(all_of(intersect(required_fields, names(.)))), na.rm = TRUE) == 4
    ) %>%
    ungroup() %>%
    select(pid, record_id, pass_cid1)

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
    select(pid, record_id, eq001) %>%
    mutate(
      pass_cid2 = eq001 == 1 & !is.na(eq001)
    ) %>%
    select(pid, record_id, pass_cid2)

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
    select(pid, record_id, eq003, eq002) %>%
    mutate(
      pass_cid3 = (eq002 == 1 & eq003 == 1) & !is.na(eq002) & !is.na(eq003)
    ) %>%
    select(pid, record_id, pass_cid3)

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
    select(pid, record_id, age_in_days) %>%
    mutate(
      pass_cid4 = (age_in_days <= 2191) & !is.na(age_in_days)
    ) %>%
    select(pid, record_id, pass_cid4)

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
    select(pid, record_id, eqstate) %>%
    mutate(
      pass_cid5 = (eqstate == 1) & !is.na(eqstate)
    ) %>%
    select(pid, record_id, pass_cid5)

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
    select(pid, record_id, sq001, fq001) %>%
    # Ensure fq001 is character for consistent joining
    mutate(fq001 = as.character(fq001)) %>%
    # Map county codes to labels
    left_join(
      county_labels %>%
        rename(fq001 = value, county_name = label) %>%
        mutate(fq001 = as.character(fq001)),  # Ensure same type
      by = "fq001"
    ) %>%
    # Get acceptable ZIP codes for each county
    left_join(
      get_nebraska_zip_county_crosswalk(),
      by = c("sq001" = "zip_code")
    ) %>%
    mutate(
      # Check if reported county is in the acceptable counties for this ZIP
      pass_cid6 = !is.na(county_name) & !is.na(acceptable_counties) &
                  str_detect(acceptable_counties, fixed(county_name))
    ) %>%
    select(pid, record_id, pass_cid6)

  return(cid6_result)
}

#' Check CID7: Birthday confirmation
#'
#' Validates that child's birthday was confirmed
#'
#' @param data Data frame with date_complete_check field
#' @return Data frame with CID7 pass/fail status
check_cid7_birthday <- function(data) {

  cid7_result <- data %>%
    select(pid, record_id, date_complete_check) %>%
    mutate(
      pass_cid7 = (date_complete_check == 1) & !is.na(date_complete_check)
    ) %>%
    select(pid, record_id, pass_cid7)

  return(cid7_result)
}

#' Check CID8: KMT response quality
#'
#' Validates KMT assessment quality based on non-"Don't Know" responses
#' and z-score distribution
#'
#' @param data Data frame with KMT assessment data
#' @param config Configuration with KMT field specifications
#' @return Data frame with CID8 pass/fail status
check_cid8_kmt_quality <- function(data, config) {

  # Get KMT items from configuration
  kmt_items <- get_kmt_items_from_config(config)

  # Minimum thresholds
  min_responses <- config$validation$kmt_min_responses %||% 10
  max_zscore <- config$validation$kmt_zscore_threshold %||% 5

  cid8_result <- data %>%
    select(pid, record_id, any_of(kmt_items)) %>%
    rowwise() %>%
    mutate(
      # Count non-missing, non-"Don't Know" responses
      kmt_valid_responses = sum(!is.na(c_across(any_of(kmt_items))), na.rm = TRUE),

      # Calculate mean score for z-score analysis
      kmt_mean_score = mean(c_across(any_of(kmt_items)), na.rm = TRUE)
    ) %>%
    ungroup() %>%
    mutate(
      # Calculate z-scores based on population distribution
      kmt_zscore = abs(scale(kmt_mean_score)[,1]),

      # Apply CID8 criteria
      pass_cid8 = (kmt_valid_responses >= min_responses) &
                  (kmt_zscore <= max_zscore | is.na(kmt_zscore))
    ) %>%
    select(pid, record_id, pass_cid8)

  return(cid8_result)
}

#' Check CID9: Survey completion
#'
#' Validates that all required survey modules were completed
#'
#' @param data Data frame with completion status fields
#' @param config Configuration with required modules
#' @return Data frame with CID9 pass/fail status
check_cid9_completion <- function(data, config) {

  # Get required completion fields
  required_modules <- config$validation$required_modules %||% c("demographics", "child_demographics", "screening_questions")
  completion_fields <- paste0(required_modules, "_complete")

  # Required completion status (2 = Complete in REDCap)
  required_status <- config$validation$completion_status_required %||% 2

  cid9_result <- data %>%
    select(pid, record_id, any_of(completion_fields)) %>%
    rowwise() %>%
    mutate(
      # Check if all required modules are complete
      modules_complete = all(c_across(any_of(completion_fields)) == required_status, na.rm = FALSE),
      pass_cid9 = modules_complete & !is.na(modules_complete)
    ) %>%
    ungroup() %>%
    select(pid, record_id, pass_cid9)

  return(cid9_result)
}

#' Master eligibility checking function
#'
#' Applies all 9 eligibility criteria and generates summary
#'
#' @param data Raw NE25 survey data
#' @param data_dictionary REDCap data dictionary
#' @param config NE25 configuration
#' @return List with eligibility summary and details
check_ne25_eligibility <- function(data, data_dictionary, config) {

  # Apply all eligibility checks
  cid_results <- data %>%
    select(pid, record_id, retrieved_date) %>%
    left_join(check_cid1_compensation(data), by = c("pid", "record_id")) %>%
    left_join(check_cid2_consent(data), by = c("pid", "record_id")) %>%
    left_join(check_cid3_caregiver(data), by = c("pid", "record_id")) %>%
    left_join(check_cid4_child_age(data), by = c("pid", "record_id")) %>%
    left_join(check_cid5_nebraska(data), by = c("pid", "record_id")) %>%
    left_join(check_cid6_zip_county(data, data_dictionary), by = c("pid", "record_id")) %>%
    left_join(check_cid7_birthday(data), by = c("pid", "record_id")) %>%
    left_join(check_cid8_kmt_quality(data, config), by = c("pid", "record_id")) %>%
    left_join(check_cid9_completion(data, config), by = c("pid", "record_id"))

  # Convert to long format for detailed analysis
  eligibility_long <- cid_results %>%
    pivot_longer(
      cols = starts_with("pass_cid"),
      names_to = "cid",
      values_to = "pass"
    ) %>%
    mutate(
      cid_number = as.integer(str_extract(cid, "\\d+"))
    ) %>%
    left_join(
      get_eligibility_criteria_definitions(config),
      by = c("cid_number" = "cid")
    )

  # Create summary by category
  eligibility_summary <- eligibility_long %>%
    group_by(retrieved_date, pid, record_id, category) %>%
    summarise(
      status = ifelse(all(pass, na.rm = TRUE), "Pass", "Fail"),
      .groups = "drop"
    ) %>%
    pivot_wider(
      names_from = category,
      values_from = status
    ) %>%
    rename_with(tolower) %>%
    relocate(retrieved_date, pid, record_id, eligibility, authenticity, compensation)

  # Get mailing addresses for eligible participants
  mailing_info <- data %>%
    select(pid, record_id, matches("q139[4-8]")) # q1394:q1398

  return(list(
    summary = eligibility_summary,
    details = eligibility_long,
    mailing = mailing_info,
    criteria_definitions = get_eligibility_criteria_definitions(config)
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

  data_with_eligibility <- data %>%
    left_join(
      eligibility_results$summary,
      by = c("retrieved_date", "pid", "record_id")
    ) %>%
    mutate(
      # Overall inclusion flag
      eligible = eligibility == "Pass",
      authentic = authenticity == "Pass",
      include = eligible & authentic
    )

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

  if (!field_name %in% names(dictionary)) {
    warning(paste("Field", field_name, "not found in dictionary"))
    return(data.frame(value = character(), label = character()))
  }

  choices_string <- dictionary[[field_name]]$select_choices_or_calculations

  if (is.null(choices_string) || choices_string == "") {
    return(data.frame(value = character(), label = character()))
  }

  # Parse choices string (format: "1, Choice 1 | 2, Choice 2")
  choices <- str_split_1(choices_string, " \\| ")

  result <- data.frame(value = character(), label = character())

  for (choice in choices) {
    parts <- str_split_1(choice, ", ")
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
#' @return Data frame mapping ZIP codes to acceptable counties
get_nebraska_zip_county_crosswalk <- function() {
  # This would typically read from a reference file
  # Placeholder implementation
  data.frame(
    zip_code = c("68001", "68101", "68503"),
    acceptable_counties = c("Douglas; Sarpy", "Douglas", "Lancaster"),
    stringsAsFactors = FALSE
  )
}

#' Get KMT items from configuration
#'
#' @param config Configuration list
#' @return Vector of KMT field names
get_kmt_items_from_config <- function(config) {
  # This would extract KMT field names from configuration
  # Placeholder implementation
  paste0("kmt_", sprintf("%03d", 1:30))
}

#' Get eligibility criteria definitions
#'
#' @param config Configuration list
#' @return Data frame with criteria definitions
get_eligibility_criteria_definitions <- function(config) {

  criteria <- config$eligibility_criteria

  definitions <- data.frame(
    cid = 1:9,
    category = c("Compensation", "Eligibility", "Eligibility", "Eligibility",
                 "Eligibility", "Authenticity", "Authenticity", "Authenticity",
                 "Compensation"),
    action = c("Exclusion", "Exclusion", "Inclusion", "Inclusion", "Inclusion",
               "Exclusion", "Exclusion", "Exclusion", "Exclusion"),
    description = c(
      "Failed to acknowledge compensation terms and conditions",
      "Failed to provide informed consent",
      "Respondent is 19 years or older and a primary caregiver",
      "Child is 2191 days or younger",
      "Currently lives in the state of Nebraska",
      "ZIP code does not match reported county",
      "Child's birthday failed to be confirmed",
      "Less than 10 valid KMT responses or z-score outside 5SD",
      "Did not complete all required modules of survey"
    ),
    stringsAsFactors = FALSE
  )

  return(definitions)
}