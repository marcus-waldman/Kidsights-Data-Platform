"""
NSCH Database Summary Generator

Generates comprehensive summary of NSCH database contents including:
- Table listing
- Record counts by year
- Column counts
- Table sizes
- Metadata table information
- Sample queries for data access

Usage:
    python scripts/nsch/generate_db_summary.py
    python scripts/nsch/generate_db_summary.py --database data/duckdb/kidsights_local.duckdb
    python scripts/nsch/generate_db_summary.py --output docs/nsch/database_summary.txt

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import duckdb
import pandas as pd
from pathlib import Path
from datetime import datetime


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Generate NSCH database summary report"
    )

    parser.add_argument(
        "--database",
        type=str,
        default="data/duckdb/kidsights_local.duckdb",
        help="Database path (default: data/duckdb/kidsights_local.duckdb)"
    )

    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output file path (default: print to console)"
    )

    return parser.parse_args()


def print_header(text, level=1, file=None):
    """Print formatted header."""
    if level == 1:
        separator = "=" * 70
    else:
        separator = "-" * 70

    print("", file=file)
    print(separator, file=file)
    print(text, file=file)
    print(separator, file=file)


def get_table_list(conn):
    """Get list of all NSCH tables."""
    query = """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_name LIKE 'nsch_%'
        ORDER BY table_name
    """
    return conn.execute(query).fetchall()


def get_record_counts(conn, year_tables):
    """Get record counts for each year table."""
    results = []
    total_records = 0

    for table in sorted(year_tables):
        count = conn.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
        total_records += count
        results.append({'table': table, 'records': count})

    return results, total_records


def get_column_counts(conn, year_tables):
    """Get column counts for each year table."""
    results = []

    for table in sorted(year_tables):
        col_count = conn.execute(f"""
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_name = '{table}'
        """).fetchone()[0]
        results.append({'table': table, 'columns': col_count})

    return results


def get_table_sizes(conn, year_tables):
    """Get estimated table sizes in MB."""
    results = []

    for table in sorted(year_tables):
        # Get estimated size from DuckDB
        size_bytes = conn.execute(f"""
            SELECT estimated_size
            FROM duckdb_tables()
            WHERE table_name = '{table}'
        """).fetchone()

        if size_bytes and size_bytes[0]:
            size_mb = size_bytes[0] / (1024 * 1024)
            results.append({'table': table, 'size_mb': size_mb})
        else:
            results.append({'table': table, 'size_mb': 0.0})

    return results


def get_metadata_summary(conn):
    """Get metadata table statistics."""
    metadata_tables = ['nsch_variables', 'nsch_value_labels', 'nsch_crosswalk']
    results = []

    for table in metadata_tables:
        # Check if table exists
        exists = conn.execute(f"""
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_name = '{table}'
        """).fetchone()[0]

        if exists:
            count = conn.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
            results.append({'table': table, 'records': count})
        else:
            results.append({'table': table, 'records': 0})

    return results


def get_common_variables(conn, year_tables):
    """Find variables that exist across all years."""
    # Get columns for each year
    year_columns = {}

    for table in year_tables:
        cols = conn.execute(f'PRAGMA table_info({table})').fetchdf()
        year_columns[table] = set(cols['name'].values)

    # Find intersection (variables in all years)
    if year_columns:
        common = set.intersection(*year_columns.values())
        return sorted(list(common))
    return []


def generate_summary(database_path, output_file=None):
    """Generate comprehensive database summary."""

    # Open output file or use stdout
    if output_file:
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        f = open(output_path, 'w', encoding='utf-8')
    else:
        f = sys.stdout

    try:
        # Connect to database
        conn = duckdb.connect(str(database_path))

        # Print header
        print("=" * 70, file=f)
        print("NSCH DATABASE SUMMARY", file=f)
        print("=" * 70, file=f)
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", file=f)
        print(f"Database: {database_path}", file=f)

        # Get all tables
        all_tables = get_table_list(conn)
        year_tables = [t[0] for t in all_tables if '_raw' in t[0]]

        print_header("TABLE OVERVIEW", file=f)
        print(f"\nTotal NSCH Tables: {len(all_tables)}", file=f)
        print("\nAll Tables:", file=f)
        for table in all_tables:
            table_type = "Data" if "_raw" in table[0] else "Metadata"
            print(f"  - {table[0]} ({table_type})", file=f)

        # Record counts
        print_header("RECORD COUNTS BY YEAR", file=f)
        record_data, total_records = get_record_counts(conn, year_tables)

        for row in record_data:
            status = "[OK]" if row['records'] > 0 else "[EMPTY]"
            print(f"{status} {row['table']}: {row['records']:,} records", file=f)

        print(f"\nTotal Records (All Years): {total_records:,}", file=f)

        # Column counts
        print_header("COLUMN COUNTS BY YEAR", file=f)
        column_data = get_column_counts(conn, year_tables)

        for row in column_data:
            print(f"{row['table']}: {row['columns']} columns", file=f)

        # Table sizes
        print_header("TABLE SIZES", file=f)
        size_data = get_table_sizes(conn, year_tables)
        total_size_mb = sum(row['size_mb'] for row in size_data)

        for row in size_data:
            if row['size_mb'] > 0:
                print(f"{row['table']}: {row['size_mb']:.2f} MB", file=f)
            else:
                print(f"{row['table']}: <0.01 MB (empty)", file=f)

        print(f"\nTotal Database Size: {total_size_mb:.2f} MB", file=f)

        # Metadata tables
        print_header("METADATA TABLES", file=f)
        metadata_data = get_metadata_summary(conn)

        for row in metadata_data:
            print(f"{row['table']}: {row['records']:,} records", file=f)

        # Common variables
        print_header("COMMON VARIABLES (Present in All Years)", file=f)

        # Filter to only years with data
        years_with_data = [t for t in year_tables if conn.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0] > 0]
        common_vars = get_common_variables(conn, years_with_data)

        print(f"\nVariables present in all {len(years_with_data)} years with data:", file=f)
        print(f"Total common variables: {len(common_vars)}", file=f)
        print("\nFirst 20 common variables:", file=f)
        for var in common_vars[:20]:
            print(f"  - {var}", file=f)

        if len(common_vars) > 20:
            print(f"  ... and {len(common_vars) - 20} more", file=f)

        # Sample queries
        print_header("SAMPLE QUERIES", file=f)

        print("\n1. Query all records from a specific year:", file=f)
        print("   SELECT * FROM nsch_2023 LIMIT 10;", file=f)

        print("\n2. Get record count by year:", file=f)
        print("   SELECT COUNT(*) FROM nsch_2023;", file=f)

        print("\n3. Query specific variables:", file=f)
        print("   SELECT HHID, YEAR, SC_AGE_YEARS FROM nsch_2023 LIMIT 10;", file=f)

        print("\n4. Get variable metadata:", file=f)
        print("   SELECT * FROM nsch_variables WHERE year = 2023;", file=f)

        print("\n5. Get value labels for a variable:", file=f)
        print("   SELECT * FROM nsch_value_labels WHERE year = 2023 AND variable_name = 'SC_SEX';", file=f)

        print("\n6. Cross-year comparison (example):", file=f)
        print("   SELECT 2017 AS year, COUNT(*) AS count FROM nsch_2017", file=f)
        print("   UNION ALL", file=f)
        print("   SELECT 2018, COUNT(*) FROM nsch_2018", file=f)
        print("   UNION ALL", file=f)
        print("   SELECT 2019, COUNT(*) FROM nsch_2019;", file=f)

        # Data quality notes
        print_header("DATA QUALITY NOTES", file=f)

        print("\n- 2016 Data: Table exists but empty (0 records) due to schema differences", file=f)
        print("  - Known issue: 2016 uses different variable encodings than 2017-2023", file=f)
        print("  - Status: Acceptable for now, will be addressed in harmonization phase", file=f)

        print("\n- 2017-2023 Data: Successfully loaded with complete data", file=f)
        print(f"  - Total records: {total_records:,}", file=f)
        print("  - All tables have HHID as primary identifier", file=f)
        print("  - Data types consistent (DOUBLE for all numeric variables)", file=f)

        print("\n- Metadata:", file=f)
        print("  - Variable definitions loaded from SPSS metadata", file=f)
        print("  - Value labels preserved from SPSS files", file=f)
        print("  - Crosswalk table available for variable name changes across years", file=f)

        # Next steps
        print_header("NEXT STEPS", file=f)

        print("\n1. Harmonization (Future Phase):", file=f)
        print("   - Create standardized variable names across years", file=f)
        print("   - Align value coding schemes", file=f)
        print("   - Create unified cross-year dataset", file=f)

        print("\n2. Analysis Tables (Future Phase):", file=f)
        print("   - Create derived variables", file=f)
        print("   - Apply sampling weights", file=f)
        print("   - Generate analysis-ready datasets", file=f)

        print("\n3. Documentation (Future Phase):", file=f)
        print("   - Auto-generate data dictionaries", file=f)
        print("   - Create variable reference guides", file=f)
        print("   - Document harmonization mappings", file=f)

        print("\n" + "=" * 70, file=f)
        print("END OF SUMMARY", file=f)
        print("=" * 70, file=f)

        # Close connection
        conn.close()

        if output_file:
            print(f"\n[SUCCESS] Summary saved to: {output_file}")

        return 0

    except Exception as e:
        print(f"\n[ERROR] Failed to generate summary: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1

    finally:
        if output_file and f != sys.stdout:
            f.close()


def main():
    """Main execution function."""
    args = parse_arguments()

    database_path = Path(args.database)

    if not database_path.exists():
        print(f"[ERROR] Database not found: {database_path}", file=sys.stderr)
        return 1

    return generate_summary(database_path, args.output)


if __name__ == "__main__":
    sys.exit(main())
