# Validation Utilities: Pre-Harmonization Input Validation
# Purpose: Catch invalid input values before harmonization begins
# These functions validate that raw demographic codes fall within expected ranges

library(dplyr)

# ============================================================================
# ACS Input Validation
# ============================================================================

validate_acs_inputs <- function(data) {
  cat("\n========================================\n")
  cat("Pre-Harmonization Input Validation: ACS\n")
  cat("========================================\n\n")

  issues <- list()

  # 1. RACE validation (1-9)
  cat("[1] RACE variable (expected 1-9):\n")
  invalid_race <- !data$RACE %in% 1:9 & !is.na(data$RACE)
  if (sum(invalid_race) > 0) {
    issues$race <- sprintf("%d records with RACE not in 1-9", sum(invalid_race))
    cat("    ERROR:", issues$race, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 2. HISPAN validation (0-4, 9)
  cat("[2] HISPAN variable (expected 0-4, 9):\n")
  invalid_hispan <- !data$HISPAN %in% c(0:4, 9) & !is.na(data$HISPAN)
  if (sum(invalid_hispan) > 0) {
    issues$hispan <- sprintf("%d records with HISPAN not in {0-4, 9}", sum(invalid_hispan))
    cat("    ERROR:", issues$hispan, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 3. EDUC_MOM validation (0-13)
  cat("[3] EDUC_MOM variable (expected 0-13):\n")
  invalid_educ <- !data$EDUC_MOM %in% 0:13 & !is.na(data$EDUC_MOM)
  if (sum(invalid_educ) > 0) {
    issues$educ <- sprintf("%d records with EDUC_MOM not in 0-13", sum(invalid_educ))
    cat("    ERROR:", issues$educ, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 4. MARST_HEAD validation (1-6, 9)
  cat("[4] MARST_HEAD variable (expected 1-6, 9):\n")
  invalid_marst <- !data$MARST_HEAD %in% c(1:6, 9) & !is.na(data$MARST_HEAD)
  if (sum(invalid_marst) > 0) {
    issues$marst <- sprintf("%d records with MARST_HEAD not in {1-6, 9}", sum(invalid_marst))
    cat("    ERROR:", issues$marst, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 5. POVERTY validation (1-501)
  cat("[5] POVERTY variable (expected 1-501):\n")
  invalid_poverty <- (data$POVERTY < 1 | data$POVERTY > 501) & !is.na(data$POVERTY)
  if (sum(invalid_poverty) > 0) {
    issues$poverty <- sprintf("%d records with POVERTY < 1 or > 501", sum(invalid_poverty))
    cat("    ERROR:", issues$poverty, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 6. SEX validation (1-2)
  cat("[6] SEX variable (expected 1-2):\n")
  invalid_sex <- !data$SEX %in% 1:2 & !is.na(data$SEX)
  if (sum(invalid_sex) > 0) {
    issues$sex <- sprintf("%d records with SEX not in {1, 2}", sum(invalid_sex))
    cat("    ERROR:", issues$sex, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 7. AGE validation (0-5)
  cat("[7] AGE variable (expected 0-5):\n")
  invalid_age <- (data$AGE < 0 | data$AGE > 5) & !is.na(data$AGE)
  if (sum(invalid_age) > 0) {
    issues$age <- sprintf("%d records with AGE < 0 or > 5", sum(invalid_age))
    cat("    ERROR:", issues$age, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All ACS input validation checks PASSED\n\n")
  } else {
    cat("✗ WARNING: ACS input validation FAILED\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    n_records = nrow(data),
    issues = issues
  )
}

# ============================================================================
# NHIS Input Validation
# ============================================================================

validate_nhis_inputs <- function(data) {
  cat("\n========================================\n")
  cat("Pre-Harmonization Input Validation: NHIS\n")
  cat("========================================\n\n")

  issues <- list()

  # Check if required columns exist (handle both _child suffix and plain names)
  sex_col <- if ("SEX_child" %in% names(data)) "SEX_child" else if ("SEX" %in% names(data)) "SEX" else NA
  age_col <- if ("AGE_child" %in% names(data)) "AGE_child" else if ("AGE" %in% names(data)) "AGE" else NA

  required_cols <- c("RACENEW", "HISPETH", "EDUCPARENT", "POVERTY")
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0 || is.na(sex_col) || is.na(age_col)) {
    cat("ERROR: Missing required columns:\n")
    for (col in c(missing_cols, if(is.na(sex_col)) "SEX or SEX_child", if(is.na(age_col)) "AGE or AGE_child")) {
      cat("  - ", col, "\n")
    }
    cat("\nAvailable columns (first 30):\n")
    print(head(names(data), 30))
    stop("Required NHIS columns not found")
  }

  # 1. RACENEW validation (100, 200, 300, 400, 500, 600)
  cat("[1] RACENEW variable (expected 100, 200, 300, 400, 500, 600):\n")
  valid_race <- c(100, 200, 300, 400, 500, 600)
  invalid_race <- !data$RACENEW %in% valid_race & !is.na(data$RACENEW)
  if (sum(invalid_race) > 0) {
    issues$race <- sprintf("%d records with RACENEW not in {100, 200, 300, 400, 500, 600}", sum(invalid_race))
    cat("    ERROR:", issues$race, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 2. HISPETH validation (10-93)
  cat("[2] HISPETH variable (expected 10-93):\n")
  invalid_hispeth <- (data$HISPETH < 10 | data$HISPETH > 93) & !is.na(data$HISPETH)
  if (sum(invalid_hispeth) > 0) {
    issues$hispeth <- sprintf("%d records with HISPETH < 10 or > 93", sum(invalid_hispeth))
    cat("    ERROR:", issues$hispeth, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 3. EDUCPARENT validation (1-9)
  cat("[3] EDUCPARENT variable (expected 1-9):\n")
  invalid_educ <- !data$EDUCPARENT %in% 1:9 & !is.na(data$EDUCPARENT)
  if (sum(invalid_educ) > 0) {
    issues$educ <- sprintf("%d records with EDUCPARENT not in 1-9", sum(invalid_educ))
    cat("    ERROR:", issues$educ, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 4. POVERTY validation (0-501)
  cat("[4] POVERTY variable (expected 0-501):\n")
  invalid_poverty <- (data$POVERTY < 0 | data$POVERTY > 501) & !is.na(data$POVERTY)
  if (sum(invalid_poverty) > 0) {
    issues$poverty <- sprintf("%d records with POVERTY < 0 or > 501", sum(invalid_poverty))
    cat("    ERROR:", issues$poverty, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 5. SEX validation (1-2)
  cat(sprintf("[5] %s variable (expected 1-2):\n", sex_col))
  invalid_sex <- !data[[sex_col]] %in% 1:2 & !is.na(data[[sex_col]])
  if (sum(invalid_sex) > 0) {
    issues$sex <- sprintf("%d records with %s not in {1, 2}", sum(invalid_sex), sex_col)
    cat("    ERROR:", issues$sex, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 6. AGE validation (0-5)
  cat(sprintf("[6] %s variable (expected 0-5):\n", age_col))
  invalid_age <- (data[[age_col]] < 0 | data[[age_col]] > 5) & !is.na(data[[age_col]])
  if (sum(invalid_age) > 0) {
    issues$age <- sprintf("%d records with %s < 0 or > 5", sum(invalid_age), age_col)
    cat("    ERROR:", issues$age, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All NHIS input validation checks PASSED\n\n")
  } else {
    cat("✗ WARNING: NHIS input validation FAILED\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    n_records = nrow(data),
    issues = issues
  )
}

# ============================================================================
# NSCH Input Validation
# ============================================================================

validate_nsch_inputs <- function(data) {
  cat("\n========================================\n")
  cat("Pre-Harmonization Input Validation: NSCH\n")
  cat("========================================\n\n")

  issues <- list()

  # Check for race4 variable (may have year suffix)
  race4_vars <- grep("^race4", names(data), value = TRUE, ignore.case = TRUE)
  if (length(race4_vars) == 0) {
    cat("ERROR: No race4 variable found\n")
    cat("Available variables containing 'race':\n")
    race_vars <- grep("race", names(data), value = TRUE, ignore.case = TRUE)
    print(race_vars)
    stop("race4 variable not found")
  }

  # Use first race4 variable found
  race4_col <- race4_vars[1]
  cat("Using race4 variable:", race4_col, "\n\n")

  # 1. race4 validation (1-4)
  cat("[1] race4 variable (expected 1-4):\n")
  invalid_race <- !data[[race4_col]] %in% 1:4 & !is.na(data[[race4_col]])
  if (sum(invalid_race) > 0) {
    issues$race <- sprintf("%d records with race4 not in 1-4", sum(invalid_race))
    cat("    ERROR:", issues$race, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 2. FPL_I1 validation (50-400 continuous)
  cat("[2] FPL_I1 variable (expected 50-400 continuous):\n")
  if ("FPL_I1" %in% names(data)) {
    invalid_fpl <- (data$FPL_I1 < 50 | data$FPL_I1 > 400) & !is.na(data$FPL_I1)
    if (sum(invalid_fpl) > 0) {
      issues$fpl <- sprintf("%d records with FPL_I1 < 50 or > 400", sum(invalid_fpl))
      cat("    ERROR:", issues$fpl, "\n")
    } else {
      cat("    ✓ All values in valid range\n")
    }
  } else {
    cat("    WARNING: FPL_I1 not found; skipping validation\n")
  }

  # 3. SC_SEX validation (1-2)
  cat("[3] SC_SEX variable (expected 1-2):\n")
  invalid_sex <- !data$SC_SEX %in% 1:2 & !is.na(data$SC_SEX)
  if (sum(invalid_sex) > 0) {
    issues$sex <- sprintf("%d records with SC_SEX not in {1, 2}", sum(invalid_sex))
    cat("    ERROR:", issues$sex, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # 4. SC_AGE_YEARS validation (0-5)
  cat("[4] SC_AGE_YEARS variable (expected 0-5):\n")
  invalid_age <- (data$SC_AGE_YEARS < 0 | data$SC_AGE_YEARS > 5) & !is.na(data$SC_AGE_YEARS)
  if (sum(invalid_age) > 0) {
    issues$age <- sprintf("%d records with SC_AGE_YEARS < 0 or > 5", sum(invalid_age))
    cat("    ERROR:", issues$age, "\n")
  } else {
    cat("    ✓ All values in valid range\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All NSCH input validation checks PASSED\n\n")
  } else {
    cat("✗ WARNING: NSCH input validation FAILED\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    n_records = nrow(data),
    issues = issues
  )
}
