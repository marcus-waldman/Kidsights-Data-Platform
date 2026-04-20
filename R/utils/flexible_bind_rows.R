#' Flexible bind_rows that resolves type conflicts
#'
#' Combines data frames with differing column types by promoting each column
#' to the highest type in the hierarchy: logical < integer < numeric < character.
#' This is needed when combining REDCap extracts from multiple projects where
#' timestamp fields may be character in some projects (empty strings) and
#' datetime in others (parsed values), or where checkbox fields may be coded
#' as logical/integer/numeric inconsistently.
#'
#' @param ... Data frames to bind or a list of data frames
#' @param .id Optional column name to identify source data frame
#' @return Combined data frame with resolved type conflicts
#' @export
flexible_bind_rows <- function(..., .id = NULL) {
  args <- list(...)

  # Handle list-of-data-frames input
  if (length(args) == 1 && is.list(args[[1]]) && !is.data.frame(args[[1]])) {
    dfs <- args[[1]]
  } else {
    dfs <- args
  }

  if (length(dfs) == 0) {
    return(data.frame())
  }

  # Type hierarchy: higher wins when columns conflict
  type_hierarchy <- function(type) {
    switch(type,
      "logical" = 1,
      "integer" = 2,
      "numeric" = 3,
      "double" = 3,
      "character" = 4,
      # POSIXct/POSIXt/Date get forced to character to handle REDCap
      # timestamps that are strings in some projects
      "POSIXct" = 4,
      "POSIXt" = 4,
      "Date" = 4,
      4
    )
  }

  convert_to_type <- function(x, target_type) {
    switch(target_type,
      "logical" = as.logical(x),
      "integer" = as.integer(x),
      "numeric" = as.numeric(x),
      "double" = as.numeric(x),
      "character" = as.character(x),
      as.character(x)
    )
  }

  if (!is.null(.id)) {
    for (i in seq_along(dfs)) {
      dfs[[i]][[.id]] <- i
    }
  }

  # Get all unique column names across all data frames
  all_cols <- unique(unlist(lapply(dfs, names)))

  for (col in all_cols) {
    col_types <- character()
    df_indices_with_col <- integer()

    for (i in seq_along(dfs)) {
      if (col %in% names(dfs[[i]])) {
        col_types <- c(col_types, class(dfs[[i]][[col]])[1])
        df_indices_with_col <- c(df_indices_with_col, i)
      }
    }

    hierarchy_levels <- sapply(col_types, type_hierarchy)
    max_hierarchy <- max(hierarchy_levels)

    target_type <- names(which(sapply(
      c("logical", "integer", "numeric", "character"),
      function(t) type_hierarchy(t) == max_hierarchy
    ))[1])

    if (length(unique(col_types)) > 1) {
      for (i in df_indices_with_col) {
        dfs[[i]][[col]] <- convert_to_type(dfs[[i]][[col]], target_type)
      }
    }
  }

  return(dplyr::bind_rows(dfs))
}
