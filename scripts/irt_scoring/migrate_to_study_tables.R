# =============================================================================
# Migrate from Combined Tables to Study-Specific Tables
# =============================================================================
# Purpose: Convert old calibration table structure to new study-specific tables
#
# Old structure (deprecated):
#   - historical_calibration_2020_2024 (combined NE20, NE22, USA24)
#   - calibration_dataset_2020_2025 (combined all 6 studies)
#
# New structure:
#   - ne20_calibration, ne22_calibration, usa24_calibration (separate)
#   - ne25_calibration, nsch21_calibration, nsch22_calibration (separate)
#
# This script:
#   1. Checks if old tables exist
#   2. Splits historical_calibration_2020_2024 into 3 study tables
#   3. Drops old tables
#   4. Reports what was done
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("MIGRATE TO STUDY-SPECIFIC CALIBRATION TABLES\n")
cat(strrep("=", 80), "\n\n")

cat("This script will convert old combined tables to new study-specific tables.\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[SETUP] Loading required packages\n")

required_packages <- c("duckdb", "dplyr")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required. Install with: install.packages('%s')",
                 pkg, pkg))
  }
}

library(duckdb)
library(dplyr)

cat("        Packages loaded successfully\n\n")

# =============================================================================
# Connect to Database
# =============================================================================

cat("[SETUP] Connecting to DuckDB database\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("Database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
cat(sprintf("        Connected to: %s\n\n", db_path))

# =============================================================================
# Check Existing Tables
# =============================================================================

cat(strrep("=", 80), "\n")
cat("CHECKING EXISTING TABLES\n")
cat(strrep("=", 80), "\n\n")

tables <- DBI::dbListTables(conn)

old_tables <- c("historical_calibration_2020_2024", "calibration_dataset_2020_2025")
new_tables <- c("ne20_calibration", "ne22_calibration", "ne25_calibration",
                "nsch21_calibration", "nsch22_calibration", "usa24_calibration")

cat("Old table structure (to be migrated):\n")
for (table in old_tables) {
  exists <- table %in% tables
  cat(sprintf("  %s: %s\n", table, ifelse(exists, "[EXISTS]", "[NOT FOUND]")))
}

cat("\nNew table structure (target):\n")
for (table in new_tables) {
  exists <- table %in% tables
  cat(sprintf("  %s: %s\n", table, ifelse(exists, "[EXISTS]", "[NOT FOUND]")))
}

cat("\n")

# =============================================================================
# Migrate Historical Calibration Table
# =============================================================================

if ("historical_calibration_2020_2024" %in% tables) {
  cat(strrep("=", 80), "\n")
  cat("MIGRATING historical_calibration_2020_2024\n")
  cat(strrep("=", 80), "\n\n")

  cat("[1/5] Loading historical calibration data\n")

  historical_data <- DBI::dbGetQuery(conn,
    "SELECT * FROM historical_calibration_2020_2024")

  cat(sprintf("      Loaded %d records\n", nrow(historical_data)))

  # Check if study column exists
  if (!"study" %in% names(historical_data)) {
    cat("      [ERROR] 'study' column not found in historical data\n")
    cat("      Cannot split into study-specific tables\n\n")
  } else {
    cat("\n[2/5] Splitting by study\n")

    # Split by study
    ne20_data <- historical_data %>% dplyr::filter(study == "NE20") %>% dplyr::select(-study)
    ne22_data <- historical_data %>% dplyr::filter(study == "NE22") %>% dplyr::select(-study)
    usa24_data <- historical_data %>% dplyr::filter(study == "USA24") %>% dplyr::select(-study)

    cat(sprintf("      NE20:  %d records\n", nrow(ne20_data)))
    cat(sprintf("      NE22:  %d records\n", nrow(ne22_data)))
    cat(sprintf("      USA24: %d records\n", nrow(usa24_data)))

    cat("\n[3/5] Creating study-specific tables\n")

    # Helper function
    create_table <- function(conn, table_name, data) {
      # Drop if exists
      if (table_name %in% DBI::dbListTables(conn)) {
        cat(sprintf("      Dropping existing '%s'\n", table_name))
        DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
      }

      # Create table
      cat(sprintf("      Creating '%s' (%d records)\n", table_name, nrow(data)))
      DBI::dbWriteTable(conn, table_name, data, overwrite = TRUE)

      # Create indexes
      idx_queries <- c(
        sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
        sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
      )

      for (query in idx_queries) {
        tryCatch({
          DBI::dbExecute(conn, query)
        }, error = function(e) {
          # Silently fail if index already exists
        })
      }
    }

    create_table(conn, "ne20_calibration", ne20_data)
    create_table(conn, "ne22_calibration", ne22_data)
    create_table(conn, "usa24_calibration", usa24_data)

    cat("\n[4/5] Dropping old historical_calibration_2020_2024 table\n")
    DBI::dbExecute(conn, "DROP TABLE historical_calibration_2020_2024")
    cat("      Table dropped successfully\n")

    cat("\n[5/5] Historical calibration migration complete\n\n")
  }
} else {
  cat("historical_calibration_2020_2024 not found - skipping migration\n\n")
}

# =============================================================================
# Handle Combined Calibration Dataset Table
# =============================================================================

if ("calibration_dataset_2020_2025" %in% tables) {
  cat(strrep("=", 80), "\n")
  cat("HANDLING calibration_dataset_2020_2025\n")
  cat(strrep("=", 80), "\n\n")

  cat("The 'calibration_dataset_2020_2025' table is no longer needed.\n")
  cat("Data is now stored in study-specific tables and combined at export time.\n\n")

  cat("Drop this table? [y/n]: ")
  response <- readline()

  if (tolower(response) == "y") {
    DBI::dbExecute(conn, "DROP TABLE calibration_dataset_2020_2025")
    cat("[OK] Table dropped successfully\n\n")
  } else {
    cat("[INFO] Table kept. You can drop it manually later with:\n")
    cat("       DROP TABLE calibration_dataset_2020_2025;\n\n")
  }
} else {
  cat("calibration_dataset_2020_2025 not found - no action needed\n\n")
}

# =============================================================================
# Create Remaining Calibration Tables
# =============================================================================

cat(strrep("=", 80), "\n")
cat("CREATING REMAINING CALIBRATION TABLES\n")
cat(strrep("=", 80), "\n\n")

missing_tables <- setdiff(c("ne25_calibration", "nsch21_calibration", "nsch22_calibration"),
                          DBI::dbListTables(conn))

if (length(missing_tables) > 0) {
  cat(sprintf("Missing calibration tables: %s\n\n", paste(missing_tables, collapse = ", ")))
  cat("Create these tables now? [y/n]: ")
  response <- readline()

  if (tolower(response) == "y") {
    DBI::dbDisconnect(conn)
    cat("\nRunning create_calibration_tables.R...\n\n")
    source("scripts/irt_scoring/create_calibration_tables.R")
    create_calibration_tables(studies = missing_tables)

    # Reconnect
    conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
  } else {
    cat("\n[INFO] Run manually later with:\n")
    cat("       source('scripts/irt_scoring/create_calibration_tables.R')\n")
    cat("       create_calibration_tables()\n\n")
  }
} else {
  cat("All calibration tables already exist - no action needed\n\n")
}

# =============================================================================
# Final Status
# =============================================================================

DBI::dbDisconnect(conn)

cat(strrep("=", 80), "\n")
cat("MIGRATION COMPLETE\n")
cat(strrep("=", 80), "\n\n")

# Reconnect read-only to check final state
conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
tables <- DBI::dbListTables(conn)

cat("Current calibration tables:\n")
for (table in new_tables) {
  if (table %in% tables) {
    count <- DBI::dbGetQuery(conn,
      sprintf("SELECT COUNT(*) as n FROM %s", table))$n
    cat(sprintf("  %s: %d records [OK]\n", table, count))
  } else {
    cat(sprintf("  %s: [NOT FOUND]\n", table))
  }
}

DBI::dbDisconnect(conn)

cat("\nNext steps:\n")
cat("  1. Export calibration dataset:\n")
cat("     source('scripts/irt_scoring/export_calibration_dat.R')\n")
cat("     export_calibration_dat()\n\n")
cat("  2. Verify output:\n")
cat("     File: mplus/calibdat.dat\n\n")

cat("[OK] Migration completed successfully\n\n")
