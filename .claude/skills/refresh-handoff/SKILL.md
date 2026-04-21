---
name: refresh-handoff
description: Surgically update `HANDOFF.md` (root) — the maintainer-transition synthesis doc — so its volatile fields (in-flight work, drift items, last-audit commit, snapshot date, uncommitted-work breadcrumb) reflect current reality. Invoke during the pre-handoff window whenever material changes land that affect what the incoming maintainer needs to know. Sister skill to `/refresh-onboarding` (which regenerates the public Pages page); this one updates the internal markdown.
---

# Refresh HANDOFF.md

## When to invoke

Run this skill during the active pre-handoff window when **any** of the following changed:

- A material commit lands on `main` (status of in-flight work shifts; new feature; bug fix that resolves a drift item)
- A previously flagged DB drift item gets resolved (or a new one surfaces)
- The pre-existing uncommitted-work breadcrumb (`scripts/raking/ne25/utils/calibrate_weights_simplex_factorized.exe` or others) gets committed, discarded, or changes
- Active in-flight workstream changes (e.g., MIBB Bucket 3 finishes, new initiative starts)
- Outgoing maintainer's contact info or transition timeline shifts
- A new pipeline lands or is renamed
- `git log origin/main..HEAD` shows >5 commits since the last refresh
- Roughly weekly during active pre-handoff work, regardless of specific changes

**Do NOT invoke for:**
- Trivial doc edits or single-line code tweaks
- Changes that don't affect what an incoming maintainer needs to know on day 1
- Anything where you're not sure — over-refreshing is fine; under-refreshing leaves the doc stale at the moment it matters most

## Sister skill

**`/refresh-onboarding`** updates `docs/index.html` (the public-facing GitHub Pages landing). Use it when the *visual snapshot* should also reflect current state. The two refresh skills are intentionally decoupled:

- HANDOFF.md changes more often (during active pre-handoff work)
- onboarding.html changes less often (only when a public-visible thing changes — new pipeline, deferred-work shift, major status change)

A typical cadence: refresh HANDOFF.md weekly during active work; refresh onboarding.html only when the visual page would meaningfully change.

## What this skill produces

A surgically-updated `HANDOFF.md` where:
- Volatile fields reflect today's state
- Stable prose sections (Tips, Recommended First-Week Plan, Knowledge Areas, Reading Order) are **untouched**
- The doc retains its hand-crafted voice — this is not a regeneration; it's a precision update

## Workflow

### Phase 1: Gather current state

Run in parallel where possible. **Re-verify everything against the source** — never trust the previous HANDOFF.md content as a starting point for facts.

**1.1 Recent commits.** Run `git log origin/main..HEAD --oneline` and `git log -10 --oneline` to see what's landed since the last HANDOFF refresh. Identify commits that signal state change:
- `[Feature]` / `[Refactor]` — likely changes in-flight work or pipeline status
- `[Fix]` — may resolve a drift item
- `[Docs]` — may change reading order or doc references

**1.2 Current commit hash for "Last audit commit" or equivalent reference.** Run `git rev-parse --short HEAD` to get the most recent commit. Decide whether to update the "Last audit commit" line in the header, or replace it with a more durable "Last updated" date field.

**1.3 Database state — verify the Critical DB Drift section.** For each item currently listed in HANDOFF.md's drift table, re-verify against the live DB:

```python
import sys, os
sys.path.insert(0, os.getcwd())
from python.db.connection import DatabaseManager
db = DatabaseManager()
with db.get_connection(read_only=True) as con:
    # Check each currently-listed drift item
    rows = con.execute("SELECT COUNT(*) FROM raking_targets_ne25").fetchone()
    # ... etc.
```

For each drift item, classify:
- **Still present** — keep in the table
- **Resolved** — remove from the table; consider noting it briefly under a "Recently resolved drift" sub-section if the resolution was significant
- **New** — add to the table with the same format (claim / actual / suspected cause)

If multiple items get resolved, the table can shrink — that's a positive signal worth communicating.

**1.4 Active in-flight work.** Re-check:
- `todo/*.md` for the most-recently-modified active todo file (`ls -t todo/*.md | head -3`)
- Recent `[Feature]`/`[Refactor]` commits to see which workstream is dominant
- The "Active In-Flight Work" section in HANDOFF.md to compare against current reality

If the dominant workstream changed (e.g., MIBB Bucket 3 finished and now MN26 raking is active), rewrite that section. If it's the same workstream but with progress (e.g., Bucket 3 went from "1,000 refits in progress" to "complete; results being analyzed"), update the status line within the existing section.

**1.5 Uncommitted work breadcrumb.** Run `git status --short` and identify any uncommitted files that should be flagged in HANDOFF.md's "Uncommitted Work in Repo at Handoff" section. Update or remove the breadcrumb based on current state.

**1.6 Pipeline status table.** Skim CLAUDE.md's `## Current Status` section. If any pipeline's status changed (Production ↔ In-flight ↔ Deferred), update the corresponding row in HANDOFF.md's "What's Running in Production" table.

**1.7 Other volatile fields.**
- Footer snapshot date (always update to today's ISO date)
- Hero "Snapshot date" line (always update)
- "Last audit commit" reference (update to current HEAD or replace with "Last updated: YYYY-MM-DD")

### Phase 2: Identify what changed

Before editing, write a short mental list:
- Volatile fields that need updating: [list]
- Stable sections to NOT touch: Tips, Recommended First-Week Plan, Knowledge Areas, Reading Order, Documentation Map subsection structure, Doc Audit Outcomes (historical), Credentials section (mostly stable)

If the changes are extensive enough that you're rewriting >40% of the doc, you're past "refresh" territory — pause and ask the user whether the HANDOFF doc itself needs structural revision, not just a refresh.

### Phase 3: Surgically edit HANDOFF.md

**Use the `Edit` tool, not `Write`.** Each volatile field gets its own targeted edit. This preserves the carefully-crafted prose elsewhere in the doc.

Typical edit pattern:

```
Edit: HANDOFF.md
  old_string: "**Snapshot date:** 2026-04-20"
  new_string: "**Snapshot date:** 2026-MM-DD"

Edit: HANDOFF.md
  old_string: "**Last audit commit:** `6fe3092` ..."
  new_string: "**Last updated:** YYYY-MM-DD"

Edit: HANDOFF.md
  old_string: <drift table entry that's been resolved>
  new_string: <removed or updated>
```

Drift table additions: insert new rows in the same format as existing entries (claim | actual | suspected cause).

In-flight section: rewrite only the bulleted status lines, not the surrounding header/framing prose.

### Phase 4: Verify and commit

1. Read the updated HANDOFF.md top-to-bottom (or at minimum the sections you touched). Check:
   - Snapshot date matches today
   - Drift table has only currently-real items
   - In-flight section reflects today's headline workstream
   - No accidental edits to stable prose
   - No broken markdown (renumbered lists still consistent, tables still aligned, etc.)

2. Stage and commit:
   ```bash
   git add HANDOFF.md
   git commit -m "[Docs] Refresh HANDOFF.md (snapshot YYYY-MM-DD)"
   ```

3. **Do NOT push automatically.** HANDOFF.md changes are low-risk but per the repo's standing rule, push requires explicit user authorization. Ask the user before pushing.

4. If the changes are material enough to also affect the public Pages page (new pipeline, status change, drift resolution), suggest also invoking `/refresh-onboarding`.

## Constraints (non-negotiable)

- **Output path is `HANDOFF.md` at the repo root.** Do not move, rename, or split it.
- **Use `Edit`, not `Write`.** Surgical edits preserve the carefully-crafted prose. Full regeneration is for `/refresh-onboarding` (which targets a different artifact with a stable structure).
- **Snapshot date and footer date must match today's ISO date.** Both fields together — don't update one and miss the other.
- **Drift items must be re-verified.** Never copy forward without checking against the live DB.
- **Stable sections are stable.** Tips, Knowledge Areas, Recommended First-Week Plan, Doc Audit Outcomes, Reading Order — do not touch unless there's a specific reason (e.g., a doc was renamed, a new tip is genuinely needed).
- **No emojis in body text** (per repo CLAUDE.md house rule).

## Anti-patterns (do not repeat)

- **Treating HANDOFF.md like a fresh document.** It was written deliberately at the original handoff moment; respect the prose. This skill updates fields, not voice.
- **Leaving stale drift items.** If a drift item was resolved, remove it from the table — don't leave it with a note. The table should reflect current reality, not historical state.
- **Forgetting to update the footer snapshot date.** It's the most-overlooked field because it's at the bottom; agents tend to update only the hero date and miss the footer.
- **Updating the doc but not committing.** A staged-but-uncommitted HANDOFF.md is worse than not updating at all — the working tree is dirty and the actual repo state is stale.
- **Auto-pushing.** Per repo rule, push requires explicit user authorization. Always ask after committing.
- **Refreshing HANDOFF.md AND onboarding.html together blindly.** They have different update cadences. Refresh HANDOFF.md weekly during active work; refresh onboarding.html only when a public-visible thing changes.

## Success criteria

A successful refresh meets all of:
- Snapshot date in hero AND footer match today's ISO date
- "Last audit commit" / "Last updated" reflects the current state
- Drift table contains only currently-real items (verified against live DB)
- In-flight section reflects today's headline workstream
- Pipeline status table matches CLAUDE.md's current state
- Uncommitted-work breadcrumb matches `git status --short`
- Stable prose sections were not modified
- A commit landed locally with a clear message including the snapshot date
- The user was asked about pushing before any push happened
