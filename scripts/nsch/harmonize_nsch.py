"""
Standalone NSCH Harmonization Utility

Convenience wrapper for harmonizing NSCH data and adding columns to database.

Usage:
    # Harmonize NSCH 2021
    python scripts/nsch/harmonize_nsch.py --year 2021

    # Harmonize NSCH 2022
    python scripts/nsch/harmonize_nsch.py --year 2022

    # Harmonize both years
    python scripts/nsch/harmonize_nsch.py --year 2021 --year 2022

Author: Kidsights Data Platform
Date: 2025-11-13
"""

import argparse
import subprocess
import sys
from pathlib import Path


def harmonize_year(year: int, verbose: bool = False) -> bool:
    """
    Harmonize a single NSCH year.

    Args:
        year: NSCH year (2021 or 2022)
        verbose: Enable verbose logging

    Returns:
        True if successful, False otherwise
    """
    print(f"\n{'='*80}")
    print(f"Harmonizing NSCH {year}")
    print(f"{'='*80}\n")

    # Call harmonization pipeline script
    cmd = [
        "python",
        "pipelines/python/nsch/harmonize_nsch_data.py",
        "--year", str(year)
    ]

    if verbose:
        cmd.append("--verbose")

    try:
        result = subprocess.run(cmd, check=True)
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        print(f"\n[ERROR] Harmonization failed for NSCH {year}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Harmonize NSCH data and add columns to database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Harmonize NSCH 2021
  python scripts/nsch/harmonize_nsch.py --year 2021

  # Harmonize both years
  python scripts/nsch/harmonize_nsch.py --year 2021 --year 2022

  # With verbose logging
  python scripts/nsch/harmonize_nsch.py --year 2021 --verbose
        """
    )

    parser.add_argument('--year', type=int, action='append',
                        choices=[2021, 2022],
                        help='NSCH year(s) to harmonize (can specify multiple)')
    parser.add_argument('--verbose', action='store_true',
                        help='Enable verbose logging')

    args = parser.parse_args()

    # Require at least one year
    if not args.year:
        parser.error("At least one --year must be specified")

    print("NSCH Harmonization Utility")
    print(f"Years to process: {', '.join(map(str, args.year))}")

    success_count = 0
    fail_count = 0

    for year in args.year:
        if harmonize_year(year, args.verbose):
            success_count += 1
        else:
            fail_count += 1

    # Summary
    print(f"\n{'='*80}")
    print("Harmonization Summary")
    print(f"{'='*80}")
    print(f"  Successful: {success_count}")
    print(f"  Failed: {fail_count}")
    print(f"{'='*80}\n")

    # Exit with error if any failed
    if fail_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
