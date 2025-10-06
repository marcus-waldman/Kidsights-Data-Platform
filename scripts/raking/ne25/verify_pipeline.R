# NE25 Raking Targets Pipeline Verification
# Quick validation script to ensure pipeline executed correctly

library(dplyr)

cat("\n========================================\n")
cat("Pipeline Verification\n")
cat("========================================\n\n")

verification_passed <- TRUE

# 1. Check all required files exist
cat("[1] Checking required files...\n")

required_files <- c(
  "data/raking/ne25/acs_estimates.rds",
  "data/raking/ne25/nhis_estimates.rds",
  "data/raking/ne25/nsch_estimates.rds",
  "data/raking/ne25/raking_targets_consolidated.rds"
)

for (file in required_files) {
  if (file.exists(file)) {
    cat("  ✓", file, "\n")
  } else {
    cat("  ✗", file, "MISSING\n")
    verification_passed <- FALSE
  }
}

cat("\n")

# 2. Check row counts
cat("[2] Checking row counts...\n")

acs_est <- readRDS("data/raking/ne25/acs_estimates.rds")
nhis_est <- readRDS("data/raking/ne25/nhis_estimates.rds")
nsch_est <- readRDS("data/raking/ne25/nsch_estimates.rds")
all_est <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")

cat("  ACS:", nrow(acs_est), "rows (expected: 150)")
if (nrow(acs_est) == 150) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  NHIS:", nrow(nhis_est), "rows (expected: 6)")
if (nrow(nhis_est) == 6) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  NSCH:", nrow(nsch_est), "rows (expected: 24)")
if (nrow(nsch_est) == 24) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  Consolidated:", nrow(all_est), "rows (expected: 180)")
if (nrow(all_est) == 180) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("\n")

# 3. Check estimand counts
cat("[3] Checking estimand counts...\n")

acs_estimands <- length(unique(acs_est$estimand))
nhis_estimands <- length(unique(nhis_est$estimand))
nsch_estimands <- length(unique(nsch_est$estimand))
total_estimands <- length(unique(all_est$estimand))

cat("  ACS estimands:", acs_estimands, "(expected: 25)")
if (acs_estimands == 25) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  NHIS estimands:", nhis_estimands, "(expected: 1)")
if (nhis_estimands == 1) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  NSCH estimands:", nsch_estimands, "(expected: 4)")
if (nsch_estimands == 4) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  Total estimands:", total_estimands, "(expected: 30)")
if (total_estimands == 30) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("\n")

# 4. Check for required columns
cat("[4] Checking required columns...\n")

required_columns <- c(
  "target_id", "survey", "age_years", "estimand", "description",
  "data_source", "estimator", "estimate", "estimation_date"
)

missing_cols <- setdiff(required_columns, names(all_est))

if (length(missing_cols) == 0) {
  cat("  ✓ All required columns present\n")
} else {
  cat("  ✗ Missing columns:", paste(missing_cols, collapse = ", "), "\n")
  verification_passed <- FALSE
}

cat("\n")

# 5. Check missing values
cat("[5] Checking missing values...\n")

# Expected missing: 3 (Emotional/Behavioral at ages 0-2)
expected_missing <- all_est %>%
  dplyr::filter(is.na(estimate)) %>%
  dplyr::filter(estimand == "Emotional/Behavioral Problems" & age_years %in% 0:2)

unexpected_missing <- all_est %>%
  dplyr::filter(is.na(estimate)) %>%
  dplyr::filter(!(estimand == "Emotional/Behavioral Problems" & age_years %in% 0:2))

cat("  Expected missing values:", nrow(expected_missing), "(should be 3)")
if (nrow(expected_missing) == 3) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

cat("  Unexpected missing values:", nrow(unexpected_missing), "(should be 0)")
if (nrow(unexpected_missing) == 0) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  cat("\n  Details:\n")
  print(unexpected_missing %>% dplyr::select(target_id, age_years, estimand, data_source))
  verification_passed <- FALSE
}

cat("\n")

# 6. Check estimate ranges
cat("[6] Checking estimate ranges...\n")

out_of_range <- all_est %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::filter(estimate < 0 | estimate > 1)

cat("  Out-of-range estimates (should be 0):", nrow(out_of_range))
if (nrow(out_of_range) == 0) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  print(out_of_range %>% dplyr::select(target_id, estimand, estimate))
  verification_passed <- FALSE
}

cat("\n")

# 7. Check database (if Python available)
cat("[7] Checking database...\n")

# Check if database file exists
db_file <- "data/duckdb/kidsights_local.duckdb"

if (file.exists(db_file)) {
  cat("  ✓ Database file exists:", db_file, "\n")

  # Try to query the database using R DuckDB
  tryCatch({
    library(DBI)
    library(duckdb)

    con <- DBI::dbConnect(duckdb::duckdb(), db_file, read_only = TRUE)

    # Check table exists
    tables <- DBI::dbListTables(con)
    if ("raking_targets_ne25" %in% tables) {
      cat("  ✓ Table raking_targets_ne25 exists\n")

      # Check row count
      db_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM raking_targets_ne25")$n

      cat("  Database row count:", db_count, "(expected: 180)")
      if (db_count == 180) {
        cat(" ✓\n")
      } else {
        cat(" ✗\n")
        verification_passed <- FALSE
      }

      # Check indexes exist
      indexes <- DBI::dbGetQuery(con, "
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND tbl_name = 'raking_targets_ne25'
      ")

      expected_indexes <- c("idx_estimand", "idx_data_source", "idx_age_years", "idx_estimand_age")
      found_indexes <- indexes$name

      cat("  Indexes found:", length(found_indexes))
      if (length(found_indexes) >= 4) {
        cat(" ✓\n")
      } else {
        cat(" (expected: 4)\n")
      }

    } else {
      cat("  ✗ Table raking_targets_ne25 NOT FOUND\n")
      verification_passed <- FALSE
    }

    DBI::dbDisconnect(con, shutdown = TRUE)

  }, error = function(e) {
    cat("  ✗ Database check failed:", conditionMessage(e), "\n")
    verification_passed <- FALSE
  })

} else {
  cat("  ✗ Database file NOT FOUND:", db_file, "\n")
  verification_passed <- FALSE
}

cat("\n")

# 8. Summary
cat("========================================\n")
if (verification_passed) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================\n\n")
  cat("Pipeline executed successfully!\n")
  cat("  - 180 raking targets created\n")
  cat("  - 30 estimands across 6 age groups\n")
  cat("  - Data loaded to raking_targets_ne25 table\n")
  cat("  - All validation checks passed\n\n")
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================\n\n")
  cat("Some checks did not pass. Please review the output above.\n\n")
}

# Return status invisibly
invisible(verification_passed)
