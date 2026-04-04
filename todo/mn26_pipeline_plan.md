# MN26 Pipeline Implementation Plan

**Created:** 2026-04-04 | **Updated:** 2026-04-04 | **Status:** Phase 1 Complete | **Repository:** Kidsights-Data-Platform

---

## Context

The NE25 (Nebraska 2025) pipeline is production-ready, processing 3,908 REDCap records through extraction, transformation, scoring, weighting, and loading into DuckDB. A new Minnesota 2026 (MN26) study uses the same REDCap platform but with significant variable changes. A separate repo (`kidsights-norc`) already has a working monitoring tool for MN26, tested against 2,654 records.

We need to build an MN26 ETL pipeline within the Kidsights Data Platform. The biggest structural change is **multi-child support** (up to 2 children per household), requiring a wide-to-long pivot. Many variables have been renamed, recoded, or restructured.

### Key Architecture Decision

**Early pivot (Option A):** Convert wide (1 row per household) to long (1 row per child) immediately after extraction, before any transforms. Unique identifier becomes `pid + record_id + child_num`.

---

## Phase 1: Variable Reconciliation Audit

### Goal
Produce a structured audit report comparing NE25 and MN26 REDCap data dictionaries field-by-field, categorizing every field by status. This becomes the authoritative reference for Phase 2.

### Dictionary Sources

| Dictionary | Source | Fields |
|-----------|--------|--------|
| NE25 | `data/export/ne25/ne25_data_dictionary.csv` (1,132 fields, 14 columns) | Already cached locally |
| MN26 (active) | Pull via API using `get_data_dictionary()` from kidsights-norc with `exclude_hidden=TRUE` | ~648 fields |
| MN26 (full) | Same API with `exclude_hidden=FALSE` | ~865 fields |
| MN26 hidden | Difference of full - active | ~217 retired NE25 fields |

**API access:** Live pull using `kidsights-norc/progress-monitoring/mn26/utils/redcap_utils.R`. MN26 REDCap API credentials available.

### Audit Script

**File:** `scripts/mn26/reconciliation_audit.R`

Written in R (both dictionary utilities are in R, and NE25's `value_labels()` already parses REDCap choice strings).

**Classification algorithm** — for each field in the union of both dictionaries:

| Category | Definition |
|----------|-----------|
| IDENTICAL | Same field_name, field_type, and select_choices |
| RENAMED | Different field_name, same/similar field_label (fuzzy match or seed mapping) |
| RECODED | Same field_name, different select_choices (with before/after diff) |
| STRUCTURALLY CHANGED | Same base concept, checkbox count or suffix scheme changed |
| NEW IN MN26 | Active MN26 field with no NE25 equivalent |
| REMOVED (HIDDEN) | NE25 field marked @HIDDEN in MN26 |
| REMOVED (ABSENT) | NE25 field not in MN26 dictionary at all |

**Known mappings to seed:**

```
NE25 cqr002       → MN26 mn2           (renamed + added Non-binary=97)
NE25 age_in_days  → MN26 age_in_days_n (renamed, both @HIDDEN calc fields)
NE25 eqstate      → MN26 mn_eqstate    (renamed)
NE25 cqr010       → MN26 cqr010b       (structural: 15 race categories → 6, codes 1-15 → 100-105)
NE25 sq002        → MN26 sq002b        (structural: same change)
NE25 cqr009       = MN26 cqr009        (IDENTICAL: 1=Female, 0=Male — NO swap, earlier docs were wrong)
NE25 cqr004       = MN26 cqr004        (IDENTICAL: codes 0-8 — NO shift)
N/A               → MN26 *_c2 vars     (new: 341 child 2 fields for multi-child support)
```

**High-risk flags:** Any variable used in joins or eligibility, any variable feeding composite scores.

**Output:** `reports/mn26/reconciliation_audit.html` — summary counts, full field table, high-risk flags, side-by-side choice diffs, instrument comparison.

### Key Verification: Dictionary-Driven Transforms

Several NE25 transforms are **more portable than expected** because they read value mappings from the dictionary rather than hardcoding them:
- **Education** (`cqr004`): Uses `value_labels(lex="cqr004", dict=dict)` — both NE25 and MN26 use codes 0-8 with same labels. Works as-is.
- **Sex** (`cqr009`): Uses `value_labels(lex="cqr009", dict=dict)` then checks `sex == "Female"` — both dictionaries use 1=Female, 0=Male. **No swap exists** (earlier docs were wrong, corrected 2026-04-04). Works as-is.
- **Race/education collapse**: Uses dictionary labels for factor levels.

**Three-way audit results (2026-04-04):**
- 331 fields IDENTICAL (active in both)
- 128 fields HIDDEN_IDENTICAL (@HIDDEN in MN26 but unchanged — still in data, pipeline-relevant)
- 341 NEW_CHILD2 fields (multi-child support)
- 3 RECODED (cqr006, mmi003, mrw002 — all sliders, likely range changes)
- 3 RENAMED (cqr002→mn2, age_in_days→age_in_days_n, eqstate→mn_eqstate)
- 2 STRUCTURAL (cqr010→cqr010b, sq002→sq002b race checkbox reorganization)
- 2 HIDDEN_RECODED (consecutive_nos calc formulas)
- 2 REMOVED_ABSENT (criteria_meet display, ineligible_flag calc — not data fields)

Transforms that are **hardcoded and must change:**
- `female_a1 = as.logical(cqr002 == 0)` → must become `mn2 == 0` (same logic, different var name)
- `age_in_days` references → must become `age_in_days_n`
- `eqstate` → `mn_eqstate`
- Race checkbox columns: `cqr010` (15 options) → `cqr010b` (6 options), `sq002` → `sq002b`
- All `_c2` child 2 variables: don't exist in NE25 (handled by pivot)
- @HIDDEN fields: 128 fields are hidden in MN26 but still present in data and unchanged — no transform changes needed

### Phase 1 Deliverables

1. `scripts/mn26/reconciliation_audit.R` — audit script (live API pull for both dictionaries)
2. `reports/mn26/reconciliation_audit.html` — rendered report
3. `config/mappings/ne25_to_mn26_field_map.csv` — machine-readable field mapping
4. `todo/mn26_pipeline_plan.md` — copy of this plan, committed to repo

### Phase 1 Checkpoint: Review Together

Before proceeding to Phase 2, we review the audit to:
1. Confirm all variable mappings correctly identified
2. Identify MN26-only variables needing new transform logic
3. Decide which scoring systems (CREDI, GSED, HRTL) apply to MN26
4. Confirm pivot handles all `_c2` variables found in dictionary
5. Identify any instruments or question blocks unique to MN26

---

## Phase 2: MN26 Pipeline Architecture

### 2.1 Wide-to-Long Pivot

**File:** `R/transform/mn26_pivot.R` (new)

Runs immediately after extraction, before any transforms:

1. Identify all `_c2` suffix columns from the raw data
2. Map each to its child-1 equivalent (e.g., `cqr009_c2` → `cqr009`, `age_in_days_c2_n` → `age_in_days_n`)
3. Create child 1 rows: all records, `child_num = 1`, drop `_c2` columns
4. Create child 2 rows: only where `dob_c2_n` is non-empty, rename `_c2` → base, `child_num = 2`
5. `dplyr::bind_rows()`, add `child_key = paste(pid, record_id, child_num, sep="_")`
6. Household-level variables (parent demographics, SES, ACEs, consent) duplicated across both rows

**Known `_c2` patterns from kidsights-norc:**
- `age_in_days_c2_n`, `dob_c2_n` (age/DOB)
- `cqr009_c2` (sex)
- `cqr010_c2b___100` through `___105` (race checkboxes)
- `cqr011_c2` (ethnicity)
- `module_6_*_2_complete` (survey completion)
- `nsch_questions_2_complete` (NSCH completion)
- `child_information_2_954c_complete` (child info completion)
- Likely more — audit will identify the complete set

### 2.2 Database Schema

**File:** `schemas/landing/mn26.sql` (new)

| Table | Purpose |
|-------|---------|
| `mn26_raw_wide` | Original wide extraction (1 row/household), audit trail |
| `mn26_raw` | Post-pivot long format (1 row/child), working table |
| `mn26_eligibility` | 4-criteria eligibility per child |
| `mn26_transformed` | Fully transformed with derived variables |
| `mn26_data_dictionary` | REDCap dictionary metadata |

### 2.3 Transform Design: Copy-and-Modify

**Decision:** Copy `ne25_transforms.R` → `mn26_transforms.R`, then modify using the reconciliation audit as a guide.

**Rationale:** The 1,381-line `recode__()` function has deeply interleaved variable references. Abstracting it would touch nearly every line and risk breaking NE25. Many transforms ARE dictionary-driven, but the variable name references throughout (column selection, joins, conditional logic) are hardcoded.

**Shared utilities to extract (already generic):**
- `R/utils/cpi_utils.R` ← `cpi_ratio_1999()` (FRED API, study-agnostic)
- `R/utils/poverty_utils.R` ← `get_poverty_threshold()` (FPL tables, study-agnostic)
- `R/utils/recode_utils.R` ← `recode_missing()` (sentinel codes, study-agnostic)
- `R/utils/query_geo_crosswalk.R` — already separate and study-agnostic
- `R/utils/safe_joins.R` — already separate and study-agnostic

### 2.4 Eligibility: 4 Criteria

**File:** `R/harmonize/mn26_eligibility.R` (new, based on kidsights-norc logic)

| Criterion | Variable | Rule |
|-----------|----------|------|
| Parent age | `eq003` | `== 1` (age >= 19) |
| Child age | `age_in_days_n` | `<= 1825` (0-5 years) |
| Primary caregiver | `eq002` | `== 1` |
| Minnesota residence | `mn_eqstate` | `== 1` |

Post-pivot: evaluated per child row. No CID6-9 equivalents (NE25-specific).

### 2.5 Geographic Crosswalks

The existing 10 `geo_zip_to_*` DuckDB tables are **national** (all US ZCTAs). Only the ZIP prefix validation changes: Nebraska 680-693 → Minnesota 550-567. `query_geo_crosswalk()` is already state-agnostic.

### 2.6 Configuration

**File:** `config/sources/mn26.yaml` — replace all `[MN26 TODO]` placeholders:
- `redcap_url`: `https://unmcredcap.unmc.edu/redcap/api/` (same UNMC instance)
- `age_fields`: `age_in_days_n`
- `state_variable`: `mn_eqstate`
- `child_age_max_days`: 1825
- `race_prefixes`: `cqr010b_`, `sq002b_`
- ZIP prefixes: already populated (550-567)

### 2.7 Pipeline Orchestration

**File:** `pipelines/orchestration/mn26_pipeline.R` (new, modeled on ne25_pipeline.R)
**Entry:** `run_mn26_pipeline.R`

Steps:
1. Load API credentials
2. Extract REDCap data (single project)
3. Extract data dictionary (with `exclude_hidden=TRUE`)
4. **Wide-to-long pivot** (NEW — not in NE25)
5. Store raw (both wide + long tables)
6. Apply transforms (`recode_it_mn26()`)
7. Eligibility validation (4 criteria)
8. Create `meets_inclusion` filter
9. Store transformed data
10. Scoring (CREDI, GSED, HRTL — TBD at checkpoint)
11. Generate metadata

---

## Phase 3: Implementation Priorities

### Sprint 1: Reconciliation Audit (Phase 1)
- `scripts/mn26/reconciliation_audit.R`
- `reports/mn26/reconciliation_audit.html`
- `config/mappings/ne25_to_mn26_field_map.csv`
- **CHECKPOINT: Review audit together**

### Sprint 2: Extraction + Pivot + Schema
- `R/extract/mn26.R` (port from kidsights-norc)
- `R/transform/mn26_pivot.R`
- `schemas/landing/mn26.sql`
- `config/sources/mn26.yaml` (fill placeholders)
- Integration test: extract → pivot → store → verify row counts

### Sprint 3: Core Transforms
- `R/transform/mn26_transforms.R` (race, sex, age, gender, education, marital status)
- `R/harmonize/mn26_eligibility.R`
- Extract shared utils to `R/utils/`
- Integration test: transforms produce expected distributions

### Sprint 4: Geographic + Income + Remaining Transforms
- Geographic (Minnesota ZIPs), income/FPL, mental health, childcare, ACEs
- Full transform integration test

### Sprint 5: Pipeline Orchestration + End-to-End
- `pipelines/orchestration/mn26_pipeline.R`
- `run_mn26_pipeline.R`
- End-to-end test against MN26 test project (2,654 records)
- Scoring integration (if applicable, based on checkpoint decision)

### What Can Wait
- Raking targets (needs Minnesota ACS data)
- Imputation pipeline (needs stable transforms first)
- IRT calibration (needs scoring systems confirmed)
- Authenticity screening (no CID6-9 defined)
- SES analytic dataset for MN26 (needs full pipeline first)

---

## New Files to Create

| File | Sprint | Purpose |
|------|--------|---------|
| `scripts/mn26/reconciliation_audit.R` | 1 | Dictionary comparison script |
| `config/mappings/ne25_to_mn26_field_map.csv` | 1 | Machine-readable field mapping |
| `R/extract/mn26.R` | 2 | REDCap extraction functions |
| `R/transform/mn26_pivot.R` | 2 | Wide-to-long pivot |
| `schemas/landing/mn26.sql` | 2 | Database schema |
| `R/transform/mn26_transforms.R` | 3 | MN26-specific transforms |
| `R/harmonize/mn26_eligibility.R` | 3 | 4-criteria eligibility |
| `R/utils/cpi_utils.R` | 3 | Extracted shared utility |
| `R/utils/poverty_utils.R` | 3 | Extracted shared utility |
| `R/utils/recode_utils.R` | 3 | Extracted shared utility |
| `pipelines/orchestration/mn26_pipeline.R` | 5 | Pipeline orchestrator |
| `run_mn26_pipeline.R` | 5 | Entry point |

## Existing Files to Modify

| File | Sprint | Change |
|------|--------|--------|
| `config/sources/mn26.yaml` | 2 | Fill all `[MN26 TODO]` placeholders |
| `R/transform/ne25_transforms.R` | 3 | Source extracted utils instead of inline definitions |
| `codebook/data/codebook.json` | 5 | Add `lex_mn26` entries (if scoring applies) |
| `CLAUDE.md` | 5 | Add MN26 pipeline documentation |

## Verification

- **Phase 1:** Audit report reviewed and approved before proceeding
- **Sprint 2:** Pivot row counts match: `N(child_num==1) == N(records)`, `N(child_num==2) == N(records with dob_c2_n)`
- **Sprint 3:** Sex, race, education distributions match kidsights-norc monitoring output
- **Sprint 5:** Full pipeline runs end-to-end on 2,654 test records with no errors
- **Unique identifier:** `pid + record_id + child_num` throughout all MN26 tables

## Risk Register

| Risk | Mitigation | Status |
|------|-----------|--------|
| Dictionary has more changes than known | Phase 1 three-way audit catches all programmatically | **Resolved** — audit complete |
| Sex code swap silently miscodes | Verified IDENTICAL in both dictionaries (1=F, 0=M) | **Resolved** — no swap exists |
| @HIDDEN fields missing from audit | Three-way comparison includes full MN26 dictionary | **Resolved** — 128 hidden-identical found |
| Pivot creates duplicates or data loss | Unit test with 0/1/2 children edge cases | Open |
| Geographic crosswalks missing MN ZCTAs | Tables are national; verify MN coverage | Open |
| Scoring instruments not in MN26 | Checkpoint decision; pipeline works without scoring | Open |
| Breaking NE25 while extracting shared utils | New files only; NE25 sources them; run NE25 pipeline to verify | Open |
