#!/usr/bin/env Rscript
#
# Fix Codebook Response Sets
#
# Purpose:
# 1. Create study-specific response sets (especially NE25 with value 9 for Don't Know)
# 2. Convert inline response options to response set references
# 3. Ensure all items use study-specific response sets
#
# Author: Kidsights Data Platform
# Date: September 17, 2025

cat("=== Fixing Codebook Response Sets ===\n\n")

# Load required packages
required_packages <- c("jsonlite")

install_and_load <- function(packages) {
  for (pkg in packages) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      cat("Installing package:", pkg, "\n")
      install.packages(pkg, dependencies = TRUE, repos = "https://cran.rstudio.com/")
      library(pkg, character.only = TRUE)
      cat("Successfully installed and loaded:", pkg, "\n")
    } else {
      cat("Package already available:", pkg, "\n")
    }
  }
}

install_and_load(required_packages)

# Load current codebook
codebook_path <- "codebook/data/codebook.json"
if (!file.exists(codebook_path)) {
  stop("ERROR: Codebook not found at: ", codebook_path)
}

cat("Loading current codebook...\n")
codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)
cat("✓ Codebook loaded - Version:", codebook$metadata$version, "\n")
cat("✓ Total items:", length(codebook$items), "\n")

# Create backup
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
backup_path <- paste0("codebook/data/codebook_pre_response_sets_fix_", timestamp, ".json")
cat("Creating backup...\n")
jsonlite::write_json(codebook, backup_path, auto_unbox = TRUE, pretty = TRUE)
cat("✓ Backup created:", backup_path, "\n")

# 1. ADD NEW STUDY-SPECIFIC RESPONSE SETS
cat("\n=== Adding Study-Specific Response Sets ===\n")

# PS Frequency response sets (study-specific)
codebook$response_sets$ps_frequency_ne25 <- list(
  list(value = 0, label = "Never or Almost Never"),
  list(value = 1, label = "Sometimes"),
  list(value = 2, label = "Often"),
  list(value = 9, label = "Don't Know", missing = TRUE)  # NE25 uses 9, not -9
)

codebook$response_sets$ps_frequency_ne22 <- list(
  list(value = 0, label = "Never or Almost Never"),
  list(value = 1, label = "Sometimes"),
  list(value = 2, label = "Often"),
  list(value = -9, label = "Don't Know", missing = TRUE)  # NE22 uses -9
)

codebook$response_sets$ps_frequency_ne20 <- list(
  list(value = 0, label = "Never or Almost Never"),
  list(value = 1, label = "Sometimes"),
  list(value = 2, label = "Often"),
  list(value = -9, label = "Don't Know", missing = TRUE)  # NE20 uses -9
)

codebook$response_sets$ps_frequency_gsed_pf <- list(
  list(value = 0, label = "Never or Almost Never"),
  list(value = 1, label = "Sometimes"),
  list(value = 2, label = "Often"),
  list(value = -9, label = "Don't Know", missing = TRUE)  # GSED_PF uses -9
)

# Standard binary response sets (study-specific)
codebook$response_sets$standard_binary_ne25 <- list(
  list(value = 1, label = "Yes"),
  list(value = 0, label = "No"),
  list(value = 9, label = "Don't Know", missing = TRUE)  # NE25 uses 9, not -9
)

# Common inline response patterns found - create response sets for them
codebook$response_sets$likert_5_frequency_ne25 <- list(
  list(value = 4, label = "Always"),
  list(value = 3, label = "Most of the time"),
  list(value = 2, label = "About half the time"),
  list(value = 1, label = "Sometimes"),
  list(value = 0, label = "Never"),
  list(value = 9, label = "Don't Know", missing = TRUE)
)

codebook$response_sets$likert_4_skill_ne25 <- list(
  list(value = 3, label = "Very well"),
  list(value = 2, label = "Somewhat well"),
  list(value = 1, label = "Not very well"),
  list(value = 0, label = "Not at all"),
  list(value = 9, label = "Don't Know", missing = TRUE)
)

codebook$response_sets$count_10_ne25 <- list(
  list(value = 0, label = "0"),
  list(value = 1, label = "1"),
  list(value = 2, label = "2"),
  list(value = 3, label = "3"),
  list(value = 4, label = "4"),
  list(value = 5, label = "5"),
  list(value = 6, label = "6"),
  list(value = 7, label = "7"),
  list(value = 8, label = "8"),
  list(value = 9, label = "9"),
  list(value = 10, label = "10 or more"),
  list(value = 99, label = "Don't Know", missing = TRUE)
)

cat("✓ Added study-specific response sets\n")

# 2. UPDATE PS ITEMS TO USE STUDY-SPECIFIC RESPONSE SETS
cat("\n=== Updating PS Items ===\n")
ps_items_updated <- 0

for (item_id in names(codebook$items)) {
  if (grepl("^PS[0-9]", item_id)) {
    item_data <- codebook$items[[item_id]]
    studies <- item_data$studies

    if ("content" %in% names(item_data) && "response_options" %in% names(item_data$content)) {
      response_opts <- item_data$content$response_options

      # Update each study's response options
      for (study in names(response_opts)) {
        if (response_opts[[study]] == "ps_frequency") {
          # Map to study-specific response set
          if (study == "ne25") {
            codebook$items[[item_id]]$content$response_options[[study]] <- "ps_frequency_ne25"
          } else if (study == "ne22") {
            codebook$items[[item_id]]$content$response_options[[study]] <- "ps_frequency_ne22"
          } else if (study == "ne20") {
            codebook$items[[item_id]]$content$response_options[[study]] <- "ps_frequency_ne20"
          } else if (study == "gsed_pf") {
            codebook$items[[item_id]]$content$response_options[[study]] <- "ps_frequency_gsed_pf"
          }
        }
      }
      ps_items_updated <- ps_items_updated + 1
    }
  }
}

cat("✓ Updated", ps_items_updated, "PS items with study-specific response sets\n")

# 3. UPDATE BINARY ITEMS TO USE NE25-SPECIFIC RESPONSE SETS
cat("\n=== Updating Binary Items for NE25 ===\n")
binary_items_updated <- 0

for (item_id in names(codebook$items)) {
  item_data <- codebook$items[[item_id]]

  if ("content" %in% names(item_data) && "response_options" %in% names(item_data$content)) {
    response_opts <- item_data$content$response_options

    if ("ne25" %in% names(response_opts)) {
      ne25_response <- response_opts$ne25
      # Check if it's a string and equals "standard_binary"
      if (is.character(ne25_response) && length(ne25_response) == 1 && ne25_response == "standard_binary") {
        codebook$items[[item_id]]$content$response_options$ne25 <- "standard_binary_ne25"
        binary_items_updated <- binary_items_updated + 1
      }
    }
  }
}

cat("✓ Updated", binary_items_updated, "binary items to use NE25-specific response sets\n")

# 4. CONVERT INLINE RESPONSE OPTIONS TO RESPONSE SET REFERENCES
cat("\n=== Converting Inline Response Options ===\n")
inline_items_converted <- 0

# Helper function to identify response pattern
identify_response_pattern <- function(response_array) {
  if (length(response_array) == 0) return(NULL)

  # Extract values and labels
  values <- sapply(response_array, function(x) x$value)
  labels <- sapply(response_array, function(x) x$label)

  # Check for common patterns
  if (length(values) == 5 && all(values == c(4, 3, 2, 1, 0))) {
    if (any(grepl("Always|Most|half|Sometimes|Never", labels, ignore.case = TRUE))) {
      return("likert_5_frequency_ne25")
    }
  }

  if (length(values) == 4 && all(values == c(3, 2, 1, 0))) {
    if (any(grepl("Very well|Somewhat|Not very|Not at all", labels, ignore.case = TRUE))) {
      return("likert_4_skill_ne25")
    }
  }

  if (length(values) >= 10 && any(grepl("or more", labels, ignore.case = TRUE))) {
    return("count_10_ne25")
  }

  # For yes/no patterns
  if (length(values) == 2 && all(sort(values) == c(0, 1))) {
    return("standard_binary_ne25")
  }

  return(NULL)  # Keep as inline if pattern not recognized
}

for (item_id in names(codebook$items)) {
  item_data <- codebook$items[[item_id]]

  if ("content" %in% names(item_data) && "response_options" %in% names(item_data$content)) {
    response_opts <- item_data$content$response_options

    for (study in names(response_opts)) {
      if (is.list(response_opts[[study]]) && length(response_opts[[study]]) > 0) {
        # This is an inline response array
        response_set_name <- identify_response_pattern(response_opts[[study]])

        if (!is.null(response_set_name)) {
          codebook$items[[item_id]]$content$response_options[[study]] <- response_set_name
          inline_items_converted <- inline_items_converted + 1
          cat("  Converted", item_id, "study", study, "to", response_set_name, "\n")
        } else {
          cat("  WARNING: Could not identify pattern for", item_id, "study", study, "\n")
        }
      }
    }
  }
}

cat("✓ Converted", inline_items_converted, "inline response options to response set references\n")

# 5. UPDATE METADATA
cat("\n=== Updating Metadata ===\n")
codebook$metadata$version <- "2.8.0"
codebook$metadata$last_response_sets_fix <- as.character(Sys.time())
codebook$metadata$previous_version <- "2.7.1"
codebook$metadata$response_sets_fix_backup <- basename(backup_path)

# Log changes
changes_log <- list(
  ps_items_updated = ps_items_updated,
  binary_items_updated = binary_items_updated,
  inline_items_converted = inline_items_converted,
  new_response_sets_added = c(
    "ps_frequency_ne25", "ps_frequency_ne22", "ps_frequency_ne20", "ps_frequency_gsed_pf",
    "standard_binary_ne25", "likert_5_frequency_ne25", "likert_4_skill_ne25", "count_10_ne25"
  )
)

codebook$metadata$response_sets_fix_log <- changes_log
cat("✓ Updated metadata to version 2.8.0\n")

# 6. SAVE UPDATED CODEBOOK
cat("\n=== Saving Updated Codebook ===\n")
jsonlite::write_json(codebook, codebook_path, auto_unbox = TRUE, pretty = TRUE)
cat("✓ Updated codebook saved\n")

# 7. VALIDATION SUMMARY
cat("\n=== Validation Summary ===\n")
cat("- PS items updated:", ps_items_updated, "\n")
cat("- Binary items updated for NE25:", binary_items_updated, "\n")
cat("- Inline response options converted:", inline_items_converted, "\n")
cat("- New response sets added:", length(changes_log$new_response_sets_added), "\n")
cat("- Codebook version: 2.7.1 → 2.8.0\n")
cat("- Backup created:", backup_path, "\n")

# Create summary log file
log_path <- paste0("scripts/codebook/response_sets_fix_log_", timestamp, ".txt")
log_content <- paste0(
  "Codebook Response Sets Fix Log\n",
  "Date: ", Sys.time(), "\n",
  "Script: fix_codebook_response_sets.R\n\n",
  "SUMMARY:\n",
  "- Total items: ", length(codebook$items), "\n",
  "- PS items updated: ", ps_items_updated, "\n",
  "- Binary items updated for NE25: ", binary_items_updated, "\n",
  "- Inline response options converted: ", inline_items_converted, "\n",
  "- Backup: ", backup_path, "\n",
  "- Version: 2.7.1 → 2.8.0\n\n",
  "KEY CHANGES:\n",
  "- NE25 now uses value 9 (not -9) for 'Don't Know'\n",
  "- All studies have study-specific response sets\n",
  "- Eliminated inline response options where possible\n",
  "- Maintained single source of truth for response labels\n"
)

writeLines(log_content, log_path)
cat("✓ Fix log saved:", log_path, "\n")

cat("\n=== Response Sets Fix Complete ===\n")
cat("CRITICAL CHANGE: NE25 now uses value 9 for 'Don't Know' instead of -9\n")
cat("This affects recoding - ensure pipeline is updated accordingly.\n")