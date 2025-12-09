# Phase 4a, Task 1: Extract ACS Nebraska Data
# Loads ACS children ages 0-5 from Nebraska only (2019-2023 pooled)
# Purpose: Serve as population reference for raking targets (geographic stratification via PUMA)

library(DBI)
library(duckdb)
library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.1: Extract ACS Nebraska Data\n")
cat("========================================\n\n")

# 2. Connect to database
cat("[2] Connecting to database...\n")
con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# 3. Check available ACS tables
cat("[3] Checking available ACS data...\n")
tables <- DBI::dbListTables(con)
acs_tables <- grep("^acs_", tables, value = TRUE)
cat("    Available ACS tables:", paste(acs_tables, collapse = ", "), "\n\n")

# 4. Determine which table to use
# Look for acs_data or acs_YYYY_ZZZZ table
acs_table <- NULL

if ("acs_data" %in% tables) {
  acs_table <- "acs_data"
} else if ("acs_2019_2023_pooled" %in% tables) {
  acs_table <- "acs_2019_2023_pooled"
} else {
  # Find any acs_* table with numeric pattern
  acs_candidates <- grep("^acs_[0-9]", tables, value = TRUE)
  if (length(acs_candidates) > 0) {
    acs_table <- acs_candidates[1]
  }
}

if (is.null(acs_table)) {
  cat("    ERROR: No ACS data table found.\n")
  cat("    Available tables:\n")
  print(tables)
  DBI::dbDisconnect(con, shutdown = TRUE)
  stop("ACS table not found. Run ACS pipeline first.")
}

cat("    Using table:", acs_table, "\n\n")

# 5. Extract North Central children ages 0-5
cat("[4] Extracting North Central children (ages 0-5, 2019-2023)...\n")

# Query to get all relevant variables for Nebraska propensity model
# Filter for Nebraska (STATEFIP=31) only
query <- sprintf("
  SELECT
    STATEFIP,
    AGE,
    SEX,
    RACE,
    HISPAN,
    POVERTY,
    EDUC_MOM,
    MARST_HEAD,
    METRO,
    PUMA,
    PERWT,
    MULTYEAR
  FROM %s
  WHERE STATEFIP = 31
    AND AGE <= 5
    AND AGE >= 0
", acs_table)

acs_nc <- DBI::dbGetQuery(con, query)
DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total records extracted:", nrow(acs_nc), "\n")
cat("    Variables:", ncol(acs_nc), "\n\n")

# 5b. Pre-harmonization input validation
cat("[4b] Running pre-harmonization input validation...\n")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
acs_validation <- validate_acs_inputs(acs_nc)

if (!acs_validation$valid) {
  cat("\nWARNING: ACS input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# 6. Basic sample summary
cat("[5] Sample summary:\n")
cat("    Total Nebraska children (0-5):", nrow(acs_nc), "\n")
cat("    Weighted population:", format(sum(acs_nc$PERWT, na.rm = TRUE), big.mark = ","), "\n\n")

# 7. Check for missing values in key variables
cat("[6] Checking data quality...\n")

# Variables needed for propensity model
key_vars <- c("STATEFIP", "AGE", "SEX", "RACE", "HISPAN", "POVERTY",
              "EDUC_MOM", "MARST_HEAD", "PUMA", "PERWT")

missing_summary <- data.frame(
  variable = key_vars,
  n_missing = sapply(key_vars, function(v) sum(is.na(acs_nc[[v]]))),
  pct_missing = sapply(key_vars, function(v)
    round(sum(is.na(acs_nc[[v]])) / nrow(acs_nc) * 100, 2))
)

print(missing_summary)

# Flag if critical variables have high missingness
critical_missing <- missing_summary$pct_missing[missing_summary$variable %in%
  c("STATEFIP", "AGE", "SEX", "PERWT")] > 0.5

if (any(critical_missing)) {
  cat("\n    WARNING: Critical variables have >0.5% missing data\n")
}

# 8. Apply defensive filters
cat("\n[7] Applying defensive filters...\n")

original_n <- nrow(acs_nc)

acs_nc_clean <- acs_nc %>%
  dplyr::filter(
    # Already filtered to Nebraska (STATEFIP=31)
    # Valid age
    AGE >= 0 & AGE <= 5,
    # Valid sex (1=Male, 2=Female)
    SEX %in% c(1, 2),
    # Valid race (exclude missing codes)
    RACE >= 1 & RACE <= 9,
    # Valid Hispanic origin (0=Non-Hispanic, 1-4=Hispanic, exclude 9=Missing)
    HISPAN %in% 0:4,
    # Valid poverty ratio (exclude 600+=N/A, keep 1-501)
    !is.na(POVERTY) & POVERTY >= 1 & POVERTY <= 501,
    # Valid education (0-13, 0=N/A is kept for now, will be NA in harmonization)
    EDUC_MOM >= 0 & EDUC_MOM <= 13,
    # Valid marital status (1-6, exclude 9=Missing)
    MARST_HEAD %in% 1:6,
    # Non-zero person weight
    !is.na(PERWT) & PERWT > 0
  )

cat("    Records before filtering:", original_n, "\n")
cat("    Records after filtering:", nrow(acs_nc_clean), "\n")
cat("    Records removed:", original_n - nrow(acs_nc_clean),
    "(", round((original_n - nrow(acs_nc_clean)) / original_n * 100, 2), "%)\n\n")

# 9. Save to feather format
cat("[8] Saving to feather format...\n")

# Create output directory if needed
if (!dir.exists("data/raking/ne25")) {
  dir.create("data/raking/ne25", recursive = TRUE)
}

output_path <- "data/raking/ne25/acs_north_central.feather"
arrow::write_feather(acs_nc_clean, output_path)

cat("    Saved to:", output_path, "\n")
cat("    File size:", round(file.size(output_path) / 1024^2, 2), "MB\n")
cat("    Dimensions:", nrow(acs_nc_clean), "rows x", ncol(acs_nc_clean), "columns\n\n")

# 10. Summary statistics
cat("[9] Summary statistics:\n")
cat("    Total Nebraska children (0-5):", nrow(acs_nc_clean), "\n")
cat("    Weighted population (Nebraska):",
    format(sum(acs_nc_clean$PERWT), big.mark = ","), "\n")
cat("    Years included:", paste(sort(unique(acs_nc_clean$MULTYEAR)), collapse = ", "), "\n")
cat("    Geographic coverage: 14 Nebraska PUMAs\n\n")

cat("========================================\n")
cat("Task 4a.1 Complete: ACS Nebraska Extracted\n")
cat("========================================\n\n")

cat("Next: Use for PUMA-stratified raking targets (script 27)\n\n")
