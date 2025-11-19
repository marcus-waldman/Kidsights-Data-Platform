# =============================================================================
# Import Psychosocial Responses and Add to Historical Calibration Data
# =============================================================================
# Purpose: Load psychosocial item responses (PS001-PS049), reverse code them
#          so higher values = better psychosocial wellbeing, and join with
#          historical_calibration_2020_2024 table
#
# Data Source: data/historical/ps_responses.csv
#   - 836 NE20 participants
#   - 46 psychosocial items (missing PS012, PS021, PS031)
#   - mrwid links to id in calibdat/historical_calibration_2020_2024
#
# Reverse Coding: PS items are psychosocial problems (higher = more problems)
#   - Original: 0=no problem, 1=some, 2=major problem
#   - Reversed: 0=major problem, 1=some, 2=no problem (higher = better wellbeing)
#
# Join Strategy: Right join from ps_responses to keep all PS records
#   - 833 will match historical_calibration_2020_2024 NE20 records
#   - 3 additional PS-only records will be added (IDs: 1, 230, 1646)
#
# Output: Updates historical_calibration_2020_2024 table with PS columns
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IMPORT PSYCHOSOCIAL RESPONSES TO HISTORICAL CALIBRATION DATA\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[1/8] Loading required packages\n")

required_packages <- c("duckdb", "dplyr")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required but not installed.\n", pkg),
         sprintf("Install with: install.packages('%s')", pkg))
  }
}

library(duckdb)
library(dplyr)

cat("      Packages loaded successfully\n\n")

# =============================================================================
# Load Psychosocial Responses
# =============================================================================

cat("[2/8] Loading psychosocial responses from CSV\n")

ps_path <- "data/historical/ps_responses.csv"

if (!file.exists(ps_path)) {
  stop(sprintf("Psychosocial responses file not found at: %s", ps_path))
}

ps_responses <- read.csv(ps_path)

cat(sprintf("      Loaded %d records, %d columns\n", nrow(ps_responses), ncol(ps_responses)))
cat(sprintf("      MRWID range: %.0f to %.0f\n",
            min(ps_responses$mrwid, na.rm = TRUE),
            max(ps_responses$mrwid, na.rm = TRUE)))

# Identify PS item columns
ps_items <- grep("^PS", names(ps_responses), value = TRUE)
cat(sprintf("      PS item columns: %d\n", length(ps_items)))
cat(sprintf("      Items: %s\n\n", paste(head(ps_items, 5), collapse = ", ")))

# =============================================================================
# Reverse Code Psychosocial Items
# =============================================================================

cat("[3/8] Reverse coding PS items (higher = better wellbeing)\n")

# For each PS item, find max value and reverse code
# Original: 0=no problem, 1=some, 2=major problem
# Reversed: 2=no problem, 1=some, 0=major problem

ps_responses_reversed <- ps_responses

for (item in ps_items) {
  # Get non-missing values
  values <- ps_responses[[item]][!is.na(ps_responses[[item]])]

  if (length(values) > 0) {
    max_val <- max(values)
    # Reverse code: new_value = max_value - old_value
    ps_responses_reversed[[item]] <- max_val - ps_responses[[item]]

    # Report if first item
    if (item == ps_items[1]) {
      cat(sprintf("      Example (%s): max=%d, 0→%d, 1→%d, 2→%d\n",
                  item, max_val, max_val-0, max_val-1, max_val-2))
    }
  }
}

cat(sprintf("      Reverse coded %d PS items\n", length(ps_items)))

# Verify reverse coding
original_mean <- mean(ps_responses[[ps_items[1]]], na.rm = TRUE)
reversed_mean <- mean(ps_responses_reversed[[ps_items[1]]], na.rm = TRUE)
cat(sprintf("      Verification (%s): original mean=%.2f, reversed mean=%.2f\n\n",
            ps_items[1], original_mean, reversed_mean))

# =============================================================================
# Connect to DuckDB and Load Historical Calibration Data
# =============================================================================

cat("[4/8] Loading historical calibration data from DuckDB\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("DuckDB database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

# Check if historical_calibration_2020_2024 exists
tables <- DBI::dbListTables(conn)
if (!"historical_calibration_2020_2024" %in% tables) {
  DBI::dbDisconnect(conn)
  stop("Table 'historical_calibration_2020_2024' not found. Run import_historical_calibration.R first.")
}

# Load historical calibration data
historical_calib <- DBI::dbReadTable(conn, "historical_calibration_2020_2024")

cat(sprintf("      Loaded %d records from historical_calibration_2020_2024\n",
            nrow(historical_calib)))

# Count NE20 records (these should match ps_responses)
ne20_count <- sum(historical_calib$study == "NE20")
cat(sprintf("      NE20 records: %d (target for PS join)\n\n", ne20_count))

# =============================================================================
# Map Original IDs to New IDs
# =============================================================================

cat("[5/8] Mapping ps_responses mrwid to new historical ID format\n")

# Historical calibration uses new 12-digit IDs (200311NNNNNN for NE20)
# We need to map original calibdat IDs to these new IDs

# Load original calibdat to get mapping
library(KidsightsPublic)
data(calibdat, package = "KidsightsPublic")

# Create mapping: old id -> new id
# NE20 in historical_calib was created with: 200311000000 + row_number
# We need to recreate this mapping

ne20_original <- calibdat %>%
  dplyr::filter(id >= 1 & id <= 10000) %>%
  dplyr::arrange(id) %>%
  dplyr::mutate(
    row_num = dplyr::row_number(),
    new_id = 200311000000 + row_num
  ) %>%
  dplyr::select(old_id = id, new_id)

cat(sprintf("      Created mapping for %d NE20 records\n", nrow(ne20_original)))

# Join ps_responses with mapping to get new IDs
ps_with_new_ids <- ps_responses_reversed %>%
  dplyr::left_join(ne20_original, by = c("mrwid" = "old_id")) %>%
  dplyr::rename(id = new_id) %>%
  dplyr::select(-mrwid)

matched_count <- sum(!is.na(ps_with_new_ids$id))
cat(sprintf("      Matched %d / %d PS records to new IDs\n",
            matched_count, nrow(ps_with_new_ids)))

# For non-matching records, create new IDs
unmatched <- ps_with_new_ids %>% dplyr::filter(is.na(id))
if (nrow(unmatched) > 0) {
  # Assign new IDs starting after last NE20 ID
  max_ne20_id <- max(ne20_original$new_id)
  ps_with_new_ids <- ps_with_new_ids %>%
    dplyr::mutate(
      id = dplyr::if_else(is.na(id),
                          max_ne20_id + dplyr::row_number(),
                          id)
    )
  cat(sprintf("      Assigned %d new IDs for unmatched PS records\n\n", nrow(unmatched)))
} else {
  cat("\n")
}

# =============================================================================
# Join Psychosocial Responses with Historical Calibration Data
# =============================================================================

cat("[6/8] Joining PS responses with historical calibration data\n")

# Full join to keep all records from both datasets
# This will add PS columns to historical_calib and add PS-only records
historical_with_ps <- historical_calib %>%
  dplyr::full_join(ps_with_new_ids, by = "id")

cat(sprintf("      Combined records: %d\n", nrow(historical_with_ps)))
cat(sprintf("      Original historical records: %d\n", nrow(historical_calib)))
cat(sprintf("      PS response records: %d\n", nrow(ps_with_new_ids)))
cat(sprintf("      New records added: %d\n", nrow(historical_with_ps) - nrow(historical_calib)))

# For PS-only records, fill in study metadata
historical_with_ps <- historical_with_ps %>%
  dplyr::mutate(
    study = dplyr::if_else(is.na(study), "NE20", study)
  )

# Check PS coverage by study
ps_coverage <- historical_with_ps %>%
  dplyr::group_by(study) %>%
  dplyr::summarise(
    n_records = dplyr::n(),
    n_with_ps = sum(!is.na(.data[[ps_items[1]]])),
    pct_with_ps = 100 * sum(!is.na(.data[[ps_items[1]]])) / dplyr::n()
  )

cat("\n      PS item coverage by study:\n")
for (i in 1:nrow(ps_coverage)) {
  cat(sprintf("        %s: %d / %d records (%.1f%%)\n",
              ps_coverage$study[i],
              ps_coverage$n_with_ps[i],
              ps_coverage$n_records[i],
              ps_coverage$pct_with_ps[i]))
}
cat("\n")

# =============================================================================
# Write Updated Table to Database
# =============================================================================

cat("[7/8] Writing updated historical calibration data to database\n")

# Drop existing table
table_name <- "historical_calibration_2020_2024"
cat(sprintf("      Dropping existing '%s' table\n", table_name))
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", table_name))

# Write updated data
cat(sprintf("      Inserting %d records with %d columns\n",
            nrow(historical_with_ps), ncol(historical_with_ps)))
DBI::dbWriteTable(conn, table_name, historical_with_ps, overwrite = TRUE)

# Recreate indexes
cat("      Creating indexes:\n")
index_queries <- c(
  sprintf("CREATE INDEX idx_%s_study ON %s (study)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_study_id ON %s (study, id)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
)

for (query in index_queries) {
  tryCatch({
    DBI::dbExecute(conn, query)
    index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
    cat(sprintf("        [OK] %s\n", index_name))
  }, error = function(e) {
    cat(sprintf("        [WARN] Index creation failed: %s\n", e$message))
  })
}

cat("\n")

# =============================================================================
# Verify Updated Table
# =============================================================================

cat("[8/8] Verifying updated table\n")

verify_count <- DBI::dbGetQuery(conn,
  sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

cat(sprintf("      Total records: %d\n", verify_count))

# Study breakdown
study_counts <- DBI::dbGetQuery(conn,
  sprintf("SELECT study, COUNT(*) as n FROM %s GROUP BY study ORDER BY study", table_name))
cat("\n      Study breakdown:\n")
for (i in 1:nrow(study_counts)) {
  cat(sprintf("        %s: %d records\n", study_counts$study[i], study_counts$n[i]))
}

# PS item coverage
ps_counts <- DBI::dbGetQuery(conn,
  sprintf("SELECT COUNT(*) as total,
           SUM(CASE WHEN PS001 IS NOT NULL THEN 1 ELSE 0 END) as with_ps
           FROM %s WHERE study = 'NE20'", table_name))

cat(sprintf("\n      NE20 with PS items: %d / %d (%.1f%%)\n",
            ps_counts$with_ps, ps_counts$total,
            100 * ps_counts$with_ps / ps_counts$total))

# Column count
col_count <- length(DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s LIMIT 0", table_name)))
cat(sprintf("      Total columns: %d (study, id, years + %d items + %d PS items)\n",
            col_count, col_count - 3 - length(ps_items), length(ps_items)))

# Disconnect
DBI::dbDisconnect(conn)
cat("      Disconnected from database\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("PSYCHOSOCIAL RESPONSES IMPORT COMPLETE\n")
cat(strrep("=", 80), "\n\n")

cat("Summary:\n")
cat(sprintf("  Source: data/historical/ps_responses.csv (836 NE20 records)\n"))
cat(sprintf("  Reverse coding: Higher values = better psychosocial wellbeing\n"))
cat(sprintf("  Table updated: historical_calibration_2020_2024\n\n"))

cat("  Records added/updated:\n")
cat(sprintf("    Total records: %d\n", verify_count))
cat(sprintf("    NE20 with PS: %d / %d\n", ps_counts$with_ps, ps_counts$total))
cat(sprintf("    PS items: %d (PS001-PS049, missing PS012/PS021/PS031)\n", length(ps_items)))

cat("\nNext steps:\n")
cat("  1. Verify PS items appear in calibration dataset\n")
cat("  2. Run calibration pipeline to include PS items\n")
cat("  3. Check that higher PS values = better wellbeing in data dictionary\n\n")

cat("[OK] Historical calibration table updated with psychosocial items\n\n")
