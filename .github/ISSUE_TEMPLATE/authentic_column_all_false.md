---
name: All records in ne25_transformed have authentic=FALSE
about: Data quality issue with authenticity validation
title: 'All records in ne25_transformed have authentic=FALSE'
labels: bug, data-quality
assignees: ''
---

## Problem

The `authentic` column in the `ne25_transformed` DuckDB table has **all FALSE values**, preventing filtering by both `eligible=TRUE AND authentic=TRUE`.

## Evidence

Query results from `ne25_transformed` table:

```
Total records: 4,965
eligible=TRUE: 3,507
authentic=TRUE: 0
eligible=TRUE AND authentic=TRUE: 0

Cross-tabulation (eligible x authentic):
  eligible | authentic | count
  ---------|-----------|-------
  FALSE    | FALSE     | 1,458
  TRUE     | FALSE     | 3,507
```

**All 4,965 records have `authentic=FALSE`.**

## Impact

- IRT calibration dataset preparation currently cannot filter by authenticity
- `scripts/irt_scoring/prepare_calibration_dataset.R` had to be modified to use only `eligible=TRUE`
- Risk of including fraudulent/duplicate responses in calibration data
- Affects downstream analyses that depend on data authenticity

## Root Cause Investigation Needed

1. **Check if authenticity validation has been run** on NE25 data
   - Is there a separate process that sets `authentic=TRUE`?
   - Has this process been executed on the current dataset?

2. **Verify authenticity detection logic** in the pipeline
   - Location: `R/harmonize/ne25_eligibility.R` (or similar file)
   - Check if logic is correctly identifying authentic responses

3. **Determine default value behavior**
   - Should `authentic` default to FALSE (opt-in) or TRUE (opt-out)?
   - Current behavior: all records default to FALSE

4. **Check upstream processes**
   - REDCap import: Does it set authenticity flags?
   - Transformation pipeline: Where should authenticity be validated?

## Expected Behavior

The `authentic` column should reflect actual authenticity validation:
- **TRUE** for records that pass authenticity checks (no red flags)
- **FALSE** for suspected duplicates, fraudulent responses, or quality issues

## Current Workaround

Modified `scripts/irt_scoring/prepare_calibration_dataset.R` to use only `eligible=TRUE` filter (line 148):

```r
# Changed from:
ne25_raw <- DBI::dbGetQuery(conn, "SELECT * FROM ne25_transformed WHERE eligible = TRUE AND authentic = TRUE")

# To:
ne25_raw <- DBI::dbGetQuery(conn, "SELECT * FROM ne25_transformed WHERE eligible = TRUE")
```

This workaround allows IRT calibration to proceed but may include inauthentic responses.

## Related Files

- **Calibration script:** `scripts/irt_scoring/prepare_calibration_dataset.R` (line 148)
- **Eligibility/authenticity logic:** `R/harmonize/ne25_eligibility.R`
- **Database:** `data/duckdb/kidsights_local.duckdb` → table `ne25_transformed`

## Discovered During

IRT calibration dataset preparation workflow testing (2025-01-05)
- Test script: `scripts/irt_scoring/test_prepare_calibration.R`
- Investigation script: `scripts/temp/check_ne25_authentic.R`

## Priority

**Medium** - Affects data quality for IRT calibration and research analyses, but not blocking pipeline execution.

## Next Steps

1. [ ] Identify where `authentic` column should be set in the pipeline
2. [ ] Run authenticity validation on NE25 data
3. [ ] Verify expected number of authentic records
4. [ ] Re-test calibration dataset preparation with proper filtering
5. [ ] Document authenticity validation process in pipeline guides
