# NE25 Weight Construction — Execution Roadmap

**Created:** 2026-04-20 | **Updated:** 2026-04-20 | **Status:** Not started | **Repository:** Kidsights-Data-Platform

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

## Bucket 2 — Medium (dedicated plan-mode session)

### 4. Multi-imputation integration M = 2..5 (`WEIGHT_CONSTRUCTION.qmd §5.1`)

- **Effort:** M (~2–3 days of engineering)
- **Priority:** P0
- **Plan mode:** **yes** — coordinated edits across scripts 32, 33, and pipeline Step 6.9; needs a design decision on whether to finish the existing stub `33_compute_kl_weights_ne25.R` or replace it.
- **What (high level):**
  - Script 32 loops MICE CART imputation m = 1..5, emitting `ne25_harmonized_m{1..5}.feather`.
  - Script 33 (or its successor) orchestrates per-imputation Stan optimization, reusing the compiled model across imputations.
  - Pipeline Step 6.9 joins per-imputation weights by `(pid, record_id, imputation_m)`.
  - Validation: Kish N and correlation RMSE stable across the five imputations.
- **Dependencies:** Bucket 1 complete is nice-to-have (cleaner codebase) but not strictly required.
- **Acceptance:** Five calibrated-weight feather files exist; diagnostics comparable across imputations; pipeline integration tests pass.

---

## Bucket 3 — Deferred

### 5. Bootstrap variance for raked weights (`WEIGHT_CONSTRUCTION.qmd §5.4`)

- **Effort:** L (~1–2 weeks part-time, incl. ~10+ hours of Stan compute)
- **Priority:** P2
- **Plan mode:** yes, but **not yet**.
- **Blocking dependency:** Bucket 2 (§5.1) must settle multi-imputation join patterns first — otherwise the bootstrap weight matrix will have to be refactored once the imputation structure lands.
- **What (sketch):** Distill 4,096 ACS target replicates to ~200 representative draws; refit weights per draw; store per-observation bootstrap weight matrix; integrate with downstream `survey` workflow.
- **Revisit:** after Bucket 2 is complete and stable for at least one analysis cycle.

---

## Suggested cadence

| When | Work |
|------|------|
| Next focused day | Bucket 1 items 1 → 2 → 3, in order. Single commit per item. |
| Next scheduled planning session | Enter plan mode for Bucket 2 (§5.1). |
| After §5.1 ships and is validated | Consider scheduling Bucket 3 (§5.4). |

## Out of scope (per `WEIGHT_CONSTRUCTION.qmd §5`)

- Reweighting to states other than Nebraska.
- Formal benchmarking of the estimator against `survey::rake` / `anesrake`.
- Bayesian posterior over weights.

---

*Detail on problem statements, rationale, and acceptance criteria lives in [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](../docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §5. This file is the execution-ordering companion.*
