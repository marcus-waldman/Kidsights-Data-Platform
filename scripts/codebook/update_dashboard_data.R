#!/usr/bin/env Rscript
#
# Update Dashboard Data
#
# Purpose: Update the JSON data file that the dashboard uses without full rendering
#
# Author: Kidsights Data Platform
# Date: September 17, 2025

cat("=== Updating Dashboard Data ===\n\n")

# Load required packages
if (!require(jsonlite, quietly = TRUE)) {
  install.packages("jsonlite", repos = "https://cran.rstudio.com/")
  library(jsonlite)
}

# Load updated codebook
codebook_path <- "codebook/data/codebook.json"
output_path <- "docs/codebook_dashboard/search.json"

if (!file.exists(codebook_path)) {
  stop("ERROR: Codebook not found at: ", codebook_path)
}

cat("Loading updated codebook...\n")
codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

cat("✓ Codebook loaded - Version:", codebook$metadata$version, "\n")
cat("✓ Total items:", length(codebook$items), "\n")

# Create search data for dashboard
search_data <- list()

for (item_id in names(codebook$items)) {
  item <- codebook$items[[item_id]]

  # Get basic info
  studies <- paste(item$studies %||% character(0), collapse = ", ")

  # Get domain info
  domains <- character(0)
  if ("domains" %in% names(item)) {
    for (domain_name in names(item$domains)) {
      domain_info <- item$domains[[domain_name]]
      domains <- c(domains, paste0(domain_name, ": ", domain_info$value))
    }
  }
  domains_text <- paste(domains, collapse = "; ")

  # Get question text
  question <- "N/A"
  if ("content" %in% names(item) && "stems" %in% names(item$content)) {
    stems <- item$content$stems
    question <- stems$combined %||% stems$ne25 %||% stems$ne22 %||% "N/A"
    # Clean HTML and truncate
    question <- gsub("<[^>]*>", "", question)
    if (nchar(question) > 200) {
      question <- paste0(substr(question, 1, 200), "...")
    }
  }

  # Get response options info
  response_info <- character(0)
  if ("content" %in% names(item) && "response_options" %in% names(item$content)) {
    resp_opts <- item$content$response_options
    for (study in names(resp_opts)) {
      response_info <- c(response_info, paste0(study, ": ", resp_opts[[study]]))
    }
  }
  response_text <- paste(response_info, collapse = "; ")

  # Get IRT parameter info
  irt_info <- character(0)
  if ("psychometric" %in% names(item) && "irt_parameters" %in% names(item$psychometric)) {
    irt_params <- item$psychometric$irt_parameters
    for (study in names(irt_params)) {
      params <- irt_params[[study]]
      has_loadings <- length(params$loadings %||% numeric(0)) > 0
      has_thresholds <- length(params$thresholds %||% numeric(0)) > 0
      if (has_loadings || has_thresholds) {
        irt_info <- c(irt_info, paste0(study, ": ", length(params$loadings %||% numeric(0)), " loadings, ", length(params$thresholds %||% numeric(0)), " thresholds"))
      }
    }
  }
  irt_text <- if (length(irt_info) > 0) paste(irt_info, collapse = "; ") else "No parameters"

  # Build search entry
  search_entry <- list(
    id = item_id,
    title = item_id,
    studies = studies,
    domains = domains_text,
    question = question,
    response_options = response_text,
    irt_parameters = irt_text,
    content = paste(item_id, studies, domains_text, question, response_text, irt_text)
  )

  search_data[[item_id]] <- search_entry
}

# Save updated search data
cat("\nSaving updated search data...\n")
write_json(search_data, output_path, auto_unbox = TRUE, pretty = TRUE)

cat("✓ Dashboard data updated at:", output_path, "\n")
cat("✓ Search entries created:", length(search_data), "\n")

# Also create a summary file for verification
summary_info <- list(
  updated = as.character(Sys.time()),
  codebook_version = codebook$metadata$version,
  total_items = length(codebook$items),
  ps_items = length(grep("^PS", names(codebook$items))),
  items_with_ne25 = length(Filter(function(x) "NE25" %in% (x$studies %||% character(0)), codebook$items)),
  response_coverage = list(
    total_ne25_items = length(Filter(function(x) "NE25" %in% (x$studies %||% character(0)), codebook$items)),
    items_with_response_options = length(Filter(function(x) {
      "NE25" %in% (x$studies %||% character(0)) &&
      "content" %in% names(x) &&
      "response_options" %in% names(x$content) &&
      "ne25" %in% names(x$content$response_options)
    }, codebook$items))
  )
)

summary_path <- "docs/codebook_dashboard/dashboard_summary.json"
write_json(summary_info, summary_path, auto_unbox = TRUE, pretty = TRUE)

cat("✓ Dashboard summary saved at:", summary_path, "\n")
cat("\nSummary:\n")
cat("- Codebook version:", summary_info$codebook_version, "\n")
cat("- Total items:", summary_info$total_items, "\n")
cat("- PS items:", summary_info$ps_items, "\n")
cat("- NE25 items:", summary_info$items_with_ne25, "\n")
cat("- NE25 items with response options:", summary_info$response_coverage$items_with_response_options, "/", summary_info$response_coverage$total_ne25_items, "\n")

cat("\n=== Dashboard Data Update Complete ===\n")
cat("Note: The HTML dashboard itself is from Sep 16 and shows old data.\n")
cat("The search.json has been updated with current data (version 2.7.1).\n")
cat("For full dashboard refresh, Quarto/Pandoc tools would be needed.\n")