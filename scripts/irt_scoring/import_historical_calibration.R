# =============================================================================
# Import Historical Calibration Data from KidsightsPublic Package
# =============================================================================
# Purpose: One-time script to load historical calibration data (NE20, NE22, USA24)
#          from KidsightsPublic package into DuckDB as separate study tables
#
# Output: 3 DuckDB tables:
#   - ne20_calibration (37,546 records)
#   - ne22_calibration (2,431 records)
#   - usa24_calibration (1,600 records)
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IMPORT HISTORICAL CALIBRATION DATA FROM KIDSIGHTSPUBLIC PACKAGE\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[1/8] Loading required packages\n")

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

cat("[2/8] Loading calibdat from KidsightsPublic package\n")

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

# =============================================================================
# Process Calibration Data
# =============================================================================

cat("[3/8] Processing calibration data\n")

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
  )

# Display available studies
study_counts <- table(calibdat$study)
cat("\n      Available studies in calibdat:\n")
for (study_name in names(study_counts)) {
  cat(sprintf("        %s: %d records\n", study_name, study_counts[study_name]))
}
cat("\n")

# =============================================================================
# Split by Study
# =============================================================================

cat("[4/8] Splitting data by study\n")

# Split into separate data frames (remove study column, not needed in study-specific tables)
ne20_data <- calibdat %>%
  dplyr::filter(study == "NE20") %>%
  dplyr::select(-study) %>%
  dplyr::relocate(id, years)  # Ensure id, years are first

ne22_data <- calibdat %>%
  dplyr::filter(study == "NE22") %>%
  dplyr::select(-study) %>%
  dplyr::relocate(id, years)

usa24_data <- calibdat %>%
  dplyr::filter(study == "USA24") %>%
  dplyr::select(-study) %>%
  dplyr::relocate(id, years)

cat(sprintf("      NE20: %d records, %d columns\n", nrow(ne20_data), ncol(ne20_data)))
cat(sprintf("      NE22: %d records, %d columns\n", nrow(ne22_data), ncol(ne22_data)))
cat(sprintf("      USA24: %d records, %d columns\n", nrow(usa24_data), ncol(usa24_data)))
cat("\n")

# =============================================================================
# Validate Data Structure
# =============================================================================

cat("[5/8] Validating data structure\n")

# Check required columns
required_cols <- c("id", "years")
cat(sprintf("      Required columns (id, years): %s\n",
            ifelse(all(required_cols %in% names(ne20_data)), "YES", "NO")))

# Check age ranges
cat(sprintf("\n      Age ranges (years):\n"))
cat(sprintf("        NE20:  %.2f - %.2f (median: %.2f)\n",
            min(ne20_data$years, na.rm = TRUE),
            max(ne20_data$years, na.rm = TRUE),
            median(ne20_data$years, na.rm = TRUE)))
cat(sprintf("        NE22:  %.2f - %.2f (median: %.2f)\n",
            min(ne22_data$years, na.rm = TRUE),
            max(ne22_data$years, na.rm = TRUE),
            median(ne22_data$years, na.rm = TRUE)))
cat(sprintf("        USA24: %.2f - %.2f (median: %.2f)\n",
            min(usa24_data$years, na.rm = TRUE),
            max(usa24_data$years, na.rm = TRUE),
            median(usa24_data$years, na.rm = TRUE)))

# Check item columns
item_cols <- setdiff(names(ne20_data), c("id", "years"))
cat(sprintf("\n      Kidsights item columns: %d\n", length(item_cols)))
cat(sprintf("      Sample items: %s\n", paste(head(item_cols, 6), collapse = ", ")))

cat("\n")

# =============================================================================
# Connect to DuckDB
# =============================================================================

cat("[6/8] Connecting to DuckDB database\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("DuckDB database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
cat(sprintf("      Connected to: %s\n\n", db_path))

# =============================================================================
# Create Study-Specific Calibration Tables
# =============================================================================

cat("[7/8] Creating study-specific calibration tables\n\n")

# Helper function to create table with indexes
create_calibration_table <- function(conn, table_name, data, study_label) {
  cat(sprintf("  Creating '%s' table\n", table_name))

  # Drop table if exists
  if (table_name %in% DBI::dbListTables(conn)) {
    cat(sprintf("    Dropping existing '%s' table\n", table_name))
    DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
  }

  # Write data
  cat(sprintf("    Inserting %d records\n", nrow(data)))
  DBI::dbWriteTable(conn, table_name, data, overwrite = TRUE)

  # Create indexes
  cat("    Creating indexes:\n")
  index_queries <- c(
    sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
    sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
  )

  for (query in index_queries) {
    tryCatch({
      DBI::dbExecute(conn, query)
      index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
      cat(sprintf("      [OK] %s\n", index_name))
    }, error = function(e) {
      cat(sprintf("      [WARN] Index creation failed: %s\n", e$message))
    })
  }

  cat("\n")
}

# Create tables for each study
create_calibration_table(conn, "ne20_calibration", ne20_data, "NE20")
create_calibration_table(conn, "ne22_calibration", ne22_data, "NE22")
create_calibration_table(conn, "usa24_calibration", usa24_data, "USA24")

# =============================================================================
# Verify Import and Generate Summary
# =============================================================================

cat("[8/8] Verifying import and generating summary\n\n")

# Verify each table
verify_table <- function(conn, table_name, expected_count) {
  actual_count <- DBI::dbGetQuery(conn,
    sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

  cat(sprintf("  %s:\n", table_name))
  cat(sprintf("    Records: %d", actual_count))

  if (actual_count == expected_count) {
    cat(" [OK]\n")
  } else {
    cat(sprintf(" [WARN] Expected %d\n", expected_count))
  }

  # Age summary
  age_summary <- DBI::dbGetQuery(conn,
    sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s",
            table_name))
  cat(sprintf("    Age range: %.2f - %.2f years (mean: %.2f)\n",
              age_summary$min, age_summary$max, age_summary$mean))
  cat("\n")

  return(actual_count)
}

ne20_count <- verify_table(conn, "ne20_calibration", nrow(ne20_data))
ne22_count <- verify_table(conn, "ne22_calibration", nrow(ne22_data))
usa24_count <- verify_table(conn, "usa24_calibration", nrow(usa24_data))

total_count <- ne20_count + ne22_count + usa24_count

# Disconnect
DBI::dbDisconnect(conn)
cat("  Disconnected from database\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("HISTORICAL CALIBRATION DATA IMPORT COMPLETE\n")
cat(strrep("=", 80), "\n\n")

cat("Summary:\n")
cat(sprintf("  Source: KidsightsPublic package (calibdat dataset)\n"))
cat(sprintf("  Tables created: 3 study-specific calibration tables\n\n"))

cat("  Study-specific tables:\n")
cat(sprintf("    ne20_calibration:  %d records\n", ne20_count))
cat(sprintf("    ne22_calibration:  %d records\n", ne22_count))
cat(sprintf("    usa24_calibration: %d records\n", usa24_count))
cat(sprintf("    Total:             %d records\n\n", total_count))

cat(sprintf("  Columns per table: %d (id, years, %d items)\n",
            ncol(ne20_data), ncol(ne20_data) - 2))

cat("\nNext steps:\n")
cat("  1. Create ne25_calibration table (from ne25_transformed)\n")
cat("  2. Create nsch21_calibration table (all records, age < 6)\n")
cat("  3. Create nsch22_calibration table (all records, age < 6)\n")
cat("  4. Use export_calibration_dat() to combine studies and create .dat file\n\n")

cat("[OK] Historical calibration tables ready for use\n\n")
