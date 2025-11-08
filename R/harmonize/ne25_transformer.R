#' NE25 Data Transformation and Recoding Functions
#'
#' Port of variable recoding functions from dashboard utils-etl.R
#' Transforms raw NE25 survey data into analysis-ready variables
#'
#' Handles race/ethnicity, education, income, age, and other demographic variables

library(dplyr)
library(tidyr)
library(stringr)
library(labelled)

#' Master transformation function for NE25 data
#'
#' Applies all variable transformations and creates analysis-ready dataset
#'
#' @param data Raw NE25 data with eligibility flags
#' @param data_dictionary REDCap data dictionary
#' @param config NE25 configuration
#' @param categories Vector of variable categories to transform (default: all)
#' @return Transformed data frame with recoded variables
transform_ne25_data <- function(data, data_dictionary, config, categories = "all") {

  if (categories == "all") {
    categories <- get_ne25_transformation_categories()
  }

  # Start with original data
  transformed_data <- data

  # Apply each category of transformations
  for (category in categories) {

    message(paste("Transforming category:", category))

    category_data <- transform_ne25_category(
      data = data,
      dictionary = data_dictionary,
      config = config,
      category = category
    )

    # Join the transformed variables
    if (!is.null(category_data) && nrow(category_data) > 0) {
      transformed_data <- transformed_data %>%
        safe_left_join(category_data, by_vars = c("pid", "record_id"))
    }
  }

  return(transformed_data)
}

#' Transform a specific category of NE25 variables
#'
#' @param data Raw NE25 data
#' @param dictionary REDCap data dictionary
#' @param config NE25 configuration
#' @param category Category to transform
#' @return Data frame with transformed variables for this category
transform_ne25_category <- function(data, dictionary, config, category) {

  switch(category,
    "include" = transform_inclusion_flags(data),
    "race" = transform_race_ethnicity(data, dictionary),
    "education" = transform_education(data, dictionary),
    "income" = transform_income_poverty(data, dictionary, config),
    "age" = transform_age_variables(data),
    "sex" = transform_sex_gender(data),
    "caregiver_relationship" = transform_caregiver_relationship(data, dictionary),
    "survey_completion" = transform_survey_completion(data),
    "mental_health" = transform_mental_health(data, config),
    "childcare" = transform_childcare_variables(data, dictionary),
    NULL
  )
}

#' Transform inclusion/eligibility flags
#'
#' @param data Data with eligibility results
#' @return Data frame with standardized inclusion variables
transform_inclusion_flags <- function(data) {

  inclusion_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      eligible = data$eligibility == "Pass",
      authentic = data$authenticity == "Pass",
      include = eligible & authentic
    )

  # Add variable labels
  var_label(inclusion_data$eligible) <- "Meets study inclusion criteria"
  var_label(inclusion_data$authentic) <- "Passes authenticity screening"
  var_label(inclusion_data$include) <- "Meets inclusion criteria (eligible + authentic)"

  return(inclusion_data)
}

#' Transform race and ethnicity variables
#'
#' Based on the race/ethnicity transformation logic from dashboard
#'
#' @param data Raw survey data
#' @param dictionary REDCap data dictionary
#' @return Data frame with race/ethnicity variables
transform_race_ethnicity <- function(data, dictionary) {

  # Child race/ethnicity
  child_race <- data %>%
    select(pid, record_id, starts_with("cqr011"), starts_with("cqr010_")) %>%
    pivot_longer(
      cols = starts_with("cqr010"),
      names_to = "var",
      values_to = "response"
    ) %>%
    # Get race labels from dictionary
    safe_left_join(
      extract_value_labels("cqr010", dictionary) %>%
        mutate(var = paste0("cqr010_", value, "___1")) %>%
        select(var, label),
      by_vars = "var"
    ) %>%
    # Collapse Asian/Pacific Islander categories
    mutate(
      label = case_when(
        label %in% c("Asian Indian", "Chinese", "Filipino", "Japanese",
                     "Korean", "Vietnamese", "Native Hawaiian",
                     "Guamanian or Chamorro", "Samoan", "Other Pacific Islander") ~
          "Asian or Pacific Islander",
        label %in% c("Middle Eastern", "Some other race") ~ "Some Other Race",
        TRUE ~ label
      )
    ) %>%
    filter(response == 1) %>%
    group_by(pid, record_id, label) %>%
    summarise(
      hisp = ifelse(cqr011[1] == 1, "Hispanic", "non-Hisp."),
      .groups = "drop"
    ) %>%
    group_by(pid, record_id) %>%
    summarise(
      hisp = hisp[1],
      race = ifelse(n() > 1, "Two or More", label[1]),
      .groups = "drop"
    ) %>%
    mutate(
      raceG = ifelse(hisp == "Hispanic", "Hispanic", paste0(race, ", non-Hisp.")),
      raceG = ifelse(raceG == "Other Asian, non-Hisp.", "Asian or Pacific Islander, non-Hisp.", raceG)
    ) %>%
    mutate(across(where(is.character), as.factor)) %>%
    mutate(
      hisp = relevel(as.factor(hisp), ref = "non-Hisp."),
      race = relevel(as.factor(race), ref = "White"),
      raceG = relevel(as.factor(raceG), ref = "White, non-Hisp.")
    )

  # Caregiver race/ethnicity
  caregiver_race <- data %>%
    select(pid, record_id, starts_with("sq003"), starts_with("sq002_")) %>%
    pivot_longer(
      cols = starts_with("sq002_"),
      names_to = "var",
      values_to = "response"
    ) %>%
    safe_left_join(
      extract_value_labels("sq002", dictionary) %>%
        mutate(var = paste0("sq002_", value, "___1")) %>%
        select(var, label),
      by_vars = "var"
    ) %>%
    mutate(
      label = case_when(
        label %in% c("Asian Indian", "Chinese", "Filipino", "Japanese",
                     "Korean", "Vietnamese", "Native Hawaiian",
                     "Guamanian or Chamorro", "Samoan", "Other Pacific Islander") ~
          "Asian or Pacific Islander",
        label %in% c("Middle Eastern", "Some other race") ~ "Some Other Race",
        TRUE ~ label
      )
    ) %>%
    filter(response == 1) %>%
    group_by(pid, record_id, label) %>%
    summarise(
      a1_hisp = ifelse(sq003[1] == 1, "Hispanic", "non-Hisp."),
      .groups = "drop"
    ) %>%
    group_by(pid, record_id) %>%
    summarise(
      a1_hisp = a1_hisp[1],
      a1_race = ifelse(n() > 1, "Two or More", label[1]),
      .groups = "drop"
    ) %>%
    mutate(
      a1_raceG = ifelse(a1_hisp == "Hispanic", "Hispanic", paste0(a1_race, ", non-Hisp.")),
      a1_raceG = ifelse(a1_raceG == "Other Asian, non-Hisp.", "Asian or Pacific Islander, non-Hisp.", a1_raceG)
    ) %>%
    mutate(across(where(is.character), as.factor)) %>%
    mutate(
      a1_hisp = relevel(as.factor(a1_hisp), ref = "non-Hisp."),
      a1_race = relevel(as.factor(a1_race), ref = "White"),
      a1_raceG = relevel(as.factor(a1_raceG), ref = "White, non-Hisp.")
    )

  # Combine child and caregiver race
  race_data <- child_race %>%
    safe_left_join(caregiver_race, by_vars = c("pid", "record_id"))

  # Add variable labels
  var_label(race_data$hisp) <- "Child Hispanic/Latino ethnicity"
  var_label(race_data$race) <- "Child race (collapsed categories)"
  var_label(race_data$raceG) <- "Child race/ethnicity combined"
  var_label(race_data$a1_hisp) <- "Primary caregiver Hispanic/Latino ethnicity"
  var_label(race_data$a1_race) <- "Primary caregiver race (collapsed categories)"
  var_label(race_data$a1_raceG) <- "Primary caregiver race/ethnicity combined"

  return(race_data)
}

#' Transform education variables
#'
#' Creates multiple education category systems (4, 6, 8 categories)
#'
#' @param data Raw survey data
#' @param dictionary REDCap data dictionary
#' @return Data frame with education variables
transform_education <- function(data, dictionary) {

  # This would implement the education transformation logic
  # Placeholder for now - would need to map actual education fields

  education_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      # 4-category education system
      educ4 = factor("Some college", levels = c("Less than HS", "HS/GED", "Some college", "Bachelor+")),
      educ4_mom = factor("Some college", levels = c("Less than HS", "HS/GED", "Some college", "Bachelor+")),
      educ4_max = factor("Some college", levels = c("Less than HS", "HS/GED", "Some college", "Bachelor+")),

      # 6-category system
      educ6 = factor("Some college", levels = c("Less than HS", "HS/GED", "Some college", "Associate", "Bachelor", "Graduate")),

      # 8-category system
      educ8 = factor("Some college", levels = c("Less than HS", "Some HS", "HS/GED", "Some college", "Associate", "Bachelor", "Some graduate", "Graduate"))
    )

  # Add variable labels
  var_label(education_data$educ4) <- "Primary caregiver education (4 categories)"
  var_label(education_data$educ4_mom) <- "Mother's education (4 categories)"
  var_label(education_data$educ4_max) <- "Maximum household education (4 categories)"
  var_label(education_data$educ6) <- "Primary caregiver education (6 categories)"
  var_label(education_data$educ8) <- "Primary caregiver education (8 categories)"

  return(education_data)
}

#' Transform income and poverty variables
#'
#' Creates CPI-adjusted income and federal poverty level calculations
#'
#' @param data Raw survey data
#' @param dictionary REDCap data dictionary
#' @param config Configuration with CPI adjustment settings
#' @return Data frame with income/poverty variables
transform_income_poverty <- function(data, dictionary, config) {

  # This would implement income transformation and FPL calculations
  # Placeholder implementation

  income_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      # Raw household income (would map from actual field)
      household_income = 50000,

      # CPI-adjusted income (if enabled in config)
      household_income_cpi = household_income * 1.05,  # Placeholder CPI adjustment

      # Family size (would map from actual field)
      family_size = 3,

      # Federal poverty level calculation
      federal_poverty_level = calculate_fpl_percentage(household_income_cpi, family_size),

      # FPL categories
      fplcat = case_when(
        federal_poverty_level < 100 ~ "<100%",
        federal_poverty_level < 200 ~ "100-199%",
        federal_poverty_level < 300 ~ "200-299%",
        federal_poverty_level < 400 ~ "300-399%",
        TRUE ~ "400%+"
      ),
      fplcat = factor(fplcat, levels = c("<100%", "100-199%", "200-299%", "300-399%", "400%+"))
    )

  # Add variable labels
  var_label(income_data$household_income) <- "Household income (raw)"
  var_label(income_data$household_income_cpi) <- "Household income (CPI-adjusted)"
  var_label(income_data$federal_poverty_level) <- "Federal poverty level percentage"
  var_label(income_data$fplcat) <- "Federal poverty level categories"

  return(income_data)
}

#' Transform age variables
#'
#' @param data Raw survey data
#' @return Data frame with age variables
transform_age_variables <- function(data) {

  age_data <- data %>%
    select(pid, record_id, age_in_days) %>%
    mutate(
      # Child age in years
      child_age_years = age_in_days / 365.25,

      # Child age groups
      child_age_group = case_when(
        age_in_days <= 365 ~ "0-1 years",
        age_in_days <= 730 ~ "1-2 years",
        age_in_days <= 1095 ~ "2-3 years",
        age_in_days <= 1460 ~ "3-4 years",
        age_in_days <= 1825 ~ "4-5 years",
        age_in_days <= 2191 ~ "5-6 years",
        TRUE ~ ">6 years"
      ),
      child_age_group = factor(child_age_group),

      # Birth year calculated from age_in_days
      birth_year = as.numeric(format(Sys.Date() - age_in_days, "%Y"))
    )

  # Add variable labels
  var_label(age_data$child_age_years) <- "Child age in years"
  var_label(age_data$child_age_group) <- "Child age groups"
  var_label(age_data$birth_year) <- "Child birth year"

  return(age_data)
}

#' Transform sex and gender variables
#'
#' @param data Raw survey data
#' @return Data frame with sex/gender variables
transform_sex_gender <- function(data) {

  # Placeholder - would map from actual sex field
  sex_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      child_sex = factor("Female", levels = c("Male", "Female", "Other")),
      child_gender = factor("Girl", levels = c("Boy", "Girl", "Other"))
    )

  # Add variable labels
  var_label(sex_data$child_sex) <- "Child biological sex"
  var_label(sex_data$child_gender) <- "Child gender identity"

  return(sex_data)
}

#' Transform caregiver relationship variables
#'
#' @param data Raw survey data
#' @param dictionary REDCap data dictionary
#' @return Data frame with relationship variables
transform_caregiver_relationship <- function(data, dictionary) {

  # Placeholder implementation
  relationship_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      caregiver_relationship = factor("Mother", levels = c("Mother", "Father", "Grandparent", "Other")),
      is_mother = caregiver_relationship == "Mother",
      is_father = caregiver_relationship == "Father"
    )

  # Add variable labels
  var_label(relationship_data$caregiver_relationship) <- "Primary caregiver relationship to child"
  var_label(relationship_data$is_mother) <- "Primary caregiver is mother"
  var_label(relationship_data$is_father) <- "Primary caregiver is father"

  return(relationship_data)
}

#' Transform survey completion variables
#'
#' @param data Raw survey data
#' @return Data frame with completion tracking variables
transform_survey_completion <- function(data) {

  # Placeholder implementation
  completion_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      survey_complete = TRUE,
      modules_completed = 5,
      completion_rate = 1.0
    )

  # Add variable labels
  var_label(completion_data$survey_complete) <- "Survey fully completed"
  var_label(completion_data$modules_completed) <- "Number of modules completed"
  var_label(completion_data$completion_rate) <- "Survey completion rate"

  return(completion_data)
}

#' Transform mental health variables
#'
#' @param data Raw survey data
#' @param config Configuration
#' @return Data frame with mental health scores
transform_mental_health <- function(data, config) {

  # Placeholder for ACE scores, anxiety, depression scales
  mental_health_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      ace_score = 2,
      anxiety_score = 5,
      depression_score = 3
    )

  # Add variable labels
  var_label(mental_health_data$ace_score) <- "Adverse Childhood Experiences score"
  var_label(mental_health_data$anxiety_score) <- "Anxiety symptom score"
  var_label(mental_health_data$depression_score) <- "Depression symptom score"

  return(mental_health_data)
}

#' Transform childcare variables
#'
#' @param data Raw survey data
#' @param dictionary REDCap data dictionary
#' @return Data frame with childcare variables
transform_childcare_variables <- function(data, dictionary) {

  # Placeholder implementation
  childcare_data <- data %>%
    select(pid, record_id) %>%
    mutate(
      childcare_type = factor("Family daycare", levels = c("No care", "Family daycare", "Center care", "Relative care")),
      childcare_cost = 500,
      childcare_hours = 30
    )

  # Add variable labels
  var_label(childcare_data$childcare_type) <- "Primary childcare type"
  var_label(childcare_data$childcare_cost) <- "Monthly childcare cost"
  var_label(childcare_data$childcare_hours) <- "Weekly childcare hours"

  return(childcare_data)
}

# Helper functions

#' Get NE25 transformation categories
#'
#' @return Vector of available transformation categories
get_ne25_transformation_categories <- function() {
  c("include", "race", "education", "income", "age", "sex",
    "caregiver_relationship", "survey_completion", "mental_health", "childcare")
}

#' Calculate federal poverty level percentage
#'
#' @param income Household income
#' @param family_size Family size
#' @return FPL percentage
calculate_fpl_percentage <- function(income, family_size) {
  # 2023 Federal Poverty Guidelines (would be updated annually)
  fpl_thresholds <- c(
    1, 13590,
    2, 18310,
    3, 23030,
    4, 27750,
    5, 32470,
    6, 37190,
    7, 41910,
    8, 46630
  )

  fpl_matrix <- matrix(fpl_thresholds, ncol = 2, byrow = TRUE)

  # Calculate FPL percentage
  fpl_threshold <- approx(fpl_matrix[,1], fpl_matrix[,2], family_size, rule = 2)$y
  fpl_percentage <- (income / fpl_threshold) * 100

  return(fpl_percentage)
}