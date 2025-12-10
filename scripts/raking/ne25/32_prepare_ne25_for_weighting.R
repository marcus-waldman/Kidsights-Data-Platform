# ==============================================================================
# Script: 32_prepare_ne25_for_weighting.R
# Purpose: Create M=1 harmonized NE25 dataset matching unified moment structure
#          for KL divergence weighting using database-imputed PUMA + CART
#
# Overview:
#     1. Load base NE25 data (meets_inclusion=TRUE, n=2,785)
#     2. Join imputed PUMA from ne25_imputed_puma table (M=1)
#     3. Preprocess CBSA (extract first value from semicolon-delimited strings)
#     4. Impute remaining missing values using CART (mice package, M=1)
#     5. Harmonize to 24-variable structure (7 demo + 14 PUMA + 2 mental health + 1 outcome)
#     6. Validate data quality
#     7. Save ne25_harmonized_m1.feather
#
# Output:
#   - ne25_harmonized_m1.feather (2,785 rows × 27 columns)
#   - Columns: pid, record_id, study_id + 24 harmonized variables
#
# Dependencies:
#   - ne25_transformed table (base data without geography)
#   - ne25_imputed_puma table (from imputation pipeline)
#   - mice package (for CART imputation of non-geographic variables)
#   - harmonize_puma.R (PUMA binary dummies)
#   - harmonize_ne25_demographics.R
#   - harmonize_ne25_outcomes.R
#
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup and Configuration
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(mice)  # For CART imputation

# Source utility functions
source("scripts/raking/ne25/utils/harmonize_puma.R")
source("scripts/raking/ne25/utils/harmonize_ne25_demographics.R")
source("scripts/raking/ne25/utils/harmonize_ne25_outcomes.R")

# Database path (from environment or default)
db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") {
  db_path <- "data/duckdb/kidsights_local.duckdb"
}

# Output directory
output_dir <- "data/raking/ne25/ne25_harmonized"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

cat("========================================\n")
cat("Phase 1: Prepare NE25 for KL Weighting\n")
cat("========================================\n\n")

# ==============================================================================
# SECTION 1: Load Base NE25 Data and Derive PUMA from ZIP Code
# ==============================================================================

cat("[1] Loading base NE25 data with ZIP codes...\n")

con <- dbConnect(duckdb(), db_path)

# Load records with meets_inclusion filter including sq001 (ZIP code)
base_data <- dbGetQuery(con, "
  SELECT
    pid,
    record_id,
    sq001 as zipcode,
    years_old,
    female,
    raceG,
    educ_mom,
    fpl,
    phq2_total,
    gad2_total,
    child_ace_total,
    mmi100
  FROM ne25_transformed
  WHERE meets_inclusion = TRUE
")

cat(sprintf("    ✓ Loaded %d records (meets_inclusion=TRUE)\n", nrow(base_data)))

# ==============================================================================
# SECTION 1.1: Join PUMA from ZIP Code Crosswalk
# ==============================================================================

cat("\n[1.1] Deriving PUMA from ZIP codes...\n")

# Query geo_zip_to_puma crosswalk
zip_to_puma <- dbGetQuery(con, "
  SELECT
    zcta as zipcode,
    puma22 as puma,
    afact,
    ROW_NUMBER() OVER (PARTITION BY zcta ORDER BY afact DESC) as puma_rank
  FROM geo_zip_to_puma
")

# Count ZIPs with single vs multiple PUMAs
zip_puma_counts <- zip_to_puma %>%
  dplyr::group_by(zipcode) %>%
  dplyr::summarise(n_pumas = dplyr::n(), .groups = "drop")

n_single_puma_zips <- sum(zip_puma_counts$n_pumas == 1)
n_multi_puma_zips <- sum(zip_puma_counts$n_pumas > 1)

cat(sprintf("    Crosswalk: %d ZIPs with single PUMA, %d ZIPs with multiple PUMAs\n",
            n_single_puma_zips, n_multi_puma_zips))

# For deterministic matching, take highest afact PUMA for each ZIP
zip_to_puma_primary <- zip_to_puma %>%
  dplyr::filter(puma_rank == 1) %>%
  dplyr::select(zipcode, puma, afact)

# Join primary PUMA to base data
base_data <- base_data %>%
  dplyr::mutate(zipcode = as.character(zipcode)) %>%
  dplyr::left_join(zip_to_puma_primary, by = "zipcode")

n_puma_from_zip <- sum(!is.na(base_data$puma))
cat(sprintf("    ✓ Matched PUMA from ZIP for %d/%d records (%.1f%%)\n",
            n_puma_from_zip, nrow(base_data),
            100 * n_puma_from_zip / nrow(base_data)))

# ==============================================================================
# SECTION 1.2: Use Imputed PUMA for Ambiguous Cases
# ==============================================================================

cat("\n[1.2] Using imputed PUMA for ambiguous ZIP-to-PUMA mappings...\n")

# Load imputed PUMA for records with multiple possible PUMAs
imputed_puma <- dbGetQuery(con, "
  SELECT
    pid,
    record_id,
    puma as puma_imputed
  FROM ne25_imputed_puma
  WHERE imputation_m = 1
")

cat(sprintf("    ✓ Loaded %d imputed PUMA records (for ambiguous cases)\n",
            nrow(imputed_puma)))

dbDisconnect(con)

# Join imputed PUMA
base_data <- base_data %>%
  dplyr::left_join(imputed_puma, by = c("pid", "record_id"))

# Use imputed PUMA if available (for ambiguous cases), otherwise use ZIP-derived PUMA
base_data <- base_data %>%
  dplyr::mutate(
    puma_final = dplyr::coalesce(puma_imputed, puma),
    puma_source = dplyr::case_when(
      !is.na(puma_imputed) ~ "imputed",
      !is.na(puma) ~ "zipcode",
      TRUE ~ "missing"
    )
  )

# Report PUMA coverage
puma_summary <- base_data %>%
  dplyr::group_by(puma_source) %>%
  dplyr::summarise(count = dplyr::n(), .groups = "drop")

cat("\n    PUMA derivation summary:\n")
for (i in 1:nrow(puma_summary)) {
  cat(sprintf("      %s: %d records\n",
              puma_summary$puma_source[i],
              puma_summary$count[i]))
}

# Replace puma with final derived value
base_data$puma <- base_data$puma_final
base_data <- base_data %>%
  dplyr::select(-puma_imputed, -puma_final, -puma_source, -afact)

n_puma_final <- sum(!is.na(base_data$puma))
cat(sprintf("\n    ✓ Final PUMA coverage: %d/%d records (%.1f%%)\n",
            n_puma_final, nrow(base_data),
            100 * n_puma_final / nrow(base_data)))

# Report missing data before imputation
cat("\n[1.1] Missing data summary (before imputation):\n")
missing_counts <- colSums(is.na(base_data))
missing_pct <- round(missing_counts / nrow(base_data) * 100, 2)
for (var in names(missing_counts)[missing_counts > 0]) {
  cat(sprintf("      %s: %d (%.1f%%)\n", var, missing_counts[var], missing_pct[var]))
}

# ==============================================================================
# SECTION 2: Prepare PUMA for Harmonization
# ==============================================================================

cat("\n[2] Preparing PUMA for harmonization...\n")

# Rename PUMA for consistency with downstream harmonization code
base_data$puma_clean <- base_data$puma

cat(sprintf("    ✓ PUMA ready for %d records\n",
            sum(!is.na(base_data$puma_clean))))

# ==============================================================================
# SECTION 3: Impute Missing Values with CART
# ==============================================================================

cat("\n[3] Imputing missing values using CART...\n")

# Prepare data for mice
# PUMA already imputed from database - exclude from MICE
# Exclude CBSA from imputation (not needed for calibration)
# Exclude identifiers
impute_data <- base_data %>%
  dplyr::select(years_old, female, raceG, educ_mom, fpl,
                phq2_total, gad2_total, child_ace_total, mmi100)

# Run mice with CART method, M=1 imputation
set.seed(20251209)  # For reproducibility

cat("    Running mice (CART, M=1, maxit=5)...\n")
imputed <- mice::mice(
  impute_data,
  m = 1,                    # Single imputation
  method = "cart",          # CART method for all variables
  maxit = 5,                # 5 iterations
  printFlag = FALSE         # Suppress iteration output
)

cat("    ✓ Imputation complete\n")

# Extract completed data
imputed_data <- mice::complete(imputed, 1)

# Add back identifiers and PUMA
imputed_data$pid <- base_data$pid
imputed_data$record_id <- base_data$record_id
imputed_data$puma_clean <- base_data$puma_clean # Use ZIP/imputed PUMA (not MICE)
imputed_data$study_id <- "ne25"
imputed_data$authenticity_weight <- 1.0  # Placeholder

# Report missing data after imputation (CBSA may still have NAs)
cat("\n[3.1] Missing data summary (after MICE imputation):\n")
missing_after <- colSums(is.na(imputed_data))
if (sum(missing_after) == 0) {
  cat("      ✓ No missing values remaining\n")
} else {
  cat("      Note: Some variables may retain missing values:\n")
  for (var in names(missing_after)[missing_after > 0]) {
    pct <- round(missing_after[var] / nrow(imputed_data) * 100, 1)
    cat(sprintf("        %s: %d (%.1f%%)\n", var, missing_after[var], pct))
  }
}

# ==============================================================================
# [3.2] Drop Records Without PUMA (Out-of-State Participants)
# ==============================================================================

cat("\n[3.2] Dropping records without PUMA (out-of-state participants)...\n")

n_puma_missing <- sum(is.na(imputed_data$puma_clean))
n_before <- nrow(imputed_data)

if (n_puma_missing > 0) {
  cat(sprintf("      Found %d records without PUMA (likely out-of-state ZIP codes)\n", n_puma_missing))

  # Filter to records with complete PUMA
  imputed_data <- imputed_data %>%
    dplyr::filter(!is.na(puma_clean))

  n_after <- nrow(imputed_data)
  cat(sprintf("      ✓ Dropped %d out-of-state records\n", n_before - n_after))
  cat(sprintf("      ✓ Retained %d Nebraska records with complete PUMA\n", n_after))
} else {
  cat(sprintf("      ✓ All %d records have complete PUMA\n", nrow(imputed_data)))
}

# Verify 100% PUMA coverage
n_puma_final <- sum(!is.na(imputed_data$puma_clean))
if (n_puma_final == nrow(imputed_data)) {
  cat(sprintf("\n      [OK] 100%% PUMA coverage: %d/%d records\n",
              n_puma_final, nrow(imputed_data)))
} else {
  stop(sprintf("ERROR: Expected 100%% PUMA coverage but got %d/%d",
               n_puma_final, nrow(imputed_data)))
}

# ==============================================================================
# SECTION 4: Harmonize to 24-Variable Structure
# ==============================================================================

cat("\n[4] Harmonizing to 24-variable structure...\n")

# Block 1: Demographics (7 variables) + PUMA (14 binary dummies) = 21 variables
cat("    Harmonizing Block 1 (demographics + PUMA)...\n")

# Harmonize demographics directly (skip CBSA/principal_city)
block1_demo <- dplyr::tibble(
  # Variable 1: male (invert female)
  male = as.integer(!imputed_data$female),

  # Variable 2: age (direct mapping)
  age = imputed_data$years_old,

  # Variables 3-5: race dummies (from raceG)
  white_nh = as.integer(imputed_data$raceG == "White, non-Hisp."),
  black = as.integer(imputed_data$raceG %in% c("Black or African American, non-Hisp.", "Black or African American, Hispanic")),
  hispanic = as.integer(grepl("Hispanic", as.character(imputed_data$raceG))),

  # Variable 6: education years (from educ_mom)
  # IMPORTANT: CART imputation in lines 73-84 produces text strings from REDCap education categories.
  # The following regex patterns MUST cover ALL variations or records with unmatched patterns get
  # listwise deletion in script 33. Pattern history:
  #   - "Less than|8th grade|9th-12th|Some High School" (added "8th grade|9th-12th" Dec 2025)
  #   - "vocational|trade|business school" (added Dec 2025, was missing ~14 records)
  # These two patterns fixed ~336 missing values (12.7% → 0% completion rate).
  # Verify: missing_check <- ne25_harmonized %>% dplyr::select(educ_years) %>%
  #         dplyr::summarise(n_missing = sum(is.na(.)))  # Should be 0
  educ_years = dplyr::case_when(
    grepl("Less than|8th grade|9th-12th|Some High School", as.character(imputed_data$educ_mom)) ~ 10,
    grepl("High School Graduate|GED", as.character(imputed_data$educ_mom)) ~ 12,
    grepl("Some College", as.character(imputed_data$educ_mom)) ~ 14,
    grepl("vocational|trade|business school", as.character(imputed_data$educ_mom)) ~ 13,
    grepl("Associate", as.character(imputed_data$educ_mom)) ~ 14,
    grepl("Bachelor", as.character(imputed_data$educ_mom)) ~ 16,
    grepl("Master", as.character(imputed_data$educ_mom)) ~ 18,
    grepl("Doctorate|Professional", as.character(imputed_data$educ_mom)) ~ 20,
    TRUE ~ NA_real_
  ),

  # Variable 7: poverty ratio (from fpl, capped at [50, 400])
  poverty_ratio = pmin(pmax(imputed_data$fpl, 50), 400)
)

# Harmonize PUMA to 14 binary dummies
block1_puma <- harmonize_puma(imputed_data$puma_clean)  # 14 variables

# Combine: demographics (1-7) + PUMA (8-21) = 21 variables
block1 <- dplyr::bind_cols(block1_demo, block1_puma)

# Block 2: Mental Health (2 variables)
cat("    Harmonizing Block 2 (mental health)...\n")

block2 <- dplyr::tibble(
  phq2_total = imputed_data$phq2_total,
  gad2_total = imputed_data$gad2_total
)

# Block 3: Child Outcome (1 variable, no ACEs)
cat("    Harmonizing Block 3 (child outcome)...\n")

block3 <- dplyr::tibble(
  excellent_health = harmonize_ne25_excellent_health(imputed_data$mmi100)
)

# Combine all blocks
harmonized <- dplyr::bind_cols(
  dplyr::select(imputed_data, pid, record_id, study_id),
  block1,
  block2,
  block3
)

cat("    ✓ Harmonization complete\n")

# ==============================================================================
# SECTION 5: Validation
# ==============================================================================

cat("\n[5] Validating harmonized data...\n")

# Check completeness
missing_harmonized <- colSums(is.na(harmonized))
if (sum(missing_harmonized) > 0) {
  cat("    ⚠ Warning: Missing values in harmonized data:\n")
  for (var in names(missing_harmonized)[missing_harmonized > 0]) {
    pct <- round(missing_harmonized[var] / nrow(harmonized) * 100, 2)
    cat(sprintf("      %s: %d (%.1f%%)\n", var, missing_harmonized[var], pct))
  }
} else {
  cat("    ✓ No missing values in harmonized data\n")
}

# Check variable ranges
cat("\n[5.1] Range validation:\n")

range_checks <- list(
  male = c(0, 1),
  age = c(0, 6),
  white_nh = c(0, 1),
  black = c(0, 1),
  hispanic = c(0, 1),
  educ_years = c(2, 20),
  poverty_ratio = c(50, 400),  # NSCH standard range
  phq2_total = c(0, 6),
  gad2_total = c(0, 6),
  excellent_health = c(0, 1)
)

range_issues <- 0
for (var in names(range_checks)) {
  if (var %in% names(harmonized)) {
    vals <- harmonized[[var]][!is.na(harmonized[[var]])]
    if (length(vals) > 0) {
      min_val <- min(vals)
      max_val <- max(vals)
      expected_min <- range_checks[[var]][1]
      expected_max <- range_checks[[var]][2]

      if (min_val < expected_min || max_val > expected_max) {
        cat(sprintf("      ⚠ %s: [%.2f, %.2f] outside expected [%d, %d]\n",
                    var, min_val, max_val, expected_min, expected_max))
        range_issues <- range_issues + 1
      }
    }
  }
}

if (range_issues == 0) {
  cat("    ✓ All variables within expected ranges\n")
}

# Check PUMA dummies
cat("\n[5.2] PUMA consistency check:\n")
puma_cols <- grep("^puma_", names(harmonized), value = TRUE)
if (length(puma_cols) > 0) {
  # Each row should have at most one PUMA = 1 (or all NA)
  puma_sums <- rowSums(harmonized[, puma_cols], na.rm = TRUE)
  invalid_puma <- sum(puma_sums > 1, na.rm = TRUE)
  if (invalid_puma > 0) {
    cat(sprintf("      ⚠ %d records with multiple PUMA = 1\n", invalid_puma))
  } else {
    cat("      ✓ PUMA dummies are mutually exclusive (0 or 1 per record)\n")
  }

  # Check range [0, 1]
  puma_range_invalid <- 0
  for (col in puma_cols) {
    vals <- harmonized[[col]][!is.na(harmonized[[col]])]
    if (any(vals < 0 | vals > 1)) {
      puma_range_invalid <- puma_range_invalid + 1
    }
  }
  if (puma_range_invalid == 0) {
    cat("      ✓ All PUMA variables in range [0, 1]\n")
  }
} else {
  cat("      ⚠ No PUMA variables found\n")
}

# Check dimensions
cat(sprintf("\n[5.3] Final dimensions: %d rows × %d columns\n",
            nrow(harmonized), ncol(harmonized)))

puma_codes <- c(100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904)
puma_names <- sprintf("puma_%d", puma_codes)
expected_cols <- c("pid", "record_id", "study_id",
                   "male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio",
                   puma_names,
                   "phq2_total", "gad2_total",
                   "excellent_health")

if (length(setdiff(expected_cols, names(harmonized))) == 0) {
  cat("    ✓ All expected columns present\n")
} else {
  cat("    ⚠ Missing columns:\n")
  print(setdiff(expected_cols, names(harmonized)))
}

# ==============================================================================
# SECTION 6: Save Output
# ==============================================================================

cat("\n[6] Saving harmonized dataset...\n")

output_path <- file.path(output_dir, "ne25_harmonized_m1.feather")
arrow::write_feather(harmonized, output_path)

file_size_mb <- file.size(output_path) / (1024^2)
cat(sprintf("    ✓ Saved: %s (%.1f MB)\n", output_path, file_size_mb))

# ==============================================================================
# SECTION 7: Final Summary
# ==============================================================================

cat("\n========================================\n")
cat("✓ NE25 Harmonization Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat(sprintf("  Sample size: %d\n", nrow(harmonized)))
cat(sprintf("  Total variables: %d\n", ncol(harmonized)))
cat("  Structure:\n")
cat("    - 3 identifiers (pid, record_id, study_id)\n")
cat("    - 21 Block 1 (7 demographics + 14 PUMA dummies)\n")
cat("    - 2 Block 2 (phq2_total, gad2_total)\n")
cat("    - 1 Block 3 (excellent_health)\n")
cat(sprintf("  Imputation method: CART (M=1)\n"))
cat(sprintf("  Output: %s\n", output_path))
cat("\nReady for Phase 2: KL divergence weighting (script 33_compute_kl_weights_ne25.R)\n")
