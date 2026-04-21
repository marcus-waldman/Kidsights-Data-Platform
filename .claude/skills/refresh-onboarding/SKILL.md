---
name: refresh-onboarding
description: Regenerate `docs/index.html` (the GitHub Pages onboarding/orientation landing page) from current platform state — DB counts, CLAUDE.md status, recent commits, and known drift items. Invoke when the platform changes materially (new pipeline added, deferred work shifts, major status changes, DB drift items resolved or new ones surfaced) so the public-facing snapshot stays accurate.
---

# Refresh the Kidsights Data Platform Onboarding Page

## When to invoke

Run this skill when **any of the following has changed since the last regeneration**:

- A pipeline was added, deprecated, or had its status change (Production ↔ In-flight ↔ Deferred)
- CLAUDE.md's "Current Status" section materially changed (new sections, shifted dates)
- A previously flagged DB drift item was resolved (or a new one surfaced)
- The active in-flight work is now different (e.g., MIBB Bucket 3 finished, new initiative started)
- Setup requirements changed (new env var, different R/Python version, new API)
- The outgoing-maintainer identity changed (new contact info)
- More than ~3 months passed since the last refresh, regardless of changes (the snapshot date shouldn't drift more than a quarter)

**Do NOT run** for trivial changes (record-count drift, minor doc edits, single-pipeline tweaks). The page is a *snapshot* — small drift is acceptable; large drift triggers regeneration.

## What this skill produces

A fresh `docs/index.html` that is:
- Self-contained (inline CSS, inline SVG, no JS dependencies beyond an optional TOC scrollspy)
- Editorial aesthetic (deep navy + gold on warm cream; auto-dark-mode supported)
- Single-page scrollable layout with sticky TOC sidebar on desktop
- All data in the page reflects the current platform state, not a stale snapshot

## Workflow

### Phase 1: Gather current state

Run these in parallel where possible. **Re-verify everything against the source** — never trust the previous `docs/index.html` content as a starting point for facts.

**1.1 Pipeline status from CLAUDE.md.** Read `CLAUDE.md`, specifically the `## Current Status` section. For each of the 8 pipelines, extract:
- Name (e.g., NE25, MN26, ACS, NHIS, NSCH, Raking Targets, Imputation, IRT Calibration)
- Status verdict (Production, In development, Deferred, Drift flagged, etc.)
- Brief one-line purpose
- Entry-point command (run script path)

If new pipelines have been added since the last refresh, include them. If any have been removed, drop them.

**1.2 Database state.** Run a Python script via the `python.db.connection.DatabaseManager` API to verify:
- Total table count
- Pipeline-specific row counts (`ne25_raw`, `ne25_transformed`, etc.)
- Any tables flagged in the last refresh's drift section — are they still missing/wrong, or have they been resolved?
- Any new zero-row, defunct, backup, or duplicate tables that warrant a fresh drift flag?

Use the pattern (note: `db.execute_query()` does NOT exist — use the context manager):

```python
import sys, os
sys.path.insert(0, os.getcwd())
from python.db.connection import DatabaseManager
db = DatabaseManager()
with db.get_connection(read_only=True) as con:
    rows = con.execute("SELECT COUNT(*) FROM ne25_transformed").fetchone()
```

Save your verification queries to `scripts/temp/factcheck_onboarding.py` so the next refresh can reuse and extend them.

**1.3 Active in-flight work.** Look at:
- `todo/*.md` files (recent dates indicate active work) — currently `todo/ne25_weights_roadmap.md`, `todo/mn26_pipeline_plan.md` were the active ones
- `git log -20 --oneline` for recent commit subjects (`[Feature]`, `[Refactor]` tags signal active development; `[Docs]` and `[Fix]` are smaller)
- Check `git status` for any uncommitted in-flight modifications

Identify the **single most prominent active workstream** for the in-flight callout box. Don't list every small task — pick the headline initiative.

**1.4 Deferred work.** Look at CLAUDE.md for explicit "deferred" mentions and any `Deferred:` lines in pipeline status sections.

**1.5 Drift items (the rose-colored callout).** This is the most consequential section. Compare what CLAUDE.md / per-pipeline docs claim against actual DB state:

| Doc claim type | How to verify |
|---|---|
| Table existence | `SHOW TABLES` and look for the claimed table name |
| Row count | `SELECT COUNT(*) FROM table` |
| Column existence | `SELECT column_name FROM information_schema.columns WHERE table_name='X'` |
| Pipeline output count | Compare doc-stated count against actual row count |

Drift items must be **specific and actionable**: "X claimed N, actual is M, suspected cause: Y." Generic "docs are out of date" is not useful.

If a previously-flagged drift item has been resolved (table now exists, count now matches), **remove it from the page** — don't keep historical drift forever.

**1.6 Setup info (rarely changes).** Confirm the env var list in `.env.template` matches what the page documents. If new vars were added (or removed), update the setup section accordingly.

**1.7 Outgoing maintainer / contact info.** This may change if leadership transitions. Check the current `HANDOFF.md` Contact section for the canonical info; the onboarding page should match.

### Phase 2: Compose the page sections

Build the content brief for the `visual-explainer` skill. The page structure is fixed; only the content within sections updates. Keep these sections in this order:

1. **Hero** — title, one-sentence pitch, snapshot date (today's ISO date), repo URL, key meta (snapshot date, source-of-truth doc, pipeline count)
2. **The N pipelines** — visual grid; one card per pipeline; status badge per card
3. **Architecture diagram** — inline SVG; data flow from sources → R/Python (with Feather between) → DuckDB → outputs. Update only if the architecture itself has changed (new source type, new processing layer, new output type). Directly below the SVG legend, include a one-sentence paragraph pointing readers from the DuckDB cylinder to the full table catalog (`docs/database/TABLES.md`) and its YAML source of truth — that pointer is how a reader gets from "what's in the DuckDB?" (which the diagram raises) to "here's the answer" without digging.
4. **Reading order** — typically 5 numbered cards: HANDOFF → CLAUDE → INSTALLATION_GUIDE → QUICK_REFERENCE → per-pipeline. Update if doc names changed.
5. **Project skills** — grid or table listing every skill in `.claude/skills/`. Each entry shows invocation (e.g., `/refresh-onboarding`), one-line purpose, trigger conditions, and a link to the SKILL.md on GitHub via the `blob/HEAD/` pattern. If `.claude/skills/` contains a directory that isn't rendered here, the inventory is stale — treat it as a drift item and add the row. The mirrored section on HANDOFF.md (`## Project-Scoped Claude Skills`) must stay in parity. The `/refresh-database-inventory` card must also expose a direct "Catalog →" link to `docs/database/TABLES.md` so the public catalog is reachable from this section, not only from section 07.
6. **Active in-flight callout** — single dominant workstream
7. **Deferred work callout** — bullet list
8. **Critical DB drift** — numbered list of specific items. End the section with an explicit pointer to `docs/database/TABLES.md` (catalog) and `docs/database/table_metadata.yaml` (source of truth) so readers landing here have a one-click path to the full table inventory, not just the drift subset.
9. **Tech stack** — chip grid (R + Python + DuckDB + Mplus + Arrow + CmdStan)
10. **Setup quick-glance** — 5 numbered steps
11. **Contact card** — outgoing maintainer
12. **Footer** — snapshot date + regen instruction (this skill name)

**Do not change the styling, palette, or layout** unless the user explicitly asks for an aesthetic update. Consistency across regenerations is a feature.

### Phase 3: Regenerate via visual-explainer

Invoke the `visual-explainer` skill with a prompt that:

- Specifies output path: `docs/index.html` (NOT `~/.agent/diagrams/`)
- Includes all the section content from Phase 2 verbatim
- Specifies the constraints: editorial aesthetic, inline SVG architecture diagram, no external JS dependencies (per the no-CDN-libs rule established for this page), preserve the existing palette (deep navy `#1e3a5f` + warm gold `#b88b1f` on warm cream `#faf6ef` background)
- States the snapshot date in ISO format (YYYY-MM-DD) and updates the footer regen instruction to mention this skill name

**Link pattern for doc references (IMPORTANT):** Jekyll is disabled for Pages, so `.md` files served via Pages download as raw text instead of rendering. All in-page references to markdown files must use **absolute GitHub blob URLs** so they render nicely on github.com:

- Blob (files): `https://github.com/marcus-waldman/Kidsights-Data-Platform/blob/HEAD/<path>` — e.g., `blob/HEAD/CLAUDE.md`, `blob/HEAD/HANDOFF.md`, `blob/HEAD/docs/setup/INSTALLATION_GUIDE.md`
- Tree (directories): `https://github.com/marcus-waldman/Kidsights-Data-Platform/tree/HEAD/<path>` — e.g., `tree/HEAD/docs` for the per-pipeline docs directory
- Use `/blob/HEAD/` and `/tree/HEAD/` (not `/blob/main/`) — `HEAD` follows the default branch, so links survive a future `main` → `master` rename or a release-branch cut
- Open reading-order cards and other primary-navigation links in a new tab: `target="_blank" rel="noopener noreferrer"` — so the orientation page stays visible while readers consume the doc
- Inline mentions (callout lists, footer code references) can open in same tab or new tab at your judgment

Never use Pages-relative paths like `setup/INSTALLATION_GUIDE.md` or `docs/CLAUDE.md` — those resolve against the Pages URL and return raw markdown.

**Exception — Quarto-rendered HTML under `/docs`:** Self-contained HTML files (`embed-resources: true`) committed alongside their `.qmd` sources SHOULD use relative Pages paths like `mn26/pipeline_guide.html`. Pages serves those directly as rendered pages; a GitHub blob URL for the same file would show HTML source, not the rendered view. The MN26 card in section 01 uses this pattern to link `mn26/pipeline_guide.html` and `mn26/pipeline_slides.html`. Each new Quarto doc added under `/docs` with a `.gitignore` exception should be linked the same way. Preserve existing such links on regeneration; do not rewrite them to blob URLs.

For reference on the existing aesthetic and structure, the agent can read the current `docs/index.html` before invoking visual-explainer — but should treat it as a stylistic template, not a content source.

### Phase 4: Verify and commit

1. Open `docs/index.html` in a browser (`start docs/index.html` on Windows) and visually verify:
   - All status badges match the new state
   - Architecture diagram renders without overflow
   - Drift section shows current items, not stale ones
   - Snapshot date in hero and footer matches today
   - No broken layouts, no console errors

2. Stage and commit:
   ```bash
   git add docs/index.html
   git commit -m "[Docs] Refresh onboarding page (snapshot YYYY-MM-DD)"
   ```

3. **Push to origin/main** (with explicit user authorization — Pages will rebuild automatically once the commit lands on the default branch). Verify build succeeds:
   ```bash
   git push origin main
   gh api repos/marcus-waldman/Kidsights-Data-Platform/pages/builds/latest
   ```

4. Confirm the live URL `https://marcus-waldman.github.io/Kidsights-Data-Platform/` reflects the new snapshot.

## Constraints (non-negotiable)

- **Output path is `docs/index.html`**, not `~/.agent/diagrams/anything.html`. The Pages-served file is the only deliverable.
- **No external JavaScript dependencies** beyond the small inline TOC scrollspy. No Mermaid, no Chart.js, no anime.js. Architecture diagram must be inline SVG.
- **No emojis in body text** (per repo CLAUDE.md house rule)
- **`.gitignore` exception** for `docs/index.html` already exists (line near "Pages landing page"). Don't remove it.
- **Snapshot date must be today's date** in ISO format. Never copy a stale date from the previous version.
- **Drift items must be re-verified** against the live DB; do not copy them forward without checking.

## Anti-patterns (do not repeat)

- Treating the previous `docs/index.html` as the source of truth for facts. It is a *snapshot* — facts may have drifted since it was generated.
- Leaving a "Snapshot date" in the footer that doesn't match what's in the hero.
- Listing pipelines that no longer exist or omitting newly added ones.
- Including drift items that have already been resolved (e.g., the table now exists but the page still flags it as missing).
- Adding new sections without considering whether the page is still scannable in 5 minutes.
- Changing the palette or aesthetic on a routine refresh — that's a stylistic decision, not a content refresh.

## Success criteria

A fresh refresh is successful when:
- The snapshot date matches today
- Every pipeline status badge matches CLAUDE.md
- Every drift item has been re-verified against the live DB (resolved items removed, new items added)
- The active in-flight callout reflects the actual current headline workstream
- The page renders cleanly at the live URL
- The commit message mentions the snapshot date so future maintainers can find it via `git log`
