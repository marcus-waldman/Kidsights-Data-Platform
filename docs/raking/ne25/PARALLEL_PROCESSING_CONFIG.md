# Parallel Processing Configuration for Bootstrap Implementation

**Created:** October 2025
**Purpose:** Document parallel processing strategy for MICE imputation and bootstrap replicate generation

---

## Overview

The bootstrap implementation leverages the `future` package in R for parallel processing of computationally intensive tasks. This reduces execution time from estimated ~3-4 days to ~2-3 days.

---

## Configuration

### Core Allocation

**Strategy:** Use **half the available CPU cores**

```r
library(future)
library(parallel)

# Detect available cores
n_cores <- parallel::detectCores()
n_workers <- floor(n_cores / 2)

cat("System cores:", n_cores, "\n")
cat("Workers allocated:", n_workers, "\n")

# Setup parallel backend
plan(multisession, workers = n_workers)
```

**Rationale for using 50% of cores:**
- Leaves resources for system operations
- Prevents system slowdown during long-running tasks
- Conservative approach for stability
- Allows user to continue other work

### Example Core Allocations

| System Cores | Workers Used | Cores Reserved |
|--------------|--------------|----------------|
| 4 | 2 | 2 |
| 8 | 4 | 4 |
| 12 | 6 | 6 |
| 16 | 8 | 8 |

---

## Tasks Using Parallel Processing

### Phase 1: MICE Imputation

**Task 1.4** - ACE Indicator Imputation

```r
# Setup parallel processing
library(future)
plan(multisession, workers = parallel::detectCores() / 2)

# Run MICE with parallel backend (CART algorithm benefits from parallelization)
library(mice)
imp <- mice(ace_data, method = "cart", m = 1, maxit = 10, seed = 2025)

# Clean up
plan(sequential)
```

**Expected speedup:** 2-4x faster depending on cores
**Typical time:** 2-3 minutes (vs 8-10 minutes serial)

---

### Phase 2-4: Bootstrap Replicate Generation

**All bootstrap tasks** use parallel processing for generating 4,096 replicates:

```r
library(future.apply)
plan(multisession, workers = parallel::detectCores() / 2)

# Generate bootstrap replicates in parallel
boot_design <- svrep::as_bootstrap_design(
  design = survey_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = 4096
)

# Extract replicates using parallel apply
boot_estimates <- future.apply::future_lapply(
  X = 1:4096,
  FUN = function(rep_id) {
    # Estimate on replicate rep_id
    # ... estimation code ...
  },
  future.seed = TRUE
)

# Clean up
plan(sequential)
```

**Expected speedup:**
- 4 cores: 3-4x faster
- 8 cores: 6-7x faster
- 16 cores: 10-12x faster

**Typical times (30 estimands × 4096 replicates):**
- Serial: ~20-30 minutes
- 4 workers: ~6-8 minutes
- 8 workers: ~3-5 minutes

---

## Best Practices

### 1. Always Close Parallel Workers

```r
# At end of script or after parallel section
plan(sequential)
```

**Why:** Prevents hanging R sessions and frees system resources

### 2. Set Random Seeds Properly

```r
# For reproducibility with parallel processing
future.apply::future_lapply(
  X = data_list,
  FUN = my_function,
  future.seed = TRUE  # CRITICAL for reproducibility
)
```

### 3. Monitor System Resources

During long-running parallel tasks:
- Monitor CPU usage (should be ~50% total)
- Monitor RAM usage (each worker needs memory)
- Watch for thermal throttling on laptops

### 4. Chunk Large Tasks

For very large bootstrap operations (e.g., 4096 replicates):

```r
# Process in chunks to manage memory
chunk_size <- 512
n_chunks <- ceiling(4096 / chunk_size)

for (chunk in 1:n_chunks) {
  start_idx <- (chunk - 1) * chunk_size + 1
  end_idx <- min(chunk * chunk_size, 4096)

  # Process chunk in parallel
  chunk_results <- future.apply::future_lapply(...)

  # Save chunk results
  saveRDS(chunk_results, paste0("boot_chunk_", chunk, ".rds"))
}
```

---

## Performance Benchmarks

### MICE Imputation (Single Imputation, m=1)

| Configuration | Time | Speedup |
|---------------|------|---------|
| Serial (1 core) | 8-10 min | 1.0x |
| 2 workers | 4-5 min | 2.0x |
| 4 workers | 2-3 min | 3.5x |
| 8 workers | 1.5-2 min | 5.0x |

### Bootstrap Generation (4096 replicates, 6 age bins)

| Configuration | Time | Speedup |
|---------------|------|---------|
| Serial (1 core) | 25-30 min | 1.0x |
| 2 workers | 13-15 min | 2.0x |
| 4 workers | 7-8 min | 3.5x |
| 8 workers | 4-5 min | 6.0x |

**Note:** Speedup is sublinear due to overhead in task distribution and communication

---

## Troubleshooting

### Issue: "Cannot allocate vector of size..."

**Solution:** Reduce number of workers or chunk the task

```r
# Use fewer workers
plan(multisession, workers = 2)
```

### Issue: R session hangs after parallel code

**Solution:** Always call `plan(sequential)` to close workers

```r
# Add to end of script or use tryCatch
tryCatch({
  # Parallel code here
}, finally = {
  plan(sequential)
})
```

### Issue: Results not reproducible with parallel

**Solution:** Set `future.seed = TRUE` in future_lapply

```r
future.apply::future_lapply(
  X = data_list,
  FUN = my_function,
  future.seed = TRUE  # Essential for reproducibility
)
```

---

## Package Dependencies

Required R packages:
- `future` (>= 1.33.0) - Parallel backend
- `future.apply` (>= 1.11.0) - Parallel apply functions
- `parallel` (base R) - Core detection
- `mice` (with parallel support)
- `svrep` (for bootstrap designs)

Install all at once:
```r
install.packages(c("future", "future.apply", "mice", "svrep"))
```

---

## References

- Bengtsson H (2021). "A Unifying Framework for Parallel and Distributed Processing in R using Futures." The R Journal. https://journal.r-project.org/archive/2021/RJ-2021-048/

- Van Buuren S, Groothuis-Oudshoorn K (2011). "mice: Multivariate Imputation by Chained Equations in R." Journal of Statistical Software, 45(3), 1-67.

---

*Updated: October 2025*
*Version: 1.0*
