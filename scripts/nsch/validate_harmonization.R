#' Validate NSCH Harmonization Results
#'
#' Performs 7 validation checks to verify harmonization correctness:
#' 1. Column Count (expected: 29 for 2021, 35 for 2022)
#' 2. Zero-Based Encoding (all min = 0)
#' 3. Reverse Coding Verification (spot checks)
#' 4. Missing Value Handling (values >= 90 → NA)
#' 5. Correlation Test (harmonized matches expected transformation)
#' 6. Age Gradient Correlation (developmental items correlate positively with age)
#' 7. Consecutive Integer Values (no gaps in value sequence)
#'
#' Usage:
#'   source("scripts/nsch/validate_harmonization.R")
#'   validate_nsch_harmonization()

library(duckdb)
library(DBI)
library(jsonlite)

validate_nsch_harmonization <- function(
  db_path = "data/duckdb/kidsights_local.duckdb",
  codebook_path = "codebook/data/codebook.json"
) {

  cat("\n")
  cat("=" , rep("=", 79), "\n", sep = "")
  cat("NSCH HARMONIZATION VALIDATION\n")
  cat("=" , rep("=", 79), "\n", sep = "")
  cat("\n")

  # Connect to database
  con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Load codebook
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # ========================================================================
  # Validation Check 1: Column Count
  # ========================================================================

  cat("[CHECK 1] Column Count\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check1_pass <- TRUE

  # Get columns with cahmi21 lexicons
  cahmi21_items <- names(Filter(function(item) {
    !is.null(item$lexicons$cahmi21)
  }, codebook$items))

  # Get columns with cahmi22 lexicons
  cahmi22_items <- names(Filter(function(item) {
    !is.null(item$lexicons$cahmi22)
  }, codebook$items))

  cat(sprintf("  Expected harmonized items (from codebook):\n"))
  cat(sprintf("    CAHMI21: %d items\n", length(cahmi21_items)))
  cat(sprintf("    CAHMI22: %d items\n", length(cahmi22_items)))
  cat("\n")

  # Check NSCH 2021
  nsch21_cols <- DBI::dbGetQuery(con, "PRAGMA table_info(nsch_2021)")$name
  nsch21_harmonized <- intersect(nsch21_cols, cahmi21_items)

  if (length(nsch21_harmonized) == 29) {
    cat(sprintf("  [OK] nsch_2021: %d harmonized columns found\n", length(nsch21_harmonized)))
  } else {
    cat(sprintf("  [WARNING] nsch_2021: %d harmonized columns (expected 29)\n", length(nsch21_harmonized)))
    check1_pass <- FALSE
  }

  # Check NSCH 2022
  nsch22_cols <- DBI::dbGetQuery(con, "PRAGMA table_info(nsch_2022)")$name
  nsch22_harmonized <- intersect(nsch22_cols, cahmi22_items)

  if (length(nsch22_harmonized) == 35) {
    cat(sprintf("  [OK] nsch_2022: %d harmonized columns found\n", length(nsch22_harmonized)))
  } else {
    cat(sprintf("  [WARNING] nsch_2022: %d harmonized columns (expected 35)\n", length(nsch22_harmonized)))
    check1_pass <- FALSE
  }

  cat("\n")

  # ========================================================================
  # Validation Check 2: Zero-Based Encoding
  # ========================================================================

  cat("[CHECK 2] Zero-Based Encoding\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check2_pass <- TRUE

  # Check NSCH 2021
  for (col in nsch21_harmonized) {
    min_val <- DBI::dbGetQuery(con, sprintf("SELECT MIN(%s) FROM nsch_2021", col))[[1]]
    if (!is.na(min_val) && min_val != 0) {
      cat(sprintf("  [FAIL] nsch_2021.%s: min = %f (expected 0)\n", col, min_val))
      check2_pass <- FALSE
    }
  }

  # Check NSCH 2022
  for (col in nsch22_harmonized) {
    min_val <- DBI::dbGetQuery(con, sprintf("SELECT MIN(%s) FROM nsch_2022", col))[[1]]
    if (!is.na(min_val) && min_val != 0) {
      cat(sprintf("  [FAIL] nsch_2022.%s: min = %f (expected 0)\n", col, min_val))
      check2_pass <- FALSE
    }
  }

  if (check2_pass) {
    cat("  [OK] All harmonized columns are 0-based (min=0)\n")
  }

  cat("\n")

  # ========================================================================
  # Validation Check 3: Reverse Coding Verification
  # ========================================================================

  cat("[CHECK 3] Reverse Coding Verification\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check3_pass <- TRUE

  # Test DD299 (DISTRACTED) - cahmi21 reverse=False, cahmi22 reverse=False
  if ("DD299" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT DISTRACTED, DD299 FROM nsch_2021 WHERE DISTRACTED IS NOT NULL AND DD299 IS NOT NULL")
    cor_21 <- cor(nsch21_data$DISTRACTED, nsch21_data$DD299)

    if (cor_21 > 0.95) {
      cat(sprintf("  [OK] DD299 (NSCH 2021): cor(raw, harmonized) = %.3f (expected positive)\n", cor_21))
    } else {
      cat(sprintf("  [FAIL] DD299 (NSCH 2021): cor = %.3f (expected > 0.95)\n", cor_21))
      check3_pass <- FALSE
    }
  }

  if ("DD299" %in% nsch22_harmonized) {
    nsch22_data <- DBI::dbGetQuery(con, "SELECT DISTRACTED, DD299 FROM nsch_2022 WHERE DISTRACTED IS NOT NULL AND DD299 IS NOT NULL")
    cor_22 <- cor(nsch22_data$DISTRACTED, nsch22_data$DD299)

    if (cor_22 > 0.95) {
      cat(sprintf("  [OK] DD299 (NSCH 2022): cor(raw, harmonized) = %.3f (expected positive)\n", cor_22))
    } else {
      cat(sprintf("  [FAIL] DD299 (NSCH 2022): cor = %.3f (expected > 0.95)\n", cor_22))
      check3_pass <- FALSE
    }
  }

  # Test DD103 (SIMPLEINST) - cahmi21 reverse=True (should be negatively correlated with raw)
  # Note: Raw SIMPLEINST has higher values = better, harmonized should reverse this
  if ("DD103" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT SIMPLEINST, DD103 FROM nsch_2021 WHERE SIMPLEINST IS NOT NULL AND DD103 IS NOT NULL")
    cor_21 <- cor(nsch21_data$SIMPLEINST, nsch21_data$DD103)

    if (cor_21 < -0.95) {
      cat(sprintf("  [OK] DD103 (NSCH 2021): cor(raw, harmonized) = %.3f (expected negative)\n", cor_21))
    } else {
      cat(sprintf("  [FAIL] DD103 (NSCH 2021): cor = %.3f (expected < -0.95)\n", cor_21))
      check3_pass <- FALSE
    }
  }

  cat("\n")

  # ========================================================================
  # Validation Check 4: Missing Value Handling
  # ========================================================================

  cat("[CHECK 4] Missing Value Handling\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check4_pass <- TRUE

  # Check a few items that have missing codes >= 90
  # DD299 (DISTRACTED): Missing codes include 95, 96
  if ("DD299" %in% nsch21_harmonized) {
    result <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) FILTER (WHERE DISTRACTED >= 90 AND DD299 IS NOT NULL) as raw_90_harmonized_not_null,
        COUNT(*) FILTER (WHERE DISTRACTED >= 90 AND DD299 IS NULL) as raw_90_harmonized_null
      FROM nsch_2021
    ")

    if (result$raw_90_harmonized_not_null == 0) {
      cat(sprintf("  [OK] DD299 (NSCH 2021): All raw values >= 90 recoded to NA (%d cases)\n", result$raw_90_harmonized_null))
    } else {
      cat(sprintf("  [FAIL] DD299 (NSCH 2021): %d raw values >= 90 NOT recoded to NA\n", result$raw_90_harmonized_not_null))
      check4_pass <- FALSE
    }
  }

  if ("DD299" %in% nsch22_harmonized) {
    result <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) FILTER (WHERE DISTRACTED >= 90 AND DD299 IS NOT NULL) as raw_90_harmonized_not_null,
        COUNT(*) FILTER (WHERE DISTRACTED >= 90 AND DD299 IS NULL) as raw_90_harmonized_null
      FROM nsch_2022
    ")

    if (result$raw_90_harmonized_not_null == 0) {
      cat(sprintf("  [OK] DD299 (NSCH 2022): All raw values >= 90 recoded to NA (%d cases)\n", result$raw_90_harmonized_null))
    } else {
      cat(sprintf("  [FAIL] DD299 (NSCH 2022): %d raw values >= 90 NOT recoded to NA\n", result$raw_90_harmonized_not_null))
      check4_pass <- FALSE
    }
  }

  cat("\n")

  # ========================================================================
  # Validation Check 5: Correlation Test (Manual Transformation)
  # ========================================================================

  cat("[CHECK 5] Correlation Test (Manual Transformation)\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check5_pass <- TRUE

  # Test DD201 (FOODSIT) - forward coded (cahmi21/cahmi22 reverse=False)
  if ("DD201" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT FOODSIT, DD201 FROM nsch_2021 WHERE FOODSIT IS NOT NULL AND FOODSIT < 90 AND DD201 IS NOT NULL")
    # Manual forward transformation
    manual_transform <- nsch21_data$FOODSIT - min(nsch21_data$FOODSIT, na.rm = TRUE)
    cor_val <- cor(manual_transform, nsch21_data$DD201)

    if (cor_val > 0.9999) {
      cat(sprintf("  [OK] DD201 (NSCH 2021): cor(manual, harmonized) = %.6f (exact match)\n", cor_val))
    } else {
      cat(sprintf("  [FAIL] DD201 (NSCH 2021): cor = %.6f (expected ~1.0)\n", cor_val))
      check5_pass <- FALSE
    }
  }

  # Test DD103 (SIMPLEINST) - reverse coded
  if ("DD103" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT SIMPLEINST, DD103 FROM nsch_2021 WHERE SIMPLEINST IS NOT NULL AND SIMPLEINST < 90 AND DD103 IS NOT NULL")
    # Manual reverse transformation
    y <- nsch21_data$SIMPLEINST - min(nsch21_data$SIMPLEINST, na.rm = TRUE)
    manual_transform <- abs(y - max(y, na.rm = TRUE))
    cor_val <- cor(manual_transform, nsch21_data$DD103)

    if (cor_val > 0.9999) {
      cat(sprintf("  [OK] DD103 (NSCH 2021): cor(manual, harmonized) = %.6f (exact match)\n", cor_val))
    } else {
      cat(sprintf("  [FAIL] DD103 (NSCH 2021): cor = %.6f (expected ~1.0)\n", cor_val))
      check5_pass <- FALSE
    }
  }

  cat("\n")

  # ========================================================================
  # Validation Check 6: Age Gradient Correlation
  # ========================================================================

  cat("[CHECK 6] Age Gradient Correlation\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check6_pass <- TRUE

  # Test developmental items that should correlate positively with age
  # EG2_2 (SHOWKNOW) - Shows knowledge of letters/numbers (should increase with age)
  if ("EG2_2" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT SC_AGE_YEARS, EG2_2 FROM nsch_2021 WHERE SC_AGE_YEARS IS NOT NULL AND EG2_2 IS NOT NULL AND SC_AGE_YEARS BETWEEN 0 AND 6")
    cor_age <- cor(nsch21_data$SC_AGE_YEARS, nsch21_data$EG2_2)

    if (cor_age > 0.2) {
      cat(sprintf("  [OK] EG2_2 (NSCH 2021): cor(age, harmonized) = %.3f (expected positive)\n", cor_age))
    } else {
      cat(sprintf("  [WARNING] EG2_2 (NSCH 2021): cor = %.3f (expected > 0.2)\n", cor_age))
      check6_pass <- FALSE
    }
  }

  if ("EG2_2" %in% nsch22_harmonized) {
    nsch22_data <- DBI::dbGetQuery(con, "SELECT SC_AGE_YEARS, EG2_2 FROM nsch_2022 WHERE SC_AGE_YEARS IS NOT NULL AND EG2_2 IS NOT NULL AND SC_AGE_YEARS BETWEEN 0 AND 6")
    cor_age <- cor(nsch22_data$SC_AGE_YEARS, nsch22_data$EG2_2)

    if (cor_age > 0.2) {
      cat(sprintf("  [OK] EG2_2 (NSCH 2022): cor(age, harmonized) = %.3f (expected positive)\n", cor_age))
    } else {
      cat(sprintf("  [WARNING] EG2_2 (NSCH 2022): cor = %.3f (expected > 0.2)\n", cor_age))
      check6_pass <- FALSE
    }
  }

  # DD201 (FOODSIT) - Can eat with fork/spoon (should increase with age)
  if ("DD201" %in% nsch21_harmonized) {
    nsch21_data <- DBI::dbGetQuery(con, "SELECT SC_AGE_YEARS, DD201 FROM nsch_2021 WHERE SC_AGE_YEARS IS NOT NULL AND DD201 IS NOT NULL AND SC_AGE_YEARS BETWEEN 0 AND 6")
    cor_age <- cor(nsch21_data$SC_AGE_YEARS, nsch21_data$DD201)

    if (cor_age > 0.2) {
      cat(sprintf("  [OK] DD201 (NSCH 2021): cor(age, harmonized) = %.3f (expected positive)\n", cor_age))
    } else {
      cat(sprintf("  [WARNING] DD201 (NSCH 2021): cor = %.3f (expected > 0.2)\n", cor_age))
      check6_pass <- FALSE
    }
  }

  if ("DD201" %in% nsch22_harmonized) {
    nsch22_data <- DBI::dbGetQuery(con, "SELECT SC_AGE_YEARS, DD201 FROM nsch_2022 WHERE SC_AGE_YEARS IS NOT NULL AND DD201 IS NOT NULL AND SC_AGE_YEARS BETWEEN 0 AND 6")
    cor_age <- cor(nsch22_data$SC_AGE_YEARS, nsch22_data$DD201)

    if (cor_age > 0.2) {
      cat(sprintf("  [OK] DD201 (NSCH 2022): cor(age, harmonized) = %.3f (expected positive)\n", cor_age))
    } else {
      cat(sprintf("  [WARNING] DD201 (NSCH 2022): cor = %.3f (expected > 0.2)\n", cor_age))
      check6_pass <- FALSE
    }
  }

  cat("\n")

  # ========================================================================
  # Validation Check 7: Consecutive Integer Values
  # ========================================================================

  cat("[CHECK 7] Consecutive Integer Values (No Gaps)\n")
  cat("-", rep("-", 79), "\n", sep = "")

  check7_pass <- TRUE

  # Check a sample of items to verify values are consecutive integers
  sample_items_2021 <- intersect(c("DD103", "DD201", "DD299", "EG2_2"), nsch21_harmonized)
  sample_items_2022 <- intersect(c("DD201", "DD299", "EG2_2", "CQFA002"), nsch22_harmonized)

  for (col in sample_items_2021) {
    data_vals <- DBI::dbGetQuery(con, sprintf("SELECT DISTINCT %s FROM nsch_2021 WHERE %s IS NOT NULL ORDER BY %s", col, col, col))[[1]]
    if (length(data_vals) > 1) {
      diffs <- unique(diff(sort(unique(data_vals))))
      if (length(diffs) == 1 && diffs[1] == 1) {
        cat(sprintf("  [OK] %s (NSCH 2021): Consecutive integers (0-%d)\n", col, max(data_vals)))
      } else {
        cat(sprintf("  [FAIL] %s (NSCH 2021): Non-consecutive values or gaps detected\n", col))
        cat(sprintf("       Unique diffs: %s\n", paste(diffs, collapse = ", ")))
        check7_pass <- FALSE
      }
    }
  }

  for (col in sample_items_2022) {
    data_vals <- DBI::dbGetQuery(con, sprintf("SELECT DISTINCT %s FROM nsch_2022 WHERE %s IS NOT NULL ORDER BY %s", col, col, col))[[1]]
    if (length(data_vals) > 1) {
      diffs <- unique(diff(sort(unique(data_vals))))
      if (length(diffs) == 1 && diffs[1] == 1) {
        cat(sprintf("  [OK] %s (NSCH 2022): Consecutive integers (0-%d)\n", col, max(data_vals)))
      } else {
        cat(sprintf("  [FAIL] %s (NSCH 2022): Non-consecutive values or gaps detected\n", col))
        cat(sprintf("       Unique diffs: %s\n", paste(diffs, collapse = ", ")))
        check7_pass <- FALSE
      }
    }
  }

  cat("\n")

  # ========================================================================
  # Summary
  # ========================================================================

  cat("=" , rep("=", 79), "\n", sep = "")
  cat("VALIDATION SUMMARY\n")
  cat("=" , rep("=", 79), "\n", sep = "")
  cat("\n")

  all_pass <- check1_pass && check2_pass && check3_pass && check4_pass && check5_pass && check6_pass && check7_pass

  cat(sprintf("  Check 1 (Column Count):         %s\n", ifelse(check1_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 2 (Zero-Based Encoding):  %s\n", ifelse(check2_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 3 (Reverse Coding):       %s\n", ifelse(check3_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 4 (Missing Values):       %s\n", ifelse(check4_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 5 (Correlation Test):     %s\n", ifelse(check5_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 6 (Age Gradient):         %s\n", ifelse(check6_pass, "[PASS]", "[FAIL]")))
  cat(sprintf("  Check 7 (Consecutive Integers): %s\n", ifelse(check7_pass, "[PASS]", "[FAIL]")))
  cat("\n")

  if (all_pass) {
    cat("[OK] ALL VALIDATION CHECKS PASSED\n")
  } else {
    cat("[WARNING] Some validation checks failed - review output above\n")
  }

  cat("\n")

  return(invisible(all_pass))
}

# Auto-run if sourced as script
if (!interactive()) {
  validate_nsch_harmonization()
}
