# Validation Utilities: Post-Harmonization Distribution Checks
# Purpose: Validate that harmonized variables have plausible distributions
# These functions check statistical properties after transformation

library(dplyr)

# ============================================================================
# Post-Harmonization Distribution Validation
# ============================================================================

validate_harmonized_data <- function(data, source_name = "Unknown") {
  cat("\n========================================\n")
  cat("Post-Harmonization Distribution Check:", source_name, "\n")
  cat("========================================\n\n")

  issues <- list()

  # 1. Race/ethnicity proportions
  cat("[1] Race/ethnicity distribution:\n")

  if ("race_harmonized" %in% names(data)) {
    race_table <- table(data$race_harmonized, useNA = "ifany")
    race_props <- prop.table(race_table)

    race_df <- data.frame(
      category = names(race_props),
      count = as.numeric(race_table),
      percent = round(as.numeric(race_props) * 100, 1)
    )

    print(race_df)

    # Flag if "Other" >30% or NA >10%
    other_pct <- race_props["Other"] * 100
    na_pct <- race_props[is.na(names(race_props))] * 100

    if (!is.na(other_pct) && other_pct > 30) {
      issues$race_other <- sprintf("Other category: %.1f%% (>30%% threshold)", other_pct)
      cat("    WARNING: High proportion of 'Other' category\n")
    }

    if (!is.na(na_pct) && na_pct > 10) {
      issues$race_na <- sprintf("Missing race: %.1f%% (>10%% threshold)", na_pct)
      cat("    WARNING: High proportion of missing race\n")
    }

    if (is.na(other_pct) && is.na(na_pct)) {
      cat("    ✓ Acceptable race/ethnicity distribution\n")
    }
  } else {
    cat("    WARNING: race_harmonized variable not found\n")
  }

  # 2. Education years: median should be 12-16
  cat("\n[2] Education years (years of schooling):\n")

  if ("educ_years" %in% names(data)) {
    educ_median <- median(data$educ_years, na.rm = TRUE)
    educ_sd <- sd(data$educ_years, na.rm = TRUE)
    educ_mean <- mean(data$educ_years, na.rm = TRUE)
    educ_na_pct <- mean(is.na(data$educ_years)) * 100

    cat("    Mean:", round(educ_mean, 2), "years\n")
    cat("    Median:", round(educ_median, 2), "years\n")
    cat("    SD:", round(educ_sd, 2), "\n")
    cat("    Missing:", round(educ_na_pct, 1), "%\n")

    if (educ_median < 10 || educ_median > 18) {
      issues$educ_median <- sprintf("Median education: %.1f years (expected 10-18)", educ_median)
      cat("    WARNING: Median outside expected range 10-18 years\n")
    }

    if (educ_sd < 1 || educ_sd > 5) {
      issues$educ_sd <- sprintf("Education SD: %.2f (expected 1-5)", educ_sd)
      cat("    WARNING: SD outside expected range 1-5\n")
    }

    if (educ_na_pct > 20) {
      issues$educ_na <- sprintf("Missing education: %.1f%% (>20%% threshold)", educ_na_pct)
      cat("    WARNING: High proportion of missing education\n")
    }

    if (length(intersect(names(issues), c("educ_median", "educ_sd", "educ_na"))) == 0) {
      cat("    ✓ Acceptable education distribution\n")
    }
  } else {
    cat("    WARNING: educ_years variable not found\n")
  }

  # 3. Marital status: married proportion should be 30-70%
  cat("\n[3] Marital status (married indicator):\n")

  if ("married" %in% names(data)) {
    married_prop <- mean(data$married == 1, na.rm = TRUE) * 100
    married_na_pct <- mean(is.na(data$married)) * 100

    cat("    Married:", round(married_prop, 1), "%\n")
    cat("    Missing:", round(married_na_pct, 1), "%\n")

    if (married_prop < 30 || married_prop > 70) {
      issues$married_prop <- sprintf("Married proportion: %.1f%% (expected 30-70%%)", married_prop)
      cat("    WARNING: Married proportion outside expected range 30-70%\n")
    } else {
      cat("    ✓ Acceptable married proportion\n")
    }
  } else {
    cat("    WARNING: married variable not found\n")
  }

  # 4. Poverty ratio: median should be 150-300
  cat("\n[4] Poverty ratio (percent of federal poverty line):\n")

  if ("poverty_ratio" %in% names(data)) {
    poverty_median <- median(data$poverty_ratio, na.rm = TRUE)
    poverty_q1 <- quantile(data$poverty_ratio, 0.25, na.rm = TRUE)
    poverty_q3 <- quantile(data$poverty_ratio, 0.75, na.rm = TRUE)
    poverty_min <- min(data$poverty_ratio, na.rm = TRUE)
    poverty_max <- max(data$poverty_ratio, na.rm = TRUE)
    poverty_na_pct <- mean(is.na(data$poverty_ratio)) * 100

    cat("    Q1 (25th pct):", round(poverty_q1, 0), "%\n")
    cat("    Median (50th pct):", round(poverty_median, 0), "%\n")
    cat("    Q3 (75th pct):", round(poverty_q3, 0), "%\n")
    cat("    Range:", round(poverty_min, 0), "to", round(poverty_max, 0), "%\n")
    cat("    Missing:", round(poverty_na_pct, 1), "%\n")

    if (poverty_median < 100 || poverty_median > 400) {
      issues$poverty_median <- sprintf("Median FPL: %d%% (expected 100-400%%)", round(poverty_median))
      cat("    WARNING: Median outside expected range 100-400%\n")
    } else {
      cat("    ✓ Acceptable poverty ratio distribution\n")
    }
  } else {
    cat("    WARNING: poverty_ratio variable not found\n")
  }

  # 5. Sex: male proportion should be 48-52%
  cat("\n[5] Sex (male indicator):\n")

  if ("male" %in% names(data)) {
    male_prop <- mean(data$male == 1, na.rm = TRUE) * 100
    male_na_pct <- mean(is.na(data$male)) * 100

    cat("    Male:", round(male_prop, 1), "%\n")
    cat("    Missing:", round(male_na_pct, 1), "%\n")

    if (male_prop < 48 || male_prop > 52) {
      issues$male_prop <- sprintf("Male proportion: %.1f%% (expected 48-52%%)", male_prop)
      cat("    WARNING: Male proportion outside expected range 48-52%\n")
    } else {
      cat("    ✓ Acceptable sex distribution\n")
    }
  } else {
    cat("    WARNING: male variable not found\n")
  }

  # 6. Age: should be roughly uniform 0-5
  cat("\n[6] Age distribution (0-5 years):\n")

  if ("age" %in% names(data)) {
    age_table <- table(data$age, useNA = "ifany")
    age_props <- prop.table(age_table) * 100

    age_df <- data.frame(
      age = names(age_props),
      percent = round(as.numeric(age_props), 1)
    )

    print(age_df)

    # For uniform distribution, each year should be roughly 16.7% (1/6)
    # Flag if any year is <5% or >30%
    age_pcts <- as.numeric(age_props)
    if (any(age_pcts < 5, na.rm = TRUE) || any(age_pcts > 30, na.rm = TRUE)) {
      issues$age_dist <- "Age distribution skewed: some ages <5% or >30%"
      cat("    WARNING: Age distribution is skewed\n")
    } else {
      cat("    ✓ Roughly uniform age distribution\n")
    }
  } else {
    cat("    WARNING: age variable not found\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All post-harmonization distribution checks PASSED\n\n")
  } else {
    cat("✗ WARNING: Post-harmonization distribution checks FAILED\n")
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
