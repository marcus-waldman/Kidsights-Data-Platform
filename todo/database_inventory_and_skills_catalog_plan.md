# Briefing: Database Inventory Catalog + Skills Inventory

**Created:** 2026-04-21 (by Claude, end of doc-audit session; context was running low)
**Owner:** Marcus Waldman
**Status:** Not started — briefing doc intended to be the starting prompt for a future session
**Sibling context:** `docs/archive/raking/ne25/ne25_weights_roadmap.md` (closed 2026-04-21 after MIBB Bucket 3 shipped) is the reference for how detailed pre-planning docs looked in this repo

---

## Why this work exists

The April 2026 pre-handoff doc audit (commits `6fe3092`, `18857dd`, `3999656`, `9c7ab07`, `d10fdca`, `1786e6f`) produced a clean handoff surface — HANDOFF.md, docs/index.html (Pages landing), and two refresh skills (`refresh-onboarding`, `refresh-handoff`). Two gaps remain:

1. **No authoritative table catalog.** The DB has ~97 tables. Documentation is fragmented across CLAUDE.md (one-line mentions), `docs/nsch/database_schema.md` (NSCH only), `docs/data_dictionary/ne25_data_dictionary_full.md` (`ne25_transformed` columns only), and scattered per-pipeline docs. A new maintainer cannot answer "what tables exist and what does each one hold?" from a single source.
2. **No discoverability surface for the project-scoped skills.** Two skills exist at `.claude/skills/{refresh-onboarding,refresh-handoff}/` — there will soon be three. Neither the onboarding page nor HANDOFF.md lists them, so a new maintainer would need to stumble onto `.claude/skills/` to discover them.

This briefing plans Work Item A (database catalog + regen skill) then Work Item B (skills inventory surfaced in onboarding + HANDOFF). Work Item A produces the third skill, so B logically follows A.

---

## Current state (what's already in place)

- `.claude/skills/refresh-onboarding/SKILL.md` — regenerates `docs/index.html` via `visual-explainer`
- `.claude/skills/refresh-handoff/SKILL.md` — surgically updates `HANDOFF.md`
- `CLAUDE.md → Documentation Maintenance` section documents both skills with cadence guidance
- Live Pages site: https://marcus-waldman.github.io/Kidsights-Data-Platform/
- Repo is public; default branch is `main`; `HEAD` used for durable GitHub blob links
- Audit's drift items (zero-row tables, NSCH naming inconsistency) are noted in HANDOFF.md — can be folded into the new catalog's `status` column

---

## Work Item A — Database TABLES catalog + regen skill

### Deliverable A1: `docs/database/TABLES.md`

Comprehensive catalog of all DuckDB tables, grouped by pipeline. Columns per row:

| Column | Example |
|---|---|
| **Table name** | `ne25_transformed` |
| **Rows** | 4,966 |
| **Source** | Produced by Step 6 of `run_ne25_pipeline.R` (derived variables via `recode_it()`) |
| **Columns (summary)** | 723 columns total — key: `pid`, `record_id`, `years_old`, `meets_inclusion`, `calibrated_weight`; plus 99 derived variables |
| **Used by** | Primary downstream: Step 6.7 joins GSED scores; Step 6.9 joins raking weights; downstream raking, imputation, IRT all read from this table |
| **Status** | live |

**Depth rules (user-confirmed 2026-04-21):**
- **Column summary format** per row: one-line summary per table like "Key columns: X, Y, Z; 99 derived variables" — NOT one line per column of every table
- **Exception for primary tables** (`ne25_transformed`, `ne25_raw`, `calibration_dataset_2020_2025`, `calibration_dataset_long`): link out to the full column-by-column dictionary (`docs/data_dictionary/*`). Don't duplicate column detail inline.
- **"Used by" format**: identify the single primary downstream (pipeline step + script path). Don't enumerate every consumer — readers can grep if they need more.

**Status values:** `live` / `backup` / `test` / `empty` / `deprecated`. Consolidates the audit's "cleanup candidates" list (see HANDOFF.md DB Drift section).

**Grouping:** by pipeline prefix (`ne25_*`, `nsch_*`, `nhis_*`, `acs_*`, `calibration_*`, etc.), then a "Cleanup candidates" section at the bottom for zero-row/backup/test tables.

### Deliverable A2: `.claude/skills/refresh-database-inventory/SKILL.md`

Regeneration skill following the same pattern as `refresh-onboarding` and `refresh-handoff`:

- **Data source**: live DuckDB via `python.db.connection.DatabaseManager` (context-managed — `db.execute_query()` does not exist)
- **Hybrid regeneration**: Python script queries DB for current table names, row counts, column lists. Hand-written metadata (source, usage, status) lives in a YAML config at `docs/database/table_metadata.yaml`. Markdown doc assembled from the two.
- **Orphan detection**: skill flags tables in the DB that aren't in the YAML config, and YAML entries that no longer have corresponding tables.
- **Triggers**: new table added, table dropped, row counts materially change, or ~monthly during active development.
- **Cadence**: similar to `refresh-handoff` (weekly-ish during active work) since table inventory drifts as pipelines run.
- **Output**: overwrite `docs/database/TABLES.md`; do NOT push without explicit user authorization.

Include all the standard skill sections (when to invoke, constraints, anti-patterns, success criteria) following the pattern established by the other two refresh skills.

### Acceptance criteria for Work Item A
- `docs/database/TABLES.md` lists all ~97 tables grouped by pipeline, each with the 6 columns above
- `docs/database/table_metadata.yaml` stores the hand-written purpose/usage/status for each table
- `.claude/skills/refresh-database-inventory/SKILL.md` exists and can regenerate the markdown from live DB + YAML
- `CLAUDE.md → Documentation Maintenance` section updated to include this third artifact and skill
- Cleanup candidates section lists the 12+ zero-row/backup/test tables already identified in HANDOFF.md

---

## Work Item B — Skills inventory surfaced in onboarding + HANDOFF

### Deliverable B1: A skills inventory section in `docs/index.html`

A new section on the onboarding page — likely between "Reading Order" and "Active In-Flight Work" — listing all **project-scoped** skills (only those in `.claude/skills/` of this repo; NOT the user's global `~/.claude/skills/`).

After Work Item A ships, that's 3 skills. Before A ships, it's 2.

**Format**: visual grid (like the pipelines grid) or a table. Per-skill fields:
- Skill name (invocation: `/refresh-onboarding`)
- One-line purpose
- Trigger conditions (when to invoke)
- File path (link to the SKILL.md on GitHub via `blob/HEAD/` pattern)

Regenerate via `/refresh-onboarding` after the section is added to the source content prompt.

### Deliverable B2: A skills inventory section in `HANDOFF.md`

Parallel section in HANDOFF.md under the "Knowledge Areas" or "Tips" area — markdown table with same fields. Surgical edit via `/refresh-handoff`.

### Deliverable B3: Update `refresh-onboarding` and `refresh-handoff` SKILL.md files

Both skills' "section structure" documentation should be updated to include the skills-inventory section, so future regenerations preserve it.

### Acceptance criteria for Work Item B
- Skills section visible on the live Pages site
- Skills section in HANDOFF.md
- Both refresh skills know about the section (their SKILL.md files updated)
- All 3 skills are listed

---

## Ordering / dependencies

1. **Work Item A first.** Produces the third skill, which should appear in Work Item B's inventory.
2. **Work Item B second.** Consumes A's output.
3. Each work item is a single commit (or maybe 2 per item — one for the artifact, one for the skill + docs). No PR process needed — single-maintainer repo with public visibility.

---

## How to open the next session

Suggested opening prompt for a fresh Claude session:

> Read `todo/database_inventory_and_skills_catalog_plan.md`. Execute Work Item A (database TABLES catalog + refresh-database-inventory skill), then Work Item B (skills inventory in onboarding + HANDOFF). Commit each work item separately. Ask before pushing per the repo's standing rule.

Before diving in, the fresh session should:
1. Read `HANDOFF.md` to catch up on repo state
2. Read the existing two skills at `.claude/skills/refresh-{onboarding,handoff}/SKILL.md` to match the pattern
3. Verify no new drift items have surfaced since 2026-04-21 (query DB, check CLAUDE.md)

Estimated effort: ~2 hours total for A + B if the DB is in a stable state. Longer if table metadata reconciliation surfaces surprises.

---

## Notes / gotchas

- **Hand-written YAML is the load-bearing piece.** Auto-generating column lists from DuckDB introspection is trivial; writing the "source" and "used by" fields requires reading code. Budget most of the Work Item A time for this reconciliation pass.
- **Skills inventory must be actively maintained.** As soon as a 4th skill appears, it needs to be added to both surfaces. Consider a tiny check in both refresh skills: "if `.claude/skills/` contains a directory not in the inventory, flag it."
- **The YAML config is git-tracked** and becomes the source of truth for table purpose/usage. Don't duplicate this information in CLAUDE.md — point CLAUDE.md at `docs/database/TABLES.md` instead.
- **Do not push automatically.** Per repo's standing rule, all pushes require explicit user authorization. The skill documents this; the next session should respect it.

---

*Created 2026-04-21 end-of-session. Context was running low; the in-session Claude made the correct call to prepare a self-contained briefing rather than attempt the work and run out of context mid-way.*
