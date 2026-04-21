"""
Script 36: Store Bayesian-bootstrap weights in long-format DuckDB table
========================================================================

Consolidates all M*B per-(m, b) weight feathers produced by script 35
into the long-format ne25_raked_weights_boot DuckDB table created by
pipelines/python/init_raked_weights_boot_table.py.

Inputs:
  - data/raking/ne25/ne25_weights_boot/weights_m{m}_b{b}.feather (M*B files)
  - DuckDB table ne25_raked_weights_boot

Output:
  - ne25_raked_weights_boot populated with M*B*N rows:
      (pid, record_id, study_id, imputation_m, boot_b, calibrated_weight)

Idempotency: DELETEs existing rows before INSERT so re-runs produce a
clean state.

History: the earlier R version (git history:
scripts/raking/ne25/36_store_bootstrap_weights_long.R, commit 16cafd4)
used DBI::dbAppendTable in a 20-chunk loop. At NE25 scale (2.6M rows
across 1,000 feathers), that path segfaulted the R process partway
through the insert on Windows. This Python implementation uses PyArrow
natively, consolidating all feathers into a single Table and inserting
via DuckDB's registered-relation path. One INSERT SELECT, ~10 seconds,
no per-chunk R round-trips to destabilize.

Step 6 of 8 for Bucket 3 (MI + Bayesian bootstrap).
"""

from __future__ import annotations

import os
import re
import time
from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.feather as ft


# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
M = 5       # number of imputations (must match production imputation pipeline)
B = 200     # number of bootstrap draws per imputation (must match script 35)

BOOT_DIR = Path("data/raking/ne25/ne25_weights_boot")
DB_PATH = os.environ.get("KIDSIGHTS_DB_PATH") or "data/duckdb/kidsights_local.duckdb"
TABLE_NAME = "ne25_raked_weights_boot"

REQUIRED_COLS = ["pid", "record_id", "study_id", "imputation_m",
                 "boot_b", "calibrated_weight"]


def main() -> None:
    print()
    print("=" * 57)
    print("SCRIPT 36: Store Bayesian-bootstrap weights in DuckDB")
    print("=" * 57)
    print()
    print(f"Expected: {M} imputations x {B} bootstrap draws = {M*B} feather files")
    print()

    # ------------------------------------------------------------------------
    # [1] Enumerate and validate feather files
    # ------------------------------------------------------------------------
    print("[1] Scanning bootstrap weight feathers...")
    expected = []
    missing = []
    for b in range(1, B + 1):
        for m in range(1, M + 1):
            p = BOOT_DIR / f"weights_m{m}_b{b}.feather"
            (expected if p.exists() else missing).append(p)

    print(f"    Found:   {len(expected)} / {M*B}")
    if missing:
        print(f"    Missing: {len(missing)} feather files")
        print(f"    First few missing: "
              f"{', '.join(p.name for p in missing[:5])}")
        raise SystemExit("Cannot proceed with missing feathers. "
                         "Re-run script 35 first.")
    print("    [OK] All expected feathers present")
    print()

    # ------------------------------------------------------------------------
    # [2] Consolidate feathers into a single PyArrow Table
    # ------------------------------------------------------------------------
    print("[2] Loading feathers into arrow table...")
    t0 = time.time()
    tables = [ft.read_table(p) for p in expected]
    arrow_all = pa.concat_tables(tables)
    print(f"    concat done: {arrow_all.num_rows:,} rows "
          f"in {time.time() - t0:.1f} s")

    # Validate schema: every feather must have REQUIRED_COLS
    cols = set(arrow_all.schema.names)
    missing_cols = [c for c in REQUIRED_COLS if c not in cols]
    if missing_cols:
        raise SystemExit(f"Feathers missing columns: {missing_cols}")

    # Cast pid/record_id to int32 (writers emit them as float64 from R)
    schema = arrow_all.schema
    if schema.field("pid").type != pa.int32():
        arrow_all = arrow_all.set_column(
            schema.get_field_index("pid"), "pid",
            arrow_all.column("pid").cast(pa.int32())
        )
    if arrow_all.schema.field("record_id").type != pa.int32():
        arrow_all = arrow_all.set_column(
            arrow_all.schema.get_field_index("record_id"), "record_id",
            arrow_all.column("record_id").cast(pa.int32())
        )

    # Reorder to match DB schema
    arrow_all = arrow_all.select(REQUIRED_COLS)

    # Sanity check: detect metadata corruption from partial writes (e.g., a
    # worker that wrote a feather with garbage imputation_m). These block
    # the PK insert; fail fast with an actionable message.
    pat = re.compile(r"weights_m(\d+)_b(\d+)\.feather$")
    for tbl, path in zip(tables, expected):
        mm_expected, bb_expected = map(int, pat.search(path.name).groups())
        col_m = tbl.column("imputation_m").to_pylist()
        col_b = tbl.column("boot_b").to_pylist()
        if (set(col_m) != {mm_expected}) or (set(col_b) != {bb_expected}):
            raise SystemExit(
                f"Corrupt feather {path.name}: filename says "
                f"(m={mm_expected}, b={bb_expected}) but columns contain "
                f"m={sorted(set(col_m))[:3]} b={sorted(set(col_b))[:3]}. "
                f"Delete the file and re-run script 35 to regenerate."
            )

    # ------------------------------------------------------------------------
    # [3] Bulk-load into DuckDB
    # ------------------------------------------------------------------------
    print("[3] Writing to DuckDB...")
    print(f"    Database: {DB_PATH}")

    con = duckdb.connect(DB_PATH)
    try:
        tables_in_db = [
            r[0] for r in con.execute("SHOW TABLES").fetchall()
        ]
        if TABLE_NAME not in tables_in_db:
            raise SystemExit(
                f"Table '{TABLE_NAME}' missing. "
                f"Run pipelines/python/init_raked_weights_boot_table.py first."
            )

        n_before = con.execute(
            f"SELECT COUNT(*) FROM {TABLE_NAME}"
        ).fetchone()[0]
        print(f"    Rows before: {n_before:,}")

        t1 = time.time()
        con.execute(f"DELETE FROM {TABLE_NAME}")
        print(f"    DELETE done in {time.time() - t1:.1f} s")

        t2 = time.time()
        con.register("boot_arrow", arrow_all)
        con.execute(f"INSERT INTO {TABLE_NAME} SELECT * FROM boot_arrow")
        print(f"    INSERT done in {time.time() - t2:.1f} s")

        n_after = con.execute(
            f"SELECT COUNT(*) FROM {TABLE_NAME}"
        ).fetchone()[0]
        print(f"    Rows after:  {n_after:,}")

        if n_after != arrow_all.num_rows:
            raise SystemExit(
                f"Row count mismatch: arrow had {arrow_all.num_rows:,} rows "
                f"but table now has {n_after:,}"
            )

        n_unique = con.execute(f"""
            SELECT COUNT(*) FROM (
              SELECT DISTINCT pid, record_id, imputation_m, boot_b
              FROM {TABLE_NAME}
            )
        """).fetchone()[0]
        if n_unique != n_after:
            raise SystemExit(
                f"Duplicate PK rows: {n_after:,} inserted but only "
                f"{n_unique:,} unique (pid, record_id, m, b) combinations"
            )
        print("    [OK] All keys unique")
        print()

        # --------------------------------------------------------------------
        # [4] Verification
        # --------------------------------------------------------------------
        print("[4] Verification:")

        unique_mb = con.execute(f"""
            SELECT COUNT(*) FROM (
              SELECT DISTINCT imputation_m, boot_b FROM {TABLE_NAME}
            )
        """).fetchone()[0]
        print(f"    Unique (imputation_m, boot_b) pairs: "
              f"{unique_mb} (expected {M*B})")
        if unique_mb != M * B:
            raise SystemExit("Missing (m, b) combinations after insert")

        by_m = con.execute(f"""
            SELECT imputation_m,
                   COUNT(*)                   AS n,
                   MIN(calibrated_weight)     AS min_w,
                   MAX(calibrated_weight)     AS max_w,
                   AVG(calibrated_weight)     AS mean_w
            FROM {TABLE_NAME}
            GROUP BY imputation_m
            ORDER BY imputation_m
        """).fetchall()
        print()
        print("    Per-imputation summary (mean_w should be ~1.0):")
        print(f"    {'m':>3}  {'n':>10}  {'min_w':>10}  "
              f"{'max_w':>10}  {'mean_w':>10}")
        for row in by_m:
            print(f"    {row[0]:>3}  {row[1]:>10,}  {row[2]:>10.4f}  "
                  f"{row[3]:>10.4f}  {row[4]:>10.4f}")

        con.execute("CHECKPOINT")
    finally:
        con.close()

    print()
    print("=" * 57)
    print("SCRIPT 36 COMPLETE")
    print("=" * 57)
    print()
    print(f"{TABLE_NAME} populated: "
          f"{arrow_all.num_rows:,} rows across "
          f"{M} imputations x {B} bootstrap draws.")
    print("MI-aware variance estimation can now query this table per (m, b).")
    print()


if __name__ == "__main__":
    main()
