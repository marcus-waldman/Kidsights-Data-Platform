# Phase 4a, Task 3: Rake NHIS to Nebraska Demographics
# Uses iterative proportional fitting to reweight NHIS North Central to match
# ACS Nebraska marginal distributions for 8 demographic variables
# Output: Raked NHIS weights that match Nebraska population targets

library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.3: Rake NHIS to Nebraska Marginals\n")
cat("========================================\n\n")

# Source utilities
cat("[1] Loading utilities...\n")
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")
source("scripts/raking/ne25/utils/weighted_covariance.R")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
source("scripts/raking/ne25/utils/rake_to_targets.R")
cat("    ✓ Utilities loaded\n\n")

# 1. Load ACS Nebraska data to create targets
cat("[2] Loading ACS Nebraska data for targets...\n")

acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
acs_ne <- acs_nc %>% dplyr::filter(STATEFIP == 31)

cat("    Loaded:", nrow(acs_ne), "Nebraska observations from ACS\n\n")

# 2. Create harmonized variables for ACS Nebraska
cat("[3] Creating harmonized variables for ACS Nebraska...\n")

acs_ne$male <- as.integer(acs_ne$SEX == 1)
acs_ne$age <- acs_ne$AGE
acs_ne$race_harmonized <- harmonize_acs_race(acs_ne$RACE, acs_ne$HISPAN)
race_dummies <- create_race_dummies(acs_ne$race_harmonized)
acs_ne$white_nh <- race_dummies$white_nh
acs_ne$black <- race_dummies$black
acs_ne$hispanic <- race_dummies$hispanic
acs_ne$educ_years <- harmonize_acs_education(acs_ne$EDUC_MOM)
acs_ne$married <- as.integer(acs_ne$MARST_HEAD == 1)
acs_ne$poverty_ratio <- acs_ne$POVERTY

cat("    ✓ Harmonized variables created\n\n")

# 3. Create target marginals from ACS Nebraska (weighted by PERWT)
cat("[4] Creating target marginals from ACS Nebraska...\n")

target_vars <- c("male", "age", "white_nh", "black", "hispanic",
                 "educ_years", "married", "poverty_ratio")

target_marginals <- list()

for (var in target_vars) {
  target_marginals[[var]] <- weighted.mean(acs_ne[[var]], acs_ne$PERWT, na.rm = TRUE)
}

cat("    Target marginals from ACS Nebraska:\n")
for (var in target_vars) {
  cat("      ", var, ":", round(target_marginals[[var]], 4), "\n")
}
cat("\n")

# 4. Load NHIS North Central data
cat("[5] Loading NHIS North Central data...\n")

if (!file.exists("data/raking/ne25/nhis_parent_child_linked.rds")) {
  stop("NHIS parent-child data not found. Run 12_filter_nhis_parents.R first.")
}

nhis <- readRDS("data/raking/ne25/nhis_parent_child_linked.rds")
cat("    Loaded:", nrow(nhis), "parent-child pairs\n")
cat("    Years:", paste(sort(unique(nhis$YEAR)), collapse = ", "), "\n\n")

# 5. Pre-harmonization input validation
cat("[6] Running pre-harmonization input validation...\n")
nhis_validation <- validate_nhis_inputs(nhis)

if (!nhis_validation$valid) {
  cat("\nWARNING: NHIS input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# 6. Create harmonized variables for NHIS
cat("[7] Creating harmonized demographic variables for NHIS...\n")

# Sex: male indicator (1=Male in NHIS)
nhis$male <- as.integer(nhis$SEX_child == 1)

# Age: continuous (child age 0-5)
nhis$age <- nhis$AGE_child

# Race/ethnicity: Use parent's race if available
race_var <- ifelse("RACENEW_parent" %in% names(nhis), "RACENEW_parent", "RACENEW")
hisp_var <- ifelse("HISPETH_parent" %in% names(nhis), "HISPETH_parent",
                   ifelse("HISPETH" %in% names(nhis), "HISPETH",
                          ifelse("HISPAN_parent" %in% names(nhis), "HISPAN_parent", "HISPAN")))

nhis$race_harmonized <- harmonize_nhis_race(nhis[[race_var]], nhis[[hisp_var]])

# Create race dummies
race_dummies <- create_race_dummies(nhis$race_harmonized)
nhis$white_nh <- race_dummies$white_nh
nhis$black <- race_dummies$black
nhis$hispanic <- race_dummies$hispanic

# Education: years of schooling (use parent's education if available)
educ_var_candidates <- c("EDUCPARENT_parent", "EDUCPARENT", "EDUC_parent", "EDUC")
educ_var <- intersect(educ_var_candidates, names(nhis))[1]

if (is.na(educ_var)) {
  stop("Education variable not found")
}

nhis$educ_years <- harmonize_nhis_education(nhis[[educ_var]])

# Marital status: Use parent's marital status if available
marital_var_candidates <- c("PAR1MARST", "MARSTAT_parent", "MARITAL_parent")
marital_var <- intersect(marital_var_candidates, names(nhis))[1]

if (is.na(marital_var)) {
  cat("    WARNING: Cannot find marital status variable\n")
  nhis$married <- NA_integer_
} else {
  nhis$married <- harmonize_nhis_marital(nhis[[marital_var]])
}

# FPL: continuous poverty ratio
poverty_var_candidates <- c("POVERTY_parent", "POVERTY", "RATCAT_parent", "RATCAT")
poverty_var <- intersect(poverty_var_candidates, names(nhis))[1]

if (is.na(poverty_var)) {
  stop("Poverty variable not found")
}

nhis$poverty_ratio <- nhis[[poverty_var]]

# Defensive filter: remove invalid poverty codes
invalid_poverty <- nhis$poverty_ratio < 0 | nhis$poverty_ratio > 501 | is.na(nhis$poverty_ratio)
if (sum(invalid_poverty) > 0) {
  cat("    WARNING:", sum(invalid_poverty), "records with invalid poverty ratio\n")
  nhis$poverty_ratio[invalid_poverty] <- NA_real_
}

cat("    ✓ Created 8 harmonized variables\n\n")

# 7. Check for missing values
cat("[8] Checking for missing values in harmonized variables...\n")

harmonized_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

missing_counts <- sapply(harmonized_vars, function(v) sum(is.na(nhis[[v]])))
missing_pct <- round(missing_counts / nrow(nhis) * 100, 2)

missing_df <- data.frame(
  variable = harmonized_vars,
  n_missing = missing_counts,
  pct_missing = missing_pct
)

print(missing_df)

# Remove records with missing data in any harmonized variable
nhis_complete <- nhis %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio)
  )

cat("\n    Records with complete data:", nrow(nhis_complete), "/", nrow(nhis),
    "(", round(nrow(nhis_complete) / nrow(nhis) * 100, 1), "%)\\n\\n")

# 8. Get the actual weight variable name
cat("[9] Identifying survey weight variable...\n")

actual_weight_var <- names(nhis_complete)[names(nhis_complete) %in%
  c("SAMPWEIGHT_child", "SAMPWEIGHT", "PARTWEIGHT", "LONGWEIGHT")][1]

if (is.na(actual_weight_var)) {
  stop("Cannot identify weight variable in NHIS data")
}

cat("    Using weight variable:", actual_weight_var, "\n")

# Create base weight column for raking
nhis_complete$base_weight <- nhis_complete[[actual_weight_var]]

cat("\n")

# 9. Perform raking to Nebraska targets
cat("[10] Raking NHIS to Nebraska marginal targets...\n\n")

raking_result <- rake_to_targets(
  nhis_complete,
  target_marginals = target_marginals,
  weight_name = "base_weight",
  max_iterations = 100,
  tolerance = 1e-6
)

nhis_complete <- raking_result$data
nhis_complete$raked_weight <- raking_result$raking_weight

cat("[11] Raking summary:\n")
cat("    Converged:", raking_result$converged, "\n")
cat("    Iterations:", raking_result$n_iterations, "\n")
cat("    Effective N:", round(raking_result$effective_n, 1), "\n")
cat("    Efficiency:", round(raking_result$effective_n / nrow(nhis_complete) * 100, 1), "%\n")
cat("    Weight ratio:", round(raking_result$weight_ratio, 2), "\n\n")

# 10. Final verification: compare raked NHIS marginals to ACS Nebraska
cat("[12] Final verification of raked marginals:\n\n")

verification_table <- data.frame(
  Variable = target_vars,
  ACS_Nebraska = unlist(target_marginals),
  Raked_NHIS = NA_real_,
  Difference = NA_real_
)

for (i in seq_along(target_vars)) {
  var <- target_vars[i]
  raked_mean <- weighted.mean(nhis_complete[[var]], nhis_complete$raked_weight, na.rm = TRUE)
  verification_table$Raked_NHIS[i] <- raked_mean
  verification_table$Difference[i] <- abs(raked_mean - verification_table$ACS_Nebraska[i])
}

print(verification_table)

cat("\n")

# 11. Save raked NHIS data
cat("[13] Saving raked NHIS data...\n")

if (!dir.exists("data/raking/ne25")) {
  dir.create("data/raking/ne25", recursive = TRUE)
}

# Keep base weight, raked weight, and harmonized variables
nhis_output <- nhis_complete %>%
  dplyr::select(
    all_of(c(actual_weight_var, "base_weight", "raked_weight")),
    all_of(harmonized_vars)
  )

saveRDS(nhis_output, "data/raking/ne25/nhis_raked.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_raked.rds\n")
cat("    Dimensions:", nrow(nhis_output), "rows x", ncol(nhis_output), "columns\n\n")

# Save raking diagnostics
nhis_raking_diagnostics <- list(
  n_raw = nrow(nhis),
  n_complete = nrow(nhis_complete),
  raking_converged = raking_result$converged,
  raking_iterations = raking_result$n_iterations,
  effective_n = raking_result$effective_n,
  efficiency = raking_result$effective_n / nrow(nhis_complete),
  weight_ratio = raking_result$weight_ratio,
  final_marginals = verification_table,
  missing_summary = missing_df
)

saveRDS(nhis_raking_diagnostics, "data/raking/ne25/nhis_raking_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nhis_raking_diagnostics.rds\n\n")

cat("========================================\n")
cat("Task 4a.3 Complete: NHIS Raked to Nebraska\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nhis_complete), "\n")
cat("  - Effective N:", round(raking_result$effective_n, 1), "\n")
cat("  - Efficiency:", round(raking_result$effective_n / nrow(nhis_complete) * 100, 1), "%\n")
cat("  - Marginal verification: max difference =",
    round(max(verification_table$Difference), 6), "\n\n")

cat("Ready for Task 4a.4: Rake NSCH to Nebraska\n\n")
