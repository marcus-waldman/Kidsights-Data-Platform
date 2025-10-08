# Phase 2, Task 2.1: Create ACS Survey Design Object
# Purpose: Load Nebraska ACS data and create survey design for estimation

library(dplyr)
library(survey)
library(DBI)
library(duckdb)

# Load helper functions
source("scripts/raking/ne25/estimation_helpers.R")

cat("\n========================================\n")
cat("Task 2.1: Create ACS Survey Design\n")
cat("========================================\n\n")

# 1. Connect to database
cat("[1] Connecting to database...\n")
con <- DBI::dbConnect(duckdb::duckdb(), 
                      dbdir = "data/duckdb/kidsights_local.duckdb",
                      read_only = TRUE)

# 2. Load Nebraska ACS data for children 0-5
cat("[2] Loading ACS data for Nebraska children ages 0-5...\n")
acs_data <- DBI::dbGetQuery(con, "
  SELECT *
  FROM acs_data
  WHERE STATEFIP = 31  -- Nebraska
    AND AGE <= 5       -- Children ages 0-5
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Loaded:", nrow(acs_data), "records\n")

# 3. Apply defensive missing data filters
cat("[3] Applying missing data filters...\n")
acs_clean <- filter_acs_missing(acs_data)

# 3.5. Convert MULTYEAR to numeric for linear modeling
cat("[3.5] Converting MULTYEAR to numeric...\n")
acs_clean$MULTYEAR <- as.numeric(acs_clean$MULTYEAR)
acs_clean$AGE <- as.numeric(acs_clean$AGE)
cat("    MULTYEAR range:", min(acs_clean$MULTYEAR), "-", max(acs_clean$MULTYEAR), "\n")

# 4. Verify required variables
cat("[4] Verifying survey design variables...\n")
required_vars <- c("CLUSTER", "STRATA", "PERWT", "AGE", "MULTYEAR")
missing_vars <- setdiff(required_vars, names(acs_clean))

if (length(missing_vars) > 0) {
  stop("Missing required variables: ", paste(missing_vars, collapse = ", "))
} else {
  cat("    All required variables present\n")
}

# 5. Create survey design object
cat("[5] Creating survey design object...\n")
acs_design <- survey::svydesign(
  ids = ~CLUSTER,      # Primary sampling unit
  strata = ~STRATA,    # Stratification variable
  weights = ~PERWT,    # Person weight
  data = acs_clean,
  nest = TRUE          # Clusters nested within strata
)

cat("    Survey design created successfully\n")
cat("    Sample size:", nrow(acs_design), "\n")
cat("    Number of PSUs:", length(unique(acs_clean$CLUSTER)), "\n")
cat("    Number of strata:", length(unique(acs_clean$STRATA)), "\n")

# 6. Check year distribution
cat("\n[6] Year distribution (MULTYEAR):\n")
year_dist <- acs_clean %>%
  dplyr::group_by(MULTYEAR) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(MULTYEAR)

for (i in 1:nrow(year_dist)) {
  cat("    ", year_dist$MULTYEAR[i], ": ", year_dist$n[i], " children\n", sep = "")
}

# 7. Check age distribution
cat("\n[7] Age distribution:\n")
age_dist <- acs_clean %>%
  dplyr::group_by(AGE) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(AGE)

for (i in 1:nrow(age_dist)) {
  cat("    Age ", age_dist$AGE[i], ": ", age_dist$n[i], " children\n", sep = "")
}

# 8. Save design object for reuse
cat("\n[8] Saving design object...\n")
saveRDS(acs_design, "data/raking/ne25/acs_design.rds")
cat("    Saved to: data/raking/ne25/acs_design.rds\n")

# 9. Summary
cat("\n========================================\n")
cat("Task 2.1 Complete: ACS Design Created\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Sample size:", nrow(acs_design), "children\n")
cat("  - Years: 2019-2023 (via MULTYEAR)\n")
cat("  - Ages: 0-5\n")
cat("  - Survey design: Complex (PSU, strata, weights)\n")
cat("  - Saved to: data/raking/ne25/acs_design.rds\n")
cat("\nReady for estimation tasks 2.2-2.7\n\n")
