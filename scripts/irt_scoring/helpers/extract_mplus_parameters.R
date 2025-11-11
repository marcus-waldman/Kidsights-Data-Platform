# =============================================================================
# Extract IRT Parameters from Mplus Output
# =============================================================================
# Purpose: Parse Mplus .out file and extract item discrimination and threshold
#          parameters using MplusAutomation package
#
# Based on: Update-KidsightsPublic/mplus/extract_estimates_Kidsights_calibration.R
# Version: 1.0
# Created: January 2025
# =============================================================================

# Load required packages
library(dplyr)
library(stringr)
library(MplusAutomation)

#' Extract IRT Parameters from Mplus Output File
#'
#' Reads Mplus calibration .out file and extracts item discrimination (alpha)
#' and threshold (tau) parameters using MplusAutomation::readModels().
#'
#' @param mplus_output_path Character. Path to Mplus .out file.
#'   Example: "mplus/Kidsights-calibration.out"
#' @param latent_class Integer. Which latent class to extract parameters from.
#'   Default: 1 (use when parameters are constrained equal across classes)
#' @param verbose Logical. Print progress messages?
#'   Default: TRUE
#'
#' @return List with two components:
#'   - discriminations: Data frame with columns (lex_equate, alpha)
#'   - thresholds: Data frame with columns (lex_equate, k, tau_k)
#'
#' @details
#' This function extracts parameters from Mplus unstandardized estimates:
#'
#' **Discrimination parameters (alpha)**:
#' - Extracted from factor loadings (paramHeader ends with ".BY")
#' - One alpha per item (discrimination/slope parameter)
#' - Format: data frame with lex_equate (item name) and alpha (estimate)
#'
#' **Threshold parameters (tau)**:
#' - Extracted from Thresholds section (paramHeader == "Thresholds")
#' - Multiple thresholds per item (k = 1, 2, 3, ... for ordinal responses)
#' - Format: long data frame with lex_equate, k (threshold index), tau_k (estimate)
#'
#' The latent_class parameter allows selecting which class to extract from
#' in mixture models. When parameters are constrained equal across classes
#' (typical for multi-study IRT calibration), any class can be used.
#'
#' @examples
#' \dontrun{
#' # Extract parameters from calibration output
#' params <- extract_mplus_parameters(
#'   mplus_output_path = "mplus/Kidsights-calibration.out",
#'   latent_class = 1
#' )
#'
#' # View discrimination parameters
#' head(params$discriminations)
#' #>   lex_equate   alpha
#' #>   AA102      1.234
#' #>   AA104      1.456
#' #>   ...
#'
#' # View threshold parameters
#' head(params$thresholds)
#' #>   lex_equate  k  tau_k
#' #>   AA102       1  0.567
#' #>   AA102       2  1.234
#' #>   ...
#' }
#'
#' @export
extract_mplus_parameters <- function(
  mplus_output_path,
  latent_class = 1,
  verbose = TRUE
) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("EXTRACT IRT PARAMETERS FROM MPLUS OUTPUT\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("Input: %s\n", mplus_output_path))
    cat(sprintf("Latent class: %d\n\n", latent_class))
  }

  # ===========================================================================
  # Step 1: Read Mplus Output
  # ===========================================================================

  if (verbose) cat("[1/3] Reading Mplus output file with MplusAutomation...\n")

  if (!file.exists(mplus_output_path)) {
    stop(sprintf("Mplus output file not found: %s", mplus_output_path))
  }

  out_list <- MplusAutomation::readModels(mplus_output_path)

  if (verbose) {
    cat("      [OK] Output file parsed successfully\n\n")
  }

  # ===========================================================================
  # Step 2: Extract Discrimination Parameters (Alpha)
  # ===========================================================================

  if (verbose) cat("[2/3] Extracting discrimination parameters (alpha)...\n")

  discriminations <- out_list$parameters$unstandardized %>%
    dplyr::filter(LatentClass == latent_class, endsWith(paramHeader, ".BY")) %>%
    dplyr::mutate(lex_equate = param) %>%
    dplyr::select(lex_equate, alpha = est)

  if (verbose) {
    cat(sprintf("      Extracted %d discrimination parameters\n", nrow(discriminations)))
    cat(sprintf("      Alpha range: [%.3f, %.3f]\n\n",
                min(discriminations$alpha), max(discriminations$alpha)))
  }

  # ===========================================================================
  # Step 3: Extract Threshold Parameters (Tau)
  # ===========================================================================

  if (verbose) cat("[3/3] Extracting threshold parameters (tau)...\n")

  thresholds <- out_list$parameters$unstandardized %>%
    dplyr::filter(LatentClass == latent_class, paramHeader == "Thresholds") %>%
    dplyr::select(-LatentClass) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      lex_equate = stringr::str_split_i(param, "\\$", 1),
      k = stringr::str_split_i(param, "\\$", 2)
    ) %>%
    dplyr::select(lex_equate, k, tau_k = est)

  if (verbose) {
    cat(sprintf("      Extracted %d threshold parameters\n", nrow(thresholds)))
    cat(sprintf("      Unique items: %d\n", length(unique(thresholds$lex_equate))))
    cat(sprintf("      Tau range: [%.3f, %.3f]\n\n",
                min(thresholds$tau_k), max(thresholds$tau_k)))
  }

  # ===========================================================================
  # Return Results
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("EXTRACTION COMPLETE\n")
    cat(strrep("=", 80), "\n\n")
    cat("Results:\n")
    cat(sprintf("  Discriminations: %d items\n", nrow(discriminations)))
    cat(sprintf("  Thresholds: %d parameters across %d items\n",
                nrow(thresholds), length(unique(thresholds$lex_equate))))
    cat("\n")
  }

  return(list(
    discriminations = discriminations,
    thresholds = thresholds
  ))

}
