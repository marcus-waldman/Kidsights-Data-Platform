#' MN26 Pipeline Orchestration
#'
#' Main pipeline function that coordinates the complete MN26 data extraction,
#' pivot (wide-to-long for multi-child households), transformation, eligibility
#' validation, and database loading workflow.
#'
#' Pipeline Steps:
#'   1. Load API credentials
#'   2. Extract REDCap data + dictionary
#'   3. Wide-to-long pivot (multi-child → 1 row per child)
#'   4. Store raw data (wide + long) in DuckDB
#'   5. Data transformation (recode_it with MN26 field names)
#'   6. Eligibility validation (4 criteria)
#'   7. Create meets_inclusion filter
#'   8. Kidsights developmental scoring (KidsightsPublic package)
#'   8.5. CREDI scoring (children under 4)
#'   8.6. GSED D-score (all meets_inclusion children)
#'   8.7. HRTL scoring (ages 3-5; auto Motor coverage gate)
#'   9. Store transformed data in DuckDB
#'   10. Store data dictionary

# Load required libraries
library(dplyr)
library(yaml)
library(arrow)
library(KidsightsPublic)  # CmdStan MAP scoring (score_kidsights, score_psychosocial)

# Source required functions
source("R/extract/mn26.R")
source("R/transform/mn26_pivot.R")
source("R/transform/mn26_transforms.R")
source("R/harmonize/mn26_eligibility.R")
source("R/utils/environment_config.R")
source("R/utils/safe_joins.R")
source("R/credi/score_credi.R")
source("R/dscore/score_dscore.R")
source("R/hrtl/score_hrtl.R")

#' Execute the complete MN26 pipeline
#'
#' @param config_path Path to MN26 configuration file
#' @param credentials_path Path to API credentials CSV (overrides config/env)
#' @param skip_database Logical, skip database storage (useful for testing)
#' @return List with execution results and metrics
run_mn26_pipeline <- function(config_path = "config/sources/mn26.yaml",
                              credentials_path = NULL,
                              skip_database = FALSE,
                              data = NULL) {

  execution_id <- paste0("mn26_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  pipeline_start <- Sys.time()

  message("\n========================================")
  message("MN26 Pipeline")
  message("========================================")
  message("Execution ID: ", execution_id)
  message("Start Time:   ", pipeline_start)

  # Load configuration
  config <- yaml::read_yaml(config_path)
  message("[OK] Configuration loaded")

  # Initialize metrics
  metrics <- list(
    execution_id = execution_id,
    start_time = pipeline_start,
    n_extracted = 0,
    n_pivoted = 0,
    n_child1 = 0,
    n_child2 = 0,
    n_eligible = 0,
    n_meets_inclusion = 0,
    step_durations = list()
  )

  tryCatch({

    if (is.null(data)) {
      # ==================================================================
      # STEP 1: LOAD API CREDENTIALS
      # ==================================================================
      message("\n--- Step 1: Loading API Credentials ---")
      step_start <- Sys.time()

      creds <- load_mn26_credentials(csv_path = credentials_path, config = config)

      metrics$step_durations$credentials <- as.numeric(Sys.time() - step_start)

      # ==================================================================
      # STEP 2: EXTRACT DATA + DICTIONARY FROM REDCAP
      # ==================================================================
      message("\n--- Step 2: Extracting REDCap Data ---")
      step_start <- Sys.time()

      extraction <- extract_mn26_data(
        credentials = creds,
        redcap_url = config$redcap$url,
        timeout = config$redcap$timeout
      )

      raw_wide <- extraction$data
      dictionary <- extraction$dictionary
      dictionary_full <- extraction$dictionary_full

      metrics$n_extracted <- nrow(raw_wide)
      metrics$step_durations$extraction <- as.numeric(Sys.time() - step_start)
      message(sprintf("  Extracted: %d records, %d columns", nrow(raw_wide), ncol(raw_wide)))

    } else {
      # Pre-loaded data (e.g., synthetic test) — skip extraction
      message("\n--- Steps 1-2: SKIPPED (pre-loaded data) ---")
      raw_wide <- data
      dictionary <- list()
      dictionary_full <- list()
      metrics$n_extracted <- nrow(raw_wide)
      message(sprintf("  Pre-loaded: %d records, %d columns", nrow(raw_wide), ncol(raw_wide)))
    }

    # Ensure sq001 (ZIP) is character
    if ("sq001" %in% names(raw_wide)) {
      raw_wide$sq001 <- as.character(raw_wide$sq001)
    }

    # ==================================================================
    # STEP 3: WIDE-TO-LONG PIVOT
    # ==================================================================
    message("\n--- Step 3: Wide-to-Long Pivot ---")
    step_start <- Sys.time()

    raw_long <- pivot_mn26_wide_to_long(raw_wide)

    metrics$n_pivoted <- nrow(raw_long)
    metrics$n_child1 <- sum(raw_long$child_num == 1)
    metrics$n_child2 <- sum(raw_long$child_num == 2)
    metrics$step_durations$pivot <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 4: STORE RAW DATA IN DUCKDB
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 4: Storing Raw Data ---")
      step_start <- Sys.time()

      temp_dir <- file.path(tempdir(), "mn26_pipeline")
      dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

      python_path <- get_python_path()
      db_path <- config$output$database_path

      # 4a: Store wide format (audit trail)
      wide_feather <- file.path(temp_dir, "mn26_raw_wide.feather")
      wide_meta <- raw_wide %>%
        dplyr::select(record_id, pid, dplyr::any_of(c(
          "redcap_event_name", "retrieved_date", "source_project", "extraction_id"
        )))
      arrow::write_feather(wide_meta, wide_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", wide_feather,
        "--table-name", "mn26_raw_wide",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_raw_wide stored (", nrow(wide_meta), " rows)")

      # 4b: Store long format (post-pivot)
      long_feather <- file.path(temp_dir, "mn26_raw.feather")
      long_meta <- raw_long %>%
        dplyr::select(record_id, pid, child_num, dplyr::any_of(c(
          "redcap_event_name", "retrieved_date", "source_project", "extraction_id"
        )))
      arrow::write_feather(long_meta, long_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", long_feather,
        "--table-name", "mn26_raw",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_raw stored (", nrow(long_meta), " rows)")

      metrics$step_durations$store_raw <- as.numeric(Sys.time() - step_start)
    } else {
      message("\n--- Step 4: SKIPPED (skip_database=TRUE) ---")
    }

    # ==================================================================
    # STEP 4.5: HRTL MOTOR _end CATCH-UP COALESCE
    # ==================================================================
    # NORC added _end-suffixed catch-up fields for the HRTL Motor drawing
    # items in module_6_1097_2191 (3-6 yr form) to fix NE25's age-routing
    # gap. Coalesce them into the canonical names BEFORE recode_it() so
    # reverse_code_items() and validate_item_responses() see the merged
    # values via the codebook's mn26 lexicon (the _end columns themselves
    # have no codebook entry).
    message("\n--- Step 4.5: HRTL Motor _end coalesce ---")
    step_start <- Sys.time()

    motor_pairs <- list(
      c(canonical = "nom029x", catchup = "nom029x_end"),  # DRAWCIRCLE
      c(canonical = "nom033x", catchup = "nom033x_end"),  # DRAWFACE
      c(canonical = "nom034x", catchup = "nom034x_end")   # DRAWPERSON
      # nom042x (BOUNCEBALL) lives natively in the 3-6 yr form -- no _end twin
    )

    n_coalesced_total <- 0L
    n_both_total      <- 0L
    n_disagree_total  <- 0L

    for (p in motor_pairs) {
      canonical <- p[["canonical"]]
      catchup   <- p[["catchup"]]
      if (!(canonical %in% names(raw_long)) || !(catchup %in% names(raw_long))) {
        message(sprintf("  [INFO] %s/%s pair not present in data; skipping", canonical, catchup))
        next
      }
      v_can <- raw_long[[canonical]]
      v_end <- raw_long[[catchup]]
      has_can <- !is.na(v_can)
      has_end <- !is.na(v_end)
      both    <- has_can & has_end
      disagree <- both & (v_can != v_end)
      n_coal_this <- sum(has_can | has_end)
      n_both_this <- sum(both)
      n_dis_this  <- sum(disagree)
      n_coalesced_total <- n_coalesced_total + n_coal_this
      n_both_total      <- n_both_total + n_both_this
      n_disagree_total  <- n_disagree_total + n_dis_this

      # Audit column captures provenance per row before we drop the _end col
      raw_long[[paste0(canonical, "_source")]] <- dplyr::case_when(
        both     ~ "both",
        has_end  ~ "end",
        has_can  ~ "original",
        TRUE     ~ NA_character_
      )

      # Coalesce: prefer _end (the HRTL-eligible-band catch-up)
      raw_long[[canonical]] <- dplyr::coalesce(v_end, v_can)
      raw_long[[catchup]]   <- NULL

      message(sprintf("  [INFO] %-9s coalesced: %d non-NA (%d both, %d disagree)",
                      canonical, n_coal_this, n_both_this, n_dis_this))
    }
    message(sprintf("  Motor _end coalesce summary: %d total coalesced, %d both, %d disagreements",
                    n_coalesced_total, n_both_total, n_disagree_total))

    metrics$step_durations$motor_coalesce <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 5: DATA TRANSFORMATION
    # ==================================================================
    message("\n--- Step 5: Data Transformation ---")
    step_start <- Sys.time()

    # Apply transforms using MN26-specific recode_it
    # Note: recode_it uses the dictionary for value labels (dictionary-driven)
    transformed_data <- recode_it(
      dat = raw_long,
      dict = dictionary_full,  # Use full dict (includes @HIDDEN fields for value_labels)
      what = "all"
    )

    metrics$step_durations$transformation <- as.numeric(Sys.time() - step_start)
    message(sprintf("  Transformed: %d records, %d columns",
                    nrow(transformed_data), ncol(transformed_data)))

    # ==================================================================
    # STEP 6: ELIGIBILITY VALIDATION
    # ==================================================================
    message("\n--- Step 6: Eligibility Validation ---")
    step_start <- Sys.time()

    transformed_data <- check_mn26_eligibility(transformed_data)
    metrics$n_eligible <- sum(transformed_data$eligible, na.rm = TRUE)

    metrics$step_durations$eligibility <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 7: CREATE MEETS_INCLUSION FILTER
    # ==================================================================
    message("\n--- Step 7: Inclusion Filter ---")

    transformed_data <- apply_mn26_inclusion(transformed_data)
    metrics$n_meets_inclusion <- sum(transformed_data$meets_inclusion, na.rm = TRUE)

    # ==================================================================
    # STEP 8: KIDSIGHTS DEVELOPMENTAL SCORING
    # ==================================================================
    message("\n--- Step 8: Kidsights Developmental Scoring ---")
    step_start <- Sys.time()

    # Score only eligible records (those with meets_inclusion == TRUE).
    # score_kidsights() requires complete years_old values, which only
    # eligible records reliably have.
    tryCatch({
      scoring_subset <- transformed_data %>%
        dplyr::filter(isTRUE(meets_inclusion) | meets_inclusion %in% TRUE)

      message(sprintf("  Scoring %d eligible children (of %d total)...",
                      nrow(scoring_subset), nrow(transformed_data)))

      if (nrow(scoring_subset) == 0) {
        message("  [WARN] No eligible records to score")
        transformed_data$kidsights_theta <- NA_real_
        metrics$n_kidsights_scored <- 0
      } else {
        kidsights_scores <- KidsightsPublic::score_kidsights(
          scoring_subset,
          id_cols = c("pid", "record_id", "child_num"),
          min_responses = 5
        )

        # Join theta back to full transformed data (non-eligible get NA)
        transformed_data <- transformed_data %>%
          safe_left_join(
            kidsights_scores %>% dplyr::rename(kidsights_theta = theta),
            by_vars = c("pid", "record_id", "child_num")
          )

        n_scored <- sum(!is.na(transformed_data$kidsights_theta))
        message(sprintf("  Scored: %d of %d eligible children",
                        n_scored, nrow(scoring_subset)))
        metrics$n_kidsights_scored <- n_scored
      }
    }, error = function(e) {
      message("  [WARN] Kidsights scoring failed: ", e$message)
      transformed_data$kidsights_theta <<- NA_real_
      metrics$n_kidsights_scored <<- 0
    })

    metrics$step_durations$kidsights_scoring <- as.numeric(Sys.time() - step_start)

    # NOTE: Psychosocial domain scoring (score_psychosocial) is NOT included
    # for MN26 — psychosocial items are NE25-specific.

    # ==================================================================
    # STEP 8.5: CREDI SCORING (CHILDREN UNDER 4 YEARS OLD)
    # ==================================================================
    message("\n--- Step 8.5: CREDI Developmental Scoring ---")
    step_start <- Sys.time()

    tryCatch({
      message("Computing CREDI developmental scores for children under 4 years old...")
      credi_scores <- score_credi(
        data = transformed_data,
        codebook_path = "codebook/data/codebook.json",
        min_items = 5,
        age_cutoff = 4,
        study_id = "mn26",
        key_vars = c("pid", "record_id", "child_num"),
        verbose = TRUE
      )

      if (nrow(credi_scores) > 0 && !skip_database) {
        message(sprintf("CREDI scoring complete. Saving %d records to database...", nrow(credi_scores)))
        save_credi_scores_to_db(
          scores = credi_scores,
          db_path = config$output$database_path,
          table_name = "mn26_credi_scores",
          key_vars = c("pid", "record_id", "child_num"),
          overwrite = TRUE,
          verbose = TRUE
        )

        # Join CREDI scores back into transformed_data with credi_ prefix
        credi_renamed <- credi_scores %>%
          dplyr::rename_with(
            ~paste0("credi_", tolower(.x)),
            -dplyr::all_of(c("pid", "record_id", "child_num"))
          )
        transformed_data <- transformed_data %>%
          safe_left_join(credi_renamed, by_vars = c("pid", "record_id", "child_num"))

        metrics$n_credi_scored <- sum(!is.na(transformed_data$credi_overall))
      } else if (nrow(credi_scores) > 0) {
        message(sprintf("CREDI scoring complete (%d records); skipping DB save (skip_database=TRUE)",
                        nrow(credi_scores)))
        metrics$n_credi_scored <- sum(!is.na(credi_scores$OVERALL))
      } else {
        message("No records eligible for CREDI scoring (no children under 4 years old)")
        metrics$n_credi_scored <- 0
      }
    }, error = function(e) {
      message("  [WARN] CREDI scoring failed: ", e$message)
      message("  [WARN] Continuing pipeline without CREDI scores")
      metrics$n_credi_scored <<- 0
    })

    metrics$step_durations$credi_scoring <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 8.6: GSED D-SCORE CALCULATION (ALL ELIGIBLE AGES)
    # ==================================================================
    message("\n--- Step 8.6: GSED D-score Calculation ---")
    step_start <- Sys.time()

    tryCatch({
      # Bridge MN26 -> cross-study naming. MN26's REDCap project uses NORC's
      # `_n` (numeric) suffix convention (`age_in_days_n`); the cross-study
      # scorer expects `age_in_days`. Mirror the column without renaming the
      # source so other MN26-specific code that reads `age_in_days_n` is
      # unaffected.
      dscore_input <- transformed_data
      if (!"age_in_days" %in% names(dscore_input) &&
          "age_in_days_n" %in% names(dscore_input)) {
        dscore_input$age_in_days <- dscore_input$age_in_days_n
      }

      message("Computing GSED D-scores for all eligible children...")
      dscore_scores <- score_dscore(
        data = dscore_input,
        codebook_path = "codebook/data/codebook.json",
        key = "gsed2406",
        study_id = "mn26",
        key_vars = c("pid", "record_id", "child_num"),
        verbose = TRUE
      )

      if (nrow(dscore_scores) > 0 && !skip_database) {
        message(sprintf("GSED D-score calculation complete. Saving %d records to database...",
                        nrow(dscore_scores)))
        save_dscore_scores_to_db(
          scores = dscore_scores,
          db_path = config$output$database_path,
          table_name = "mn26_dscore_scores",
          key_vars = c("pid", "record_id", "child_num"),
          overwrite = TRUE,
          verbose = TRUE
        )

        # Join D-scores back into transformed_data with dscore_ prefix
        dscore_renamed <- dscore_scores %>%
          dplyr::rename_with(
            ~paste0("dscore_", tolower(.x)),
            -dplyr::all_of(c("pid", "record_id", "child_num"))
          )
        transformed_data <- transformed_data %>%
          safe_left_join(dscore_renamed, by_vars = c("pid", "record_id", "child_num"))

        metrics$n_dscore_scored <- sum(!is.na(transformed_data$dscore_d))
      } else if (nrow(dscore_scores) > 0) {
        message(sprintf("D-score calculation complete (%d records); skipping DB save (skip_database=TRUE)",
                        nrow(dscore_scores)))
        metrics$n_dscore_scored <- sum(!is.na(dscore_scores$d))
      } else {
        message("No records eligible for GSED D-score calculation")
        metrics$n_dscore_scored <- 0
      }
    }, error = function(e) {
      message("  [WARN] GSED D-score calculation failed: ", e$message)
      message("  [WARN] Continuing pipeline without GSED D-scores")
      metrics$n_dscore_scored <<- 0
    })

    metrics$step_durations$dscore_scoring <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 8.7: HRTL SCORING (AGES 3-5; AUTO MOTOR COVERAGE GATE)
    # ==================================================================
    # Function-based HRTL scorer with auto coverage gate. MN26's _end
    # catch-up coalesce (Step 4.5) ensures Motor coverage in the 3-5 yr
    # band is ~85%, well above the 0.50 threshold -- so unlike NE25,
    # MN26 produces non-NA Motor classifications and overall HRTL.
    # MN26 covariate is kidsights_theta (from Step 8); the NE25 manual-
    # calibration covariates (kidsights_2022, general_gsed_pf_2022) do
    # not exist in mn26_transformed and the scorer drops them silently.
    message("\n--- Step 8.7: HRTL Scoring Pipeline ---")
    step_start <- Sys.time()

    tryCatch({
      hrtl_results <- score_hrtl(
        data = transformed_data,
        study_id = "mn26",
        key_vars = c("pid", "record_id", "child_num"),
        codebook_path = "codebook/data/codebook.json",
        thresholds_path = "data/reference/hrtl/HRTL-2022-Scoring-Thresholds.xlsx",
        itemdict_path = "data/reference/hrtl/itemdict22.csv",
        covariate_cols = c("kidsights_theta"),
        min_motor_coverage = 0.50,
        verbose = TRUE
      )

      if (nrow(hrtl_results$domain_scores) > 0 && !skip_database) {
        save_hrtl_scores_to_db(
          hrtl_result = hrtl_results,
          db_path = config$output$database_path,
          study_id = "mn26",
          key_vars = c("pid", "record_id", "child_num"),
          overwrite = TRUE,
          verbose = TRUE
        )

        metrics$n_hrtl_scored <- nrow(hrtl_results$overall)
        metrics$hrtl_motor_coverage <- hrtl_results$motor_coverage
        metrics$hrtl_motor_masked   <- hrtl_results$motor_masked
      } else if (nrow(hrtl_results$domain_scores) > 0) {
        message(sprintf("HRTL scoring complete (%d domain rows); skipping DB save (skip_database=TRUE)",
                        nrow(hrtl_results$domain_scores)))
        metrics$n_hrtl_scored <- nrow(hrtl_results$overall)
        metrics$hrtl_motor_coverage <- hrtl_results$motor_coverage
        metrics$hrtl_motor_masked   <- hrtl_results$motor_masked
      } else {
        message("No records eligible for HRTL scoring")
        metrics$n_hrtl_scored <- 0
      }

      # Domain classification summary
      if (nrow(hrtl_results$domain_scores) > 0) {
        message("\nMN26 HRTL Domain Classification Summary:")
        for (d in unique(hrtl_results$domain_scores$domain)) {
          domain_rows <- hrtl_results$domain_scores %>% dplyr::filter(domain == !!d)
          n_classified <- sum(!is.na(domain_rows$classification))
          if (n_classified == 0) {
            message(sprintf("  %s: all NA (masked)", d))
          } else {
            on_track <- sum(domain_rows$classification == "On-Track", na.rm = TRUE)
            pct <- 100 * on_track / n_classified
            message(sprintf("  %s: %d/%d on-track (%.1f%%)", d, on_track, n_classified, pct))
          }
        }
      }
    }, error = function(e) {
      message("  [WARN] HRTL scoring failed: ", e$message)
      message("  [WARN] Continuing pipeline without HRTL scores")
      metrics$n_hrtl_scored <<- 0
    })

    metrics$step_durations$hrtl_scoring <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 9: STORE TRANSFORMED DATA IN DUCKDB
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 9: Storing Transformed Data ---")
      step_start <- Sys.time()

      transformed_feather <- file.path(temp_dir, "mn26_transformed.feather")
      arrow::write_feather(transformed_data, transformed_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", transformed_feather,
        "--table-name", "mn26_transformed",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_transformed stored (", nrow(transformed_data), " rows)")

      metrics$step_durations$store_transformed <- as.numeric(Sys.time() - step_start)
    } else {
      message("\n--- Step 9: SKIPPED (skip_database=TRUE) ---")
    }

    # ==================================================================
    # STEP 10: STORE DATA DICTIONARY
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 10: Storing Data Dictionary ---")

      dict_df <- dictionary_to_dataframe(dictionary_full)
      dict_feather <- file.path(temp_dir, "mn26_data_dictionary.feather")
      arrow::write_feather(dict_df, dict_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", dict_feather,
        "--table-name", "mn26_data_dictionary",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_data_dictionary stored (", nrow(dict_df), " fields)")
    }

  }, error = function(e) {
    message("\n[ERROR] Pipeline failed: ", e$message)
    metrics$error <- e$message
  })

  # ==================================================================
  # SUMMARY
  # ==================================================================
  metrics$total_duration <- as.numeric(Sys.time() - pipeline_start)

  message("\n========================================")
  message("MN26 Pipeline Complete")
  message("========================================")
  message(sprintf("  Records extracted:    %d", metrics$n_extracted))
  message(sprintf("  Records after pivot:  %d (child 1: %d, child 2: %d)",
                  metrics$n_pivoted, metrics$n_child1, metrics$n_child2))
  message(sprintf("  Eligible:             %d", metrics$n_eligible))
  message(sprintf("  Meets inclusion:      %d", metrics$n_meets_inclusion))
  message(sprintf("  Kidsights scored:     %d", if (is.null(metrics$n_kidsights_scored)) 0 else metrics$n_kidsights_scored))
  message(sprintf("  CREDI scored:         %d", if (is.null(metrics$n_credi_scored)) 0 else metrics$n_credi_scored))
  message(sprintf("  GSED D-score scored:  %d", if (is.null(metrics$n_dscore_scored)) 0 else metrics$n_dscore_scored))
  message(sprintf("  HRTL scored:          %d", if (is.null(metrics$n_hrtl_scored)) 0 else metrics$n_hrtl_scored))
  if (!is.null(metrics$hrtl_motor_coverage)) {
    message(sprintf("  HRTL Motor coverage:  %.1f%% (%s)",
                    100 * metrics$hrtl_motor_coverage,
                    if (isTRUE(metrics$hrtl_motor_masked)) "MASKED" else "scored"))
  }
  message(sprintf("  Total duration:       %.1f seconds", metrics$total_duration))
  message("========================================\n")

  return(list(
    metrics = metrics,
    data = transformed_data,
    raw_wide = raw_wide,
    raw_long = raw_long,
    dictionary = dictionary,
    dictionary_full = dictionary_full
  ))
}
