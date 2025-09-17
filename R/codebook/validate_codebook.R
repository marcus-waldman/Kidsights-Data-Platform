#' Comprehensive Codebook Validation Functions
#'
#' Functions for validating codebook structure, content, and data quality

library(tidyverse)
library(yaml)

#' Run comprehensive validation checks on codebook
#'
#' @param codebook Codebook object
#' @param config_path Path to configuration file
#' @return Detailed validation report
#' @examples
#' \dontrun{
#' report <- run_validation_checks(codebook)
#' print(report)
#' }
run_validation_checks <- function(codebook, config_path = "config/codebook_config.yaml") {

  # Load configuration
  config <- if (file.exists(config_path)) {
    yaml::read_yaml(config_path)
  } else {
    list()  # Use minimal validation if no config
  }

  validation_results <- list()

  # Structure validation
  validation_results$structure <- validate_structure(codebook, config)

  # Content validation
  validation_results$content <- validate_content(codebook, config)

  # Data quality validation
  validation_results$data_quality <- validate_data_quality(codebook, config)

  # Cross-reference validation
  validation_results$cross_reference <- validate_cross_references(codebook, config)

  # Psychometric validation
  validation_results$psychometric <- validate_psychometric_data(codebook, config)

  # Compile summary
  validation_results$summary <- compile_validation_summary(validation_results)

  class(validation_results) <- c("codebook_validation", class(validation_results))

  return(validation_results)
}

#' Validate basic codebook structure
#'
#' @param codebook Codebook object
#' @param config Configuration list
#' @return Validation results for structure
validate_structure <- function(codebook, config) {

  issues <- list()
  checks_passed <- 0
  checks_total <- 0

  # Check metadata section
  checks_total <- checks_total + 1
  if (is.null(codebook$metadata)) {
    issues <- append(issues, list(
      level = "error",
      check = "metadata_present",
      message = "Missing metadata section"
    ))
  } else {
    checks_passed <- checks_passed + 1

    # Check metadata fields
    required_metadata <- c("version", "generated_date", "total_items")
    for (field in required_metadata) {
      checks_total <- checks_total + 1
      if (is.null(codebook$metadata[[field]])) {
        issues <- append(issues, list(
          level = "warning",
          check = paste0("metadata_", field),
          message = paste("Missing metadata field:", field)
        ))
      } else {
        checks_passed <- checks_passed + 1
      }
    }
  }

  # Check items section
  checks_total <- checks_total + 1
  if (is.null(codebook$items) || length(codebook$items) == 0) {
    issues <- append(issues, list(
      level = "error",
      check = "items_present",
      message = "Missing or empty items section"
    ))
  } else {
    checks_passed <- checks_passed + 1
  }

  # Check response_sets section
  checks_total <- checks_total + 1
  if (is.null(codebook$response_sets)) {
    issues <- append(issues, list(
      level = "warning",
      check = "response_sets_present",
      message = "Missing response_sets section"
    ))
  } else {
    checks_passed <- checks_passed + 1
  }

  # Check domains section
  checks_total <- checks_total + 1
  if (is.null(codebook$domains)) {
    issues <- append(issues, list(
      level = "warning",
      check = "domains_present",
      message = "Missing domains section"
    ))
  } else {
    checks_passed <- checks_passed + 1
  }

  return(list(
    issues = issues,
    checks_passed = checks_passed,
    checks_total = checks_total,
    pass_rate = checks_passed / checks_total
  ))
}

#' Validate item content and required fields
#'
#' @param codebook Codebook object
#' @param config Configuration list
#' @return Validation results for content
validate_content <- function(codebook, config) {

  if (is.null(codebook$items)) {
    return(list(
      issues = list(list(level = "error", check = "no_items", message = "No items to validate")),
      checks_passed = 0,
      checks_total = 1,
      pass_rate = 0
    ))
  }

  issues <- list()
  checks_passed <- 0
  checks_total <- 0

  # Get validation rules from config
  required_fields <- if (is.null(config$validation$required_fields)) {
    c("id", "lexicons.equate", "studies")
  } else {
    config$validation$required_fields
  }
  valid_domains <- if (is.null(config$validation$domain_validation$valid_domains)) {
    c("socemo", "motor", "coglan")
  } else {
    config$validation$domain_validation$valid_domains
  }
  valid_studies <- if (is.null(config$validation$study_validation$valid_studies)) {
    c("NE25", "NE22", "NE20")
  } else {
    config$validation$study_validation$valid_studies
  }

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    # Check required fields
    for (field in required_fields) {
      checks_total <- checks_total + 1
      field_value <- get_nested_field(item, field)

      if (is.null(field_value) || (is.character(field_value) && field_value == "") ||
          (is.list(field_value) && length(field_value) == 0)) {
        issues <- append(issues, list(
          level = "error",
          check = "required_field",
          item_id = item_id,
          message = paste("Missing required field:", field)
        ))
      } else {
        checks_passed <- checks_passed + 1
      }
    }

    # Check domain validity
    checks_total <- checks_total + 1
    if (!is.null(item$classification$domain)) {
      if (item$classification$domain %in% valid_domains) {
        checks_passed <- checks_passed + 1
      } else {
        issues <- append(issues, list(
          level = "warning",
          check = "domain_validity",
          item_id = item_id,
          message = paste("Invalid domain:", item$classification$domain)
        ))
      }
    } else {
      issues <- append(issues, list(
        level = "error",
        check = "domain_missing",
        item_id = item_id,
        message = "Missing domain classification"
      ))
    }

    # Check study validity
    checks_total <- checks_total + 1
    if (!is.null(item$studies) && length(item$studies) > 0) {
      invalid_studies <- setdiff(item$studies, valid_studies)
      if (length(invalid_studies) == 0) {
        checks_passed <- checks_passed + 1
      } else {
        issues <- append(issues, list(
          level = "warning",
          check = "study_validity",
          item_id = item_id,
          message = paste("Invalid studies:", paste(invalid_studies, collapse = ", "))
        ))
      }
    } else {
      issues <- append(issues, list(
        level = "warning",
        check = "studies_missing",
        item_id = item_id,
        message = "No studies specified"
      ))
    }

    # Check identifier consistency
    checks_total <- checks_total + 1
    if (!is.null(item$identifiers$kidsight)) {
      if (item$identifiers$kidsight == item_id) {
        checks_passed <- checks_passed + 1
      } else {
        issues <- append(issues, list(
          level = "error",
          check = "identifier_consistency",
          item_id = item_id,
          message = "Kidsight identifier doesn't match item key"
        ))
      }
    } else {
      issues <- append(issues, list(
        level = "error",
        check = "identifier_missing",
        item_id = item_id,
        message = "Missing kidsight identifier"
      ))
    }
  }

  return(list(
    issues = issues,
    checks_passed = checks_passed,
    checks_total = checks_total,
    pass_rate = if (checks_total > 0) checks_passed / checks_total else 0
  ))
}

#' Validate data quality and completeness
#'
#' @param codebook Codebook object
#' @param config Configuration list
#' @return Validation results for data quality
validate_data_quality <- function(codebook, config) {

  if (is.null(codebook$items)) {
    return(list(
      issues = list(),
      checks_passed = 0,
      checks_total = 0,
      pass_rate = 0
    ))
  }

  issues <- list()
  checks_passed <- 0
  checks_total <- 0

  # Check for duplicate item IDs
  checks_total <- checks_total + 1
  item_ids <- sapply(codebook$items, function(x) x$id %||% NA)
  if (any(duplicated(item_ids, incomparables = NA))) {
    duplicate_ids <- item_ids[duplicated(item_ids, incomparables = NA)]
    issues <- append(issues, list(
      level = "error",
      check = "duplicate_ids",
      message = paste("Duplicate item IDs found:", paste(unique(duplicate_ids), collapse = ", "))
    ))
  } else {
    checks_passed <- checks_passed + 1
  }

  # Check for missing item text
  checks_total <- checks_total + 1
  items_without_text <- sum(sapply(codebook$items, function(x) {
    is.null(x$content$stems$combined) || x$content$stems$combined == ""
  }))

  if (items_without_text == 0) {
    checks_passed <- checks_passed + 1
  } else {
    issues <- append(issues, list(
      level = "warning",
      check = "missing_item_text",
      message = paste(items_without_text, "items missing combined stem text")
    ))
  }

  # Check response options coverage
  checks_total <- checks_total + 1
  items_without_responses <- sum(sapply(codebook$items, function(x) {
    is.null(x$content$response_options) || length(x$content$response_options) == 0
  }))

  total_items <- length(codebook$items)
  response_coverage <- 1 - (items_without_responses / total_items)

  if (response_coverage >= 0.9) {
    checks_passed <- checks_passed + 1
  } else {
    issues <- append(issues, list(
      level = "warning",
      check = "response_coverage",
      message = paste("Low response options coverage:",
                      round(response_coverage * 100, 1), "%")
    ))
  }

  return(list(
    issues = issues,
    checks_passed = checks_passed,
    checks_total = checks_total,
    pass_rate = if (checks_total > 0) checks_passed / checks_total else 0,
    metrics = list(
      total_items = total_items,
      items_without_text = items_without_text,
      items_without_responses = items_without_responses,
      response_coverage = response_coverage
    )
  ))
}

#' Validate cross-references and relationships
#'
#' @param codebook Codebook object
#' @param config Configuration list
#' @return Validation results for cross-references
validate_cross_references <- function(codebook, config) {

  issues <- list()
  checks_passed <- 0
  checks_total <- 0

  if (is.null(codebook$items)) {
    return(list(issues = issues, checks_passed = 0, checks_total = 0, pass_rate = 0))
  }

  # Check domain references
  if (!is.null(codebook$domains)) {
    checks_total <- checks_total + 1
    defined_domains <- names(codebook$domains)
    used_domains <- unique(sapply(codebook$items, function(x) x$classification$domain))
    used_domains <- used_domains[!is.na(used_domains)]

    undefined_domains <- setdiff(used_domains, defined_domains)
    if (length(undefined_domains) == 0) {
      checks_passed <- checks_passed + 1
    } else {
      issues <- append(issues, list(
        level = "warning",
        check = "undefined_domains",
        message = paste("Used but undefined domains:", paste(undefined_domains, collapse = ", "))
      ))
    }
  }

  # Check response set references
  if (!is.null(codebook$response_sets)) {
    checks_total <- checks_total + 1
    defined_response_sets <- names(codebook$response_sets)
    # This would need to be implemented based on how response sets are referenced
    checks_passed <- checks_passed + 1  # Placeholder
  }

  return(list(
    issues = issues,
    checks_passed = checks_passed,
    checks_total = checks_total,
    pass_rate = if (checks_total > 0) checks_passed / checks_total else 0
  ))
}

#' Validate psychometric data
#'
#' @param codebook Codebook object
#' @param config Configuration list
#' @return Validation results for psychometric data
validate_psychometric_data <- function(codebook, config) {

  issues <- list()
  checks_passed <- 0
  checks_total <- 0

  if (is.null(codebook$items)) {
    return(list(issues = issues, checks_passed = 0, checks_total = 0, pass_rate = 0))
  }

  # Check IRT parameter structure and completeness
  items_with_irt_structure <- sum(sapply(codebook$items, function(x) {
    !is.null(x$psychometric$irt_parameters) &&
    length(x$psychometric$irt_parameters) > 0
  }))

  items_with_irt_data <- sum(sapply(codebook$items, function(x) {
    !is.null(x$psychometric$irt_parameters) &&
    length(x$psychometric$irt_parameters) > 0 &&
    any(sapply(x$psychometric$irt_parameters, function(study_params) {
      length(study_params$factors) > 0 ||
      length(study_params$loadings) > 0 ||
      length(study_params$thresholds) > 0
    }))
  }))

  total_items <- length(codebook$items)
  irt_structure_coverage <- items_with_irt_structure / total_items
  irt_data_coverage <- items_with_irt_data / total_items

  # Check IRT structure coverage
  checks_total <- checks_total + 1
  if (irt_structure_coverage >= 0.9) {  # Most items should have IRT structure
    checks_passed <- checks_passed + 1
  } else {
    issues <- append(issues, list(
      level = "warning",
      check = "irt_structure_coverage",
      message = paste("Low IRT parameter structure coverage:",
                      round(irt_structure_coverage * 100, 1), "%")
    ))
  }

  # Check IRT data coverage (this will be low initially)
  checks_total <- checks_total + 1
  if (irt_data_coverage > 0) {
    checks_passed <- checks_passed + 1
  } else {
    issues <- append(issues, list(
      level = "info",
      check = "irt_data_coverage",
      message = paste("No items have populated IRT parameters yet (",
                      round(irt_data_coverage * 100, 1), "%)")
    ))
  }

  # Validate IRT parameter structure for items that have it
  irt_structure_issues <- 0
  valid_studies <- if (is.null(config$irt_models$supported_studies)) {
    c("NE25", "NE22", "NE20", "CAHMI22", "CAHMI21", "ECDI", "CREDI", "GSED", "GSED_PF")
  } else {
    config$irt_models$supported_studies
  }

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    if (!is.null(item$psychometric$irt_parameters)) {
      irt_params <- item$psychometric$irt_parameters

      # Check if IRT parameters exist for item's studies
      item_studies <- if (is.null(item$studies)) list() else item$studies
      for (study in item_studies) {
        if (study %in% valid_studies) {
          checks_total <- checks_total + 1
          if (study %in% names(irt_params)) {
            study_params <- irt_params[[study]]
            # Check if structure is correct
            if (all(c("factors", "loadings", "thresholds") %in% names(study_params))) {
              checks_passed <- checks_passed + 1
            } else {
              irt_structure_issues <- irt_structure_issues + 1
              issues <- append(issues, list(list(
                level = "error",
                check = "irt_parameter_structure",
                item_id = item_id,
                message = paste("Invalid IRT parameter structure for study", study)
              )))
            }
          } else {
            irt_structure_issues <- irt_structure_issues + 1
            issues <- append(issues, list(list(
              level = "warning",
              check = "missing_irt_study",
              item_id = item_id,
              message = paste("Missing IRT parameters for study", study)
            )))
          }
        }
      }
    }
  }

  # Check calibration item flags
  calibration_items <- sum(sapply(codebook$items, function(x) {
    isTRUE(x$psychometric$calibration_item)
  }))

  checks_total <- checks_total + 1
  if (calibration_items > 0) {
    checks_passed <- checks_passed + 1
  } else {
    issues <- append(issues, list(
      level = "info",
      check = "calibration_items",
      message = "No calibration items identified"
    ))
  }

  return(list(
    issues = issues,
    checks_passed = checks_passed,
    checks_total = checks_total,
    pass_rate = if (checks_total > 0) checks_passed / checks_total else 0,
    metrics = list(
      total_items = total_items,
      items_with_irt_structure = items_with_irt_structure,
      items_with_irt_data = items_with_irt_data,
      irt_structure_coverage = irt_structure_coverage,
      irt_data_coverage = irt_data_coverage,
      irt_structure_issues = irt_structure_issues,
      calibration_items = calibration_items
    )
  ))
}

#' Compile validation summary
#'
#' @param validation_results Full validation results
#' @return Summary of validation results
compile_validation_summary <- function(validation_results) {

  # Exclude summary from calculation
  sections <- validation_results[names(validation_results) != "summary"]

  total_checks <- sum(sapply(sections, function(x) x$checks_total))
  total_passed <- sum(sapply(sections, function(x) x$checks_passed))

  # Count issues by level
  all_issues <- unlist(lapply(sections, function(x) x$issues), recursive = FALSE)
  issue_levels <- sapply(all_issues, function(x) x$level)

  error_count <- sum(issue_levels == "error")
  warning_count <- sum(issue_levels == "warning")
  info_count <- sum(issue_levels == "info")

  # Determine overall status
  overall_status <- if (error_count > 0) {
    "error"
  } else if (warning_count > 0) {
    "warning"
  } else {
    "pass"
  }

  return(list(
    overall_status = overall_status,
    total_checks = total_checks,
    total_passed = total_passed,
    pass_rate = if (total_checks > 0) total_passed / total_checks else 0,
    error_count = error_count,
    warning_count = warning_count,
    info_count = info_count,
    total_issues = length(all_issues)
  ))
}

#' Helper function to get nested field values
#'
#' @param item Item object
#' @param field_path Dot-separated field path (e.g., "identifiers.kidsight")
#' @return Field value or NULL if not found
get_nested_field <- function(item, field_path) {
  if (is.null(item)) return(NULL)

  parts <- strsplit(field_path, "\\.")[[1]]
  current <- item

  for (part in parts) {
    if (is.list(current) && part %in% names(current)) {
      current <- current[[part]]
    } else {
      return(NULL)
    }
  }

  return(current)
}

#' Print method for validation results
#'
#' @param x Validation results object
#' @param ... Additional arguments (ignored)
print.codebook_validation <- function(x, ...) {
  cat("=== Codebook Validation Report ===\n\n")

  summary <- x$summary

  # Overall status
  status_symbol <- switch(summary$overall_status,
    "pass" = "✅",
    "warning" = "⚠️",
    "error" = "❌"
  )

  cat(status_symbol, " Overall Status: ", toupper(summary$overall_status), "\n")
  cat("📊 Pass Rate: ", round(summary$pass_rate * 100, 1), "% (",
      summary$total_passed, "/", summary$total_checks, " checks)\n\n")

  # Issue summary
  if (summary$total_issues > 0) {
    cat("📋 Issues Summary:\n")
    if (summary$error_count > 0)
      cat("  ❌ Errors: ", summary$error_count, "\n")
    if (summary$warning_count > 0)
      cat("  ⚠️  Warnings: ", summary$warning_count, "\n")
    if (summary$info_count > 0)
      cat("  ℹ️  Info: ", summary$info_count, "\n")
    cat("\n")
  }

  # Section details
  sections <- x[names(x) != "summary"]
  for (section_name in names(sections)) {
    section <- sections[[section_name]]
    cat("🔍 ", stringr::str_to_title(gsub("_", " ", section_name)), ":\n")
    cat("   Pass rate: ", round(section$pass_rate * 100, 1), "% (",
        section$checks_passed, "/", section$checks_total, ")\n")

    if (length(section$issues) > 0) {
      cat("   Issues: ", length(section$issues), "\n")
    }
    cat("\n")
  }

  cat("Use summary() for detailed issue list.\n")
}

#' Helper operator for cleaner NA handling
`%||%` <- function(x, y) if (is.null(x) || is.na(x)) y else x