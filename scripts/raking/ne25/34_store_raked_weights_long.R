# ============================================================================
# Script 34: Store M calibrated raking weights in long-format DuckDB table
# ============================================================================
#
# Purpose: Consolidate the M per-imputation weight feathers produced by
#          script 33 into the long-format ne25_raked_weights DuckDB table.
#
# Inputs:
#   - data/raking/ne25/ne25_weights/ne25_calibrated_weights_m{1..M}.feather
#   - DuckDB table ne25_raked_weights (schema created by
#     pipelines/python/init_raked_weights_table.py)
#
# Output:
#   - ne25_raked_weights DuckDB table populated with M * N_m rows:
#       columns: (pid, record_id, study_id, imputation_m, calibrated_weight)
#
# Idempotency: TRUNCATEs the table before INSERT so re-running the script
# produces a clean state.
#
# Part of NE25 Bucket 2 (multi-imputation integration). Step 4 of 7.
# See docs/archive/raking/ne25/ne25_weights_roadmap.md and WEIGHT_CONSTRUCTION.qmd section 5.1.
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(DBI)
  library(duckdb)
})

source("R/imputation/config.R")

cat("\n========================================\n")
cat("SCRIPT 34: Store raking weights in long-format DuckDB table\n")
cat("========================================\n\n")

M <- get_n_imputations()
cat(sprintf("Expected imputations: M = %d\n\n", M))

weights_dir <- "data/raking/ne25/ne25_weights"
db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") db_path <- "data/duckdb/kidsights_local.duckdb"
table_name <- "ne25_raked_weights"

# ----------------------------------------------------------------------------
# [1] Load all M weight feathers and assemble long format
# ----------------------------------------------------------------------------
cat("[1] Loading per-imputation weight feathers...\n")

long_list <- vector("list", M)
for (m in seq_len(M)) {
  fpath <- file.path(weights_dir,
                     sprintf("ne25_calibrated_weights_m%d.feather", m))
  if (!file.exists(fpath)) {
    stop(sprintf("Missing weight feather for m=%d: %s\nRun script 33 first.",
                 m, fpath))
  }
  d <- arrow::read_feather(fpath)
  required <- c("pid", "record_id", "study_id", "calibrated_weight")
  missing_cols <- setdiff(required, names(d))
  if (length(missing_cols) > 0) {
    stop(sprintf("Feather m=%d missing columns: %s",
                 m, paste(missing_cols, collapse = ", ")))
  }
  long_list[[m]] <- tibble::tibble(
    pid               = as.integer(d$pid),
    record_id         = as.integer(d$record_id),
    study_id          = as.character(d$study_id),
    imputation_m      = as.integer(m),
    calibrated_weight = as.numeric(d$calibrated_weight)
  )
  cat(sprintf("    m=%d: %d records\n", m, nrow(long_list[[m]])))
}

long_df <- dplyr::bind_rows(long_list)
cat(sprintf("\n    Total long-format rows: %d\n", nrow(long_df)))

# Sanity check: unique (pid, record_id, imputation_m)
n_unique <- long_df %>%
  dplyr::distinct(pid, record_id, imputation_m) %>%
  nrow()
if (n_unique != nrow(long_df)) {
  stop(sprintf("Duplicate (pid, record_id, imputation_m) keys: %d rows but %d unique keys",
               nrow(long_df), n_unique))
}
cat(sprintf("    [OK] All %d rows have unique (pid, record_id, imputation_m)\n",
            nrow(long_df)))

# ----------------------------------------------------------------------------
# [2] Insert into DuckDB (TRUNCATE first for idempotency)
# ----------------------------------------------------------------------------
cat(sprintf("\n[2] Writing to DuckDB table '%s'...\n", table_name))
cat(sprintf("    Database: %s\n", db_path))

con <- DBI::dbConnect(duckdb::duckdb(), db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# Verify table exists with expected schema
tables <- DBI::dbListTables(con)
if (!table_name %in% tables) {
  stop(sprintf(
    "Table '%s' does not exist. Run pipelines/python/init_raked_weights_table.py first.",
    table_name
  ))
}

# TRUNCATE (DuckDB supports DELETE FROM without WHERE for full clear)
n_before <- DBI::dbGetQuery(
  con, sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
)$n
cat(sprintf("    Rows before: %d\n", n_before))

DBI::dbExecute(con, sprintf("DELETE FROM %s", table_name))

# INSERT via registered view (avoids row-by-row INSERT)
DBI::dbAppendTable(con, table_name, long_df)

n_after <- DBI::dbGetQuery(
  con, sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
)$n
cat(sprintf("    Rows after:  %d\n", n_after))

if (n_after != nrow(long_df)) {
  stop(sprintf("Row count mismatch after insert: expected %d, got %d",
               nrow(long_df), n_after))
}

# ----------------------------------------------------------------------------
# [3] Verify distribution by imputation_m
# ----------------------------------------------------------------------------
cat(sprintf("\n[3] Verification:\n"))

group_counts <- DBI::dbGetQuery(
  con,
  sprintf("SELECT imputation_m, COUNT(*) AS n FROM %s GROUP BY imputation_m ORDER BY imputation_m",
          table_name)
)
print(group_counts, row.names = FALSE)

if (length(unique(group_counts$n)) != 1) {
  cat("    [WARN] Row counts differ across imputations (expected identical)\n")
} else {
  cat(sprintf("    [OK] All %d imputations have %d rows\n",
              nrow(group_counts), group_counts$n[1]))
}

# Summary stats on weights
stats <- DBI::dbGetQuery(
  con,
  sprintf(
    "SELECT imputation_m,
            MIN(calibrated_weight) AS min_w,
            MAX(calibrated_weight) AS max_w,
            AVG(calibrated_weight) AS mean_w,
            MAX(calibrated_weight) / MIN(calibrated_weight) AS ratio
     FROM %s
     GROUP BY imputation_m
     ORDER BY imputation_m",
    table_name
  )
)
cat("\n    Per-imputation weight summary:\n")
print(stats, row.names = FALSE, digits = 4)

cat("\n========================================\n")
cat("SCRIPT 34 COMPLETE\n")
cat("========================================\n\n")

cat("ne25_raked_weights table is now populated for M =", M, "imputations.\n")
cat("Next step: update pipeline Step 6.9 to read from this table (step 6).\n")
