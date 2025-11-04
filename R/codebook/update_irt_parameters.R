# =============================================================================
# Codebook IRT Parameters Update Functions
# =============================================================================
# Purpose: Interactive system for updating IRT parameters in codebook.json
#          Human-in-the-loop approach for adding/modifying calibrations
#
# Usage: Called by psychometric specialist agent or standalone
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

#' Interactive IRT Parameter Update
#'
#' Guides user through adding or updating IRT parameters for items
#' Human-in-the-loop approach ensures expert oversight
#'
#' @param codebook_path Path to codebook.json file
#' @return Updated codebook object (invisibly)
#' @export
interactive_parameter_update <- function(codebook_path = "codebook/data/codebook.json") {

  cat("\n", strrep("=", 70), "\n")
  cat("INTERACTIVE IRT PARAMETER UPDATE\n")
  cat(strrep("=", 70), "\n\n")

  # Load existing codebook
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  cat(sprintf("Loading codebook: %s\n", codebook_path))
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)
  cat("[OK] Codebook loaded\n\n")

  # ---------------------------------------------------------------------------
  # Step 1: Select update type
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 1: SELECT UPDATE TYPE\n")
  cat(strrep("-", 70), "\n\n")

  cat("What type of update?\n")
  cat("  [1] Add new item to codebook\n")
  cat("  [2] Update existing IRT parameters\n")
  cat("  [3] Add new study calibration to existing item\n")
  cat("  [4] Batch update from CSV/data frame\n")
  cat("  [5] Cancel\n\n")

  update_type <- readline(prompt = "Enter choice (1-5): ")
  update_type <- as.integer(update_type)

  if (is.na(update_type) || update_type < 1 || update_type > 5) {
    cat("\n[ERROR] Invalid choice\n")
    return(invisible(NULL))
  }

  if (update_type == 5) {
    cat("\n[INFO] Update cancelled\n")
    return(invisible(NULL))
  }

  # ---------------------------------------------------------------------------
  # Step 2: Study selection
  # ---------------------------------------------------------------------------

  cat("\n", strrep("-", 70), "\n")
  cat("STEP 2: STUDY SELECTION\n")
  cat(strrep("-", 70), "\n\n")

  cat("Which study calibration?\n")
  cat("  Common options: NE25, NE22, NE20, NC26, CO27\n")
  cat("  Or enter custom study ID\n\n")

  study_id <- readline(prompt = "Enter study ID: ")
  study_id <- trimws(study_id)

  if (nchar(study_id) == 0) {
    cat("\n[ERROR] Study ID cannot be empty\n")
    return(invisible(NULL))
  }

  cat(sprintf("\n[OK] Study: %s\n", study_id))

  # ---------------------------------------------------------------------------
  # Step 3: Model type selection
  # ---------------------------------------------------------------------------

  cat("\n", strrep("-", 70), "\n")
  cat("STEP 3: MODEL TYPE\n")
  cat(strrep("-", 70), "\n\n")

  cat("Which IRT model type?\n")
  cat("  [1] Unidimensional (single latent trait)\n")
  cat("  [2] Bifactor (general + specific factors)\n")
  cat("  [3] Multidimensional (correlated factors)\n")
  cat("  [4] Custom\n\n")

  model_type <- readline(prompt = "Enter choice (1-4): ")
  model_type <- as.integer(model_type)

  model_type_names <- c("unidimensional", "bifactor", "multidimensional", "custom")

  if (is.na(model_type) || model_type < 1 || model_type > 4) {
    cat("\n[ERROR] Invalid choice\n")
    return(invisible(NULL))
  }

  model_type_str <- model_type_names[model_type]
  cat(sprintf("\n[OK] Model type: %s\n", model_type_str))

  # ---------------------------------------------------------------------------
  # Step 4: Factor structure
  # ---------------------------------------------------------------------------

  cat("\n", strrep("-", 70), "\n")
  cat("STEP 4: FACTOR STRUCTURE\n")
  cat(strrep("-", 70), "\n\n")

  if (model_type == 1) {
    # Unidimensional - single factor
    factors <- "kidsight"  # Default
    cat("Unidimensional model - single factor\n")
    factor_name <- readline(prompt = "Enter factor name (default: kidsight): ")
    if (nchar(trimws(factor_name)) > 0) {
      factors <- trimws(factor_name)
    }
    factors <- c(factors)

  } else if (model_type == 2) {
    # Bifactor - general + specific
    cat("Bifactor model - general factor + specific factors\n\n")
    cat("How many specific factors (beyond general)?\n")
    n_specific <- readline(prompt = "Number of specific factors: ")
    n_specific <- as.integer(n_specific)

    if (is.na(n_specific) || n_specific < 1) {
      cat("\n[ERROR] Must have at least 1 specific factor\n")
      return(invisible(NULL))
    }

    cat("\nEnter factor names (comma-separated):\n")
    cat("  Example: gen,eat,sle,soc,int,ext\n")
    cat(sprintf("  (1 general + %d specific = %d total)\n\n", n_specific, n_specific + 1))

    factor_string <- readline(prompt = "Factor names: ")
    factors <- unlist(strsplit(factor_string, ","))
    factors <- trimws(factors)

    if (length(factors) != (n_specific + 1)) {
      cat(sprintf("\n[ERROR] Expected %d factors, got %d\n", n_specific + 1, length(factors)))
      return(invisible(NULL))
    }

  } else {
    # Multidimensional or custom
    cat("Enter factor names (comma-separated):\n")
    cat("  Example: motor,cognitive,language,socioemotional\n\n")

    factor_string <- readline(prompt = "Factor names: ")
    factors <- unlist(strsplit(factor_string, ","))
    factors <- trimws(factors)
  }

  cat(sprintf("\n[OK] Factors: %s\n", paste(factors, collapse = ", ")))

  # ---------------------------------------------------------------------------
  # Step 5: Parameter entry
  # ---------------------------------------------------------------------------

  cat("\n", strrep("-", 70), "\n")
  cat("STEP 5: PARAMETER ENTRY\n")
  cat(strrep("-", 70), "\n\n")

  # Route to appropriate entry method
  if (update_type == 1 || update_type == 2 || update_type == 3) {
    # Interactive single-item or small batch
    updated_codebook <- interactive_single_item_params(
      codebook = codebook,
      study_id = study_id,
      model_type_str = model_type_str,
      factors = factors,
      update_type = update_type
    )
  } else if (update_type == 4) {
    # Batch from CSV
    updated_codebook <- batch_update_from_csv(
      codebook = codebook,
      study_id = study_id,
      model_type_str = model_type_str,
      factors = factors
    )
  }

  # ---------------------------------------------------------------------------
  # Step 6: Validation and save
  # ---------------------------------------------------------------------------

  if (!is.null(updated_codebook)) {
    cat("\n", strrep("-", 70), "\n")
    cat("STEP 6: VALIDATION AND SAVE\n")
    cat(strrep("-", 70), "\n\n")

    # Validate updated codebook
    cat("Validating updated codebook...\n")

    # Source validation functions if available
    if (file.exists("R/codebook/validate_irt_structure.R")) {
      source("R/codebook/validate_irt_structure.R")
      validation_result <- validate_irt_structure(updated_codebook)

      if (!validation_result$valid) {
        cat("\n[ERROR] Validation failed:\n")
        for (error in validation_result$errors) {
          cat(sprintf("  - %s\n", error))
        }
        cat("\nUpdate not saved.\n")
        return(invisible(NULL))
      }
    }

    cat("[OK] Validation passed\n\n")

    # Version tracking
    cat("Enter description of changes for changelog:\n")
    change_description <- readline(prompt = "> ")
    change_description <- trimws(change_description)

    if (nchar(change_description) == 0) {
      change_description <- sprintf("Updated IRT parameters for study %s", study_id)
    }

    # Determine change type based on update type
    change_type <- if (update_type == 1) {
      "new_item"
    } else if (update_type == 3) {
      "new_calibration"
    } else {
      "parameter_update"
    }

    # Increment version and add changelog
    updated_codebook <- increment_codebook_version(
      updated_codebook,
      change_description = change_description,
      change_type = change_type
    )

    # Backup existing codebook
    cat("Creating backup of existing codebook...\n")
    if (file.exists("R/codebook/update_irt_parameters.R")) {
      # backup_codebook function should be in this same file
      backup_codebook(codebook_path)
    }
    cat("[OK] Backup created\n\n")

    # Save updated codebook
    cat("Saving updated codebook...\n")
    jsonlite::write_json(
      updated_codebook,
      path = codebook_path,
      pretty = TRUE,
      auto_unbox = TRUE
    )
    cat(sprintf("[OK] Codebook saved: %s\n\n", codebook_path))

    cat(strrep("=", 70), "\n")
    cat("UPDATE COMPLETE\n")
    cat(strrep("=", 70), "\n\n")

    return(invisible(updated_codebook))
  }

  return(invisible(NULL))
}

#' Interactive Single Item Parameter Entry
#'
#' Guides user through entering parameters for single items or small batches
#'
#' @param codebook Codebook object
#' @param study_id Study identifier
#' @param model_type_str Model type string
#' @param factors Factor names vector
#' @param update_type Update type (1=new item, 2=update, 3=new calibration)
#' @return Updated codebook object
#' @keywords internal
interactive_single_item_params <- function(codebook, study_id, model_type_str, factors, update_type) {

  cat("Enter IRT parameters for items\n")
  cat("Type 'done' when finished\n\n")

  continue_entry <- TRUE
  n_items_updated <- 0

  while (continue_entry) {

    cat(strrep("-", 70), "\n")

    # Get item identifier
    item_id <- readline(prompt = "Item lexicon ID (or 'done'): ")
    item_id <- trimws(item_id)

    if (tolower(item_id) == "done") {
      break
    }

    # Find item in codebook
    item_index <- NULL
    for (i in seq_along(codebook$items)) {
      # Check if item matches any lexicon
      for (lex_name in names(codebook$items[[i]]$lexicons)) {
        if (codebook$items[[i]]$lexicons[[lex_name]] == item_id) {
          item_index <- i
          break
        }
      }
      if (!is.null(item_index)) break
    }

    if (is.null(item_index)) {
      cat(sprintf("\n[WARN] Item '%s' not found in codebook\n", item_id))

      if (update_type == 1) {
        cat("[INFO] Use update_type=1 (add new item) to add new items\n")
        cat("[INFO] This requires full item metadata, not just IRT parameters\n\n")
      }

      skip_choice <- readline(prompt = "Skip this item? (y/n): ")
      if (tolower(trimws(skip_choice)) == "y") {
        next
      } else {
        break
      }
    }

    cat(sprintf("\n[OK] Found item: %s\n", item_id))

    # Enter loadings
    cat(sprintf("\nEnter loadings (%d values for factors: %s)\n",
                length(factors), paste(factors, collapse = ", ")))
    cat("  Example: 0.85 (unidimensional) or 0.45,0.32 (bifactor)\n")

    loadings_str <- readline(prompt = "Loadings (comma-separated): ")
    loadings <- as.numeric(unlist(strsplit(loadings_str, ",")))

    if (length(loadings) != length(factors)) {
      cat(sprintf("\n[ERROR] Expected %d loadings, got %d\n", length(factors), length(loadings)))
      next
    }

    # Enter thresholds
    cat("\nEnter thresholds (ascending order)\n")
    cat("  Example: -1.45,0.67,2.12 (for 4-category item)\n")

    thresholds_str <- readline(prompt = "Thresholds (comma-separated): ")
    thresholds <- as.numeric(unlist(strsplit(thresholds_str, ",")))

    # Validate thresholds are ascending
    if (!all(diff(thresholds) > 0)) {
      cat("\n[ERROR] Thresholds must be in ascending order\n")
      next
    }

    # Create IRT parameters object
    irt_params <- list(
      factors = as.list(factors),
      loadings = as.list(loadings),
      thresholds = as.list(thresholds),
      constraints = list()  # Empty for now
    )

    # Update item
    if (is.null(codebook$items[[item_index]]$psychometric)) {
      codebook$items[[item_index]]$psychometric <- list()
    }
    if (is.null(codebook$items[[item_index]]$psychometric$irt_parameters)) {
      codebook$items[[item_index]]$psychometric$irt_parameters <- list()
    }

    codebook$items[[item_index]]$psychometric$irt_parameters[[study_id]] <- irt_params

    cat(sprintf("\n[OK] Updated IRT parameters for item %s (study: %s)\n", item_id, study_id))
    n_items_updated <- n_items_updated + 1

    # Continue?
    cont_choice <- readline(prompt = "\nAdd another item? (y/n): ")
    if (tolower(trimws(cont_choice)) != "y") {
      continue_entry <- FALSE
    }
  }

  cat(sprintf("\n[OK] Updated %d items\n\n", n_items_updated))

  return(codebook)
}

#' Batch Update from CSV/Data Frame
#'
#' Updates IRT parameters for multiple items from CSV file or data frame
#'
#' @param codebook Codebook object
#' @param study_id Study identifier
#' @param model_type_str Model type string
#' @param factors Factor names vector
#' @return Updated codebook object
#' @keywords internal
batch_update_from_csv <- function(codebook, study_id, model_type_str, factors) {

  cat("Batch update from CSV file\n\n")

  cat("CSV file format requirements:\n")
  cat("  - Column 1: item_id (lexicon identifier)\n")
  cat("  - Columns 2-(n+1): loading_factor1, loading_factor2, ...\n")
  cat("  - Remaining columns: threshold_1, threshold_2, ...\n\n")

  csv_path <- readline(prompt = "Enter path to CSV file: ")
  csv_path <- trimws(csv_path)

  if (!file.exists(csv_path)) {
    cat(sprintf("\n[ERROR] File not found: %s\n", csv_path))
    return(NULL)
  }

  # Read CSV
  params_df <- read.csv(csv_path, stringsAsFactors = FALSE)
  cat(sprintf("[OK] Read %d items from CSV\n\n", nrow(params_df)))

  n_items_updated <- 0

  for (i in 1:nrow(params_df)) {
    item_id <- params_df$item_id[i]

    # Find item in codebook
    item_index <- NULL
    for (j in seq_along(codebook$items)) {
      for (lex_name in names(codebook$items[[j]]$lexicons)) {
        if (codebook$items[[j]]$lexicons[[lex_name]] == item_id) {
          item_index <- j
          break
        }
      }
      if (!is.null(item_index)) break
    }

    if (is.null(item_index)) {
      cat(sprintf("[WARN] Item '%s' not found in codebook (skipping)\n", item_id))
      next
    }

    # Extract loadings (assumes columns named loading_*)
    loading_cols <- grep("^loading_", names(params_df), value = TRUE)
    loadings <- as.numeric(params_df[i, loading_cols])

    # Extract thresholds (assumes columns named threshold_*)
    threshold_cols <- grep("^threshold_", names(params_df), value = TRUE)
    thresholds <- as.numeric(params_df[i, threshold_cols])
    thresholds <- thresholds[!is.na(thresholds)]  # Remove NA for items with fewer thresholds

    # Create IRT parameters object
    irt_params <- list(
      factors = as.list(factors),
      loadings = as.list(loadings),
      thresholds = as.list(thresholds),
      constraints = list()
    )

    # Update item
    if (is.null(codebook$items[[item_index]]$psychometric)) {
      codebook$items[[item_index]]$psychometric <- list()
    }
    if (is.null(codebook$items[[item_index]]$psychometric$irt_parameters)) {
      codebook$items[[item_index]]$psychometric$irt_parameters <- list()
    }

    codebook$items[[item_index]]$psychometric$irt_parameters[[study_id]] <- irt_params

    n_items_updated <- n_items_updated + 1
  }

  cat(sprintf("\n[OK] Batch updated %d items from CSV\n\n", n_items_updated))

  return(codebook)
}

#' Backup Codebook Before Updates
#'
#' Creates timestamped backup of codebook in codebook/backups/ directory
#'
#' @param codebook_path Path to codebook.json file
#' @return Path to backup file (invisibly)
#' @export
backup_codebook <- function(codebook_path = "codebook/data/codebook.json") {

  # Create backups directory if it doesn't exist
  backup_dir <- "codebook/backups"
  dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)

  # Generate timestamped backup filename
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_filename <- sprintf("codebook_backup_%s.json", timestamp)
  backup_path <- file.path(backup_dir, backup_filename)

  # Copy file
  file.copy(codebook_path, backup_path, overwrite = FALSE)

  cat(sprintf("[OK] Backup created: %s\n", backup_path))

  invisible(backup_path)
}

# =============================================================================
# VERSION TRACKING FUNCTIONS
# =============================================================================

#' Increment Codebook Version
#'
#' Increments the codebook version number and adds changelog entry
#' Version format: MAJOR.MINOR (e.g., "2.1" -> "2.2")
#'
#' @param codebook Codebook object (from jsonlite::fromJSON)
#' @param change_description Description of changes made
#' @param change_type Type of change ("parameter_update", "new_calibration", "structure_change")
#' @return Updated codebook object
#' @export
increment_codebook_version <- function(codebook, change_description, change_type = "parameter_update") {

  # Get current version
  current_version <- codebook$metadata$version
  if (is.null(current_version)) {
    current_version <- "1.0"
  }

  # Parse version (MAJOR.MINOR)
  version_parts <- strsplit(current_version, "\\.")[[1]]
  major <- as.integer(version_parts[1])
  minor <- as.integer(version_parts[2])

  # Increment minor version for parameter updates
  # (Major version increments reserved for structure changes)
  if (change_type == "structure_change") {
    major <- major + 1
    minor <- 0
  } else {
    minor <- minor + 1
  }

  new_version <- sprintf("%d.%d", major, minor)

  # Update version
  codebook$metadata$version <- new_version
  codebook$metadata$last_updated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Add changelog entry
  codebook <- add_changelog_entry(
    codebook,
    version = new_version,
    change_type = change_type,
    description = change_description
  )

  cat(sprintf("\n[OK] Version incremented: %s -> %s\n", current_version, new_version))
  cat(sprintf("     Change type: %s\n", change_type))
  cat(sprintf("     Description: %s\n\n", change_description))

  return(codebook)
}

#' Get Codebook Version
#'
#' Retrieves current version number from codebook metadata
#'
#' @param codebook Codebook object
#' @return Version string (e.g., "2.1")
#' @export
get_codebook_version <- function(codebook) {

  version <- codebook$metadata$version

  if (is.null(version)) {
    return("1.0")  # Default version
  }

  return(version)
}

#' Add Changelog Entry
#'
#' Adds entry to codebook changelog with timestamp
#'
#' @param codebook Codebook object
#' @param version Version number
#' @param change_type Type of change
#' @param description Description of changes
#' @return Updated codebook object
#' @export
add_changelog_entry <- function(codebook, version, change_type, description) {

  # Initialize changelog if it doesn't exist
  if (is.null(codebook$metadata$changelog)) {
    codebook$metadata$changelog <- list()
  }

  # Create changelog entry
  entry <- list(
    version = version,
    date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    change_type = change_type,
    description = description
  )

  # Add to changelog (prepend so newest is first)
  codebook$metadata$changelog <- c(list(entry), codebook$metadata$changelog)

  return(codebook)
}

#' Display Codebook Version History
#'
#' Prints changelog to console
#'
#' @param codebook Codebook object or path to codebook JSON
#' @return NULL (prints to console)
#' @export
display_version_history <- function(codebook) {

  # Load codebook if path provided
  if (is.character(codebook)) {
    codebook <- jsonlite::fromJSON(codebook, simplifyVector = FALSE)
  }

  cat("\n", strrep("=", 70), "\n")
  cat("CODEBOOK VERSION HISTORY\n")
  cat(strrep("=", 70), "\n\n")

  cat(sprintf("Current version: %s\n", get_codebook_version(codebook)))
  cat(sprintf("Last updated: %s\n\n", codebook$metadata$last_updated))

  if (is.null(codebook$metadata$changelog) || length(codebook$metadata$changelog) == 0) {
    cat("No changelog entries found.\n\n")
    return(invisible(NULL))
  }

  cat(strrep("-", 70), "\n")
  cat("CHANGELOG\n")
  cat(strrep("-", 70), "\n\n")

  for (entry in codebook$metadata$changelog) {
    cat(sprintf("Version %s (%s)\n", entry$version, entry$date))
    cat(sprintf("  Type: %s\n", entry$change_type))
    cat(sprintf("  Changes: %s\n\n", entry$description))
  }

  cat(strrep("=", 70), "\n\n")

  invisible(NULL)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Interactive update workflow (includes automatic version tracking)
# interactive_parameter_update()
#
# # Or with custom path
# interactive_parameter_update("path/to/codebook.json")
#
# # View version history
# display_version_history("codebook/data/codebook.json")
#
# # Manual version increment (if needed outside interactive workflow)
# codebook <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)
# codebook <- increment_codebook_version(
#   codebook,
#   change_description = "Updated NE25 psychosocial parameters after recalibration",
#   change_type = "parameter_update"
# )
# jsonlite::write_json(codebook, "codebook/data/codebook.json", pretty = TRUE, auto_unbox = TRUE)
#
# # Batch update example CSV format:
# # item_id,loading_gen,loading_eat,threshold_1,threshold_2,threshold_3
# # ps001,0.45,0.32,-1.418,0.167,1.892
# # ps002,0.52,0.28,-0.982,0.445,1.654
