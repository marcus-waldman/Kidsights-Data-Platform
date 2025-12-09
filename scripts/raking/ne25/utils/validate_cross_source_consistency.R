# Validation Utilities: Cross-Source Consistency Checks
# Purpose: Validate that harmonized variables are comparable across ACS, NHIS, NSCH
# These functions compare distributions across all 3 sources to ensure consistency

library(dplyr)

# ============================================================================
# Cross-Source Consistency Validation
# ============================================================================

validate_cross_source_consistency <- function(acs_data, nhis_data, nsch_data) {
  cat("\n========================================\n")
  cat("Cross-Source Consistency Validation\n")
  cat("========================================\n\n")

  issues <- list()

  # 1. Compare race/ethnicity distributions
  cat("[1] Race/ethnicity proportions:\n")

  if (all(c("race_harmonized") %in% c(names(acs_data), names(nhis_data), names(nsch_data)))) {
    acs_race <- prop.table(table(acs_data$race_harmonized))
    nhis_race <- prop.table(table(nhis_data$race_harmonized))
    nsch_race <- prop.table(table(nsch_data$race_harmonized))

    # Get all race categories present
    all_race_categories <- unique(c(names(acs_race), names(nhis_race), names(nsch_race)))

    # Create comparison table
    race_comparison <- data.frame(
      Category = all_race_categories,
      ACS = round(acs_race[all_race_categories] * 100, 1),
      NHIS = round(nhis_race[all_race_categories] * 100, 1),
      NSCH = round(nsch_race[all_race_categories] * 100, 1)
    )

    row.names(race_comparison) <- NULL
    print(race_comparison)

    # Check consistency: flag if any category differs by >15 percentage points across sources
    max_diff_white <- max(abs(diff(c(
      acs_race["White NH"],
      nhis_race["White NH"],
      nsch_race["White NH"]
    ))), na.rm = TRUE)

    max_diff_black <- max(abs(diff(c(
      acs_race["Black"],
      nhis_race["Black"],
      nsch_race["Black"]
    ))), na.rm = TRUE)

    max_diff_hispanic <- max(abs(diff(c(
      acs_race["Hispanic"],
      nhis_race["Hispanic"],
      nsch_race["Hispanic"]
    ))), na.rm = TRUE)

    if (max_diff_white > 0.15) {
      issues$race_white <- sprintf("White NH differs by >15pp across sources (max: %.1f%%)", max_diff_white * 100)
      cat("    WARNING: White NH category differs >15pp across sources\n")
    }

    if (max_diff_black > 0.15) {
      issues$race_black <- sprintf("Black differs by >15pp across sources (max: %.1f%%)", max_diff_black * 100)
      cat("    WARNING: Black category differs >15pp across sources\n")
    }

    if (max_diff_hispanic > 0.15) {
      issues$race_hispanic <- sprintf("Hispanic differs by >15pp across sources (max: %.1f%%)", max_diff_hispanic * 100)
      cat("    WARNING: Hispanic category differs >15pp across sources\n")
    }

    if (length(intersect(names(issues), c("race_white", "race_black", "race_hispanic"))) == 0) {
      cat("    ✓ Race/ethnicity distributions consistent across sources\n")
    }
  } else {
    cat("    WARNING: race_harmonized variable missing in one or more sources\n")
  }

  # 2. Compare education distributions
  cat("\n[2] Education years summary:\n")

  if (all(c("educ_years") %in% c(names(acs_data), names(nhis_data), names(nsch_data)))) {
    educ_comparison <- data.frame(
      Statistic = c("Median", "SD", "Mean", "Missing %"),
      ACS = c(
        round(median(acs_data$educ_years, na.rm = TRUE), 1),
        round(sd(acs_data$educ_years, na.rm = TRUE), 2),
        round(mean(acs_data$educ_years, na.rm = TRUE), 1),
        round(mean(is.na(acs_data$educ_years)) * 100, 1)
      ),
      NHIS = c(
        round(median(nhis_data$educ_years, na.rm = TRUE), 1),
        round(sd(nhis_data$educ_years, na.rm = TRUE), 2),
        round(mean(nhis_data$educ_years, na.rm = TRUE), 1),
        round(mean(is.na(nhis_data$educ_years)) * 100, 1)
      ),
      NSCH = c(
        round(median(nsch_data$educ_years, na.rm = TRUE), 1),
        round(sd(nsch_data$educ_years, na.rm = TRUE), 2),
        round(mean(nsch_data$educ_years, na.rm = TRUE), 1),
        round(mean(is.na(nsch_data$educ_years)) * 100, 1)
      )
    )

    print(educ_comparison)

    # Flag if median differs by >2 years across sources
    educ_medians <- c(
      median(acs_data$educ_years, na.rm = TRUE),
      median(nhis_data$educ_years, na.rm = TRUE),
      median(nsch_data$educ_years, na.rm = TRUE)
    )

    educ_median_range <- max(educ_medians, na.rm = TRUE) - min(educ_medians, na.rm = TRUE)

    if (educ_median_range > 2) {
      issues$educ_median <- sprintf("Education median differs by >2 years (range: %.1f-%.1f)",
        min(educ_medians, na.rm = TRUE),
        max(educ_medians, na.rm = TRUE)
      )
      cat("    WARNING: Education median differs >2 years across sources\n")
    } else {
      cat("    ✓ Education distributions consistent across sources\n")
    }
  } else {
    cat("    WARNING: educ_years variable missing in one or more sources\n")
  }

  # 3. Compare marital status proportions
  cat("\n[3] Married proportion:\n")

  if (all(c("married") %in% c(names(acs_data), names(nhis_data), names(nsch_data)))) {
    married_comparison <- data.frame(
      Source = c("ACS", "NHIS", "NSCH"),
      Married_Pct = c(
        round(mean(acs_data$married == 1, na.rm = TRUE) * 100, 1),
        round(mean(nhis_data$married == 1, na.rm = TRUE) * 100, 1),
        round(mean(nsch_data$married == 1, na.rm = TRUE) * 100, 1)
      )
    )

    print(married_comparison)

    # Flag if married proportion differs by >20pp across sources
    married_props <- c(
      mean(acs_data$married == 1, na.rm = TRUE),
      mean(nhis_data$married == 1, na.rm = TRUE),
      mean(nsch_data$married == 1, na.rm = TRUE)
    )

    married_range <- max(married_props, na.rm = TRUE) - min(married_props, na.rm = TRUE)

    if (married_range > 0.20) {
      issues$married_prop <- sprintf("Married proportion differs by >20pp (range: %.1f%%-%.1f%%)",
        min(married_props, na.rm = TRUE) * 100,
        max(married_props, na.rm = TRUE) * 100
      )
      cat("    WARNING: Married proportion differs >20pp across sources\n")
    } else {
      cat("    ✓ Marital status distributions consistent across sources\n")
    }
  } else {
    cat("    WARNING: married variable missing in one or more sources\n")
  }

  # 4. Compare poverty distributions
  cat("\n[4] Poverty ratio summary:\n")

  if (all(c("poverty_ratio") %in% c(names(acs_data), names(nhis_data), names(nsch_data)))) {
    poverty_comparison <- data.frame(
      Statistic = c("Q1", "Median", "Q3", "Mean"),
      ACS = c(
        round(quantile(acs_data$poverty_ratio, 0.25, na.rm = TRUE), 0),
        round(median(acs_data$poverty_ratio, na.rm = TRUE), 0),
        round(quantile(acs_data$poverty_ratio, 0.75, na.rm = TRUE), 0),
        round(mean(acs_data$poverty_ratio, na.rm = TRUE), 0)
      ),
      NHIS = c(
        round(quantile(nhis_data$poverty_ratio, 0.25, na.rm = TRUE), 0),
        round(median(nhis_data$poverty_ratio, na.rm = TRUE), 0),
        round(quantile(nhis_data$poverty_ratio, 0.75, na.rm = TRUE), 0),
        round(mean(nhis_data$poverty_ratio, na.rm = TRUE), 0)
      ),
      NSCH = c(
        round(quantile(nsch_data$poverty_ratio, 0.25, na.rm = TRUE), 0),
        round(median(nsch_data$poverty_ratio, na.rm = TRUE), 0),
        round(quantile(nsch_data$poverty_ratio, 0.75, na.rm = TRUE), 0),
        round(mean(nsch_data$poverty_ratio, na.rm = TRUE), 0)
      )
    )

    print(poverty_comparison)
    cat("    ✓ Poverty ratio distributions compared\n")
  } else {
    cat("    WARNING: poverty_ratio variable missing in one or more sources\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All cross-source consistency checks PASSED\n\n")
  } else {
    cat("✗ WARNING: Cross-source inconsistencies detected:\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    issues = issues,
    race_comparison = if (exists("race_comparison")) race_comparison else NULL,
    educ_comparison = if (exists("educ_comparison")) educ_comparison else NULL,
    married_comparison = if (exists("married_comparison")) married_comparison else NULL,
    poverty_comparison = if (exists("poverty_comparison")) poverty_comparison else NULL
  )
}
