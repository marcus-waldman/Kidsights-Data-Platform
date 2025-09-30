"""
ACS Documentation Generator

Generates comprehensive documentation from ACS data stored in DuckDB:
- HTML data dictionary with IPUMS variable definitions
- JSON metadata export
- Summary statistics by state/year

Usage:
    # Generate docs for Nebraska 2019-2023
    python scripts/acs/generate_acs_documentation.py \
        --state nebraska --year-range 2019-2023

    # Generate docs for all states/years in database
    python scripts/acs/generate_acs_documentation.py --all

    # Custom output directory
    python scripts/acs/generate_acs_documentation.py \
        --state nebraska --year-range 2019-2023 \
        --output-dir docs/acs/generated

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple
import duckdb
import structlog

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Generate ACS documentation from DuckDB",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single state/year
  python scripts/acs/generate_acs_documentation.py --state nebraska --year-range 2019-2023

  # All data in database
  python scripts/acs/generate_acs_documentation.py --all

  # Custom output directory
  python scripts/acs/generate_acs_documentation.py --state nebraska --year-range 2019-2023 --output-dir docs/custom
        """
    )

    # State/year selection
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--state",
        type=str,
        help="State name (requires --year-range)"
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Generate docs for all states/years in database"
    )

    parser.add_argument(
        "--year-range",
        type=str,
        help="Year range (required with --state)"
    )

    # Output settings
    parser.add_argument(
        "--output-dir",
        type=str,
        default="docs/acs",
        help="Output directory (default: docs/acs)"
    )

    parser.add_argument(
        "--database",
        type=str,
        default="data/duckdb/kidsights_local.duckdb",
        help="Database path (default: data/duckdb/kidsights_local.duckdb)"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Validate state/year-range combination
    if args.state and not args.year_range:
        parser.error("--state requires --year-range")

    return args


def connect_database(db_path: str) -> duckdb.DuckDBPyConnection:
    """Connect to DuckDB database.

    Args:
        db_path: Path to database file

    Returns:
        duckdb.DuckDBPyConnection: Database connection

    Raises:
        FileNotFoundError: If database doesn't exist
    """
    db_file = Path(db_path)

    if not db_file.exists():
        raise FileNotFoundError(
            f"Database not found: {db_path}\n\n"
            f"Please run the ACS pipeline first to create and populate the database."
        )

    log.info("Connecting to database", path=db_path)
    conn = duckdb.connect(str(db_file), read_only=True)

    return conn


def get_state_year_combinations(conn, state: Optional[str] = None,
                                year_range: Optional[str] = None) -> List[Tuple[str, str]]:
    """Get list of state/year combinations to process.

    Args:
        conn: DuckDB connection
        state: Specific state (optional)
        year_range: Specific year range (optional)

    Returns:
        List of (state, year_range) tuples
    """
    if state and year_range:
        # Single state/year
        return [(state, year_range)]
    else:
        # All combinations in database
        result = conn.execute("""
            SELECT DISTINCT state, year_range
            FROM acs_data
            ORDER BY state, year_range
        """).fetchall()

        return [(row[0], row[1]) for row in result]


def get_variable_metadata(conn) -> Dict[str, Dict[str, Any]]:
    """Get metadata for all variables from database schema.

    Args:
        conn: DuckDB connection

    Returns:
        Dict mapping variable name to metadata
    """
    log.info("Extracting variable metadata from schema")

    result = conn.execute("""
        SELECT
            column_name,
            data_type,
            is_nullable
        FROM information_schema.columns
        WHERE table_name = 'acs_data'
        ORDER BY ordinal_position
    """).fetchall()

    metadata = {}
    for row in result:
        var_name = row[0]
        metadata[var_name] = {
            "name": var_name,
            "type": row[1],
            "nullable": row[2] == "YES",
            "is_attached_char": var_name.endswith(("_mom", "_pop", "_head")),
            "ipums_url": f"https://usa.ipums.org/usa-action/variables/{var_name.split('_')[0]}"
                        if var_name not in ["state", "year_range"] else None
        }

    log.info("Variable metadata extracted", count=len(metadata))

    return metadata


def get_summary_statistics(conn, state: str, year_range: str) -> Dict[str, Any]:
    """Generate summary statistics for state/year.

    Args:
        conn: DuckDB connection
        state: State name
        year_range: Year range

    Returns:
        Dict with summary statistics
    """
    log.info("Generating summary statistics", state=state, year_range=year_range)

    stats = {
        "state": state,
        "year_range": year_range,
        "generated_at": datetime.now().isoformat()
    }

    # Total records
    result = conn.execute("""
        SELECT COUNT(*) FROM acs_data
        WHERE state = ? AND year_range = ?
    """, [state, year_range]).fetchone()
    stats["total_records"] = result[0]

    # Age distribution
    result = conn.execute("""
        SELECT AGE, COUNT(*) as count, SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY AGE
        ORDER BY AGE
    """, [state, year_range]).fetchall()
    stats["age_distribution"] = [
        {"age": row[0], "count": row[1], "weighted_population": row[2]}
        for row in result
    ]

    # Sex distribution
    result = conn.execute("""
        SELECT
            SEX,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY SEX
        ORDER BY SEX
    """, [state, year_range]).fetchall()
    stats["sex_distribution"] = [
        {
            "sex_code": row[0],
            "sex_label": "Male" if row[0] == 1 else "Female" if row[0] == 2 else "Unknown",
            "count": row[1],
            "weighted_population": row[2]
        }
        for row in result
    ]

    # Race distribution (top 10)
    result = conn.execute("""
        SELECT
            RACE,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY RACE
        ORDER BY count DESC
        LIMIT 10
    """, [state, year_range]).fetchall()
    stats["race_distribution"] = [
        {"race_code": row[0], "count": row[1], "weighted_population": row[2]}
        for row in result
    ]

    # Hispanic origin distribution
    result = conn.execute("""
        SELECT
            HISPAN,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY HISPAN
        ORDER BY HISPAN
    """, [state, year_range]).fetchall()
    stats["hispanic_distribution"] = [
        {
            "hispan_code": row[0],
            "hispan_label": "Not Hispanic" if row[0] == 0 else f"Hispanic origin {row[0]}",
            "count": row[1],
            "weighted_population": row[2]
        }
        for row in result
    ]

    # Mother's education distribution
    result = conn.execute("""
        SELECT
            EDUC_mom,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ? AND EDUC_mom IS NOT NULL
        GROUP BY EDUC_mom
        ORDER BY EDUC_mom
    """, [state, year_range]).fetchall()
    stats["mother_education_distribution"] = [
        {"educ_code": row[0], "count": row[1], "weighted_population": row[2]}
        for row in result
    ]

    # Father's education distribution
    result = conn.execute("""
        SELECT
            EDUC_pop,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ? AND EDUC_pop IS NOT NULL
        GROUP BY EDUC_pop
        ORDER BY EDUC_pop
    """, [state, year_range]).fetchall()
    stats["father_education_distribution"] = [
        {"educ_code": row[0], "count": row[1], "weighted_population": row[2]}
        for row in result
    ]

    # Metropolitan status distribution
    result = conn.execute("""
        SELECT
            METRO,
            COUNT(*) as count,
            SUM(PERWT) as weighted_pop
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY METRO
        ORDER BY METRO
    """, [state, year_range]).fetchall()
    stats["metro_distribution"] = [
        {
            "metro_code": row[0],
            "metro_label": (
                "Not in metro" if row[0] == 1
                else "In metro, central city" if row[0] == 2
                else "In metro, outside central city" if row[0] == 3
                else "In metro, city status unknown" if row[0] == 4
                else "Unknown"
            ),
            "count": row[1],
            "weighted_population": row[2]
        }
        for row in result
    ]

    # PUMA count
    result = conn.execute("""
        SELECT COUNT(DISTINCT PUMA) FROM acs_data
        WHERE state = ? AND year_range = ?
    """, [state, year_range]).fetchone()
    stats["puma_count"] = result[0]

    # Sampling weights summary
    result = conn.execute("""
        SELECT
            COUNT(*) as n,
            COUNT(PERWT) as perwt_nonmissing,
            MIN(PERWT) as perwt_min,
            AVG(PERWT) as perwt_mean,
            MAX(PERWT) as perwt_max,
            SUM(PERWT) as perwt_sum
        FROM acs_data
        WHERE state = ? AND year_range = ?
    """, [state, year_range]).fetchone()
    stats["sampling_weights"] = {
        "total_records": result[0],
        "perwt_nonmissing": result[1],
        "perwt_min": result[2],
        "perwt_mean": result[3],
        "perwt_max": result[4],
        "perwt_sum": result[5]
    }

    log.info("Summary statistics complete", records=stats["total_records"])

    return stats


def generate_html_data_dictionary(
    conn,
    state: str,
    year_range: str,
    variable_metadata: Dict[str, Dict[str, Any]],
    output_path: Path
) -> None:
    """Generate HTML data dictionary.

    Args:
        conn: DuckDB connection
        state: State name
        year_range: Year range
        variable_metadata: Variable metadata dict
        output_path: Output HTML file path
    """
    log.info("Generating HTML data dictionary", output=str(output_path))

    # Get record count
    result = conn.execute("""
        SELECT COUNT(*) FROM acs_data
        WHERE state = ? AND year_range = ?
    """, [state, year_range]).fetchone()
    record_count = result[0]

    # Start HTML
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ACS Data Dictionary - {state.title()} {year_range}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        h1 {{
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #34495e;
            margin-top: 30px;
        }}
        .metadata {{
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }}
        .variable {{
            background-color: white;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .variable-name {{
            font-weight: bold;
            font-size: 1.2em;
            color: #2980b9;
        }}
        .variable-type {{
            color: #7f8c8d;
            font-style: italic;
        }}
        .attached-char {{
            background-color: #ffeaa7;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.9em;
        }}
        .ipums-link {{
            color: #3498db;
            text-decoration: none;
        }}
        .ipums-link:hover {{
            text-decoration: underline;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }}
        th, td {{
            padding: 8px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        th {{
            background-color: #3498db;
            color: white;
        }}
        .footer {{
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ccc;
            color: #7f8c8d;
            font-size: 0.9em;
        }}
    </style>
</head>
<body>
    <h1>ACS Data Dictionary</h1>
    <div class="metadata">
        <p><strong>State:</strong> {state.title()}</p>
        <p><strong>Year Range:</strong> {year_range}</p>
        <p><strong>Records:</strong> {record_count:,}</p>
        <p><strong>Variables:</strong> {len(variable_metadata)}</p>
        <p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>

    <h2>Variable Descriptions</h2>
    <p>All variables use raw IPUMS coding. No harmonization or transformations applied.</p>
    <p>Variables with <span class="attached-char">Attached Characteristic</span> suffix are automatically linked to household members.</p>
"""

    # Add each variable
    for var_name, var_meta in variable_metadata.items():
        # Skip metadata columns
        if var_name in ["state", "year_range"]:
            continue

        html += f"""
    <div class="variable">
        <div class="variable-name">{var_name}</div>
        <div class="variable-type">Type: {var_meta['type']} | Nullable: {var_meta['nullable']}</div>
"""

        if var_meta['is_attached_char']:
            html += f"""
        <div><span class="attached-char">Attached Characteristic</span></div>
"""

        if var_meta['ipums_url']:
            html += f"""
        <div><a href="{var_meta['ipums_url']}" class="ipums-link" target="_blank">IPUMS Documentation →</a></div>
"""

        # Get value distribution (for non-continuous variables)
        if var_name not in ["SERIAL", "PERNUM", "HHWT", "PERWT", "HHINCOME", "FTOTINC"]:
            result = conn.execute(f"""
                SELECT
                    {var_name},
                    COUNT(*) as count,
                    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as pct
                FROM acs_data
                WHERE state = ? AND year_range = ?
                GROUP BY {var_name}
                ORDER BY count DESC
                LIMIT 10
            """, [state, year_range]).fetchall()

            if result:
                html += """
        <table>
            <tr>
                <th>Value</th>
                <th>Count</th>
                <th>Percent</th>
            </tr>
"""
                for row in result:
                    value = row[0] if row[0] is not None else "NULL"
                    count = row[1]
                    pct = row[2]
                    html += f"""
            <tr>
                <td>{value}</td>
                <td>{count:,}</td>
                <td>{pct}%</td>
            </tr>
"""
                html += """
        </table>
"""

        html += """
    </div>
"""

    # Footer
    html += f"""
    <div class="footer">
        <p><strong>Data Source:</strong> IPUMS USA, University of Minnesota, www.ipums.org</p>
        <p><strong>Citation:</strong> Steven Ruggles, Sarah Flood, Matthew Sobek, et al. IPUMS USA: Version 15.0 [dataset]. Minneapolis, MN: IPUMS, 2024. https://doi.org/10.18128/D010.V15.0</p>
        <p><strong>Pipeline Version:</strong> 1.0.0</p>
    </div>
</body>
</html>
"""

    # Write to file
    output_path.write_text(html, encoding='utf-8')

    log.info("HTML data dictionary generated", path=str(output_path))


def generate_json_metadata(
    conn,
    state: str,
    year_range: str,
    variable_metadata: Dict[str, Dict[str, Any]],
    output_path: Path
) -> None:
    """Generate JSON metadata export.

    Args:
        conn: DuckDB connection
        state: State name
        year_range: Year range
        variable_metadata: Variable metadata dict
        output_path: Output JSON file path
    """
    log.info("Generating JSON metadata", output=str(output_path))

    # Build metadata
    metadata = {
        "extraction_info": {
            "state": state,
            "year_range": year_range,
            "generated_at": datetime.now().isoformat(),
            "pipeline_version": "1.0.0"
        },
        "data_summary": {},
        "variables": []
    }

    # Get record count
    result = conn.execute("""
        SELECT COUNT(*) FROM acs_data
        WHERE state = ? AND year_range = ?
    """, [state, year_range]).fetchone()
    metadata["data_summary"]["total_records"] = result[0]

    # Add variable metadata
    for var_name, var_meta in variable_metadata.items():
        if var_name not in ["state", "year_range"]:
            metadata["variables"].append(var_meta)

    # Write to file
    with output_path.open('w', encoding='utf-8') as f:
        json.dump(metadata, f, indent=2)

    log.info("JSON metadata generated", path=str(output_path))


def generate_summary_statistics_file(
    stats: Dict[str, Any],
    output_path: Path
) -> None:
    """Write summary statistics to JSON file.

    Args:
        stats: Summary statistics dict
        output_path: Output JSON file path
    """
    log.info("Writing summary statistics", output=str(output_path))

    with output_path.open('w', encoding='utf-8') as f:
        json.dump(stats, f, indent=2)

    log.info("Summary statistics written", path=str(output_path))


def main():
    """Main documentation generation workflow."""
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    log.info("=" * 70)
    log.info("ACS DOCUMENTATION GENERATOR")
    log.info("=" * 70)
    log.info(f"Started: {start_time}")

    try:
        # Connect to database
        conn = connect_database(args.database)

        # Get state/year combinations
        combinations = get_state_year_combinations(conn, args.state, args.year_range)

        log.info(f"Processing {len(combinations)} state/year combination(s)")

        # Get variable metadata (same for all)
        variable_metadata = get_variable_metadata(conn)

        # Create output directory
        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Process each combination
        for state, year_range in combinations:
            log.info("=" * 70)
            log.info(f"Processing: {state} {year_range}")
            log.info("=" * 70)

            # Generate summary statistics
            stats = get_summary_statistics(conn, state, year_range)

            # Generate HTML data dictionary
            html_path = output_dir / f"{state}_{year_range}_data_dictionary.html"
            generate_html_data_dictionary(
                conn, state, year_range, variable_metadata, html_path
            )

            # Generate JSON metadata
            json_path = output_dir / f"{state}_{year_range}_metadata.json"
            generate_json_metadata(
                conn, state, year_range, variable_metadata, json_path
            )

            # Generate summary statistics file
            stats_path = output_dir / f"{state}_{year_range}_summary_statistics.json"
            generate_summary_statistics_file(stats, stats_path)

            log.info("Documentation generated successfully")
            log.info(f"  HTML: {html_path}")
            log.info(f"  Metadata: {json_path}")
            log.info(f"  Statistics: {stats_path}")

        # Close connection
        conn.close()

        # Summary
        end_time = datetime.now()
        elapsed = (end_time - start_time).total_seconds()

        log.info("=" * 70)
        log.info("DOCUMENTATION GENERATION COMPLETE")
        log.info("=" * 70)
        log.info(f"Processed: {len(combinations)} state/year combination(s)")
        log.info(f"Output Directory: {output_dir}")
        log.info(f"Elapsed Time: {elapsed:.2f} seconds")

        return 0

    except Exception as e:
        log.error(
            "Documentation generation failed",
            error=str(e),
            error_type=type(e).__name__
        )
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
