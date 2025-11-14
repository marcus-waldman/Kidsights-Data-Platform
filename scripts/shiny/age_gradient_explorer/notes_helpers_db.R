# ==============================================================================
# Item Review Notes Management Functions (DuckDB Backend)
# ==============================================================================
#
# Functions for reading/writing item review notes with version history
# stored in DuckDB database instead of JSON files
#
# Database Schema:
# CREATE TABLE item_review_notes (
#   id INTEGER PRIMARY KEY,
#   item_id VARCHAR,
#   note TEXT,
#   timestamp TIMESTAMP,
#   reviewer VARCHAR,
#   is_current BOOLEAN DEFAULT FALSE
# );
#
# ==============================================================================

library(duckdb)
library(dplyr)

# ==============================================================================
# Get Database Connection
# ==============================================================================

get_notes_db_connection <- function() {
  # Connect to main kidsights database
  db_path <- file.path("..", "..", "..", "data", "duckdb", "kidsights_local.duckdb")

  if (!file.exists(db_path)) {
    stop("Database not found at: ", db_path)
  }

  conn <- dbConnect(duckdb(), dbdir = db_path, read_only = FALSE)
  return(conn)
}

# ==============================================================================
# Initialize Notes Table
# ==============================================================================

init_notes_db <- function() {
  # Create notes table if it doesn't exist
  conn <- get_notes_db_connection()

  tryCatch({
    # Check if table exists
    table_exists <- dbExistsTable(conn, "item_review_notes")

    if (!table_exists) {
      # Create sequence for auto-incrementing IDs
      dbExecute(conn, "
        CREATE SEQUENCE item_review_notes_seq START 1
      ")

      # Create table
      dbExecute(conn, "
        CREATE TABLE item_review_notes (
          id INTEGER PRIMARY KEY DEFAULT nextval('item_review_notes_seq'),
          item_id VARCHAR,
          note TEXT,
          timestamp TIMESTAMP,
          reviewer VARCHAR,
          is_current BOOLEAN DEFAULT FALSE
        )
      ")

      # Create index for fast lookups
      dbExecute(conn, "
        CREATE INDEX idx_item_notes ON item_review_notes(item_id, is_current)
      ")

      cat(sprintf("Created item_review_notes table in database\n"))
    } else {
      cat(sprintf("item_review_notes table already exists\n"))
    }

    dbDisconnect(conn, shutdown = TRUE)
    return(TRUE)

  }, error = function(e) {
    dbDisconnect(conn, shutdown = TRUE)
    cat(sprintf("[ERROR] Failed to initialize notes table: %s\n", e$message))
    return(FALSE)
  })
}

# ==============================================================================
# Get Item Note
# ==============================================================================

get_item_note <- function(item_id, notes_path = NULL) {
  # Get current note and history for a specific item
  # notes_path parameter kept for API compatibility but not used

  conn <- get_notes_db_connection()

  tryCatch({
    # Get current note
    current_query <- "
      SELECT note, timestamp, reviewer
      FROM item_review_notes
      WHERE item_id = ? AND is_current = TRUE
      ORDER BY timestamp DESC
      LIMIT 1
    "

    current_note <- dbGetQuery(conn, current_query, params = list(item_id))

    # Get history (all notes for this item, ordered by timestamp)
    history_query <- "
      SELECT note, timestamp, reviewer
      FROM item_review_notes
      WHERE item_id = ?
      ORDER BY timestamp DESC
    "

    history <- dbGetQuery(conn, history_query, params = list(item_id))

    dbDisconnect(conn, shutdown = TRUE)

    # Convert to list format matching JSON structure
    if (nrow(current_note) == 0) {
      return(list(
        current = list(
          timestamp = "",
          reviewer = "",
          note = ""
        ),
        history = list()
      ))
    }

    current_list <- list(
      timestamp = as.character(current_note$timestamp[1]),
      reviewer = current_note$reviewer[1],
      note = current_note$note[1]
    )

    # Convert history dataframe to list of lists
    history_list <- lapply(1:nrow(history), function(i) {
      list(
        timestamp = as.character(history$timestamp[i]),
        reviewer = history$reviewer[i],
        note = history$note[i]
      )
    })

    return(list(
      current = current_list,
      history = history_list
    ))

  }, error = function(e) {
    dbDisconnect(conn, shutdown = TRUE)
    cat(sprintf("[ERROR] Failed to get item note: %s\n", e$message))
    return(list(
      current = list(timestamp = "", reviewer = "", note = ""),
      history = list()
    ))
  })
}

# ==============================================================================
# Save Item Note
# ==============================================================================

save_item_note <- function(item_id, note_text, reviewer = "User",
                          notes_path = NULL) {
  # Save a new note for an item (creates new version in history)
  # notes_path parameter kept for API compatibility but not used

  if (nchar(trimws(note_text)) == 0) {
    # Don't save empty notes
    return(FALSE)
  }

  conn <- get_notes_db_connection()

  tryCatch({
    # Start transaction
    dbBegin(conn)

    # Get current timestamp
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    # Mark all existing notes for this item as not current
    dbExecute(conn, "
      UPDATE item_review_notes
      SET is_current = FALSE
      WHERE item_id = ?
    ", params = list(item_id))

    # Insert new note
    dbExecute(conn, "
      INSERT INTO item_review_notes (item_id, note, timestamp, reviewer, is_current)
      VALUES (?, ?, ?, ?, TRUE)
    ", params = list(item_id, note_text, timestamp, reviewer))

    # Commit transaction
    dbCommit(conn)
    dbDisconnect(conn, shutdown = TRUE)

    return(TRUE)

  }, error = function(e) {
    # Rollback on error
    tryCatch(dbRollback(conn), error = function(e2) {})
    dbDisconnect(conn, shutdown = TRUE)
    cat(sprintf("[ERROR] Failed to save note: %s\n", e$message))
    return(FALSE)
  })
}

# ==============================================================================
# Format Note for Display
# ==============================================================================

format_note_display <- function(note_entry) {
  # Format a single note entry for display in UI
  if (is.null(note_entry) || is.null(note_entry$timestamp)) {
    return("")
  }

  timestamp <- note_entry$timestamp
  reviewer <- if (!is.null(note_entry$reviewer)) note_entry$reviewer else "Unknown"
  note <- if (!is.null(note_entry$note)) note_entry$note else ""

  # Format: "2025-11-14 10:23 - Marcus"
  sprintf("%s - %s", substr(timestamp, 1, 16), reviewer)
}

# ==============================================================================
# Get History Summary
# ==============================================================================

get_history_summary <- function(item_id, notes_path = NULL, max_entries = 5) {
  # Get formatted list of previous note versions
  # notes_path parameter kept for API compatibility but not used

  item_notes <- get_item_note(item_id)

  if (length(item_notes$history) == 0) {
    return(data.frame(
      index = integer(0),
      display = character(0),
      note_text = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Get most recent entries (reverse chronological)
  history <- item_notes$history
  n_entries <- min(max_entries, length(history))

  if (n_entries == 0) {
    return(data.frame(
      index = integer(0),
      display = character(0),
      note_text = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Get last n_entries (already in reverse chronological order from query)
  recent_indices <- 1:n_entries

  history_df <- data.frame(
    index = recent_indices,
    display = sapply(recent_indices, function(i) {
      format_note_display(history[[i]])
    }),
    note_text = sapply(recent_indices, function(i) {
      if (!is.null(history[[i]]$note)) history[[i]]$note else ""
    }),
    stringsAsFactors = FALSE
  )

  return(history_df)
}

# ==============================================================================
# Connection Management Helpers
# ==============================================================================

test_db_connection <- function() {
  # Test if database is accessible and return status message
  tryCatch({
    conn <- get_notes_db_connection()

    # Test query
    result <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM item_review_notes")
    n_notes <- result$count[1]

    dbDisconnect(conn, shutdown = TRUE)

    return(list(
      success = TRUE,
      message = sprintf("Connected - %d notes in database", n_notes)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = sprintf("Connection failed: %s", e$message)
    ))
  })
}

close_all_db_connections <- function() {
  # Force close all DuckDB connections
  tryCatch({
    # Get database path
    db_path <- file.path("..", "..", "..", "data", "duckdb", "kidsights_local.duckdb")

    if (!file.exists(db_path)) {
      return(list(
        success = FALSE,
        message = "Database file not found"
      ))
    }

    # Connect and immediately shutdown to force cleanup
    conn <- dbConnect(duckdb(), dbdir = db_path, read_only = FALSE)
    dbDisconnect(conn, shutdown = TRUE)

    # Force garbage collection to release any lingering connections
    gc()

    return(list(
      success = TRUE,
      message = "All connections closed successfully"
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = sprintf("Error closing connections: %s", e$message)
    ))
  })
}

# ==============================================================================
# Migration Helper: Import from JSON
# ==============================================================================

import_notes_from_json <- function(json_path = "item_review_notes.json") {
  # One-time import of existing JSON notes into database

  if (!file.exists(json_path)) {
    cat("No JSON notes file found - nothing to import\n")
    return(invisible(NULL))
  }

  # Load JSON notes
  notes_json <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

  if (length(notes_json) == 0) {
    cat("JSON notes file is empty - nothing to import\n")
    return(invisible(NULL))
  }

  conn <- get_notes_db_connection()

  tryCatch({
    dbBegin(conn)

    n_imported <- 0

    for (item_id in names(notes_json)) {
      item_notes <- notes_json[[item_id]]

      # Import all history entries
      if (!is.null(item_notes$history) && length(item_notes$history) > 0) {
        for (i in seq_along(item_notes$history)) {
          hist_entry <- item_notes$history[[i]]

          # Mark only the last entry as current
          is_current <- (i == length(item_notes$history))

          dbExecute(conn, "
            INSERT INTO item_review_notes (item_id, note, timestamp, reviewer, is_current)
            VALUES (?, ?, ?, ?, ?)
          ", params = list(
            item_id,
            hist_entry$note,
            hist_entry$timestamp,
            hist_entry$reviewer,
            is_current
          ))

          n_imported <- n_imported + 1
        }
      }
    }

    dbCommit(conn)
    dbDisconnect(conn, shutdown = TRUE)

    cat(sprintf("Successfully imported %d notes from JSON\n", n_imported))
    return(invisible(n_imported))

  }, error = function(e) {
    tryCatch(dbRollback(conn), error = function(e2) {})
    dbDisconnect(conn, shutdown = TRUE)
    cat(sprintf("[ERROR] Failed to import notes: %s\n", e$message))
    return(invisible(NULL))
  })
}
