# ============================================================================
# Script 36: Store Bayesian-bootstrap weights in long-format DuckDB table
# ============================================================================
#
# Purpose: Consolidate all M*B per-(m, b) weight feathers produced by
#          script 35 into the long-format ne25_raked_weights_boot DuckDB
#          table created in step 3 of Bucket 3.
#
# Inputs:
#   - data/raking/ne25/ne25_weights_boot/weights_m{m}_b{b}.feather (M*B files)
#   - DuckDB table ne25_raked_weights_boot (schema from
#     pipelines/python/init_raked_weights_boot_table.py)
#
# Output:
#   - ne25_raked_weights_boot populated with M*B*N rows:
#       (pid, record_id, study_id, imputation_m, boot_b, calibrated_weight)
#
# Idempotency: TRUNCATEs the table before INSERT so re-running produces a
# clean state.
#
# Step 6 of 8 for Bucket 3 (MI + Bayesian bootstrap).
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(DBI)
  library(duckdb)
})

source("R/imputation/config.R")

cat("\n=========================================================\n")
cat("SCRIPT 36: Store Bayesian-bootstrap weights in DuckDB\n")
cat("=========================================================\n\n")

M <- get_n_imputations()
B <- 200    # must match script 35

cat(sprintf("Expected: %d imputations x %d bootstrap draws = %d feather files\n\n",
            M, B, M*B))

boot_dir   <- "data/raking/ne25/ne25_weights_boot"
db_path    <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") db_path <- "data/duckdb/kidsights_local.duckdb"
table_name <- "ne25_raked_weights_boot"

# ----------------------------------------------------------------------------
# [1] Enumerate and validate feather files
# ----------------------------------------------------------------------------
cat("[1] Scanning bootstrap weight feathers...\n")

expected <- expand.grid(m = seq_len(M), b = seq_len(B))
expected$path <- with(expected, file.path(
  boot_dir, sprintf("weights_m%d_b%d.feather", m, b)
))
expected$exists <- file.exists(expected$path)

n_found   <- sum(expected$exists)
n_missing <- sum(!expected$exists)

cat(sprintf("    Found:   %d / %d\n", n_found, nrow(expected)))
if (n_missing > 0) {
  cat(sprintf("    Missing: %d feather files\n", n_missing))
  missing_head <- head(expected$path[!expected$exists], 5)
  cat(sprintf("    First few missing: %s\n",
              paste(basename(missing_head), collapse = ", ")))
  stop("Cannot proceed with missing feathers. Re-run script 35 first.")
}
cat("    [OK] All expected feathers present\n\n")

# ----------------------------------------------------------------------------
# [2] Read and stack into long format
# ----------------------------------------------------------------------------
cat("[2] Reading feathers and assembling long format...\n")

# Progress: read in chunks of 50 to avoid memory spikes on 1,000+ reads
long_chunks <- list()
chunk_size <- 50
n_chunks <- ceiling(nrow(expected) / chunk_size)

for (ci in seq_len(n_chunks)) {
  start <- (ci - 1) * chunk_size + 1
  end   <- min(ci * chunk_size, nrow(expected))
  sub <- expected[start:end, ]

  chunk_dfs <- lapply(seq_len(nrow(sub)), function(i) {
    d <- arrow::read_feather(sub$path[i])
    required <- c("pid", "record_id", "study_id", "imputation_m",
                  "boot_b", "calibrated_weight")
    if (!all(required %in% names(d))) {
      stop(sprintf("Feather %s missing columns: %s",
                   sub$path[i],
                   paste(setdiff(required, names(d)), collapse = ", ")))
    }
    tibble::tibble(
      pid               = as.integer(d$pid),
      record_id         = as.integer(d$record_id),
      study_id          = as.character(d$study_id),
      imputation_m      = as.integer(d$imputation_m),
      boot_b            = as.integer(d$boot_b),
      calibrated_weight = as.numeric(d$calibrated_weight)
    )
  })

  long_chunks[[ci]] <- dplyr::bind_rows(chunk_dfs)
  if (ci %% 5 == 0 || ci == n_chunks) {
    cat(sprintf("    read %d / %d chunks (%d feathers)\n",
                ci, n_chunks, min(ci * chunk_size, nrow(expected))))
  }
}

long_df <- dplyr::bind_rows(long_chunks)
rm(long_chunks); invisible(gc())

cat(sprintf("\n    Total long-format rows: %s\n", format(nrow(long_df), big.mark = ",")))

# Uniqueness check
n_unique <- long_df %>%
  dplyr::distinct(pid, record_id, imputation_m, boot_b) %>%
  nrow()
if (n_unique != nrow(long_df)) {
  stop(sprintf("Duplicate (pid, record_id, m, b) keys: %d rows but %d unique",
               nrow(long_df), n_unique))
}
cat("    [OK] All keys unique\n\n")

# ----------------------------------------------------------------------------
# [3] Insert into DuckDB
# ----------------------------------------------------------------------------
cat(sprintf("[3] Writing to DuckDB table '%s'...\n", table_name))
cat(sprintf("    Database: %s\n", db_path))

con <- DBI::dbConnect(duckdb::duckdb(), db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

tables <- DBI::dbListTables(con)
if (!table_name %in% tables) {
  stop(sprintf("Table '%s' missing. Run init_raked_weights_boot_table.py first.",
               table_name))
}

n_before <- DBI::dbGetQuery(
  con, sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
)$n
cat(sprintf("    Rows before: %s\n", format(n_before, big.mark = ",")))

DBI::dbExecute(con, sprintf("DELETE FROM %s", table_name))
DBI::dbAppendTable(con, table_name, long_df)

n_after <- DBI::dbGetQuery(
  con, sprintf("SELECT COUNT(*) AS n FROM %s", table_name)
)$n
cat(sprintf("    Rows after:  %s\n", format(n_after, big.mark = ",")))

if (n_after != nrow(long_df)) {
  stop(sprintf("Row count mismatch after insert: expected %d, got %d",
               nrow(long_df), n_after))
}

# ----------------------------------------------------------------------------
# [4] Verification
# ----------------------------------------------------------------------------
cat("\n[4] Verification:\n")

by_mb <- DBI::dbGetQuery(con, sprintf("
  SELECT imputation_m, boot_b, COUNT(*) AS n
  FROM %s
  GROUP BY imputation_m, boot_b
", table_name))
unique_mb <- by_mb %>% dplyr::distinct(imputation_m, boot_b) %>% nrow()
cat(sprintf("    Unique (imputation_m, boot_b) pairs: %d (expected %d)\n",
            unique_mb, M*B))
if (unique_mb != M*B) stop("Missing (m, b) combinations after insert")

row_counts <- table(by_mb$n)
cat(sprintf("    Per-(m, b) row counts: %s\n",
            paste(sprintf("%d -> %d pairs", as.integer(names(row_counts)),
                          as.integer(row_counts)), collapse = "; ")))

by_m <- DBI::dbGetQuery(con, sprintf("
  SELECT imputation_m, COUNT(*) AS n
  FROM %s
  GROUP BY imputation_m
  ORDER BY imputation_m
", table_name))
cat("\n    Rows per imputation (expected equal across m):\n")
print(by_m, row.names = FALSE)

weight_stats <- DBI::dbGetQuery(con, sprintf("
  SELECT imputation_m,
         MIN(calibrated_weight) AS min_w,
         MAX(calibrated_weight) AS max_w,
         AVG(calibrated_weight) AS mean_w
  FROM %s
  GROUP BY imputation_m
  ORDER BY imputation_m
", table_name))
cat("\n    Weight summary per imputation (mean_w should be ~1.0):\n")
print(weight_stats, row.names = FALSE, digits = 4)

cat("\n=========================================================\n")
cat("SCRIPT 36 COMPLETE\n")
cat("=========================================================\n\n")

cat(sprintf("ne25_raked_weights_boot populated: %s rows across %d imputations x %d bootstrap draws.\n",
            format(n_after, big.mark = ","), M, B))
cat("MI-aware variance estimation can now query this table per (m, b).\n\n")
