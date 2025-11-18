# global.R
# Data loading and setup (runs once on app startup)

# Load required packages
library(shiny)
library(duckdb)
library(dplyr)
library(ggplot2)
library(jsonlite)
library(DT)
library(MASS)  # For ordered logit models (polr)
library(patchwork)  # For combining plots

# Load notes management functions (DuckDB backend)
source("notes_helpers_db.R")

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

cat(sprintf("  Loaded %d records from calibration_dataset_2020_2025\n",
            nrow(calibration_data)))

# Load maskflag data from long format table
cat("  Loading maskflag data from calibration_dataset_long...\n")
maskflag_data <- dbGetQuery(conn, "
  SELECT id, lex_equate, maskflag
  FROM calibration_dataset_long
  WHERE maskflag = 1
")

cat(sprintf("    Loaded %d masked observations\n", nrow(maskflag_data)))

dbDisconnect(conn)

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
# Load Precomputed Models
# ==============================================================================

precomputed_models_path <- file.path("precomputed_models.rds")

if (file.exists(precomputed_models_path)) {
  cat("\nLoading precomputed models from disk...\n")
  precomputed_models <- readRDS(precomputed_models_path)
  cat(sprintf("  Loaded models for %d items\n", length(precomputed_models)))
} else {
  cat("\n[WARN] Precomputed models not found!\n")
  cat("  Expected file: ", precomputed_models_path, "\n")
  cat("  Please run: source('scripts/shiny/age_gradient_explorer/precompute_models.R')\n")
  cat("  Initializing empty model list (app will have limited functionality)\n")
  precomputed_models <- list()
}

# ==============================================================================
# Pre-compute Regression Coefficient Table
# ==============================================================================

cat("Extracting regression coefficients from precomputed models...\n")

# Studies to include (all studies with calibration data)
studies_for_coef <- c("NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24")

# Filter out PS (Parenting Stress) items - expected to have negative coefficients
item_cols_filtered <- item_cols[!grepl("^PS", item_cols)]

cat(sprintf("  Filtered out %d PS (Parenting Stress) items\n",
            length(item_cols) - length(item_cols_filtered)))

# Initialize coefficient tables (full and no_influence)
coef_table_full <- data.frame(
  Item = item_cols_filtered,
  stringsAsFactors = FALSE
)

coef_table_no_influence <- data.frame(
  Item = item_cols_filtered,
  stringsAsFactors = FALSE
)

# Extract pooled coefficients
cat("  Extracting pooled coefficients...\n")
for (item in item_cols_filtered) {
  if (!is.null(precomputed_models[[item]])) {
    coef_table_full$Pooled[coef_table_full$Item == item] <-
      precomputed_models[[item]]$pooled$beta_years
    # Use 5% threshold for default "no influence" table
    coef_table_no_influence$Pooled[coef_table_no_influence$Item == item] <-
      precomputed_models[[item]]$reduced_5pct$beta_years
  } else {
    coef_table_full$Pooled[coef_table_full$Item == item] <- NA_real_
    coef_table_no_influence$Pooled[coef_table_no_influence$Item == item] <- NA_real_
  }
}

# Extract study-specific coefficients
cat("  Extracting study-specific coefficients...\n")
for (study_name in studies_for_coef) {
  for (item in item_cols_filtered) {
    if (!is.null(precomputed_models[[item]]) &&
        !is.null(precomputed_models[[item]]$study_specific[[study_name]])) {
      coef_table_full[[study_name]][coef_table_full$Item == item] <-
        precomputed_models[[item]]$study_specific[[study_name]]$full$beta_years
      # Use 5% threshold for default "no influence" table
      coef_table_no_influence[[study_name]][coef_table_no_influence$Item == item] <-
        precomputed_models[[item]]$study_specific[[study_name]]$reduced_5pct$beta_years
    } else {
      coef_table_full[[study_name]][coef_table_full$Item == item] <- NA_real_
      coef_table_no_influence[[study_name]][coef_table_no_influence$Item == item] <- NA_real_
    }
  }
}

cat(sprintf("  Extracted coefficients for %d items across %d studies + pooled\n",
            nrow(coef_table_full), length(studies_for_coef)))

# Debug: Check data structure
cat(sprintf("  coef_table_full dimensions: %d rows x %d columns\n",
            nrow(coef_table_full), ncol(coef_table_full)))
cat(sprintf("  Column names: %s\n", paste(names(coef_table_full), collapse = ", ")))
cat("  First 3 rows (full model):\n")
print(head(coef_table_full, 3))

# ==============================================================================
# Initialize Review Notes System (DuckDB Backend)
# ==============================================================================

cat("Initializing review notes database...\n")
init_notes_db()

# One-time migration: Import existing JSON notes into database
# (will skip if JSON file doesn't exist or is empty)
if (file.exists("item_review_notes.json")) {
  cat("Importing existing notes from JSON...\n")
  import_notes_from_json("item_review_notes.json")
}

notes_path <- NULL  # Not used with DB backend, kept for API compatibility

cat("\nData loading complete!\n\n")
