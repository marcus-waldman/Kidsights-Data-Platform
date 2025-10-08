# Phase 5, Task 5.3: Add Estimand Descriptions
# Populate standardized descriptions for all 31 estimands

library(dplyr)

cat("\n========================================\n")
cat("Phase 5: Add Estimand Descriptions\n")
cat("========================================\n\n")

# 1. Load consolidated estimates
cat("[1] Loading consolidated estimates...\n")

all_estimates <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")

cat("    Loaded:", nrow(all_estimates), "rows\n")
cat("    Estimands:", length(unique(all_estimates$estimand)), "\n\n")

# 2. Create estimand description mapping
cat("[2] Creating description mapping...\n")

# ACS Estimands (25 total)
acs_descriptions <- c(
  # Income (5)
  "0-99%" = "Household income 0-99% of federal poverty level",
  "100-199%" = "Household income 100-199% of federal poverty level",
  "200-299%" = "Household income 200-299% of federal poverty level",
  "300-399%" = "Household income 300-399% of federal poverty level",
  "400%+" = "Household income 400%+ of federal poverty level",

  # Race/Ethnicity (3)
  "Black" = "Child race: Black or African American",
  "Hispanic" = "Child ethnicity: Hispanic or Latino (any race)",
  "White non-Hispanic" = "Child race: White non-Hispanic",

  # Demographics (2)
  "Male" = "Child sex: Male",
  "Mother Bachelor's+" = "Mother's education: Bachelor's degree or higher",
  "Mother Married" = "Mother's marital status: Married",

  # PUMA Geography (14)
  "PUMA_100" = "PUMA 100: Keith, Perkins, Chase, Dundy, Hayes Counties",
  "PUMA_200" = "PUMA 200: Scotts Bluff, Banner, Kimball, Morrill, Cheyenne, Deuel, Garden, Sioux, Box Butte, Sheridan, Dawes Counties",
  "PUMA_300" = "PUMA 300: Lincoln, Logan, McPherson, Thomas, Hooker, Grant, Arthur, Blaine Counties",
  "PUMA_400" = "PUMA 400: Dawson, Custer, Frontier, Gosper, Valley, Greeley Counties",
  "PUMA_500" = "PUMA 500: Buffalo, Sherman, Howard, Hall, Merrick Counties",
  "PUMA_600" = "PUMA 600: Adams, Webster, Franklin, Harlan, Furnas, Red Willow, Hitchcock, Phelps, Kearney Counties",
  "PUMA_701" = "PUMA 701: Douglas County (Omaha - North)",
  "PUMA_702" = "PUMA 702: Douglas County (Omaha - South)",
  "PUMA_801" = "PUMA 801: Sarpy County (West)",
  "PUMA_802" = "PUMA 802: Sarpy County (East)",
  "PUMA_901" = "PUMA 901: Lancaster County (Lincoln - Northwest)",
  "PUMA_902" = "PUMA 902: Lancaster County (Lincoln - Northeast)",
  "PUMA_903" = "PUMA 903: Lancaster County (Lincoln - Southwest)",
  "PUMA_904" = "PUMA 904: Lancaster County (Lincoln - Southeast)"
)

# NHIS Estimands (2)
nhis_descriptions <- c(
  "PHQ-2 Positive" = "Parent PHQ-2 positive screen for depression (score >= 3)",
  "GAD-2 Positive" = "Parent GAD-2 positive screen for anxiety (score >= 3)"
)

# NSCH Estimands (4)
nsch_descriptions <- c(
  "Child ACE Exposure (1+ ACEs)" = "Child exposed to 1 or more adverse childhood experiences (ACEs)",
  "Emotional/Behavioral Problems" = "Parent-reported moderate/severe emotional, behavioral, or developmental problems (ages 3-5 only)",
  "Excellent Health Rating" = "Parent rates child's overall health as excellent",
  "Child Care 10+ Hours/Week" = "Child receives 10 or more hours per week of child care (ages 0-4 only)"
)

# Combine all descriptions
all_descriptions <- c(acs_descriptions, nhis_descriptions, nsch_descriptions)

cat("    Created descriptions for", length(all_descriptions), "estimands:\n")
cat("      - ACS:", length(acs_descriptions), "\n")
cat("      - NHIS:", length(nhis_descriptions), "\n")
cat("      - NSCH:", length(nsch_descriptions), "\n\n")

# 3. Add descriptions to data frame
cat("[3] Adding descriptions to estimates...\n")

all_estimates <- all_estimates %>%
  dplyr::mutate(
    description = all_descriptions[estimand]
  )

# Verify all descriptions were added
missing_desc <- sum(is.na(all_estimates$description))
if (missing_desc > 0) {
  cat("    [WARN] ", missing_desc, " estimates missing descriptions\n")
  cat("    Missing estimands:\n")
  print(unique(all_estimates$estimand[is.na(all_estimates$description)]))
} else {
  cat("    [OK] All estimates have descriptions\n")
}

cat("\n")

# 4. Reorder columns to place description after estimand
cat("[4] Reordering columns...\n")

all_estimates <- all_estimates %>%
  dplyr::select(
    target_id,
    survey,
    age_years,
    estimand,
    description,
    data_source,
    estimator,
    estimate,
    se,
    lower_ci,
    upper_ci,
    sample_size,
    estimation_date,
    notes
  )

cat("    Final column order:\n")
cat("      ", paste(names(all_estimates), collapse = ", "), "\n\n")

# 5. Sample output
cat("[5] Sample output (first 5 ACS, first NHIS, first 2 NSCH):\n\n")

sample_output <- all_estimates %>%
  dplyr::filter(
    (data_source == "ACS" & target_id <= 5) |
    (data_source == "NHIS" & target_id == 151) |
    (data_source == "NSCH" & target_id %in% c(157, 169))
  ) %>%
  dplyr::select(target_id, age_years, estimand, description, data_source, estimate)

print(sample_output)

cat("\n")

# 6. Save updated estimates
cat("[6] Saving updated estimates...\n")

saveRDS(all_estimates, "data/raking/ne25/raking_targets_consolidated.rds")

cat("    Saved to: data/raking/ne25/raking_targets_consolidated.rds\n")
cat("    Dimensions:", nrow(all_estimates), "rows x", ncol(all_estimates), "columns\n\n")

cat("========================================\n")
cat("Task 5.3 Complete\n")
cat("========================================\n\n")

# Return for inspection
all_estimates
