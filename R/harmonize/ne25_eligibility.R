#' NE25 Eligibility Validation Functions
#'
#' Port of eligibility checking functions from the dashboard utils-eligibility.R
#' Implements the 9 eligibility criteria (CID1-CID9) for the NE25 study
#'
#' All participants must pass eligibility AND authenticity checks for inclusion

# Automatic package installation and loading
install_and_load_packages <- function() {
  # Required packages for eligibility validation
  required_packages <- c(
    # Basic data manipulation
    "dplyr",      # Data manipulation
    "stringr",    # String operations
    "tidyr",      # Data tidying
    "plyr",       # For mapvalues (load before dplyr to avoid conflicts)

    # Advanced statistical packages for CID8 IRT analysis
    "gamlss",     # Generalized Additive Models for Location Scale and Shape
    "mirt",       # Multidimensional Item Response Theory
    "pairwise",   # Pairwise comparison models

    # Additional packages that may be needed
    "readxl",     # For ZIP code data
    "zipcodeR",   # ZIP code utilities
    "haven",      # For data format handling
    "knitr"       # For table formatting
  )

  # Check which packages are missing
  missing_packages <- setdiff(required_packages, installed.packages()[,"Package"])

  # Install missing packages
  if(length(missing_packages) > 0) {
    message("Installing missing packages for eligibility validation: ",
            paste(missing_packages, collapse = ", "))

    # Install from CRAN with dependencies
    install.packages(missing_packages,
                    dependencies = TRUE,
                    repos = "https://cran.rstudio.com/",
                    quiet = TRUE)

    message("Package installation completed.")
  }

  # Load packages in correct order (plyr before dplyr to avoid conflicts)
  load_order <- c("plyr", setdiff(required_packages, "plyr"))

  for(pkg in load_order) {
    if(pkg %in% installed.packages()[,"Package"]) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    } else {
      warning(paste("Package", pkg, "failed to install and could not be loaded"))
    }
  }

  # Verify critical packages for CID8
  critical_packages <- c("gamlss", "mirt", "pairwise")
  missing_critical <- setdiff(critical_packages, loadedNamespaces())

  if(length(missing_critical) > 0) {
    warning("Critical packages for CID8 analysis not available: ",
            paste(missing_critical, collapse = ", "),
            "\nCID8 quality scoring may not work properly.")
  }

  return(list(
    installed = required_packages,
    missing = missing_packages,
    critical_missing = missing_critical
  ))
}

# Initialize packages
package_status <- install_and_load_packages()

#' Check CID1: Compensation acknowledgment
#'
#' Validates that participants acknowledged all compensation terms
#'
#' @param data Data frame with compensation acknowledgment fields
#' @return Data frame with CID1 pass/fail status
check_cid1_compensation <- function(data) {

  required_fields <- c(
    "state_law_requires_that_kidsights_data_collect_my_name___1",
    "financial_compensation_be_sent_to_a_nebraska_residential_address___1",
    "state_law_prohibits_sending_compensation_electronically___1",
    "kidsights_data_reviews_all_responses_for_quality___1"
  )

  cid1_result <- data %>%
    dplyr::select(pid, record_id, any_of(required_fields)) %>%
    rowwise() %>%
    dplyr::mutate(
      pass_cid1 = sum(c_across(all_of(intersect(required_fields, names(.)))), na.rm = TRUE) == 4
    ) %>%
    ungroup() %>%
    dplyr::select(pid, record_id, pass_cid1)

  return(cid1_result)
}

#' Check CID2: Informed consent
#'
#' Validates that informed consent was provided
#'
#' @param data Data frame with consent field (eq001)
#' @return Data frame with CID2 pass/fail status
check_cid2_consent <- function(data) {

  cid2_result <- data %>%
    dplyr::select(pid, record_id, eq001) %>%
    dplyr::mutate(
      pass_cid2 = eq001 == 1 & !is.na(eq001)
    ) %>%
    dplyr::select(pid, record_id, pass_cid2)

  return(cid2_result)
}

#' Check CID3: Caregiver age and status
#'
#' Validates that respondent is 19+ years old and primary caregiver
#'
#' @param data Data frame with caregiver fields (eq002, eq003)
#' @return Data frame with CID3 pass/fail status
check_cid3_caregiver <- function(data) {

  cid3_result <- data %>%
    dplyr::select(pid, record_id, eq003, eq002) %>%
    dplyr::mutate(
      pass_cid3 = (eq002 == 1 & eq003 == 1) & !is.na(eq002) & !is.na(eq003)
    ) %>%
    dplyr::select(pid, record_id, pass_cid3)

  return(cid3_result)
}

#' Check CID4: Child age restriction
#'
#' Validates that child is 2191 days (6 years) or younger
#'
#' @param data Data frame with age_in_days field
#' @return Data frame with CID4 pass/fail status
check_cid4_child_age <- function(data) {

  cid4_result <- data %>%
    dplyr::select(pid, record_id, age_in_days) %>%
    dplyr::mutate(
      pass_cid4 = (age_in_days <= 2191) & !is.na(age_in_days)
    ) %>%
    dplyr::select(pid, record_id, pass_cid4)

  return(cid4_result)
}

#' Check CID5: Nebraska residence
#'
#' Validates that participant currently lives in Nebraska
#'
#' @param data Data frame with state field (eqstate)
#' @return Data frame with CID5 pass/fail status
check_cid5_nebraska <- function(data) {

  cid5_result <- data %>%
    dplyr::select(pid, record_id, eqstate) %>%
    dplyr::mutate(
      pass_cid5 = (eqstate == 1) & !is.na(eqstate)
    ) %>%
    dplyr::select(pid, record_id, pass_cid5)

  return(cid5_result)
}

#' Check CID6: ZIP code and county consistency
#'
#' Validates that ZIP code matches reported county
#'
#' @param data Data frame with ZIP (sq001) and county (fq001) fields
#' @param data_dictionary REDCap data dictionary for value labels
#' @return Data frame with CID6 pass/fail status
check_cid6_zip_county <- function(data, data_dictionary) {

  # Extract county labels from data dictionary
  county_labels <- extract_value_labels("fq001", data_dictionary)

  cid6_result <- data %>%
    select(pid, record_id, sq001, fq001) %>%
    # Ensure fq001 is character for consistent joining
    dplyr::mutate(fq001 = as.character(fq001)) %>%
    # Map county codes to labels
    left_join(
      county_labels %>%
        dplyr::rename(fq001 = value, county_name = label) %>%
        dplyr::mutate(fq001 = as.character(fq001)),  # Ensure same type
      by = "fq001"
    ) %>%
    # Get acceptable ZIP codes for each county
    dplyr::left_join(
      get_nebraska_zip_county_crosswalk(),
      by = c("sq001" = "zip_code")
    ) %>%
    dplyr::mutate(
      # Check if reported county is in the acceptable counties for this ZIP
      pass_cid6 = !is.na(county_name) & !is.na(acceptable_counties) &
                  stringr::str_detect(acceptable_counties, fixed(county_name))
    ) %>%
    select(pid, record_id, pass_cid6)

  return(cid6_result)
}

#' Check CID7: Birthday confirmation
#'
#' Validates that child's birthday was confirmed
#'
#' @param data Data frame with date_complete_check field
#' @return Data frame with CID7 pass/fail status
check_cid7_birthday <- function(data) {

  cid7_result <- data %>%
    select(pid, record_id, date_complete_check) %>%
    mutate(
      pass_cid7 = (date_complete_check == 1) & !is.na(date_complete_check)
    ) %>%
    select(pid, record_id, pass_cid7)

  return(cid7_result)
}

#' Check CID8: KMT response quality
#'
#' Validates KMT assessment quality based on non-"Don't Know" responses
#' and z-score distribution using IRT analysis (ported from Dashboard)
#'
#' @param data Data frame with KMT assessment data
#' @param codebook Codebook data frame with item mappings
#' @param calibdat Calibration dataset for IRT analysis (optional)
#' @return Data frame with CID8 pass/fail status
check_cid8_kmt_quality <- function(data, codebook, calibdat = NULL) {

  cat("=== CID8 CHECK STARTING ===\n")
  cat("Data dimensions:", nrow(data), "x", ncol(data), "\n")
  cat("Codebook rows:", nrow(codebook), "\n")

  # Save test data for faster debugging
  test_data_dir <- "temp/cid8_test_data"
  if (!dir.exists(test_data_dir)) dir.create(test_data_dir, recursive = TRUE)

  saveRDS(data, file.path(test_data_dir, "cid8_input_data.rds"))
  saveRDS(codebook, file.path(test_data_dir, "cid8_input_codebook.rds"))
  if (!is.null(calibdat)) {
    saveRDS(calibdat, file.path(test_data_dir, "cid8_input_calibdat.rds"))
  } else {
    # Save a marker that calibdat is NULL
    saveRDS(NULL, file.path(test_data_dir, "cid8_input_calibdat.rds"))
  }
  cat("CID8 test data saved to:", test_data_dir, "\n")

  # Ensure required packages are loaded
  if(!all(c("gamlss", "mirt", "pairwise") %in% loadedNamespaces())) {
    warning("CID8 requires gamlss, mirt, and pairwise packages. Attempting to load...")
    install_and_load_packages()
  }

  tryCatch({
    # Filter codebook to valid items
    codebook <- codebook %>%
      dplyr::filter(!is.na(lex_ne25), !is.na(lex_kidsight)) %>%
      dplyr::mutate(lex_ne25 = tolower(lex_ne25))

    # Initial data preparation
    foo <- data %>%
      dplyr::rename(days = age_in_days) %>%
      dplyr::select(pid, record_id, days, dplyr::any_of(codebook$lex_ne25)) %>%
      dplyr::mutate(years = days/365.25, months = floor(12*(days/365.25))) %>%
      dplyr::relocate(pid, record_id, years, months, days) %>%
      tidyr::pivot_longer(cols = -c(1:5), names_to = "lex_ne25") %>%
      stats::na.omit() %>%
      dplyr::left_join(codebook, by = "lex_ne25")

    cat("Columns after codebook join:", paste(names(foo)[1:min(10, ncol(foo))], collapse=", "), "\n")

    # Determine which column to arrange by and do the arrangement
    if ("item_order" %in% names(foo)) {
      foo <- foo %>% dplyr::arrange(pid, record_id, item_order)
    } else if ("jid" %in% names(foo)) {
      foo <- foo %>% dplyr::arrange(pid, record_id, jid)
    } else {
      # Fallback: just arrange by pid and record_id
      foo <- foo %>% dplyr::arrange(pid, record_id)
    }

    foo <- foo %>%
      dplyr::relocate(pid:days, dplyr::any_of(c("item_order", "jid")), lex_ne25, dplyr::any_of(c("stem", "value", "num_code")))

    cat("DEBUG: About to calculate response_counts...\n")
    cat("DEBUG: foo dimensions before response_counts:", nrow(foo), "x", ncol(foo), "\n")

    # Calculate response counts
    cat("DEBUG: Starting group_by and summarise...\n")
    response_counts <- tryCatch({
      foo %>%
        dplyr::group_by(pid, record_id) %>%
        dplyr::summarise(
          months = dplyr::first(months),
          `Total Responses` = dplyr::n(),
          `No/Never` = sum(value == 0, na.rm = TRUE),
          `Yes/Sometimes+` = sum(value > 0 & value < 9, na.rm = TRUE),
          `Don't Know` = sum(value == 9, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        dplyr::mutate(`Net Responses` = `Total Responses` - `Don't Know`)
    }, error = function(e) {
      cat("DEBUG: Error in response_counts calculation:", e$message, "\n")
      cat("DEBUG: Error call:", deparse(e$call), "\n")
      stop(e)
    })

    cat("DEBUG: response_counts completed successfully\n")
    cat("DEBUG: response_counts dimensions:", nrow(response_counts), "x", ncol(response_counts), "\n")

    # Prepare data for IRT analysis
    cat("DEBUG: Starting tmp data preparation...\n")
    tmp <- data %>%
      dplyr::rename(days = age_in_days) %>%
      dplyr::select(pid, record_id, days, dplyr::any_of(codebook$lex_ne25))

    cat("After data preparation:\n")
    cat("tmp dimensions:", nrow(tmp), "x", ncol(tmp), "\n")
    cat("tmp columns:", paste(names(tmp)[1:min(10, ncol(tmp))], collapse=", "),
        if(ncol(tmp) > 10) "..." else "", "\n")

    # Convert to long format for IRT
    cat("DEBUG: Starting pivot_longer and joins...\n")
    long <- tmp %>%
      tidyr::pivot_longer(4:ncol(tmp), names_to = "lex_ne25") %>%
      stats::na.omit() %>%
      dplyr::left_join(codebook, by = "lex_ne25") %>%
      dplyr::mutate(
        years = days/365.25,
        months = floor(12*(days/365.25))
      ) %>%
      dplyr::relocate(pid, record_id, years, months, days, item_order, lex_ne25, value)

    cat("DEBUG: Long format completed. Dimensions:", nrow(long), "x", ncol(long), "\n")

    # Create wide format for IRT analysis
    cat("DEBUG: Starting wide format creation...\n")
    cat("DEBUG: Long data already has these columns:", paste(names(long), collapse=", "), "\n")
    cat("DEBUG: Does long data have lex_kidsight?", "lex_kidsight" %in% names(long), "\n")

    # Use the existing lex_kidsight column from long data (already joined earlier)
    wide <- long %>%
      dplyr::filter(value != 9) %>%  # Remove "Don't know" responses
      dplyr::select(pid:record_id, years, dplyr::any_of(c("lex_kidsight", "lex_kidsights")), value)

    cat("DEBUG: Wide data prepared. Columns:", paste(names(wide), collapse=", "), "\n")
    cat("DEBUG: Wide dimensions:", nrow(wide), "x", ncol(wide), "\n")

    # Check if we have any lex_kidsight values
    if ("lex_kidsight" %in% names(wide)) {
      cat("DEBUG: lex_kidsight values found:", sum(!is.na(wide$lex_kidsight)), "out of", nrow(wide), "\n")
      cat("DEBUG: Sample lex_kidsight values:", paste(head(unique(wide$lex_kidsight), 5), collapse=", "), "\n")
    }

    # Determine which column to use for pivot_wider and do the operation
    cat("DEBUG: About to determine pivot column...\n")
    if ("lex_kidsight" %in% names(wide)) {
      cat("DEBUG: Using lex_kidsight for pivot_wider...\n")
      input <- tryCatch({
        wide %>% tidyr::pivot_wider(names_from = lex_kidsight, values_from = value)
      }, error = function(e) {
        cat("DEBUG: Error in pivot_wider with lex_kidsight:", e$message, "\n")
        cat("DEBUG: Error call:", deparse(e$call), "\n")
        stop(e)
      })
    } else if ("lex_kidsights" %in% names(wide)) {
      cat("DEBUG: Using lex_kidsights for pivot_wider...\n")
      input <- tryCatch({
        wide %>% tidyr::pivot_wider(names_from = lex_kidsights, values_from = value)
      }, error = function(e) {
        cat("DEBUG: Error in pivot_wider with lex_kidsights:", e$message, "\n")
        cat("DEBUG: Error call:", deparse(e$call), "\n")
        stop(e)
      })
    } else {
      # Fallback: no pivot if column not found
      cat("Warning: Neither lex_kidsight nor lex_kidsights found in data\n")
      input <- wide
    }

    cat("DEBUG: Pivot_wider completed successfully\n")
    cat("DEBUG: Input dimensions after pivot:", nrow(input), "x", ncol(input), "\n")

    # Debug: Show what columns we actually have after pivot
    cat("DEBUG: Column names after pivot (first 20):", paste(head(names(input), 20), collapse=", "), "\n")
    cat("DEBUG: Columns starting with 'AA':", paste(names(input)[grepl("^AA", names(input))][1:5], collapse=", "), "\n")
    cat("DEBUG: Columns starting with 'BB':", paste(names(input)[grepl("^BB", names(input))][1:5], collapse=", "), "\n")
    cat("DEBUG: Columns starting with 'CC':", paste(names(input)[grepl("^CC", names(input))][1:5], collapse=", "), "\n")
    cat("DEBUG: Columns starting with 'DD':", paste(names(input)[grepl("^DD", names(input))][1:5], collapse=", "), "\n")

    # Store the pivoted data with item columns
    pivoted_data <- input

    # Combine with calibration data if available
    if(!is.null(calibdat)) {
      input <- calibdat %>%
        dplyr::bind_rows(pivoted_data %>% dplyr::mutate(study = "NE25")) %>%
        dplyr::relocate(id, pid, record_id, years)
    } else {
      # If no calibration data, use NE25 data only
      input <- pivoted_data %>%
        dplyr::mutate(study = "NE25", id = dplyr::row_number()) %>%
        dplyr::relocate(id, pid, record_id, years)
    }

    # Identify items for IRT fitting
    # Look for items in the final input data which should have the item columns
    items_to_fit <- names(input %>% dplyr::select(dplyr::starts_with("AA"), dplyr::starts_with("BB"),
                           dplyr::starts_with("CC"), dplyr::starts_with("DD")))

    cat("Items to fit:", length(items_to_fit), "\n")
    cat("First 5 items:", paste(utils::head(items_to_fit, 5), collapse=", "), "\n")
    cat("Contains 'days'?", "days" %in% items_to_fit, "\n")
    cat("Contains 'age_in_days'?", "age_in_days" %in% items_to_fit, "\n")

    # Quality checks for items
    if(length(items_to_fit) > 0) {
      cat("DEBUG: Starting quality checks for", length(items_to_fit), "items...\n")

      Kobs <- base::apply(input %>% dplyr::select(dplyr::any_of(items_to_fit)), 2,
                   function(x) length(base::unique(x[!is.na(x)])))
      SDobs <- base::apply(input %>% dplyr::select(dplyr::any_of(items_to_fit)), 2,
                    function(x) stats::sd(x, na.rm = TRUE))
      Nobs <- base::apply(input %>% dplyr::select(dplyr::any_of(items_to_fit)), 2,
                   function(x) length(x[!is.na(x)]))
      MINobs <- base::apply(input %>% dplyr::select(dplyr::any_of(items_to_fit)), 2,
                     function(x) base::min(x, na.rm = TRUE))

      cat("DEBUG: Quality stats for first 5 items:\n")
      for(i in 1:min(5, length(items_to_fit))) {
        item <- items_to_fit[i]
        cat(sprintf("  %s: Kobs=%d, SDobs=%.3f, Nobs=%d, MINobs=%.1f\n",
                    item, Kobs[item], SDobs[item], Nobs[item], MINobs[item]))
      }

      # Apply quality filters
      quality_pass <- Kobs > 1 & SDobs > 0.05 & Nobs >= 30 & MINobs == 0
      cat("DEBUG: Quality filter results:\n")
      cat("  Kobs > 1:", sum(Kobs > 1), "items\n")
      cat("  SDobs > 0.05:", sum(SDobs > 0.05), "items\n")
      cat("  Nobs >= 30:", sum(Nobs >= 30), "items\n")
      cat("  MINobs == 0:", sum(MINobs == 0, na.rm = TRUE), "items\n")
      cat("  All criteria met:", sum(quality_pass), "items\n")

      items_to_fit <- names(Kobs)[quality_pass]
    }

    if(length(items_to_fit) < 5) {
      base::warning("Insufficient items for IRT analysis. Using simplified CID8 scoring.")

      # Fallback to simple scoring
      df <- data %>%
        dplyr::select(pid, record_id) %>%
        dplyr::left_join(response_counts %>% dplyr::select(pid, record_id, `Net Responses`),
                 by = c("pid", "record_id")) %>%
        dplyr::mutate(
          net_responses = base::ifelse(is.na(`Net Responses`), 0, `Net Responses`),
          pass_cid8 = (net_responses >= 10)
        ) %>%
        dplyr::select(pid, record_id, pass_cid8, net_responses)

      return(df)
    }

    # Prepare input for IRT
    input <- input %>% dplyr::select(id:study, dplyr::any_of(items_to_fit))

    # Handle polytomous items
    Kobs <- base::apply(input %>% dplyr::select(dplyr::any_of(items_to_fit)), 2,
                 function(x) length(base::unique(x[!is.na(x)])))

    if(base::any(Kobs > 2)) {
      polytomous_df <- base::sapply(items_to_fit[Kobs > 2], function(item) {
        y <- input[[item]]
        K <- base::max(y, na.rm = TRUE)
        out <- base::matrix(0, nrow = length(y), ncol = K)
        for(k in 1:K) {
          out[y >= k, k] <- 1.0
          out[is.na(y), k] <- NA
        }
        out <- base::data.frame(out)
        names(out) <- base::paste0(item, "_", 1:K)
        return(out)
      }, simplify = FALSE) %>% dplyr::bind_cols()

      input <- input %>%
        dplyr::select(-dplyr::any_of(items_to_fit[Kobs > 2])) %>%
        dplyr::bind_cols(polytomous_df)

      items_to_fit <- names(input)[base::startsWith(names(input), "AA") |
                                 base::startsWith(names(input), "BB") |
                                 base::startsWith(names(input), "CC") |
                                 base::startsWith(names(input), "DD")]
    }

    # Pairwise IRT analysis
    if("pairwise" %in% base::loadedNamespaces() && length(items_to_fit) >= 5) {
      cat("About to call pairwise::pair\n")
      irt_data <- input %>% dplyr::select(dplyr::any_of(items_to_fit))
      cat("Input data for IRT:", nrow(irt_data), "rows x", ncol(irt_data), "columns\n")
      cat("Column names:", paste(names(irt_data)[1:base::min(5, ncol(irt_data))], collapse=", "),
          if(ncol(irt_data) > 5) "..." else "", "\n")

      fit_pair <- pairwise::pair(
        daten = irt_data,
        likelihood = "minchi"
      )

      tholds <- fit_pair$threshold %>%
        base::data.frame() %>%
        stats::setNames("hat") %>%
        dplyr::mutate(
          item = base::row.names(.),
          name = "d",
          hat = -hat
        )
    } else {
      tholds <- base::data.frame(item = base::character(), name = base::character(), hat = base::numeric())
    }

    # MIRT analysis
    if("mirt" %in% base::loadedNamespaces() && length(items_to_fit) >= 5) {
      # Get initial parameters
      pars0 <- mirt::mirt(
        data = input %>% dplyr::select(dplyr::any_of(items_to_fit)),
        model = 1,
        covdata = input %>% dplyr::select(years),
        formula = ~ log(years + 0.1),
        pars = "value"
      ) %>%
        dplyr::left_join(tholds, by = c("item", "name")) %>%
        dplyr::mutate(
          value = base::ifelse(!is.na(hat), hat, value),
          est = base::ifelse(!is.na(hat), FALSE, est)
        ) %>%
        dplyr::mutate(est = base::ifelse(item %in% c("GROUP", "BETA"), TRUE, est)) %>%
        dplyr::mutate(
          value = base::ifelse(name == "a1", 1.0, value),
          est = base::ifelse(name == "a1", FALSE, est)
        ) %>%
        dplyr::select(-hat)

      # Fit final model
      fit_kidsights2 <- mirt::mirt(
        data = input %>% dplyr::select(dplyr::any_of(items_to_fit)),
        model = 1,
        quadpts = 61*2,
        large = FALSE,
        TOL = 1E-3,
        covdata = input %>% dplyr::select("years"),
        formula = ~ log(years + 0.1),
        pars = pars0,
        technical = base::list(theta_lim = c(-15, 15), NCYCLES = 10000)
      )

      # Extract theta scores
      input <- input %>%
        dplyr::mutate(theta = base::as.numeric(mirt::fscores(fit_kidsights2, theta_lim = c(-15, 15))))

      # Fit age-adjustment model using non-NE25 data if available
      if(!is.null(calibdat)) {
        input_gamlss <- input %>%
          filter(study != "NE25") %>%
          select(years, theta) %>%
          mutate(across(everything(), function(x) {
            x %>% haven::zap_formats() %>% haven::zap_label() %>%
              haven::zap_labels() %>% haven::zap_missing()
          }))

        if(nrow(input_gamlss) > 50) {
          fit_lm <- lm(theta ~ log(years + 0.1) + years, data = input_gamlss)
          sigma_hat <- sd(fit_lm$residuals)
        } else {
          # Fallback if insufficient calibration data
          fit_lm <- lm(theta ~ log(years + 0.1) + years, data = input)
          sigma_hat <- sd(fit_lm$residuals)
        }
      } else {
        # Use all data if no calibration data
        fit_lm <- lm(theta ~ log(years + 0.1) + years, data = input)
        sigma_hat <- sd(fit_lm$residuals)
      }

      # Calculate z-scores
      input <- input %>%
        mutate(
          mu = predict(fit_lm, newdata = input),
          sigma = sigma_hat,
          zscore = (theta - mu) / sigma
        )

      # Join with response counts
      response_counts <- response_counts %>%
        left_join(
          input %>%
            filter(study == "NE25") %>%
            select(pid, record_id, zscore),
          by = c("pid", "record_id")
        )

      # Final CID8 determination
      df <- data %>%
        select(pid, record_id) %>%
        left_join(
          response_counts %>% select(pid, record_id, `Net Responses`, zscore),
          by = c("pid", "record_id")
        ) %>%
        mutate(
          net_responses = ifelse(is.na(`Net Responses`), 0, `Net Responses`),
          pass_cid8 = (net_responses >= 10 & abs(zscore) < 5)
        ) %>%
        select(pid, record_id, pass_cid8, net_responses, zscore)

    } else {
      warning("MIRT package not available. Using simplified CID8 scoring.")

      # Fallback scoring
      df <- data %>%
        select(pid, record_id) %>%
        left_join(response_counts %>% select(pid, record_id, `Net Responses`),
                 by = c("pid", "record_id")) %>%
        mutate(
          net_responses = ifelse(is.na(`Net Responses`), 0, `Net Responses`),
          pass_cid8 = (net_responses >= 10)
        ) %>%
        select(pid, record_id, pass_cid8, net_responses)
    }

    return(df)

  }, error = function(e) {
    cat("ACTUAL ERROR in CID8:", e$message, "\n")
    cat("Error call:", if(!is.null(e$call)) deparse(e$call) else "No call info", "\n")
    warning("CID8 IRT analysis failed: ", e$message, ". Using simplified scoring.")

    # Fallback to simple response count only
    simple_result <- data %>%
      select(pid, record_id) %>%
      mutate(
        pass_cid8 = FALSE,  # Conservative fallback
        net_responses = 0,
        error_message = e$message
      )

    return(simple_result)
  })
}

#' Check CID9: Survey completion
#'
#' Validates that all required survey modules were completed
#' (ported from Dashboard version)
#'
#' @param data Data frame with completion status fields
#' @return Data frame with CID9 pass/fail status
check_cid9_completion <- function(data) {

  # Dashboard implementation: looks for module_2 through module_9 completion
  tmp <- data %>%
    select(pid, record_id, starts_with("module_"))

  # Convert to long format
  tmp <- tmp %>%
    tidyr::pivot_longer(
      cols = contains("_complete"),
      names_to = "name",
      values_to = "value"
    ) %>%
    mutate(module = as.integer(stringr::str_extract(name, "(?<=module_)\\d+"))) %>%
    group_by(pid, record_id, module) %>%
    reframe(value = max(value, na.rm = TRUE))

  # Get rid of follow up information (module 8)
  tmp <- tmp %>% filter(module != 8)

  # Convert back to wide format
  tmp <- tmp %>%
    mutate(
      module = paste("module", module, sep = "_"),
      value = as.integer(value == 2)  # 2 = Complete in REDCap
    ) %>%
    tidyr::pivot_wider(names_from = module, values_from = value)

  # Check completion
  df <- tmp %>%
    rowwise() %>%
    dplyr::mutate(
      pass_cid9 = ifelse(
        all(c("module_2", "module_3", "module_4", "module_5",
              "module_6", "module_7", "module_9") %in% names(.)),
        mean(c_across(module_2:module_9), na.rm = TRUE) == 1,
        FALSE
      )
    ) %>%
    ungroup() %>%
    select(pid, record_id, pass_cid9)

  return(df)
}

#' Master eligibility checking function
#'
#' Applies all 9 eligibility criteria and generates summary
#'
#' @param data Raw NE25 survey data
#' @param data_dictionary REDCap data dictionary
#' @param codebook Codebook data frame with item mappings
#' @param calibdat Optional calibration dataset for IRT analysis
#' @return List with eligibility summary and details
check_ne25_eligibility <- function(data, data_dictionary, codebook, calibdat = NULL) {

  # Apply all eligibility checks
  cid_results <- data %>%
    select(pid, record_id, retrieved_date) %>%
    left_join(check_cid1_compensation(data), by = c("pid", "record_id")) %>%
    left_join(check_cid2_consent(data), by = c("pid", "record_id")) %>%
    left_join(check_cid3_caregiver(data), by = c("pid", "record_id")) %>%
    left_join(check_cid4_child_age(data), by = c("pid", "record_id")) %>%
    left_join(check_cid5_nebraska(data), by = c("pid", "record_id")) %>%
    left_join(check_cid6_zip_county(data, data_dictionary), by = c("pid", "record_id")) %>%
    left_join(check_cid7_birthday(data), by = c("pid", "record_id")) %>%
    left_join(check_cid8_kmt_quality(data, codebook, calibdat), by = c("pid", "record_id")) %>%
    left_join(check_cid9_completion(data), by = c("pid", "record_id"))

  # Convert to long format for detailed analysis
  eligibility_long <- cid_results %>%
    tidyr::pivot_longer(
      cols = starts_with("pass_cid"),
      names_to = "cid",
      values_to = "pass"
    ) %>%
    mutate(
      cid_number = as.integer(str_extract(cid, "\\d+"))
    ) %>%
    left_join(
      get_eligibility_criteria_definitions(),
      by = c("cid_number" = "cid")
    )

  # Create summary by category
  eligibility_summary <- eligibility_long %>%
    group_by(retrieved_date, pid, record_id, category) %>%
    summarise(
      status = ifelse(all(pass, na.rm = TRUE), "Pass", "Fail"),
      .groups = "drop"
    ) %>%
    tidyr::pivot_wider(
      names_from = category,
      values_from = status
    ) %>%
    rename_with(tolower) %>%
    relocate(retrieved_date, pid, record_id, eligibility, authenticity, compensation)

  # Get mailing addresses for eligible participants
  mailing_info <- data %>%
    select(pid, record_id, matches("q139[4-8]")) # q1394:q1398

  return(list(
    summary = eligibility_summary,
    details = eligibility_long,
    mailing = mailing_info,
    criteria_definitions = get_eligibility_criteria_definitions()
  ))
}

#' Apply eligibility results to dataset
#'
#' Adds eligibility flags to the main dataset
#'
#' @param data Main NE25 dataset
#' @param eligibility_results Results from check_ne25_eligibility()
#' @return Data frame with eligibility columns added
apply_ne25_eligibility <- function(data, eligibility_results) {
  cat("\n=== APPLY_NE25_ELIGIBILITY DEBUG ===\n")
  cat("Input data dimensions:", nrow(data), "x", ncol(data), "\n")
  cat("Data columns (first 10):", paste(head(names(data), 10), collapse=", "), "\n")

  cat("Eligibility results structure:\n")
  cat("- Names:", paste(names(eligibility_results), collapse=", "), "\n")

  if (!is.null(eligibility_results$summary)) {
    cat("Summary dimensions:", nrow(eligibility_results$summary), "x", ncol(eligibility_results$summary), "\n")
    cat("Summary columns:", paste(names(eligibility_results$summary), collapse=", "), "\n")
  } else {
    cat("WARNING: eligibility_results$summary is NULL\n")
  }

  cat("Attempting left join...\n")
  data_with_eligibility <- tryCatch({
    data %>%
      dplyr::left_join(
        eligibility_results$summary,
        by = c("retrieved_date", "pid", "record_id")
      ) %>%
      dplyr::mutate(
        # Overall inclusion flag
        eligible = eligibility == "Pass",
        authentic = authenticity == "Pass",
        include = eligible & authentic
      )
  }, error = function(e) {
    cat("ERROR in apply_ne25_eligibility:\n")
    cat("- Message:", e$message, "\n")
    cat("- Call:", deparse(e$call), "\n")
    stop(e)
  })

  cat("Apply eligibility completed. Result dimensions:", nrow(data_with_eligibility), "x", ncol(data_with_eligibility), "\n")
  return(data_with_eligibility)
}

#' Filter data to include only eligible participants
#'
#' @param data Data frame with eligibility flags
#' @return Filtered data frame
filter_eligible_ne25 <- function(data) {
  data %>%
    filter(eligibility == "Pass", authenticity == "Pass")
}

# Helper functions

#' Extract value labels from REDCap data dictionary
#'
#' @param field_name Field name to extract labels for
#' @param dictionary REDCap data dictionary
#' @return Data frame with value and label columns
extract_value_labels <- function(field_name, dictionary) {

  cat("=== EXTRACT_VALUE_LABELS DEBUG ===\n")
  cat("Field name:", field_name, "\n")
  cat("Dictionary names (first 5):", paste(head(names(dictionary), 5), collapse=", "), "\n")

  # Save test data for rapid debugging
  test_data_dir <- "temp/value_labels_test_data"
  if (!dir.exists(test_data_dir)) dir.create(test_data_dir, recursive = TRUE)

  saveRDS(field_name, file.path(test_data_dir, "field_name.rds"))
  saveRDS(dictionary, file.path(test_data_dir, "dictionary.rds"))
  cat("Value labels test data saved to:", test_data_dir, "\n")

  if (!field_name %in% names(dictionary)) {
    warning(paste("Field", field_name, "not found in dictionary"))
    return(data.frame(value = character(), label = character()))
  }

  choices_string <- dictionary[[field_name]]$select_choices_or_calculations
  cat("Choices string type:", class(choices_string), "\n")
  cat("Choices string length:", length(choices_string), "\n")
  cat("Choices string content (first 100 chars):", substr(paste(choices_string, collapse=" | "), 1, 100), "\n")

  if (is.null(choices_string) || all(choices_string == "")) {
    return(data.frame(value = character(), label = character()))
  }

  # Parse choices string (format: "1, Choice 1 | 2, Choice 2")
  cat("About to call str_split_1 with choices_string...\n")
  choices <- tryCatch({
    stringr::str_split_1(choices_string, " \\| ")
  }, error = function(e) {
    cat("ERROR in str_split_1:", e$message, "\n")
    cat("Choices string causing error:", choices_string, "\n")
    stop(e)
  })

  result <- data.frame(value = character(), label = character())

  for (choice in choices) {
    cat("Processing choice:", choice, "\n")
    parts <- tryCatch({
      stringr::str_split_1(choice, ", ")
    }, error = function(e) {
      cat("ERROR in str_split_1 for choice:", choice, "\n")
      cat("Error message:", e$message, "\n")
      stop(e)
    })
    if (length(parts) >= 2) {
      value <- parts[1]
      label <- paste(parts[-1], collapse = ", ")
      result <- rbind(result, data.frame(value = value, label = label))
    }
  }

  return(result)
}

#' Get Nebraska ZIP code to county crosswalk
#'
#' @return Data frame mapping ZIP codes to acceptable counties
get_nebraska_zip_county_crosswalk <- function() {
  # This would typically read from a reference file
  # Placeholder implementation
  data.frame(
    zip_code = c("68001", "68101", "68503"),
    acceptable_counties = c("Douglas; Sarpy", "Douglas", "Lancaster"),
    stringsAsFactors = FALSE
  )
}

#' Get KMT items from configuration
#'
#' @param config Configuration list
#' @return Vector of KMT field names
get_kmt_items_from_config <- function(config) {
  # This would extract KMT field names from configuration
  # Placeholder implementation
  paste0("kmt_", sprintf("%03d", 1:30))
}

#' Get eligibility criteria definitions (matching Dashboard categorization)
#'
#' @return Data frame with criteria definitions
get_eligibility_criteria_definitions <- function() {

  definitions <- data.frame(
    cid = 1:9,
    category = c("Compensation", "Eligibility", "Eligibility", "Eligibility",
                 "Eligibility", "Authenticity", "Authenticity", "Authenticity",
                 "Compensation"),
    action = c("Exclusion", "Exclusion", "Inclusion", "Inclusion", "Inclusion",
               "Exclusion", "Exclusion", "Exclusion", "Exclusion"),
    description = c(
      "Failed to acknowledge compensation terms and conditions",
      "Failed to provide informed consent",
      "Respondent is 19 years or older and a primary caregiver",
      "Child is 2191 days or younger",
      "Currently lives in the state of Nebraska",
      "ZIP code does not match reported county",
      "Child's birthday failed to be confirmed",
      "Less than 10 valid KMT responses or z-score outside 5SD",
      "Did not complete all required modules of survey"
    ),
    stringsAsFactors = FALSE
  )

  return(definitions)
}

#' Load Kidsights ZIP code data
#'
#' Loads the ZIP code to county crosswalk data
#' @param data_dir Directory containing ZIP code data file
#' @return Data frame with ZIP codes and acceptable counties
load_kidsights_zip_data <- function(data_dir = "data") {

  zip_file <- file.path(data_dir, "Zip_County_Code_UPDATED10.18.xlsx")

  if(file.exists(zip_file) && "readxl" %in% loadedNamespaces()) {
    tryCatch({
      zipcodes_df <- readxl::read_excel(
        path = zip_file,
        sheet = "Master"
      ) %>%
        mutate(County = stringr::str_remove_all(County, " County")) %>%
        group_by(ZipCode) %>%
        reframe(acceptable_counties = paste(County, collapse = "; ")) %>%
        mutate(ZipCode = as.character(ZipCode))

      return(zipcodes_df)
    }, error = function(e) {
      warning("Could not load ZIP code data: ", e$message)
      return(get_nebraska_zip_county_crosswalk())
    })
  } else {
    if(!file.exists(zip_file)) {
      warning("ZIP code data file not found: ", zip_file)
    }
    return(get_nebraska_zip_county_crosswalk())
  }
}