#!/usr/bin/env Rscript

#' Authenticity Screening - Phase 1: Data Preparation
#'
#' This script:
#' 1. Extracts items with lex_equate names from codebook
#' 2. Creates NE25 → lex_equate name mapping
#' 3. Identifies binary vs polytomous items
#' 4. Loads training (authentic) and test (inauthentic) data
#' 5. Vectorizes to Stan format (yvec, ivec, jvec)
#'
#' @output data/temp/item_metadata.rds
#' @output data/temp/stan_data_authentic.rds
#' @output data/temp/stan_data_inauthentic.rds

library(jsonlite)
library(dplyr)
library(DBI)
library(duckdb)

cat("=== PHASE 1: DATA PREPARATION FOR AUTHENTICITY SCREENING ===\n\n")

# Create output directory
dir.create("data/temp", showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# STEP 1: EXTRACT ITEMS FROM CODEBOOK
# ============================================================================

cat("[Step 1/6] Extracting items with lex_equate names from codebook...\n")

codebook_path <- "codebook/data/codebook.json"
cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

item_metadata <- list()

for (item_id in names(cb$items)) {
  item <- cb$items[[item_id]]

  # Check if item has lexicons$equate and lexicons$ne25
  if (!is.null(item$lexicons)) {
    equate_name <- item$lexicons$equate
    ne25_name <- item$lexicons$ne25

    # Handle simplifyVector=FALSE (might be lists)
    if (is.list(equate_name)) equate_name <- unlist(equate_name)
    if (is.list(ne25_name)) ne25_name <- unlist(ne25_name)

    # Only include items with both equate and ne25 names
    if (!is.null(equate_name) && !is.null(ne25_name) &&
        length(equate_name) > 0 && length(ne25_name) > 0 &&
        equate_name != "" && ne25_name != "") {

      # Get response set to determine number of categories
      n_categories <- NA
      response_set_name <- NA

      if (!is.null(item$content) && !is.null(item$content$response_options)) {
        if ("ne25" %in% names(item$content$response_options)) {
          resp_ref <- item$content$response_options$ne25
          if (is.list(resp_ref)) resp_ref <- unlist(resp_ref)

          # Look up response set in codebook
          if (!is.null(resp_ref) && length(resp_ref) == 1) {
            if (resp_ref %in% names(cb$response_sets)) {
              response_set_name <- resp_ref
              response_set <- cb$response_sets[[resp_ref]]

              # Count non-missing categories (exclude -9, -99, etc.)
              valid_categories <- sapply(response_set, function(opt) {
                val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
                as.numeric(val)
              })

              # Only count non-negative values (exclude missing codes)
              n_categories <- sum(valid_categories >= 0)
            }
          }
        }
      }

      # Store metadata
      item_metadata[[equate_name]] <- list(
        item_id = item_id,
        equate_name = equate_name,
        ne25_name = tolower(ne25_name),  # NE25 uses lowercase
        n_categories = n_categories,
        response_set = response_set_name,
        item_type = ifelse(is.na(n_categories), "unknown",
                          ifelse(n_categories == 2, "binary", "polytomous"))
      )
    }
  }
}

cat(sprintf("      Found %d items with both equate and ne25 names\n", length(item_metadata)))

# Convert to data frame
items_df <- dplyr::bind_rows(item_metadata)

# Summary by type
cat("\n      Item type breakdown:\n")
type_summary <- items_df %>%
  dplyr::count(item_type, n_categories) %>%
  dplyr::arrange(item_type, n_categories)
print(type_summary)

cat(sprintf("\n      Total items: %d\n", nrow(items_df)))
cat(sprintf("        Binary (2 categories): %d\n", sum(items_df$item_type == "binary")))
cat(sprintf("        Polytomous (3+ categories): %d\n", sum(items_df$item_type == "polytomous")))
cat(sprintf("        Unknown: %d\n", sum(items_df$item_type == "unknown")))

# Filter to validated items only (have response_sets)
cat("\n      Filtering to validated items only...\n")
items_df <- items_df %>%
  dplyr::filter(!is.na(response_set) & response_set != "")

cat(sprintf("      Using %d validated items for analysis\n", nrow(items_df)))
cat(sprintf("        Binary: %d\n", sum(items_df$item_type == "binary")))
cat(sprintf("        Polytomous: %d\n", sum(items_df$item_type == "polytomous")))

# ============================================================================
# STEP 2: LOAD TRAINING AND TEST DATA FROM DATABASE
# ============================================================================

cat("\n[Step 2/6] Loading training and test data from database...\n")

conn <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

# Query authentic participants (training set)
authentic_query <- "
  SELECT *, age_in_days / 365.25 AS age_years
  FROM ne25_transformed
  WHERE eligible = TRUE AND authentic = TRUE
"

authentic_data <- DBI::dbGetQuery(conn, authentic_query)
cat(sprintf("      Loaded %d authentic participants\n", nrow(authentic_data)))

# Query inauthentic participants (test set)
inauthentic_query <- "
  SELECT *, age_in_days / 365.25 AS age_years
  FROM ne25_transformed
  WHERE eligible = TRUE AND authentic = FALSE
"

inauthentic_data <- DBI::dbGetQuery(conn, inauthentic_query)
cat(sprintf("      Loaded %d inauthentic participants\n", nrow(inauthentic_data)))

DBI::dbDisconnect(conn, shutdown = TRUE)

# ============================================================================
# STEP 3: SELECT ITEM COLUMNS
# ============================================================================

cat("\n[Step 3/6] Selecting item columns from data...\n")

# Get NE25 column names from item metadata
ne25_columns <- items_df$ne25_name

# Check which columns exist in the data
existing_cols <- ne25_columns[ne25_columns %in% names(authentic_data)]
missing_cols <- ne25_columns[!ne25_columns %in% names(authentic_data)]

cat(sprintf("      Found %d / %d items in database\n", length(existing_cols), length(ne25_columns)))
if (length(missing_cols) > 0) {
  cat(sprintf("      Warning: %d items missing from database\n", length(missing_cols)))
  cat("      First 10 missing:", paste(head(missing_cols, 10), collapse = ", "), "\n")
}

# Filter item metadata to only existing columns
items_df <- items_df %>%
  dplyr::filter(ne25_name %in% existing_cols)

cat(sprintf("\n      Using %d items for analysis\n", nrow(items_df)))

# ============================================================================
# STEP 4: VECTORIZE TO STAN FORMAT (AUTHENTIC DATA)
# ============================================================================

cat("\n[Step 4/6] Vectorizing authentic data to Stan format...\n")

# Extract item columns + metadata
authentic_items <- authentic_data %>%
  dplyr::select(pid, age_years, dplyr::all_of(items_df$ne25_name))

# Create long format vectors
yvec <- c()
ivec <- c()
jvec <- c()
age_vec <- c()

# Create person index mapping
person_ids <- authentic_items$pid
N <- length(person_ids)

# Create item index mapping
item_names <- items_df$ne25_name
J <- length(item_names)

cat(sprintf("      N = %d persons, J = %d items\n", N, J))

# Loop through persons
for (i in 1:N) {
  person_row <- authentic_items[i, ]
  person_age <- person_row$age_years

  # Loop through items
  for (j in 1:J) {
    item_col <- item_names[j]
    response <- person_row[[item_col]]

    # Only include non-missing responses
    if (!is.na(response)) {
      yvec <- c(yvec, response)
      ivec <- c(ivec, i)
      jvec <- c(jvec, j)
      age_vec <- c(age_vec, person_age)
    }
  }
}

M <- length(yvec)
cat(sprintf("      M = %d non-missing observations\n", M))

# Create K vector (number of categories per item)
K <- items_df$n_categories

# All validated items should have known categories
if (any(is.na(K))) {
  stop("ERROR: Validated items should not have NA categories!")
}

# Create Stan data list (only numeric data for Stan)
stan_data_authentic <- list(
  M = M,
  N = N,
  J = J,
  yvec = as.integer(yvec),
  ivec = as.integer(ivec),
  jvec = as.integer(jvec),
  age = authentic_items$age_years,
  K = as.integer(K)
)

# Store metadata separately (not passed to Stan)
attr(stan_data_authentic, "pid") <- person_ids
attr(stan_data_authentic, "item_names") <- items_df$equate_name

cat("\n      Data structure:\n")
cat(sprintf("        Total observations (M): %d\n", stan_data_authentic$M))
cat(sprintf("        Persons (N): %d\n", stan_data_authentic$N))
cat(sprintf("        Items (J): %d\n", stan_data_authentic$J))
cat(sprintf("        Avg responses per person: %.1f\n", M / N))
cat(sprintf("        Response range: [%.0f, %.0f]\n", min(yvec), max(yvec)))
cat(sprintf("        Age range: [%.1f, %.1f]\n", min(age_vec), max(age_vec)))

# ============================================================================
# STEP 5: VECTORIZE INAUTHENTIC DATA
# ============================================================================

cat("\n[Step 5/6] Vectorizing inauthentic data to Stan format...\n")

inauthentic_items <- inauthentic_data %>%
  dplyr::select(pid, age_years, dplyr::all_of(items_df$ne25_name))

# Same vectorization process
yvec_inauth <- c()
ivec_inauth <- c()
jvec_inauth <- c()
age_vec_inauth <- c()

person_ids_inauth <- inauthentic_items$pid
N_inauth <- length(person_ids_inauth)

for (i in 1:N_inauth) {
  person_row <- inauthentic_items[i, ]
  person_age <- person_row$age_years

  for (j in 1:J) {
    item_col <- item_names[j]
    response <- person_row[[item_col]]

    if (!is.na(response)) {
      yvec_inauth <- c(yvec_inauth, response)
      ivec_inauth <- c(ivec_inauth, i)
      jvec_inauth <- c(jvec_inauth, j)
      age_vec_inauth <- c(age_vec_inauth, person_age)
    }
  }
}

M_inauth <- length(yvec_inauth)

stan_data_inauthentic <- list(
  M = M_inauth,
  N = N_inauth,
  J = J,
  yvec = as.integer(yvec_inauth),
  ivec = as.integer(ivec_inauth),
  jvec = as.integer(jvec_inauth),
  age = inauthentic_items$age_years,
  K = as.integer(K)
)

# Store metadata separately
attr(stan_data_inauthentic, "pid") <- person_ids_inauth
attr(stan_data_inauthentic, "item_names") <- items_df$equate_name

cat(sprintf("      M = %d non-missing observations\n", M_inauth))
cat(sprintf("      N = %d persons\n", N_inauth))
cat(sprintf("      Avg responses per person: %.1f\n", M_inauth / N_inauth))

# ============================================================================
# STEP 6: SAVE OUTPUTS
# ============================================================================

cat("\n[Step 6/6] Saving outputs...\n")

# Save item metadata
saveRDS(items_df, "data/temp/item_metadata.rds")
cat("      Saved: data/temp/item_metadata.rds\n")

# Save Stan data
saveRDS(stan_data_authentic, "data/temp/stan_data_authentic.rds")
cat("      Saved: data/temp/stan_data_authentic.rds\n")

saveRDS(stan_data_inauthentic, "data/temp/stan_data_inauthentic.rds")
cat("      Saved: data/temp/stan_data_inauthentic.rds\n")

# ============================================================================
# PHASE 1 SUMMARY
# ============================================================================

cat("\n=== PHASE 1 COMPLETE ===\n\n")
cat("Summary Statistics:\n")
cat(sprintf("  Items extracted: %d\n", nrow(items_df)))
cat(sprintf("    Binary items: %d\n", sum(items_df$item_type == "binary")))
cat(sprintf("    Polytomous items: %d\n", sum(items_df$item_type == "polytomous")))
cat(sprintf("\n  Training set (authentic):\n"))
cat(sprintf("    N = %d persons\n", stan_data_authentic$N))
cat(sprintf("    M = %d observations\n", stan_data_authentic$M))
cat(sprintf("    Avg responses per person: %.1f\n", stan_data_authentic$M / stan_data_authentic$N))
cat(sprintf("\n  Test set (inauthentic):\n"))
cat(sprintf("    N = %d persons\n", stan_data_inauthentic$N))
cat(sprintf("    M = %d observations\n", stan_data_inauthentic$M))
cat(sprintf("    Avg responses per person: %.1f\n", stan_data_inauthentic$M / stan_data_inauthentic$N))

cat("\n[OK] Phase 1 data preparation complete!\n")
cat("\nNext: Proceed to Phase 2 (Stan model development)\n")
