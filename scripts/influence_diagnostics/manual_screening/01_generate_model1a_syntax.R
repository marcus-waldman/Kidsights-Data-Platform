#!/usr/bin/env Rscript

#' Generate Mplus Model 1a Input Syntax
#'
#' Creates Mplus .inp syntax for Model 1a: Equal loadings within domain with
#' latent regression on demographic covariates.
#'
#' Model Specification:
#'   - 2-parameter IRT with logit link (graded response model)
#'   - Equal loadings within domain (tau-equivalent assumption)
#'   - Latent regression: F ~ female + years + female×years + log(years)
#'   - Identification: Factor variances fixed to 1, means fixed to 0
#'   - Estimation: MLR with 16-point Gauss-Hermite quadrature
#'   - Starting values: All loadings = 1
#'
#' Inputs:
#'   @param wide_data Data frame with item responses (id + equate names)
#'                    Person covariates (female, years, femXyrs, logyrs) are automatically excluded
#'   @param item_metadata Data frame with item metadata (equate_name, dimension columns)
#'
#' Output:
#'   Returns Mplus syntax as character string (does not save to file)
#'
#' IMPORTANT: The .dat file must be prepared separately with all person variables:
#'   - Column order: pid, recordid, female, years, femXyrs, logyrs, <items>
#'   - recordid: Renamed from record_id (Mplus doesn't allow underscores)
#'   - femXyrs = female * years (computed in R)
#'   - logyrs = log(years) (computed in R)
#'
#' Usage:
#'   source("scripts/authenticity_screening/manual_screening/01_generate_model1a_syntax.R")
#'
#'   # Load data
#'   out_list <- load_stage1_data()
#'
#'   # Generate syntax
#'   syntax <- generate_model1a_syntax(
#'     wide_data = out_list$wide_data,
#'     item_metadata = out_list$item_metadata
#'   )
#'
#'   cat(syntax)

library(dplyr)

#' Generate Mplus Model 1a Syntax
#'
#' @param wide_data Data frame with person × item matrix
#'                  Can contain: id + item equate names (ONLY items)
#'                  OR: id + person covariates + item equate names (items + covariates)
#'                  Function automatically excludes person vars (female, years, femXyrs, logyrs)
#' @param item_metadata Data frame with item metadata (columns: equate_name, dimension, ...)
#' @param dat_file Path to Mplus .dat file (default: "mplus/model_1a/model_1a.dat")
#'                 NOTE: The .dat file MUST contain columns in order:
#'                       id, female, years, femXyrs, logyrs, <items>
#' @param output_dir Directory for Mplus output files (default: "mplus/model_1a")
#' @return Character string containing complete Mplus .inp syntax
generate_model1a_syntax <- function(wide_data,
                                     item_metadata,
                                     dat_file = "mplus/model_1a/model_1a.dat",
                                     output_dir = "mplus/model_1a") {

  cat("\n")
  cat("================================================================================\n")
  cat("  GENERATE MPLUS MODEL 1a SYNTAX\n")
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
    "  Model 1a - Equal Loadings Within Domain + Latent Regression\n",
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

  # MODEL - Factor 1 (Psychosocial-Specific)
  # Only psychosocial items load on F_Psych
  factor1_lines <- character()
  factor1_lines[1] <- "  ! FACTOR 1: PSYCHOSOCIAL-SPECIFIC (Dimension 1 items only)"
  factor1_lines[2] <- "  ! Equal loadings constraint via (a001) label"
  factor1_lines[3] <- "  ! Starting values = 1 for all items"
  factor1_lines[4] <- "  F_Psych BY "

  for (i in seq_along(items_dim1)) {
    item <- items_dim1[i]
    if (i == length(items_dim1)) {
      # Last item: add semicolon
      factor1_lines <- c(factor1_lines, paste0("    ", item, "*1     (a001);"))
    } else {
      factor1_lines <- c(factor1_lines, paste0("    ", item, "*1     (a001)"))
    }
  }

  # MODEL - Factor 2 (General Developmental)
  # ALL items load on F_Dev (psychosocial + developmental)
  factor2_lines <- character()
  factor2_lines[1] <- "  "
  factor2_lines[2] <- "  ! FACTOR 2: GENERAL DEVELOPMENTAL (ALL items)"
  factor2_lines[3] <- "  ! Psychosocial items load on BOTH F_Psych and F_Dev"
  factor2_lines[4] <- "  ! Developmental items load ONLY on F_Dev"
  factor2_lines[5] <- "  ! Equal loadings constraint via (b001) label"
  factor2_lines[6] <- "  F_Dev BY "

  # Combine all items for F_Dev (psychosocial + developmental)
  all_items <- c(items_dim1, items_dim2)

  for (i in seq_along(all_items)) {
    item <- all_items[i]
    if (i == length(all_items)) {
      factor2_lines <- c(factor2_lines, paste0("    ", item, "*1     (b001);"))
    } else {
      factor2_lines <- c(factor2_lines, paste0("    ", item, "*1     (b001)"))
    }
  }

  # MODEL - Latent regression and factor structure
  model_structure <- paste0(
    "  \n",
    "  ! LATENT REGRESSION: Factors predicted by demographics\n",
    "  ! F ~ intercept + female + years + female×years + log(years)\n",
    "  F_Psych ON female years femXyrs logyrs;\n",
    "  F_Dev ON female years femXyrs logyrs;\n",
    "  \n",
    "  ! Factor residual variances (constrainted for model identification)\n",
    "  ! These are variances AFTER accounting for covariates\n",
    "  F_Psych@1;\n",
    "  F_Dev@1;\n",
    "\n",
    "   ! Factor means/intercepts (constrainted for model identification)\n",
    "  [F_Psych@0];\n",
    "  [F_Dev@0];\n",
    "  \n",
    "  ! Factor residual correlation (fixed to zero - orthogonal factors)\n",
    "  F_Psych WITH F_Dev@0;\n",
    "  \n",
    "  ! Item thresholds: First threshold per item fixed at 0 for identification\n",
    "  ! (Mplus does this automatically for CATEGORICAL with THETA parameterization)\n"
  )

  # Complete MODEL section
  model_section <- paste0(
    "MODEL:\n",
    paste(factor1_lines, collapse = "\n"), "\n",
    paste(factor2_lines, collapse = "\n"), "\n",
    model_structure
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
    model_section, "\n",
    output_section, "\n",
    savedata_section
  )

  cat(sprintf("[Complete] Generated Mplus syntax (%d lines)\n",
              length(strsplit(complete_syntax, "\n")[[1]])))
  cat(sprintf("  - Dimension 1 items: %d\n", length(items_dim1)))
  cat(sprintf("  - Dimension 2 items: %d\n", length(items_dim2)))
  cat(sprintf("  - Total items: %d\n", length(all_item_names)))
  cat(sprintf("  - Covariates: female, years, femXyrs, logyrs (pre-computed in R)\n"))
  cat(sprintf("  - Total variables in .dat: %d (6 person vars + %d items)\n",
              length(all_var_names), length(all_item_names)))
  cat("\n")

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("================================================================================\n")
  cat("  SYNTAX GENERATION COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Model 1a Specification:\n")
  cat("  - Estimation: MLR with 16-point Gauss-Hermite quadrature\n")
  cat("  - Link: Logit (graded response model)\n")
  cat("  - Equal loadings within domain (tau-equivalent assumption)\n")
  cat("  - Starting values: All loadings = 1\n")
  cat("  - Identification: Factor variances fixed to 1, means fixed to 0\n")
  cat("  - Latent regression: F ~ female + years + female×years + log(years)\n")
  cat("  - Output: NOSERROR, SVALUES (for Model 1b starting values)\n")
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
  cat("  2. Save to file: writeLines(syntax, 'mplus/model_1a/model_1a.inp')\n")
  cat("  3. Prepare .dat file (CRITICAL: must include all 6 person vars):\n")
  cat("     - Join wide_data with person_data (pid, recordid, female, years)\n")
  cat("     - Compute derived vars: femXyrs = female * years, logyrs = log(years)\n")
  cat("     - Column order: pid, recordid, female, years, femXyrs, logyrs, <items>\n")
  cat("     - Use MplusAutomation::prepareMplusData() to create .dat file\n")
  cat("  4. Run in Mplus or via MplusAutomation::runModels()\n")
  cat("  5. Extract SVALUES for Model 1b starting values\n")
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
# # Generate syntax
# source("scripts/authenticity_screening/manual_screening/01_generate_model1a_syntax.R")
# syntax <- generate_model1a_syntax(
#   wide_data = out_list$wide_data,
#   item_metadata = out_list$item_metadata
# )
#
# # Inspect syntax
# cat(syntax)
#
# # Save to file when ready
# writeLines(syntax, "mplus/model_1a/model_1a.inp")
