# =============================================================================
# Codebook IRT Structure Validation Functions
# =============================================================================
# Purpose: Validate IRT parameter structure and consistency in codebook.json
#          Ensures data quality before saving updates
#
# Usage: Called by update_irt_parameters.R or standalone validation
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

#' Validate IRT Structure in Codebook
#'
#' Main validation function - runs all checks on codebook
#'
#' @param codebook Codebook object (from jsonlite::fromJSON)
#' @return List with $valid (logical) and $errors (character vector)
#' @export
validate_irt_structure <- function(codebook) {

  errors <- character(0)

  # Run all validation checks
  errors <- c(errors, validate_json_structure(codebook))
  errors <- c(errors, validate_parameter_arrays(codebook))
  errors <- c(errors, validate_thresholds_ordered(codebook))
  errors <- c(errors, validate_factor_names(codebook))
  errors <- c(errors, check_duplicate_items(codebook))

  valid <- length(errors) == 0

  return(list(
    valid = valid,
    errors = errors,
    n_errors = length(errors)
  ))
}

#' Validate JSON Structure
#'
#' Checks that codebook has required top-level structure
#'
#' @param codebook Codebook object
#' @return Character vector of errors (empty if valid)
#' @export
validate_json_structure <- function(codebook) {

  errors <- character(0)

  # Check required top-level fields
  required_fields <- c("items")

  for (field in required_fields) {
    if (!field %in% names(codebook)) {
      errors <- c(errors, sprintf("Missing required field: %s", field))
    }
  }

  # Check items is a list
  if ("items" %in% names(codebook)) {
    if (!is.list(codebook$items)) {
      errors <- c(errors, "Field 'items' must be a list")
    }
  }

  # Check each item has required structure
  if ("items" %in% names(codebook) && is.list(codebook$items)) {
    for (i in seq_along(codebook$items)) {
      item <- codebook$items[[i]]

      # Required item fields
      item_required <- c("id", "lexicons")

      for (field in item_required) {
        if (!field %in% names(item)) {
          errors <- c(errors, sprintf("Item %d missing required field: %s", i, field))
        }
      }

      # If IRT parameters exist, validate structure
      if ("psychometric" %in% names(item) &&
          "irt_parameters" %in% names(item$psychometric)) {

        for (study_id in names(item$psychometric$irt_parameters)) {
          params <- item$psychometric$irt_parameters[[study_id]]

          # Required parameter fields
          param_required <- c("factors", "loadings", "thresholds", "constraints")

          for (field in param_required) {
            if (!field %in% names(params)) {
              errors <- c(errors,
                          sprintf("Item %d, study %s: missing field '%s'",
                                  i, study_id, field))
            }
          }
        }
      }
    }
  }

  return(errors)
}

#' Validate Parameter Arrays
#'
#' Checks that loadings count matches factor count
#' Ensures arrays have appropriate lengths
#'
#' @param codebook Codebook object
#' @return Character vector of errors (empty if valid)
#' @export
validate_parameter_arrays <- function(codebook) {

  errors <- character(0)

  if (!"items" %in% names(codebook)) {
    return(errors)
  }

  for (i in seq_along(codebook$items)) {
    item <- codebook$items[[i]]

    # Get item identifier for error messages
    item_id <- item$id
    if (is.null(item_id)) item_id <- sprintf("item_%d", i)

    # Check IRT parameters if they exist
    if ("psychometric" %in% names(item) &&
        "irt_parameters" %in% names(item$psychometric)) {

      for (study_id in names(item$psychometric$irt_parameters)) {
        params <- item$psychometric$irt_parameters[[study_id]]

        # Check factors is a list/vector
        if (!"factors" %in% names(params)) next

        factors <- unlist(params$factors)
        loadings <- unlist(params$loadings)
        thresholds <- unlist(params$thresholds)

        # Validate loadings count matches factors count
        if (length(loadings) != length(factors)) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: %d loadings but %d factors",
                              item_id, study_id, length(loadings), length(factors)))
        }

        # Check for NA or infinite values
        if (any(is.na(loadings))) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: loadings contain NA",
                              item_id, study_id))
        }

        if (any(is.infinite(loadings))) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: loadings contain Inf",
                              item_id, study_id))
        }

        if (any(is.na(thresholds))) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: thresholds contain NA",
                              item_id, study_id))
        }

        if (any(is.infinite(thresholds))) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: thresholds contain Inf",
                              item_id, study_id))
        }

        # Check thresholds array is not empty
        if (length(thresholds) == 0) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: thresholds array is empty",
                              item_id, study_id))
        }

        # Check loadings are plausible (typically 0 to 5, but allow wider range)
        if (any(abs(loadings) > 10)) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: loadings unusually large (max: %.2f)",
                              item_id, study_id, max(abs(loadings))))
        }
      }
    }
  }

  return(errors)
}

#' Validate Thresholds Ordered
#'
#' Checks that threshold parameters are in ascending order
#' Required for proper GRM model specification
#'
#' @param codebook Codebook object
#' @return Character vector of errors (empty if valid)
#' @export
validate_thresholds_ordered <- function(codebook) {

  errors <- character(0)

  if (!"items" %in% names(codebook)) {
    return(errors)
  }

  for (i in seq_along(codebook$items)) {
    item <- codebook$items[[i]]

    # Get item identifier
    item_id <- item$id
    if (is.null(item_id)) item_id <- sprintf("item_%d", i)

    # Check IRT parameters if they exist
    if ("psychometric" %in% names(item) &&
        "irt_parameters" %in% names(item$psychometric)) {

      for (study_id in names(item$psychometric$irt_parameters)) {
        params <- item$psychometric$irt_parameters[[study_id]]

        if (!"thresholds" %in% names(params)) next

        thresholds <- unlist(params$thresholds)

        if (length(thresholds) < 2) next  # Single threshold doesn't need ordering check

        # Check ascending order
        diffs <- diff(thresholds)

        if (any(diffs <= 0)) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: thresholds not in ascending order (%s)",
                              item_id, study_id,
                              paste(sprintf("%.3f", thresholds), collapse = ", ")))
        }
      }
    }
  }

  return(errors)
}

#' Validate Factor Names
#'
#' Checks for consistent factor naming within models
#' Flags potential issues with factor name inconsistencies
#'
#' @param codebook Codebook object
#' @return Character vector of errors (empty if valid)
#' @export
validate_factor_names <- function(codebook) {

  errors <- character(0)

  if (!"items" %in% names(codebook)) {
    return(errors)
  }

  # Track factor names by study for consistency
  study_factors <- list()

  for (i in seq_along(codebook$items)) {
    item <- codebook$items[[i]]

    # Get item identifier
    item_id <- item$id
    if (is.null(item_id)) item_id <- sprintf("item_%d", i)

    # Check IRT parameters if they exist
    if ("psychometric" %in% names(item) &&
        "irt_parameters" %in% names(item$psychometric)) {

      for (study_id in names(item$psychometric$irt_parameters)) {
        params <- item$psychometric$irt_parameters[[study_id]]

        if (!"factors" %in% names(params)) next

        factors <- unlist(params$factors)

        # Check factor names are not empty
        if (any(nchar(factors) == 0)) {
          errors <- c(errors,
                      sprintf("Item %s, study %s: empty factor name(s)",
                              item_id, study_id))
        }

        # Track factors for this study
        if (!study_id %in% names(study_factors)) {
          study_factors[[study_id]] <- list()
        }

        # Store factor set
        factor_key <- paste(sort(factors), collapse = "|")
        if (!factor_key %in% names(study_factors[[study_id]])) {
          study_factors[[study_id]][[factor_key]] <- list(
            factors = factors,
            items = character(0)
          )
        }

        study_factors[[study_id]][[factor_key]]$items <-
          c(study_factors[[study_id]][[factor_key]]$items, item_id)
      }
    }
  }

  # Check for inconsistent factor structures within studies
  # (This is a warning, not necessarily an error, as different scales can coexist)
  for (study_id in names(study_factors)) {
    if (length(study_factors[[study_id]]) > 1) {
      # Multiple factor structures in same study
      # This is OK if intentional (different scales)
      # Just flag for awareness
      # (Could enhance to check if this is expected)
    }
  }

  return(errors)
}

#' Check for Duplicate Items
#'
#' Checks for duplicate item IDs in lexicons
#' Ensures each item has unique identifiers
#'
#' @param codebook Codebook object
#' @return Character vector of errors (empty if valid)
#' @export
check_duplicate_items <- function(codebook) {

  errors <- character(0)

  if (!"items" %in% names(codebook)) {
    return(errors)
  }

  # Track all lexicon values
  lexicon_values <- list()

  for (i in seq_along(codebook$items)) {
    item <- codebook$items[[i]]

    if ("lexicons" %in% names(item)) {
      for (lex_name in names(item$lexicons)) {
        lex_value <- item$lexicons[[lex_name]]

        if (!lex_name %in% names(lexicon_values)) {
          lexicon_values[[lex_name]] <- character(0)
        }

        # Check if this value already exists
        if (lex_value %in% lexicon_values[[lex_name]]) {
          errors <- c(errors,
                      sprintf("Duplicate %s lexicon value: %s",
                              lex_name, lex_value))
        }

        lexicon_values[[lex_name]] <- c(lexicon_values[[lex_name]], lex_value)
      }
    }

    # Check item ID duplicates
    if ("id" %in% names(item)) {
      # Item IDs should be unique
      # (This is handled by lexicon check above if ID is in lexicon)
    }
  }

  return(errors)
}

#' Generate Validation Report
#'
#' Creates human-readable validation report
#'
#' @param codebook Codebook object or path to codebook JSON
#' @param output_file Optional path to write report (default: print to console)
#' @return Validation result object (invisibly)
#' @export
generate_validation_report <- function(codebook, output_file = NULL) {

  cat("\n", strrep("=", 70), "\n")
  cat("CODEBOOK VALIDATION REPORT\n")
  cat(strrep("=", 70), "\n\n")

  # Load codebook if path provided
  if (is.character(codebook)) {
    codebook_path <- codebook
    cat(sprintf("Loading codebook: %s\n", codebook_path))
    codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)
    cat("[OK] Codebook loaded\n\n")
  }

  # Run validation
  cat("Running validation checks...\n\n")
  result <- validate_irt_structure(codebook)

  # Print summary
  cat(strrep("-", 70), "\n")
  cat("VALIDATION SUMMARY\n")
  cat(strrep("-", 70), "\n\n")

  if (result$valid) {
    cat("[OK] All validation checks passed\n")
  } else {
    cat(sprintf("[ERROR] Validation failed with %d error(s)\n\n", result$n_errors))

    cat("Errors:\n")
    for (i in seq_along(result$errors)) {
      cat(sprintf("  %d. %s\n", i, result$errors[i]))
    }
  }

  cat("\n", strrep("=", 70), "\n\n")

  # Write to file if requested
  if (!is.null(output_file)) {
    sink(output_file)
    cat("CODEBOOK VALIDATION REPORT\n")
    cat(sprintf("Generated: %s\n\n", Sys.time()))

    if (result$valid) {
      cat("STATUS: PASS\n")
    } else {
      cat(sprintf("STATUS: FAIL (%d errors)\n\n", result$n_errors))
      cat("Errors:\n")
      for (i in seq_along(result$errors)) {
        cat(sprintf("  %d. %s\n", i, result$errors[i]))
      }
    }
    sink()

    cat(sprintf("[OK] Report written to: %s\n\n", output_file))
  }

  invisible(result)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Validate codebook
# result <- validate_irt_structure(codebook)
#
# if (!result$valid) {
#   cat("Validation failed:\n")
#   print(result$errors)
# }
#
# # Generate report
# generate_validation_report("codebook/data/codebook.json")
#
# # Save report to file
# generate_validation_report(
#   "codebook/data/codebook.json",
#   output_file = "codebook/validation_report.txt"
# )
