# =============================================================================
# Import Historical Calibration Data from KidsightsPublic Package
# =============================================================================
# Purpose: One-time script to load historical calibration data (NE20, NE22, USA24)
#          from KidsightsPublic package into DuckDB for use in calibration datasets
#
# Output: DuckDB table 'historical_calibration_2020_2024' with historical data
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IMPORT HISTORICAL CALIBRATION DATA FROM KIDSIGHTSPUBLIC PACKAGE\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[1/7] Loading required packages\n")

required_packages <- c("KidsightsPublic", "duckdb", "dplyr", "haven")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required but not installed.\n", pkg),
         sprintf("Install with: install.packages('%s')", pkg))
  }
}

library(KidsightsPublic)
library(duckdb)
library(dplyr)
library(haven)

cat("      Packages loaded successfully\n\n")

# =============================================================================
# Load Historical Calibration Data from KidsightsPublic
# =============================================================================

cat("[2/7] Loading calibdat from KidsightsPublic package\n")

# Load the calibdat dataset from package
data(calibdat, package = "KidsightsPublic")

if (!exists("calibdat")) {
  stop("Failed to load 'calibdat' from KidsightsPublic package")
}

cat(sprintf("      Loaded calibdat: %d records, %d columns\n",
            nrow(calibdat), ncol(calibdat)))

# Check for required base columns (study column will be derived)
base_cols <- c("id", "years")
missing_cols <- setdiff(base_cols, names(calibdat))
if (length(missing_cols) > 0) {
  stop(sprintf("Required columns missing from calibdat: %s",
               paste(missing_cols, collapse = ", ")))
}

# Strip haven labels from all columns (prevents errors with summary/median/etc)
cat("      Stripping haven labels from data\n")
calibdat <- calibdat %>%
  dplyr::mutate(dplyr::across(dplyr::everything(), haven::zap_formats))

# Derive study column from ID ranges (based on Update-KidsightsPublic/main.R logic)
cat("      Deriving study column from ID ranges\n")
calibdat <- calibdat %>%
  dplyr::mutate(
    study = dplyr::case_when(
      id < 0 ~ "NE22",              # Negative IDs = NE22
      id >= 990000 & id <= 991695 ~ "USA24",  # 990000-991695 = USA24
      .default = "NE20"             # Everything else = NE20
    )
  ) %>%
  dplyr::relocate(study, id, years)  # Put study first

# Display available studies
study_counts <- table(calibdat$study)
cat("\n      Available studies in calibdat:\n")
for (study_name in names(study_counts)) {
  cat(sprintf("        %s: %d records\n", study_name, study_counts[study_name]))
}
cat("\n")

# =============================================================================
# Filter to Historical Studies (NE20, NE22, USA24)
# =============================================================================

cat("[3/7] Filtering to historical studies: NE20, NE22, USA24\n")

historical_studies <- c("NE20", "NE22", "USA24")
historical_data <- calibdat %>%
  dplyr::filter(study %in% historical_studies)

cat(sprintf("      Filtered to %d records from %d studies\n",
            nrow(historical_data), length(unique(historical_data$study))))

# Verify all expected studies present
filtered_studies <- unique(historical_data$study)
missing_studies <- setdiff(historical_studies, filtered_studies)
if (length(missing_studies) > 0) {
  cat(sprintf("      [WARN] Expected studies not found: %s\n",
              paste(missing_studies, collapse = ", ")))
}

# Display filtered study counts
filtered_counts <- table(historical_data$study)
cat("\n      Historical study record counts:\n")
for (study_name in names(filtered_counts)) {
  cat(sprintf("        %s: %d records\n", study_name, filtered_counts[study_name]))
}
cat("\n")

# =============================================================================
# Validate Data Structure
# =============================================================================

cat("[4/7] Validating data structure\n")

# Check for required columns
required_cols <- c("study", "id", "years")
cat(sprintf("      Columns: %d total\n", ncol(historical_data)))
cat(sprintf("      Required columns present: %s\n",
            ifelse(all(required_cols %in% names(historical_data)), "YES", "NO")))

# Check ID uniqueness within studies
id_check <- historical_data %>%
  dplyr::group_by(study) %>%
  dplyr::summarise(
    n_records = dplyr::n(),
    n_unique_ids = dplyr::n_distinct(id),
    has_duplicates = n_records != n_unique_ids
  )

cat("\n      ID uniqueness check:\n")
for (i in 1:nrow(id_check)) {
  status <- ifelse(id_check$has_duplicates[i], "[WARN] DUPLICATES", "[OK]")
  cat(sprintf("        %s: %s (%d records, %d unique IDs)\n",
              id_check$study[i], status, id_check$n_records[i], id_check$n_unique_ids[i]))
}

# Check age range (use direct functions to avoid haven_labelled issues)
cat(sprintf("\n      Age range (years): %.2f - %.2f (median: %.2f)\n",
            min(historical_data$years, na.rm = TRUE),
            max(historical_data$years, na.rm = TRUE),
            median(historical_data$years, na.rm = TRUE)))

# Check item columns (everything except study, id, years)
item_cols <- setdiff(names(historical_data), c("study", "id", "years"))
cat(sprintf("      Kidsights item columns: %d\n", length(item_cols)))

# Sample item names
cat(sprintf("      Sample items: %s\n", paste(head(item_cols, 6), collapse = ", ")))

cat("\n")

# =============================================================================
# Connect to DuckDB
# =============================================================================

cat("[5/7] Connecting to DuckDB database\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("DuckDB database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
cat(sprintf("      Connected to: %s\n\n", db_path))

# =============================================================================
# Create/Replace Historical Calibration Table
# =============================================================================

cat("[6/7] Creating historical_calibration_2020_2024 table\n")

table_name <- "historical_calibration_2020_2024"

# Drop table if exists
if (table_name %in% DBI::dbListTables(conn)) {
  cat(sprintf("      Dropping existing '%s' table\n", table_name))
  DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
}

# Write data to DuckDB
cat(sprintf("      Inserting %d records into '%s'\n", nrow(historical_data), table_name))
DBI::dbWriteTable(conn, table_name, historical_data, overwrite = TRUE)

# Create indexes for faster querying
cat("      Creating indexes:\n")

index_queries <- c(
  sprintf("CREATE INDEX idx_%s_study ON %s (study)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_study_id ON %s (study, id)", table_name, table_name)
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
# Verify Import and Generate Summary
# =============================================================================

cat("[7/7] Verifying import and generating summary\n")

# Count records in new table
table_count <- DBI::dbGetQuery(conn,
  sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

cat(sprintf("      Records in %s: %d\n", table_name, table_count))

if (table_count != nrow(historical_data)) {
  cat("      [WARN] Record count mismatch!\n")
  cat(sprintf("        Expected: %d, Found: %d\n",
              nrow(historical_data), table_count))
} else {
  cat("      [OK] Record count matches\n")
}

# Get study counts from database
study_counts_db <- DBI::dbGetQuery(conn,
  sprintf("SELECT study, COUNT(*) as n FROM %s GROUP BY study ORDER BY study",
          table_name))

cat("\n      Study counts in database:\n")
for (i in 1:nrow(study_counts_db)) {
  cat(sprintf("        %s: %d records\n",
              study_counts_db$study[i], study_counts_db$n[i]))
}

# Check item missingness
item_cols_query <- sprintf("SELECT * FROM %s LIMIT 1", table_name)
sample_row <- DBI::dbGetQuery(conn, item_cols_query)
item_cols_db <- setdiff(names(sample_row), c("study", "id", "years"))

cat(sprintf("\n      Items in database: %d columns\n", length(item_cols_db)))

# Disconnect
DBI::dbDisconnect(conn)
cat("\n      Disconnected from database\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("HISTORICAL CALIBRATION DATA IMPORT COMPLETE\n")
cat(strrep("=", 80), "\n\n")

cat("Summary:\n")
cat(sprintf("  Source: KidsightsPublic package (calibdat dataset)\n"))
cat(sprintf("  Table created: %s\n", table_name))
cat(sprintf("  Total records: %d\n", table_count))
cat(sprintf("  Studies: %s\n", paste(study_counts_db$study, collapse = ", ")))
cat(sprintf("  Items: %d Kidsights item columns\n", length(item_cols_db)))
cat(sprintf("  Age range: %.2f - %.2f years\n",
            min(historical_data$years, na.rm = TRUE),
            max(historical_data$years, na.rm = TRUE)))

cat("\nNext steps:\n")
cat("  1. Use this historical data in prepare_calibration_dataset.R\n")
cat("  2. Combine with NE25 data (from ne25_transformed table)\n")
cat("  3. Combine with NSCH 2021/2022 data (via recode_nsch functions)\n")
cat("  4. Create complete calibdat for Mplus calibration\n\n")

cat("[OK] Historical calibration data ready for use\n\n")
