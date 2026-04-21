# Repo Handoff Notes

**For:** Incoming maintainer of the Kidsights Data Platform
**From:** Marcus Waldman (outgoing maintainer)
**Snapshot date:** 2026-04-21
**Last updated:** 2026-04-21 (HEAD `1786e6f`; last audit commit `6fe3092`)

> **5-minute visual orientation:** [https://marcus-waldman.github.io/Kidsights-Data-Platform/](https://marcus-waldman.github.io/Kidsights-Data-Platform/)
>
> Open this in a browser before reading anything below. It's a one-page visual map of the 8 pipelines, the architecture, what's running, what's deferred, and the critical DB drift items. Source: `docs/index.html`. Regenerate via the `/refresh-onboarding` skill (see CLAUDE.md → Documentation Maintenance) when platform state materially changes.

---

## Read in This Order

1. **[CLAUDE.md](CLAUDE.md)** — authoritative current-state reference. Read fully. Status, pipeline counts, derived variables, coding standards, run commands. This is the doc that gets updated when reality changes; trust it over any other doc.
2. **[docs/setup/INSTALLATION_GUIDE.md](docs/setup/INSTALLATION_GUIDE.md)** — set up your machine. You'll need API keys for IPUMS, REDCap, and FRED — see "Credentials" section below.
3. **[README.md](README.md)** — slim landing page (intentionally; was rewritten in the audit to point to CLAUDE.md rather than duplicate stats that drift)
4. **[docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** — command cheatsheet for all 8 pipelines

After that, dive into per-pipeline docs as needed. The new architecture/README.md and architecture/PIPELINE_OVERVIEW.md are good orientation.

---

## What's Running in Production (as of 2026-04-21)

The platform has **eight independent pipelines**. All have been used in production at some point; current state varies:

| # | Pipeline | Status | Entry point |
|---|---|---|---|
| 1 | NE25 (Nebraska 2025 REDCap) | Production | `run_ne25_pipeline.R` |
| 2 | MN26 (Minnesota 2026 REDCap, multi-child) | Core complete; raking and imputation deferred | `run_mn26_pipeline.R` |
| 3 | ACS (IPUMS USA) | Production | `pipelines/python/acs/extract_acs_data.py` |
| 4 | NHIS (IPUMS Health Surveys) | Production | `pipelines/python/nhis/extract_nhis_data.py` |
| 5 | NSCH (SPSS files) | Production | `scripts/nsch/process_all_years.py` |
| 6 | Raking Targets | Production | `scripts/raking/ne25/run_raking_targets_pipeline.R` |
| 7 | Imputation | Production (M=5, 11 stages, 29 variables) | `scripts/imputation/ne25/run_full_imputation_pipeline.R` |
| 8 | IRT Calibration | In development; produces `calibration_dataset_*` tables for Mplus | `scripts/irt_scoring/run_calibration_pipeline.R` |

For per-pipeline operational details and current record counts, see [CLAUDE.md → Current Status](CLAUDE.md#current-status-april-2026).

---

## Active In-Flight Work

### NE25 MIBB Variance Estimation Framework — complete (April 2026)

**What:** Multiple Imputation + Bayesian Bootstrap (MIBB) for estimating sampling variance of NE25 raking weights, accounting for both substantive imputation uncertainty and weight calibration uncertainty.

**Where:** `scripts/raking/ne25/35_run_bayesian_bootstrap.R` (orchestrator) and `scripts/raking/ne25/36_store_bootstrap_weights_long.py` (DB loader).

**Status:** All three buckets shipped.
- Bucket 1: M=1 calibrated raking weights (production).
- Bucket 2: M=5 multi-imputation calibrated weights (production; `ne25_raked_weights`, 13,225 rows).
- **Bucket 3 complete (commits `1b5ac79`, `971875f`):** 5 imputations × 200 Bayesian-bootstrap draws = 1,000 Stan refits, all converged. Stored in `ne25_raked_weights_boot` (**2,645,000 rows**, PK `(pid, record_id, imputation_m, boot_b)`). Framework: MI + sample-only Bayesian bootstrap (NE22 pattern — `bbw ~ Exp(1)` as multiplicative data weight in the moment loss; flat `Dirichlet(1,…,1)` prior). Per-imputation Kish-N CV across bootstrap draws: 0.009–0.010.

**Design note (per-project memory):** The earlier `BOOTSTRAP_IMPLEMENTATION_PLAN.md` (now in `docs/archive/raking/ne25/`) is for the upstream **survey-design** replicate weights bootstrap on ACS targets — that work completed in October 2025 and is unrelated to the MIBB variance work described here.

**Follow-on (separate ticket, not yet started):** wire `reports/ne25/helpers/model_fitting.R` to iterate over `(imputation_m, boot_b)` pairs and pool variance via Rubin's rules. Today it consumes only the point-estimate `calibrated_weight` column.

**Closed-out references:** [`docs/archive/raking/ne25/ne25_weights_roadmap.md`](docs/archive/raking/ne25/ne25_weights_roadmap.md) (archived 2026-04-21 after all three buckets shipped); [`docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd`](docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd) §5.4 documents the shipped implementation and Rubin's-rules formula.

### MN26 (Minnesota 2026)

**Status:** Core pipeline runs end-to-end. Kidsights scoring integrated. Raking and imputation **explicitly deferred** (need MN ACS data extraction first).

**Active todo:** [`todo/mn26_pipeline_plan.md`](todo/mn26_pipeline_plan.md)

---

## DB Drift Items

The April 2026 audit surfaced several divergences between docs and DB state. After review (2026-04-21, Marcus), items 1-5 from the original audit were closed as acceptable — the DB represents current intent and the doc claims were outdated design text or pre-QA counts. Only the NSCH naming inconsistency remains open as a worth-standardizing item.

### Closed after review (2026-04-21)

- `raking_targets_ne25` row count (11 is current state; the 180-target design text in older docs is stale)
- `calibration_dataset_2020_2025` record count (9,319 is the post-QA state; 47,084 was a pre-filter count)
- Missing `ne25_calibration` table and per-study `ne**_calibration` tables (consolidated into `calibration_dataset_*` family; older pipeline Step 11 docs are stale)
- Missing `overall_influence_cutoff` and `authenticity_weight` columns on `ne25_transformed` (removed in a refactor; no longer part of the current schema)

### Cleanup candidates

12+ zero-row / test / backup tables polluting the schema:
- `ne25_*_test` (2 tables)
- `ne25_transformed_backup_2025_11_08`
- `ne25_imputed_imputed_cc_*` (4 zero-row defunct double-prefixed)
- `ne25_irt_scores_*` (2 zero-row)
- `ne25_raw_pid*` (4 zero-row per-project)
- `ne25_eligibility` (0-row)

### NSCH table-naming inconsistency

Years 2017-2020 and 2023 use `nsch_{year}_raw`; years 2021 and 2022 use `nsch_{year}` (no `_raw` suffix). 2016 table exists but is empty (schema differences). Worth standardizing.

---

## Known Open Issues

- **GitHub Issue #15** (HRTL Motor Development masking) — Motor domain classification masked to NA because age-routed items DrawFace/DrawPerson/BounceBall have 93% missing. Overall HRTL marked NA pending fix.
- **GitHub Issue #11** (Age Gradient Explorer Shiny app) — partial implementation of masking toggle and response options display
- **GitHub Issue #6** (NSCH calibration data exclusion) — resolved per CLAUDE.md, but pre-existing issue templates still exist under `.github/ISSUE_TEMPLATE/`
- **Issue #8** (NSCH negative age correlations) — resolved (4 items remaining with weak correlations, expected from age-routing design)

GitHub issue templates live in `.github/ISSUE_TEMPLATE/` if you want context on past investigations.

---

## Credentials / Access Transfer

The platform requires three external API integrations. Each is configured via the `.env` file at the project root (see `.env.template` for variables):

| API | `.env` variable | Where to get | Used by |
|---|---|---|---|
| **REDCap** | `REDCAP_API_CREDENTIALS_PATH` | Contact REDCap administrator at UNMC for project tokens (PIDs 7679, 7943, 7999, 8014 for NE25; separate token for MN26 NORC project) | NE25 + MN26 pipelines |
| **IPUMS** | `IPUMS_API_KEY_PATH` | https://account.ipums.org/api_keys | ACS + NHIS pipelines |
| **FRED** | `FRED_API_KEY_PATH` | https://fredaccount.stlouisfed.org/apikeys | NE25 + MN26 income transformations (CPI inflation adjustment in `R/utils/cpi_utils.R`) |

**Transfer steps:**
1. Outgoing maintainer: ensure incoming maintainer has REDCap project access at UNMC (this is the gating dependency — IPUMS and FRED are self-service)
2. Incoming maintainer: register for IPUMS and FRED accounts, generate API keys, save to local files
3. Incoming maintainer: copy `.env.template` to `.env`, fill in paths matching local file locations
4. Run `python scripts/setup/verify_installation.py` to confirm all checks pass

The `.env` file is gitignored — never commit it.

Full setup walkthrough: [docs/setup/INSTALLATION_GUIDE.md](docs/setup/INSTALLATION_GUIDE.md).

---

## Uncommitted Work in Repo at Handoff

None as of 2026-04-21. The earlier breadcrumb (`scripts/raking/ne25/utils/calibrate_weights_simplex_factorized.exe`) was recompiled and committed as part of the Bucket 3 shipping window (`971875f`), alongside its regenerated `.stan` source. Working tree is clean.

---

## Doc Audit Outcomes (April 2026)

Just before this handoff, a comprehensive doc audit ran. Single commit: `6fe3092`. Summary:

- **32 deletions** of cruft (`PIPELINE_RUN_SUMMARY.md`, `docs/pipeline/`, `docs/manual/_book/` build artifacts, `docs/data_dictionary/ne25/legacy/`, etc.)
- **30 completed planning docs archived** to `docs/archive/<pipeline>/` (PHASE/PLAN/MIGRATION docs from imputation, raking, NSCH, NHIS, ACS, guides, irt_scoring)
- **Abandoned Quarto book** (`docs/manual/`) archived to `docs/archive/manual/` with build artifacts removed
- **Codebook docs reorganized**: `codebook_utilities.md` and `codebook_api.md` moved into `docs/codebook/`
- **19 load-bearing docs drift-checked** against the live DB and code; each gained a `## Verification Summary` section at the bottom listing what was confirmed, corrected, and remaining-drift items

To view what the audit changed: `git show 6fe3092 --stat`. To find the comprehensive corrections list: search for "Verification Summary" headers in CLAUDE.md, README.md, INDEX.md, QUICK_REFERENCE.md, and the Tier 2-4 docs.

---

## Knowledge Areas (where to look first)

| Area | Primary doc | Secondary |
|---|---|---|
| What is this repo | CLAUDE.md | README.md |
| How to run pipeline X | docs/QUICK_REFERENCE.md | docs/architecture/PIPELINE_STEPS.md |
| Architecture decisions | docs/architecture/PIPELINE_OVERVIEW.md | docs/architecture/README.md |
| Setup / new machine | docs/setup/INSTALLATION_GUIDE.md | docs/setup/INSTALLATION_CHECKLIST.md |
| Coding standards | docs/guides/CODING_STANDARDS.md | CLAUDE.md "Critical Coding Standards" |
| Missing data handling | docs/guides/MISSING_DATA_GUIDE.md | (REQUIRED reading before adding derived vars) |
| NE25 raking weights | docs/raking/RAKING_INTEGRATION.md | docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd |
| NE25 MIBB variance work | docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd §5.4 | scripts/raking/ne25/35_run_bayesian_bootstrap.R (archived roadmap: docs/archive/raking/ne25/ne25_weights_roadmap.md) |
| MN26 multi-child pipeline | docs/mn26/pipeline_guide.qmd | todo/mn26_pipeline_plan.md |
| Imputation | docs/imputation/IMPUTATION_PIPELINE.md | docs/imputation/ADDING_NEW_STUDY.md |
| IRT calibration | docs/irt_scoring/CALIBRATION_PIPELINE_USAGE.md | docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md |
| HRTL scoring | docs/hrtl/README.md | scripts/hrtl/README.md, CLAUDE.md HRTL section |
| Authenticity screening | docs/authenticity_screening/README.md | scripts/influence_diagnostics/README.md |
| Codebook system | docs/codebook/README.md | docs/codebook/codebook_api.md |

---

## Project-Scoped Claude Skills

Three skills live in `.claude/skills/` of this repo and encapsulate the regeneration recipes for the platform's living documentation. Invoke from Claude Code via the slash command shown. Each skill's `SKILL.md` documents the workflow, constraints, and success criteria.

| Skill | Purpose | When to invoke | SKILL.md |
|---|---|---|---|
| `/refresh-onboarding` | Regenerate `docs/index.html` (the public GitHub Pages orientation page). | Pipeline added/removed, status change, drift item resolved, quarterly minimum. | [.claude/skills/refresh-onboarding/SKILL.md](.claude/skills/refresh-onboarding/SKILL.md) |
| `/refresh-handoff` | Surgically update HANDOFF.md (this doc). Preserves hand-crafted prose; updates volatile fields only. | Material commit lands, drift item resolves, in-flight workstream shifts, weekly during pre-handoff. | [.claude/skills/refresh-handoff/SKILL.md](.claude/skills/refresh-handoff/SKILL.md) |
| `/refresh-database-inventory` | Regenerate `docs/database/TABLES.md` from live DB introspection + hand-written YAML metadata. | Table added/dropped/renamed, row counts drift materially, cleanup candidates purged. | [.claude/skills/refresh-database-inventory/SKILL.md](.claude/skills/refresh-database-inventory/SKILL.md) |

All three skills require explicit user authorization before pushing to remote. See CLAUDE.md → Documentation Maintenance for the broader cadence guidance. If a fourth project-scoped skill is added, extend both this table and the equivalent section on the onboarding page.

---

## Recommended First-Week Plan

**Day 1:** Read CLAUDE.md fully. Skim README.md, INDEX.md, QUICK_REFERENCE.md to know what's where.

**Day 2:** Set up your machine via INSTALLATION_GUIDE.md. Get API keys configured. Run `verify_installation.py`. Try running the NE25 pipeline end-to-end on your local machine — this exercises REDCap access, R/Python integration, DuckDB writes.

**Day 3:** Read docs/architecture/PIPELINE_OVERVIEW.md to build mental model of how the 8 pipelines fit together.

**Day 4:** Pick the pipeline most relevant to your immediate work and read its per-pipeline docs in `docs/<pipeline>/`. Run it end-to-end if possible.

**Day 5:** Skim the 2026-04-20 doc audit (`git show 6fe3092`) and the follow-up drift review (commit message body) to see what was verified against the live DB and why items 1-5 of the drift table were closed. This grounds you in what actually exists now vs. what older docs once claimed.

After week 1: if picking up the MIBB variance work's loose end (Rubin's-rules pooling in `reports/ne25/helpers/model_fitting.R`), read `docs/raking/ne25/WEIGHT_CONSTRUCTION.qmd` §5.4 and the archived `docs/archive/raking/ne25/ne25_weights_roadmap.md`. Otherwise, whatever your specific brief is.

---

## Tips from the Outgoing Maintainer

- **R execution:** never use inline `-e` commands — they cause segfaults. Always use `--file=script.R` or `Rscript`. See CLAUDE.md "R Execution" section.
- **Database operations always go through Python.** This was an architectural decision after R DuckDB segfaults. Don't try to use R DuckDB directly.
- **Use `safe_left_join()` not `dplyr::left_join()`** — catches column collisions before they corrupt data. See CLAUDE.md "Safe Joins" section.
- **`pid` alone does not uniquely identify NE25 records.** It's `pid + record_id` together. (For MN26 it's `pid + record_id + child_num` because of multi-child households.)
- **Old todo files are in `todo/archive.zip`** — bulk-archived Dec 2025 to save repo size. If you need them, unzip locally; don't re-add to git.
- **Quarto `.qmd` files render to HTML** — don't render in-place if it creates `_book/` or `_files/` subdirs (those should be gitignored, but historically have been committed by mistake).
- **The "Verification Summary" pattern** introduced in the April 2026 audit is worth continuing: when fact-checking a doc against the codebase, append a brief summary block at the end. Future audits become easier when each doc's last verification date is visible.

---

## Contact

- **Outgoing maintainer:** Marcus Waldman — `marcus.waldman@cuanschutz.edu` (academic) / `marcus.waldman@gmail.com` (personal)
- **Institution:** University of Colorado Anschutz Medical Campus
- **REDCap admin contact:** UNMC REDCap administrators (for project token access)

---

*Created: April 2026 (Bucket F of pre-handoff doc audit). This file is a snapshot — it will become stale. CLAUDE.md is the living reference.*
