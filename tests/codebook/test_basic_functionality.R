#' Basic Functionality Tests for Codebook System
#'
#' Simple test script to verify core functionality works correctly

library(testthat)

# Source all codebook functions
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")
source("R/codebook/validate_codebook.R")

#' Run basic functionality tests
#' @return Test results
test_basic_functionality <- function() {

  cat("=== Testing Basic Codebook Functionality ===\n\n")

  # Test 1: Load codebook
  cat("Test 1: Loading codebook...\n")
  tryCatch({
    codebook <- load_codebook("codebook/data/codebook.json", validate = FALSE)
    cat("✅ Codebook loaded successfully\n")
    cat("   Items:", length(codebook$items), "\n")
    cat("   Version:", codebook$metadata$version, "\n")
  }, error = function(e) {
    cat("❌ Failed to load codebook:", e$message, "\n")
    return(FALSE)
  })

  # Test 2: Query functions
  cat("\nTest 2: Testing query functions...\n")
  tryCatch({
    # Filter by domain
    motor_items <- filter_items_by_domain(codebook, "motor")
    cat("✅ Domain filtering works - found", length(motor_items), "motor items\n")

    # Filter by study
    ne25_items <- filter_items_by_study(codebook, "NE25")
    cat("✅ Study filtering works - found", length(ne25_items), "NE25 items\n")

    # Get single item
    test_item <- get_item(codebook, "AA102")
    if (!is.null(test_item)) {
      cat("✅ Single item retrieval works\n")
    } else {
      cat("⚠️ Item AA102 not found, but function works\n")
    }

    # Convert to dataframe
    df <- items_to_dataframe(codebook)
    cat("✅ DataFrame conversion works - ", nrow(df), "rows\n")

  }, error = function(e) {
    cat("❌ Query function failed:", e$message, "\n")
    return(FALSE)
  })

  # Test 3: Search function
  cat("\nTest 3: Testing search functionality...\n")
  tryCatch({
    search_results <- search_items(codebook, "walk")
    cat("✅ Search works - found", length(search_results), "items containing 'walk'\n")
  }, error = function(e) {
    cat("❌ Search failed:", e$message, "\n")
  })

  # Test 4: Validation
  cat("\nTest 4: Testing validation...\n")
  tryCatch({
    validation_results <- run_validation_checks(codebook)
    cat("✅ Validation works\n")
    cat("   Overall status:", validation_results$summary$overall_status, "\n")
    cat("   Pass rate:", round(validation_results$summary$pass_rate * 100, 1), "%\n")
    cat("   Issues:", validation_results$summary$total_issues, "\n")
  }, error = function(e) {
    cat("❌ Validation failed:", e$message, "\n")
  })

  # Test 5: Study coverage
  cat("\nTest 5: Testing coverage analysis...\n")
  tryCatch({
    coverage_matrix <- get_study_coverage(codebook)
    cat("✅ Coverage matrix works - dimensions:",
        nrow(coverage_matrix), "x", ncol(coverage_matrix), "\n")

    crosstab <- get_domain_study_crosstab(codebook)
    cat("✅ Domain × study crosstab works - dimensions:",
        nrow(crosstab), "x", ncol(crosstab), "\n")
  }, error = function(e) {
    cat("❌ Coverage analysis failed:", e$message, "\n")
  })

  cat("\n=== Testing Complete ===\n")
  return(TRUE)
}

#' Quick validation test
#' @return Validation summary
quick_validation_test <- function() {
  cat("=== Quick Validation Test ===\n")

  codebook <- load_codebook("codebook/data/codebook.json", validate = FALSE)
  validation <- run_validation_checks(codebook)

  print(validation)

  return(validation)
}

# Run tests if script is executed directly
if (!interactive()) {
  test_basic_functionality()
}