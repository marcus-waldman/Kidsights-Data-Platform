#' Safe Left Join with Collision Detection
#'
#' A wrapper around dplyr::left_join that prevents column name collisions
#' and validates join cardinality.
#'
#' @param left Left data frame (primary table)
#' @param right Right data frame (table to join)
#' @param by_vars Character vector of join key column names
#' @param allow_collision Logical. If TRUE, allows .x/.y suffixes (default: FALSE)
#' @param auto_fix Logical. If TRUE, automatically removes colliding columns from
#'   right table with a warning (default: TRUE)
#' @return A data frame with the same number of rows as left
safe_left_join <- function(left, right, by_vars, allow_collision = FALSE, auto_fix = TRUE) {
  left_cols <- names(left)
  right_cols <- names(right)
  overlapping <- setdiff(intersect(left_cols, right_cols), by_vars)

  if(length(overlapping) > 0) {
    if(auto_fix) {
      right <- right %>% dplyr::select(-dplyr::all_of(overlapping))
      warning(paste("safe_left_join: Auto-fixed column collision by removing from right table:",
                   paste(overlapping, collapse=", ")))
    } else if(!allow_collision) {
      stop(paste("COLUMN COLLISION DETECTED:", paste(overlapping, collapse=", ")))
    }
  }

  nr <- nrow(left)
  ret <- dplyr::left_join(x = left, y = right, by = by_vars)

  if(nrow(ret) != nr) {
    stop(paste0("safe_left_join: Row count changed. Before: ", nr, ", After: ", nrow(ret)))
  }

  return(ret)
}
