# Authenticity Screening

**Purpose**: Identify and flag inauthentic or careless response patterns in developmental survey data using IRT-based influence diagnostics.

⚠️ **IMPORTANT**: This is a **MANUAL** workflow that requires researcher judgment at multiple decision points. It is **NOT** automated in the NE25 pipeline and must be run separately with careful inspection of results.

---

## Overview

This directory contains a **two-stage manual authenticity screening workflow**:

1. **Item-Level Influence Analysis** - Detect observations distorting item characteristic curves (ICCs)
2. **Person-Level Influence Analysis** - Detect observations distorting latent regression coefficients

Both stages use Cook's Distance and cross-validation to optimize removal cutoffs, but **require manual review** of diagnostic plots, coefficient stability, and out-of-sample predictive performance before making exclusion decisions.

---

## Why This Is Manual (Not Automated)

### Critical Researcher Decisions Required:

1. **Cutoff Selection**: No universal threshold for "high influence" - depends on:
   - Sample size and study design
   - Magnitude of coefficient changes
   - Trade-off between Type I and Type II errors
   - Research question sensitivity (e.g., policy vs exploratory)

2. **Diagnostic Interpretation**: Must visually inspect:
   - Coefficient stability plots (are effects stabilizing or oscillating?)
   - Out-of-sample log-likelihood trajectories (is predictive performance improving?)
   - Individual case profiles (do flagged persons have plausible response patterns?)

3. **Domain Expertise**: Statistical influence ≠ data quality
   - High-influence observations may represent **real** subpopulations (e.g., children with disabilities)
   - Removing legitimate variance reduces generalizability
   - Requires developmental psychology knowledge to distinguish careless vs authentic responses

4. **Reproducibility Documentation**: Every exclusion must be justified and documented
   - Which cutoff was chosen and why
   - How many observations were flagged
   - Sensitivity analyses comparing results with/without exclusions

**Bottom line**: This workflow provides **diagnostic tools**, not automatic decisions. The researcher is responsible for interpreting results and defending exclusions.

---

## Workflow

### Stage 1: Item-Level Influence (IRT Models)

**Goal**: Identify observations that distort item characteristic curves when modeling item responses as a function of latent factor scores.

**⚠️ MANUAL STEPS REQUIRED**:
- Run Mplus `.inp` files manually (scripts only generate syntax)
- Inspect Mplus convergence warnings and modification indices
- Review item characteristic curves visually before computing influence
- Select cutoff based on cross-validation plots and domain knowledge

**Key Scripts**:
- `scripts/authenticity_screening/manual_screening/00_load_item_response_data.R` - Load and prepare NE25 item response data
- `scripts/authenticity_screening/manual_screening/01-03_generate_model1[a-c]_syntax.R` - Generate Mplus syntax for bifactor IRT models
- `scripts/authenticity_screening/manual_screening/04_construct_iccs.R` - Extract item characteristic curves from Mplus output

**Key Functions** (`R/authenticity_screening/`):
- `compute_item_influence()` - Compute Cook's Distance for individual-item combinations (models: `item ~ f_dev + f_psych`)
- `optimize_influence_cutoff()` - Find optimal number of high-influence observations to remove via K-fold CV
- `entropy_normalized_kfold_cv()` - Cross-validation with entropy normalization for comparability across items

**Workflow**:
```r
# 1. Load data
source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")
out_list <- load_stage1_data()

# 2. Generate Mplus syntax (MANUAL: Review generated .inp files before running)
source("scripts/authenticity_screening/manual_screening/01_generate_model1a_syntax.R")
source("scripts/authenticity_screening/manual_screening/02_generate_model1b_syntax.R")
source("scripts/authenticity_screening/manual_screening/03_generate_model1c_syntax.R")

# 3. MANUAL: Run Mplus models (Model 1a → 1b → 1c → 1f)
#    - Open Mplus GUI
#    - Run each .inp file sequentially
#    - Check convergence and model fit indices
#    - Inspect modification indices for misspecifications

# 4. Compute item-level influence
fscores_df <- MplusAutomation::readModels("mplus/model_1f")$savedata %>%
  dplyr::rename_all(tolower)

influence_df <- compute_item_influence(
  fscores_df = fscores_df,
  item_list = c("eg30d", "eg30e", "aa56", ...),  # Items with @0 loadings or suspect patterns
  n_cores = 16
)

# 5. Optimize cutoff (provides recommendations, not automatic decisions)
cutoff_results <- optimize_influence_cutoff(
  fscores_df = fscores_df,
  influence_df = influence_df,
  item_list = all_items,
  max_k = 100,
  n_folds = 10
)

# 6. MANUAL: Inspect cutoff_results plot
#    - Look for elbow in mean_normalized_log_lik curve
#    - Check if removing more observations continues improving fit
#    - Consider diminishing returns vs sample size loss
plot(cutoff_results$k, cutoff_results$mean_normalized_log_lik, type = "b")

# 7. MANUAL: Select optimal k based on visual inspection + domain knowledge
optimal_k <- 42  # EXAMPLE ONLY - replace with your decision

# 8. Extract flagged observations
flagged_from_item_analysis <- influence_df %>%
  dplyr::arrange(desc(overall_influence)) %>%
  dplyr::slice(1:optimal_k)
```

---

### Stage 2: Person-Level Influence (Latent Regression)

**Goal**: Identify observations that distort regression coefficients when predicting latent factor scores from demographic/clinical covariates.

**⚠️ MANUAL STEPS REQUIRED**:
- Inspect coefficient stability plots (are effects stabilizing or erratic?)
- Compare Cook's D vs DFBETAS results (does parameter-specific influence matter?)
- Evaluate trade-offs between bias reduction and sample size loss
- Document exclusion criteria in research protocol

**Key Scripts**:
- `scripts/authenticity_screening/manual_screening/latent_regression_coefficients.R` - Main workflow for person-level influence analysis

**Key Functions** (`R/authenticity_screening/`):
- `optimize_person_cutoff()` - **Multivariate** (f_dev + f_psych) person-level cutoff optimization via LOOCV
- `optimize_person_cutoff_1d()` - **Univariate** (f_dev OR f_psych) person-level cutoff optimization via LOOCV
- `plot_coefficient_stability()` - Visualize coefficient changes as influential persons removed (multivariate)
- `plot_coefficient_stability_1d()` - Visualize coefficient changes (univariate)

**Influence Metrics**:
- **Cook's Distance** (default): Overall model influence across all parameters
- **DFBETAS** (via `target_params`): Parameter-specific influence (e.g., only MDD coefficients)

**Workflow**:
```r
# 1. Load and prepare data
source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")
source("R/utils/safe_joins.R")
out_list <- load_stage1_data()

# 2. MANUAL: Decide whether to exclude high-influence persons from Stage 1
#    - Review flagged_from_item_analysis from previous stage
#    - Inspect individual response patterns manually
#    - Decide on exclusion criteria (e.g., overall_influence > 5.5)
person_dat_imp <- out_list$person_data %>%
  dplyr::filter(!(pid == 7943 & recordid == 746)) %>%  # EXAMPLE exclusions
  dplyr::filter(!(pid == 7999 & recordid == 1171)) %>%
  mice::mice(method = "cart", m = 1, maxit = 5, printFlag = FALSE) %>%
  mice::complete(1)

# 3. Engineer predictors
person_dat_imp <- person_dat_imp %>%
  dplyr::mutate(
    college = as.integer(educ_a1 %in% c(
      "Bachelor's Degree (BA, BS, AB)",
      "Master's Degree (MA, MS, MSW, MBA)",
      "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)"
    )),
    logyrs = log(years + 1),
    yrs3 = years - 3,
    school = scale(school),  # Standardize continuous predictors
    logfpl = scale(log(fpl + 100)),
    phq2 = scale(phq2_total)
  )

# 4. Extract factor scores from Mplus Model 1f
fscores_df <- MplusAutomation::readModels("mplus/model_1f")$savedata %>%
  dplyr::rename_all(tolower)

person_dat_imp <- person_dat_imp %>%
  safe_left_join(
    fscores_df %>% dplyr::select(pid, recordid, f_dev, f_psych),
    by_vars = c("pid", "recordid")
  ) %>%
  na.omit()

# 5. Set up parallel cluster
cl <- parallel::makeCluster(8)

# 6. Run person-level cutoff optimization
# OPTION A: Multivariate (f_dev + f_psych simultaneously)
results <- optimize_person_cutoff(
  person_data = person_dat_imp,
  formula_rhs = "logyrs + female*yrs3 + school*yrs3 + logfpl*yrs3 + phq2*yrs3 + as.factor(pid)*yrs3",
  target_params = c("phq2", "yrs3:phq2"),  # Focus on depression effects (DFBETAS)
  max_k = 100,
  cl = cl,
  iterative_influence = TRUE,  # Recalculate influence at each k
  verbose = TRUE
)

# OPTION B: Univariate (f_dev only) - faster, simpler influence metric
results_1d <- optimize_person_cutoff_1d(
  person_data = person_dat_imp,
  outcome_var = "f_dev",
  formula_rhs = "logyrs + female*yrs3 + school*yrs3 + logfpl*yrs3 + phq2*yrs3 + as.factor(pid)*yrs3",
  target_params = c("phq2", "yrs3:phq2"),
  max_k = 100,
  cl = cl,
  iterative_influence = TRUE
)

parallel::stopCluster(cl)

# 7. MANUAL: Visualize coefficient stability
custom_groups <- list(
  top_left = c("female", "yrs3:female"),
  top_right = c("school", "yrs3:school"),
  bottom_left = c("logfpl", "yrs3:logfpl"),
  bottom_right = c("phq2", "yrs3:phq2")
)

custom_labels <- c(
  "Female × Age",
  "Education × Age",
  "Income (log FPL) × Age",
  "Depression (PHQ-2) × Age"
)

plots <- plot_coefficient_stability(
  results$coefficient_results,
  panel_groups = custom_groups,
  panel_labels = custom_labels
)

print(plots$plot_f_dev)
print(plots$plot_f_psych)

# 8. MANUAL: Inspect cutoff_results and decide on optimal k
#    Questions to ask:
#    - Are coefficients stabilizing or still changing at k=100?
#    - Is mean_log_lik improving or plateauing?
#    - Do coefficient changes align with theory (e.g., reduced attenuation bias)?
#    - How many observations are we willing to lose?
View(results$cutoff_results)
plot(results$cutoff_results$k, results$cutoff_results$mean_log_lik, type = "b")

# 9. MANUAL: Select optimal k (EXAMPLE ONLY)
optimal_k_person <- 25  # Replace with your decision

# 10. Extract flagged observations
ne25_flagged_observations <- results$cutoff_results %>%
  dplyr::filter(k <= optimal_k_person, k > 0) %>%
  dplyr::select(k, removed_pid, removed_record_id, overall_influence_cutoff) %>%
  dplyr::rename(pid = removed_pid, record_id = removed_record_id)

# 11. MANUAL: Document decision in research protocol
#     Include:
#     - Cutoff value chosen (k = ?)
#     - Justification (coefficient stability, predictive performance, theory)
#     - Sensitivity analyses planned (with vs without exclusions)
```

---

## Saving Flagged Observations

After **manually** selecting flagged observations, save them to the database and create backups:

```r
# 1. Save to DuckDB database
library(duckdb)
library(DBI)

db_path <- "data/duckdb/kidsights_local.duckdb"
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

DBI::dbWriteTable(
  conn = con,
  name = "ne25_flagged_observations",
  value = ne25_flagged_observations,
  overwrite = TRUE
)

cat(sprintf("[OK] Saved %d flagged observations to database\n",
            DBI::dbGetQuery(con, "SELECT COUNT(*) FROM ne25_flagged_observations")[[1]]))

DBI::dbDisconnect(con, shutdown = TRUE)

# 2. Save RDS backups
output_dir <- "output/ne25/authenticity_screening"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Timestamped backup
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
rds_path <- file.path(output_dir, sprintf("ne25_flagged_observations_%s.rds", timestamp))
saveRDS(ne25_flagged_observations, rds_path)

# Latest version (for easy recovery)
latest_path <- file.path(output_dir, "ne25_flagged_observations_latest.rds")
saveRDS(ne25_flagged_observations, latest_path)

# Optional: CSV for human inspection
csv_path <- file.path(output_dir, "ne25_flagged_observations_latest.csv")
write.csv(ne25_flagged_observations, csv_path, row.names = FALSE)

cat(sprintf("[OK] Backups saved:\n  - %s\n  - %s\n  - %s\n",
            rds_path, latest_path, csv_path))
```

---

## Key Parameters

### `optimize_person_cutoff()` / `optimize_person_cutoff_1d()`

| Parameter | Description | Default |
|-----------|-------------|---------|
| `target_params` | If NULL: Cook's D (overall influence)<br>If specified: DFBETAS for specific parameters (e.g., `c("mdd", "yrs3:mdd")`) | `NULL` |
| `iterative_influence` | TRUE: Recalculate influence at each k (forward stepwise)<br>FALSE: Compute once on full data (faster but less adaptive) | `TRUE` |
| `max_k` | Maximum number of persons to test removing | `50` |
| `cl` | Parallel cluster object from `parallel::makeCluster()` | Required |
| `verbose` | Print progress messages and target coefficient estimates | `TRUE` |

**When to use DFBETAS (`target_params`)**:
- Hypothesis-specific sensitivity analysis (e.g., only care about MDD effects)
- Parameter-specific influence detection (person may affect MDD but not education coefficients)
- Targeted diagnostics for key policy parameters

**When to use Cook's D (default)**:
- General model diagnostics
- Overall fit concerns
- No specific hypothesis to protect

### `optimize_influence_cutoff()` (Item-Level)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `n_folds` | Number of folds for K-fold cross-validation | `10` |
| `random_seed` | Random seed for reproducible fold assignments | `42` |
| `n_cores` | Number of cores for parallelization across items | `16` |

---

## Output Files

### Item-Level Analysis
- `influence_summary_by_individual.feather` - Aggregated influence scores per person
- `cutoff_optimization_results.feather` - K-fold CV results for k=0 to max_k

### Person-Level Analysis
- **Database Table**: `ne25_flagged_observations` (DuckDB)
- **RDS Backup**: `output/ne25/authenticity_screening/ne25_flagged_observations_latest.rds`
- **Timestamped Archive**: `output/ne25/authenticity_screening/ne25_flagged_observations_YYYYMMDD_HHMMSS.rds`
- **CSV Export** (optional): `output/ne25/authenticity_screening/ne25_flagged_observations_latest.csv`

---

## Integration with NE25 Pipeline

⚠️ **This is NOT automatic** - flagged observations must be manually reviewed and explicitly excluded in pipeline code.

**After** completing the manual authenticity screening workflow above:

```r
# In NE25 pipeline (Step 6.5 - Apply Authenticity Flags)
library(DBI)
library(duckdb)

# Load flagged observations from database
con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
flagged_obs <- DBI::dbGetQuery(con, "SELECT * FROM ne25_flagged_observations")
DBI::dbDisconnect(con, shutdown = TRUE)

# Join flags to main data
ne25_data <- ne25_data %>%
  dplyr::left_join(flagged_obs, by = c("pid", "record_id")) %>%
  dplyr::mutate(
    is_flagged = !is.na(overall_influence_cutoff),
    authenticity_weight = ifelse(is_flagged, 0, 1)  # Simple exclusion
  )

# ALTERNATIVE: Downweight instead of exclude
ne25_data <- ne25_data %>%
  dplyr::mutate(
    authenticity_weight = ifelse(is_flagged, 0.5, 1.0)  # 50% downweighting
  )
```

**Document in pipeline**:
- Number of flagged observations
- Exclusion criteria used (which k was selected)
- Impact on final sample size and demographic composition

---

## Decision Checklist

Before finalizing authenticity screening decisions, verify:

- [ ] **Convergence**: Mplus models converged without warnings
- [ ] **Stability**: Coefficient stability plots show stabilization (not oscillation) as k increases
- [ ] **Predictive Performance**: Out-of-sample log-likelihood improves or plateaus
- [ ] **Sample Size**: Remaining sample size is adequate for intended analyses
- [ ] **Representativeness**: Flagged observations don't disproportionately remove subgroups
- [ ] **Theory Alignment**: Coefficient changes align with theoretical expectations
- [ ] **Documentation**: Exclusion criteria documented in research protocol
- [ ] **Sensitivity Analyses**: Plan to report results with/without exclusions
- [ ] **Backup Created**: RDS and CSV backups saved before database insertion

---

## Historical Notes

### Known Issues (Fixed)
- **Item Reverse Coding**: Items EG39a, EG41_2, EG30d, EG30e, AA56, EG44_2 had improper reverse coding (fixed in `codebook.json`)
- **Identified High-Influence Persons** (NE25):
  - PID 7943, Record 746 (overall_influence = 6.2, extreme outlier in f_dev)
  - PID 7999, Record 1171 (overall_influence = 5.8, extreme outlier in f_psych)
  - **Decision**: Excluded from latent regression analyses after manual inspection revealed implausible response patterns

### Methods References
- **Cook's Distance**: Cook, R. D. (1977). Detection of influential observation in linear regression. *Technometrics*, 19(1), 15-18.
- **DFBETAS**: Belsley, D. A., Kuh, E., & Welsch, R. E. (1980). *Regression diagnostics*. Wiley.
- **Entropy Normalization**: Ensures log-likelihoods are comparable across items with different difficulties
- **LOOCV vs K-Fold**: LOOCV for person-level (more stable, smaller datasets), K-fold for item-level (faster, larger item space)

---

## Dependencies

**R Packages**:
- `MplusAutomation` - Read Mplus output files
- `MASS` - Ordinal regression (`polr`)
- `parallel`, `pbapply` - Parallelization with progress bars
- `mice` - Multiple imputation for missing covariates
- `ggplot2`, `dplyr`, `tidyr` - Data manipulation and visualization
- `DBI`, `duckdb` - Database connectivity

**External Software**:
- **Mplus 8.0+** (for Stage 1 IRT model estimation) - **Manual execution required**

---

## Frequently Asked Questions

### Q: Why isn't this automated in the pipeline?

**A**: Authenticity screening requires **substantive judgment** about:
1. What constitutes "high influence" (context-dependent)
2. Whether influence reflects data quality vs real variance
3. Trade-offs between bias reduction and sample size loss
4. Sensitivity to research question and policy implications

Automating these decisions would **hide critical assumptions** and reduce transparency.

### Q: What if I don't see clear stabilization in coefficient plots?

**A**: This suggests:
1. Influence is distributed continuously (no clear outlier cluster)
2. Model may be misspecified (check for omitted variables, non-linearity)
3. Sample size may be too small for reliable influence detection

**Recommendation**: Report results **without** exclusions and note influence diagnostics as limitations.

### Q: Should I use Cook's D or DFBETAS?

**A**:
- **Cook's D**: Use when concerned about overall model fit
- **DFBETAS**: Use when protecting specific hypotheses (e.g., only care about depression effects)

**Best practice**: Run both and compare. If they identify different persons, investigate why.

### Q: How do I recover flagged observations if database gets corrupted?

**A**:
```r
# Restore from latest RDS backup
ne25_flagged_observations <- readRDS("output/ne25/authenticity_screening/ne25_flagged_observations_latest.rds")

# Re-insert to database
con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = FALSE)
DBI::dbWriteTable(con, "ne25_flagged_observations", ne25_flagged_observations, overwrite = TRUE)
DBI::dbDisconnect(con, shutdown = TRUE)
```

---

## Contact

For questions about the authenticity screening workflow or interpretation of influence diagnostics, contact the Kidsights research team.

**Remember**: This workflow provides diagnostic tools, not automatic decisions. Always prioritize transparency and document your reasoning.
