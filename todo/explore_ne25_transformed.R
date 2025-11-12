#!/usr/bin/env Rscript
#
# Explore NE25 Transformed Data
#
# Extracts the ne25_transformed table from DuckDB for interactive exploration
#

library(DBI)
library(duckdb)
library(dplyr)

# Connect to database
cat("Connecting to database...\n")
con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

# Extract the full table
cat("Loading ne25_transformed table...\n")
ne25 <- DBI::dbGetQuery(con, "SELECT * FROM ne25_transformed") %>%
  tibble::as_tibble()

# Disconnect
DBI::dbDisconnect(con, shutdown = TRUE)

# Display summary
cat("\n=== NE25 TRANSFORMED DATA ===\n")
cat(sprintf("Rows: %s\n", scales::comma(nrow(ne25))))
cat(sprintf("Columns: %s\n", ncol(ne25)))

cat("\n=== COLUMN NAMES (first 20) ===\n")
print(head(names(ne25), 20))

cat("\n=== DATA SUMMARY ===\n")
cat(sprintf("Eligible participants: %s\n",
            scales::comma(sum(ne25$eligible, na.rm = TRUE))))
cat(sprintf("Authentic participants: %s\n",
            scales::comma(sum(ne25$authentic, na.rm = TRUE))))
cat(sprintf("Included participants: %s\n",
            scales::comma(sum(ne25$meets_inclusion, na.rm = TRUE))))

cat("\n=== ETA ESTIMATES ===\n")
cat(sprintf("authenticity_eta_full (non-NA): %s\n",
            scales::comma(sum(!is.na(ne25$authenticity_eta_full)))))
cat(sprintf("authenticity_eta_holdout (non-NA): %s\n",
            scales::comma(sum(!is.na(ne25$authenticity_eta_holdout)))))

# Display structure
cat("\n=== DATA STRUCTURE (first 10 columns) ===\n")
str(ne25[, 1:min(10, ncol(ne25))])

cat("\n✅ Data loaded successfully!\n")
cat("\nThe 'ne25' dataframe is now available for exploration.\n")
cat("Example usage:\n")
cat("  - View first rows: head(ne25)\n")
cat("  - Column names: names(ne25)\n")
cat("  - Summary stats: summary(ne25)\n")
cat("  - Filter included: ne25 %>% filter(meets_inclusion == TRUE)\n")
cat("  - Explore eta: ne25 %>% select(pid, record_id, authenticity_eta_full, authenticity_eta_holdout)\n")
