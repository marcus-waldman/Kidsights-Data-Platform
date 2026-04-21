"""
Regenerate docs/database/TABLES.md from:
  - Live DB inventory (via scripts.documentation.inventory_tables.build_inventory)
  - Hand-written metadata (docs/database/table_metadata.yaml)

Exits non-zero if orphans are detected (DB table missing from YAML, or stale
YAML entry pointing at a missing table). The /refresh-database-inventory
skill surfaces these failures to the maintainer.

Run from project root:
    py scripts/documentation/generate_tables_md.py
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from pathlib import Path

import yaml

sys.path.insert(0, os.getcwd())

from scripts.documentation.inventory_tables import build_inventory


YAML_PATH = Path("docs/database/table_metadata.yaml")
OUTPUT_PATH = Path("docs/database/TABLES.md")


GROUP_ORDER = [
    ("ne25", "NE25 Pipeline (non-imputed)"),
    ("ne25_imputed", "NE25 Imputed Variables (M=5)"),
    ("mn26", "MN26 Pipeline"),
    ("nsch", "NSCH Pipeline"),
    ("nhis", "NHIS Pipeline"),
    ("acs", "ACS Pipeline"),
    ("calibration", "IRT Calibration"),
    ("historical", "Historical Calibration Data"),
    ("raking", "Raking Targets & Bootstrap Replicates"),
    ("crosswalks", "Geographic Crosswalks"),
    ("metadata", "Metadata / Catalog Tables"),
]

CLEANUP_GROUP = ("cleanup", "Cleanup Candidates")


GROUP_INTROS = {
    "ne25": (
        "Nebraska 2025 REDCap survey pipeline. Entry point: `run_ne25_pipeline.R`. "
        "`ne25_transformed` is the canonical analytic table; see its dictionary link below."
    ),
    "ne25_imputed": (
        "Multiple-imputation outputs (M=5) from `scripts/imputation/ne25/`. Each table "
        "stores only the imputed rows (observed values remain in the base table). Join by "
        "`(pid, record_id, imputation_m)`."
    ),
    "mn26": (
        "Minnesota 2026 REDCap pipeline. Currently runs in `--skip-database` test mode — "
        "no `mn26_*` tables expected in the DB yet."
    ),
    "nsch": (
        "National Survey of Children's Health (2016-2023). Produced by `scripts/nsch/process_all_years.py`. "
        "Note the year-suffix naming inconsistency (2021/2022 use `nsch_{year}`; other years use `nsch_{year}_raw`)."
    ),
    "nhis": (
        "National Health Interview Survey multi-year extracts (2019-2024) from IPUMS."
    ),
    "acs": (
        "IPUMS USA ACS extracts + DDI metadata registry. Consumed by the raking pipeline."
    ),
    "calibration": (
        "Multi-study IRT calibration dataset (9,319 post-QA records across 6 studies). "
        "`calibration_dataset_2020_2025` is the canonical wide format; the `_with_flags`, "
        "`_full_with_flags`, and `_restructured` variants serve QA and Mplus-syntax-generation "
        "workflows respectively."
    ),
    "historical": (
        "Historical Kidsights calibration records imported from the KidsightsPublic package "
        "(NE20, NE22, USA24)."
    ),
    "raking": (
        "Population-representative targets and bootstrap replicate infrastructure feeding "
        "the NE25 raking pipeline (scripts 01-34) and the MIBB variance framework (scripts 35-36)."
    ),
    "crosswalks": (
        "ZCTA-based geographic crosswalks. `geo_zip_to_*` tables are loaded by "
        "`pipelines/python/load_geographic_crosswalks.py`; `ne_zip_county_crosswalk` is a "
        "legacy Nebraska-specific array format kept for the NE25 eligibility path."
    ),
    "metadata": (
        "Catalog and provenance tables not tied to a single pipeline."
    ),
    "cleanup": (
        "Zero-row, backup, test, or deprecated tables flagged for removal. HANDOFF.md's "
        "DB Drift section tracks the larger cleanup initiative."
    ),
}


def _escape_md_cell(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def _fmt_row_count(n: int) -> str:
    if n == 0:
        return "0"
    return f"{n:,}"


def _render_group_section(
    title: str,
    intro: str,
    entries: list[tuple[str, dict, dict]],
    include_status: bool,
) -> str:
    """Render a single group section. `entries` is a list of (name, yaml_meta, db_info)."""
    lines = [f"## {title}", "", intro, ""]
    if include_status:
        header = "| Table | Rows | Cols | Source | Purpose | Used by | Status |"
        sep = "|---|---:|---:|---|---|---|---|"
    else:
        header = "| Table | Rows | Cols | Source | Purpose | Used by |"
        sep = "|---|---:|---:|---|---|---|"
    lines.append(header)
    lines.append(sep)

    for name, ym, db_info in entries:
        rows = _fmt_row_count(db_info["row_count"])
        cols = db_info["column_count"]
        purpose = ym["purpose"]
        if "dictionary" in ym:
            # TABLES.md lives at docs/database/TABLES.md, so paths starting with
            # "docs/" need one ".." to reach the docs root.
            rel = ym["dictionary"]
            if rel.startswith("docs/"):
                rel = "../" + rel[len("docs/") :]
            purpose = f"{purpose} See [dictionary]({rel})."
        source = ym["source"]
        if "notes" in ym:
            # Append notes in italics to the Used-by cell so they stay visible but compact.
            notes = f" _Note: {ym['notes']}_"
        else:
            notes = ""
        downstream = ym["primary_downstream"] + notes
        cells = [
            f"`{name}`",
            rows,
            str(cols),
            _escape_md_cell(source),
            _escape_md_cell(purpose),
            _escape_md_cell(downstream),
        ]
        if include_status:
            cells.append(ym["status"])
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    inv = build_inventory()
    with YAML_PATH.open("r", encoding="utf-8") as f:
        meta = yaml.safe_load(f)
    yaml_tables = meta["tables"]

    yaml_names = set(yaml_tables.keys())
    db_names = set(inv["tables"].keys())

    missing = db_names - yaml_names
    stale = yaml_names - db_names
    if missing or stale:
        sys.stderr.write("[refresh-database-inventory] Orphan / stale check FAILED:\n")
        if missing:
            sys.stderr.write(f"  DB tables missing from YAML ({len(missing)}):\n")
            for t in sorted(missing):
                info = inv["tables"][t]
                sys.stderr.write(
                    f"    - {t} ({info.get('row_count', '?')} rows, "
                    f"{info.get('column_count', '?')} cols)\n"
                )
        if stale:
            sys.stderr.write(f"  YAML entries with no live table ({len(stale)}):\n")
            for t in sorted(stale):
                sys.stderr.write(f"    - {t}\n")
        sys.stderr.write(
            "\n  Fix docs/database/table_metadata.yaml before regenerating TABLES.md.\n"
        )
        sys.exit(1)

    # Group tables by YAML `group` field.
    by_group: dict[str, list[tuple[str, dict, dict]]] = {}
    for name, ym in yaml_tables.items():
        db_info = inv["tables"][name]
        by_group.setdefault(ym["group"], []).append((name, ym, db_info))
    for g in by_group:
        by_group[g].sort(key=lambda row: row[0])

    # Validate every group key we emit is known.
    known_groups = {g for g, _ in GROUP_ORDER} | {CLEANUP_GROUP[0]}
    unknown = [g for g in by_group if g not in known_groups]
    if unknown:
        sys.stderr.write(
            f"[refresh-database-inventory] Unknown group(s) in YAML: {unknown}\n"
            f"  Update GROUP_ORDER in scripts/documentation/generate_tables_md.py.\n"
        )
        sys.exit(2)

    today = _dt.date.today().isoformat()
    total = inv["total_tables"]

    parts = [
        "# Database Table Catalog",
        "",
        f"**Snapshot date:** {today}",
        f"**Database:** `data/duckdb/kidsights_local.duckdb`",
        f"**Total tables:** {total}",
        "**Regenerate via:** `/refresh-database-inventory` skill "
        "(see `.claude/skills/refresh-database-inventory/SKILL.md`)",
        "**Source of truth for metadata:** "
        "[`docs/database/table_metadata.yaml`](table_metadata.yaml)",
        "",
        "---",
        "",
        "This catalog lists every table in the platform's DuckDB database, grouped by pipeline. "
        "For each table: row count and column count come from live DB introspection; the "
        "source, primary downstream consumer, and status come from the hand-written YAML "
        "config linked above.",
        "",
        "**Status values:**",
        "- `live` — actively written and read by a current pipeline",
        "- `backup` — snapshot retained for reference",
        "- `test` — development artifact",
        "- `empty` — exists but holds 0 rows (may be a placeholder or defunct)",
        "- `deprecated` — superseded but not yet removed",
        "",
        "---",
        "",
    ]

    # Main groups (exclude cleanup — rendered at the end with a leaner column set).
    for group_key, title in GROUP_ORDER:
        entries = by_group.get(group_key, [])
        if not entries:
            # Skip empty groups (e.g., mn26 before it ships DB tables).
            continue
        parts.append(
            _render_group_section(
                title=title,
                intro=GROUP_INTROS[group_key],
                entries=entries,
                include_status=True,
            )
        )

    # Cleanup section (always rendered at the end, if entries exist).
    cleanup_entries = by_group.get(CLEANUP_GROUP[0], [])
    if cleanup_entries:
        parts.append("---")
        parts.append("")
        parts.append(
            _render_group_section(
                title=CLEANUP_GROUP[1],
                intro=GROUP_INTROS["cleanup"],
                entries=cleanup_entries,
                include_status=True,
            )
        )

    # Footer
    parts.extend(
        [
            "---",
            "",
            "## Regenerating this catalog",
            "",
            "When a table is added, dropped, or its metadata changes:",
            "",
            "1. Edit [`docs/database/table_metadata.yaml`](table_metadata.yaml) — the hand-written source.",
            "2. Invoke `/refresh-database-inventory` (the skill runs the generator and surfaces orphan/stale warnings).",
            "3. Commit both the YAML edits and the regenerated `TABLES.md` together.",
            "",
            f"*Generated {today} by `scripts/documentation/generate_tables_md.py`.*",
            "",
        ]
    )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text("\n".join(parts), encoding="utf-8")
    print(f"[OK] Wrote {OUTPUT_PATH} ({total} tables, {len(GROUP_ORDER) + 1} groups).")


if __name__ == "__main__":
    main()
