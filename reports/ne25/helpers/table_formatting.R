# Table formatting utilities for criterion validity report
# Creates APA-style coefficient tables

#' Format Criterion-Specific Table
#'
#' Create table showing associations for ONE criterion across BOTH outcomes
#'
#' @param pooled_results Named list of pooled results from pool_all_models()
#' @param criterion Character, criterion variable name (e.g., "fpl")
#' @param outcomes Character vector of outcome names (e.g., c("kidsights_2022", "general_gsed_pf_2022"))
#' @param digits Number of decimal places for coefficients/SEs. Default: 3
#' @param include_fit_stats Logical, include R² and N rows. Default: TRUE
#' @return data.frame formatted for knitr::kable()
#'
#' @details
#' Creates a table with predictors in rows and outcomes in columns.
#' Each cell shows "b (SE)" format for easy reading.
#'
#' @export
format_criterion_table <- function(pooled_results, criterion, outcomes,
                                   digits = 3, include_fit_stats = TRUE) {
  # Source helper functions if not loaded
  if (!exists("get_outcome_label", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }

  # Build predictor names and coefficient mappings based on criterion type
  if (criterion == "educ4_a1") {
    # Categorical caregiver education (4 levels, Bachelor+ is reference)
    predictor_names <- c(
      "Intercept",
      "log(years_old + 1)",
      "Female",
      "years_old",
      "Caregiver Educ: <HS (vs Bachelor+)",
      "Caregiver Educ: HS (vs Bachelor+)",
      "Caregiver Educ: Some College (vs Bachelor+)",
      "Age × Female",
      "Age × Caregiver Educ: <HS",
      "Age × Caregiver Educ: HS",
      "Age × Caregiver Educ: Some College"
    )

    coef_map <- c(
      "Intercept" = "(Intercept)",
      "log(years_old + 1)" = "log(years_old + 1)",
      "Female" = "female",
      "years_old" = "years_old",
      "Caregiver Educ: <HS (vs Bachelor+)" = "educ4_a1Less than High School Graduate",
      "Caregiver Educ: HS (vs Bachelor+)" = "educ4_a1High School Graduate (including Equivalency)",
      "Caregiver Educ: Some College (vs Bachelor+)" = "educ4_a1Some College or Associate's Degree",
      "Age × Female" = "female:years_old",
      "Age × Caregiver Educ: <HS" = "years_old:educ4_a1Less than High School Graduate",
      "Age × Caregiver Educ: HS" = "years_old:educ4_a1High School Graduate (including Equivalency)",
      "Age × Caregiver Educ: Some College" = "years_old:educ4_a1Some College or Associate's Degree"
    )
  } else if (criterion == "fpl") {
    # FPL: log-transformed
    predictor_names <- c(
      "Intercept",
      "log(years_old + 1)",
      "Female",
      "years_old",
      "log(FPL + 1)",
      "Age × Female",
      "Age × log(FPL + 1)"
    )

    coef_map <- c(
      "Intercept" = "(Intercept)",
      "log(years_old + 1)" = "log(years_old + 1)",
      "Female" = "female",
      "years_old" = "years_old",
      "log(FPL + 1)" = "log(fpl + 1)",
      "Age × Female" = "female:years_old",
      "Age × log(FPL + 1)" = "years_old:log(fpl + 1)"
    )
  } else {
    # Default: continuous criterion (urban_pct, phq2_total)
    predictor_names <- c(
      "Intercept",
      "log(years_old + 1)",
      "Female",
      "years_old",
      sprintf("%s", criterion),
      "Age × Female",
      sprintf("Age × %s", criterion)
    )

    coef_map <- c(
      "Intercept" = "(Intercept)",
      "log(years_old + 1)" = "log(years_old + 1)",
      "Female" = "female",
      "years_old" = "years_old",
      "Age × Female" = "female:years_old"
    )
    coef_map[sprintf("%s", criterion)] <- criterion
    coef_map[sprintf("Age × %s", criterion)] <- sprintf("years_old:%s", criterion)
  }

  table_df <- data.frame(
    Predictor = predictor_names,
    stringsAsFactors = FALSE
  )

  # Extract coefficients for each outcome
  for (outcome in outcomes) {
    # Get pooled result for this outcome-criterion combination
    model_key <- paste0(outcome, "_", criterion)
    pooled <- pooled_results[[model_key]]

    # Get coefficients, SEs, and p-values
    coefs <- pooled$coefficients
    ses <- pooled$se
    pvals <- pooled$p_values

    # Helper function to get significance stars
    get_sig_stars <- function(p) {
      if (is.na(p)) return("")
      if (p < 0.001) return("***")
      if (p < 0.01) return("**")
      if (p < 0.05) return("*")
      return("")
    }

    # Extract values and format as "b (SE)" with significance stars
    formatted_values <- sapply(predictor_names, function(pred) {
      coef_name <- coef_map[[pred]]
      if (coef_name %in% names(coefs)) {
        b <- coefs[[coef_name]]
        se <- ses[[coef_name]]
        p <- pvals[[coef_name]]
        stars <- get_sig_stars(p)
        sprintf("%.*f (%.*f)%s", digits, b, digits, se, stars)
      } else {
        "-"  # Missing coefficient
      }
    })

    # Add column with outcome label
    outcome_label <- get_outcome_label(outcome)
    table_df[[outcome_label]] <- formatted_values
  }

  # Add fit statistics if requested
  if (include_fit_stats) {
    # Get fit stats from first outcome (representative, using imputation 1)
    model_key_first <- paste0(outcomes[1], "_", criterion)

    # Extract from original model list (need to pass this through)
    # For now, we'll add empty rows and fill them separately
    # This will be handled in the main report where we have access to all_models

    # Add placeholder rows
    fit_rows <- data.frame(
      Predictor = c("**R²**", "**Adjusted R²**", "**N**"),
      stringsAsFactors = FALSE
    )

    # Add empty columns for outcomes (to be filled later)
    for (outcome in outcomes) {
      outcome_label <- get_outcome_label(outcome)
      fit_rows[[outcome_label]] <- c("", "", "")  # Placeholder
    }

    table_df <- rbind(table_df, fit_rows)
  }

  return(table_df)
}


#' Add Fit Statistics to Criterion Table
#'
#' Add R², Adjusted R², and N rows to a criterion table
#'
#' @param table_df Output from format_criterion_table()
#' @param all_models Output from fit_all_models() (contains model lists)
#' @param criterion Character, criterion variable name
#' @param outcomes Character vector of outcome names
#' @param digits Number of decimal places for R². Default: 3
#' @return data.frame with fit statistics added
#'
#' @export
add_fit_stats_to_table <- function(table_df, all_models, criterion, outcomes, digits = 3) {
  # Source helper if not loaded
  if (!exists("extract_fit_stats", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }
  if (!exists("get_outcome_label", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }

  # Find fit stat rows (identified by ** markers)
  fit_row_indices <- grep("\\*\\*", table_df$Predictor)

  if (length(fit_row_indices) == 0) {
    # No fit stat rows to fill
    return(table_df)
  }

  # Extract fit stats for each outcome
  for (outcome in outcomes) {
    model_key <- paste0(outcome, "_", criterion)
    model_list <- all_models[[model_key]]

    # Extract fit statistics
    fit_stats <- extract_fit_stats(model_list, use_imputation = 1)

    # Get column name
    outcome_label <- get_outcome_label(outcome)

    # Fill in values
    table_df[fit_row_indices[1], outcome_label] <- sprintf("%.*f", digits, fit_stats$r_squared)
    table_df[fit_row_indices[2], outcome_label] <- sprintf("%.*f", digits, fit_stats$adj_r_squared)
    table_df[fit_row_indices[3], outcome_label] <- as.character(fit_stats$n)
  }

  return(table_df)
}


#' Format All Criterion Tables
#'
#' Create formatted tables for all criterion variables
#'
#' @param pooled_results Output from pool_all_models()
#' @param all_models Output from fit_all_models()
#' @param criteria Character vector of criterion variable names
#' @param outcomes Character vector of outcome names
#' @param digits Number of decimal places. Default: 3
#' @return Named list of formatted tables (one per criterion)
#'
#' @export
format_all_criterion_tables <- function(pooled_results, all_models, criteria, outcomes, digits = 3) {
  tables <- list()

  for (criterion in criteria) {
    # Create base table
    table_df <- format_criterion_table(
      pooled_results = pooled_results,
      criterion = criterion,
      outcomes = outcomes,
      digits = digits,
      include_fit_stats = TRUE
    )

    # Add fit statistics
    table_df <- add_fit_stats_to_table(
      table_df = table_df,
      all_models = all_models,
      criterion = criterion,
      outcomes = outcomes,
      digits = digits
    )

    # Store with criterion name as key
    tables[[criterion]] <- table_df
  }

  return(tables)
}


#' Format Fit Summary Table
#'
#' Create summary table of fit statistics for all models
#'
#' @param all_models Output from fit_all_models()
#' @param outcomes Character vector of outcome names
#' @param criteria Character vector of criterion names
#' @param digits Number of decimal places. Default: 3
#' @return data.frame formatted for knitr::kable()
#'
#' @export
format_fit_summary_table <- function(all_models, outcomes, criteria, digits = 3) {
  # Source helper if not loaded
  if (!exists("create_fit_summary_table", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }
  if (!exists("get_criterion_label", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }
  if (!exists("get_outcome_label", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }

  # Get raw fit summary
  fit_df <- create_fit_summary_table(all_models, outcomes, criteria)

  # Format labels
  fit_df$Outcome <- sapply(fit_df$Outcome, get_outcome_label)
  fit_df$Criterion <- sapply(fit_df$Criterion, get_criterion_label)

  # Round numeric columns and convert to character for kable
  # Handle NA values explicitly
  fit_df$`R²` <- ifelse(is.na(fit_df$`R²`), "NA", sprintf("%.*f", digits, fit_df$`R²`))
  fit_df$`Adjusted R²` <- ifelse(is.na(fit_df$`Adjusted R²`), "NA", sprintf("%.*f", digits, fit_df$`Adjusted R²`))

  # Convert N to character to avoid kable rounding issues
  fit_df$N <- as.character(fit_df$N)

  return(fit_df)
}


#' Render Table with kableExtra
#'
#' Apply kableExtra styling to a formatted table
#'
#' @param table_df data.frame from format_criterion_table() or similar
#' @param caption Character, table caption
#' @param bootstrap_options Character vector of bootstrap options. Default: c("striped", "hover")
#' @param add_sig_note Logical, add significance stars footnote. Default: TRUE
#' @return kableExtra HTML table object
#'
#' @export
render_table <- function(table_df, caption = NULL, bootstrap_options = c("striped", "hover"), add_sig_note = TRUE) {
  # Create kable
  tbl <- knitr::kable(
    table_df,
    caption = caption,
    digits = NULL,  # Already formatted as strings
    format = "html",
    escape = FALSE,  # Allow ** for bold in Predictor column
    align = c("l", rep("r", ncol(table_df) - 1))  # Left-align predictors, right-align values
  )

  # Apply kableExtra styling
  tbl <- kableExtra::kable_styling(
    tbl,
    bootstrap_options = bootstrap_options,
    full_width = FALSE,
    position = "left"
  )

  # Add significance footnote if requested
  if (add_sig_note) {
    tbl <- kableExtra::footnote(
      tbl,
      general = "* p < 0.05, ** p < 0.01, *** p < 0.001",
      general_title = "Note:",
      footnote_as_chunk = TRUE
    )
  }

  return(tbl)
}


#' Get Criterion Table Caption
#'
#' Generate caption for criterion-specific table
#'
#' @param criterion Character, criterion variable name
#' @param table_number Integer, table number
#' @return Character, formatted caption
#'
#' @export
get_criterion_table_caption <- function(criterion, table_number = NULL) {
  # Source helper if not loaded
  if (!exists("get_criterion_label", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "model_fitting.R"))
  }

  criterion_label <- get_criterion_label(criterion)

  if (!is.null(table_number)) {
    sprintf("Table %d: Associations with %s", table_number, criterion_label)
  } else {
    sprintf("Associations with %s", criterion_label)
  }
}
