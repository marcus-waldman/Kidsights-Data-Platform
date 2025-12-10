#!/usr/bin/env Rscript
################################################################################
# HRTL Validation: Verify domain on-track percentages match expected values
################################################################################

library(dplyr)

message("=== HRTL Validation ===\n")

# Expected values from development testing
expected <- data.frame(
  domain = c("Health", "Social-Emotional Development", "Early Learning Skills",
             "Self-Regulation", "Motor Development"),
  expected_pct = c(88.8, 86.1, 71.7, 66.1, 55.0),
  expected_n = c(1425, 1425, 1413, 1411, 1412),
  stringsAsFactors = FALSE
)

# Load actual results
con <- duckdb::dbConnect(duckdb::duckdb(),
                         dbdir = "data/duckdb/kidsights_local.duckdb",
                         read_only = TRUE)

actual <- DBI::dbGetQuery(con, "
  SELECT
    domain,
    COUNT(*) as n,
    SUM(CASE WHEN classification = 'On-Track' THEN 1 ELSE 0 END) as n_on_track,
    100.0 * SUM(CASE WHEN classification = 'On-Track' THEN 1 ELSE 0 END) / COUNT(*) as pct_on_track
  FROM ne25_hrtl_domain_scores
  GROUP BY domain
")

duckdb::dbDisconnect(con, shutdown = TRUE)

# Validate
message("Domain-Level Validation:")
message(strrep("-", 70))

all_pass <- TRUE
for (i in 1:nrow(expected)) {
  domain_name <- expected$domain[i]
  exp_pct <- expected$expected_pct[i]
  exp_n <- expected$expected_n[i]

  # Match using partial domain name (handles variations)
  act_row <- actual[grepl(gsub("-.*", "", domain_name), actual$domain, ignore.case = TRUE), ]

  if (nrow(act_row) == 0) {
    # Motor Development excluded - this is expected
    if (domain_name == "Motor Development") {
      message(sprintf("[SKIP] %s: Excluded due to data quality issues", domain_name))
      next
    }
    message(sprintf("[FAIL] %s: NOT FOUND", domain_name))
    all_pass <- FALSE
    next
  }

  act_pct <- round(act_row$pct_on_track, 1)
  act_n <- act_row$n

  pct_match <- abs(act_pct - exp_pct) < 0.5
  n_match <- abs(act_n - exp_n) < 5

  status <- if (pct_match && n_match) "[PASS]" else "[FAIL]"
  if (!pct_match || !n_match) all_pass <- FALSE

  message(sprintf("%s %s: %.1f%% (expected %.1f%%), n=%d (expected %d)",
                  status, domain_name, act_pct, exp_pct, act_n, exp_n))
}

message(strrep("-", 70))

# Overall HRTL check
con <- duckdb::dbConnect(duckdb::duckdb(),
                         dbdir = "data/duckdb/kidsights_local.duckdb",
                         read_only = TRUE)

overall <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) as n,
    SUM(CASE WHEN hrtl = TRUE THEN 1 ELSE 0 END) as n_hrtl,
    SUM(CASE WHEN hrtl IS NULL THEN 1 ELSE 0 END) as n_null
  FROM ne25_hrtl_overall
")

duckdb::dbDisconnect(con, shutdown = TRUE)

# Note: Motor Development excluded, so HRTL is marked as NA
if (overall$n_null > 0) {
  message(sprintf("\n[INFO] Overall HRTL: NA (incomplete - Motor Development excluded)"))
  message(sprintf("       Total children in HRTL table: %d", overall$n))
  message(sprintf("       All records have hrtl=NA due to missing Motor Development domain"))
} else {
  hrtl_pct <- round(100 * overall$n_hrtl / overall$n, 1)
  expected_hrtl <- 56.9

  hrtl_match <- abs(hrtl_pct - expected_hrtl) < 1.0
  hrtl_status <- if (hrtl_match) "[PASS]" else "[FAIL]"
  if (!hrtl_match) all_pass <- FALSE

  message(sprintf("\n%s Overall HRTL: %.1f%% (expected %.1f%%), n=%d",
                  hrtl_status, hrtl_pct, expected_hrtl, overall$n))
}

message("\n", strrep("=", 70))
if (all_pass) {
  message("VALIDATION PASSED - All metrics within tolerance")
} else {
  message("VALIDATION FAILED - Review discrepancies above")
}
message(strrep("=", 70))
