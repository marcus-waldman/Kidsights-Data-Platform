# ==============================================================================
# MN26 Wide-to-Long Pivot
# ==============================================================================
# Converts MN26 REDCap data from wide format (1 row per household, up to 2
# children) to long format (1 row per child). Runs immediately after extraction,
# before any transforms.
#
# Unique identifier after pivot: pid + record_id + child_num
#
# Logic:
#   - Child 1 rows: ALL records, child_num = 1
#   - Child 2 rows: Only where dob_c2_n is non-empty, child_num = 2
#   - Household-level vars (parent demographics, SES) duplicated across both rows
#   - Child 2 columns renamed to match child 1 equivalents (strip _c2 segment)
# ==============================================================================

library(dplyr)

#' Pivot MN26 data from wide (household) to long (child) format
#'
#' @param wide_data Data frame with 1 row per household from REDCap extraction
#' @param verbose Logical, print progress messages (default TRUE)
#' @return Data frame with 1 row per child, child_num column added
pivot_mn26_wide_to_long <- function(wide_data, verbose = TRUE) {

  n_households <- nrow(wide_data)
  all_cols <- names(wide_data)

  if (verbose) message("MN26 Pivot: ", n_households, " household records")

  # --------------------------------------------------------------------------
  # Step 1: Identify child 2 columns by naming patterns
  # --------------------------------------------------------------------------

  # Pattern 1: Standard _c2 suffix (e.g., cqr009_c2, nom001_c2)
  # Pattern 2: _c2b variant (e.g., cqr010_c2b___100)
  # Pattern 3: _c2_n suffix (e.g., age_in_days_c2_n, dob_c2_n)
  # Pattern 4: desc_c2_ prefix (e.g., desc_c2_0_89)
  # Pattern 5: _2_complete suffix for instruments (e.g., module_6_0_89_2_complete)
  # Pattern 6: child_information_2 (e.g., child_information_2_954c_complete)

  # Detect all columns that are child-2-specific
  c2_cols <- all_cols[
    grepl("_c2$|_c2_|_c2b", all_cols) |
    grepl("_2_complete$", all_cols) |
    grepl("^desc_c2_", all_cols) |
    grepl("child_information_2", all_cols)
  ]

  if (verbose) message("  Child 2 columns detected: ", length(c2_cols))

  # --------------------------------------------------------------------------
  # Step 2: Build child2 → child1 column name mapping
  # --------------------------------------------------------------------------

  c2_to_c1 <- sapply(c2_cols, function(col) {
    # _c2b variant: cqr010_c2b___100 → cqr010b___100
    if (grepl("_c2b", col)) {
      return(sub("_c2b", "b", col))
    }
    # _c2_n suffix: age_in_days_c2_n → age_in_days_n
    if (grepl("_c2_n$", col)) {
      return(sub("_c2_n$", "_n", col))
    }
    # desc_c2_ prefix: desc_c2_0_89 → desc_c1_0_89
    if (grepl("^desc_c2_", col)) {
      return(sub("^desc_c2_", "desc_c1_", col))
    }
    # _2_complete suffix: module_6_0_89_2_complete → module_6_0_89_complete
    if (grepl("_2_complete$", col)) {
      return(sub("_2_complete$", "_complete", col))
    }
    # child_information_2: child_information_2_954c_complete → module_3_child_information_complete
    # This one doesn't have a clean 1:1 mapping — keep as-is for child 2 only
    if (grepl("child_information_2", col)) {
      return(NA_character_)
    }
    # Standard _c2 suffix: cqr009_c2 → cqr009
    if (grepl("_c2$", col)) {
      return(sub("_c2$", "", col))
    }
    # Fallback: no mapping found
    return(NA_character_)
  }, USE.NAMES = TRUE)

  # Split into mappable and child-2-only columns
  mappable <- c2_to_c1[!is.na(c2_to_c1)]
  c2_only  <- names(c2_to_c1[is.na(c2_to_c1)])

  if (verbose) {
    message("  Mappable to child 1: ", length(mappable))
    message("  Child-2-only columns: ", length(c2_only))
  }

  # Verify that child 1 equivalents exist
  missing_c1 <- mappable[!mappable %in% all_cols]
  if (length(missing_c1) > 0 && verbose) {
    message("  [WARN] ", length(missing_c1),
            " child 2 columns map to non-existent child 1 columns: ",
            paste(head(names(missing_c1), 5), collapse = ", "),
            if (length(missing_c1) > 5) "..." else "")
  }

  # --------------------------------------------------------------------------
  # Step 3: Define column sets
  # --------------------------------------------------------------------------

  # Household-level columns: everything that is NOT child-2-specific
  household_cols <- setdiff(all_cols, c2_cols)

  # --------------------------------------------------------------------------
  # Step 4: Create child 1 rows (ALL records)
  # --------------------------------------------------------------------------

  child1 <- wide_data %>%
    dplyr::select(dplyr::all_of(household_cols)) %>%
    dplyr::mutate(child_num = 1L)

  if (verbose) message("  Child 1 rows: ", nrow(child1))

  # --------------------------------------------------------------------------
  # Step 5: Create child 2 rows (only where child 2 exists)
  # --------------------------------------------------------------------------

  # Determine which records have a child 2
  # dob_c2_n may be Date, POSIXct, character, or numeric — handle all types
  has_child2 <- if ("dob_c2_n" %in% all_cols) {
    vals <- wide_data$dob_c2_n
    !is.na(vals) & nchar(as.character(vals)) > 0 & as.character(vals) != ""
  } else {
    # Fallback: check if any _c2 data field (not completion flags) is non-empty
    c2_data_cols <- intersect(c2_cols, all_cols)
    c2_data_cols <- c2_data_cols[!grepl("_complete$|_timestamp$", c2_data_cols)]
    if (length(c2_data_cols) > 0) {
      rowSums(!is.na(wide_data[, c2_data_cols, drop = FALSE])) > 0
    } else {
      rep(FALSE, n_households)
    }
  }
  # Ensure no NAs in the logical vector
  has_child2[is.na(has_child2)] <- FALSE

  n_child2 <- sum(has_child2)
  if (verbose) message("  Households with child 2: ", n_child2, " of ", n_households)

  if (n_child2 > 0) {
    wide_c2 <- wide_data[has_child2, , drop = FALSE]

    # Start with household-level columns (duplicated)
    # Remove child-1-specific columns that will be replaced by child 2 values
    c1_cols_to_replace <- intersect(unname(mappable), household_cols)
    child2_base <- wide_c2 %>%
      dplyr::select(dplyr::all_of(setdiff(household_cols, c1_cols_to_replace)))

    # Add renamed child 2 columns (mapped to child 1 names)
    for (c2_name in names(mappable)) {
      c1_name <- mappable[[c2_name]]
      if (c2_name %in% names(wide_c2)) {
        child2_base[[c1_name]] <- wide_c2[[c2_name]]
      }
    }

    # Add child-2-only columns (no child 1 equivalent)
    for (col in c2_only) {
      if (col %in% names(wide_c2)) {
        child2_base[[col]] <- wide_c2[[col]]
      }
    }

    child2_base$child_num <- 2L

    # Ensure column alignment with child 1
    # Add any missing columns as NA
    missing_in_c2 <- setdiff(names(child1), names(child2_base))
    for (col in missing_in_c2) {
      child2_base[[col]] <- NA
    }
    missing_in_c1 <- setdiff(names(child2_base), names(child1))
    for (col in missing_in_c1) {
      child1[[col]] <- NA
    }
  } else {
    child2_base <- NULL
  }

  # --------------------------------------------------------------------------
  # Step 6: Bind rows and create composite key
  # --------------------------------------------------------------------------

  if (!is.null(child2_base)) {
    long_data <- dplyr::bind_rows(child1, child2_base)
  } else {
    long_data <- child1
  }

  # Sort by household then child number
  long_data <- long_data %>%
    dplyr::arrange(pid, record_id, child_num)

  if (verbose) {
    message("  Final long format: ", nrow(long_data), " rows (",
            nrow(child1), " child 1 + ", n_child2, " child 2)")
    message("[OK] Pivot complete")
  }

  return(long_data)
}
