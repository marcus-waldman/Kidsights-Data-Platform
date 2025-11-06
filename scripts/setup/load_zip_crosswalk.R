#!/usr/bin/env Rscript

#' Load Nebraska ZIP/County Crosswalk to Database
#'
#' Loads the ZIP code to county crosswalk from the shared OneDrive location
#' and stores it in the DuckDB database for use by eligibility validation.
#'
#' Usage:
#'   source("scripts/setup/load_zip_crosswalk.R")
#'   # or from command line: Rscript scripts/setup/load_zip_crosswalk.R

library(duckdb)
library(DBI)
library(readxl)
library(dplyr)

# Path to the Excel file (OneDrive shared location)
zip_file <- "C:/Users/marcu/University of Nebraska Medical Center/Kidsights Data - General/Phase 2 Data/Zip_County_Code_UPDATED10.18.xlsx"

cat("===========================================\n")
cat("   Load ZIP/County Crosswalk to Database\n")
cat("===========================================\n\n")

# Check if file exists
if (!file.exists(zip_file)) {
  stop("File not found at: ", zip_file, "\n",
       "Please ensure the OneDrive folder is synced and accessible.")
}

cat("[1/6] Loading Excel file...\n")
zip_data <- read_excel(zip_file, sheet = "Master")
cat("      Loaded", nrow(zip_data), "rows from Excel\n\n")

cat("[2/6] Processing crosswalk data...\n")
crosswalk <- zip_data %>%
  dplyr::mutate(
    zip_code = as.character(ZipCode),
    County = stringr::str_remove_all(County, " County")
  ) %>%
  dplyr::group_by(zip_code) %>%
  dplyr::reframe(
    acceptable_counties = paste(unique(County), collapse = "; ")
  )

cat("      Processed", nrow(crosswalk), "unique ZIP codes\n\n")

cat("[3/6] Connecting to database...\n")
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
cat("      Connected to: data/duckdb/kidsights_local.duckdb\n\n")

cat("[4/6] Dropping existing table (if any)...\n")
dbExecute(conn, "DROP TABLE IF EXISTS ne_zip_county_crosswalk")
cat("      Ready to create new table\n\n")

cat("[5/6] Creating ne_zip_county_crosswalk table...\n")
dbWriteTable(conn, "ne_zip_county_crosswalk", crosswalk, overwrite = TRUE)

# Create index for faster lookups
dbExecute(conn, "CREATE INDEX idx_zip_county_zip ON ne_zip_county_crosswalk (zip_code)")
cat("      Table created with index on zip_code\n\n")

cat("[6/6] Verifying table...\n")
count <- dbGetQuery(conn, "SELECT COUNT(*) as n FROM ne_zip_county_crosswalk")$n
cat("      Records:", count, "\n")

# Show sample
sample <- dbGetQuery(conn, "SELECT * FROM ne_zip_county_crosswalk LIMIT 3")
cat("\n      Sample data:\n")
print(sample)

dbDisconnect(conn)

cat("\n===========================================\n")
cat("✅ ZIP/county crosswalk loaded successfully!\n")
cat("===========================================\n\n")

cat("Table: ne_zip_county_crosswalk\n")
cat("Records:", count, "Nebraska ZIP codes\n")
cat("Location: data/duckdb/kidsights_local.duckdb\n\n")

cat("This crosswalk is now used by CID6 (eligibility validation)\n")
cat("to verify that reported ZIP codes match reported counties.\n\n")
