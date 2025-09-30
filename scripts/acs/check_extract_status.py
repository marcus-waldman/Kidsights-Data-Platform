"""
ACS Extract Status Checker

Check status of IPUMS extracts and local cache, with sync and validation functionality.

Usage:
    # List IPUMS account extracts
    python scripts/acs/check_extract_status.py --list-ipums

    # List cached extracts
    python scripts/acs/check_extract_status.py --list-cache

    # Show both IPUMS and cache
    python scripts/acs/check_extract_status.py --list-all

    # Sync: download completed IPUMS extracts not in cache
    python scripts/acs/check_extract_status.py --sync

    # Validate all cached files (check integrity)
    python scripts/acs/check_extract_status.py --validate-cache

    # Check specific extract
    python scripts/acs/check_extract_status.py --extract-id usa:12345

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
import json
import structlog
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional
from tabulate import tabulate

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.acs.auth import get_client
from python.acs.cache_manager import (
    _load_registry,
    CACHE_ROOT,
    CACHE_EXTRACTS_DIR
)

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Check IPUMS extract status and local cache",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List all IPUMS account extracts
  python scripts/acs/check_extract_status.py --list-ipums

  # List locally cached extracts
  python scripts/acs/check_extract_status.py --list-cache

  # Show both
  python scripts/acs/check_extract_status.py --list-all

  # Validate cache integrity
  python scripts/acs/check_extract_status.py --validate-cache
        """
    )

    # Listing options
    parser.add_argument(
        "--list-ipums",
        action="store_true",
        help="List all extracts from IPUMS account"
    )

    parser.add_argument(
        "--list-cache",
        action="store_true",
        help="List all locally cached extracts"
    )

    parser.add_argument(
        "--list-all",
        action="store_true",
        help="Show both IPUMS and cache extracts"
    )

    # Sync option
    parser.add_argument(
        "--sync",
        action="store_true",
        help="Download completed IPUMS extracts not in cache"
    )

    # Validation option
    parser.add_argument(
        "--validate-cache",
        action="store_true",
        help="Validate integrity of all cached files"
    )

    # Specific extract
    parser.add_argument(
        "--extract-id",
        type=str,
        help="Check status of specific extract (e.g., usa:12345)"
    )

    # Output options
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    return parser.parse_args()


def list_ipums_extracts(verbose: bool = False) -> List[Dict[str, Any]]:
    """List all extracts from IPUMS account.

    Args:
        verbose: Enable verbose logging

    Returns:
        List of extract metadata dicts
    """
    log.info("Retrieving extracts from IPUMS account")

    try:
        client = get_client()

        # Get all extracts for the USA collection
        # Note: ipumspy may not have a list_extracts method in all versions
        # Try to get extracts via the API

        log.info("[OK] Connected to IPUMS API")

        # IPUMS API doesn't always expose a list method
        # We'll need to track extracts via our cache registry instead
        log.warning(
            "IPUMS API does not expose extract listing",
            note="Track extracts via cache registry or IPUMS web interface"
        )

        return []

    except Exception as e:
        log.error("Failed to connect to IPUMS API", error=str(e))
        return []


def list_cached_extracts() -> List[Dict[str, Any]]:
    """List all cached extracts from local registry.

    Returns:
        List of cached extract metadata dicts
    """
    log.info("Loading cached extracts from registry")

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    log.info(f"Found {len(extracts)} cached extract(s)")

    return extracts


def format_extract_table(extracts: List[Dict[str, Any]], cache_mode: bool = True) -> str:
    """Format extracts as a table for display.

    Args:
        extracts: List of extract metadata dicts
        cache_mode: If True, format for cache display (includes file paths)

    Returns:
        Formatted table string
    """
    if not extracts:
        return "No extracts found."

    # Build table rows
    rows = []
    for extract in extracts:
        if cache_mode:
            # Cache listing
            extract_id = extract.get('extract_id', 'Unknown')
            state = extract.get('state', 'Unknown')
            year_range = extract.get('year_range', 'Unknown')
            timestamp = extract.get('registration_timestamp', 'Unknown')

            # Parse timestamp for age calculation
            age = "Unknown"
            if timestamp != "Unknown":
                try:
                    reg_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                    age_delta = datetime.now() - reg_time.replace(tzinfo=None)
                    age_days = age_delta.days
                    if age_days == 0:
                        age = "Today"
                    elif age_days == 1:
                        age = "1 day"
                    else:
                        age = f"{age_days} days"
                except:
                    age = "Unknown"

            # Get file info
            files = extract.get('files', {})
            file_count = len(files)

            rows.append([
                extract_id,
                state.title(),
                year_range,
                age,
                f"{file_count} files",
                timestamp[:10] if timestamp != "Unknown" else "Unknown"
            ])
        else:
            # IPUMS listing (not implemented yet)
            rows.append([
                extract.get('extract_id', 'Unknown'),
                extract.get('status', 'Unknown'),
                extract.get('description', 'Unknown')
            ])

    # Headers
    if cache_mode:
        headers = ["Extract ID", "State", "Year Range", "Age", "Files", "Cached Date"]
    else:
        headers = ["Extract ID", "Status", "Description"]

    return tabulate(rows, headers=headers, tablefmt="grid")


def validate_cache_integrity(verbose: bool = False) -> Dict[str, Any]:
    """Validate integrity of all cached files.

    Checks that all files in cache registry actually exist on disk.

    Args:
        verbose: Enable detailed validation logging

    Returns:
        Dict with validation results
    """
    log.info("Validating cache integrity")

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    results = {
        'total_extracts': len(extracts),
        'valid_extracts': 0,
        'invalid_extracts': 0,
        'missing_files': [],
        'valid': True
    }

    for extract in extracts:
        extract_id = extract.get('extract_id', 'Unknown')
        files = extract.get('files', {})

        extract_valid = True
        for file_type, file_path in files.items():
            path = Path(file_path)
            if not path.exists():
                log.warning(
                    "Cached file missing",
                    extract_id=extract_id,
                    file_type=file_type,
                    path=str(path)
                )
                results['missing_files'].append({
                    'extract_id': extract_id,
                    'file_type': file_type,
                    'path': str(path)
                })
                extract_valid = False
                results['valid'] = False

        if extract_valid:
            results['valid_extracts'] += 1
            if verbose:
                log.info("[OK] Extract validated", extract_id=extract_id)
        else:
            results['invalid_extracts'] += 1

    # Summary
    if results['valid']:
        log.info(
            "[OK] Cache validation passed",
            total=results['total_extracts'],
            valid=results['valid_extracts']
        )
    else:
        log.error(
            "[FAIL] Cache validation failed",
            total=results['total_extracts'],
            valid=results['valid_extracts'],
            invalid=results['invalid_extracts'],
            missing_files=len(results['missing_files'])
        )

    return results


def check_specific_extract(extract_id: str) -> Dict[str, Any]:
    """Check status of a specific extract.

    Args:
        extract_id: IPUMS extract ID (e.g., usa:12345)

    Returns:
        Dict with extract information
    """
    log.info("Checking specific extract", extract_id=extract_id)

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    for extract in extracts:
        if extract.get('extract_id') == extract_id:
            log.info("[OK] Extract found in cache", extract_id=extract_id)
            return {
                'found': True,
                'cached': True,
                'extract': extract
            }

    log.info("Extract not found in cache", extract_id=extract_id)
    return {
        'found': False,
        'cached': False,
        'extract': None
    }


def sync_extracts(verbose: bool = False) -> Dict[str, Any]:
    """Sync IPUMS extracts to local cache.

    Downloads completed IPUMS extracts that aren't in cache yet.

    Args:
        verbose: Enable verbose logging

    Returns:
        Dict with sync results
    """
    log.info("Syncing IPUMS extracts to cache")

    # This would require IPUMS API extract listing
    # Not implemented in current ipumspy version
    log.warning(
        "Sync not implemented",
        reason="IPUMS API does not expose extract listing in ipumspy 0.7.0"
    )

    return {
        'synced': 0,
        'already_cached': 0,
        'failed': 0,
        'message': "Sync functionality requires IPUMS API extract listing (not available in ipumspy 0.7.0)"
    }


def main():
    """Main status checker workflow."""
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    print("=" * 70)
    print("ACS EXTRACT STATUS CHECKER")
    print("=" * 70)
    print(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    try:
        # Check specific extract
        if args.extract_id:
            print("=" * 70)
            print(f"CHECKING EXTRACT: {args.extract_id}")
            print("=" * 70)

            result = check_specific_extract(args.extract_id)

            if result['found']:
                extract = result['extract']
                print(f"\n[OK] Extract found in cache")
                print(f"  Extract ID: {extract.get('extract_id')}")
                print(f"  State: {extract.get('state', 'Unknown').title()}")
                print(f"  Year Range: {extract.get('year_range')}")
                print(f"  Sample: {extract.get('acs_sample')}")
                print(f"  Cached: {extract.get('registration_timestamp', 'Unknown')}")

                files = extract.get('files', {})
                print(f"  Files ({len(files)}):")
                for file_type, file_path in files.items():
                    exists = "[OK]" if Path(file_path).exists() else "[MISSING]"
                    print(f"    {exists} {file_type}: {file_path}")
            else:
                print(f"\n[NOT FOUND] Extract not in cache")
                print(f"  You may need to run the extraction pipeline for this extract")

            return 0

        # List cache
        if args.list_cache or args.list_all:
            print("=" * 70)
            print("CACHED EXTRACTS")
            print("=" * 70)

            cached_extracts = list_cached_extracts()

            if cached_extracts:
                table = format_extract_table(cached_extracts, cache_mode=True)
                print(f"\n{table}\n")
                print(f"Total cached extracts: {len(cached_extracts)}")

                # Calculate total disk usage
                total_size = 0
                for extract in cached_extracts:
                    files = extract.get('files', {})
                    for file_path in files.values():
                        path = Path(file_path)
                        if path.exists():
                            total_size += path.stat().st_size

                size_mb = total_size / (1024 ** 2)
                print(f"Total disk usage: {size_mb:.2f} MB")
            else:
                print("\nNo cached extracts found.")
                print(f"Cache directory: {CACHE_ROOT}")

            print()

        # List IPUMS (note: not fully implemented)
        if args.list_ipums or args.list_all:
            print("=" * 70)
            print("IPUMS ACCOUNT EXTRACTS")
            print("=" * 70)

            print("\n[NOTE] IPUMS API does not expose extract listing in ipumspy 0.7.0")
            print("Please use IPUMS web interface to view account extracts:")
            print("  https://usa.ipums.org/usa/extract_history.shtml")
            print()

        # Validate cache
        if args.validate_cache:
            print("=" * 70)
            print("CACHE VALIDATION")
            print("=" * 70)

            results = validate_cache_integrity(verbose=args.verbose)

            print(f"\nTotal cached extracts: {results['total_extracts']}")
            print(f"Valid extracts: {results['valid_extracts']}")
            print(f"Invalid extracts: {results['invalid_extracts']}")

            if results['missing_files']:
                print(f"\nMissing files ({len(results['missing_files'])}):")
                for missing in results['missing_files']:
                    print(f"  [MISSING] {missing['extract_id']}: {missing['file_type']}")
                    print(f"            {missing['path']}")

            if results['valid']:
                print("\n[OK] All cached files validated successfully")
            else:
                print("\n[FAIL] Cache validation failed - some files are missing")
                return 1

            print()

        # Sync
        if args.sync:
            print("=" * 70)
            print("SYNC IPUMS EXTRACTS TO CACHE")
            print("=" * 70)

            sync_results = sync_extracts(verbose=args.verbose)
            print(f"\n{sync_results['message']}")
            print()

        # Default: show summary
        if not any([args.list_cache, args.list_ipums, args.list_all,
                   args.validate_cache, args.sync, args.extract_id]):
            print("No action specified. Use --help for usage information.")
            print()
            print("Quick commands:")
            print("  --list-cache         List cached extracts")
            print("  --validate-cache     Validate cache integrity")
            print("  --extract-id ID      Check specific extract")
            return 1

        # Summary
        end_time = datetime.now()
        elapsed = (end_time - start_time).total_seconds()

        print("=" * 70)
        print("[OK] STATUS CHECK COMPLETE")
        print("=" * 70)
        print(f"Elapsed time: {elapsed:.2f} seconds")

        return 0

    except Exception as e:
        log.error(
            "Status check failed",
            error=str(e),
            error_type=type(e).__name__
        )
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
