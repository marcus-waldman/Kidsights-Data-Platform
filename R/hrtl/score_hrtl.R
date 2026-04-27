################################################################################
# HRTL (Healthy & Ready to Learn) Scoring -- multi-study, function-based
################################################################################
# Replaces the four-script pipeline at scripts/hrtl/0[1-4]_*.R with a single
# parameterized function. Phases (extract -> Rasch -> impute -> threshold-score)
# run in-memory; no intermediate RDS files. The Motor Development domain is
# masked automatically when its non-NA rate in the HRTL-eligible (3-5 yr) band
# falls below `min_motor_coverage` (default 0.50).
#
# Author: Kidsights Data Platform
# Created: 2026-04-27 (PR 2 of MN26 scoring integration)
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(readxl)
  library(mirt)
})

#' Score HRTL for a study
#'
#' Multi-study HRTL scorer. Replaces the four-script pipeline at
#' scripts/hrtl/0[1-4]_*.R. Returns domain-level and overall classifications
#' without writing to disk; orchestration is responsible for persistence via
#' [save_hrtl_scores_to_db()].
#'
#' @param data Data frame with study-transformed data; must contain `key_vars`,
#'   `years_old`, `meets_inclusion`, plus the CAHMI item columns and optional
#'   covariate columns.
#' @param study_id Codebook lexicon key (default `"ne25"`). Drives item lookup
#'   via `codebook$items[[*]]$lexicons[[study_id]]`.
#' @param key_vars Join-key columns; default `c("pid","record_id")`. MN26
#'   callers pass `c("pid","record_id","child_num")`.
#' @param codebook_path Path to codebook.json.
#' @param thresholds_path Path to HRTL-2022-Scoring-Thresholds.xlsx.
#' @param itemdict_path Path to itemdict22.csv.
#' @param covariate_cols Optional covariate columns for the Rasch model
#'   (default `c("kidsights_2022","general_gsed_pf_2022")`). Columns missing
#'   from `data` are dropped silently. Pass `NULL` or `character(0)` to fit
#'   without covariates.
#' @param min_motor_coverage Coverage threshold for the Motor Development
#'   domain (default `0.50`). If the mean non-NA rate across Motor items in
#'   the HRTL-eligible (3-5 yr) band falls below this, Motor classification
#'   is masked to NA and overall HRTL becomes NA. Set to 0 to disable masking.
#' @param verbose Logical, print progress messages.
#'
#' @return List with elements:
#'   * `domain_scores` -- data frame keyed by `(key_vars, domain)` with
#'     `avg_code`, `classification`, `years_old`.
#'   * `overall` -- data frame keyed by `key_vars` with `n_on_track`,
#'     `n_needs_support`, `hrtl`.
#'   * `motor_coverage` -- numeric mean Motor coverage in eligible band.
#'   * `motor_masked` -- logical, whether Motor was masked.
#'
#' @export
score_hrtl <- function(data,
                       study_id = "ne25",
                       key_vars = c("pid", "record_id"),
                       codebook_path = "codebook/data/codebook.json",
                       thresholds_path = "data/reference/hrtl/HRTL-2022-Scoring-Thresholds.xlsx",
                       itemdict_path = "data/reference/hrtl/itemdict22.csv",
                       covariate_cols = c("kidsights_2022", "general_gsed_pf_2022"),
                       min_motor_coverage = 0.50,
                       verbose = TRUE) {

  if (verbose) {
    message(sprintf("=== score_hrtl(study_id=%s, key_vars=%s) ===",
                    study_id, paste(key_vars, collapse = "+")))
  }

  required_cols <- c(key_vars, "years_old", "meets_inclusion")
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
  }
  if (!file.exists(codebook_path)) stop(sprintf("Codebook not found: %s", codebook_path))
  if (!file.exists(thresholds_path)) stop(sprintf("Thresholds not found: %s", thresholds_path))
  if (!file.exists(itemdict_path)) stop(sprintf("Item dictionary not found: %s", itemdict_path))

  # Drop covariates not present in data (cross-study graceful degradation)
  if (is.null(covariate_cols)) covariate_cols <- character(0)
  available_cov <- intersect(covariate_cols, names(data))
  missing_cov <- setdiff(covariate_cols, names(data))
  if (length(missing_cov) > 0 && verbose) {
    message(sprintf("  [INFO] Covariates absent from data (will fit without): %s",
                    paste(missing_cov, collapse = ", ")))
  }

  # ============================================================================
  # PHASE 1: Build study-to-CAHMI mappings and extract per-domain datasets
  # ============================================================================
  if (verbose) message("\n--- Phase 1: Extract domain datasets ---")

  codebook    <- jsonlite::fromJSON(codebook_path)
  thresholds  <- readxl::read_excel(thresholds_path)
  itemdict    <- read.csv(itemdict_path, stringsAsFactors = FALSE)

  # Build study_id -> CAHMI22 mapping (handle list-valued cahmi22/cahmi21 aliases)
  study_cahmi_map <- data.frame(
    study = character(0), cahmi22 = character(0), stringsAsFactors = FALSE
  )
  for (item_key in names(codebook$items)) {
    item_data <- codebook$items[[item_key]]
    if (!is.list(item_data) || is.null(item_data$lexicons)) next
    study_var   <- item_data$lexicons[[study_id]]
    cahmi22_var <- item_data$lexicons$cahmi22
    cahmi21_var <- item_data$lexicons$cahmi21
    if (is.null(study_var) || is.null(cahmi22_var)) next

    add_alias <- function(alias) {
      study_cahmi_map <<- rbind(study_cahmi_map,
                                data.frame(study = tolower(study_var),
                                           cahmi22 = alias,
                                           stringsAsFactors = FALSE))
    }
    if (length(cahmi22_var) > 1) {
      for (a in cahmi22_var) add_alias(a)
    } else {
      add_alias(cahmi22_var)
    }
    if (!is.null(cahmi21_var)) {
      if (length(cahmi21_var) > 1) {
        for (a in cahmi21_var) add_alias(a)
      } else {
        add_alias(cahmi21_var)
      }
    }
  }
  if (verbose) {
    message(sprintf("  Found %d %s -> CAHMI22 mappings", nrow(study_cahmi_map), study_id))
  }

  # Filter to eligible cohort (HRTL-relevant population includes 0-5; thresholds
  # apply only to 3-5 in Phase 4. Rasch fit benefits from full age span.)
  data_elig <- data %>% dplyr::filter(meets_inclusion == TRUE)
  if (verbose) message(sprintf("  HRTL-relevant (meets_inclusion=TRUE): %d", nrow(data_elig)))

  # Derive DailyAct_22 (Health domain) from cqr014x + nom044 if present
  if ("cqr014x" %in% names(data_elig)) {
    data_elig <- data_elig %>%
      dplyr::mutate(
        dailyact_22 = dplyr::case_when(
          is.na(cqr014x) ~ NA_real_,
          cqr014x %in% c(0, 1) ~ 0,
          cqr014x == 2 ~ 1,
          cqr014x == 3 ~ 2,
          cqr014x == 4 ~ 3,
          TRUE ~ NA_real_
        )
      )
    if ("nom044" %in% names(data_elig)) {
      data_elig <- data_elig %>%
        dplyr::mutate(dailyact_22 = dplyr::if_else(
          !is.na(nom044) & nom044 == 2, 3, dailyact_22
        ))
    }
    if (verbose) {
      n_da <- sum(!is.na(data_elig$dailyact_22))
      message(sprintf("  DailyAct_22 derived for %d / %d (%.1f%%)",
                      n_da, nrow(data_elig), 100 * n_da / nrow(data_elig)))
    }
  } else if (verbose) {
    message("  [INFO] cqr014x absent; DailyAct_22 will not be derived")
  }

  # Build per-domain datasets
  domains <- unique(itemdict$domain_2022)
  domains <- domains[!is.na(domains)]
  domain_datasets <- list()

  for (domain in domains) {
    domain_cahmi <- itemdict %>%
      dplyr::filter(domain_2022 == domain) %>%
      dplyr::pull(lex_cahmi22)
    domain_study_vars <- study_cahmi_map %>%
      dplyr::filter(toupper(cahmi22) %in% toupper(domain_cahmi)) %>%
      dplyr::pull(study) %>%
      unique()
    available <- intersect(tolower(domain_study_vars), tolower(names(data_elig)))

    if (length(available) == 0) {
      if (verbose) message(sprintf("  Domain '%s': no items available -- skipping", domain))
      next
    }

    aux_in_data <- intersect(available_cov, names(data_elig))

    # Special case: Health domain folds in derived DailyAct_22 BEFORE the
    # has_any filter, so children with only DailyAct_22 signal are retained.
    add_dailyact <- (domain == "Health" && "dailyact_22" %in% names(data_elig))
    select_cols <- c(key_vars, "years_old", aux_in_data, available,
                     if (add_dailyact) "dailyact_22" else character(0))
    domain_data <- data_elig %>% dplyr::select(dplyr::all_of(select_cols))
    if (add_dailyact) {
      available <- c(available, "dailyact_22")
    }

    # Drop rows that are NA on every domain item (no signal at all)
    has_any <- rowSums(!is.na(domain_data[, available, drop = FALSE])) > 0
    domain_data <- domain_data[has_any, , drop = FALSE]

    domain_datasets[[domain]] <- list(
      data = domain_data,
      variables = available,
      cahmi_codes = domain_cahmi,
      aux_cols = aux_in_data
    )
    if (verbose) {
      message(sprintf("  Domain '%s': %d items, %d children",
                      domain, length(available), nrow(domain_data)))
    }
  }

  # ============================================================================
  # PHASE 2: Fit 1PL graded Rasch models with optional covariates
  # ============================================================================
  if (verbose) message("\n--- Phase 2: Fit Rasch models ---")

  rasch_models <- list()

  for (domain in names(domain_datasets)) {
    dom <- domain_datasets[[domain]]
    item_matrix <- as.matrix(dom$data[, dom$variables, drop = FALSE])

    if (verbose) {
      pct_miss <- 100 * sum(is.na(item_matrix)) / length(item_matrix)
      message(sprintf("  %s: %d children x %d items (%.2f%% missing)",
                      domain, nrow(item_matrix), ncol(item_matrix), pct_miss))
    }

    fit_no_cov <- function() {
      pars   <- mirt::mirt(item_matrix, 1, itemtype = "graded",
                           pars = "values", verbose = FALSE)
      slopes <- pars[pars$name == "a1", "parnum"]
      mirt::mirt(
        data      = item_matrix,
        model     = 1,
        itemtype  = "graded",
        constrain = list(slopes),
        verbose   = FALSE
      )
    }
    fit_with_cov <- function() {
      pars   <- mirt::mirt(item_matrix, 1, itemtype = "graded",
                           pars = "values", verbose = FALSE)
      slopes <- pars[pars$name == "a1", "parnum"]
      cov_df <- dom$data %>%
        dplyr::select(dplyr::all_of(dom$aux_cols)) %>%
        dplyr::mutate(dplyr::across(dplyr::everything(), function(x) as.numeric(scale(x))))
      formula_str <- paste("~", paste(dom$aux_cols, collapse = " + "))
      mirt::mirt(
        data      = item_matrix,
        model     = 1,
        itemtype  = "graded",
        covdata   = cov_df,
        formula   = stats::as.formula(formula_str),
        constrain = list(slopes),
        verbose   = FALSE
      )
    }

    fit <- NULL
    used_cov <- FALSE
    if (length(dom$aux_cols) > 0) {
      fit <- tryCatch(fit_with_cov(), error = function(e) {
        message(sprintf("  [WARN] Rasch fit with covariates failed for %s: %s",
                        domain, e$message))
        message("           Falling back to no-covariate fit...")
        NULL
      })
      if (!is.null(fit)) used_cov <- TRUE
    }
    if (is.null(fit)) {
      fit <- tryCatch(fit_no_cov(), error = function(e) {
        message(sprintf("  [WARN] Rasch fit failed for %s: %s", domain, e$message))
        NULL
      })
    }

    if (!is.null(fit)) {
      rasch_models[[domain]] <- fit
      domain_datasets[[domain]]$used_cov <- used_cov  # track for Phase 3
    }
  }

  # ============================================================================
  # PHASE 3: Impute missing item values via EAP theta
  # ============================================================================
  if (verbose) message("\n--- Phase 3: Impute missing values ---")

  imputed_items <- list()

  # Domains with failed Rasch fits are dropped entirely. Falling back to raw
  # items for threshold scoring would be misleading: a single Needs-Support
  # response on a sparse domain (e.g., MN26 Health with 67% missing) drags
  # the whole domain to "Needs Support" and falsely tanks overall HRTL. A
  # missing domain is interpretable; a half-scored domain is not.

  for (domain in names(rasch_models)) {
    dom <- domain_datasets[[domain]]
    fit <- rasch_models[[domain]]
    item_matrix <- as.matrix(dom$data[, dom$variables, drop = FALSE])

    imp <- tryCatch({
      cov_df <- if (isTRUE(dom$used_cov) && length(dom$aux_cols) > 0) {
        dom$data %>% dplyr::select(dplyr::all_of(dom$aux_cols))
      } else NULL

      theta_eap <- if (!is.null(cov_df)) {
        mirt::fscores(fit, method = "EAP", full.scores = TRUE,
                      full.scores.SE = FALSE, covdata = cov_df)
      } else {
        mirt::fscores(fit, method = "EAP", full.scores = TRUE,
                      full.scores.SE = FALSE)
      }
      if (is.vector(theta_eap)) theta_eap <- matrix(theta_eap, ncol = 1)
      if (ncol(theta_eap) > 1)  theta_eap <- matrix(theta_eap[, 1], ncol = 1)

      filled <- mirt::imputeMissing(fit, Theta = theta_eap)
      colnames(filled) <- dom$variables
      filled
    }, error = function(e) {
      message(sprintf("  [WARN] Imputation failed for %s; using raw items: %s",
                      domain, e$message))
      item_matrix
    })

    imputed_items[[domain]] <- imp
    if (verbose) {
      n_miss <- sum(is.na(imp))
      message(sprintf("  %s: %d cells remaining missing post-imputation", domain, n_miss))
    }
  }

  # ============================================================================
  # PHASE 4a: Compute Motor coverage on ORIGINAL (pre-imputation) data
  # ============================================================================
  motor_coverage <- NA_real_
  motor_masked   <- FALSE
  motor_label    <- "Motor Development"

  if (motor_label %in% names(domain_datasets)) {
    motor_dom <- domain_datasets[[motor_label]]
    eligible_idx <- floor(motor_dom$data$years_old) %in% c(3, 4, 5)
    motor_orig <- motor_dom$data[eligible_idx, motor_dom$variables, drop = FALSE]
    if (nrow(motor_orig) > 0) {
      per_item <- vapply(motor_dom$variables,
                         function(v) mean(!is.na(motor_orig[[v]])),
                         numeric(1))
      motor_coverage <- mean(per_item)
    }
    motor_masked <- !is.na(motor_coverage) && motor_coverage < min_motor_coverage

    if (verbose) {
      message(sprintf("\n--- Phase 4a: Motor coverage gate ---"))
      message(sprintf("  Motor items (3-5 yr eligible band, n=%d):", sum(eligible_idx)))
      if (length(motor_dom$variables) > 0 && nrow(motor_orig) > 0) {
        for (v in motor_dom$variables) {
          message(sprintf("    %-12s  non-NA: %.1f%%", v,
                          100 * mean(!is.na(motor_orig[[v]]))))
        }
      }
      message(sprintf("  Mean Motor coverage: %.1f%% (threshold: %.0f%%)",
                      100 * motor_coverage, 100 * min_motor_coverage))
      if (motor_masked) {
        message("  -> Motor classification will be MASKED (coverage below threshold)")
      } else {
        message("  -> Motor classification will be SCORED (coverage meets threshold)")
      }
    }
  }

  # ============================================================================
  # PHASE 4b: Apply CAHMI age-specific thresholds, classify, aggregate
  # ============================================================================
  if (verbose) message("\n--- Phase 4b: Score with CAHMI thresholds ---")

  domain_score_frames <- list()

  for (domain in names(imputed_items)) {
    dom <- domain_datasets[[domain]]
    imp_df <- as.data.frame(imputed_items[[domain]])
    colnames(imp_df) <- dom$variables

    # CAHMI lookup for this domain
    study_to_cahmi <- study_cahmi_map %>%
      dplyr::filter(study %in% dom$variables) %>%
      dplyr::select(study, cahmi22) %>%
      dplyr::distinct()
    if ("dailyact_22" %in% dom$variables) {
      study_to_cahmi <- rbind(
        study_to_cahmi,
        data.frame(study = "dailyact_22", cahmi22 = "DailyAct", stringsAsFactors = FALSE)
      )
    }

    # Restrict to HRTL-eligible (ages 3-5)
    age_floor <- floor(dom$data$years_old)
    elig_idx <- age_floor %in% c(3, 4, 5)
    elig_df <- dom$data[elig_idx, , drop = FALSE]
    elig_imp <- imp_df[elig_idx, , drop = FALSE]

    if (nrow(elig_df) == 0) {
      if (verbose) message(sprintf("  %s: 0 HRTL-eligible children -- skipping", domain))
      next
    }

    coded_df <- elig_df %>%
      dplyr::select(dplyr::all_of(c(key_vars, "years_old")))

    for (study_var in dom$variables) {
      cahmi_row <- study_to_cahmi %>% dplyr::filter(study == study_var)
      if (nrow(cahmi_row) == 0) next
      cahmi_code <- cahmi_row$cahmi22[1]

      item_thr <- thresholds %>%
        dplyr::mutate(var_clean = gsub("_", "", toupper(gsub("_\\d+$", "", var_cahmi)))) %>%
        dplyr::filter(var_clean == gsub("_", "", toupper(cahmi_code))) %>%
        dplyr::select(-var_clean)
      if (nrow(item_thr) == 0) next

      values <- elig_imp[[study_var]]
      coded  <- rep(NA_real_, length(values))

      for (age in unique(item_thr$SC_AGE_YEARS)) {
        # Exclude NA values from the threshold-coding mask. With imputation
        # (Rasch fit succeeded) every value is non-NA so this is a no-op; with
        # raw-items fallback (fit failed) it prevents kids without a response
        # from being silently coded as Needs Support.
        mask <- floor(elig_df$years_old) == age & !is.na(values)
        if (!any(mask, na.rm = TRUE)) next
        thr <- item_thr %>% dplyr::filter(SC_AGE_YEARS == age)
        if (nrow(thr) == 0) next
        on_track <- thr$on_track[1]
        emerging <- thr$emerging[1]

        coded[mask] <- 1L
        coded[mask & values >= emerging] <- 2L
        coded[mask & values >= on_track] <- 3L
      }
      coded_df[[study_var]] <- coded
    }

    item_cols <- setdiff(names(coded_df), c(key_vars, "years_old"))
    if (length(item_cols) == 0) next

    coded_df$avg_code <- rowMeans(coded_df[, item_cols, drop = FALSE], na.rm = TRUE)
    coded_df <- coded_df %>%
      dplyr::mutate(
        classification = dplyr::case_when(
          is.nan(avg_code) ~ NA_character_,
          avg_code < 2.0 ~ "Needs Support",
          avg_code <  2.5 ~ "Emerging",
          avg_code >= 2.5 ~ "On-Track",
          TRUE ~ NA_character_
        ),
        avg_code = ifelse(is.nan(avg_code), NA_real_, avg_code),
        domain = domain
      )

    domain_score_frames[[domain]] <- coded_df %>%
      dplyr::select(dplyr::all_of(c(key_vars, "domain", "avg_code", "classification", "years_old")))
  }

  if (length(domain_score_frames) == 0) {
    warning("No HRTL domains scored")
    return(list(domain_scores = data.frame(),
                overall = data.frame(),
                motor_coverage = motor_coverage,
                motor_masked = motor_masked))
  }

  domain_scores <- dplyr::bind_rows(domain_score_frames)

  # Apply Motor masking if gate triggered
  if (motor_masked) {
    domain_scores <- domain_scores %>%
      dplyr::mutate(
        avg_code       = dplyr::if_else(domain == motor_label, NA_real_, avg_code),
        classification = dplyr::if_else(domain == motor_label, NA_character_, classification)
      )
  }

  # ============================================================================
  # PHASE 4c: Build overall HRTL classification (one row per child)
  # ============================================================================

  # Wide format: one row per child with one column per domain status
  overall <- domain_scores %>%
    dplyr::select(dplyr::all_of(c(key_vars, "domain", "classification"))) %>%
    tidyr::pivot_wider(names_from = domain, values_from = classification,
                       names_prefix = "status_") %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      n_on_track      = sum(dplyr::c_across(dplyr::starts_with("status_")) == "On-Track",      na.rm = TRUE),
      n_needs_support = sum(dplyr::c_across(dplyr::starts_with("status_")) == "Needs Support", na.rm = TRUE)
    ) %>%
    dplyr::ungroup()

  # HRTL = >=4 domains On-Track AND 0 domains Needs Support
  overall <- overall %>%
    dplyr::mutate(hrtl = (n_on_track >= 4) & (n_needs_support == 0))

  # If Motor was masked, overall HRTL is unreliable (incomplete domain set) -> NA
  if (motor_masked) {
    overall <- overall %>% dplyr::mutate(hrtl = NA)
  }

  overall <- overall %>%
    dplyr::select(dplyr::all_of(c(key_vars, "n_on_track", "n_needs_support", "hrtl")))

  if (verbose) {
    n_overall <- nrow(overall)
    n_hrtl_true <- if (motor_masked) NA_integer_ else sum(overall$hrtl, na.rm = TRUE)
    message(sprintf("\n  Domain scores: %d rows across %d domains",
                    nrow(domain_scores), length(unique(domain_scores$domain))))
    message(sprintf("  Overall HRTL: %d children",
                    n_overall))
    if (!is.na(n_hrtl_true)) {
      message(sprintf("  HRTL=TRUE: %d (%.1f%%)", n_hrtl_true,
                      100 * n_hrtl_true / n_overall))
    } else {
      message("  HRTL: all NA (Motor masked)")
    }
  }

  return(list(
    domain_scores  = domain_scores,
    overall        = overall,
    motor_coverage = motor_coverage,
    motor_masked   = motor_masked
  ))
}


#' Save HRTL scores to DuckDB database
#'
#' Persists the two HRTL output frames (`domain_scores`, `overall`) returned by
#' [score_hrtl()] to study-prefixed DuckDB tables. Indexes are created on each
#' column in `key_vars`.
#'
#' @param hrtl_result List returned by [score_hrtl()].
#' @param db_path Path to DuckDB database file.
#' @param study_id Study identifier; drives table naming
#'   (`<study_id>_hrtl_domain_scores`, `<study_id>_hrtl_overall`).
#' @param key_vars Columns to index.
#' @param overwrite Logical, overwrite existing tables (default `TRUE`).
#' @param verbose Logical, print progress.
#'
#' @return Invisible NULL.
#'
#' @export
save_hrtl_scores_to_db <- function(hrtl_result,
                                   db_path = "data/duckdb/kidsights_local.duckdb",
                                   study_id = "ne25",
                                   key_vars = c("pid", "record_id"),
                                   overwrite = TRUE,
                                   verbose = TRUE) {

  domain_table  <- paste0(study_id, "_hrtl_domain_scores")
  overall_table <- paste0(study_id, "_hrtl_overall")

  if (verbose) {
    message(sprintf("[INFO] Saving HRTL scores to %s and %s",
                    domain_table, overall_table))
  }

  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(con, domain_table,  hrtl_result$domain_scores, overwrite = overwrite)
  DBI::dbWriteTable(con, overall_table, hrtl_result$overall,       overwrite = overwrite)

  for (tbl in c(domain_table, overall_table)) {
    for (col in key_vars) {
      DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_%s ON %s(%s)",
                                  tbl, col, tbl, col))
    }
  }
  # Domain table also benefits from a domain index
  DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_domain ON %s(domain)",
                              domain_table, domain_table))

  if (verbose) {
    message(sprintf("[INFO] Wrote %d domain rows and %d overall rows",
                    nrow(hrtl_result$domain_scores), nrow(hrtl_result$overall)))
  }
  invisible(NULL)
}
