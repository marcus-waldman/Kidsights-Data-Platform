# global.R
# Data loading and setup (runs once on app startup)

# Load required packages
library(shiny)
library(duckdb)
library(dplyr)
library(ggplot2)
library(jsonlite)
library(DT)

cat("Loading data...\n")

# ==============================================================================
# Load Calibration Dataset from DuckDB
# ==============================================================================

# Construct path relative to project root (3 levels up from app directory)
db_path <- file.path("..", "..", "..", "data", "duckdb", "kidsights_local.duckdb")

if (!file.exists(db_path)) {
  stop("Database not found at: ", db_path, "\n",
       "Please run the calibration pipeline first.\n",
       "Current working directory: ", getwd())
}

conn <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)

calibration_data <- dbGetQuery(conn, "
  SELECT * FROM calibration_dataset_2020_2025
")

dbDisconnect(conn)

cat(sprintf("  Loaded %d records from calibration_dataset_2020_2025\n",
            nrow(calibration_data)))

# Extract metadata columns
metadata_cols <- c("study", "studynum", "id", "years")
item_cols <- setdiff(names(calibration_data), metadata_cols)

cat(sprintf("  Items available: %d\n", length(item_cols)))

# ==============================================================================
# Load Codebook Metadata
# ==============================================================================

codebook_path <- file.path("..", "..", "..", "codebook", "data", "codebook.json")

if (!file.exists(codebook_path)) {
  stop("Codebook not found at: ", codebook_path)
}

codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

cat(sprintf("  Loaded codebook with %d items\n", length(codebook$items)))

# Create item metadata lookup: item_name -> codebook entry
item_metadata_lookup <- list()

for (item_id in names(codebook$items)) {
  item <- codebook$items[[item_id]]

  # Get equate lexicon name
  if (!is.null(item$lexicons$equate)) {
    equate_name <- item$lexicons$equate

    # Store full item entry
    item_metadata_lookup[[equate_name]] <- item
  }
}

# Create item choices for dropdown (name + description)
item_choices <- sapply(item_cols, function(item_name) {
  item <- item_metadata_lookup[[item_name]]

  if (!is.null(item) && !is.null(item$content$description)) {
    description <- item$content$description

    # Truncate long descriptions
    if (nchar(description) > 80) {
      description <- paste0(substr(description, 1, 77), "...")
    }

    return(paste0(item_name, " - ", description))
  } else {
    return(item_name)
  }
})

names(item_choices) <- item_cols

cat(sprintf("  Created metadata lookup for %d items\n", length(item_metadata_lookup)))

# ==============================================================================
# Load Quality Flags
# ==============================================================================

quality_flags_path <- file.path("..", "..", "..", "docs", "irt_scoring", "quality_flags.csv")

if (file.exists(quality_flags_path)) {
  quality_flags <- read.csv(quality_flags_path, stringsAsFactors = FALSE)
  cat(sprintf("  Loaded %d quality flags\n", nrow(quality_flags)))
} else {
  quality_flags <- data.frame(
    item_id = character(),
    study = character(),
    flag_type = character(),
    flag_severity = character(),
    description = character(),
    stringsAsFactors = FALSE
  )
  cat("  No quality flags file found (empty flags loaded)\n")
}

# ==============================================================================
# Define Study Colors
# ==============================================================================

study_colors <- c(
  "NE20" = "#1f77b4",   # Blue
  "NE22" = "#ff7f0e",   # Orange
  "NE25" = "#2ca02c",   # Green
  "NSCH21" = "#d62728", # Red
  "NSCH22" = "#9467bd", # Purple
  "USA24" = "#8c564b"   # Brown
)

cat("Data loading complete!\n\n")
