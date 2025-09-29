#' Lightweight Dependency Manager for QMD Files
#'
#' This is a simplified version of the dependency manager specifically
#' for use in Quarto documents where the full system might not be available.

#' Quick function to ensure documentation packages are available
ensure_qmd_dependencies <- function() {
  required_packages <- c("DT", "knitr", "dplyr", "htmltools", "tibble")

  missing_packages <- character(0)
  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing_packages <- c(missing_packages, pkg)
    }
  }

  if (length(missing_packages) > 0) {
    message("Installing missing packages for QMD rendering: ",
            paste(missing_packages, collapse = ", "))

    tryCatch({
      install.packages(missing_packages,
                      repos = "https://cran.rstudio.com/",
                      dependencies = TRUE)
      message("Packages installed successfully")
    }, error = function(e) {
      stop("Failed to install required packages: ", e$message)
    })
  }

  return(TRUE)
}

# Auto-run when sourced
ensure_qmd_dependencies()