# HRTL Scoring Documentation

**Healthy & Ready to Learn (HRTL)** scoring is integrated as **Step 7.7** of the NE25 pipeline (December 2025). It computes domain-level school-readiness classifications for children ages 3-5 from `meets_inclusion=TRUE` records, fitting Rasch IRT models, imputing missing item responses, and applying CAHMI thresholds.

## Where Documentation Lives

| Topic | Location |
|---|---|
| **Current production status, scoring algorithm, database tables, sub-step breakdown** | [`CLAUDE.md` → HRTL Scoring section](../../CLAUDE.md#-hrtl-scoring---production-ready-december-2025) |
| **Preprocessing scripts (Phase 1-4 detail)** | [`scripts/hrtl/README.md`](../../scripts/hrtl/README.md) |
| **Production pipeline scripts** | [`pipelines/orchestration/ne25_pipeline.R`](../../pipelines/orchestration/ne25_pipeline.R) Step 7.7 sub-steps |
| **Domain age-contingency data** | [`hrtl_item_age_contingency.csv`](hrtl_item_age_contingency.csv) (this directory) |

## Quick Reference

- **Eligibility:** children with `3 ≤ years_old < 6` AND `meets_inclusion = TRUE`
- **Domains scored:** 4 — Early Learning Skills, Health, Self-Regulation, Social-Emotional Development
- **Domain masked:** Motor Development (93% missing due to age-routed items; see [GitHub Issue #15](https://github.com/anthropics/claude-code/issues))
- **Output tables:** `ne25_hrtl_domain_scores`, `ne25_hrtl_overall`
- **Execution time:** ~13.4 seconds (Step 7.7)

For all current numbers, status, and any drift, **defer to CLAUDE.md** — this file is intentionally minimal to prevent duplication drift.

---

*Created: April 2026 (during pre-handoff doc audit)*
