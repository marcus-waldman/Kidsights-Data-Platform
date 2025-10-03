"""
NSCH Variable Reference Generator

Auto-generates comprehensive variable reference documentation from database metadata.
Creates markdown tables showing all variables with their labels, types, and year availability.

Usage:
    python scripts/nsch/generate_variable_reference.py
    python scripts/nsch/generate_variable_reference.py --database data/duckdb/kidsights_local.duckdb
    python scripts/nsch/generate_variable_reference.py --output docs/nsch/variables_reference.md

Output Format:
    - Variables organized alphabetically
    - Shows variable name, label, type
    - Lists years where variable appears
    - Includes summary statistics

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import duckdb
import pandas as pd
from pathlib import Path
from datetime import datetime
from typing import Dict, List


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Auto-generate NSCH variable reference from database metadata"
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
        default="docs/nsch/variables_reference.md",
        help="Output file path (default: docs/nsch/variables_reference.md)"
    )

    parser.add_argument(
        "--format",
        type=str,
        choices=["full", "summary"],
        default="full",
        help="Output format: full (all variables) or summary (common variables only)"
    )

    return parser.parse_args()


def get_all_variables(conn):
    """Get all variables with their metadata."""
    query = """
        SELECT
            variable_name,
            variable_label,
            variable_type,
            year,
            source_file
        FROM nsch_variables
        ORDER BY variable_name, year
    """
    return conn.execute(query).fetchdf()


def get_variable_year_mapping(df):
    """Create mapping of variables to years they appear in."""
    variable_years = {}

    for var_name in df['variable_name'].unique():
        var_data = df[df['variable_name'] == var_name]
        years = sorted(var_data['year'].unique())
        label = var_data['variable_label'].iloc[0]
        var_type = var_data['variable_type'].iloc[0]

        variable_years[var_name] = {
            'label': label,
            'type': var_type,
            'years': years
        }

    return variable_years


def get_common_variables(variable_years, min_years=7):
    """Get variables that appear in at least min_years."""
    common_vars = {}

    for var_name, data in variable_years.items():
        if len(data['years']) >= min_years:
            common_vars[var_name] = data

    return common_vars


def get_year_summary(conn):
    """Get summary statistics by year."""
    query = """
        SELECT
            year,
            COUNT(DISTINCT variable_name) AS variable_count
        FROM nsch_variables
        GROUP BY year
        ORDER BY year
    """
    return conn.execute(query).fetchdf()


def format_year_list(years):
    """Format year list for compact display."""
    if len(years) == 8:
        return "All (2016-2023)"
    elif len(years) >= 5:
        return f"{years[0]}-{years[-1]} ({len(years)} years)"
    else:
        return ", ".join(str(y) for y in years)


def generate_markdown(variable_years, year_summary, output_format="full"):
    """Generate markdown content."""
    lines = []

    # Header
    lines.append("# NSCH Variable Reference")
    lines.append("")
    lines.append("**Auto-generated from database metadata**")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("---")
    lines.append("")

    # Summary statistics
    lines.append("## Summary Statistics")
    lines.append("")
    lines.append("### Variables by Year")
    lines.append("")
    lines.append("| Year | Variable Count |")
    lines.append("|------|----------------|")
    for _, row in year_summary.iterrows():
        lines.append(f"| {row['year']} | {row['variable_count']:,} |")
    lines.append("")

    # Overall statistics
    total_unique = len(variable_years)
    common_vars = get_common_variables(variable_years, min_years=7)
    rare_vars = {k: v for k, v in variable_years.items() if len(v['years']) == 1}

    lines.append("### Variable Availability")
    lines.append("")
    lines.append(f"- **Total unique variables:** {total_unique:,}")
    lines.append(f"- **Common variables (7+ years):** {len(common_vars):,}")
    lines.append(f"- **Year-specific variables (1 year only):** {len(rare_vars):,}")
    lines.append("")

    # Most common years pattern
    lines.append("### Most Common Year Patterns")
    lines.append("")
    year_patterns = {}
    for var_data in variable_years.values():
        pattern = format_year_list(var_data['years'])
        year_patterns[pattern] = year_patterns.get(pattern, 0) + 1

    sorted_patterns = sorted(year_patterns.items(), key=lambda x: x[1], reverse=True)[:10]
    lines.append("| Year Pattern | Variable Count |")
    lines.append("|-------------|----------------|")
    for pattern, count in sorted_patterns:
        lines.append(f"| {pattern} | {count:,} |")
    lines.append("")
    lines.append("---")
    lines.append("")

    # Variable listings
    if output_format == "full":
        lines.append("## All Variables (Alphabetical)")
        lines.append("")
        lines.append("This section lists all variables found across all NSCH years.")
        lines.append("")

        # Group variables by first letter
        first_letters = {}
        for var_name in sorted(variable_years.keys()):
            first_letter = var_name[0].upper()
            if first_letter not in first_letters:
                first_letters[first_letter] = []
            first_letters[first_letter].append(var_name)

        # Table of contents
        lines.append("### Table of Contents (by letter)")
        lines.append("")
        for letter in sorted(first_letters.keys()):
            count = len(first_letters[letter])
            lines.append(f"- [{letter}](#{letter.lower()}) ({count} variables)")
        lines.append("")

        # Variables by letter
        for letter in sorted(first_letters.keys()):
            lines.append(f"### {letter}")
            lines.append("")
            lines.append("| Variable | Label | Years Available |")
            lines.append("|----------|-------|-----------------|")

            for var_name in first_letters[letter]:
                var_data = variable_years[var_name]
                label = var_data['label'][:80] + "..." if len(var_data['label']) > 80 else var_data['label']
                years = format_year_list(var_data['years'])
                lines.append(f"| `{var_name}` | {label} | {years} |")

            lines.append("")

    # Common variables section
    lines.append("## Common Variables (Present in 7+ Years)")
    lines.append("")
    lines.append("These variables are available in most or all NSCH years, making them suitable for trend analysis.")
    lines.append("")
    lines.append(f"**Total:** {len(common_vars):,} variables")
    lines.append("")

    # Organize common variables by category
    categories = {
        'Identifiers': ['HHID', 'YEAR', 'FIPSST', 'STRATUM'],
        'Child Demographics': [v for v in common_vars.keys() if v.startswith('SC_')],
        'Adult 1 Info': [v for v in common_vars.keys() if v.startswith('A1_')],
        'Adult 2 Info': [v for v in common_vars.keys() if v.startswith('A2_')],
        'Health Conditions': [v for v in common_vars.keys() if v.startswith('K2Q')],
        'Healthcare Access': [v for v in common_vars.keys() if v.startswith('K4Q') or v.startswith('K5Q')],
        'Family & Household': [v for v in common_vars.keys() if 'FAMILY' in v or 'HOUSE' in v or 'FPL' in v],
    }

    for category, var_list in categories.items():
        if not var_list:
            continue

        category_vars = [v for v in var_list if v in common_vars]
        if not category_vars:
            continue

        lines.append(f"### {category}")
        lines.append("")
        lines.append("| Variable | Label | Years |")
        lines.append("|----------|-------|-------|")

        for var_name in sorted(category_vars):
            var_data = common_vars[var_name]
            label = var_data['label'][:60] + "..." if len(var_data['label']) > 60 else var_data['label']
            years = format_year_list(var_data['years'])
            lines.append(f"| `{var_name}` | {label} | {years} |")

        lines.append("")

    # Other common variables (not in categories)
    categorized_vars = set()
    for var_list in categories.values():
        categorized_vars.update(var_list)

    other_vars = sorted([v for v in common_vars.keys() if v not in categorized_vars])

    if other_vars:
        lines.append("### Other Common Variables")
        lines.append("")
        lines.append("| Variable | Label | Years |")
        lines.append("|----------|-------|-------|")

        for var_name in other_vars:
            var_data = common_vars[var_name]
            label = var_data['label'][:60] + "..." if len(var_data['label']) > 60 else var_data['label']
            years = format_year_list(var_data['years'])
            lines.append(f"| `{var_name}` | {label} | {years} |")

        lines.append("")

    # Usage notes
    lines.append("---")
    lines.append("")
    lines.append("## Usage Notes")
    lines.append("")
    lines.append("### Variable Naming Conventions")
    lines.append("")
    lines.append("NSCH uses several prefixes to organize variables:")
    lines.append("")
    lines.append("- `SC_*` - Selected Child demographics (age, sex, race, etc.)")
    lines.append("- `A1_*` - Adult 1 (primary caregiver) information")
    lines.append("- `A2_*` - Adult 2 (secondary caregiver) information")
    lines.append("- `K2Q*` - Health conditions and status")
    lines.append("- `K4Q*` - Healthcare access and insurance")
    lines.append("- `K5Q*` - Healthcare quality and utilization")
    lines.append("- `K6Q*` - Family functioning and activities")
    lines.append("- `K7Q*` - Parenting and discipline")
    lines.append("- `K8Q*` - Neighborhood characteristics")
    lines.append("- `K9Q*` - School experiences")
    lines.append("- `K10Q*` - Adverse childhood experiences (ACEs)")
    lines.append("- `K11Q*` - Additional health and development items")
    lines.append("")
    lines.append("### Querying Variables")
    lines.append("")
    lines.append("To find variables in the database:")
    lines.append("")
    lines.append("```python")
    lines.append("import duckdb")
    lines.append("")
    lines.append("conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')")
    lines.append("")
    lines.append("# Find all ACE variables in 2023")
    lines.append("ace_vars = conn.execute(\"\"\"")
    lines.append("    SELECT variable_name, variable_label")
    lines.append("    FROM nsch_variables")
    lines.append("    WHERE year = 2023")
    lines.append("      AND variable_name LIKE 'K10Q%'")
    lines.append("    ORDER BY variable_name")
    lines.append("\"\"\").fetchdf()")
    lines.append("")
    lines.append("print(ace_vars)")
    lines.append("")
    lines.append("conn.close()")
    lines.append("```")
    lines.append("")
    lines.append("### Value Labels")
    lines.append("")
    lines.append("To see response options for a variable:")
    lines.append("")
    lines.append("```python")
    lines.append("import duckdb")
    lines.append("")
    lines.append("conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')")
    lines.append("")
    lines.append("# Get value labels for SC_SEX in 2023")
    lines.append("labels = conn.execute(\"\"\"")
    lines.append("    SELECT value, label")
    lines.append("    FROM nsch_value_labels")
    lines.append("    WHERE year = 2023")
    lines.append("      AND variable_name = 'SC_SEX'")
    lines.append("    ORDER BY value")
    lines.append("\"\"\").fetchdf()")
    lines.append("")
    lines.append("print(labels)")
    lines.append("")
    lines.append("conn.close()")
    lines.append("```")
    lines.append("")
    lines.append("### Cross-Year Harmonization")
    lines.append("")
    lines.append("When using variables across multiple years:")
    lines.append("")
    lines.append("1. **Check value labels:** Response options may differ across years")
    lines.append("2. **Verify skip patterns:** Universe and skip logic may have changed")
    lines.append("3. **Review question wording:** Item text may have been revised")
    lines.append("4. **Test for consistency:** Run cross-year validation queries")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Additional Resources")
    lines.append("")
    lines.append("- **Database Schema:** [database_schema.md](database_schema.md)")
    lines.append("- **Example Queries:** [example_queries.md](example_queries.md)")
    lines.append("- **Pipeline Usage:** [pipeline_usage.md](pipeline_usage.md)")
    lines.append("- **NSCH Documentation:** https://www.census.gov/programs-surveys/nsch.html")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("**Source:** nsch_variables table in Kidsights Data Platform")
    lines.append("")

    return "\n".join(lines)


def main():
    """Main execution function."""
    args = parse_arguments()

    database_path = Path(args.database)
    output_path = Path(args.output)

    if not database_path.exists():
        print(f"[ERROR] Database not found: {database_path}", file=sys.stderr)
        return 1

    print("=" * 70)
    print("NSCH VARIABLE REFERENCE GENERATOR")
    print("=" * 70)
    print(f"Database: {database_path}")
    print(f"Output: {output_path}")
    print(f"Format: {args.format}")
    print("")

    try:
        # Connect to database
        print("[STEP 1/4] Connecting to database...")
        conn = duckdb.connect(str(database_path))

        # Get all variables
        print("[STEP 2/4] Querying variable metadata...")
        df = get_all_variables(conn)
        print(f"  Found {len(df):,} variable-year combinations")
        print(f"  Unique variables: {df['variable_name'].nunique():,}")

        # Create mappings
        print("[STEP 3/4] Creating variable-year mappings...")
        variable_years = get_variable_year_mapping(df)
        print(f"  Created mappings for {len(variable_years):,} variables")

        # Get year summary
        year_summary = get_year_summary(conn)

        # Close connection
        conn.close()

        # Generate markdown
        print("[STEP 4/4] Generating markdown documentation...")
        markdown = generate_markdown(variable_years, year_summary, args.format)

        # Write to file
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(markdown)

        print(f"\n[SUCCESS] Variable reference generated: {output_path}")
        print(f"  Total variables documented: {len(variable_years):,}")
        print(f"  Common variables (7+ years): {len(get_common_variables(variable_years)):,}")
        print(f"  File size: {output_path.stat().st_size / 1024:.1f} KB")

        return 0

    except Exception as e:
        print(f"\n[ERROR] Failed to generate variable reference: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
