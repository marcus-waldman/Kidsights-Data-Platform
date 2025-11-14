# Phase 4, Task 4.1: Filter to Nebraska children ages 0-5
# Load NSCH 2023 data, verify sample sizes

library(DBI)
library(duckdb)
library(dplyr)

cat("\n========================================\n")
cat("Task 4.1: Filter NSCH to Nebraska Children Ages 0-5\n")
cat("========================================\n\n")

# 1. Connect to database
cat("[1] Connecting to database...\n")
con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# 2. Load NSCH 2023 Nebraska children ages 0-5
cat("[2] Loading NSCH 2023 Nebraska children (FIPSST=31, ages 0-5)...\n")

nsch_ne <- DBI::dbGetQuery(con, "
  SELECT *
  FROM nsch_2023
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total records:", nrow(nsch_ne), "\n\n")

# 3. Sample size by age
cat("[3] Sample size by age bin:\n")
age_dist <- nsch_ne %>%
  dplyr::group_by(SC_AGE_YEARS) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(SC_AGE_YEARS)

print(age_dist)

# 4. Identify weight variable
cat("\n[4] Identifying survey weight variable...\n")
weight_vars <- grep("^FW", names(nsch_ne), value = TRUE)
cat("    Weight variables available:", paste(weight_vars, collapse = ", "), "\n")

# FWC is typically the final weight for child-level estimates
if ("FWC" %in% names(nsch_ne)) {
  cat("    Using FWC (final child weight) for estimation\n")
  nsch_ne$survey_weight <- nsch_ne$FWC
} else {
  cat("    WARNING: FWC not found, using first available weight\n")
  nsch_ne$survey_weight <- nsch_ne[[weight_vars[1]]]
}

# Check weight distribution
cat("    Weight range:", round(min(nsch_ne$survey_weight, na.rm = TRUE), 2),
    "to", round(max(nsch_ne$survey_weight, na.rm = TRUE), 2), "\n")
cat("    Missing weights:", sum(is.na(nsch_ne$survey_weight)), "\n\n")

# 5. Save filtered data
cat("[5] Saving filtered NSCH data...\n")
saveRDS(nsch_ne, "data/raking/ne25/nsch_nebraska_0_5.rds")

cat("    Saved to: data/raking/ne25/nsch_nebraska_0_5.rds\n")
cat("    Dimensions:", nrow(nsch_ne), "rows x", ncol(nsch_ne), "columns\n\n")

cat("========================================\n")
cat("Task 4.1 Complete\n")
cat("========================================\n\n")
