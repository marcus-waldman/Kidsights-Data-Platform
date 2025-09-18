#!/usr/bin/env Rscript
#
# Render Codebook Dashboard
#
# Purpose: Render the interactive codebook dashboard with updated data
#
# Author: Kidsights Data Platform
# Date: September 17, 2025

cat("=== Rendering Codebook Dashboard ===\n\n")

# Required packages
required_packages <- c("quarto", "jsonlite", "rmarkdown")

# Function to install and load packages
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

# Install and load packages
install_and_load(required_packages)

# Set up Quarto and Pandoc paths
cat("Setting up Quarto and Pandoc paths...\n")
quarto_path <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
pandoc_dir <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools"

# Set environment variables
Sys.setenv(QUARTO_PATH = quarto_path)
Sys.setenv(RSTUDIO_PANDOC = pandoc_dir)

# Verify tools are accessible
if (file.exists(quarto_path)) {
  cat("✓ Quarto found at:", quarto_path, "\n")
} else {
  stop("ERROR: Quarto not found at expected path")
}

if (file.exists(file.path(pandoc_dir, "pandoc.exe"))) {
  cat("✓ Pandoc found at:", file.path(pandoc_dir, "pandoc.exe"), "\n")
} else {
  stop("ERROR: Pandoc not found at expected path")
}

# Change to dashboard directory
setwd("codebook/dashboard")

# Check if codebook file exists
codebook_path <- "../../codebook/data/codebook.json"
if (!file.exists(codebook_path)) {
  stop("ERROR: Codebook not found at: ", codebook_path)
}

# Load and verify codebook
cat("Loading updated codebook...\n")
codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)
cat("✓ Codebook loaded - Version:", codebook$metadata$version, "\n")
cat("✓ Total items:", length(codebook$items), "\n")

# Render the dashboard
cat("\nRendering dashboard...\n")

tryCatch({
  # Try quarto package with explicit path
  cat("Attempting render with quarto package...\n")
  quarto::quarto_render("index.qmd")
  cat("✓ Dashboard rendered successfully with quarto package!\n")
}, error = function(e) {
  cat("Quarto package failed:", e$message, "\n")
  cat("Trying direct quarto executable...\n")

  tryCatch({
    # Try direct quarto executable
    system2(quarto_path, args = c("render", "index.qmd"), stdout = TRUE, stderr = TRUE)
    cat("✓ Dashboard rendered successfully with direct quarto!\n")
  }, error = function(e2) {
    cat("Direct quarto failed, trying rmarkdown...\n")

    tryCatch({
      # Fallback to rmarkdown
      rmarkdown::render("index.qmd", output_dir = "../../docs/codebook_dashboard/")
      cat("✓ Dashboard rendered successfully with rmarkdown!\n")
    }, error = function(e3) {
      cat("ERROR: All rendering methods failed\n")
      cat("Quarto package error:", e$message, "\n")
      cat("Direct quarto error:", e2$message, "\n")
      cat("Rmarkdown error:", e3$message, "\n")
    })
  })
})

# Check output
output_path <- "../../docs/codebook_dashboard/index.html"
if (file.exists(output_path)) {
  cat("\n✓ Dashboard available at: docs/codebook_dashboard/index.html\n")

  # Get file info
  file_info <- file.info(output_path)
  cat("✓ File size:", round(file_info$size / 1024, 1), "KB\n")
  cat("✓ Last modified:", as.character(file_info$mtime), "\n")
} else {
  cat("\n⚠ Dashboard output not found at expected location\n")

  # List files to see where output went
  cat("Files in current directory:\n")
  print(list.files(pattern = "*.html"))
}

cat("\n=== Dashboard Rendering Complete ===\n")