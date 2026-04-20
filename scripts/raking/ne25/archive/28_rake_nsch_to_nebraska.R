# Phase 4a, Task 4: Rake NSCH to Nebraska Demographics
# Uses iterative proportional fitting to reweight NSCH North Central to match
# ACS Nebraska marginal distributions for 8 demographic variables
# Output: Raked NSCH weights that match Nebraska population targets

library(DBI)
library(duckdb)
library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.4: Rake NSCH to Nebraska Marginals\n")
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

# 1. Load ACS Nebraska targets (already created in script 27)
cat("[2] Loading ACS Nebraska target marginals...\n")

acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
acs_ne <- acs_nc %>% dplyr::filter(STATEFIP == 31)

# Create harmonized variables for ACS Nebraska
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

cat("    Loaded:", nrow(acs_ne), "Nebraska observations\n")

# Create target marginals
target_vars <- c("male", "age", "white_nh", "black", "hispanic",
                 "educ_years", "married", "poverty_ratio")

target_marginals <- list()

for (var in target_vars) {
  target_marginals[[var]] <- weighted.mean(acs_ne[[var]], acs_ne$PERWT, na.rm = TRUE)
}

cat("    Target marginals loaded\n\n")

# 2. Load NSCH North Central data
cat("[3] Loading NSCH North Central data (2021-2022 pooled)...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# North Central state FIPS codes
north_central_fips <- c(17, 18, 19, 20, 26, 27, 29, 31, 38, 39, 46, 55)

# Check which NSCH tables are available
tables <- DBI::dbListTables(con)
nsch_tables <- grep("^nsch_", tables, value = TRUE)
cat("    Available NSCH tables:", paste(nsch_tables, collapse = ", "), "\n")

# Load 2021 and 2022 data (pooled for larger sample)
nsch_years <- c(2021, 2022)
nsch_nc_list <- list()

for (year in nsch_years) {
  table_name <- paste0("nsch_", year)

  if (!(table_name %in% tables)) {
    cat("    WARNING: Table", table_name, "not found, skipping\n")
    next
  }

  query <- sprintf("
    SELECT *
    FROM %s
    WHERE FIPSST IN (%s)
      AND SC_AGE_YEARS <= 5
      AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  ", table_name, paste(north_central_fips, collapse = ", "))

  nsch_nc_list[[as.character(year)]] <- DBI::dbGetQuery(con, query)
  cat("    Loaded", year, ":", nrow(nsch_nc_list[[as.character(year)]]), "records\n")
}

DBI::dbDisconnect(con, shutdown = TRUE)

# Combine years
nsch_nc <- dplyr::bind_rows(nsch_nc_list, .id = "year_source")
nsch_nc$year_source <- as.integer(nsch_nc$year_source)

cat("\n    Total North Central records:", nrow(nsch_nc), "\n")
cat("    Nebraska records:", sum(nsch_nc$FIPSST == 31), "\n")
cat("    Years:", paste(sort(unique(nsch_nc$year_source)), collapse = ", "), "\n\n")

# 3. Pre-harmonization input validation
cat("[4] Running pre-harmonization input validation...\n")
nsch_validation <- validate_nsch_inputs(nsch_nc)

if (!nsch_validation$valid) {
  cat("\nWARNING: NSCH input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# 4. Create harmonized variables for NSCH
cat("[5] Creating harmonized demographic variables for NSCH...\n")

# Sex: male indicator (1=Male in NSCH)
nsch_nc$male <- as.integer(nsch_nc$SC_SEX == 1)

# Age: continuous (child age 0-5)
nsch_nc$age <- nsch_nc$SC_AGE_YEARS

# Race/ethnicity: NSCH race4 is already harmonized by IPUMS
# Detect race4 variable (may have year suffix)
race4_vars <- grep("^race4", names(nsch_nc), value = TRUE, ignore.case = TRUE)

if (length(race4_vars) == 0) {
  stop("race4 variable not found in NSCH data")
}

# Use first race4 variable found, or coalesce if multiple
if (length(race4_vars) > 1) {
  # Coalesce race4_21 and race4_22 if both present
  if ("race4_21" %in% names(nsch_nc) && "race4_22" %in% names(nsch_nc)) {
    nsch_nc$race4 <- dplyr::coalesce(nsch_nc$race4_21, nsch_nc$race4_22)
  } else if ("race4_2021" %in% names(nsch_nc) && "race4_2022" %in% names(nsch_nc)) {
    nsch_nc$race4 <- dplyr::coalesce(nsch_nc$race4_2021, nsch_nc$race4_2022)
  } else {
    nsch_nc$race4 <- nsch_nc[[race4_vars[1]]]
  }
} else {
  nsch_nc$race4 <- nsch_nc[[race4_vars[1]]]
}

# Harmonize NSCH race4 to 4-category scheme
nsch_nc$race_harmonized <- harmonize_nsch_race(nsch_nc$race4)

# Create race dummies
race_dummies <- create_race_dummies(nsch_nc$race_harmonized)
nsch_nc$white_nh <- race_dummies$white_nh
nsch_nc$black <- race_dummies$black
nsch_nc$hispanic <- race_dummies$hispanic

# Education: NSCH uses different coding - need to map
# Check available education variables
educ_vars <- grep("educ|school|grade|care", names(nsch_nc), value = TRUE, ignore.case = TRUE)

if (length(educ_vars) > 0) {
  cat("    Available education variables:", paste(educ_vars[1:min(3, length(educ_vars))], collapse = ", "), "\n")
}

# For NSCH parent education, look for caregiver education variables
if ("S5_K6_MOM" %in% names(nsch_nc)) {
  nsch_nc$educ_years <- harmonize_nsch_education(nsch_nc$S5_K6_MOM)
} else if ("mom_educ" %in% names(nsch_nc)) {
  nsch_nc$educ_years <- harmonize_nsch_education(nsch_nc$mom_educ)
} else {
  cat("    WARNING: No parent education variable found\n")
  cat("    Setting educ_years to NA (will be excluded from raking)\n")
  nsch_nc$educ_years <- NA_real_
}

# Marital status: Look for caregiver marital status
if ("A1_MARITAL" %in% names(nsch_nc)) {
  nsch_nc$married <- harmonize_nsch_marital(nsch_nc$A1_MARITAL)
} else if ("marital" %in% names(nsch_nc)) {
  nsch_nc$married <- harmonize_nsch_marital(nsch_nc$marital)
} else {
  cat("    WARNING: No marital status variable found\n")
  cat("    Setting married to NA (will be excluded from raking)\n")
  nsch_nc$married <- NA_integer_
}

# FPL: NSCH has FPL_I1-I6 as continuous (50-400)
if ("FPL_I1" %in% names(nsch_nc)) {
  nsch_nc$poverty_ratio <- nsch_nc$FPL_I1
} else if ("fpl" %in% names(nsch_nc)) {
  nsch_nc$poverty_ratio <- nsch_nc$fpl
} else {
  cat("    WARNING: No FPL variable found\n")
  cat("    Setting poverty_ratio to NA (will be excluded from raking)\n")
  nsch_nc$poverty_ratio <- NA_real_
}

# Defensive filter: remove invalid values
invalid_poverty <- nsch_nc$poverty_ratio < 0 | nsch_nc$poverty_ratio > 401 | is.na(nsch_nc$poverty_ratio)
if (sum(invalid_poverty) > 0) {
  cat("    WARNING:", sum(invalid_poverty), "records with invalid poverty ratio\n")
  nsch_nc$poverty_ratio[invalid_poverty] <- NA_real_
}

cat("    ✓ Created 8 harmonized variables\n\n")

# 5. Check for missing values
cat("[6] Checking for missing values in harmonized variables...\n")

harmonized_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

missing_counts <- sapply(harmonized_vars, function(v) sum(is.na(nsch_nc[[v]])))
missing_pct <- round(missing_counts / nrow(nsch_nc) * 100, 2)

missing_df <- data.frame(
  variable = harmonized_vars,
  n_missing = missing_counts,
  pct_missing = missing_pct
)

print(missing_df)

# Remove records with missing data in any harmonized variable
nsch_complete <- nsch_nc %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio)
  )

cat("\n    Records with complete data:", nrow(nsch_complete), "/", nrow(nsch_nc),
    "(", round(nrow(nsch_complete) / nrow(nsch_nc) * 100, 1), "%)\\n\\n")

# 6. Get weight variable
cat("[7] Identifying survey weight variable...\n")

# NSCH uses FWC (final weight child)
weight_candidates <- c("FWC", "WEIGHT", "FINALWEIGHT", "fwc")
actual_weight_var <- intersect(weight_candidates, names(nsch_complete))[1]

if (is.na(actual_weight_var)) {
  cat("    WARNING: Standard NSCH weight not found\n")
  cat("    Available weight variables:", paste(grep("weight|wt", names(nsch_complete), value = TRUE, ignore.case = TRUE), collapse = ", "), "\n")
  actual_weight_var <- "FWC"
}

if (!(actual_weight_var %in% names(nsch_complete))) {
  stop(sprintf("Weight variable '%s' not found", actual_weight_var))
}

cat("    Using weight variable:", actual_weight_var, "\n")

# Create base weight column for raking
nsch_complete$base_weight <- nsch_complete[[actual_weight_var]]

cat("\n")

# 7. Perform raking to Nebraska targets
cat("[8] Raking NSCH to Nebraska marginal targets...\n\n")

raking_result <- rake_to_targets(
  nsch_complete,
  target_marginals = target_marginals,
  weight_name = "base_weight",
  max_iterations = 100,
  tolerance = 1e-6
)

nsch_complete <- raking_result$data
nsch_complete$raked_weight <- raking_result$raking_weight

cat("[9] Raking summary:\n")
cat("    Converged:", raking_result$converged, "\n")
cat("    Iterations:", raking_result$n_iterations, "\n")
cat("    Effective N:", round(raking_result$effective_n, 1), "\n")
cat("    Efficiency:", round(raking_result$effective_n / nrow(nsch_complete) * 100, 1), "%\n")
cat("    Weight ratio:", round(raking_result$weight_ratio, 2), "\n\n")

# 8. Final verification
cat("[10] Final verification of raked marginals:\n\n")

verification_table <- data.frame(
  Variable = target_vars,
  ACS_Nebraska = unlist(target_marginals),
  Raked_NSCH = NA_real_,
  Difference = NA_real_
)

for (i in seq_along(target_vars)) {
  var <- target_vars[i]
  raked_mean <- weighted.mean(nsch_complete[[var]], nsch_complete$raked_weight, na.rm = TRUE)
  verification_table$Raked_NSCH[i] <- raked_mean
  verification_table$Difference[i] <- abs(raked_mean - verification_table$ACS_Nebraska[i])
}

print(verification_table)

cat("\n")

# 9. Save raked NSCH data
cat("[11] Saving raked NSCH data...\n")

if (!dir.exists("data/raking/ne25")) {
  dir.create("data/raking/ne25", recursive = TRUE)
}

# Keep base weight, raked weight, and harmonized variables
nsch_output <- nsch_complete %>%
  dplyr::select(
    all_of(c(actual_weight_var, "base_weight", "raked_weight")),
    all_of(harmonized_vars)
  )

saveRDS(nsch_output, "data/raking/ne25/nsch_raked.rds")
cat("    ✓ Saved to: data/raking/ne25/nsch_raked.rds\n")
cat("    Dimensions:", nrow(nsch_output), "rows x", ncol(nsch_output), "columns\n\n")

# Save raking diagnostics
nsch_raking_diagnostics <- list(
  n_raw = nrow(nsch_nc),
  n_complete = nrow(nsch_complete),
  raking_converged = raking_result$converged,
  raking_iterations = raking_result$n_iterations,
  effective_n = raking_result$effective_n,
  efficiency = raking_result$effective_n / nrow(nsch_complete),
  weight_ratio = raking_result$weight_ratio,
  final_marginals = verification_table,
  missing_summary = missing_df
)

saveRDS(nsch_raking_diagnostics, "data/raking/ne25/nsch_raking_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nsch_raking_diagnostics.rds\n\n")

cat("========================================\n")
cat("Task 4a.4 Complete: NSCH Raked to Nebraska\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nsch_complete), "\n")
cat("  - Effective N:", round(raking_result$effective_n, 1), "\n")
cat("  - Efficiency:", round(raking_result$effective_n / nrow(nsch_complete) * 100, 1), "%\n")
cat("  - Marginal verification: max difference =",
    round(max(verification_table$Difference), 6), "\n\n")

cat("Ready for Task 4a.5: Create design matrices from raked data\n\n")
