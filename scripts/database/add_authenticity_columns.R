#!/usr/bin/env Rscript
#
# Database Migration: Add Authenticity Screening Columns
#
# Adds 5 new columns to ne25_transformed table:
# - authenticity_weight (DOUBLE, default 1.0)
# - authenticity_lz (DOUBLE)
# - authenticity_avg_logpost (DOUBLE)
# - authenticity_quintile (INTEGER)
# - meets_inclusion (BOOLEAN, default FALSE)
#
# Usage:
#   Rscript scripts/database/add_authenticity_columns.R

library(duckdb)

cat("\n=== ADDING AUTHENTICITY COLUMNS TO ne25_transformed ===\n\n")

# Connect to database
db_path <- "data/duckdb/kidsights_local.duckdb"
cat(sprintf("Connecting to: %s\n", db_path))
con <- duckdb::dbConnect(duckdb::duckdb(), db_path)

# Check if columns already exist
existing_cols <- DBI::dbListFields(con, "ne25_transformed")
new_cols <- c("authenticity_weight", "authenticity_lz", "authenticity_avg_logpost",
              "authenticity_quintile", "meets_inclusion")

already_exist <- new_cols[new_cols %in% existing_cols]
to_add <- new_cols[!new_cols %in% existing_cols]

if (length(already_exist) > 0) {
  cat("\nColumns already exist (skipping):\n")
  for (col in already_exist) {
    cat(sprintf("  - %s\n", col))
  }
}

if (length(to_add) == 0) {
  cat("\nAll columns already exist. Migration complete.\n\n")
  duckdb::dbDisconnect(con, shutdown = TRUE)
  quit(status = 0)
}

cat("\nAdding columns:\n")
for (col in to_add) {
  cat(sprintf("  - %s\n", col))
}
cat("\n")

# Add columns with ALTER TABLE
tryCatch({

  # authenticity_weight (default 1.0 for authentic participants)
  if ("authenticity_weight" %in% to_add) {
    cat("Adding authenticity_weight...\n")
    DBI::dbExecute(con, "ALTER TABLE ne25_transformed ADD COLUMN authenticity_weight DOUBLE DEFAULT 1.0")
  }

  # authenticity_lz (standardized z-score)
  if ("authenticity_lz" %in% to_add) {
    cat("Adding authenticity_lz...\n")
    DBI::dbExecute(con, "ALTER TABLE ne25_transformed ADD COLUMN authenticity_lz DOUBLE")
  }

  # authenticity_avg_logpost (raw log_posterior / n_items)
  if ("authenticity_avg_logpost" %in% to_add) {
    cat("Adding authenticity_avg_logpost...\n")
    DBI::dbExecute(con, "ALTER TABLE ne25_transformed ADD COLUMN authenticity_avg_logpost DOUBLE")
  }

  # authenticity_quintile (1-5)
  if ("authenticity_quintile" %in% to_add) {
    cat("Adding authenticity_quintile...\n")
    DBI::dbExecute(con, "ALTER TABLE ne25_transformed ADD COLUMN authenticity_quintile INTEGER")
  }

  # meets_inclusion (eligible & has authenticity_weight)
  if ("meets_inclusion" %in% to_add) {
    cat("Adding meets_inclusion...\n")
    DBI::dbExecute(con, "ALTER TABLE ne25_transformed ADD COLUMN meets_inclusion BOOLEAN DEFAULT FALSE")
  }

  cat("\nColumns added successfully.\n")

}, error = function(e) {
  cat(sprintf("\nError adding columns: %s\n", e$message))
  duckdb::dbDisconnect(con, shutdown = TRUE)
  quit(status = 1)
})

# Create indexes for performance
cat("\nCreating indexes...\n")

tryCatch({

  # Index on authenticity_weight (for weighted analyses)
  cat("  - idx_ne25_authenticity_weight\n")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ne25_authenticity_weight ON ne25_transformed(authenticity_weight)")

  # Index on meets_inclusion (for filtering in imputation)
  cat("  - idx_ne25_meets_inclusion\n")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ne25_meets_inclusion ON ne25_transformed(meets_inclusion)")

  cat("\nIndexes created successfully.\n")

}, error = function(e) {
  cat(sprintf("\nWarning: Error creating indexes: %s\n", e$message))
  cat("Continuing...\n")
})

# Verify columns were added
cat("\nVerifying columns...\n")
final_cols <- DBI::dbListFields(con, "ne25_transformed")
verification <- new_cols %in% final_cols

if (all(verification)) {
  cat("\n✓ All columns verified:\n")
  for (col in new_cols) {
    cat(sprintf("  ✓ %s\n", col))
  }
} else {
  cat("\n✗ Missing columns:\n")
  for (i in seq_along(new_cols)) {
    if (!verification[i]) {
      cat(sprintf("  ✗ %s\n", new_cols[i]))
    }
  }
  duckdb::dbDisconnect(con, shutdown = TRUE)
  quit(status = 1)
}

# Disconnect
duckdb::dbDisconnect(con, shutdown = TRUE)

cat("\n=== MIGRATION COMPLETE ===\n\n")
