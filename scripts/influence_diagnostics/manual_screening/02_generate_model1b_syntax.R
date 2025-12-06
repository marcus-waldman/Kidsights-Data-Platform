#!/usr/bin/env Rscript

#' Generate Mplus Model 1b Input Syntax
#'
#' Creates Mplus .inp syntax for Model 1b: FREE loadings within domain with
#' N(0,1) priors, using Model 1a starting values.
#'
#' Model Specification:
#'   - 2-parameter IRT with logit link (graded response model)
#'   - FREE loadings within domain (each item gets unique label: a001, a002, ... b001, b002, ...)
#'   - N(0,1) priors on all loadings
#'   - Latent regression: F ~ female + years + female×years + log(years)
#'   - Identification: Factor variances fixed to 1, means fixed to 0
#'   - Estimation: MLR with 16-point Gauss-Hermite quadrature
#'   - Starting values: From Model 1a SVALUES output
#'
#' Inputs:
#'   @param wide_data Data frame with item responses (id + equate names)
#'                    Person covariates (female, years, femXyrs, logyrs) are automatically excluded
#'   @param item_metadata Data frame with item metadata (columns: equate_name, dimension, ...)
#'   @param model1a_out_file Path to Model 1a .out file (default: "mplus/model_1a/model_1a.out")
#'                           REQUIRED: Model 1a must be run first to generate starting values
#'
#' Output:
#'   Returns Mplus syntax as character string (does not save to file)
#'
#' IMPORTANT: Uses Model 1a .dat file (default: "mplus/model_1a/model_1a.dat")
#'   - No need to create separate .dat file for Model 1b
#'   - .dat file contains: pid, recordid, female, years, femXyrs, logyrs, <items>
#'   - recordid: Renamed from record_id (Mplus doesn't allow underscores)
#'   - femXyrs = female * years (computed in R)
#'   - logyrs = log(years) (computed in R)
#'
#' Usage:
#'   source("scripts/authenticity_screening/manual_screening/02_generate_model1b_syntax.R")
#'
#'   # Load data
#'   out_list <- load_stage1_data()
#'
#'   # Generate syntax
#'   syntax <- generate_model1b_syntax(
#'     wide_data = out_list$wide_data,
#'     item_metadata = out_list$item_metadata
#'   )
#'
#'   cat(syntax)

library(dplyr)
library(stringr)

#' Parse Model 1a SVALUES from Mplus Output File
#'
#' @param out_file Path to Model 1a .out file
#' @return List with components: loadings, thresholds, regression_coefs, factor_cor
parse_model1a_svalues <- function(out_file) {

  if (!file.exists(out_file)) {
    stop(sprintf("Model 1a output file not found: %s", out_file))
  }

  # Read output file
  lines <- readLines(out_file, warn = FALSE)

  # Find STARTING VALUES section (Mplus SVALUES output)
  sval_start <- which(stringr::str_detect(lines, "MODEL COMMAND WITH FINAL ESTIMATES USED AS STARTING VALUES"))

  if (length(sval_start) == 0) {
    stop("STARTING VALUES section not found in Model 1a output file.\n",
         "Make sure Model 1a was run with OUTPUT: SVALUES; in the .inp file.")
  }

  sval_start <- sval_start[1]

  # Initialize storage
  loadings <- list()
  thresholds <- list()
  regression_coefs <- list()
  factor_cor <- NULL

  # Parse Mplus syntax starting from SVALUES section
  # Format: "f_psych BY aa4*1.21688 (a001);"
  i <- sval_start + 1

  while (i <= length(lines)) {
    line <- lines[i]

    # Stop at next major section (but not on empty lines)
    if (stringr::str_detect(line, "^TECH\\d+|^PLOT|^SAVEDATA")) {
      break
    }

    # Parse BY statements: "f_psych BY aa4*1.21688 (a001);"
    if (stringr::str_detect(line, "\\s+(f_psych|f_dev)\\s+BY\\s+")) {
      # Extract: factor, item, value
      match <- stringr::str_match(line, "(f_psych|f_dev)\\s+BY\\s+(\\w+)\\*([-\\d.]+)")
      if (!is.na(match[1])) {
        factor_name <- toupper(match[2])
        item_name <- tolower(match[3])
        loading_value <- as.numeric(match[4])

        if (!is.na(loading_value)) {
          loadings[[item_name]] <- list(factor = factor_name, value = loading_value)
        }
      }
    }

    # Parse ON statements: "     f_psych ON female*0.07110;"
    if (stringr::str_detect(line, "(f_psych|f_dev)\\s+ON\\s+\\w+\\*")) {
      # Extract: factor, covariate, coefficient
      match <- stringr::str_match(line, "(f_psych|f_dev)\\s+ON\\s+(\\w+)\\*([-\\d.]+)")
      if (!is.na(match[1])) {
        factor_name <- toupper(match[2])
        covar_name <- tolower(match[3])
        coef_value <- as.numeric(match[4])

        if (!is.na(coef_value)) {
          key <- paste0(factor_name, "_", covar_name)
          regression_coefs[[key]] <- coef_value
        }
      }
    }

    # Parse WITH statements: "     f_psych WITH f_dev*0.16661;"
    if (stringr::str_detect(line, "f_psych\\s+WITH\\s+f_dev\\*")) {
      match <- stringr::str_match(line, "f_psych\\s+WITH\\s+f_dev\\*([-\\d.]+)")
      if (!is.na(match[1])) {
        factor_cor <- as.numeric(match[2])
      }
    }

    # Parse threshold statements: "     [ aa4$1*-1.66308 ];"
    if (stringr::str_detect(line, "\\[\\s*\\w+\\$\\d+\\*")) {
      match <- stringr::str_match(line, "\\[\\s*(\\w+\\$\\d+)\\*([-\\d.]+)")
      if (!is.na(match[1])) {
        threshold_name <- tolower(match[2])
        threshold_value <- as.numeric(match[3])

        if (!is.na(threshold_value)) {
          thresholds[[threshold_name]] <- threshold_value
        }
      }
    }

    i <- i + 1
  }

  return(list(
    loadings = loadings,
    thresholds = thresholds,
    regression_coefs = regression_coefs,
    factor_cor = factor_cor
  ))
}

#' Generate Mplus Model 1b Syntax
#'
#' @param wide_data Data frame with person × item matrix
#'                  Can contain: id + item equate names (ONLY items)
#'                  OR: id + person covariates + item equate names (items + covariates)
#'                  Function automatically excludes person vars (female, years, femXyrs, logyrs)
#' @param item_metadata Data frame with item metadata (columns: equate_name, dimension, ...)
#' @param model1a_out_file Path to Model 1a .out file with SVALUES
#'                         Default: "mplus/model_1a/model_1a.out"
#' @param dat_file Path to Mplus .dat file (default: "mplus/model_1a/model_1a.dat")
#'                 Uses same .dat file as Model 1a (no need to duplicate)
#'                 NOTE: The .dat file MUST contain columns in order:
#'                       id, female, years, femXyrs, logyrs, <items>
#' @param output_dir Directory for Mplus output files (default: "mplus/model_1b")
#' @return Character string containing complete Mplus .inp syntax
generate_model1b_syntax <- function(wide_data,
                                     item_metadata,
                                     model1a_out_file = "mplus/model_1a/model_1a.out",
                                     dat_file = "mplus/model_1a/model_1a.dat",
                                     output_dir = "mplus/model_1b") {

  cat("\n")
  cat("================================================================================\n")
  cat("  GENERATE MPLUS MODEL 1b SYNTAX\n")
  cat("================================================================================\n")
  cat("\n")

  # ==========================================================================
  # STEP 1: VALIDATE INPUT DATA
  # ==========================================================================

  cat("=== STEP 1: VALIDATE INPUT DATA ===\n\n")

  # Validate wide_data
  if (!is.data.frame(wide_data)) {
    stop("wide_data must be a data frame")
  }
  if (!"pid" %in% names(wide_data)) {
    stop("wide_data must contain 'pid' column")
  }
  if (!"recordid" %in% names(wide_data)) {
    stop("wide_data must contain 'recordid' column")
  }

  # Validate item_metadata
  if (!is.data.frame(item_metadata)) {
    stop("item_metadata must be a data frame")
  }
  required_cols <- c("equate_name", "dimension")
  missing_cols <- setdiff(required_cols, names(item_metadata))
  if (length(missing_cols) > 0) {
    stop(sprintf("item_metadata missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  # Parse Model 1a starting values
  cat(sprintf("[Reading] Model 1a output file: %s\n", model1a_out_file))
  svalues <- parse_model1a_svalues(model1a_out_file)

  cat(sprintf("[Parsed] %d loadings, %d thresholds, %d regression coefficients\n",
              length(svalues$loadings), length(svalues$thresholds),
              length(svalues$regression_coefs)))

  if (!is.null(svalues$factor_cor)) {
    cat(sprintf("[Parsed] Factor correlation: %.5f\n", svalues$factor_cor))
  }

  cat(sprintf("[Validated] Wide data: %d participants × %d items\n",
              nrow(wide_data), ncol(wide_data) - 1))
  cat(sprintf("[Validated] Item metadata: %d items\n", nrow(item_metadata)))
  cat("\n")

  # ==========================================================================
  # STEP 2: ORGANIZE ITEMS BY DIMENSION
  # ==========================================================================

  cat("=== STEP 2: ORGANIZE ITEMS BY DIMENSION ===\n\n")

  # Define person variables that should be excluded from item lists
  person_var_names <- c("pid", "recordid", "female", "years", "femXyrs", "logyrs")

  # Get actual item column names from wide_data (exclude person variables)
  actual_item_names <- setdiff(names(wide_data), person_var_names)

  # Create mapping from actual column names to equate names via item_metadata
  # This allows us to determine dimension membership
  name_lookup <- item_metadata %>%
    dplyr::select(equate_name, dimension)

  # Match actual names to equate names (assuming wide_data uses equate names)
  # Split by dimension using actual column names
  items_dim1 <- item_metadata %>%
    dplyr::filter(dimension == 1) %>%
    dplyr::filter(equate_name %in% actual_item_names) %>%
    dplyr::pull(equate_name)

  items_dim2 <- item_metadata %>%
    dplyr::filter(dimension == 2) %>%
    dplyr::filter(equate_name %in% actual_item_names) %>%
    dplyr::pull(equate_name)

  cat(sprintf("Dimension 1 (Psychosocial/Behavioral): %d items\n", length(items_dim1)))
  cat(sprintf("Dimension 2 (Developmental Skills): %d items\n", length(items_dim2)))
  cat("\n")

  # ==========================================================================
  # STEP 3: BUILD MPLUS SYNTAX COMPONENTS
  # ==========================================================================

  cat("=== STEP 3: BUILD SYNTAX COMPONENTS ===\n\n")

  # TITLE
  title_section <- paste0(
    "TITLE: \n",
    "  Model 1b - Free Loadings Within Domain + N(0,1) Priors\n",
    "  NE25 Authenticity Screening Stage 1\n",
    "  2-Parameter IRT with Demographic Covariates\n",
    "  Generated: ", Sys.Date(), "\n"
  )

  # DATA
  # Extract just the filename (Mplus .inp file should be in same directory as .dat)
  dat_filename <- basename(dat_file)
  data_section <- paste0(
    "DATA: \n",
    "  FILE = \"", dat_filename, "\";\n"
  )

  # VARIABLE - NAMES
  # Format: 80 characters per line max, items separated by spaces
  # Use actual column names from wide_data in the order they appear
  # Person vars order: pid, recordid, female, years, femXyrs, logyrs (derived vars computed in R)
  person_vars <- c("pid", "recordid", "female", "years", "femXyrs", "logyrs")

  # Get item names in the order they appear in wide_data
  # Exclude ALL person variables to prevent duplication
  all_item_names <- setdiff(names(wide_data), person_vars)

  # Combine person vars + item vars (person vars MUST come first)
  all_var_names <- c(person_vars, all_item_names)

  # Format NAMES section with line breaks every ~10 items
  names_lines <- character()
  names_lines[1] <- "  NAMES = "
  current_line <- "    pid recordid female years femXyrs logyrs"

  for (i in seq_along(all_item_names)) {
    item <- all_item_names[i]
    # Check if adding this item would exceed 80 chars
    if (nchar(current_line) + nchar(item) + 1 > 78) {
      names_lines <- c(names_lines, current_line)
      current_line <- paste0("    ", item)
    } else {
      current_line <- paste(current_line, item)
    }
  }
  # Add final line with semicolon
  names_lines <- c(names_lines, paste0(current_line, ";"))

  # VARIABLE - USEVARIABLES
  usevars_lines <- character()
  usevars_lines[1] <- "  USEVARIABLES = "
  current_line <- "    female years femXyrs logyrs"

  for (i in seq_along(all_item_names)) {
    item <- all_item_names[i]
    if (nchar(current_line) + nchar(item) + 1 > 78) {
      usevars_lines <- c(usevars_lines, current_line)
      current_line <- paste0("    ", item)
    } else {
      current_line <- paste(current_line, item)
    }
  }
  usevars_lines <- c(usevars_lines, paste0(current_line, ";"))

  # VARIABLE - CATEGORICAL
  cat_lines <- character()
  cat_lines[1] <- "  CATEGORICAL = "
  current_line <- "    "

  for (i in seq_along(all_item_names)) {
    item <- all_item_names[i]
    if (nchar(current_line) + nchar(item) + 1 > 78) {
      cat_lines <- c(cat_lines, current_line)
      current_line <- paste0("    ", item)
    } else {
      current_line <- paste(current_line, item)
    }
  }
  cat_lines <- c(cat_lines, paste0(current_line, ";"))

  # Complete VARIABLE section
  variable_section <- paste0(
    "VARIABLE:\n",
    paste(names_lines, collapse = "\n"), "\n",
    "  \n",
    paste(usevars_lines, collapse = "\n"), "\n",
    "  \n",
    paste(cat_lines, collapse = "\n"), "\n",
    "  \n",
    "  IDVARIABLE = pid;\n",
    "  AUXILIARY = recordid;\n",
    "  \n",
    "  MISSING = . ;\n",
    "  \n",
    "  ! Create derived covariates\n",
    "  DEFINE:\n"
  )

  # ANALYSIS
  analysis_section <- paste0(
    "ANALYSIS:\n",
    "  ESTIMATOR = MLR;                     ! Maximum likelihood with robust SEs\n",
    "  ALGORITHM = INTEGRATION;             ! Numerical integration for categorical\n",
    "  INTEGRATION = GAUSS(16);             ! 16-point Gauss-Hermite quadrature\n",
    "  LINK = LOGIT;                        ! Logit link (graded response model)\n",
    "  PROCESSORS = 16;                     ! Parallel processing\n"
  )

  # MODEL - Factor 1 (Psychosocial-Specific) with FREE loadings
  # Only psychosocial items load on F_Psych
  factor1_lines <- character()
  factor1_lines[1] <- "  ! FACTOR 1: PSYCHOSOCIAL-SPECIFIC (Dimension 1 items only)"
  factor1_lines[2] <- "  ! FREE loadings: Each item gets unique label (a001, a002, ...)"
  factor1_lines[3] <- "  ! Starting values from Model 1a"
  factor1_lines[4] <- "  F_Psych BY "

  for (i in seq_along(items_dim1)) {
    item <- items_dim1[i]
    label <- sprintf("a%03d", i)  # a001, a002, a003, ...

    # Get starting value from Model 1a (default to 1.0 if not found)
    item_lower <- tolower(item)
    start_val <- 1.0
    if (item_lower %in% names(svalues$loadings)) {
      start_val <- svalues$loadings[[item_lower]]$value
    }

    if (i == length(items_dim1)) {
      # Last item: add semicolon
      factor1_lines <- c(factor1_lines,
                        sprintf("    %s*%.5f     (%s);", item, start_val, label))
    } else {
      factor1_lines <- c(factor1_lines,
                        sprintf("    %s*%.5f     (%s)", item, start_val, label))
    }
  }

  # MODEL - Factor 2 (General Developmental) with FREE loadings
  # ALL items load on F_Dev (psychosocial + developmental)
  factor2_lines <- character()
  factor2_lines[1] <- "  "
  factor2_lines[2] <- "  ! FACTOR 2: GENERAL DEVELOPMENTAL (ALL items)"
  factor2_lines[3] <- "  ! Psychosocial items load on BOTH F_Psych and F_Dev"
  factor2_lines[4] <- "  ! Developmental items load ONLY on F_Dev"
  factor2_lines[5] <- "  ! FREE loadings: Each item gets unique label (b001, b002, ...)"
  factor2_lines[6] <- "  ! Starting values from Model 1a"
  factor2_lines[7] <- "  F_Dev BY "

  # Combine all items for F_Dev (psychosocial + developmental)
  all_items <- c(items_dim1, items_dim2)

  for (i in seq_along(all_items)) {
    item <- all_items[i]
    label <- sprintf("b%03d", i)  # b001, b002, b003, ...

    # Get starting value from Model 1a (default to 1.0 if not found)
    item_lower <- tolower(item)
    start_val <- 1.0
    if (item_lower %in% names(svalues$loadings)) {
      start_val <- svalues$loadings[[item_lower]]$value
    }

    if (i == length(all_items)) {
      factor2_lines <- c(factor2_lines,
                        sprintf("    %s*%.5f     (%s);", item, start_val, label))
    } else {
      factor2_lines <- c(factor2_lines,
                        sprintf("    %s*%.5f     (%s)", item, start_val, label))
    }
  }

  # MODEL - Priors section for N(0,1) on loadings
  priors_lines <- character()
  priors_lines[1] <- "  "
  priors_lines[2] <- "MODEL PRIORS:"
  priors_lines[3] <- "  ! N(0,1) priors on all loadings"

  # F_Psych priors (psychosocial items only)
  for (i in seq_along(items_dim1)) {
    label <- sprintf("a%03d", i)
    priors_lines <- c(priors_lines, sprintf("  %s ~ N(0, 1);", label))
  }

  priors_lines <- c(priors_lines, "  ")

  # F_Dev priors (ALL items: psychosocial + developmental)
  for (i in seq_along(all_items)) {
    label <- sprintf("b%03d", i)
    priors_lines <- c(priors_lines, sprintf("  %s ~ N(0, 1);", label))
  }

  # MODEL - Latent regression with starting values from Model 1a
  regression_lines <- character()
  regression_lines[1] <- "  "
  regression_lines[2] <- "  ! LATENT REGRESSION: Factors predicted by demographics"
  regression_lines[3] <- "  ! Starting values from Model 1a"

  # F_Psych ON statements
  psych_on_female <- svalues$regression_coefs[["F_PSYCH_female"]] %||% 0.0
  psych_on_years <- svalues$regression_coefs[["F_PSYCH_years"]] %||% 0.0
  psych_on_femxyrs <- svalues$regression_coefs[["F_PSYCH_femxyrs"]] %||% 0.0
  psych_on_logyrs <- svalues$regression_coefs[["F_PSYCH_logyrs"]] %||% 0.0

  regression_lines <- c(regression_lines, sprintf("  F_Psych ON female*%.5f;", psych_on_female))
  regression_lines <- c(regression_lines, sprintf("  F_Psych ON years*%.5f;", psych_on_years))
  regression_lines <- c(regression_lines, sprintf("  F_Psych ON femXyrs*%.5f;", psych_on_femxyrs))
  regression_lines <- c(regression_lines, sprintf("  F_Psych ON logyrs*%.5f;", psych_on_logyrs))

  # F_Dev ON statements
  dev_on_female <- svalues$regression_coefs[["F_DEV_female"]] %||% 0.0
  dev_on_years <- svalues$regression_coefs[["F_DEV_years"]] %||% 0.0
  dev_on_femxyrs <- svalues$regression_coefs[["F_DEV_femxyrs"]] %||% 0.0
  dev_on_logyrs <- svalues$regression_coefs[["F_DEV_logyrs"]] %||% 0.0

  regression_lines <- c(regression_lines, sprintf("  F_Dev ON female*%.5f;", dev_on_female))
  regression_lines <- c(regression_lines, sprintf("  F_Dev ON years*%.5f;", dev_on_years))
  regression_lines <- c(regression_lines, sprintf("  F_Dev ON femXyrs*%.5f;", dev_on_femxyrs))
  regression_lines <- c(regression_lines, sprintf("  F_Dev ON logyrs*%.5f;", dev_on_logyrs))

  # Factor correlation (fixed to zero - orthogonal factors)
  regression_lines <- c(regression_lines, "  ")
  regression_lines <- c(regression_lines, "  ! Factor residual correlation (fixed to zero - orthogonal factors)")
  regression_lines <- c(regression_lines, "  F_Psych WITH F_Dev@0;")

  # Factor identification
  regression_lines <- c(regression_lines, "  ")
  regression_lines <- c(regression_lines, "  ! Factor means/intercepts (fixed for identification)")
  regression_lines <- c(regression_lines, "  [F_Psych@0];")
  regression_lines <- c(regression_lines, "  [F_Dev@0];")

  # Thresholds with starting values from Model 1a
  threshold_lines <- character()
  threshold_lines[1] <- "  "
  threshold_lines[2] <- "  ! Item thresholds with starting values from Model 1a"

  # Combine all items for threshold generation
  for (item in c(items_dim1, items_dim2)) {
    item_lower <- tolower(item)

    # Find all thresholds for this item (aa4$1, aa4$2, etc.)
    item_thresholds <- names(svalues$thresholds)[stringr::str_starts(names(svalues$thresholds), paste0(item_lower, "\\$"))]

    for (thr_name in item_thresholds) {
      thr_val <- svalues$thresholds[[thr_name]]
      # Convert back to original case for output
      thr_name_upper <- stringr::str_replace(thr_name, item_lower, item)
      threshold_lines <- c(threshold_lines, sprintf("  [ %s*%.5f ];", thr_name_upper, thr_val))
    }
  }

  # Factor variances
  variance_lines <- character()
  variance_lines[1] <- "  "
  variance_lines[2] <- "  ! Factor residual variances (fixed for identification)"
  variance_lines[3] <- "  F_Psych@1;"
  variance_lines[4] <- "  F_Dev@1;"

  # Combine model structure
  model_structure <- paste0(
    paste(regression_lines, collapse = "\n"), "\n",
    paste(threshold_lines, collapse = "\n"), "\n",
    paste(variance_lines, collapse = "\n"), "\n"
  )

  # Complete MODEL section
  model_section <- paste0(
    "MODEL:\n",
    paste(factor1_lines, collapse = "\n"), "\n",
    paste(factor2_lines, collapse = "\n"), "\n",
    model_structure, "\n",
    paste(priors_lines, collapse = "\n"), "\n"
  )

  # OUTPUT
  output_section <- paste0(
    "OUTPUT:\n",
    "  NOSERROR;\n",
    "  SVALUES;\n"
  )

  # SAVEDATA
  savedata_section <- paste0(
    "SAVEDATA:\n",
    "\n",
    "\n"
  )

  # ==========================================================================
  # STEP 4: COMBINE ALL SECTIONS
  # ==========================================================================

  cat("=== STEP 4: ASSEMBLE COMPLETE SYNTAX ===\n\n")

  complete_syntax <- paste0(
    title_section, "\n",
    data_section, "\n",
    variable_section, "\n",
    analysis_section, "\n",
    model_section,
    output_section, "\n",
    savedata_section
  )

  cat(sprintf("[Complete] Generated Mplus syntax (%d lines)\n",
              length(strsplit(complete_syntax, "\n")[[1]])))
  cat(sprintf("  - Dimension 1 items: %d (labels: a001 to a%03d)\n",
              length(items_dim1), length(items_dim1)))
  cat(sprintf("  - Dimension 2 items: %d (labels: b001 to b%03d)\n",
              length(items_dim2), length(items_dim2)))
  cat(sprintf("  - Total items: %d\n", length(all_item_names)))
  cat(sprintf("  - Covariates: female, years, femXyrs, logyrs (pre-computed in R)\n"))
  cat(sprintf("  - Total variables in .dat: %d (6 person vars + %d items)\n",
              length(all_var_names), length(all_item_names)))
  cat(sprintf("  - Total priors: %d N(0,1) priors on loadings\n",
              length(items_dim1) + length(items_dim2)))
  cat("\n")

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("================================================================================\n")
  cat("  SYNTAX GENERATION COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Model 1b Specification:\n")
  cat("  - Estimation: MLR with 16-point Gauss-Hermite quadrature\n")
  cat("  - Link: Logit (graded response model)\n")
  cat("  - FREE loadings within domain (each item unique label)\n")
  cat("  - Starting values: ALL parameters from Model 1a output\n")
  cat(sprintf("    * %d loadings\n", length(svalues$loadings)))
  cat(sprintf("    * %d thresholds\n", length(svalues$thresholds)))
  cat(sprintf("    * %d regression coefficients\n", length(svalues$regression_coefs)))
  cat(sprintf("    * 1 factor correlation\n"))
  cat("  - Priors: N(0,1) on all loadings (regularization)\n")
  cat("  - Identification: Factor variances fixed to 1, means fixed to 0\n")
  cat("  - Latent regression: F ~ female + years + female×years + log(years)\n")
  cat("  - Output: NOSERROR, SVALUES (for Model 1c starting values)\n")
  cat("  - Processors: 16 (parallel estimation)\n")
  cat("\n")

  cat("Usage Example:\n")
  cat("  # This function was called with:\n")
  cat(sprintf("  #   wide_data: %d participants × %d items\n",
              nrow(wide_data), ncol(wide_data) - 1))
  cat(sprintf("  #   item_metadata: %d items with dimension assignments\n",
              nrow(item_metadata)))
  cat("\n")

  cat("Next Steps:\n")
  cat("  1. Inspect syntax: cat(syntax)\n")
  cat("  2. Save to file: writeLines(syntax, 'mplus/model_1b/model_1b.inp')\n")
  cat("  3. .dat file: Uses Model 1a .dat file (no preparation needed)\n")
  cat("     - Default: mplus/model_1a/model_1a.dat\n")
  cat("     - Contains: pid, recordid, female, years, femXyrs, logyrs, <items>\n")
  cat("  4. Run in Mplus or via MplusAutomation::runModels()\n")
  cat("  5. Extract SVALUES for Model 1c starting values\n")
  cat("  6. Identify items with negative loadings for Model 1c constraints\n")
  cat("\n")

  return(complete_syntax)
}


# ============================================================================
# EXAMPLE USAGE
# ============================================================================

# When sourced interactively, this demonstrates the usage pattern:
#
# # Load data first
# source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")
# out_list <- load_stage1_data()
#
# # Generate syntax (reads Model 1a starting values automatically)
# source("scripts/authenticity_screening/manual_screening/02_generate_model1b_syntax.R")
# syntax <- generate_model1b_syntax(
#   wide_data = out_list$wide_data,
#   item_metadata = out_list$item_metadata,
#   model1a_out_file = "mplus/model_1a/model_1a.out"  # Default, can omit
# )
#
# # Inspect syntax
# cat(syntax)
#
# # Save to file when ready
# writeLines(syntax, "mplus/model_1b/model_1b.inp")
