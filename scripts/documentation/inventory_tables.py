"""
Inventory every table in the Kidsights Data Platform DuckDB.

Used by scripts/documentation/generate_tables_md.py (which imports
build_inventory) and by the /refresh-database-inventory skill.

Run directly for a human-readable JSON dump:
    py scripts/documentation/inventory_tables.py > scripts/temp/inventory_tables.json
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.getcwd())

from python.db.connection import DatabaseManager


PK_CANDIDATES = {
    "pid",
    "record_id",
    "child_num",
    "HHID",
    "hhid",
    "state_fip",
    "year",
    "year_range",
    "table_name",
    "variable_name",
    "item",
    "imputation_m",
    "boot_b",
}


def _pk_hint(columns: list[str]) -> list[str]:
    return [c for c in columns if c in PK_CANDIDATES]


def build_inventory() -> dict:
    """Return a dict describing every table in the DuckDB database.

    Shape:
        {
            "db_path": str,
            "total_tables": int,
            "tables": {
                name: {
                    "row_count": int,
                    "column_count": int,
                    "first_10_columns": [str, ...],
                    "columns": [str, ...],
                    "pk_hint": [str, ...],
                }
            }
        }
    """
    db = DatabaseManager()
    out: dict = {"db_path": str(db.db_path), "tables": {}}
    with db.get_connection(read_only=True) as con:
        all_tables = sorted(r[0] for r in con.execute("SHOW TABLES").fetchall())
        out["total_tables"] = len(all_tables)

        for t in all_tables:
            try:
                row_cnt = con.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            except Exception as e:
                out["tables"][t] = {"error": f"row_count: {e}"}
                continue
            try:
                col_rows = con.execute(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_name = ? ORDER BY ordinal_position",
                    [t],
                ).fetchall()
                cols = [c[0] for c in col_rows]
            except Exception as e:
                out["tables"][t] = {"error": f"cols: {e}", "row_count": row_cnt}
                continue

            out["tables"][t] = {
                "row_count": row_cnt,
                "column_count": len(cols),
                "first_10_columns": cols[:10],
                "columns": cols,
                "pk_hint": _pk_hint(cols),
            }

    return out


def main() -> None:
    inv = build_inventory()
    print(json.dumps(inv, indent=2, default=str))


if __name__ == "__main__":
    main()
