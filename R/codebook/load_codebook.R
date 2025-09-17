#' Load and Validate JSON Codebook
#'
#' Functions for loading, validating, and working with the JSON codebook

library(jsonlite)
library(yaml)

#' Load JSON codebook with validation
#'
#' @param path Path to JSON codebook file
#' @param validate Whether to run validation checks (default: TRUE)
#' @return List representing the codebook with class "codebook"
#' @examples
#' \dontrun{
#' codebook <- load_codebook("codebook/data/codebook.json")
#' print(codebook)
#' }
load_codebook <- function(path = "codebook/data/codebook.json", validate = TRUE) {

  # Check if file exists
  if (!file.exists(path)) {
    stop("Codebook file not found: ", path)
  }

  message("Loading codebook from: ", path)

  # Load JSON
  tryCatch({
    codebook <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  }, error = function(e) {
    stop("Failed to parse JSON codebook: ", e$message)
  })

  # Add class attribute
  class(codebook) <- c("codebook", class(codebook))

  # Run validation if requested
  if (validate) {
    validation_result <- validate_codebook(codebook)
    if (!validation_result$valid) {
      warning("Codebook validation issues found:\n",
              paste(validation_result$issues, collapse = "\n"))
    } else {
      message("Codebook validation passed")
    }
  }

  message("Loaded ", codebook$metadata$total_items, " items from ",
          codebook$metadata$version, " codebook")

  return(codebook)
}

#' Validate codebook structure and content
#'
#' @param codebook Codebook object
#' @return List with validation results
validate_codebook <- function(codebook) {

  # Load configuration for validation rules
  config_path <- "config/codebook_config.yaml"
  if (file.exists(config_path)) {
    config <- yaml::read_yaml(config_path)
  } else {
    warning("Configuration file not found, using basic validation")
    config <- list()
  }

  issues <- character()
  valid <- TRUE

  # Check metadata
  if (is.null(codebook$metadata)) {
    issues <- c(issues, "Missing metadata section")
    valid <- FALSE
  }

  # Check items section
  if (is.null(codebook$items) || length(codebook$items) == 0) {
    issues <- c(issues, "Missing or empty items section")
    valid <- FALSE
  } else {

    # Check each item
    for (item_id in names(codebook$items)) {
      item <- codebook$items[[item_id]]

      # Check required fields
      if (is.null(item$id)) {
        issues <- c(issues, paste("Item", item_id, "missing id field"))
        valid <- FALSE
      }

      if (is.null(item$studies) || length(item$studies) == 0) {
        issues <- c(issues, paste("Item", item_id, "missing studies field"))
        valid <- FALSE
      }

      if (is.null(item$classification$domain)) {
        issues <- c(issues, paste("Item", item_id, "missing domain"))
        valid <- FALSE
      }

      # Check domain validity if config available
      if (!is.null(config$validation$domain_validation$valid_domains)) {
        valid_domains <- config$validation$domain_validation$valid_domains
        if (!item$classification$domain %in% valid_domains) {
          issues <- c(issues, paste("Item", item_id, "has invalid domain:",
                                  item$classification$domain))
          valid <- FALSE
        }
      }

      # Check identifier consistency
      if (item$identifiers$kidsight != item_id) {
        issues <- c(issues, paste("Item", item_id, "identifier mismatch"))
        valid <- FALSE
      }
    }
  }

  # Check for duplicate IDs
  if (!is.null(codebook$items)) {
    item_ids <- sapply(codebook$items, function(x) x$id)
    if (any(duplicated(item_ids))) {
      duplicate_ids <- item_ids[duplicated(item_ids)]
      issues <- c(issues, paste("Duplicate item IDs found:", paste(duplicate_ids, collapse = ", ")))
      valid <- FALSE
    }
  }

  return(list(
    valid = valid,
    issues = issues,
    n_issues = length(issues)
  ))
}

#' Print method for codebook objects
#'
#' @param x Codebook object
#' @param ... Additional arguments (ignored)
print.codebook <- function(x, ...) {
  cat("Kidsights Codebook (JSON)\n")
  cat("Version:", x$metadata$version, "\n")
  cat("Generated:", x$metadata$generated_date, "\n")
  cat("Items:", x$metadata$total_items, "\n")

  if (!is.null(x$items)) {
    # Count items by domain
    domains <- sapply(x$items, function(item) item$classification$domain %||% "unknown")
    domain_counts <- table(domains)

    cat("\nItems by domain:\n")
    for (domain in names(domain_counts)) {
      cat(" ", domain, ":", domain_counts[domain], "\n")
    }

    # Count items by study
    all_studies <- unique(unlist(sapply(x$items, function(item) item$studies)))
    cat("\nStudies represented:", paste(all_studies, collapse = ", "), "\n")
  }

  cat("\nUse summary() for more details or query functions to explore items.\n")
}

#' Summary method for codebook objects
#'
#' @param object Codebook object
#' @param ... Additional arguments (ignored)
summary.codebook <- function(object, ...) {
  cat("=== Kidsights Codebook Summary ===\n\n")

  # Basic info
  cat("Basic Information:\n")
  cat("  Version:", object$metadata$version, "\n")
  cat("  Generated:", object$metadata$generated_date, "\n")
  cat("  Total items:", object$metadata$total_items, "\n\n")

  if (!is.null(object$items)) {
    # Domain breakdown
    cat("Domain Distribution:\n")
    domains <- sapply(object$items, function(item) item$classification$domain %||% "unknown")
    domain_counts <- table(domains)
    for (domain in names(sort(domain_counts, decreasing = TRUE))) {
      cat(sprintf("  %-15s: %3d items\n", domain, domain_counts[domain]))
    }

    # Study coverage
    cat("\nStudy Coverage:\n")
    study_counts <- table(unlist(sapply(object$items, function(item) item$studies)))
    for (study in names(sort(study_counts, decreasing = TRUE))) {
      cat(sprintf("  %-10s: %3d items\n", study, study_counts[study]))
    }

    # Response options
    cat("\nResponse Options Summary:\n")
    has_response_opts <- sum(sapply(object$items, function(item) {
      !is.null(item$content$response_options) &&
      length(item$content$response_options) > 0
    }))
    cat("  Items with response options:", has_response_opts, "/", length(object$items), "\n")

    # IRT parameters
    has_irt_params <- sum(sapply(object$items, function(item) {
      !is.null(item$psychometric$irt_parameters) &&
      length(item$psychometric$irt_parameters) > 0
    }))
    cat("  Items with IRT parameters:", has_irt_params, "/", length(object$items), "\n")

    # Calibration items
    calibration_items <- sum(sapply(object$items, function(item) {
      isTRUE(item$psychometric$calibration_item)
    }))
    cat("  Calibration items:", calibration_items, "/", length(object$items), "\n")
  }

  cat("\n")
}

#' Helper operator for cleaner NA handling
`%||%` <- function(x, y) if (is.null(x) || is.na(x)) y else x