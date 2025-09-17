#' Generate Codebook Dashboard
#'
#' Pipeline script to generate the Quarto dashboard from the JSON codebook

library(quarto)
library(fs)
library(here)

#' Generate the complete codebook dashboard
#'
#' @param codebook_path Path to JSON codebook file
#' @param dashboard_dir Directory containing Quarto dashboard files
#' @param output_dir Directory for generated HTML files
#' @param render_all Whether to render all pages (default: TRUE)
#' @return Path to generated index.html
generate_codebook_dashboard <- function(
  codebook_path = "codebook/data/codebook.json",
  dashboard_dir = "codebook/dashboard",
  output_dir = "docs/codebook_dashboard",
  render_all = TRUE
) {

  message("=== Generating Codebook Dashboard ===")

  # Check if codebook exists
  if (!file.exists(codebook_path)) {
    stop("Codebook file not found: ", codebook_path)
  }

  # Check if dashboard directory exists
  if (!dir.exists(dashboard_dir)) {
    stop("Dashboard directory not found: ", dashboard_dir)
  }

  # Check if Quarto is available
  tryCatch({
    quarto_version <- system("quarto --version", intern = TRUE)
    message("Found Quarto version: ", quarto_version)
  }, error = function(e) {
    message("Quarto not found in PATH, attempting to find it...")
    # Try to find Quarto
    possible_paths <- c(
      "C:/Program Files/Quarto/bin/quarto.exe",
      "C:/Program Files (x86)/Quarto/bin/quarto.exe",
      "/usr/local/bin/quarto",
      "/opt/quarto/bin/quarto"
    )

    found_quarto <- FALSE
    for (path in possible_paths) {
      if (file.exists(path)) {
        Sys.setenv(PATH = paste(dirname(path), Sys.getenv("PATH"), sep = ";"))
        found_quarto <- TRUE
        message("Found Quarto at: ", path)
        break
      }
    }

    if (!found_quarto) {
      stop("Quarto not found. Please install Quarto from https://quarto.org/")
    }
  })

  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("Created output directory: ", output_dir)
  }

  # Get current working directory to restore later
  original_wd <- getwd()

  tryCatch({

    # Change to dashboard directory
    setwd(dashboard_dir)
    message("Working directory: ", getwd())

    # Validate codebook before rendering
    message("Validating codebook...")
    source("../../R/codebook/load_codebook.R")
    codebook <- load_codebook(paste0("../../", codebook_path), validate = FALSE)
    message("Codebook loaded successfully: ", codebook$metadata$total_items, " items")

    # Render the Quarto project
    message("Rendering Quarto dashboard...")

    if (render_all) {
      # Render all pages
      quarto::quarto_render()
    } else {
      # Render specific pages
      pages <- c("index.qmd", "items.qmd", "domains.qmd", "studies.qmd",
                "psychometrics.qmd", "quality.qmd")

      for (page in pages) {
        if (file.exists(page)) {
          message("Rendering ", page, "...")
          quarto::quarto_render(page)
        }
      }
    }

    # Check if index.html was generated
    index_path <- file.path(output_dir, "index.html")
    if (file.exists(index_path)) {
      message("✅ Dashboard generated successfully!")
      message("📊 View at: ", normalizePath(index_path))
      message("🌐 Or serve locally with: quarto preview")

      return(index_path)
    } else {
      warning("Dashboard generation completed but index.html not found")
      return(NULL)
    }

  }, error = function(e) {
    message("❌ Error during dashboard generation: ", e$message)
    return(NULL)
  }, finally = {
    # Restore original working directory
    setwd(original_wd)
  })
}

#' Preview the dashboard locally
#'
#' @param dashboard_dir Directory containing Quarto dashboard files
preview_dashboard <- function(dashboard_dir = "codebook/dashboard") {
  original_wd <- getwd()

  tryCatch({
    setwd(dashboard_dir)
    message("Starting preview server...")
    message("Dashboard will open in your browser")
    quarto::quarto_preview()
  }, finally = {
    setwd(original_wd)
  })
}

#' Quick dashboard regeneration for development
#'
#' @param page_name Optional specific page to render (e.g., "index", "items")
quick_render <- function(page_name = NULL) {
  dashboard_dir <- "codebook/dashboard"
  original_wd <- getwd()

  tryCatch({
    setwd(dashboard_dir)

    if (is.null(page_name)) {
      # Render all
      quarto::quarto_render()
    } else {
      # Render specific page
      page_file <- paste0(page_name, ".qmd")
      if (file.exists(page_file)) {
        quarto::quarto_render(page_file)
        message("Rendered: ", page_file)
      } else {
        stop("Page not found: ", page_file)
      }
    }
  }, finally = {
    setwd(original_wd)
  })
}

# Run dashboard generation if script is executed directly
if (!interactive()) {
  result <- generate_codebook_dashboard()
  if (!is.null(result)) {
    message("Dashboard available at: ", result)
  } else {
    stop("Dashboard generation failed")
  }
}