#!/usr/bin/env python3
"""
Load geographic crosswalks using direct SQL COPY commands.
Simpler approach to avoid segmentation faults.
"""

import sys
import duckdb
from pathlib import Path

def main():
    """Load crosswalks using SQL COPY."""

    db_path = "data/duckdb/kidsights_local.duckdb"

    print(f"Connecting to database: {db_path}")
    conn = duckdb.connect(db_path)

    print(f"Database size before: {Path(db_path).stat().st_size / 1024 / 1024:.2f} MB")

    # Define crosswalks with SQL queries that filter to NE during import
    crosswalks = [
        {
            'table': 'geo_zip_to_puma',
            'file': 'data/reference/zip_to_puma_usa_2020.csv',
            'filter': "stab = 'NE'"
        },
        {
            'table': 'geo_zip_to_county',
            'file': 'data/reference/zip_to_county_usa_2020.csv',
            'filter': "county LIKE '31%'"  # Nebraska FIPS code
        },
        {
            'table': 'geo_zip_to_tract',
            'file': 'data/reference/zip_to_census_tract_usa_2020.csv',
            'filter': "county LIKE '31%'"  # Nebraska FIPS code
        },
        {
            'table': 'geo_zip_to_cbsa',
            'file': 'data/reference/zip_to_cbsa_usa_2020.csv',
            'filter': "zcta IS NOT NULL AND zcta != '' AND TRIM(zcta) != ''"  # Load all, filter by zcta in R
        },
        {
            'table': 'geo_zip_to_urban_rural',
            'file': 'data/reference/zip_to_urban_rural_usa_2020.csv',
            'filter': "zcta IS NOT NULL AND zcta != '' AND TRIM(zcta) != ''"  # Load all, filter by zcta in R
        },
        {
            'table': 'geo_zip_to_school_dist',
            'file': 'data/reference/zip_to_school_district_usa_2020.csv',
            'filter': "stab = 'NE'"
        },
        {
            'table': 'geo_zip_to_state_leg_lower',
            'file': 'data/reference/zip_to_state_legislative_lower_usa_2020.csv',
            'filter': "stab = 'NE'"
        },
        {
            'table': 'geo_zip_to_state_leg_upper',
            'file': 'data/reference/zip_to_state_legislative_upper_usa_2020.csv',
            'filter': "stab = 'NE'"
        },
        {
            'table': 'geo_zip_to_congress',
            'file': 'data/reference/zip_to_us_congress_usa_2020.csv',
            'filter': "stab = 'NE'"
        },
        {
            'table': 'geo_zip_to_native_lands',
            'file': 'data/reference/zip_to_native_lands_usa_2020.csv',
            'filter': "zcta IS NOT NULL AND zcta != '' AND TRIM(zcta) != ''"
        }
    ]

    successful = 0
    failed = 0

    for xwalk in crosswalks:
        table = xwalk['table']
        file = xwalk['file']
        filter_cond = xwalk['filter']

        print(f"\n--- Loading {table} ---")

        try:
            # Drop existing table
            conn.execute(f"DROP TABLE IF EXISTS {table}")

            # Create table from CSV with filter
            # Skip row 2 (descriptions) by reading all then filtering
            conn.execute(f"""
                CREATE TABLE {table} AS
                SELECT *
                FROM read_csv_auto('{file}',
                    header=true,
                    skip=1,
                    encoding='latin-1',
                    all_varchar=true)
                WHERE {filter_cond}
            """)

            # Get count
            result = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
            count = result[0]

            print(f"[OK] Loaded {count:,} rows into {table}")
            successful += 1

        except Exception as e:
            print(f"[FAIL] Failed to load {table}: {e}")
            failed += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print(f"Database size after: {Path(db_path).stat().st_size / 1024 / 1024:.2f} MB")

    # List all tables
    print(f"\n{'='*60}")
    print("ALL TABLES IN DATABASE")
    print(f"{'='*60}")
    tables = conn.execute("SHOW TABLES").fetchall()
    for table in sorted(tables):
        count = conn.execute(f"SELECT COUNT(*) FROM {table[0]}").fetchone()[0]
        print(f"  {table[0]}: {count:,} rows")

    conn.close()

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
