"""
ACS Batch State Runner

Run the complete ACS pipeline for multiple states in sequence, with aggregated
reporting and error handling.

Usage:
    # Run for Nebraska, Iowa, Kansas
    python scripts/acs/run_multiple_states.py \
        --states nebraska iowa kansas \
        --year-range 2019-2023

    # From config file
    python scripts/acs/run_multiple_states.py \
        --config config/acs_batch_states.yaml

    # Continue on errors
    python scripts/acs/run_multiple_states.py \
        --states nebraska iowa kansas \
        --year-range 2019-2023 \
        --continue-on-error

    # Generate summary report only (skip pipeline)
    python scripts/acs/run_multiple_states.py \
        --states nebraska iowa kansas \
        --year-range 2019-2023 \
        --summary-only

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
import subprocess
import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any
import structlog

# Configure structured logging
log = structlog.get_logger()


# State FIPS codes
STATE_FIPS = {
    'nebraska': 31,
    'iowa': 19,
    'kansas': 20,
    'missouri': 29,
    'south_dakota': 46,
}


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Run ACS pipeline for multiple states",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process multiple states
  python scripts/acs/run_multiple_states.py --states nebraska iowa kansas --year-range 2019-2023

  # Continue on errors
  python scripts/acs/run_multiple_states.py --states nebraska iowa --year-range 2019-2023 --continue-on-error

  # Summary report only
  python scripts/acs/run_multiple_states.py --states nebraska iowa --year-range 2019-2023 --summary-only
        """
    )

    # State selection
    parser.add_argument(
        "--states",
        nargs="+",
        help="List of states to process (e.g., nebraska iowa kansas)"
    )

    parser.add_argument(
        "--year-range",
        type=str,
        required=True,
        help="Year range (e.g., 2019-2023)"
    )

    # Options
    parser.add_argument(
        "--continue-on-error",
        action="store_true",
        help="Continue processing other states if one fails"
    )

    parser.add_argument(
        "--skip-extraction",
        action="store_true",
        help="Skip extraction step (use existing Feather files)"
    )

    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip R validation step"
    )

    parser.add_argument(
        "--skip-database",
        action="store_true",
        help="Skip database insertion step"
    )

    parser.add_argument(
        "--summary-only",
        action="store_true",
        help="Generate summary report only (don't run pipeline)"
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default="logs/acs/batch",
        help="Output directory for logs and reports"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


def run_extraction(state: str, year_range: str, verbose: bool = False) -> Dict[str, Any]:
    """Run Python extraction step for a state.

    Args:
        state: State name
        year_range: Year range
        verbose: Enable verbose output

    Returns:
        Dict with step results
    """
    log.info("Running extraction", state=state, year_range=year_range)

    cmd = [
        "python",
        "pipelines/python/acs/extract_acs_data.py",
        "--state", state,
        "--year-range", year_range
    ]

    if verbose:
        cmd.append("--verbose")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=3600  # 1 hour timeout
        )

        return {
            'step': 'extraction',
            'state': state,
            'success': result.returncode == 0,
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }

    except subprocess.TimeoutExpired:
        log.error("Extraction timeout", state=state)
        return {
            'step': 'extraction',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': 'Timeout after 1 hour'
        }
    except Exception as e:
        log.error("Extraction failed", state=state, error=str(e))
        return {
            'step': 'extraction',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': str(e)
        }


def run_validation(state: str, year_range: str, state_fip: int, verbose: bool = False) -> Dict[str, Any]:
    """Run R validation step for a state.

    Args:
        state: State name
        year_range: Year range
        state_fip: State FIPS code
        verbose: Enable verbose output

    Returns:
        Dict with step results
    """
    log.info("Running validation", state=state, year_range=year_range)

    # Create temp R script (avoid -e issues)
    script_content = f"""
source("R/load/acs/load_acs_data.R")
source("R/utils/acs/validate_acs_raw.R")

data <- load_acs_feather(
  state = "{state}",
  year_range = "{year_range}",
  base_dir = "data/acs",
  source_file = "raw",
  add_metadata = TRUE,
  validate = TRUE
)

validation <- validate_acs_raw_data(
  data = data,
  state_fip = {state_fip},
  state = "{state}",
  year_range = "{year_range}",
  expected_ages = 0:5,
  verbose = FALSE
)

# Write processed file
processed_path <- file.path("data/acs", "{state}", "{year_range}", "processed.feather")
arrow::write_feather(data, processed_path)

cat("\\n[OK] Validation complete\\n")
"""

    script_path = Path("scripts/temp/temp_validation.R")
    script_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.write_text(script_content)

    cmd = [
        "C:\\Program Files\\R\\R-4.5.1\\bin\\R.exe",
        "--slave",
        "--no-restore",
        "--file=" + str(script_path)
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )

        return {
            'step': 'validation',
            'state': state,
            'success': result.returncode == 0,
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }

    except subprocess.TimeoutExpired:
        log.error("Validation timeout", state=state)
        return {
            'step': 'validation',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': 'Timeout after 10 minutes'
        }
    except Exception as e:
        log.error("Validation failed", state=state, error=str(e))
        return {
            'step': 'validation',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': str(e)
        }


def run_database_insert(state: str, year_range: str, verbose: bool = False) -> Dict[str, Any]:
    """Run database insertion step for a state.

    Args:
        state: State name
        year_range: Year range
        verbose: Enable verbose output

    Returns:
        Dict with step results
    """
    log.info("Running database insertion", state=state, year_range=year_range)

    cmd = [
        "python",
        "pipelines/python/acs/insert_acs_database.py",
        "--state", state,
        "--year-range", year_range,
        "--mode", "replace"
    ]

    if verbose:
        cmd.append("--verbose")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )

        return {
            'step': 'database',
            'state': state,
            'success': result.returncode == 0,
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }

    except subprocess.TimeoutExpired:
        log.error("Database insertion timeout", state=state)
        return {
            'step': 'database',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': 'Timeout after 10 minutes'
        }
    except Exception as e:
        log.error("Database insertion failed", state=state, error=str(e))
        return {
            'step': 'database',
            'state': state,
            'success': False,
            'returncode': -1,
            'error': str(e)
        }


def process_state(
    state: str,
    year_range: str,
    skip_extraction: bool = False,
    skip_validation: bool = False,
    skip_database: bool = False,
    verbose: bool = False
) -> Dict[str, Any]:
    """Process a single state through the pipeline.

    Args:
        state: State name
        year_range: Year range
        skip_extraction: Skip extraction step
        skip_validation: Skip validation step
        skip_database: Skip database step
        verbose: Enable verbose output

    Returns:
        Dict with all step results
    """
    log.info("=" * 70)
    log.info(f"PROCESSING STATE: {state.upper()}")
    log.info("=" * 70)

    state_fip = STATE_FIPS.get(state)
    if not state_fip:
        log.error(f"Unknown state: {state}")
        return {
            'state': state,
            'success': False,
            'error': f"Unknown state FIPS code for {state}"
        }

    results = {
        'state': state,
        'year_range': year_range,
        'start_time': datetime.now().isoformat(),
        'steps': []
    }

    # Step 1: Extraction
    if not skip_extraction:
        extraction_result = run_extraction(state, year_range, verbose)
        results['steps'].append(extraction_result)

        if not extraction_result['success']:
            results['success'] = False
            results['failed_step'] = 'extraction'
            return results

    # Step 2: Validation
    if not skip_validation:
        validation_result = run_validation(state, year_range, state_fip, verbose)
        results['steps'].append(validation_result)

        if not validation_result['success']:
            results['success'] = False
            results['failed_step'] = 'validation'
            return results

    # Step 3: Database insertion
    if not skip_database:
        database_result = run_database_insert(state, year_range, verbose)
        results['steps'].append(database_result)

        if not database_result['success']:
            results['success'] = False
            results['failed_step'] = 'database'
            return results

    results['success'] = True
    results['end_time'] = datetime.now().isoformat()

    return results


def generate_summary_report(all_results: List[Dict[str, Any]], output_dir: Path):
    """Generate summary report for all states.

    Args:
        all_results: List of state processing results
        output_dir: Output directory for report
    """
    log.info("Generating summary report")

    output_dir.mkdir(parents=True, exist_ok=True)

    # Create report
    report_path = output_dir / f"batch_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"

    with open(report_path, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("ACS BATCH PROCESSING SUMMARY\n")
        f.write("=" * 70 + "\n\n")

        total_states = len(all_results)
        successful_states = sum(1 for r in all_results if r.get('success', False))
        failed_states = total_states - successful_states

        f.write(f"Total States: {total_states}\n")
        f.write(f"Successful: {successful_states}\n")
        f.write(f"Failed: {failed_states}\n\n")

        f.write("=" * 70 + "\n")
        f.write("STATE DETAILS\n")
        f.write("=" * 70 + "\n\n")

        for result in all_results:
            state = result.get('state', 'Unknown')
            success = result.get('success', False)
            status = "[OK]" if success else "[FAIL]"

            f.write(f"{status} {state.upper()}\n")

            if success:
                f.write(f"  All steps completed successfully\n")
            else:
                failed_step = result.get('failed_step', 'Unknown')
                f.write(f"  Failed at: {failed_step}\n")

            f.write("\n")

        f.write("=" * 70 + "\n")

    print(f"\nSummary report written to: {report_path}")

    # Also save JSON
    json_path = output_dir / f"batch_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(json_path, 'w') as f:
        json.dump(all_results, f, indent=2)

    print(f"JSON results written to: {json_path}")


def main():
    """Main batch processing workflow."""
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    print("=" * 70)
    print("ACS BATCH STATE RUNNER")
    print("=" * 70)
    print(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"States: {', '.join(args.states)}")
    print(f"Year Range: {args.year_range}")
    print()

    # Process each state
    all_results = []

    for state in args.states:
        if not args.summary_only:
            result = process_state(
                state=state,
                year_range=args.year_range,
                skip_extraction=args.skip_extraction,
                skip_validation=args.skip_validation,
                skip_database=args.skip_database,
                verbose=args.verbose
            )

            all_results.append(result)

            if not result.get('success', False) and not args.continue_on_error:
                log.error(f"State {state} failed, stopping batch processing")
                break

        print()

    # Generate summary report
    output_dir = Path(args.output_dir)
    generate_summary_report(all_results, output_dir)

    # Final summary
    end_time = datetime.now()
    elapsed = (end_time - start_time).total_seconds()

    print("\n" + "=" * 70)
    print("BATCH PROCESSING COMPLETE")
    print("=" * 70)
    print(f"Total states processed: {len(all_results)}")
    print(f"Successful: {sum(1 for r in all_results if r.get('success', False))}")
    print(f"Failed: {sum(1 for r in all_results if not r.get('success', False))}")
    print(f"Elapsed time: {elapsed:.2f} seconds")

    # Exit code
    if all(r.get('success', False) for r in all_results):
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
