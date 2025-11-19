#!/usr/bin/env Rscript
#
# Database Migration: Add Individual Latent Ability (eta_est) Column
#
# Adds authenticity_eta_est column to ne25_transformed table and populates it
# from the LOOCV and inauthentic results files.
#
# Usage:
#   Rscript scripts/database/add_eta_estimate_column.R
#
# Prerequisites:
#   - results/loocv_authentic_results.rds (from 03_run_loocv.R)
#   - results/inauthentic_logpost_results.rds (from 04_compute_inauthentic_logpost.R)

library(duckdb)
library(dplyr)

cat("\n")
cat("================================================================================\n")
cat("  ADD INDIVIDUAL LATENT ABILITY (eta_est) TO DATABASE\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: CONNECT TO DATABASE AND CHECK COLUMN
# ============================================================================

cat("=== PHASE 1: DATABASE CONNECTION ===\n\n")

db_path <- "data/duckdb/kidsights_local.duckdb"
cat(sprintf("Connecting to: %s\n", db_path))
con <- duckdb::dbConnect(duckdb::duckdb(), db_path)

# Check if column already exists
existing_cols <- DBI::dbListFields(con, "ne25_transformed")
col_name <- "authenticity_eta_est"

if (col_name %in% existing_cols) {
  cat(sprintf("\n[Skip] Column '%s' already exists\n", col_name))

  # Ask if user wants to update values
  cat("\nDo you want to update the existing values? (y/n): ")
  response <- tolower(trimws(readLines("stdin", n=1)))

  if (response != "y") {
    cat("\n[Exit] No changes made\n\n")
    duckdb::dbDisconnect(con, shutdown = TRUE)
    quit(status = 0)
  }

  cat("\n[Update] Proceeding to update existing column\n")

} else {
  cat(sprintf("\n[Add] Creating column '%s'\n", col_name))

  # Add column
  DBI::dbExecute(con, sprintf(
    "ALTER TABLE ne25_transformed ADD COLUMN %s DOUBLE",
    col_name
  ))

  cat(sprintf("[OK] Column '%s' added\n", col_name))
}

# ============================================================================
# PHASE 2: LOAD ETA ESTIMATES FROM RESULTS FILES
# ============================================================================

cat("\n=== PHASE 2: LOAD ETA ESTIMATES ===\n\n")

cat("[1/2] Loading authentic participants' eta estimates...\n")

authentic_results <- readRDS("results/loocv_authentic_results.rds")

authentic_eta <- authentic_results %>%
  dplyr::filter(converged_main & converged_holdout) %>%
  dplyr::select(pid, eta_est) %>%
  dplyr::mutate(authentic = TRUE)

cat(sprintf("      Loaded %d authentic participants\n", nrow(authentic_eta)))

cat("\n[2/2] Loading inauthentic participants' eta estimates...\n")

inauthentic_results <- readRDS("results/inauthentic_logpost_results.rds")

inauthentic_eta <- inauthentic_results %>%
  dplyr::filter(sufficient_data & converged) %>%
  dplyr::select(pid, eta_est) %>%
  dplyr::mutate(authentic = FALSE)

cat(sprintf("      Loaded %d inauthentic participants\n", nrow(inauthentic_eta)))

# Combine
all_eta <- dplyr::bind_rows(authentic_eta, inauthentic_eta)

cat(sprintf("\n[Combined] Total: %d participants with eta estimates\n", nrow(all_eta)))

# ============================================================================
# PHASE 3: UPDATE DATABASE
# ============================================================================

cat("\n=== PHASE 3: UPDATE DATABASE ===\n\n")

cat("[1/2] Creating temporary table with eta estimates...\n")

# Write eta estimates to temporary table
DBI::dbWriteTable(con, "temp_eta_estimates", all_eta, overwrite = TRUE, temporary = TRUE)

cat(sprintf("      [OK] Temporary table created with %d rows\n", nrow(all_eta)))

cat("\n[2/2] Updating ne25_transformed with eta estimates...\n")

# Update ne25_transformed by joining on pid
update_query <- sprintf("
  UPDATE ne25_transformed AS t
  SET %s = temp.eta_est
  FROM temp_eta_estimates AS temp
  WHERE t.pid = temp.pid
", col_name)

rows_updated <- DBI::dbExecute(con, update_query)

cat(sprintf("      [OK] Updated %d rows\n", rows_updated))

# ============================================================================
# PHASE 4: VERIFY UPDATES
# ============================================================================

cat("\n=== PHASE 4: VERIFICATION ===\n\n")

cat("[1/3] Checking for missing values...\n")

missing_query <- sprintf("
  SELECT COUNT(*) as n_missing
  FROM ne25_transformed
  WHERE %s IS NULL
", col_name)

n_missing <- DBI::dbGetQuery(con, missing_query)$n_missing
n_total <- DBI::dbGetQuery(con, "SELECT COUNT(*) FROM ne25_transformed")[[1]]

cat(sprintf("      Total records: %d\n", n_total))
cat(sprintf("      With eta_est: %d (%.1f%%)\n", n_total - n_missing, 100 * (n_total - n_missing) / n_total))
cat(sprintf("      Missing eta_est: %d (%.1f%%)\n", n_missing, 100 * n_missing / n_total))

cat("\n[2/3] Computing summary statistics...\n")

stats_query <- sprintf("
  SELECT
    COUNT(*) as n,
    MIN(%s) as min_eta,
    AVG(%s) as mean_eta,
    MEDIAN(%s) as median_eta,
    MAX(%s) as max_eta
  FROM ne25_transformed
  WHERE %s IS NOT NULL
", col_name, col_name, col_name, col_name, col_name)

stats <- DBI::dbGetQuery(con, stats_query)

cat(sprintf("      N: %d\n", stats$n))
cat(sprintf("      Min: %.4f\n", stats$min_eta))
cat(sprintf("      Mean: %.4f\n", stats$mean_eta))
cat(sprintf("      Median: %.4f\n", stats$median_eta))
cat(sprintf("      Max: %.4f\n", stats$max_eta))

cat("\n[3/3] Comparing authentic vs inauthentic...\n")

group_stats_query <- sprintf("
  SELECT
    authentic,
    COUNT(*) as n,
    AVG(%s) as mean_eta,
    MIN(%s) as min_eta,
    MAX(%s) as max_eta
  FROM ne25_transformed
  WHERE %s IS NOT NULL
  GROUP BY authentic
  ORDER BY authentic DESC
", col_name, col_name, col_name, col_name)

group_stats <- DBI::dbGetQuery(con, group_stats_query)

cat("\n")
print(group_stats)

# ============================================================================
# PHASE 5: CREATE INDEX
# ============================================================================

cat("\n=== PHASE 5: CREATE INDEX ===\n\n")

index_name <- "idx_ne25_authenticity_eta_est"
cat(sprintf("Creating index: %s\n", index_name))

index_query <- sprintf("
  CREATE INDEX IF NOT EXISTS %s ON ne25_transformed(%s)
", index_name, col_name)

DBI::dbExecute(con, index_query)

cat(sprintf("      [OK] Index created: %s\n", index_name))

# ============================================================================
# CLEANUP AND SUMMARY
# ============================================================================

# Drop temporary table
DBI::dbExecute(con, "DROP TABLE IF EXISTS temp_eta_estimates")

# Disconnect
duckdb::dbDisconnect(con, shutdown = TRUE)

cat("\n")
cat("================================================================================\n")
cat("  MIGRATION COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  - Added/Updated column: %s\n", col_name))
cat(sprintf("  - Total records: %d\n", n_total))
cat(sprintf("  - Records with eta_est: %d (%.1f%%)\n", n_total - n_missing, 100 * (n_total - n_missing) / n_total))
cat(sprintf("  - eta_est range: [%.4f, %.4f]\n", stats$min_eta, stats$max_eta))
cat("\n")

cat("Interpretation:\n")
cat("  - authenticity_eta_est: Individual's latent ability on the developmental construct\n")
cat("  - Higher values indicate more advanced developmental skills\n")
cat("  - This is the person-level random effect (eta_i) from the GLMM\n")
cat("  - Missing values: participants with insufficient data (<5 items) or non-convergence\n")
cat("\n")

cat("Usage Example (DuckDB SQL):\n")
cat("  SELECT pid, record_id, authenticity_eta_est, authenticity_weight, authenticity_lz\n")
cat("  FROM ne25_transformed\n")
cat("  WHERE authenticity_eta_est IS NOT NULL\n")
cat("  ORDER BY authenticity_eta_est DESC\n")
cat("  LIMIT 10;\n")
cat("\n")

cat("[OK] Done!\n\n")
