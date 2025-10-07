# Environment Configuration Utilities for R Scripts
# Reads configuration from .env file for cross-platform portability

#' Get Python Executable Path from Environment
#'
#' Reads PYTHON_EXECUTABLE from .env file or falls back to system defaults
#'
#' @return Character string with Python executable path
#' @export
get_python_path <- function() {
  # Try to read from .env file first
  env_file <- ".env"

  if (file.exists(env_file)) {
    # Read .env file
    env_lines <- readLines(env_file, warn = FALSE)

    # Filter out comments and empty lines
    env_lines <- env_lines[!grepl("^\\s*#", env_lines)]
    env_lines <- env_lines[nzchar(trimws(env_lines))]

    # Look for PYTHON_EXECUTABLE
    python_line <- env_lines[grepl("^PYTHON_EXECUTABLE=", env_lines)]

    if (length(python_line) > 0) {
      # Extract path (remove PYTHON_EXECUTABLE= prefix)
      python_path <- sub("^PYTHON_EXECUTABLE=", "", python_line[1])
      python_path <- trimws(python_path)

      # Remove quotes if present
      python_path <- gsub("^['\"]|['\"]$", "", python_path)

      # Verify the path exists
      if (file.exists(python_path)) {
        return(python_path)
      } else {
        warning("PYTHON_EXECUTABLE in .env points to non-existent path: ", python_path)
        warning("Falling back to system default")
      }
    }
  }

  # Fallback: Try system environment variable
  env_python <- Sys.getenv("PYTHON_EXECUTABLE", unset = "")
  if (nzchar(env_python) && file.exists(env_python)) {
    return(env_python)
  }

  # Fallback: Try common system defaults
  if (.Platform$OS.type == "windows") {
    # Common Windows Python locations
    possible_paths <- c(
      "C:/Program Files/Python313/python.exe",
      "C:/Program Files/Python312/python.exe",
      "C:/Python313/python.exe",
      "C:/Python312/python.exe"
    )

    # Check user AppData
    username <- Sys.getenv("USERNAME")
    if (nzchar(username)) {
      user_paths <- c(
        paste0("C:/Users/", username, "/AppData/Local/Programs/Python/Python313/python.exe"),
        paste0("C:/Users/", username, "/AppData/Local/Programs/Python/Python312/python.exe")
      )
      possible_paths <- c(user_paths, possible_paths)
    }

    for (path in possible_paths) {
      if (file.exists(path)) {
        return(path)
      }
    }

    # Last resort: try 'python' from PATH
    return("python.exe")

  } else {
    # Unix-like systems (Mac/Linux)
    # Try python3 first, then python
    python3_path <- Sys.which("python3")
    if (nzchar(python3_path)) {
      return(as.character(python3_path))
    }

    python_path <- Sys.which("python")
    if (nzchar(python_path)) {
      return(as.character(python_path))
    }

    # Last resort
    return("python3")
  }
}

#' Get R Executable Path from Environment
#'
#' Reads R_EXECUTABLE from .env file or uses current R installation
#'
#' @return Character string with R executable path
#' @export
get_r_path <- function() {
  # Try to read from .env file first
  env_file <- ".env"

  if (file.exists(env_file)) {
    env_lines <- readLines(env_file, warn = FALSE)
    env_lines <- env_lines[!grepl("^\\s*#", env_lines)]
    env_lines <- env_lines[nzchar(trimws(env_lines))]

    r_line <- env_lines[grepl("^R_EXECUTABLE=", env_lines)]

    if (length(r_line) > 0) {
      r_path <- sub("^R_EXECUTABLE=", "", r_line[1])
      r_path <- trimws(r_path)
      r_path <- gsub("^['\"]|['\"]$", "", r_path)

      if (file.exists(r_path)) {
        return(r_path)
      }
    }
  }

  # Fallback: Use current R installation
  r_home <- R.home("bin")

  if (.Platform$OS.type == "windows") {
    return(file.path(r_home, "R.exe"))
  } else {
    return(file.path(r_home, "R"))
  }
}

#' Test Python Path Configuration
#'
#' Verifies that Python executable can be found and is working
#'
#' @return TRUE if Python is accessible, FALSE otherwise
#' @export
test_python_config <- function() {
  python_path <- get_python_path()

  cat("Testing Python configuration...\n")
  cat("  Path:", python_path, "\n")

  # Test if file exists
  if (!file.exists(python_path) && python_path != "python.exe" && python_path != "python3") {
    cat("  [ERROR] Python executable not found at:", python_path, "\n")
    cat("  Please update PYTHON_EXECUTABLE in .env file\n")
    return(FALSE)
  }

  # Test if Python runs
  tryCatch({
    result <- system2(python_path, args = "--version", stdout = TRUE, stderr = TRUE)
    cat("  Version:", result[1], "\n")
    cat("  [OK] Python is accessible\n")
    return(TRUE)
  }, error = function(e) {
    cat("  [ERROR] Failed to run Python:", e$message, "\n")
    return(FALSE)
  })
}
