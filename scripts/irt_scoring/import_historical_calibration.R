# =============================================================================
# Import Historical Calibration Data from KidsightsPublic Package
# =============================================================================
# Purpose: Load historical calibration data (NE20, NE22, USA24) from KidsightsPublic
#          package and apply lexicon mapping (kidsight → equate) to harmonize with
#          current codebook naming conventions
#
# Lexicon Mapping: Maps historical kidsight lexicon to equate lexicon
#   - Example: AA10 (kidsight) → EG46b (equate)
#   - Example: DD202 (kidsight) → EG5a (equate)
#   - Uses codebook.json for mapping definitions
#
# Output: 1 DuckDB table:
#   - historical_calibration_2020_2024 (41,577 records with equate lexicon names)
#     - NE20:  37,546 records
#     - NE22:  2,431 records
#     - USA24: 1,600 records
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IMPORT HISTORICAL CALIBRATION DATA FROM KIDSIGHTSPUBLIC PACKAGE\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[1/9] Loading required packages\n")

required_packages <- c("KidsightsPublic", "duckdb", "dplyr", "haven", "jsonlite")

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
library(jsonlite)

cat("      Packages loaded successfully\n\n")

# =============================================================================
# Load Historical Calibration Data from KidsightsPublic
# =============================================================================

cat("[2/9] Loading calibdat from KidsightsPublic package\n")

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

cat("[3/9] Processing calibration data\n")

# Strip haven labels from all columns (prevents errors with summary/median/etc)
cat("      Stripping haven labels from data\n")
calibdat <- calibdat %>%
  dplyr::mutate(dplyr::across(dplyr::everything(), haven::zap_formats))

# =============================================================================
# Map Kidsight Lexicon to Equate Lexicon
# =============================================================================

cat("[4/9] Mapping kidsight lexicon to equate lexicon\n")

# Load codebook
codebook_path <- "codebook/data/codebook.json"
if (!file.exists(codebook_path)) {
  stop(sprintf("Codebook file not found at: %s", codebook_path))
}

cat(sprintf("      Loading codebook from: %s\n", codebook_path))
codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

# Build kidsight → equate mapping from codebook
kidsight_to_equate <- list()
for (item_id in names(codebook$items)) {
  item <- codebook$items[[item_id]]

  # Extract lexicons
  if (!is.null(item$lexicons$kidsight) && nchar(item$lexicons$kidsight) > 0 &&
      !is.null(item$lexicons$equate) && nchar(item$lexicons$equate) > 0) {
    kidsight_name <- item$lexicons$kidsight
    equate_name <- item$lexicons$equate
    kidsight_to_equate[[kidsight_name]] <- equate_name
  }
}

cat(sprintf("      Found %d items with kidsight->equate mappings\n", length(kidsight_to_equate)))

# Identify item columns in calibdat
metadata_cols <- c("id", "years")
item_cols <- setdiff(names(calibdat), metadata_cols)
cat(sprintf("      Item columns in calibdat: %d\n", length(item_cols)))

# Identify which columns need renaming
cols_to_rename <- intersect(item_cols, names(kidsight_to_equate))
cols_no_mapping <- setdiff(item_cols, names(kidsight_to_equate))

cat(sprintf("      Columns to rename (kidsight->equate): %d\n", length(cols_to_rename)))
cat(sprintf("      Columns with no mapping (kept as-is): %d\n", length(cols_no_mapping)))

# Build dplyr rename mapping (new_name = old_name format)
rename_map <- character()
for (old_col in cols_to_rename) {
  new_col <- kidsight_to_equate[[old_col]]
  rename_map[new_col] <- old_col
}

# Apply lexicon mapping
cat("      Applying lexicon mapping (renaming columns)\n")
calibdat <- calibdat %>%
  dplyr::rename(!!!rename_map)

cat(sprintf("      [OK] Lexicon mapping complete\n"))
cat(sprintf("      Sample renamed columns: %s -> %s, %s -> %s\n",
            "AA10", kidsight_to_equate[["AA10"]] %||% "AA10",
            "DD202", kidsight_to_equate[["DD202"]] %||% "DD202"))
cat("\n")

# =============================================================================
# Derive Study Column
# =============================================================================

cat("[5/9] Deriving study column from ID ranges\n")
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

cat("[6/9] Splitting data by study\n")

# Split into separate data frames and create integer IDs following convention: YYFFFSNNNNNN
# YY=year, FFF=031 (Nebraska) or 999 (USA), S=1 (non-NSCH), N=sequential (6 digits)

# NE20: 200311NNNNNN
ne20_data <- calibdat %>%
  dplyr::filter(study == "NE20") %>%
  dplyr::mutate(
    row_num = dplyr::row_number(),
    id = 200311000000 + row_num  # 200311000001, 200311000002, etc.
  ) %>%
  dplyr::select(-row_num, -study) %>%
  dplyr::relocate(id, years)

# NE22: 220311NNNNNN
ne22_data <- calibdat %>%
  dplyr::filter(study == "NE22") %>%
  dplyr::mutate(
    row_num = dplyr::row_number(),
    id = 220311000000 + row_num  # 220311000001, 220311000002, etc.
  ) %>%
  dplyr::select(-row_num, -study) %>%
  dplyr::relocate(id, years)

# USA24: 249991NNNNNN
usa24_data <- calibdat %>%
  dplyr::filter(study == "USA24") %>%
  dplyr::mutate(
    row_num = dplyr::row_number(),
    id = 249991000000 + row_num  # 249991000001, 249991000002, etc.
  ) %>%
  dplyr::select(-row_num, -study) %>%
  dplyr::relocate(id, years)

cat(sprintf("      NE20: %d records, %d columns\n", nrow(ne20_data), ncol(ne20_data)))
cat(sprintf("      NE22: %d records, %d columns\n", nrow(ne22_data), ncol(ne22_data)))
cat(sprintf("      USA24: %d records, %d columns\n", nrow(usa24_data), ncol(usa24_data)))
cat("\n")

# =============================================================================
# Validate Data Structure
# =============================================================================

cat("[7/9] Validating data structure\n")

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

cat("[8/9] Connecting to DuckDB database\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("DuckDB database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
cat(sprintf("      Connected to: %s\n\n", db_path))

# =============================================================================
# Create Combined Historical Calibration Table
# =============================================================================

cat("[9/9] Creating combined historical_calibration_2020_2024 table\n\n")

# Combine all studies into single table
historical_combined <- dplyr::bind_rows(
  ne20_data %>% dplyr::mutate(study = "NE20"),
  ne22_data %>% dplyr::mutate(study = "NE22"),
  usa24_data %>% dplyr::mutate(study = "USA24")
) %>%
  dplyr::relocate(study, id, years)

cat(sprintf("  Combined data: %d records, %d columns\n", nrow(historical_combined), ncol(historical_combined)))

# Drop table if exists
table_name <- "historical_calibration_2020_2024"
if (table_name %in% DBI::dbListTables(conn)) {
  cat(sprintf("  Dropping existing '%s' table\n", table_name))
  DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
}

# Write data
cat(sprintf("  Inserting %d records into '%s'\n", nrow(historical_combined), table_name))
DBI::dbWriteTable(conn, table_name, historical_combined, overwrite = TRUE)

# Create indexes
cat("  Creating indexes:\n")
index_queries <- c(
  sprintf("CREATE INDEX idx_%s_study ON %s (study)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_study_num ON %s (study, id)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
  sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
)

for (query in index_queries) {
  tryCatch({
    DBI::dbExecute(conn, query)
    index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
    cat(sprintf("    [OK] %s\n", index_name))
  }, error = function(e) {
    cat(sprintf("    [WARN] Index creation failed: %s\n", e$message))
  })
}

cat("\n")

# Verify table
cat("  Verifying import:\n")
verify_count <- DBI::dbGetQuery(conn,
  sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

cat(sprintf("    Records in table: %d", verify_count))
if (verify_count == nrow(historical_combined)) {
  cat(" [OK]\n")
} else {
  cat(sprintf(" [WARN] Expected %d\n", nrow(historical_combined)))
}

# Study breakdown
study_counts_db <- DBI::dbGetQuery(conn,
  sprintf("SELECT study, COUNT(*) as n FROM %s GROUP BY study ORDER BY study", table_name))
cat("\n    Study breakdown:\n")
for (i in 1:nrow(study_counts_db)) {
  cat(sprintf("      %s: %d records\n", study_counts_db$study[i], study_counts_db$n[i]))
}

# Age summary
age_summary <- DBI::dbGetQuery(conn,
  sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s", table_name))
cat(sprintf("\n    Age range: %.2f - %.2f years (mean: %.2f)\n",
            age_summary$min, age_summary$max, age_summary$mean))

# Check for equate lexicon names (verify mapping worked)
cols_in_table <- DBI::dbGetQuery(conn,
  sprintf("SELECT * FROM %s LIMIT 0", table_name))
has_aa10 <- "AA10" %in% names(cols_in_table)
has_eg46b <- "EG46b" %in% names(cols_in_table)

cat("\n    Lexicon mapping verification:\n")
cat(sprintf("      Has AA10 (old kidsight name): %s\n", ifelse(has_aa10, "YES [PROBLEM]", "NO [OK]")))
cat(sprintf("      Has EG46b (equate name): %s\n", ifelse(has_eg46b, "YES [OK]", "NO [PROBLEM]")))

total_count <- verify_count

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
cat(sprintf("  Lexicon: Kidsight → Equate (harmonized)\n"))
cat(sprintf("  Table created: historical_calibration_2020_2024\n\n"))

cat("  Study breakdown:\n")
cat(sprintf("    NE20:  %d records\n", nrow(ne20_data)))
cat(sprintf("    NE22:  %d records\n", nrow(ne22_data)))
cat(sprintf("    USA24: %d records\n", nrow(usa24_data)))
cat(sprintf("    Total: %d records\n\n", total_count))

cat(sprintf("  Columns: %d (study, id, years, %d items with equate names)\n",
            ncol(historical_combined), ncol(historical_combined) - 3))

cat(sprintf("\n  Lexicon mapping applied: %d items renamed (kidsight -> equate)\n", length(cols_to_rename)))
cat(sprintf("  Examples: AA10 -> EG46b, DD202 -> %s\n",
            kidsight_to_equate[["DD202"]] %||% "DD202"))

cat("\nNext steps:\n")
cat("  1. Run prepare_calibration_dataset.R to create combined calibration dataset\n")
cat("  2. Verify AA10 no longer appears in final .dat file\n")
cat("  3. Verify only codebook items (299) appear in NAMES field of .inp file\n\n")

cat("[OK] Historical calibration table ready with equate lexicon\n\n")
