# HRTL Production Migration Plan

**Status**: Ready for implementation
**Created**: December 2025
**Expected Output**: 56.9% overall HRTL (804/1,412 children ages 3-5)

---

## 1. File Migration

### Move from `scripts/temp/` to `scripts/hrtl/`

| Current Location | New Location |
|-----------------|--------------|
| `scripts/temp/phase2_rasch_step1.R` | `scripts/hrtl/01_extract_domain_datasets.R` |
| `scripts/temp/phase2_rasch_step2.R` | `scripts/hrtl/02_fit_rasch_models.R` |
| `scripts/temp/phase2_rasch_step3_imputation.R` | `scripts/hrtl/03_impute_missing_values.R` |
| `scripts/temp/test_hrtl_percentages.R` | `scripts/hrtl/04_score_hrtl.R` |

### Production Functions in `R/hrtl/`

| File | Status | Purpose |
|------|--------|---------|
| `R/hrtl/score_hrtl.R` | **CREATE** | Main scoring wrapper (calls steps 1-4) |
| `R/hrtl/save_hrtl_to_db.R` | **CREATE** | Database persistence |
| `R/hrtl/get_itemdict22.R` | EXISTS | Item dictionary (reference only) |
| `R/hrtl/hrtl_scoring_2022.R` | EXISTS | Original CAHMI implementation (reference only) |

---

## 2. Production Orchestrator Script

Create `scripts/hrtl/run_hrtl_pipeline.R`:

```r
#!/usr/bin/env Rscript
# HRTL Scoring Pipeline Orchestrator
# Runs all steps: domain extraction -> Rasch -> imputation -> scoring

message("=== HRTL Scoring Pipeline ===\n")
start_time <- Sys.time()

# Step 1: Extract domain datasets
source("scripts/hrtl/01_extract_domain_datasets.R")

# Step 2: Fit Rasch models
source("scripts/hrtl/02_fit_rasch_models.R")

# Step 3: Impute missing values
source("scripts/hrtl/03_impute_missing_values.R")

# Step 4: Score HRTL
source("scripts/hrtl/04_score_hrtl.R")

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
message(sprintf("\nHRTL Pipeline complete in %.1f seconds", elapsed))
```

---

## 3. Pipeline Integration (Step 7.7)

Add to `pipelines/orchestration/ne25_pipeline.R` after Step 7.6 (GSED):

```r
# ===========================================================================
# STEP 7.7: HRTL SCORING (FOR CHILDREN AGES 3-5)
# ===========================================================================
message("\n--- Step 7.7: HRTL School Readiness Scoring ---")
hrtl_start <- Sys.time()

tryCatch({
  source("R/hrtl/score_hrtl.R")

  hrtl_results <- score_hrtl(
    data = final_data,
    db_path = "data/duckdb/kidsights_local.duckdb",
    verbose = TRUE
  )

  metrics$hrtl_eligible <- hrtl_results$n_eligible
  metrics$hrtl_on_track <- hrtl_results$n_hrtl
  metrics$hrtl_pct <- hrtl_results$hrtl_pct

}, error = function(e) {
  warning(paste("HRTL scoring failed:", e$message))
})

hrtl_time <- as.numeric(difftime(Sys.time(), hrtl_start, units = "secs"))
metrics$hrtl_duration <- hrtl_time
```

---

## 4. Database Tables

| Table | Columns | Purpose |
|-------|---------|---------|
| `ne25_hrtl_domain_scores` | pid, record_id, domain, status, avg_score | Per-domain classification |
| `ne25_hrtl_overall` | pid, record_id, n_on_track, n_needs_support, hrtl | Overall HRTL boolean |

---

## 5. Validation Script

Save as `scripts/hrtl/validate_hrtl_results.R`:

```r
#!/usr/bin/env Rscript
# HRTL Validation: Verify domain on-track percentages match expected values

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
    SUM(CASE WHEN status = 'On-Track' THEN 1 ELSE 0 END) as n_on_track,
    100.0 * SUM(CASE WHEN status = 'On-Track' THEN 1 ELSE 0 END) / COUNT(*) as pct_on_track
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

  act_row <- actual[grepl(gsub("-.*", "", domain_name), actual$domain, ignore.case = TRUE), ]

  if (nrow(act_row) == 0) {
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
overall <- DBI::dbGetQuery(
  duckdb::dbConnect(duckdb::duckdb(),
                    dbdir = "data/duckdb/kidsights_local.duckdb",
                    read_only = TRUE),
  "SELECT COUNT(*) as n, SUM(CASE WHEN hrtl THEN 1 ELSE 0 END) as n_hrtl FROM ne25_hrtl_overall"
)

hrtl_pct <- round(100 * overall$n_hrtl / overall$n, 1)
expected_hrtl <- 56.9

hrtl_match <- abs(hrtl_pct - expected_hrtl) < 1.0
hrtl_status <- if (hrtl_match) "[PASS]" else "[FAIL]"
if (!hrtl_match) all_pass <- FALSE

message(sprintf("\n%s Overall HRTL: %.1f%% (expected %.1f%%), n=%d",
                hrtl_status, hrtl_pct, expected_hrtl, overall$n))

message("\n", strrep("=", 70))
if (all_pass) {
  message("VALIDATION PASSED - All metrics within tolerance")
} else {
  message("VALIDATION FAILED - Review discrepancies above")
}
message(strrep("=", 70))
```

---

## 6. Implementation Checklist

- [ ] Move `phase2_rasch_step1.R` → `scripts/hrtl/01_extract_domain_datasets.R`
- [ ] Move `phase2_rasch_step2.R` → `scripts/hrtl/02_fit_rasch_models.R`
- [ ] Move `phase2_rasch_step3_imputation.R` → `scripts/hrtl/03_impute_missing_values.R`
- [ ] Move `test_hrtl_percentages.R` → `scripts/hrtl/04_score_hrtl.R`
- [ ] Create `scripts/hrtl/run_hrtl_pipeline.R` orchestrator
- [ ] Create `R/hrtl/score_hrtl.R` production wrapper
- [ ] Create `R/hrtl/save_hrtl_to_db.R` database persistence
- [ ] Add Step 7.7 to `pipelines/orchestration/ne25_pipeline.R`
- [ ] Create `scripts/hrtl/validate_hrtl_results.R`
- [ ] Run validation, verify all [PASS]
- [ ] Update CLAUDE.md with HRTL documentation
- [ ] Clean up `scripts/temp/` (remove migrated files)

---

## 7. Expected Validation Output

```
=== HRTL Validation ===

Domain-Level Validation:
----------------------------------------------------------------------
[PASS] Health: 88.8% (expected 88.8%), n=1425 (expected 1425)
[PASS] Social-Emotional Development: 86.1% (expected 86.1%), n=1425 (expected 1425)
[PASS] Early Learning Skills: 71.7% (expected 71.7%), n=1413 (expected 1413)
[PASS] Self-Regulation: 66.1% (expected 66.1%), n=1411 (expected 1411)
[PASS] Motor Development: 55.0% (expected 55.0%), n=1412 (expected 1412)
----------------------------------------------------------------------

[PASS] Overall HRTL: 56.9% (expected 56.9%), n=1412

======================================================================
VALIDATION PASSED - All metrics within tolerance
======================================================================
```
