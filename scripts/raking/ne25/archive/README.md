# Archived NE25 Raking Scripts

Scripts in this directory are **not part of the production pipeline**. They are kept for historical reference and diff-ability during refactors. Do not source or call any of these files from active code.

For the production pipeline, see `scripts/raking/ne25/run_raking_targets_pipeline.R` and `run_complete_pipeline.R`.

For the narrative explaining why these scripts were superseded, see [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](../../../../docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §4 (Archaeology).

## Contents

### Pre-`_glm2` variants (superseded by the GLM2 refactor)

| Archived | Superseded by |
|---|---|
| `02_estimate_sex.R`, `02_estimate_sex_final.R` | `02_estimate_sex_glm2.R` |
| `03_estimate_race_ethnicity.R` | `03_estimate_race_ethnicity_glm2.R` |
| `04_estimate_fpl.R` | `04_estimate_fpl_glm2.R` |
| `05_estimate_puma.R` | `05_estimate_puma_glm2.R` |
| `06_estimate_mother_education.R` | `06_estimate_mother_education_glm2.R` |
| `07_estimate_mother_marital_status.R` | `07_estimate_mother_marital_status_glm2.R` |
| `13_estimate_phq2.R` | `13_estimate_phq2_glm2.R` |

Rationale: [`docs/raking/ne25/GLM2_REFACTORING_PLAN.md`](../../../../docs/raking/ne25/GLM2_REFACTORING_PLAN.md).

### Propensity-scoring approach (rejected)

- `26_estimate_propensity_model.R`
- `27_apply_propensity_nhis.R`
- `28_apply_propensity_nsch.R`

Propensity-based reweighting failed because pooling across three disjoint surveys (ACS, NHIS, NSCH) left the propensity model chronically misspecified.

### Classical IPF / raking approach (rejected)

- `27_rake_nhis_to_nebraska.R`
- `28_rake_nsch_to_nebraska.R`
- `rake_to_targets.R` (helper; only used by the above two)

Classical iterative proportional fitting cannot match a covariance structure, so it cannot use the 488 observed off-diagonal cells of the factorized target covariance.

### Orphaned / stubs

- `14_estimate_maternal_aces.R`, `14_estimate_maternal_aces_v2.R` — Phase 3 maternal ACEs, disabled in current orchestrator.
- `33_compute_kl_weights_ne25.R` — intent-file stub for multi-imputation orchestration; never implemented. Production weight code is `33_compute_kl_divergence_weights.R`.

### Stale verification / test scripts

- `11_phase2_verification.R` — Phase 2 milestone verification, references pre-`_glm2` filenames.
- `tests/verify_phase2.R`, `tests/verify_phase3.R` — same.
- `test_reverted_scripts.R`, `test_reverted_simple.R` — scratch tests for a pre-`_glm2` revert that was itself reverted.

## Roadmap

- Reconciling `run_raking_targets_pipeline.R` (still calls pre-`_glm2` `18_estimate_nsch_outcomes.R`) with `run_complete_pipeline.R` (uses `_glm2`) is a follow-up; see [`docs/archive/raking/ne25/ne25_weights_roadmap.md`](../../../../docs/archive/raking/ne25/ne25_weights_roadmap.md).
