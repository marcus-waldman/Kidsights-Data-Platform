#' Data Transformation Utilities
#'
#' Functions for transforming raw REDCap data into monitoring variables.

#' Transform raw REDCap data into monitoring variables
#'
#' Performs inline transformations on raw data to create derived variables
#' needed for monitoring (age, sex, race/ethnicity, education, marital status).
#'
#' [MN26 TODO] Update variable names and value codes to match MN26 data dictionary
#'
#' @param raw_data Raw REDCap data
#' @param dictionary REDCap data dictionary (optional, for value labels)
#' @return Data frame with transformed variables
transform_raw_data <- function(raw_data, dictionary = NULL) {

  message("Transforming raw data...")

  transformed <- raw_data %>%
    dplyr::mutate(
      # --- Child age ---
      # [MN26 TODO] Verify age_in_days field name
      years_old = age_in_days / 365.25,

      # --- Child sex ---
      # [MN26 TODO] Verify cqr009 field name and value codes
      # NE25: cqr009 = 0 (Female), 1 (Male)
      sex = dplyr::case_when(
        cqr009 == 0 ~ "Female",
        cqr009 == 1 ~ "Male",
        TRUE ~ NA_character_
      ),

      # --- Parent sex ---
      # [MN26 TODO] Verify cqr002 field name and value codes
      # NE25: cqr002 = 0 (Female), 1 (Male)
      female_a1 = (cqr002 == 0),

      # --- Parent age ---
      # [MN26 TODO] Verify cqr003 field name
      a1_years_old = as.numeric(cqr003),

      # --- Parent education ---
      # [MN26 TODO] Verify cqr004 field name and value labels
      educ_a1 = dplyr::case_when(
        cqr004 == 1 ~ "Less than 9th grade",
        cqr004 == 2 ~ "9th-12th grade, no diploma",
        cqr004 == 3 ~ "High school graduate or GED",
        cqr004 == 4 ~ "Some college, no degree",
        cqr004 == 5 ~ "Associate degree",
        cqr004 == 6 ~ "Vocational/Technical/Trade",
        cqr004 == 7 ~ "Bachelor's degree",
        cqr004 == 8 ~ "Graduate or professional degree",
        TRUE ~ NA_character_
      ),

      # --- Marital status ---
      # [MN26 TODO] Verify cqfa001 field name and value labels
      marital_status_label = dplyr::case_when(
        cqfa001 == 1 ~ "Married",
        cqfa001 == 2 ~ "Not married, but living with a partner",
        cqfa001 == 3 ~ "Never Married",
        cqfa001 == 4 ~ "Divorced",
        cqfa001 == 5 ~ "Separated",
        cqfa001 == 6 ~ "Widowed",
        TRUE ~ NA_character_
      )
    )

  # --- Parent race/ethnicity ---
  # [MN26 TODO] Verify sq002_* and sq003 field names
  # Build race from checkbox columns (sq002___1 through sq002___15)
  race_cols <- grep("^sq002___", names(raw_data), value = TRUE)

  if (length(race_cols) > 0) {
    # Count how many race categories selected per person
    race_count <- rowSums(raw_data[, race_cols, drop = FALSE], na.rm = TRUE)

    # Determine primary race (simplified mapping)
    # [MN26 TODO] Update these mappings to match MN26 value labels
    transformed <- transformed %>%
      dplyr::mutate(
        a1_race_count = race_count,
        a1_hisp = ifelse(sq003 == 1, "Hispanic", "non-Hisp."),
        a1_race = dplyr::case_when(
          a1_race_count > 1 ~ "Two or More",
          sq002___1 == 1 ~ "White",
          sq002___2 == 1 ~ "Black or African American",
          TRUE ~ "Other"
        ),
        a1_raceG = ifelse(a1_hisp == "Hispanic", "Hispanic", paste0(a1_race, ", non-Hisp."))
      )
  } else {
    transformed <- transformed %>%
      dplyr::mutate(
        a1_hisp = NA_character_,
        a1_race = NA_character_,
        a1_raceG = NA_character_
      )
    warning("No race checkbox columns (sq002___*) found in data")
  }

  message("[OK] Transformed ", nrow(transformed), " records")
  return(transformed)
}
