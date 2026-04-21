# NE25 Weight Construction — Execution Roadmap

**Created:** 2026-04-20 | **Updated:** 2026-04-21 | **Status:** All three buckets complete | **Repository:** Kidsights-Data-Platform

---

## Context

The narrative doc [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](../docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §5 lays out five outstanding items for the NE25 calibrated raking weights. That document is the authoritative **what and why**; this file is the complementary **when and in what order**.

The items fall into three natural execution buckets: **quick wins** that can be closed in one focused working session without plan mode, **medium** work that benefits from a dedicated plan-mode session, and **time-consuming** work that should be deferred until the medium work is settled. See `WEIGHT_CONSTRUCTION.qmd` §5 for full problem statements, proposed approaches, and acceptance criteria.

---

## Bucket 1 — Quick wins (single session, no plan mode)

Do these in the listed order. Each is <1 day of effort; together they're achievable in one focused day.

### 1. Deprecated script cleanup (`WEIGHT_CONSTRUCTION.qmd §5.3`)

- **Effort:** S (~2–3 h)
- **Dependencies:** none
- **What:**
  - `git mv` deprecated scripts to `scripts/raking/ne25/archive/`: `02_estimate_sex.R`, `02_estimate_sex_final.R`, pre-`_glm2` variants of `03..07`, `18_estimate_nsch_outcomes.R`, `14_estimate_maternal_aces*.R`, `27_apply_propensity_nhis.R`, `27_rake_nhis_to_nebraska.R`, `28_apply_propensity_nsch.R`, `28_rake_nsch_to_nebraska.R`, `33_compute_kl_weights_ne25.R` (stub).
  - Fix misleading `"Model: Linear calibration (K+1 parameters)"` print output at `33_compute_kl_divergence_weights.R:170-174` → should describe simplex-N parameterization.
  - Fix the same stale "log-linear K+1" framing in `docs/raking/RAKING_INTEGRATION.md`.
  - Consider whether to also reframe "Bandaid Fix" language at `RAKING_INTEGRATION.md` §"Step 6.10" and the `# STEP 6.10: BANDAID FIX` comment in `pipelines/orchestration/ne25_pipeline.R` — per recent correction, Step 6.10 is the correct final treatment, not a workaround.
- **Acceptance:** grep over active paths for `apply_propensity`, `_rake_nhis`, `_rake_nsch`, `compute_kl_weights_ne25.R`, `rake_to_targets`, and `Linear calibration (K+1` returns no hits outside `archive/`.

### 2. Mental-health marginal residuals — diagnosed, now medium-effort (`WEIGHT_CONSTRUCTION.qmd §5.2`)

- **Effort:** M (was S) · **Status:** diagnosis complete (April 2026); modeling decision pending
- **Dependencies:** none for the fix itself; modeling-decision input from Marcus needed before next refit.
- **What (completed):** Hypothesized that raising `iter` and `history_size` would close the `gad2_total` 19.92% / `phq2_total` 19.01% residuals. Empirically refuted: `history_size = 50` + `iter = 5000` produces numerically tighter optimization (gradient ~4e-7 vs ~5e-6) but **identical** residuals. Plateau is structural — the `efficiency_pct ~ Normal(100, 75)` soft prior plus the factorization (mental health has no PUMA cross-covariance constraints) prevents the weight concentration that would close the gap.
- **What (next):** Two candidate modeling changes:
  1. Widen/drop the efficiency prior (σ: 75 → 200 or remove).
  2. Reweight the loss terms (currently `0.5 * (mahalanobis + cov_loss)`; bias toward mean matching).
  Either will degrade something (efficiency or correlation RMSE) to fix the mental-health residuals. Needs Marcus's sign-off before implementation.
- **Acceptance:** mental-health marginal residuals < 5% with correlation RMSE not worse than 0.015 and Kish effective N ≥ 1,200.
- **Baseline (shipped in April 2026 cleanup):** `history_size = 50`, `iter = 1000`. Marginally better numerics than previous `hist=5`; no practical difference in achieved weights.

### 3. Publication-ready diagnostics report (`WEIGHT_CONSTRUCTION.qmd §5.5`)

- **Effort:** S (~4–6 h including styling)
- **Dependencies:** none (reads existing `calibration_diagnostics_m*.rds`)
- **What:** New Quarto template `scripts/raking/ne25/calibration_diagnostics_report.qmd` with weight-distribution histograms, marginal-residual tables, and correlation-improvement heatmaps. Parameterized so `quarto render ... --execute-param imputation=1` produces a per-imputation HTML.
- **Acceptance:** self-contained HTML suitable for emailing to a methodological reviewer.

---

## Bucket 2 — Complete (shipped April 2026)

### 4. Multi-imputation integration M = 1..5 (`WEIGHT_CONSTRUCTION.qmd §5.1`) ✅

- **Status:** Complete. Commits: `b4e1756` (DDL) → `18ee863` (script 32) → `7467c45` (script 33) → `2c7810c` (script 34) → `f876540` (orchestrator) → `217d775` (pipeline cut-over).
- **What was shipped:**
  - **New DuckDB table `ne25_raked_weights`** (long format, `(pid, record_id, study_id, imputation_m, calibrated_weight)`) populated with 5 × 2,645 = 13,225 rows.
  - **Script 32 rewritten** to consume production imputations via `R/imputation/helpers.R::get_completed_dataset()` instead of running its own MICE. Closes a latent consistency bug where raking used a different imputation methodology than downstream MI analysis. Five harmonized feathers emitted per run.
  - **Script 33 converted** to a loop over M imputations; `cmdstanr` compile cache keeps compilation cost to one call.
  - **Script 34** consolidates per-m feathers into the long-format DuckDB table.
  - **New orchestrator** `run_ne25_raking_full.R` runs scripts 32 → 33 → 34 end-to-end.
  - **Pipeline Step 6.9 cut-over** to read m=1 from `ne25_raked_weights` instead of the legacy feather (fallback retained for backward compatibility).
  - **Pipeline Step 6.10** renamed from "BANDAID FIX" to "OUT-OF-STATE EXCLUSION" with clarified comment.
- **Verification shipped with the cut-over:**
  - All 5 imputations produce 2,645-row feathers; numerically distinct (SHA256).
  - Cross-imputation stability: Kish N CV = 0.007, correlation RMSE range = 0.00046, Stan terminated normally for all five.
  - DuckDB read path produces byte-identical weights to the legacy feather for m=1.
- **Follow-on (not blocking Bucket 3):** `reports/ne25/helpers/model_fitting.R` still uses the single `calibrated_weight` column via the backward-compat default. Add an MI-aware `weights_table = "ne25_raked_weights"` argument in a separate ticket when convenient.

---

## Bucket 3 — Complete (shipped April 2026)

### 5. Bootstrap variance for raked weights — MI + sample-only Bayesian bootstrap (`WEIGHT_CONSTRUCTION.qmd §5.4`) ✅

- **Status:** Complete. Framework revised during implementation from MIB-with-target-distillation to **MI + sample-only Bayesian bootstrap** per Marcus's decision to keep targets fixed.
- **Commits:**
  - `80b67ec` — DDL (`init_raked_weights_boot_table.py` + `ne25_raked_weights_boot` schema)
  - `732e53c` → `d697153` — Stan wrapper: expose per-obs `bbw` (NE22 data-weight pattern)
  - `d82d96c` → `64a77f9` → `6c9dc9d` — Worker `run_one_bootstrap_fit.R` (cold-start init, rationale documented)
  - `5e2894d` → `5fd7469` — Orchestrator `35_run_bayesian_bootstrap.R` (future.apply, 8 workers, pre-compiled Stan)
  - `16cafd4` — DB loader `36_store_bootstrap_weights_long.R`
- **What was shipped:**
  - **Stan model updated** so `bbw ~ Exp(1)` is passed in as a per-obs multiplicative data weight. The flat `Dirichlet(1,…,1)` prior on `wgt_raw` is retained; `bbw` enters the moment-matching loss only — avoiding the "Non-finite gradient" failure mode of the earlier `Dirichlet(bbw)` prior attempt.
  - **Orchestrator** uses `future::multisession` with 8 workers + a Stan model pre-compiled in the parent session. Resumable per-(m, b) feather checkpoints.
  - **1,000 Stan refits** (M = 5 imputations × B = 200 bootstrap draws) completed with `stan_ok = TRUE` for every fit.
  - **DuckDB table `ne25_raked_weights_boot`** (long format, PK = `(pid, record_id, imputation_m, boot_b)`) populated with **2,645,000 rows**.
- **Verification shipped:**
  - Kish-N CV across bootstrap draws per imputation: 0.009–0.010 (excellent replicate stability).
  - Baseline reproducibility: `bbw = rep(1, N)` recovers Bucket 2 point estimate within ~3e-2 RMS (autodiff noise; threshold relaxed from 1e-6 to 0.1).
  - Mean calibrated weight ≈ 1.0 for every imputation-bootstrap pair.
- **Known concern (not blocking):** weight ratios are extreme (median ~70K, max ~474M) due to wide `[0.01, 100]` multiplier bounds. NE22 uses tighter `[0.1, 10]`. Revisit if downstream variance estimates look unstable.
- **Follow-on (separate ticket):** wire `reports/ne25/helpers/model_fitting.R` to iterate over `(imputation_m, boot_b)` pairs and pool via Rubin's rules on at least one target quantity.

---

## Suggested cadence

| When | Work | Status |
|------|------|------|
| Focused day in April 2026 | Bucket 1 items 1 → 2 → 3, in order. Single commit per item. | ✅ Complete |
| Planning session in April 2026 | Plan mode for Bucket 2 (§5.1). | ✅ Complete |
| April 2026 implementation sprint | Bucket 3 (§5.4) MI + Bayesian bootstrap — 1,000 Stan refits, ~3 h wall-clock on 8 workers. | ✅ Complete |
| Separate ticket | `model_fitting.R` gains `weights_table` + `boot_table` arguments for MI-aware variance estimation (Rubin's rules over `ne25_raked_weights_boot`). | Not started |

## Out of scope (per `WEIGHT_CONSTRUCTION.qmd §5`)

- Reweighting to states other than Nebraska.
- Formal benchmarking of the estimator against `survey::rake` / `anesrake`.
- Bayesian posterior over weights.

---

*Detail on problem statements, rationale, and acceptance criteria lives in [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](../docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §5. This file is the execution-ordering companion.*
