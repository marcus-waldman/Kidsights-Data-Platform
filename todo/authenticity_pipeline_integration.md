# Authenticity Screening Pipeline Integration

**Goal:** Integrate authenticity screening into NE25 pipeline as Step 6.5

**Strategy:**
- Use **cached LOOCV distribution** (2,635 authentic, Phase 3 results)
- Re-compute **avg_logpost for inauthentic** each pipeline run (~30 sec)
- Assign **normalized weights**: Authentic = 1.0, Inauthentic = 0.42-1.96
- Add **4 columns** to `ne25_transformed`: authenticity_weight, lz, avg_logpost, quintile

---

## Phase 1: Create Pipeline-Optimized Weighting Function

**Objective:** Build efficient weighting script that uses cached LOOCV

- [ ] **Task 1.1:** Git commit current state (message: "Complete Phase 3: LOOCV weights computed")
- [ ] **Task 1.2:** Add N_CORES configuration to `.env.template`
  - Add optional N_CORES setting with documentation
  - Default: Half of available cores for safety (e.g., 8 on 16-core machine)
  - Example: `# N_CORES=8`
- [ ] **Task 1.3:** Create `scripts/authenticity_screening/08_compute_pipeline_weights.R`
  - Function signature: `compute_authenticity_weights(data, rebuild_loocv = FALSE, cache_dir = "results/")`
  - **Cores configuration:** `n_cores <- as.integer(Sys.getenv("N_CORES", floor(parallel::detectCores() / 2)))`
  - Load cached LOOCV results from `results/loocv_authentic_results.rds`
  - Extract distribution parameters: mean_authentic, sd_authentic, quintile_breaks
  - Filter inauthentic: `!authentic & n_items >= 5` (where n_items = count of non-NA item responses)
  - Compute avg_logpost for inauthentic using holdout Stan model
  - Assign weights: Authentic = 1.0, Inauthentic = quintile-based normalized (sum to N_inauthentic)
  - Return data with 4 new columns: authenticity_weight, authenticity_lz, authenticity_avg_logpost, authenticity_quintile
- [ ] **Task 1.4:** Test script with existing `ne25_transformed` data
  - Load `ne25_transformed` from database
  - Run `compute_authenticity_weights(data, rebuild_loocv = FALSE)`
  - Verify: Authentic all = 1.0, Inauthentic sum = 196, quintiles match Phase 3
  - Expected runtime: ~30 seconds
- [ ] **Task 1.5:** Test LOOCV rebuild flag
  - Run `compute_authenticity_weights(data, rebuild_loocv = TRUE)`
  - Verify: Re-runs LOOCV (~7 min), produces same weights
- [ ] **Task 1.6:** Git commit Phase 1 (message: "Add pipeline-optimized authenticity weighting function with cores config")
- [ ] **Task 1.7:** Load Phase 2 tasks from this file

---

## Phase 2: Integrate into NE25 Pipeline

**Objective:** Add Step 6.5 to pipeline orchestration

- [ ] **Task 2.1:** Modify `pipelines/orchestration/ne25_pipeline.R`
  - Insert Step 6.5 after line 431 (after eligibility validation, before database storage)
  - Source `scripts/authenticity_screening/08_compute_pipeline_weights.R`
  - Check global option: `rebuild_loocv <- getOption("ne25.rebuild_loocv", FALSE)`
  - Call `compute_authenticity_weights(final_data, rebuild_loocv, "results/")`
  - **Create `meets_inclusion` column:** `final_data$meets_inclusion <- (final_data$eligible == TRUE & !is.na(final_data$authenticity_weight))`
  - Cache result: `saveRDS(final_data, "temp/pipeline_cache/step6.5_authenticity_weights.rds")`
  - Add logging: print number of participants weighted and number meeting inclusion criteria
- [ ] **Task 2.2:** Update pipeline header comment
  - Add Step 6.5 to pipeline overview comment block
  - Document rebuild_loocv option usage
- [ ] **Task 2.3:** Test pipeline with cached LOOCV (dry run, no database write)
  - Comment out database write steps temporarily
  - Run pipeline: `source("pipelines/orchestration/ne25_pipeline.R")`
  - Verify: Step 6.5 runs, adds 4 columns, ~30 second overhead
  - Check cache file: `temp/pipeline_cache/step6.5_authenticity_weights.rds` exists
- [ ] **Task 2.4:** Test pipeline with LOOCV rebuild (optional validation)
  - Run: `options(ne25.rebuild_loocv = TRUE); source("pipelines/orchestration/ne25_pipeline.R")`
  - Verify: LOOCV re-runs (~7 min), weights match Phase 3
- [ ] **Task 2.5:** Git commit Phase 2 (message: "Integrate authenticity screening as pipeline Step 6.5")
- [ ] **Task 2.6:** Load Phase 3 tasks from this file

---

## Phase 3: Database Schema & Storage

**Objective:** Add authenticity columns to `ne25_transformed` table

- [ ] **Task 3.1:** Add columns to `ne25_transformed` table schema
  - **Option A (SQL migration):** Create migration script `migrations/add_authenticity_columns.sql`
  - **Option B (Python migration):** Update `python/db/schema.py` with ALTER TABLE statements
  - Columns to add:
    - `authenticity_weight DOUBLE DEFAULT 1.0`
    - `authenticity_lz DOUBLE`
    - `authenticity_avg_logpost DOUBLE`
    - `authenticity_quintile INTEGER`
    - `meets_inclusion BOOLEAN DEFAULT FALSE`
  - Create index: `CREATE INDEX idx_ne25_authenticity_weight ON ne25_transformed(authenticity_weight)`
  - Create index: `CREATE INDEX idx_ne25_meets_inclusion ON ne25_transformed(meets_inclusion)`
- [ ] **Task 3.2:** Run database migration
  - Execute migration script
  - Verify columns exist: `PRAGMA table_info(ne25_transformed)`
- [ ] **Task 3.3:** Test pipeline with database storage (full run)
  - Uncomment database write steps in pipeline
  - Run full pipeline: `source("pipelines/orchestration/ne25_pipeline.R")`
  - Verify: `ne25_transformed` table contains 4 new columns with expected values
- [ ] **Task 3.4:** Validate database results
  - Query: `SELECT COUNT(*) FROM ne25_transformed WHERE authenticity_weight = 1.0` → should equal N_authentic
  - Query: `SELECT SUM(authenticity_weight) FROM ne25_transformed WHERE authenticity_weight != 1.0` → should equal N_inauthentic
  - Query: `SELECT MIN(authenticity_weight), MAX(authenticity_weight) FROM ne25_transformed` → should be [0.42, 1.96]
  - Query: `SELECT COUNT(*) FROM ne25_transformed WHERE meets_inclusion = TRUE` → should equal N_eligible with weights
- [ ] **Task 3.5:** Update imputation configuration to use `meets_inclusion`
  - File: `config/imputation/imputation_config.yaml`
  - Change `eligible_only: true` to `meets_inclusion_only: true` (or keep both for backward compat)
  - Update auxiliary variables comment: change `authentic` → `meets_inclusion`
- [ ] **Task 3.6:** Update imputation scripts to filter on `meets_inclusion`
  - File: `scripts/imputation/ne25/02_impute_sociodemographic.R`
    - Change line 133: `WHERE eligible = TRUE` → `WHERE meets_inclusion = TRUE`
  - File: `scripts/imputation/ne25/05_impute_adult_mental_health.R`
    - Change line 150: `WHERE "eligible.x" = TRUE AND "authentic.x" = TRUE` → `WHERE "meets_inclusion.x" = TRUE`
    - Change line 288, 319: Similar updates to WHERE clauses
  - Update all other imputation scripts similarly (childcare, child ACEs, geography)
- [ ] **Task 3.7:** Test imputation pipeline with new `meets_inclusion` filter
  - Run: `"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/02_impute_sociodemographic.R`
  - Verify: Filters to eligible participants with non-NA `authenticity_weight`
  - Expected: Should include authentic (2,633) + inauthentic with 5+ items (196) = 2,829 participants
- [ ] **Task 3.8:** Git commit Phase 3 (message: "Add meets_inclusion column and update imputation filters")
- [ ] **Task 3.9:** Load Phase 4 tasks from this file

---

## Phase 4: Documentation & Finalization

**Objective:** Document integration and usage

- [ ] **Task 4.1:** Update `CLAUDE.md`
  - Add Step 6.5 to "NE25 Pipeline" section
  - Document N_CORES configuration in `.env.template` section
  - Document `rebuild_loocv` option:
    ```r
    # Normal run (cached LOOCV, ~30 sec overhead)
    source("pipelines/orchestration/ne25_pipeline.R")

    # Force LOOCV rebuild (~7 min overhead)
    options(ne25.rebuild_loocv = TRUE)
    source("pipelines/orchestration/ne25_pipeline.R")
    ```
  - Add "Using Authenticity Weights" section with R examples (weighted.mean, survey package)
  - Document `meets_inclusion` column and its usage in imputation pipeline
- [ ] **Task 4.2:** Update data dictionary
  - File: `docs/data_dictionary/ne25_data_dictionary_full.md`
  - Add 5 new columns with descriptions:
    - `authenticity_weight`: Normalized weight for analyses (1.0 for authentic, 0.42-1.96 for inauthentic)
    - `authenticity_lz`: Standardized score (z-score of avg_logpost)
    - `authenticity_avg_logpost`: Raw metric (log_posterior / n_items)
    - `authenticity_quintile`: Quintile assignment (1-5, based on authentic distribution)
    - `meets_inclusion`: Inclusion flag (eligible=TRUE & !is.na(authenticity_weight), used for imputation filtering)
- [ ] **Task 4.3:** Update `docs/authenticity_screening/authenticity_screening_results.md`
  - Add "Pipeline Integration" section
  - Document Step 6.5 location in pipeline
  - Add performance benchmarks (cached: 30 sec, rebuild: 7 min)
  - Link to usage examples in CLAUDE.md
- [ ] **Task 4.4:** Create usage example script
  - File: `scripts/examples/authenticity_weights_examples.R`
  - Example 1: Weighted descriptive statistics
  - Example 2: Weighted regression with survey package
  - Example 3: Sensitivity analysis (weighted vs unweighted)
  - Example 4: Exclude vs weight comparison
- [ ] **Task 4.5:** Final validation
  - Run full pipeline end-to-end
  - Verify all 4 columns present in database
  - Spot-check 10 participants: weights match Phase 3 results
  - Check pipeline runtime: cached run adds ~30 sec
- [ ] **Task 4.6:** Git commit Phase 4 (message: "Document authenticity screening pipeline integration")
- [ ] **Task 4.7:** Close GitHub issue (if applicable) or create completion summary

---

## Implementation Notes

**Cores Configuration:**
- Default: `floor(parallel::detectCores() / 2)` for safety (8 cores on 16-core machine)
- Override: Set `N_CORES=16` in `.env` file to use more cores
- Example: 16-core machine uses 8 cores by default, leaving headroom for multi-tasking

**Inclusion Criteria (`meets_inclusion`):**
- Definition: `meets_inclusion = (eligible == TRUE & !is.na(authenticity_weight))`
- **Includes:**
  - All authentic participants: eligible=TRUE, authenticity_weight=1.0 (N=2,633)
  - Inauthentic with 5+ items: eligible=TRUE, authenticity_weight=0.42-1.96 (N=196)
- **Excludes:**
  - Ineligible participants: eligible=FALSE (N=448)
  - Inauthentic with <5 items: eligible=TRUE, authenticity_weight=NA (N=676)
- **Total meeting inclusion:** 2,829 participants (was 2,633 with `eligible & authentic` filter)

**Cache Invalidation Strategy:**
- Default: Always use cached LOOCV (Phase 3 results are final)
- Manual override: Set `options(ne25.rebuild_loocv = TRUE)` before running pipeline
- Cache location: `results/loocv_*.rds` files

**Performance Expectations:**
- **Cached run:** ~30 seconds overhead (load cache + score inauthentic)
- **Rebuild run:** ~7 minutes overhead (re-run LOOCV + score inauthentic)
- **Cores:** Default to half of available (safe), override with N_CORES env var

**Weight Interpretation:**
- `authenticity_weight = 1.0`: Authentic participant (full weight)
- `authenticity_weight = 0.42`: Inauthentic in Q1 (lowest avg_logpost, down-weighted)
- `authenticity_weight = 1.96`: Inauthentic in Q3 (highest avg_logpost among inauthentic, up-weighted)
- Sum of inauthentic weights = N_inauthentic (196) by design

**Files Created:**
1. `scripts/authenticity_screening/08_compute_pipeline_weights.R` (Phase 1)
2. `migrations/add_authenticity_columns.sql` (Phase 3, if using SQL migration)
3. `scripts/examples/authenticity_weights_examples.R` (Phase 4)

**Files Modified:**
1. `.env.template` (Phase 1 - add N_CORES configuration)
2. `pipelines/orchestration/ne25_pipeline.R` (Phase 2 - add Step 6.5 + meets_inclusion)
3. `config/imputation/imputation_config.yaml` (Phase 3 - add meets_inclusion_only filter)
4. `scripts/imputation/ne25/02_impute_sociodemographic.R` (Phase 3 - update WHERE clause)
5. `scripts/imputation/ne25/05_impute_adult_mental_health.R` (Phase 3 - update WHERE clauses)
6. `scripts/imputation/ne25/03a_impute_cc_receives_care.R` (Phase 3 - update WHERE clause)
7. `scripts/imputation/ne25/03b_impute_cc_type_hours.R` (Phase 3 - update WHERE clause)
8. `scripts/imputation/ne25/06_impute_child_aces.R` (Phase 3 - update WHERE clause)
9. `CLAUDE.md` (Phase 4)
10. `docs/data_dictionary/ne25_data_dictionary_full.md` (Phase 4)
11. `docs/authenticity_screening/authenticity_screening_results.md` (Phase 4)

**Total Estimated Time:**
- Phase 1: 1-2 hours (script creation + cores config + testing)
- Phase 2: 30-45 minutes (pipeline integration + meets_inclusion column)
- Phase 3: 1-1.5 hours (database schema + imputation pipeline updates + testing)
- Phase 4: 1 hour (documentation)
- **Total: 3.5-5 hours**
