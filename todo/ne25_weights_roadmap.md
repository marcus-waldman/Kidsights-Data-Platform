# NE25 Weight Construction — Execution Roadmap

**Created:** 2026-04-20 | **Updated:** 2026-04-20 | **Status:** Buckets 1 and 2 complete; Bucket 3 (MIB bootstrap) deferred | **Repository:** Kidsights-Data-Platform

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

## Bucket 3 — Deferred

### 5. Bootstrap variance for raked weights — MIB framework (`WEIGHT_CONSTRUCTION.qmd §5.4`)

- **Effort:** L (~1–2 weeks engineering; ~3 h compute on 16 parallel workers, ~50 h serial)
- **Priority:** P2
- **Plan mode:** yes, but **not yet**.
- **Framework (decided April 2026):** **Multiple Imputation then Bootstrap (MIB).** For each of M = 5 imputations, refit weights against B = 200 distilled bootstrap-target draws → **1,000 total Stan refits**. Rubin's rules pool variance across imputations; bootstrap provides within-imputation variance.
- **Blocking dependency:** Bucket 2 (§5.1) must complete first — MIB needs the five harmonized datasets `ne25_harmonized_m{1..5}.feather` to exist.
- **What (sketch):**
  1. Distill 4,096 ACS target replicates → 200 representative draws, shared across all M.
  2. Refit loop over `(m, b) ∈ {1..5} × {1..200}` with cached Stan compilation.
  3. Store as `ne25_calibrated_weights_m{m}_boot.feather` (per-imputation N × 200 matrix; ~21 MB total).
  4. Document variance pooling via Rubin's rules on at least one analysis target.
- **Why MIB over alternatives:** fixed-imputation bootstrap silently drops imputation variance; random-pairing BtI is cheaper but harder to decompose. MIB is the rigorous option and transparent to downstream `survey`-package analysts.
- **Revisit:** after Bucket 2 is complete and stable for at least one analysis cycle.

---

## Suggested cadence

| When | Work | Status |
|------|------|------|
| Focused day in April 2026 | Bucket 1 items 1 → 2 → 3, in order. Single commit per item. | ✅ Complete |
| Planning session in April 2026 | Plan mode for Bucket 2 (§5.1). | ✅ Complete |
| Next 1–2 week window (optional) | Bucket 3 (§5.4) MIB bootstrap — large compute budget (~10 h) and architectural implications. | Deferred |
| Separate ticket | `model_fitting.R` gains `weights_table` argument for MI-aware analysis. | Not started |

## Out of scope (per `WEIGHT_CONSTRUCTION.qmd §5`)

- Reweighting to states other than Nebraska.
- Formal benchmarking of the estimator against `survey::rake` / `anesrake`.
- Bayesian posterior over weights.

---

*Detail on problem statements, rationale, and acceptance criteria lives in [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](../docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §5. This file is the execution-ordering companion.*
