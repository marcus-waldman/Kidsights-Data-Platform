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

# ==============================================================================
# Pre-compute Correlation Table
# ==============================================================================

cat("Computing age correlations for all items...\n")

# Studies to include (no NSCH data)
studies_for_corr <- c("NE20", "NE22", "NE25", "USA24")

# Filter out PS (Parenting Stress) items - expected to have negative correlations
item_cols_filtered <- item_cols[!grepl("^PS", item_cols)]

cat(sprintf("  Filtered out %d PS (Parenting Stress) items\n",
            length(item_cols) - length(item_cols_filtered)))

# Initialize correlation matrix
corr_matrix <- data.frame(
  Item = item_cols_filtered,
  stringsAsFactors = FALSE
)

# Calculate correlations for each study
for (study_name in studies_for_corr) {
  study_data <- calibration_data[calibration_data$study == study_name, ]

  corr_values <- sapply(item_cols_filtered, function(item) {
    valid_idx <- !is.na(study_data[[item]]) & !is.na(study_data$years)

    if (sum(valid_idx) >= 30) {
      cor(study_data$years[valid_idx], study_data[[item]][valid_idx],
          use = "complete.obs")
    } else {
      NA_real_
    }
  })

  corr_matrix[[study_name]] <- corr_values
}

# Calculate pooled correlation (all studies combined)
corr_matrix[["Pooled"]] <- sapply(item_cols_filtered, function(item) {
  valid_idx <- !is.na(calibration_data[[item]]) & !is.na(calibration_data$years)

  if (sum(valid_idx) >= 30) {
    cor(calibration_data$years[valid_idx], calibration_data[[item]][valid_idx],
        use = "complete.obs")
  } else {
    NA_real_
  }
})

cat(sprintf("  Computed correlations for %d items across %d studies + pooled\n",
            nrow(corr_matrix), length(studies_for_corr)))

# Debug: Check data structure
cat(sprintf("  corr_matrix dimensions: %d rows x %d columns\n",
            nrow(corr_matrix), ncol(corr_matrix)))
cat(sprintf("  Column names: %s\n", paste(names(corr_matrix), collapse = ", ")))
cat("  First 3 rows:\n")
print(head(corr_matrix, 3))

cat("\nData loading complete!\n\n")
