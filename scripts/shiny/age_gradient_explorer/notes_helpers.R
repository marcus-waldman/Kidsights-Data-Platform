# ==============================================================================
# Item Review Notes Management Functions
# ==============================================================================
#
# Functions for reading/writing item review notes with version history
#
# JSON Structure:
# {
#   "AA4": {
#     "current": {
#       "timestamp": "2025-11-14 10:23:15",
#       "reviewer": "Marcus",
#       "note": "Excellent age gradient, no issues"
#     },
#     "history": [
#       {"timestamp": "...", "reviewer": "...", "note": "..."},
#       ...
#     ]
#   }
# }
# ==============================================================================

library(jsonlite)

# ==============================================================================
# Initialize Notes File
# ==============================================================================

init_notes_file <- function(notes_path = "item_review_notes.json") {
  # Create empty notes file if it doesn't exist
  if (!file.exists(notes_path)) {
    empty_notes <- list()
    writeLines(toJSON(empty_notes, pretty = TRUE, auto_unbox = TRUE), notes_path)
    cat(sprintf("Created new notes file: %s\n", notes_path))
  }
}

# ==============================================================================
# Load All Notes
# ==============================================================================

load_notes <- function(notes_path = "item_review_notes.json") {
  # Load notes from JSON file
  if (!file.exists(notes_path)) {
    init_notes_file(notes_path)
    return(list())
  }

  tryCatch({
    notes <- fromJSON(notes_path, simplifyVector = FALSE)
    return(notes)
  }, error = function(e) {
    cat(sprintf("[WARN] Failed to load notes: %s\n", e$message))
    return(list())
  })
}

# ==============================================================================
# Get Item Note
# ==============================================================================

get_item_note <- function(item_id, notes_path = "item_review_notes.json") {
  # Get current note and history for a specific item
  notes <- load_notes(notes_path)

  if (is.null(notes[[item_id]])) {
    return(list(
      current = list(
        timestamp = "",
        reviewer = "",
        note = ""
      ),
      history = list()
    ))
  }

  return(notes[[item_id]])
}

# ==============================================================================
# Save Item Note
# ==============================================================================

save_item_note <- function(item_id, note_text, reviewer = "User",
                          notes_path = "item_review_notes.json") {
  # Save a new note for an item (creates new version in history)

  if (nchar(trimws(note_text)) == 0) {
    # Don't save empty notes
    return(FALSE)
  }

  # Load existing notes
  notes <- load_notes(notes_path)

  # Get current timestamp
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Create new note entry
  new_note <- list(
    timestamp = timestamp,
    reviewer = reviewer,
    note = note_text
  )

  # Initialize item notes if doesn't exist
  if (is.null(notes[[item_id]])) {
    notes[[item_id]] <- list(
      current = new_note,
      history = list(new_note)
    )
  } else {
    # Move current note to history
    if (!is.null(notes[[item_id]]$current) &&
        nchar(notes[[item_id]]$current$note) > 0) {
      notes[[item_id]]$history <- c(
        notes[[item_id]]$history,
        list(notes[[item_id]]$current)
      )
    }

    # Update current note
    notes[[item_id]]$current <- new_note

    # Add new note to history
    notes[[item_id]]$history <- c(
      notes[[item_id]]$history,
      list(new_note)
    )
  }

  # Save to file
  tryCatch({
    writeLines(toJSON(notes, pretty = TRUE, auto_unbox = TRUE), notes_path)
    return(TRUE)
  }, error = function(e) {
    cat(sprintf("[ERROR] Failed to save notes: %s\n", e$message))
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

get_history_summary <- function(item_id, notes_path = "item_review_notes.json", max_entries = 5) {
  # Get formatted list of previous note versions
  item_notes <- get_item_note(item_id, notes_path)

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

  # Get last n_entries (most recent first)
  recent_indices <- seq(length(history), max(1, length(history) - n_entries + 1), by = -1)

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
