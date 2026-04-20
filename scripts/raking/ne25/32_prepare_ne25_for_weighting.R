# ==============================================================================
# Script: 32_prepare_ne25_for_weighting.R
# Purpose: Produce M=5 harmonized NE25 datasets matching the unified-moments
#          24-variable structure, one per imputation, for KL-divergence raking.
#
# Overview:
#     For each imputation m in 1..M:
#       1. Call get_completed_dataset(m, variables = ...) from R/imputation/helpers.R
#          to merge the production pipeline's imputed values onto the observed
#          base (ne25_transformed). Observed values take precedence; imputed
#          values fill NAs.
#       2. Filter to meets_inclusion = TRUE.
#       3. Compute derived variables:
#            phq2_total = phq2_interest + phq2_depressed
#            gad2_total = gad2_nervous + gad2_worry
#            fpl        = income / get_poverty_threshold(consent_date, family_size) * 100
#       4. Drop out-of-state records (puma is NA after completion).
#       5. Run a per-m lightweight fallback mice pass on residual NAs in
#          years_old / mmi100 (production pipeline doesn't impute these; <1%
#          missing in practice).
#       6. Harmonize to the 24-variable structure (7 demographics + 14 PUMA
#          dummies + 2 mental health + 1 child outcome).
#       7. Validate range and consistency.
#       8. Save ne25_harmonized_m{m}.feather.
#     After the loop, check that all M feathers differ numerically (distinctness
#     across imputations).
#
# Design decisions (locked in April 2026; see plan file and
# docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd Section 5.1):
#   - Option B (consume production pipeline): eliminates the in-script MICE
#     that previously ran in this script, so raking weights are fit against
#     the SAME imputed values that downstream MI analysis uses. This closes
#     a latent consistency bug.
#   - poverty_ratio derivation (Q1): use the platform-canonical formula
#     income / federal_poverty_threshold(family_size, consent_date). No
#     second definition of poverty_ratio introduced.
#
# Outputs:
#   - data/raking/ne25/ne25_harmonized/ne25_harmonized_m{1..M}.feather
#   - Each: N_in_state rows (typically ~2,645) by 27 columns
#           (pid, record_id, study_id + 24 harmonized variables)
#
# Dependencies:
#   - R/imputation/helpers.R   :: get_completed_dataset()
#   - R/imputation/config.R    :: get_n_imputations()
#   - R/utils/poverty_utils.R  :: get_poverty_threshold()
#   - scripts/raking/ne25/utils/harmonize_puma.R
#   - scripts/raking/ne25/utils/harmonize_ne25_demographics.R
#   - scripts/raking/ne25/utils/harmonize_ne25_outcomes.R
#   - DuckDB tables: ne25_transformed, ne25_imputed_*
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup
# ==============================================================================

library(duckdb)
library(dplyr)
library(arrow)
library(mice)        # for per-m fallback on residual years_old / mmi100

source("scripts/raking/ne25/utils/harmonize_puma.R")
source("scripts/raking/ne25/utils/harmonize_ne25_demographics.R")
source("scripts/raking/ne25/utils/harmonize_ne25_outcomes.R")
source("R/imputation/helpers.R")
source("R/imputation/config.R")
source("R/utils/poverty_utils.R")
source("R/utils/safe_joins.R")  # required by get_poverty_threshold()

output_dir <- "data/raking/ne25/ne25_harmonized"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

cat("========================================\n")
cat("Phase 1: Prepare NE25 for KL Weighting (M imputations)\n")
cat("========================================\n\n")

M <- get_n_imputations()
cat(sprintf("Number of imputations (from config): M = %d\n\n", M))

# Imputed variables to request from the production pipeline. These are the
# ones the imputation pipeline produces tables for; we request only what's
# needed for the 24-variable harmonization.
imputed_vars <- c(
  "puma",
  "female", "raceG", "educ_mom",
  "income", "family_size",
  "phq2_interest", "phq2_depressed",
  "gad2_nervous", "gad2_worry",
  "child_ace_total"
)

# ==============================================================================
# SECTION 1: Per-Imputation Loop
# ==============================================================================

harmonized_list <- vector("list", M)

for (m in seq_len(M)) {
  cat(sprintf("\n----------------------------------------\n"))
  cat(sprintf("  Imputation m = %d of %d\n", m, M))
  cat(sprintf("----------------------------------------\n"))

  # ----------------------------------------------------------------------------
  # 1a: Fetch completed dataset from production imputation pipeline
  # ----------------------------------------------------------------------------
  cat("[1a] get_completed_dataset() ... ")
  completed <- get_completed_dataset(
    imputation_m = m,
    variables = imputed_vars,
    base_table = "ne25_transformed",
    study_id = "ne25",
    include_observed = TRUE
  )
  cat(sprintf("loaded %d rows x %d cols\n", nrow(completed), ncol(completed)))

  # Coerce imputed columns to atomic vectors (reticulate round-trip can leave
  # some of them as list-columns which break downstream arithmetic / factor
  # coercion). Numeric-looking vars become numeric; the rest become character.
  numeric_imputed <- c("income", "family_size",
                       "phq2_interest", "phq2_depressed",
                       "gad2_nervous", "gad2_worry",
                       "child_ace_total")
  for (v in imputed_vars) {
    if (v %in% names(completed) && is.list(completed[[v]])) {
      completed[[v]] <- unlist(completed[[v]], use.names = FALSE)
    }
    if (v %in% numeric_imputed && v %in% names(completed)) {
      completed[[v]] <- as.numeric(completed[[v]])
    }
  }
  # female is Boolean/integer in ne25_transformed; coerce safely
  if ("female" %in% names(completed)) {
    completed$female <- as.integer(as.logical(completed$female))
  }

  # ----------------------------------------------------------------------------
  # 1b: Filter to meets_inclusion = TRUE (pre-Step-6.10; out-of-state filtered
  # further down by puma NA)
  # ----------------------------------------------------------------------------
  completed <- completed %>% dplyr::filter(meets_inclusion == TRUE)
  cat(sprintf("[1b] filtered to meets_inclusion=TRUE: %d rows\n", nrow(completed)))

  # ----------------------------------------------------------------------------
  # 1c: Compute derived variables (phq2_total, gad2_total, fpl)
  # ----------------------------------------------------------------------------
  # Mental-health composites
  completed$phq2_total <- completed$phq2_interest + completed$phq2_depressed
  completed$gad2_total <- completed$gad2_nervous + completed$gad2_worry

  # Poverty ratio from imputed income and family_size
  # Use consent_date for year-appropriate poverty threshold; fall back to 2025
  # if consent_date is NA (very rare)
  poverty_dates <- as.Date(completed$consent_date)
  if (any(is.na(poverty_dates))) {
    poverty_dates[is.na(poverty_dates)] <- as.Date("2025-01-01")
  }
  thresholds <- get_poverty_threshold(poverty_dates, completed$family_size)
  completed$fpl <- (completed$income / thresholds) * 100

  cat(sprintf("[1c] derived: phq2_total, gad2_total, fpl (from imputed income/family_size)\n"))

  # ----------------------------------------------------------------------------
  # 1d: Drop out-of-state records (puma is NA even after imputation for ZIPs
  # not in the Nebraska ZCTA->PUMA crosswalk)
  # ----------------------------------------------------------------------------
  n_before <- nrow(completed)
  completed <- completed %>% dplyr::filter(!is.na(puma))
  n_after <- nrow(completed)
  cat(sprintf("[1d] dropped %d out-of-state records; retained %d\n",
              n_before - n_after, n_after))

  # ----------------------------------------------------------------------------
  # 1e: Fallback mice for residual NAs across all harmonization inputs.
  # Most NAs are resolved by get_completed_dataset (which merges the
  # production imputation pipeline's M=5 imputed values). A small number of
  # records remain NA because either the pipeline didn't impute them or
  # variables like years_old / mmi100 aren't produced by the pipeline at all.
  # Residuals should be <5% per variable; if larger, something is wrong.
  # ----------------------------------------------------------------------------
  fallback_vars <- c("years_old", "mmi100", "female", "raceG",
                     "educ_mom", "fpl", "phq2_total", "gad2_total",
                     "child_ace_total")
  na_rates <- vapply(fallback_vars, function(v) mean(is.na(completed[[v]])),
                     numeric(1))
  if (any(na_rates > 0.05)) {
    offenders <- names(na_rates)[na_rates > 0.05]
    stop(sprintf(
      "Unexpected residual missingness > 5%% in: %s. Investigate.",
      paste(offenders, collapse = ", ")
    ))
  }
  if (any(na_rates > 0)) {
    # Assemble mice input. Coerce text vars to factor so CART handles them.
    fallback_data <- data.frame(
      years_old       = as.numeric(completed$years_old),
      mmi100          = as.numeric(completed$mmi100),
      female          = as.factor(completed$female),
      raceG           = as.factor(as.character(completed$raceG)),
      educ_mom        = as.factor(as.character(completed$educ_mom)),
      fpl             = as.numeric(completed$fpl),
      phq2_total      = as.numeric(completed$phq2_total),
      gad2_total      = as.numeric(completed$gad2_total),
      child_ace_total = as.numeric(completed$child_ace_total),
      stringsAsFactors = FALSE
    )
    fallback_impute <- mice::mice(
      fallback_data,
      m = 1,
      method = "cart",
      maxit = 5,
      seed = 20251209L + m,
      printFlag = FALSE
    )
    filled <- mice::complete(fallback_impute, 1)
    completed$years_old       <- filled$years_old
    completed$mmi100          <- filled$mmi100
    completed$female          <- as.integer(as.character(filled$female))
    completed$raceG           <- as.character(filled$raceG)
    completed$educ_mom        <- as.character(filled$educ_mom)
    completed$fpl             <- filled$fpl
    completed$phq2_total      <- filled$phq2_total
    completed$gad2_total      <- filled$gad2_total
    completed$child_ace_total <- filled$child_ace_total
    filled_counts <- round(na_rates * n_after)
    filled_nonzero <- filled_counts[filled_counts > 0]
    cat(sprintf("[1e] fallback mice filled %d NA(s) total across: %s\n",
                sum(filled_nonzero),
                paste(names(filled_nonzero), "=", filled_nonzero, collapse = ", ")))
  } else {
    cat("[1e] no residual NAs in harmonization inputs\n")
  }

  # ----------------------------------------------------------------------------
  # 1f: Harmonize to 24-variable structure
  # ----------------------------------------------------------------------------
  completed$study_id <- "ne25"

  block1_demo <- dplyr::tibble(
    male = 1L - as.integer(completed$female),
    age  = completed$years_old,
    white_nh = as.integer(completed$raceG == "White, non-Hisp."),
    black    = as.integer(completed$raceG %in% c(
      "Black or African American, non-Hisp.",
      "Black or African American, Hispanic")),
    hispanic = as.integer(grepl("Hispanic", as.character(completed$raceG))),
    # Education years — unchanged regex mapping from prior version. Keep
    # in sync if educ_mom categories change upstream.
    educ_years = dplyr::case_when(
      grepl("Less than|8th grade|9th-12th|Some High School",
            as.character(completed$educ_mom)) ~ 10,
      grepl("High School Graduate|GED", as.character(completed$educ_mom)) ~ 12,
      grepl("Some College", as.character(completed$educ_mom)) ~ 14,
      grepl("vocational|trade|business school",
            as.character(completed$educ_mom)) ~ 13,
      grepl("Associate", as.character(completed$educ_mom)) ~ 14,
      grepl("Bachelor",  as.character(completed$educ_mom)) ~ 16,
      grepl("Master",    as.character(completed$educ_mom)) ~ 18,
      grepl("Doctorate|Professional",
            as.character(completed$educ_mom)) ~ 20,
      TRUE ~ NA_real_
    ),
    # Poverty ratio capped to calibration range [50, 400]
    poverty_ratio = pmin(pmax(completed$fpl, 50), 400)
  )

  block1_puma <- harmonize_puma(completed$puma)   # 14 binary dummies

  block1 <- dplyr::bind_cols(block1_demo, block1_puma)

  block2 <- dplyr::tibble(
    phq2_total = completed$phq2_total,
    gad2_total = completed$gad2_total
  )

  block3 <- dplyr::tibble(
    excellent_health = harmonize_ne25_excellent_health(completed$mmi100)
  )

  harmonized <- dplyr::bind_cols(
    dplyr::select(completed, pid, record_id, study_id),
    block1, block2, block3
  )

  # ----------------------------------------------------------------------------
  # 1g: Validation (same checks as prior version)
  # ----------------------------------------------------------------------------
  missing_counts <- colSums(is.na(harmonized))
  if (sum(missing_counts) > 0) {
    cat("[1g] WARNING: missing values in harmonized output:\n")
    for (var in names(missing_counts)[missing_counts > 0]) {
      cat(sprintf("      %s: %d\n", var, missing_counts[var]))
    }
  }

  range_checks <- list(
    male = c(0, 1), age = c(0, 6),
    white_nh = c(0, 1), black = c(0, 1), hispanic = c(0, 1),
    educ_years = c(2, 20), poverty_ratio = c(50, 400),
    phq2_total = c(0, 6), gad2_total = c(0, 6),
    excellent_health = c(0, 1)
  )
  for (v in names(range_checks)) {
    vals <- harmonized[[v]][!is.na(harmonized[[v]])]
    if (length(vals) > 0) {
      if (min(vals) < range_checks[[v]][1] || max(vals) > range_checks[[v]][2]) {
        cat(sprintf("      [WARN] %s: [%.2f, %.2f] outside [%d, %d]\n",
                    v, min(vals), max(vals),
                    range_checks[[v]][1], range_checks[[v]][2]))
      }
    }
  }

  puma_cols <- grep("^puma_", names(harmonized), value = TRUE)
  puma_sums <- rowSums(harmonized[, puma_cols], na.rm = TRUE)
  if (any(puma_sums > 1, na.rm = TRUE)) {
    cat(sprintf("      [WARN] %d records with multiple PUMA = 1\n",
                sum(puma_sums > 1, na.rm = TRUE)))
  }

  # ----------------------------------------------------------------------------
  # 1h: Save
  # ----------------------------------------------------------------------------
  output_path <- file.path(output_dir,
                           sprintf("ne25_harmonized_m%d.feather", m))
  arrow::write_feather(harmonized, output_path)
  size_mb <- file.size(output_path) / (1024^2)
  cat(sprintf("[1h] saved: %s (%.2f MB, %d rows x %d cols)\n",
              output_path, size_mb,
              nrow(harmonized), ncol(harmonized)))

  harmonized_list[[m]] <- harmonized
}

# ==============================================================================
# SECTION 2: Cross-Imputation Distinctness Check
# ==============================================================================

cat("\n========================================\n")
cat("Cross-imputation distinctness check\n")
cat("========================================\n\n")

# All M feathers should have identical row counts but different values.
row_counts <- vapply(harmonized_list, nrow, integer(1))
if (length(unique(row_counts)) > 1) {
  stop(sprintf("Row counts differ across imputations: %s",
               paste(row_counts, collapse = ", ")))
}
cat(sprintf("[OK] All %d imputations have identical row counts: %d\n",
            M, row_counts[1]))

# Between-m variance in a few variables that SHOULD differ across imputations
check_vars <- c("phq2_total", "gad2_total", "educ_years", "poverty_ratio")
for (v in check_vars) {
  per_m_means <- vapply(harmonized_list, function(d) mean(d[[v]], na.rm = TRUE),
                        numeric(1))
  between_m_var <- stats::var(per_m_means)
  cat(sprintf("[CHECK] %s: between-m SD of the mean = %.6f ", v,
              sqrt(between_m_var)))
  if (between_m_var <= 1e-12) {
    cat("[WARN] (zero or near-zero — imputations may be identical for this var)\n")
  } else {
    cat("[OK]\n")
  }
}

# SHA256 of numeric columns per imputation — all M hashes must differ
if (requireNamespace("digest", quietly = TRUE)) {
  hashes <- vapply(harmonized_list, function(d) {
    numeric_d <- d %>% dplyr::select(dplyr::where(is.numeric))
    digest::digest(numeric_d, algo = "sha256")
  }, character(1))
  if (length(unique(hashes)) == M) {
    cat(sprintf("[OK] All %d harmonized datasets are numerically distinct (SHA256)\n", M))
  } else {
    cat(sprintf("[WARN] Only %d/%d distinct SHA256 hashes across imputations\n",
                length(unique(hashes)), M))
  }
}

cat("\n========================================\n")
cat("NE25 Multi-Imputation Harmonization Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat(sprintf("  Imputations:   %d\n", M))
cat(sprintf("  Per-m rows:    %d\n", row_counts[1]))
cat(sprintf("  Output dir:    %s\n", output_dir))
cat("\nReady for Phase 2: 33_compute_kl_divergence_weights.R\n")
