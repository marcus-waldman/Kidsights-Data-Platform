# Bootstrap Configuration Fix: Single Source of Truth

**Date:** October 2025
**Issue:** Individual bootstrap files generated with n_boot=96 instead of n_boot=4096
**Status:** RESOLVED

---

## Problem Statement

When running the complete raking targets pipeline, individual bootstrap files were being generated with only 96 replicates instead of the configured 4,096 replicates. This caused consolidation scripts to fail with validation errors:

```
ERROR: Bootstrap files have n_boot = 96 but config expects 4096.
```

## Root Cause Analysis

The bootstrap design creation scripts (`01a_create_acs_bootstrap_design.R`, `12a_create_nhis_bootstrap_design.R`, `17a_create_nsch_bootstrap_design.R`) have fallback logic to handle standalone execution:

```r
if (!exists("n_boot")) {
  n_boot <- 96  # Default for standalone execution
  cat("[INFO] Using default n_boot = 96 (set via run_bootstrap_pipeline.R for production)\n\n")
}
```

When `run_complete_pipeline.R` called these scripts via `source()`, the `n_boot` variable didn't exist in the parent environment, so the scripts fell back to the default value of 96.

The downstream estimation scripts (`02_estimate_sex_glm2.R`, etc.) correctly read `n_boot` from the bootstrap design file:

```r
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
replicate_weights <- boot_design$repweights
n_boot <- ncol(replicate_weights)  # Reads 96 from the design file
```

So the entire chain was internally consistent, but used 96 replicates instead of 4,096.

## Solution

Modified `run_complete_pipeline.R` to source `bootstrap_config.R` at the top of the script and define `n_boot` globally before any bootstrap design creation scripts are sourced:

```r
# Source bootstrap configuration FIRST (single source of truth for n_boot)
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot
cat("\n[CONFIG] Bootstrap configuration loaded: n_boot =", n_boot, "\n")
```

This ensures that when the bootstrap design creation scripts check `if (!exists("n_boot"))`, the variable **will** exist with the correct value of 4,096 from `bootstrap_config.R`.

## Changes Made

### File: `scripts/raking/ne25/run_complete_pipeline.R`

**Before:**
```r
library(dplyr)

cat("\n========================================\n")
cat("COMPLETE NE25 Raking Targets Pipeline\n")
```

**After:**
```r
library(dplyr)

# Source bootstrap configuration FIRST (single source of truth for n_boot)
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot
cat("\n[CONFIG] Bootstrap configuration loaded: n_boot =", n_boot, "\n")

cat("\n========================================\n")
cat("COMPLETE NE25 Raking Targets Pipeline\n")
```

### No Changes Needed

- **`run_bootstrap_pipeline.R`**: Already sources `bootstrap_config.R` correctly (line 9)
- **`run_raking_targets_pipeline.R`**: Doesn't create bootstrap designs (assumes they exist)
- **Individual estimation scripts**: Correctly read from bootstrap design files
- **Consolidation scripts**: Already validate against `bootstrap_config.R`

## Verification

After the fix, running the complete pipeline will:

1. Load `bootstrap_config.R` with `n_boot = 4096`
2. Define `n_boot` globally before any `source()` calls
3. Bootstrap design creation scripts detect `exists("n_boot")` → TRUE
4. Bootstrap designs created with 4,096 replicates
5. All downstream estimation scripts read 4,096 from design files
6. Consolidation validation passes

**Expected output dimensions:**
- ACS bootstrap: 614,400 rows (25 estimands × 6 ages × 4,096 replicates)
- NHIS bootstrap: 49,152 rows (2 estimands × 6 ages × 4,096 replicates)
- NSCH bootstrap: 98,304 rows (4 estimands × 6 ages × 4,096 replicates)
- Total: 761,856 rows (31 estimands × 6 ages × 4,096 replicates)

## Testing Instructions

To verify the fix works correctly:

1. **Delete all existing bootstrap files:**
   ```powershell
   Remove-Item data\raking\ne25\*_bootstrap_design.rds
   Remove-Item data\raking\ne25\*_boot*.rds
   Remove-Item data\raking\ne25\*bootstrap_consolidated.rds
   Remove-Item data\raking\ne25\all_bootstrap_replicates.rds
   ```

2. **Run complete pipeline:**
   ```powershell
   .\scripts\raking\ne25\run_complete_pipeline_test.ps1
   ```

3. **Verify bootstrap design dimensions:**
   ```r
   # ACS bootstrap design
   acs_boot <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
   ncol(acs_boot$repweights)  # Should be 4096

   # NHIS bootstrap design
   nhis_boot <- readRDS("data/raking/ne25/nhis_bootstrap_design.rds")
   ncol(nhis_boot$repweights)  # Should be 4096

   # NSCH bootstrap design
   nsch_boot <- readRDS("data/raking/ne25/nsch_bootstrap_design.rds")
   ncol(nsch_boot$repweights)  # Should be 4096
   ```

4. **Verify consolidated replicates:**
   ```r
   all_boot <- readRDS("data/raking/ne25/all_bootstrap_replicates.rds")
   cat("Total rows:", nrow(all_boot), "\n")  # Should be 761,856
   cat("Unique replicates:", length(unique(all_boot$replicate)), "\n")  # Should be 4096
   ```

## Architecture Notes

### Why This Design Works

**R Variable Scoping:** When you `source()` a script in R, it executes in the parent environment by default. This means:
- Variables defined in the parent environment are accessible to the sourced script
- The sourced script can check `exists("variable_name")` to detect parent variables
- This enables the fallback pattern: production uses parent variable, standalone uses default

### Single Source of Truth Hierarchy

1. **`bootstrap_config.R`** - Ultimate source of truth for n_boot
2. **Pipeline orchestration scripts** - Read config and define n_boot globally
3. **Bootstrap design creation scripts** - Use parent n_boot or fall back to 96
4. **Estimation scripts** - Read n_boot from bootstrap design files
5. **Consolidation scripts** - Validate against config

This creates a consistent chain where configuration flows from config → pipeline → design → estimates → validation.

## Lessons Learned

1. **Global Configuration Early:** Pipeline orchestration scripts must source configuration files **before** any other scripts
2. **Variable Existence Checks:** The `exists()` pattern enables flexible standalone/production modes
3. **Validation at Consolidation:** Consolidation scripts act as gatekeepers to detect configuration mismatches
4. **Environment Scoping:** Understanding R's scoping rules is critical for pipeline design

---

**Updated:** October 2025
**Related:** `BOOTSTRAP_IMPLEMENTATION_PLAN.md`, `bootstrap_config.R`
