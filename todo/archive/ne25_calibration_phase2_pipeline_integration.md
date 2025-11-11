# Phase 2: Integrate NE25 Calibration into Pipeline

**Issue:** #5 - Optimize NE25 Calibration Dataset and Integrate into Pipeline
**Status:** Not Started
**Estimated Time:** 30-40 minutes
**Created:** 2025-11-10

---

## Objective

Integrate NE25 calibration table creation as Step 11 in the NE25 pipeline (`pipelines/orchestration/ne25_pipeline.R`) to automate table generation on every pipeline run.

---

## Prerequisites

- [x] Phase 1 completed: Helper script exists at `scripts/irt_scoring/create_ne25_calibration_table.R`
- [x] Helper script tested and validated (2,831 records, 27 columns)
- [x] `ne25_calibration` table successfully created

---

## Tasks

### 1. Add Calibration Metrics Tracking
- [ ] Open `pipelines/orchestration/ne25_pipeline.R`
- [ ] Locate metrics initialization (line ~104-123)
- [ ] Add new metric: `calibration_table_duration = 0`
- [ ] Verify metrics list structure intact

### 2. Insert Step 11 After Interactive Dictionary
- [ ] Locate Step 10: "Generate Interactive Dictionary" (line ~620-640)
- [ ] Find comment: "Calculate final metrics" (line ~645)
- [ ] Insert new Step 11 section BEFORE final metrics
- [ ] Section header:
  ```r
  # ===========================================================================
  # STEP 11: CREATE NE25 CALIBRATION TABLE
  # ===========================================================================

  message("\n--- Step 11: Creating NE25 Calibration Table ---")
  ```

### 3. Implement Step 11 Logic
- [ ] Add timing start: `calibration_start <- Sys.time()`
- [ ] Source helper script:
  ```r
  source("scripts/irt_scoring/create_ne25_calibration_table.R")
  ```
- [ ] Wrap function call in tryCatch block:
  ```r
  tryCatch({
    create_ne25_calibration_table(
      codebook_path = "codebook/data/codebook.json",
      db_path = "data/duckdb/kidsights_local.duckdb",
      verbose = TRUE
    )
    message("NE25 calibration table created successfully")
  }, error = function(e) {
    warning(paste("Calibration table creation failed:", e$message))
    message("Pipeline will continue, but calibration table is unavailable")
  })
  ```
- [ ] Calculate duration: `calibration_time <- as.numeric(Sys.time() - calibration_start)`
- [ ] Store in metrics: `metrics$calibration_table_duration <- calibration_time`
- [ ] Log completion time

### 4. Update Summary Output
- [ ] Locate summary metrics section (line ~658)
- [ ] After "⏱️ TOTAL EXECUTION TIME" output
- [ ] Add conditional calibration time output:
  ```r
  if (!is.null(metrics$calibration_table_duration) &&
      metrics$calibration_table_duration > 0) {
    cat(paste("  • Calibration table:",
              round(metrics$calibration_table_duration, 1),
              "seconds"), "\n")
  }
  ```

### 5. Test Full Pipeline Run
- [ ] Run complete NE25 pipeline:
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
  ```
- [ ] Monitor console output for Step 11 execution
- [ ] Verify no errors during calibration table creation
- [ ] Check pipeline completes successfully

### 6. Verify Step 11 Execution
- [ ] Check console output shows:
  ```
  --- Step 11: Creating NE25 Calibration Table ---
  [1/7] Loading codebook from: codebook/data/codebook.json
  ...
  [7/7] Complete
  NE25 calibration table created successfully
  ```
- [ ] Verify timing: ~5-10 seconds
- [ ] Check no warning messages about failure

### 7. Validate Pipeline Metrics
- [ ] Check summary output includes:
  ```
  ⏱️ TOTAL EXECUTION TIME: X.X seconds
    • Calibration table: 7.2 seconds
  ```
- [ ] Verify `metrics$calibration_table_duration` > 0
- [ ] Confirm total duration increased by ~5-10 seconds

### 8. Verify Database Output
- [ ] Connect to database after pipeline run
- [ ] Query `ne25_calibration` table structure
- [ ] Verify 2,831 records
- [ ] Verify 27 columns
- [ ] Check table was created by pipeline (not manual run)

### 9. Test Pipeline Error Handling
- [ ] Temporarily rename codebook.json to trigger error
- [ ] Run pipeline
- [ ] Verify error is caught gracefully
- [ ] Confirm pipeline continues (doesn't crash)
- [ ] Restore codebook.json

### 10. Load Phase 3 Tasks
- [ ] **FINAL TASK:** Load `todo/ne25_calibration_phase3_combined_dataset.md` tasks into Claude todo list

---

## Validation Criteria

**Success:**
- ✅ Pipeline completes with Step 11 added
- ✅ Step 11 executes in 5-10 seconds
- ✅ `ne25_calibration` table created automatically
- ✅ Metrics include `calibration_table_duration`
- ✅ No errors or warnings in pipeline execution
- ✅ Error handling works (pipeline continues on failure)

**Failure conditions:**
- ❌ Pipeline crashes during Step 11
- ❌ Step 11 doesn't execute
- ❌ Calibration table not created
- ❌ Metrics missing calibration_table_duration

---

## Expected Pipeline Output

```
===========================================
   Kidsights NE25 Data Pipeline
===========================================
Start Time: 2025-11-10 10:15:32
Working Directory: C:/Users/marcu/git-repositories/Kidsights-Data-Platform

...
[Steps 1-10 execute]
...

--- Step 11: Creating NE25 Calibration Table ---

================================================================================
CREATE NE25 CALIBRATION TABLE
================================================================================

[1/7] Loading codebook from: codebook/data/codebook.json
      Loaded 24 calibration items from codebook

[2/7] Connecting to database: data/duckdb/kidsights_local.duckdb
      Verified ne25_transformed table exists

[3/7] Querying NE25 data with meets_inclusion filter
      Loaded 2,831 records (meets_inclusion=TRUE)

[4/7] Transforming data
      Final structure: 27 columns

[5/7] Writing to database
      Inserted 2,831 records with 27 columns

[6/7] Validating output
      Record count: 2,831 ✓
      Column count: 27 ✓

[7/7] Complete
      Table: ne25_calibration

================================================================================

NE25 calibration table created successfully
Calibration table creation completed in 7.2 seconds

===========================================
   Pipeline Execution Summary
===========================================
✅ STATUS: SUCCESS

📊 EXTRACTION METRICS:
  • Projects processed: 4
  • Total records extracted: 3908

🎯 PROCESSING METRICS:
  • Records processed: 3908
  • Eligible participants: 3507
  • Authentic participants: 2643
  • Included participants: 2831

⏱️ TOTAL EXECUTION TIME: 42.3 seconds
  • Calibration table: 7.2 seconds

🎉 Pipeline completed successfully!
```

---

## Code Changes Summary

**File:** `pipelines/orchestration/ne25_pipeline.R`

**Change 1:** Add metric (line ~122)
```r
calibration_table_duration = 0  # NEW LINE
```

**Change 2:** Add Step 11 (after line ~645)
```r
# STEP 11: CREATE NE25 CALIBRATION TABLE
message("\n--- Step 11: Creating NE25 Calibration Table ---")
calibration_start <- Sys.time()

source("scripts/irt_scoring/create_ne25_calibration_table.R")

tryCatch({
  create_ne25_calibration_table(
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    verbose = TRUE
  )
  message("NE25 calibration table created successfully")
}, error = function(e) {
  warning(paste("Calibration table creation failed:", e$message))
  message("Pipeline will continue, but calibration table is unavailable")
})

calibration_time <- as.numeric(Sys.time() - calibration_start)
metrics$calibration_table_duration <- calibration_time
message(paste("Calibration table creation completed in",
              round(calibration_time, 2), "seconds"))
```

**Change 3:** Update summary (after line ~658)
```r
if (!is.null(metrics$calibration_table_duration) &&
    metrics$calibration_table_duration > 0) {
  cat(paste("  • Calibration table:",
            round(metrics$calibration_table_duration, 1),
            "seconds"), "\n")
}
```

---

## Notes

- Step 11 is intentionally placed AFTER all data transformation and validation steps
- Uses tryCatch to prevent pipeline failure if calibration table creation fails
- Execution time adds ~5-10 seconds to pipeline (acceptable overhead)
- Table is recreated on every pipeline run (ensures freshness)
- Consistent with meets_inclusion filter used in imputation pipeline
