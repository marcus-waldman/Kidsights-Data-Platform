---
name: refresh-database-inventory
description: Regenerate `docs/database/TABLES.md` from live DuckDB introspection + the hand-written metadata in `docs/database/table_metadata.yaml`. Invoke when a table is added, dropped, renamed, moves between pipelines, or when row counts materially drift. Third member of the docs-refresh skill family (alongside `/refresh-onboarding` and `/refresh-handoff`).
---

# Refresh the Kidsights Database Table Catalog

## When to invoke

Run this skill when **any of the following has changed since the last regeneration**:

- A new table was added to the DuckDB database (new pipeline output, new metadata table, new crosswalk)
- A table was dropped, renamed, or moved (e.g., consolidation of per-study tables into a combined one)
- A previously-flagged cleanup-candidate table was finally removed
- Row counts for a load-bearing table shifted materially (e.g., a new year of NSCH data landed; a raking run produced different weights)
- A table's purpose or downstream consumer changed (e.g., a new pipeline step now reads from `ne25_transformed`)
- Roughly weekly during active development, if multiple smaller changes have accumulated

**Do NOT invoke for:**
- Trivial row-count drift inside an already-catalogued table (pipeline reruns producing ±1 row)
- Purely cosmetic doc edits that don't touch the schema
- Anything that can be handled by a targeted edit to `table_metadata.yaml` + a single re-run

## Sister skills

This is the third member of the docs-refresh family:

- **`/refresh-onboarding`** regenerates `docs/index.html` (public GitHub Pages landing)
- **`/refresh-handoff`** surgically updates `HANDOFF.md` (internal maintainer-transition doc)
- **`/refresh-database-inventory`** (this one) regenerates `docs/database/TABLES.md` (authoritative table catalog)

All three are decoupled by cadence and scope. This skill touches only the database catalog — it does not re-run the onboarding page or HANDOFF.md. Doc cross-references between the three artifacts should be kept stable so they don't drift into each other's territory.

## What this skill produces

A refreshed `docs/database/TABLES.md` that:
- Lists every table currently in the DuckDB database
- Groups tables by pipeline (ne25, ne25_imputed, nsch, nhis, acs, calibration, historical, raking, crosswalks, metadata) with a "Cleanup Candidates" section at the end
- Shows live row and column counts from DB introspection
- Shows hand-written source, purpose, downstream consumer, and status from `docs/database/table_metadata.yaml`
- Surfaces orphan or stale entries (DB table missing from YAML, or YAML entry with no matching table) as a hard error — the generator exits non-zero and the maintainer must resolve the drift before the catalog regenerates

## Architecture (hybrid regeneration)

The catalog is assembled from two sources:

1. **Live DuckDB introspection** — row counts, column counts, and column names. Produced by `scripts/documentation/inventory_tables.py::build_inventory()`. This is the volatile part; it re-runs on every invocation.
2. **Hand-written YAML metadata** — `docs/database/table_metadata.yaml`. This holds the editorial judgment fields (purpose, source, primary downstream, status, group). This is the load-bearing part; it is edited by hand and survives DB churn.

The assembler is `scripts/documentation/generate_tables_md.py`. It imports the introspection function, reads the YAML, joins them, and writes the markdown. If it detects orphans, it exits non-zero and prints actionable guidance.

## Workflow

### Phase 1: Understand what changed

Before touching anything, figure out the scope of the refresh:

**1.1 Diff the DB against the YAML.** Run the generator and read its stderr output:

```bash
py scripts/documentation/generate_tables_md.py
```

- **Exit 0:** no orphans. The catalog regenerated successfully. You may still want to refresh metadata for tables whose purpose has changed — proceed to Phase 2.
- **Exit 1:** orphans detected. The stderr output lists DB tables missing from the YAML and YAML entries with no matching DB table. Resolve before proceeding.

**1.2 Classify each orphan.** For each DB table missing from the YAML:
- Is it a legitimate new table (new pipeline output, new metadata, new crosswalk)? → add a YAML entry.
- Is it a test or throwaway table that should be cleaned up instead? → delete it from the DB rather than cataloguing it.
- Is it a defunct double-prefixed or legacy artifact? → add it to the YAML with `status: empty` and `group: cleanup` so it's visible as a cleanup candidate.

For each YAML entry with no matching table:
- Was the table intentionally dropped? → remove the YAML entry.
- Was the table renamed? → rename the YAML key to match.
- Did the table fail to ingest? → investigate the pipeline; don't remove the YAML entry until you understand why.

**1.3 Identify metadata staleness.** Even if the set of tables matches, individual entries may be stale:
- `source`: is the script path still correct? (Pipelines get renamed; scripts move between directories.)
- `primary_downstream`: is the consumer still the one named? (A new raking script may now be the primary reader.)
- `status`: did a cleanup-candidate table finally get purged, or a placeholder finally get populated?
- `notes`: is there new context worth capturing?

Grep for the table name if you're unsure which script writes to it:

```bash
# From the repo root. Searches R and Python source.
grep -rn "table_name" --include="*.R" --include="*.py" .
```

### Phase 2: Edit the YAML

All editorial changes go into `docs/database/table_metadata.yaml`. This is the single source of truth for table metadata.

**2.1 Adding a new table.** Append a new entry under `tables:` with all required fields:

```yaml
  new_table_name:
    purpose: "One-line description of what the table holds."
    source: "Which script or pipeline step produces it."
    primary_downstream: "Single primary consumer, or '—' if terminal."
    status: live                       # live | backup | test | empty | deprecated
    group: ne25                         # See valid group keys in generate_tables_md.py::GROUP_ORDER
    # Optional:
    # dictionary: "docs/data_dictionary/..."
    # notes: "Gotchas, history, caveats."
```

Required fields: `purpose`, `source`, `primary_downstream`, `status`, `group`. Optional: `dictionary`, `notes`.

**2.2 Updating an existing entry.** Edit in place. Keep one line per field. Be concise — the markdown cells are narrow.

**2.3 Valid `status` values:**

- `live` — actively written and read by a current pipeline
- `backup` — snapshot retained for reference (e.g., `*_backup_2025_11_08`)
- `test` — development artifact that should eventually be cleaned up
- `empty` — exists but holds 0 rows (placeholder or defunct)
- `deprecated` — superseded by another table but not yet removed

The generator will reject unknown status values.

**2.4 Valid `group` values:** See `GROUP_ORDER` in `scripts/documentation/generate_tables_md.py`. Currently:
`ne25`, `ne25_imputed`, `mn26`, `nsch`, `nhis`, `acs`, `calibration`, `historical`, `raking`, `crosswalks`, `metadata`, `cleanup`.

If a new pipeline needs a new group, add it to `GROUP_ORDER` and to `GROUP_INTROS` in the generator script. The generator rejects unknown groups — this is intentional so that tables are not silently dropped from the rendered output.

### Phase 3: Regenerate

Run the generator:

```bash
py scripts/documentation/generate_tables_md.py
```

Expected output on success:

```
[OK] Wrote docs\database\TABLES.md (97 tables, 12 groups).
```

If it exits non-zero, read the stderr carefully and go back to Phase 1.

### Phase 4: Verify

1. Read the regenerated `docs/database/TABLES.md`. Spot-check:
   - Total table count in the header matches the live DB.
   - Every group section has the tables you expect.
   - New or updated entries show the correct metadata.
   - The Cleanup Candidates section still makes sense.
   - Dictionary links (if any) resolve — e.g., `[dictionary](../data_dictionary/ne25_data_dictionary_full.md)` should point at an existing file.

2. Check the working tree:

   ```bash
   git diff docs/database/TABLES.md
   git diff docs/database/table_metadata.yaml
   git status --short
   ```

   The only tracked changes should be `docs/database/TABLES.md` and `docs/database/table_metadata.yaml`. If the generator or inventory script changed, include those too.

### Phase 5: Commit

Stage and commit both files together — the YAML is the source of truth, and the markdown is the generated derivative. They should never drift.

```bash
git add docs/database/TABLES.md docs/database/table_metadata.yaml
git commit -m "[Docs] Refresh database inventory (YYYY-MM-DD)"
```

**Do NOT push automatically.** Per the repo's standing rule, push requires explicit user authorization. Ask the user before pushing.

If this refresh also changed the pipeline enough to warrant updating `HANDOFF.md` or `docs/index.html`, suggest invoking `/refresh-handoff` or `/refresh-onboarding` separately. Do not bundle those changes into this commit.

## Constraints (non-negotiable)

- **`docs/database/table_metadata.yaml` is the single source of truth for metadata.** Never edit `docs/database/TABLES.md` by hand — it will be overwritten on the next regeneration.
- **The generator must exit 0 before committing.** Never commit a catalog where the DB and YAML disagree; fix the drift first.
- **Use the `python.db.connection.DatabaseManager` API** (context-managed) for DB introspection. `db.execute_query()` does NOT exist as a method.
- **Output path is `docs/database/TABLES.md`** — do not rename or move it without also updating sibling references (HANDOFF.md, CLAUDE.md, docs/index.html).
- **No emojis in the generated markdown** (per repo house rule).
- **Required YAML fields per entry:** `purpose`, `source`, `primary_downstream`, `status`, `group`.

## Anti-patterns (do not repeat)

- **Editing `TABLES.md` directly.** It is a generated artifact. Edit the YAML instead.
- **Silencing the orphan check** by adding placeholder YAML entries with `source: unknown`. If you don't know what a table is, grep the codebase and figure it out — that's the editorial work this catalog exists to preserve.
- **Mixing metadata updates with DB operations** (adding/dropping tables) in one commit. Split them: a commit that adds the table is separate from the commit that catalogs it.
- **Regenerating without verifying dictionary links.** If you add a `dictionary:` field, confirm the target file exists. Broken links in TABLES.md erode trust.
- **Pushing without explicit authorization.** Same rule as the sibling refresh skills.

## Success criteria

A successful refresh meets all of:

- `py scripts/documentation/generate_tables_md.py` exits 0
- `git diff docs/database/table_metadata.yaml` shows only intentional edits
- The rendered `TABLES.md`'s total table count matches the live DB's `SHOW TABLES` count
- Every new / renamed / status-changed table is reflected correctly
- Cleanup Candidates section lists all zero-row / backup / test / deprecated tables
- Dictionary links (if any) resolve to existing files
- The commit message includes the refresh date (`YYYY-MM-DD`)
- The user was asked about pushing before any push happened
