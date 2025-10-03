"""
Missing Data Validation Script

Checks transformed data for persisting sentinel missing value codes (99, 9, -99, etc.)
that should have been converted to NULL/NA during transformation.

Usage:
    python scripts/validation/check_missing_codes.py

Returns exit code 1 if issues found, 0 if clean.
"""

import duckdb
import sys
from pathlib import Path

# Database path
DB_PATH = "data/duckdb/kidsights_local.duckdb"

# Validation rules for specific variables
VALIDATION_RULES = {
    # ACE variables should be 0/1 or NULL (no 99 values)
    "ace_total": {"min": 0, "max": 10, "forbidden_values": [99, -99, 999]},
    "child_ace_total": {"min": 0, "max": 8, "forbidden_values": [99, -99, 999]},

    # Mental health scores should be in valid ranges
    "phq2_total": {"min": 0, "max": 6, "forbidden_values": [99, -99, 9, 999]},
    "gad2_total": {"min": 0, "max": 6, "forbidden_values": [99, -99, 9, 999]},

    # Individual ACE items should be 0/1 or NULL
    "ace_neglect": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_parent_loss": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_mental_illness": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_substance_use": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_domestic_violence": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_incarceration": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_verbal_abuse": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_physical_abuse": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_emotional_neglect": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "ace_sexual_abuse": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},

    # Child ACE items
    "child_ace_parent_divorce": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_parent_death": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_parent_jail": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_domestic_violence": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_neighborhood_violence": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_mental_illness": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_substance_use": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
    "child_ace_discrimination": {"min": 0, "max": 1, "forbidden_values": [99, -99, 9]},
}


def check_database_exists():
    """Check if database file exists."""
    db_file = Path(DB_PATH)
    if not db_file.exists():
        print(f"ERROR: Database not found at {DB_PATH}")
        print("Run the NE25 pipeline first to create the database.")
        return False
    return True


def validate_variable(conn, table_name, var_name, rules):
    """
    Validate a single variable against rules.

    Returns: (is_valid, issues_found)
    """
    issues = []

    # Check if variable exists in table
    columns = conn.execute(f"PRAGMA table_info('{table_name}')").fetchall()
    column_names = [col[1] for col in columns]

    if var_name not in column_names:
        # Variable doesn't exist (might be expected for some variables)
        return True, []

    # Check for forbidden values
    for forbidden_val in rules.get("forbidden_values", []):
        count = conn.execute(f"""
            SELECT COUNT(*) as cnt
            FROM {table_name}
            WHERE {var_name} = {forbidden_val}
        """).fetchone()[0]

        if count > 0:
            issues.append(f"  {var_name} has {count} records with forbidden value {forbidden_val}")

    # Check for out-of-range values
    if "min" in rules and "max" in rules:
        out_of_range = conn.execute(f"""
            SELECT COUNT(*) as cnt
            FROM {table_name}
            WHERE {var_name} IS NOT NULL
              AND ({var_name} < {rules['min']} OR {var_name} > {rules['max']})
        """).fetchone()[0]

        if out_of_range > 0:
            # Get example values
            examples = conn.execute(f"""
                SELECT DISTINCT {var_name}
                FROM {table_name}
                WHERE {var_name} IS NOT NULL
                  AND ({var_name} < {rules['min']} OR {var_name} > {rules['max']})
                LIMIT 5
            """).fetchall()
            example_values = [str(ex[0]) for ex in examples]

            issues.append(
                f"  {var_name} has {out_of_range} records outside valid range "
                f"[{rules['min']}-{rules['max']}]. Examples: {', '.join(example_values)}"
            )

    is_valid = len(issues) == 0
    return is_valid, issues


def main():
    """Main validation routine."""
    print("=" * 70)
    print("NE25 MISSING DATA VALIDATION")
    print("=" * 70)
    print()

    # Check database exists
    if not check_database_exists():
        return 1

    # Connect to database
    try:
        conn = duckdb.connect(DB_PATH, read_only=True)
    except Exception as e:
        print(f"ERROR: Failed to connect to database: {e}")
        return 1

    # Check if ne25_transformed table exists
    tables = conn.execute("SHOW TABLES").fetchall()
    table_names = [t[0] for t in tables]

    if "ne25_transformed" not in table_names:
        print("ERROR: ne25_transformed table not found in database")
        print("Available tables:", ", ".join(table_names))
        conn.close()
        return 1

    # Run validations
    print("Checking transformed data for missing value codes...\n")

    all_valid = True
    total_issues = 0

    for var_name, rules in VALIDATION_RULES.items():
        is_valid, issues = validate_variable(conn, "ne25_transformed", var_name, rules)

        if not is_valid:
            all_valid = False
            total_issues += len(issues)
            print(f"FAILED: {var_name}")
            for issue in issues:
                print(issue)
            print()

    # Summary
    print("=" * 70)
    if all_valid:
        print("VALIDATION PASSED")
        print("No missing value codes found in transformed data.")
        print()
        print("All checked variables have valid values or NULL.")
        exit_code = 0
    else:
        print("VALIDATION FAILED")
        print(f"Found {total_issues} issue(s) with missing value handling.")
        print()
        print("Action required:")
        print("1. Review transformation logic in R/transform/ne25_transforms.R")
        print("2. Ensure recode_missing() is applied before variable assignment")
        print("3. Verify composite scores use na.rm = FALSE")
        print("4. Re-run pipeline after fixes")
        exit_code = 1
    print("=" * 70)

    conn.close()
    return exit_code


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
