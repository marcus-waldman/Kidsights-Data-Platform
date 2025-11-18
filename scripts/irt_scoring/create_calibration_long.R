#!/usr/bin/env Rscript
# ==============================================================================
# Create Long Format Calibration Dataset with Masking Flags
# ==============================================================================
#
# This script creates a space-efficient long format calibration dataset:
# - Includes ALL NSCH data (~38K records for external validation)
# - Single copy (no duplication)
# - Masking flags instead of duplicate rows
# - Cook's D computed once (pooled across all data)
#
# Output: ~3.1M rows × 9 columns
# Columns: id, years, study, studynum, lex_equate, y, cooksd_quantile, maskflag, devflag
#
# ==============================================================================

library(duckdb)
library(dplyr)
library(tidyr)
library(future)
library(future.apply)
library(DBI)
library(jsonlite)

cat("\n")
cat(strrep("=", 80), "\n")
cat("CREATE LONG FORMAT CALIBRATION DATASET\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# PHASE 1: Load ALL Data Sources
# ==============================================================================

cat("[PHASE 1/5] Loading all data sources...\n\n")

# -----------------------------------------------------------------------------
# Load historical data (NE20, NE22, USA24)
# -----------------------------------------------------------------------------

cat("[1.1] Loading historical calibration data (NE20, NE22, USA24)...\n")

conn <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

historical_data <- DBI::dbGetQuery(conn, "SELECT * FROM historical_calibration_2020_2024")

cat(sprintf("      Loaded %d records\n", nrow(historical_data)))
cat(sprintf("      Studies: %s\n\n", paste(unique(historical_data$study), collapse=", ")))

# -----------------------------------------------------------------------------
# Load NE25 data
# -----------------------------------------------------------------------------

cat("[1.2] Loading NE25 calibration data...\n")

ne25_data <- DBI::dbGetQuery(conn, "SELECT * FROM ne25_calibration")
ne25_data$study <- "NE25"

cat(sprintf("      Loaded %d records\n\n", nrow(ne25_data)))

# -----------------------------------------------------------------------------
# Load current dev sample to identify NSCH dev IDs
# -----------------------------------------------------------------------------

cat("[1.3] Loading current development sample to identify NSCH dev IDs...\n")

dev_sample <- DBI::dbGetQuery(conn, "SELECT * FROM calibration_dataset_2020_2025")

nsch21_dev_ids <- dev_sample %>%
  dplyr::filter(study == "NSCH21") %>%
  dplyr::pull(id)

nsch22_dev_ids <- dev_sample %>%
  dplyr::filter(study == "NSCH22") %>%
  dplyr::pull(id)

cat(sprintf("      NSCH21 dev IDs: %d\n", length(nsch21_dev_ids)))
cat(sprintf("      NSCH22 dev IDs: %d\n\n", length(nsch22_dev_ids)))

DBI::dbDisconnect(conn, shutdown = TRUE)

# -----------------------------------------------------------------------------
# Load FULL NSCH datasets
# -----------------------------------------------------------------------------

cat("[1.4] Loading FULL NSCH datasets (not sampled)...\n")

# Source helper functions
source("scripts/irt_scoring/helpers/recode_nsch_2021.R")
source("scripts/irt_scoring/helpers/recode_nsch_2022.R")

cat("      Loading NSCH 2021 (full dataset)...\n")
nsch21_full <- recode_nsch_2021(
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb",
  age_filter_years = 6
)
nsch21_full$study <- "NSCH21"
cat(sprintf("        Loaded %d records\n", nrow(nsch21_full)))

cat("      Loading NSCH 2022 (full dataset)...\n")
nsch22_full <- recode_nsch_2022(
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb",
  age_filter_years = 6
)
nsch22_full$study <- "NSCH22"
cat(sprintf("        Loaded %d records\n\n", nrow(nsch22_full)))

# ==============================================================================
# PHASE 2: Reshape to Long Format with devflag
# ==============================================================================

cat("[PHASE 2/5] Reshaping all datasets to long format...\n\n")

# Load codebook to identify valid item columns
cat("[2.0] Loading codebook to identify Kidsights developmental item columns...\n")
codebook <- jsonlite::fromJSON("codebook/data/codebook.json")

# Filter to only items with domains.kidsights defined (excludes health items)
all_items <- names(codebook$items)
valid_items <- character()

for (item_id in all_items) {
  item_info <- codebook$items[[item_id]]
  # Only include items with kidsights domain
  if (!is.null(item_info$domains$kidsights)) {
    valid_items <- c(valid_items, item_id)
  }
}

cat(sprintf("      Total items in codebook: %d\n", length(all_items)))
cat(sprintf("      Kidsights developmental items: %d\n", length(valid_items)))
cat(sprintf("      Excluded items (no kidsights domain): %d\n\n", length(all_items) - length(valid_items)))

# Metadata columns
metadata_cols <- c("study", "studynum", "id", "years", "wgt")

# Function to reshape and assign devflag
reshape_to_long <- function(data, dev_ids = NULL, valid_items) {
  # Identify item columns (must be in codebook AND in data)
  data_cols <- names(data)
  item_cols <- intersect(valid_items, data_cols)

  cat(sprintf("      Data columns: %d, Item columns: %d\n",
              length(data_cols), length(item_cols)))

  # Select only metadata + item columns
  cols_to_keep <- c(metadata_cols[metadata_cols %in% data_cols], item_cols)
  data <- data %>% dplyr::select(dplyr::all_of(cols_to_keep))

  # Reshape to long
  long_data <- data %>%
    tidyr::pivot_longer(
      cols = dplyr::all_of(item_cols),
      names_to = "lex_equate",
      values_to = "y"
    ) %>%
    dplyr::filter(!is.na(y))  # Remove missing responses

  # Assign devflag
  if (!is.null(dev_ids)) {
    long_data$devflag <- ifelse(long_data$id %in% dev_ids, 1, 0)
  } else {
    long_data$devflag <- 1  # Historical + NE25 always in dev sample
  }

  return(long_data)
}

cat("[2.1] Reshaping historical data...\n")
historical_long <- reshape_to_long(historical_data, valid_items = valid_items)
cat(sprintf("      %d rows created\n", nrow(historical_long)))

cat("[2.2] Reshaping NE25 data...\n")
ne25_long <- reshape_to_long(ne25_data, valid_items = valid_items)
cat(sprintf("      %d rows created\n", nrow(ne25_long)))

cat("[2.3] Reshaping NSCH21 data (with devflag)...\n")
nsch21_long <- reshape_to_long(nsch21_full, dev_ids = nsch21_dev_ids, valid_items = valid_items)
cat(sprintf("      %d rows created\n", nrow(nsch21_long)))
cat(sprintf("      devflag=1: %d rows\n", sum(nsch21_long$devflag == 1)))
cat(sprintf("      devflag=0: %d rows\n", sum(nsch21_long$devflag == 0)))

cat("[2.4] Reshaping NSCH22 data (with devflag)...\n")
nsch22_long <- reshape_to_long(nsch22_full, dev_ids = nsch22_dev_ids, valid_items = valid_items)
cat(sprintf("      %d rows created\n", nrow(nsch22_long)))
cat(sprintf("      devflag=1: %d rows\n", sum(nsch22_long$devflag == 1)))
cat(sprintf("      devflag=0: %d rows\n\n", sum(nsch22_long$devflag == 0)))

# Combine all long datasets
cat("[2.5] Combining all datasets...\n")

# Get common columns
common_cols <- intersect(
  names(historical_long),
  intersect(
    names(ne25_long),
    intersect(names(nsch21_long), names(nsch22_long))
  )
)

calibration_long <- dplyr::bind_rows(
  historical_long %>% dplyr::select(dplyr::all_of(common_cols)),
  ne25_long %>% dplyr::select(dplyr::all_of(common_cols)),
  nsch21_long %>% dplyr::select(dplyr::all_of(common_cols)),
  nsch22_long %>% dplyr::select(dplyr::all_of(common_cols))
)

cat(sprintf("      Combined dataset: %d rows\n", nrow(calibration_long)))
cat(sprintf("      Unique items: %d\n", length(unique(calibration_long$lex_equate))))
cat(sprintf("      Studies: %s\n\n", paste(sort(unique(calibration_long$study)), collapse=", ")))

# ==============================================================================
# PHASE 3: Compute Cook's D Quantiles (Parallel)
# ==============================================================================

cat("[PHASE 3/5] Computing Cook's D quantiles for all items...\n\n")

# Setup parallel processing
n_cores <- future::availableCores() - 1
n_cores <- max(1, n_cores)

cat(sprintf("[3.1] Setting up parallel processing (%d workers)...\n", n_cores))
future::plan(future::multisession, workers = n_cores)

# Function to compute Cook's D for a single item
compute_item_cooksd <- function(item_name, calibration_long) {
  # Filter to this item
  item_data <- calibration_long %>%
    dplyr::filter(lex_equate == item_name)

  if (nrow(item_data) < 10) {
    return(NULL)
  }

  # Determine model type
  unique_responses <- sort(unique(item_data$y))
  n_categories <- length(unique_responses)
  is_binary <- n_categories == 2

  # Fit model and compute Cook's D
  tryCatch({
    if (is_binary) {
      model <- glm(y ~ years, data = item_data, family = binomial())
      cooksd <- cooks.distance(model)
    } else {
      model <- lm(y ~ years, data = item_data)
      cooksd <- cooks.distance(model)
    }

    # Calculate quantile within each study
    item_data$cooksd <- cooksd

    item_data <- item_data %>%
      dplyr::group_by(study) %>%
      dplyr::mutate(cooksd_quantile = rank(cooksd, na.last = "keep") / sum(!is.na(cooksd))) %>%
      dplyr::ungroup() %>%
      dplyr::select(id, study, lex_equate, cooksd_quantile)

    return(item_data)

  }, error = function(e) {
    return(NULL)
  })
}

cat("[3.2] Computing Cook's D in parallel...\n")
cat("      This may take 30-60 seconds...\n\n")

start_time <- Sys.time()

# Get unique items
unique_items <- unique(calibration_long$lex_equate)

# Compute Cook's D for all items in parallel
cooksd_results <- future.apply::future_lapply(
  unique_items,
  function(item_name) compute_item_cooksd(item_name, calibration_long),
  future.seed = TRUE
)

# Combine results
cooksd_df <- dplyr::bind_rows(cooksd_results[!sapply(cooksd_results, is.null)])

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat(sprintf("      Completed %d items in %.1f seconds\n", length(unique_items), elapsed))
cat(sprintf("      Cook's D quantiles computed for %d rows\n\n", nrow(cooksd_df)))

# Join back to main dataset
cat("[3.3] Joining Cook's D quantiles to main dataset...\n")

calibration_long <- calibration_long %>%
  dplyr::left_join(cooksd_df, by = c("id", "study", "lex_equate"))

# Fill missing quantiles with 0 (items that failed to compute)
calibration_long$cooksd_quantile[is.na(calibration_long$cooksd_quantile)] <- 0

cat(sprintf("      Joined successfully\n\n"))

# ==============================================================================
# PHASE 4: Apply Masking Logic
# ==============================================================================

cat("[PHASE 4/5] Applying masking logic...\n\n")

# Initialize maskflag = 0
calibration_long$maskflag <- 0

# -----------------------------------------------------------------------------
# NE25 removal masking
# -----------------------------------------------------------------------------

cat("[4.1] Applying NE25 data removal masking...\n")

ne25_removal_items <- c(
  "EG39b", "EG37_2", "AA202", "AA201", "AA68", "AA57",
  "EG30d", "EG32b", "EG30e", "EG29c", "EG21a", "EG13a"
)

ne25_mask <- calibration_long$study == "NE25" &
             calibration_long$lex_equate %in% ne25_removal_items

calibration_long$maskflag[ne25_mask] <- 1

cat(sprintf("      Masked %d NE25 observations\n\n", sum(ne25_mask)))

# -----------------------------------------------------------------------------
# Influence point masking
# -----------------------------------------------------------------------------

cat("[4.2] Applying influence point masking...\n")

# Load item-specific thresholds
review_notes <- read.csv("scripts/temp/review_notes_exclude_influence_points.csv",
                         stringsAsFactors = FALSE)

item_thresholds <- data.frame(
  lex_equate = character(),
  threshold_quantile = numeric(),
  stringsAsFactors = FALSE
)

for (i in 1:nrow(review_notes)) {
  item_id <- review_notes$item_id[i]
  note <- review_notes$note[i]

  # Parse threshold
  if (grepl("1%|1 %", note, ignore.case = TRUE)) {
    threshold_quantile <- 0.99
  } else if (grepl("5%|5 %", note, ignore.case = TRUE)) {
    threshold_quantile <- 0.95
  } else {
    threshold_quantile <- 0.95
  }

  item_thresholds <- rbind(item_thresholds, data.frame(
    lex_equate = item_id,
    threshold_quantile = threshold_quantile,
    stringsAsFactors = FALSE
  ))
}

cat(sprintf("      Loaded thresholds for %d items\n", nrow(item_thresholds)))

# Apply influence point masking
for (i in 1:nrow(item_thresholds)) {
  item_id <- item_thresholds$lex_equate[i]
  threshold <- item_thresholds$threshold_quantile[i]

  influence_mask <- calibration_long$lex_equate == item_id &
                    calibration_long$cooksd_quantile > threshold

  calibration_long$maskflag[influence_mask] <- 1

  if (i %% 50 == 0) {
    cat(sprintf("      Processed %d / %d items...\n", i, nrow(item_thresholds)))
  }
}

total_masked <- sum(calibration_long$maskflag == 1)
cat(sprintf("\n      Total observations masked: %d\n\n", total_masked))

# ==============================================================================
# PHASE 5: Save to Database
# ==============================================================================

cat("[PHASE 5/5] Saving to database...\n\n")

# Create studynum from study name
study_mapping <- c(
  "NE20" = 1,
  "NE22" = 2,
  "NE25" = 3,
  "NSCH21" = 5,
  "NSCH22" = 6,
  "USA24" = 7
)

calibration_long$studynum <- study_mapping[calibration_long$study]

# Select final columns
final_cols <- c("id", "years", "study", "studynum", "lex_equate", "y",
                "cooksd_quantile", "maskflag", "devflag")

calibration_long <- calibration_long %>%
  dplyr::select(dplyr::all_of(final_cols))

cat("[5.1] Final dataset structure:\n")
cat(sprintf("      Rows: %d\n", nrow(calibration_long)))
cat(sprintf("      Columns: %d\n", ncol(calibration_long)))
cat(sprintf("      Column names: %s\n\n", paste(names(calibration_long), collapse=", ")))

# Save to database
cat("[5.2] Writing to DuckDB...\n")

conn <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

# Drop old table if exists
DBI::dbExecute(conn, "DROP TABLE IF EXISTS calibration_dataset_long")

# Create new table
DBI::dbWriteTable(conn, "calibration_dataset_long", calibration_long, overwrite = TRUE)

cat("      Table created successfully\n\n")

# Create indexes
cat("[5.3] Creating indexes...\n")

DBI::dbExecute(conn, "CREATE INDEX idx_long_study ON calibration_dataset_long(study)")
DBI::dbExecute(conn, "CREATE INDEX idx_long_devflag ON calibration_dataset_long(devflag)")
DBI::dbExecute(conn, "CREATE INDEX idx_long_maskflag ON calibration_dataset_long(maskflag)")
DBI::dbExecute(conn, "CREATE INDEX idx_long_item ON calibration_dataset_long(lex_equate)")
DBI::dbExecute(conn, "CREATE INDEX idx_long_study_item ON calibration_dataset_long(study, lex_equate)")

cat("      Indexes created successfully\n\n")

# Verify
final_count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM calibration_dataset_long")$n

DBI::dbDisconnect(conn, shutdown = TRUE)

# ==============================================================================
# Summary Report
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("SUMMARY\n")
cat(strrep("=", 80), "\n\n")

cat("Dataset structure:\n")
cat(sprintf("  Total rows: %d\n", final_count))
cat(sprintf("  Columns: %d\n", ncol(calibration_long)))

cat("\nStudy breakdown:\n")
study_summary <- calibration_long %>%
  dplyr::group_by(study, devflag) %>%
  dplyr::summarise(rows = dplyr::n(), .groups = "drop")
print(study_summary)

cat("\nMasking summary:\n")
cat(sprintf("  maskflag=0 (original): %d observations\n", sum(calibration_long$maskflag == 0)))
cat(sprintf("  maskflag=1 (masked): %d observations\n", total_masked))

cat("\nQuery patterns:\n")
cat("  Development sample (original):\n")
cat("    SELECT * FROM calibration_dataset_long WHERE devflag=1 AND maskflag=0\n")
cat("  Development sample (cleaned for Mplus):\n")
cat("    SELECT * FROM calibration_dataset_long WHERE devflag=1 AND maskflag=0\n")
cat("  NSCH holdout (validation):\n")
cat("    SELECT * FROM calibration_dataset_long WHERE devflag=0 AND maskflag=0\n")

cat("\n[OK] Long format calibration dataset created successfully\n")
