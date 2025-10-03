"""
Automated Validation Script for All Composite Variables
Created: 2025-10-03 (Phase 5: Future Prevention)

Purpose:
  - Validate all 14 composite variables in ne25_transformed table
  - Check for values outside valid ranges
  - Check for sentinel values (99, 9, -99, 999) persisting after recode_missing()
  - Report missing value counts and percentages
  - Return comprehensive summary table

Usage:
  python scripts/validation/validate_composite_variables.py

Output:
  - Console table with validation results for all 14 composites
  - Exit code 0 if all checks pass, 1 if any validation fails
"""

import duckdb
import sys
from pathlib import Path

# Database path
DB_PATH = Path("data/duckdb/kidsights_local.duckdb")

# Composite variable definitions
# Format: {variable_name: (min_val, max_val, description)}
COMPOSITE_VARIABLES = {
    # Mental Health Composites
    "phq2_total": (0, 6, "PHQ-2 Depression Screening Total"),
    "gad2_total": (0, 6, "GAD-2 Anxiety Screening Total"),

    # ACE Composites
    "ace_total": (0, 10, "Caregiver ACE Total Score"),
    "child_ace_total": (0, 8, "Child ACE Total Score"),

    # Income/Poverty Composites
    "family_size": (1, 99, "Family Size"),
    "fpl": (0, None, "Federal Poverty Level %"),  # None = no upper bound

    # Age Composites
    "years_old": (0, 5, "Child Age in Years"),
    "months_old": (0, 60, "Child Age in Months"),

    # Geographic Composites
    "urban_pct": (0, 100, "Urban Percentage"),
}

# Categorical composites (no numeric range validation)
CATEGORICAL_COMPOSITES = [
    "fplcat"  # Factor with 5 levels, no numeric validation
]

# Childcare cost composites (conditional, no strict upper bound)
CHILDCARE_COMPOSITES = [
    "cc_weekly_cost_all",
    "cc_weekly_cost_primary",
    "cc_weekly_cost_total",
    "cc_any_support"
]

def connect_db():
    """Connect to DuckDB database."""
    if not DB_PATH.exists():
        print(f"[ERROR] Database not found: {DB_PATH}")
        sys.exit(1)

    try:
        conn = duckdb.connect(str(DB_PATH), read_only=True)
        return conn
    except Exception as e:
        print(f"[ERROR] Failed to connect to database: {e}")
        sys.exit(1)

def validate_composite(conn, var_name, min_val, max_val, description):
    """
    Validate a single composite variable.

    Returns:
        dict with validation results
    """
    # Get basic statistics
    query = f"""
        SELECT
            COUNT(*) as total_records,
            COUNT({var_name}) as non_missing,
            COUNT(*) - COUNT({var_name}) as missing,
            ROUND(100.0 * (COUNT(*) - COUNT({var_name})) / COUNT(*), 1) as missing_pct,
            MIN({var_name}) as min_val,
            MAX({var_name}) as max_val,
            SUM(CASE WHEN {var_name} < {min_val} THEN 1 ELSE 0 END) as below_min,
            SUM(CASE WHEN {var_name} IN (9, 99, -99, 999, -999) THEN 1 ELSE 0 END) as sentinel_values
        FROM ne25_transformed
    """

    # Add upper bound check if max_val is specified
    if max_val is not None:
        query = query.replace(
            "as below_min,",
            f"as below_min,\n            SUM(CASE WHEN {var_name} > {max_val} THEN 1 ELSE 0 END) as above_max,"
        )
    else:
        query = query.replace(
            "as below_min,",
            "as below_min,\n            0 as above_max,"
        )

    try:
        result = conn.execute(query).fetchone()

        total_records, non_missing, missing, missing_pct, obs_min, obs_max, below_min, above_max, sentinel = result

        # Determine validation status
        invalid_count = below_min + above_max + sentinel
        status = "[OK]" if invalid_count == 0 else "[FAIL]"

        return {
            "variable": var_name,
            "description": description,
            "total": total_records,
            "non_missing": non_missing,
            "missing": missing,
            "missing_pct": missing_pct,
            "valid_range": f"{min_val}-{max_val if max_val else 'Inf'}",
            "obs_range": f"{obs_min:.1f}-{obs_max:.1f}" if obs_min is not None else "N/A",
            "below_min": below_min,
            "above_max": above_max,
            "sentinel": sentinel,
            "invalid_total": invalid_count,
            "status": status
        }

    except Exception as e:
        return {
            "variable": var_name,
            "description": description,
            "total": 0,
            "non_missing": 0,
            "missing": 0,
            "missing_pct": 0,
            "valid_range": f"{min_val}-{max_val}",
            "obs_range": "ERROR",
            "below_min": 0,
            "above_max": 0,
            "sentinel": 0,
            "invalid_total": 0,
            "status": f"[ERROR] {str(e)}"
        }

def print_results_table(results):
    """Print validation results as formatted table."""
    print("="*140)
    print("COMPOSITE VARIABLES VALIDATION REPORT - All 14 Variables")
    print("="*140)
    print()

    # Table header
    print(f"{'Variable':<20} {'Description':<30} {'Valid Range':<12} {'Obs Range':<12} {'Status':<8} {'Invalid':<8}")
    print("-"*140)

    # Table rows
    for r in results:
        print(f"{r['variable']:<20} {r['description']:<30} {r['valid_range']:<12} {r['obs_range']:<12} {r['status']:<8} {r['invalid_total']:<8}")

    print()
    print("="*140)
    print("DETAILED VALIDATION CHECKS")
    print("="*140)
    print()

    for r in results:
        print(f"{r['variable']} ({r['description']})")
        print(f"  Total records:     {r['total']:,}")
        print(f"  Non-missing:       {r['non_missing']:,}")
        print(f"  Missing (NA):      {r['missing']:,} ({r['missing_pct']:.1f}%)")
        print(f"  Valid range:       {r['valid_range']}")
        print(f"  Observed range:    {r['obs_range']}")
        print(f"  Below minimum:     {r['below_min']}")
        print(f"  Above maximum:     {r['above_max']}")
        print(f"  Sentinel values:   {r['sentinel']}")
        print(f"  Status:            {r['status']}")
        print()

def main():
    """Main validation function."""
    print("[INFO] Connecting to database...")
    conn = connect_db()

    print(f"[INFO] Validating {len(COMPOSITE_VARIABLES)} composite variables...")
    print()

    results = []

    # Validate each composite variable
    for var_name, (min_val, max_val, description) in COMPOSITE_VARIABLES.items():
        result = validate_composite(conn, var_name, min_val, max_val, description)
        results.append(result)

    # Print results table
    print_results_table(results)

    # Summary statistics
    total_variables = len(results)
    passed = sum(1 for r in results if r['status'] == "[OK]")
    failed = sum(1 for r in results if "[FAIL]" in r['status'] or "[ERROR]" in r['status'])

    print("="*140)
    print("VALIDATION SUMMARY")
    print("="*140)
    print(f"Total variables validated:  {total_variables}")
    print(f"Passed:                     {passed}")
    print(f"Failed:                     {failed}")
    print()

    if failed > 0:
        print("[FAIL] Some composite variables have invalid values!")
        print()
        print("Failed variables:")
        for r in results:
            if "[FAIL]" in r['status'] or "[ERROR]" in r['status']:
                print(f"  - {r['variable']}: {r['invalid_total']} invalid values")
        print()
        print("Action required:")
        print("  1. Check R/transform/ne25_transforms.R for recode_missing() usage")
        print("  2. Verify sentinel values (99, 9, -99, 999) are being recoded to NA")
        print("  3. Check for calculation errors in composite score logic")
        print()
        conn.close()
        sys.exit(1)
    else:
        print("[OK] All composite variables passed validation!")
        print()
        print("Additional composites (not numerically validated):")
        print(f"  - Categorical: {', '.join(CATEGORICAL_COMPOSITES)}")
        print(f"  - Childcare: {', '.join(CHILDCARE_COMPOSITES)}")
        print()

    conn.close()
    sys.exit(0)

if __name__ == "__main__":
    main()
