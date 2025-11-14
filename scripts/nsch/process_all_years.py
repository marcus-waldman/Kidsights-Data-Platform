"""
NSCH Batch Processing Script

Processes multiple NSCH years through the complete pipeline.
Handles SPSS → Feather → R Validation → Database loading.

Usage:
    # Process all years (2016-2023)
    python scripts/nsch/process_all_years.py --years all

    # Process specific years
    python scripts/nsch/process_all_years.py --years 2016,2017,2023

    # Process year range
    python scripts/nsch/process_all_years.py --years 2020-2023

    # Skip R validation (faster, but less safe)
    python scripts/nsch/process_all_years.py --years all --skip-validation

Command-line Arguments:
    --years: Years to process (required)
             Options: "all", "2016,2017,2023", "2020-2023"
    --skip-validation: Skip R validation step (not recommended)
    --database: Database path (default: data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Processes each year through complete pipeline
    - Generates summary report with statistics
    - Logs successes and failures

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import subprocess
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any
import json

# SPSS filename mapping
YEAR_TO_FILE = {
    2016: "NSCH2016_Topical_SPSS_CAHM_DRCv2.sav",
    2017: "2017 NSCH_Topical_CAHMI_DRCv2.sav",
    2018: "2018 NSCH_Topical_DRC_v2.sav",
    2019: "2019 NSCH_Topical_CAHMI DRCv2.sav",
    2020: "NSCH_2020e_Topical_CAHMI_DRCv3.sav",
    2021: "2021e NSCH_Topical_DRC_CAHMIv3.sav",
    2022: "NSCH_2022e_Topical_SPSS_CAHMI_DRCv3.sav",
    2023: "NSCH_2023e_Topical_CAHMI_DRC.sav"
}

# Years with harmonization support (codebook lexicons available)
HARMONIZE_YEARS = [2021, 2022]


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Process multiple NSCH years through complete pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process all years
  python scripts/nsch/process_all_years.py --years all

  # Process specific years
  python scripts/nsch/process_all_years.py --years 2016,2022,2023

  # Process year range
  python scripts/nsch/process_all_years.py --years 2020-2023

For more information, see: docs/nsch/IMPLEMENTATION_PLAN.md
        """
    )

    parser.add_argument(
        "--years",
        type=str,
        required=True,
        help='Years to process: "all", "2016,2017,2023", or "2020-2023"'
    )

    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip R validation step (not recommended)"
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

    return parser.parse_args()


def parse_years(years_arg: str) -> List[int]:
    """Parse years argument into list of years.

    Args:
        years_arg: "all", "2016,2017,2023", or "2020-2023"

    Returns:
        List of years to process
    """
    if years_arg.lower() == "all":
        return list(range(2016, 2024))

    if "-" in years_arg:
        # Range format: "2020-2023"
        parts = years_arg.split("-")
        start = int(parts[0])
        end = int(parts[1])
        return list(range(start, end + 1))

    if "," in years_arg:
        # Comma-separated: "2016,2017,2023"
        return [int(y.strip()) for y in years_arg.split(",")]

    # Single year
    return [int(years_arg)]


def verify_spss_files() -> Dict[int, bool]:
    """Verify SPSS files exist for all years.

    Returns:
        Dict mapping year to file exists boolean
    """
    print("\n[VERIFY] Checking SPSS files...")
    print("=" * 70)

    results = {}

    for year, filename in YEAR_TO_FILE.items():
        spss_path = Path(f"data/nsch/spss/{filename}")
        exists = spss_path.exists()
        results[year] = exists

        status = "[OK]" if exists else "[MISSING]"
        print(f"  {status} {year}: {filename}")

    missing_count = sum(1 for exists in results.values() if not exists)

    if missing_count > 0:
        print(f"\n[WARNING] {missing_count} SPSS files missing")
    else:
        print(f"\n[OK] All SPSS files present")

    return results


def run_spss_conversion(year: int, verbose: bool = False) -> bool:
    """Run SPSS to Feather conversion.

    Args:
        year: Survey year
        verbose: Enable verbose output (controls output capture, not passed to script)

    Returns:
        True if successful
    """
    print(f"  [STEP 1/4] SPSS to Feather conversion...")

    cmd = [
        "python",  # Use python from PATH
        "pipelines/python/nsch/load_nsch_spss.py",
        "--year", str(year),
        "--overwrite"  # Overwrite existing files
    ]

    # Note: load_nsch_spss.py doesn't have --verbose flag
    # verbose parameter only controls output capture

    # Set environment with PYTHONPATH
    import os
    env = os.environ.copy()
    env["PYTHONPATH"] = "."

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=not verbose,
            text=True,
            env=env
        )

        print(f"    [OK] Feather file created")
        return True

    except subprocess.CalledProcessError as e:
        print(f"    [FAIL] Conversion failed: {e}")
        if not verbose and e.stdout:
            print(f"    Output: {e.stdout[-200:]}")
        return False


def run_r_validation(year: int, verbose: bool = False) -> bool:
    """Run R validation.

    Args:
        year: Survey year
        verbose: Enable verbose output

    Returns:
        True if successful
    """
    print(f"  [STEP 2/4] R validation...")

    cmd = [
        r"C:\Program Files\R\R-4.5.1\bin\Rscript.exe",
        "pipelines/orchestration/run_nsch_pipeline.R",
        "--year", str(year)
    ]

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=not verbose,
            text=True
        )

        print(f"    [OK] Validation passed")
        return True

    except subprocess.CalledProcessError as e:
        print(f"    [FAIL] Validation failed: {e}")
        if not verbose and e.stdout:
            print(f"    Output: {e.stdout[-200:]}")
        return False


def run_metadata_loading(year: int, database: str, verbose: bool = False) -> bool:
    """Run metadata loading.

    Args:
        year: Survey year
        database: Database path
        verbose: Enable verbose output

    Returns:
        True if successful
    """
    print(f"  [STEP 3/4] Metadata loading...")

    cmd = [
        "python",
        "pipelines/python/nsch/load_nsch_metadata.py",
        "--year", str(year),
        "--database", database
    ]

    if verbose:
        cmd.append("--verbose")

    # Set environment with PYTHONPATH
    import os
    env = os.environ.copy()
    env["PYTHONPATH"] = "."

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=not verbose,
            text=True,
            env=env
        )

        print(f"    [OK] Metadata loaded")
        return True

    except subprocess.CalledProcessError as e:
        print(f"    [FAIL] Metadata loading failed: {e}")
        if not verbose and e.stdout:
            print(f"    Output: {e.stdout[-200:]}")
        return False


def run_data_insertion(year: int, database: str, verbose: bool = False) -> bool:
    """Run raw data insertion.

    Args:
        year: Survey year
        database: Database path
        verbose: Enable verbose output

    Returns:
        True if successful
    """
    print(f"  [STEP 4/4] Raw data insertion...")

    cmd = [
        "python",
        "pipelines/python/nsch/insert_nsch_database.py",
        "--year", str(year),
        "--database", database
    ]

    if verbose:
        cmd.append("--verbose")

    # Set environment with PYTHONPATH
    import os
    env = os.environ.copy()
    env["PYTHONPATH"] = "."

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=not verbose,
            text=True,
            env=env
        )

        print(f"    [OK] Data inserted")
        return True

    except subprocess.CalledProcessError as e:
        print(f"    [FAIL] Data insertion failed: {e}")
        if not verbose and e.stdout:
            print(f"    Output: {e.stdout[-200:]}")
        return False


def run_harmonization(year: int, database: str, verbose: bool = False) -> bool:
    """Run harmonization (add lex_equate columns).

    Args:
        year: Survey year
        database: Database path
        verbose: Enable verbose output

    Returns:
        True if successful
    """
    print(f"  [STEP 5/5] Harmonization (adding lex_equate columns)...")

    cmd = [
        "python",
        "pipelines/python/nsch/harmonize_nsch_data.py",
        "--year", str(year),
        "--database", database
    ]

    if verbose:
        cmd.append("--verbose")

    # Set environment with PYTHONPATH
    import os
    env = os.environ.copy()
    env["PYTHONPATH"] = "."

    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=not verbose,
            text=True,
            env=env
        )

        print(f"    [OK] Harmonization complete")
        return True

    except subprocess.CalledProcessError as e:
        print(f"    [FAIL] Harmonization failed: {e}")
        if not verbose and e.stdout:
            print(f"    Output: {e.stdout[-200:]}")
        return False


def process_year(
    year: int,
    database: str,
    skip_validation: bool = False,
    verbose: bool = False
) -> Dict[str, Any]:
    """Process a single year through complete pipeline.

    Args:
        year: Survey year
        database: Database path
        skip_validation: Skip R validation
        verbose: Enable verbose output

    Returns:
        Dict with processing results
    """
    print(f"\n{'='*70}")
    print(f"PROCESSING YEAR: {year}")
    print(f"{'='*70}")

    start_time = datetime.now()

    results = {
        "year": year,
        "success": False,
        "steps_completed": [],
        "steps_failed": [],
        "elapsed_seconds": 0
    }

    # Step 1: SPSS conversion
    if run_spss_conversion(year, verbose):
        results["steps_completed"].append("spss_conversion")
    else:
        results["steps_failed"].append("spss_conversion")
        return results

    # Step 2: R validation (optional)
    if not skip_validation:
        if run_r_validation(year, verbose):
            results["steps_completed"].append("r_validation")
        else:
            results["steps_failed"].append("r_validation")
            return results
    else:
        print(f"  [SKIP] R validation skipped")

    # Step 3: Metadata loading
    if run_metadata_loading(year, database, verbose):
        results["steps_completed"].append("metadata_loading")
    else:
        results["steps_failed"].append("metadata_loading")
        return results

    # Step 4: Data insertion
    if run_data_insertion(year, database, verbose):
        results["steps_completed"].append("data_insertion")
    else:
        results["steps_failed"].append("data_insertion")
        return results

    # Step 5: Harmonization (only for years with codebook lexicons)
    if year in HARMONIZE_YEARS:
        if run_harmonization(year, database, verbose):
            results["steps_completed"].append("harmonization")
        else:
            results["steps_failed"].append("harmonization")
            return results
    else:
        print(f"  [SKIP] Harmonization not available for {year} (no codebook lexicons)")

    # Calculate elapsed time
    end_time = datetime.now()
    results["elapsed_seconds"] = (end_time - start_time).total_seconds()

    # Mark as success
    results["success"] = True

    print(f"\n[SUCCESS] Year {year} processed in {results['elapsed_seconds']:.1f} seconds")

    return results


def print_summary(all_results: List[Dict[str, Any]], start_time: datetime, end_time: datetime) -> None:
    """Print processing summary.

    Args:
        all_results: List of processing results for each year
        start_time: Batch start time
        end_time: Batch end time
    """
    print("\n" + "=" * 70)
    print("BATCH PROCESSING SUMMARY")
    print("=" * 70)

    total_years = len(all_results)
    successful_years = sum(1 for r in all_results if r["success"])
    failed_years = total_years - successful_years

    total_elapsed = (end_time - start_time).total_seconds()

    print(f"Total Years Processed: {total_years}")
    print(f"Successful: {successful_years}")
    print(f"Failed: {failed_years}")
    print(f"Total Time: {total_elapsed:.1f} seconds ({total_elapsed/60:.1f} minutes)")

    print("\nPER-YEAR RESULTS:")
    print("-" * 70)

    for result in all_results:
        status = "[PASS]" if result["success"] else "[FAIL]"
        elapsed = result["elapsed_seconds"]

        print(f"  {status} {result['year']}: {elapsed:.1f}s - Steps: {', '.join(result['steps_completed'])}")

        if result["steps_failed"]:
            print(f"         Failed steps: {', '.join(result['steps_failed'])}")

    print("=" * 70)

    if failed_years > 0:
        print(f"\n[WARNING] {failed_years} year(s) failed processing")
        print("Review logs above for details")
    else:
        print("\n[SUCCESS] All years processed successfully!")


def main() -> int:
    """Main execution function.

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    batch_start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    years_to_process = parse_years(args.years)
    database = args.database
    skip_validation = args.skip_validation
    verbose = args.verbose

    print("=" * 70)
    print("NSCH BATCH PROCESSING")
    print("=" * 70)
    print(f"Started: {batch_start_time}")
    print(f"Years to process: {years_to_process}")
    print(f"Database: {database}")
    print(f"Skip validation: {skip_validation}")
    print("=" * 70)

    # Verify SPSS files
    file_status = verify_spss_files()

    missing_years = [year for year in years_to_process if not file_status.get(year, False)]

    if missing_years:
        print(f"\n[ERROR] Cannot process missing years: {missing_years}")
        return 1

    # Process each year
    all_results = []

    for year in years_to_process:
        result = process_year(year, database, skip_validation, verbose)
        all_results.append(result)

    # Print summary
    batch_end_time = datetime.now()
    print_summary(all_results, batch_start_time, batch_end_time)

    # Exit code
    failed_count = sum(1 for r in all_results if not r["success"])

    return 1 if failed_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
