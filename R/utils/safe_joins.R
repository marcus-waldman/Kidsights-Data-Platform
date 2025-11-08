#' Safe Left Join with Collision Detection
#'
#' A wrapper around dplyr::left_join that prevents column name collisions
#' and validates join cardinality. This function detects overlapping column
#' names (excluding join keys) and either auto-fixes them or throws an error.
#'
#' @param left Left data frame (primary table)
#' @param right Right data frame (table to join)
#' @param by_vars Character vector of join key column names
#' @param allow_collision Logical. If TRUE, allows .x/.y suffixes (default: FALSE)
#' @param auto_fix Logical. If TRUE, automatically removes colliding columns from
#'   right table with a warning (default: TRUE)
#'
#' @return A data frame with the same number of rows as left
#'
#' @details
#' This function prevents common join errors:
#' 1. Column collisions that create .x/.y suffixed columns
#' 2. Many-to-many joins that duplicate rows unexpectedly
#'
#' When auto_fix=TRUE (default), colliding columns are removed from the right
#' table before joining, with a warning message listing the removed columns.
#'
#' When auto_fix=FALSE and allow_collision=FALSE, throws a detailed error
#' with solutions for fixing the collision manually.
#'
#' @examples
#' \dontrun{
#' # Standard usage (auto-fixes collisions)
#' data %>%
#'   safe_left_join(eligibility_data, by_vars = c("pid", "record_id"))
#'
#' # Strict mode (throws error on collision)
#' data %>%
#'   safe_left_join(eligibility_data,
#'                  by_vars = c("pid", "record_id"),
#'                  auto_fix = FALSE)
#'
#' # Allow collision explicitly (not recommended)
#' data %>%
#'   safe_left_join(eligibility_data,
#'                  by_vars = c("pid", "record_id"),
#'                  allow_collision = TRUE)
#' }
#'
#' @export
safe_left_join <- function(left, right, by_vars, allow_collision = FALSE, auto_fix = TRUE) {
  # Check for column collisions before joining
  left_cols <- names(left)
  right_cols <- names(right)

  # Find overlapping columns (excluding join keys)
  overlapping <- setdiff(intersect(left_cols, right_cols), by_vars)

  if(length(overlapping) > 0) {
    if(auto_fix) {
      # Remove colliding columns from right table
      right <- right %>% dplyr::select(-dplyr::all_of(overlapping))
      warning(paste("safe_left_join: Auto-fixed column collision by removing from right table:",
                   paste(overlapping, collapse=", ")))
    } else if(!allow_collision) {
      # Throw error with detailed information
      stop(paste("COLUMN COLLISION DETECTED in safe_left_join!",
                paste("Colliding columns:", paste(overlapping, collapse=", ")),
                "This creates .x/.y suffixed columns and causes data loss/corruption.",
                "",
                "SOLUTIONS:",
                paste("1. Remove columns from right table: right %>% dplyr::select(-dplyr::all_of(c('", paste(overlapping, collapse="', '"), "')))", sep=""),
                "2. Use auto_fix=TRUE: safe_left_join(..., auto_fix=TRUE)",
                "3. Use allow_collision=TRUE: safe_left_join(..., allow_collision=TRUE) [NOT RECOMMENDED]",
                "",
                "Join details:",
                paste("- Left table columns:", paste(head(left_cols, 10), collapse=", "), if(length(left_cols)>10) "..." else ""),
                paste("- Right table columns:", paste(head(right_cols, 10), collapse=", "), if(length(right_cols)>10) "..." else ""),
                paste("- Join key(s):", paste(by_vars, collapse=", ")),
                sep="\n"))
    } else {
      # Allow collision but warn
      warning(paste("safe_left_join: Column collision allowed for:", paste(overlapping, collapse=", "),
                   "- This will create .x/.y suffixed columns"))
    }
  }

  # Perform the join
  nr <- nrow(left)
  ret <- dplyr::left_join(x = left, y = right, by = by_vars)

  # Row count validation
  if(nrow(ret) != nr) {
    stop(paste0("safe_left_join: Join resulted in different number of rows. Before: ", nr, ", After: ", nrow(ret),
                "\nThis indicates a many-to-many join or duplicate keys in the right table."))
  }

  return(ret)
}
