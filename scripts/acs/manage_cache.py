"""
ACS Cache Management Utility

Comprehensive cache management for IPUMS ACS extracts including listing,
statistics, cleaning, validation, and export.

Usage:
    # List all cached extracts
    python scripts/acs/manage_cache.py --list

    # Show cache statistics
    python scripts/acs/manage_cache.py --stats

    # Clean caches older than 365 days
    python scripts/acs/manage_cache.py --clean --days 365

    # Dry run (show what would be deleted)
    python scripts/acs/manage_cache.py --clean --days 365 --dry-run

    # Validate cache integrity
    python scripts/acs/manage_cache.py --validate

    # Remove specific extract
    python scripts/acs/manage_cache.py --remove-extract usa:12345

    # Export cache manifest
    python scripts/acs/manage_cache.py --export manifest.json

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
import json
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
import structlog
from tabulate import tabulate

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.acs.cache_manager import (
    _load_registry,
    _save_registry,
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
        description="Manage ACS extract cache",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List cached extracts
  python scripts/acs/manage_cache.py --list

  # Show statistics
  python scripts/acs/manage_cache.py --stats

  # Clean old caches
  python scripts/acs/manage_cache.py --clean --days 365

  # Validate integrity
  python scripts/acs/manage_cache.py --validate
        """
    )

    # Actions
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all cached extracts"
    )

    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show cache statistics"
    )

    parser.add_argument(
        "--clean",
        action="store_true",
        help="Clean old caches (requires --days)"
    )

    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate cache integrity"
    )

    parser.add_argument(
        "--remove-extract",
        type=str,
        metavar="EXTRACT_ID",
        help="Remove specific extract (e.g., usa:12345)"
    )

    parser.add_argument(
        "--export",
        type=str,
        metavar="FILE",
        help="Export cache manifest to JSON file"
    )

    # Options
    parser.add_argument(
        "--days",
        type=int,
        help="Age threshold in days (for --clean)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without actually doing it"
    )

    parser.add_argument(
        "--keep-files",
        action="store_true",
        help="Remove from registry only, keep files on disk"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


def list_cached_extracts(verbose: bool = False) -> List[Dict[str, Any]]:
    """List all cached extracts with metadata.

    Args:
        verbose: Enable verbose output

    Returns:
        List of extract metadata dicts
    """
    log.info("Listing cached extracts")

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    if not extracts:
        print("\nNo cached extracts found.")
        print(f"Cache directory: {CACHE_ROOT}")
        return []

    # Build table
    rows = []
    for extract in extracts:
        extract_id = extract.get('extract_id', 'Unknown')
        state = extract.get('state', 'Unknown')
        year_range = extract.get('year_range', 'Unknown')
        timestamp = extract.get('registration_timestamp', 'Unknown')

        # Calculate age
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

        # Calculate size
        files = extract.get('files', {})
        total_size = 0
        for file_path in files.values():
            path = Path(file_path)
            if path.exists():
                total_size += path.stat().st_size

        size_mb = total_size / (1024 ** 2)

        rows.append([
            extract_id,
            state.title(),
            year_range,
            f"{size_mb:.2f} MB",
            age,
            len(files),
            timestamp[:10] if timestamp != "Unknown" else "Unknown"
        ])

    headers = ["Extract ID", "State", "Year Range", "Size", "Age", "Files", "Cached Date"]
    table = tabulate(rows, headers=headers, tablefmt="grid")

    print(f"\n{table}\n")
    print(f"Total cached extracts: {len(extracts)}")

    return extracts


def show_cache_statistics(verbose: bool = False) -> Dict[str, Any]:
    """Calculate and display cache statistics.

    Args:
        verbose: Enable verbose output

    Returns:
        Dict with statistics
    """
    log.info("Calculating cache statistics")

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    stats = {
        'total_extracts': len(extracts),
        'total_size_bytes': 0,
        'total_size_mb': 0,
        'oldest_cache_days': 0,
        'newest_cache_days': 0,
        'states': set(),
        'year_ranges': set()
    }

    if not extracts:
        print("\nNo cached extracts found.")
        return stats

    # Calculate statistics
    oldest_timestamp = None
    newest_timestamp = None

    for extract in extracts:
        # Size
        files = extract.get('files', {})
        for file_path in files.values():
            path = Path(file_path)
            if path.exists():
                stats['total_size_bytes'] += path.stat().st_size

        # States and year ranges
        if extract.get('state'):
            stats['states'].add(extract['state'])
        if extract.get('year_range'):
            stats['year_ranges'].add(extract['year_range'])

        # Age tracking
        timestamp = extract.get('registration_timestamp')
        if timestamp:
            try:
                reg_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                if oldest_timestamp is None or reg_time < oldest_timestamp:
                    oldest_timestamp = reg_time
                if newest_timestamp is None or reg_time > newest_timestamp:
                    newest_timestamp = reg_time
            except:
                pass

    # Calculate ages
    if oldest_timestamp:
        stats['oldest_cache_days'] = (datetime.now() - oldest_timestamp.replace(tzinfo=None)).days
    if newest_timestamp:
        stats['newest_cache_days'] = (datetime.now() - newest_timestamp.replace(tzinfo=None)).days

    stats['total_size_mb'] = stats['total_size_bytes'] / (1024 ** 2)

    # Estimate time saved (assuming 30 min average per extract without cache)
    time_saved_hours = (stats['total_extracts'] * 30) / 60

    # Print statistics
    print("\n" + "=" * 70)
    print("CACHE STATISTICS")
    print("=" * 70)
    print(f"\nTotal cached extracts: {stats['total_extracts']}")
    print(f"Total disk usage: {stats['total_size_mb']:.2f} MB ({stats['total_size_bytes']:,} bytes)")
    print(f"States covered: {len(stats['states'])} ({', '.join(sorted(stats['states']))})")
    print(f"Year ranges: {len(stats['year_ranges'])} ({', '.join(sorted(stats['year_ranges']))})")

    if stats['oldest_cache_days'] > 0:
        print(f"\nOldest cache: {stats['oldest_cache_days']} days ago")
    if stats['newest_cache_days'] >= 0:
        print(f"Newest cache: {stats['newest_cache_days']} day(s) ago")

    print(f"\nEstimated time saved: {time_saved_hours:.1f} hours (~{time_saved_hours * 60:.0f} minutes)")
    print(f"  (Assumes 30 min average IPUMS extract time without cache)")

    print("\n" + "=" * 70)

    return stats


def clean_old_caches(days_threshold: int, dry_run: bool = False, verbose: bool = False) -> Dict[str, Any]:
    """Remove caches older than threshold.

    Args:
        days_threshold: Remove caches older than this many days
        dry_run: Show what would be deleted without actually deleting
        verbose: Enable verbose output

    Returns:
        Dict with cleaning results
    """
    log.info(f"Cleaning caches older than {days_threshold} days", dry_run=dry_run)

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    results = {
        'total_checked': len(extracts),
        'to_remove': 0,
        'removed': 0,
        'kept': 0,
        'removed_extracts': []
    }

    threshold_date = datetime.now() - timedelta(days=days_threshold)

    for extract in extracts:
        timestamp = extract.get('registration_timestamp')
        if not timestamp:
            continue

        try:
            reg_time = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            age_days = (datetime.now() - reg_time.replace(tzinfo=None)).days

            if reg_time.replace(tzinfo=None) < threshold_date:
                results['to_remove'] += 1

                extract_id = extract.get('extract_id', 'Unknown')
                state = extract.get('state', 'Unknown')
                year_range = extract.get('year_range', 'Unknown')

                if not dry_run:
                    # Remove files
                    files = extract.get('files', {})
                    for file_path in files.values():
                        path = Path(file_path)
                        if path.exists():
                            if verbose:
                                log.info(f"Removing file: {path}")
                            path.unlink()

                    # Remove from registry
                    registry['extracts'].remove(extract)

                    results['removed'] += 1
                    log.info(f"Removed cache", extract_id=extract_id, age_days=age_days)
                else:
                    log.info(f"[DRY RUN] Would remove cache", extract_id=extract_id, age_days=age_days)

                results['removed_extracts'].append({
                    'extract_id': extract_id,
                    'state': state,
                    'year_range': year_range,
                    'age_days': age_days
                })
            else:
                results['kept'] += 1

        except Exception as e:
            log.warning(f"Skipping extract with invalid timestamp", error=str(e))

    # Save updated registry
    if not dry_run and results['removed'] > 0:
        _save_registry(registry)

    # Print results
    print("\n" + "=" * 70)
    if dry_run:
        print("CACHE CLEANING (DRY RUN)")
    else:
        print("CACHE CLEANING COMPLETE")
    print("=" * 70)

    print(f"\nAge threshold: {days_threshold} days")
    print(f"Total caches checked: {results['total_checked']}")
    print(f"Caches to remove: {results['to_remove']}")

    if not dry_run:
        print(f"Caches removed: {results['removed']}")
    print(f"Caches kept: {results['kept']}")

    if results['removed_extracts']:
        print(f"\nRemoved caches:")
        for removed in results['removed_extracts']:
            status = "[DRY RUN]" if dry_run else "[REMOVED]"
            print(f"  {status} {removed['extract_id']} ({removed['state']}, {removed['year_range']}, {removed['age_days']} days old)")

    print("\n" + "=" * 70)

    return results


def validate_cache_integrity(verbose: bool = False) -> Dict[str, Any]:
    """Validate integrity of all cached files.

    Args:
        verbose: Enable verbose output

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

    # Print results
    print("\n" + "=" * 70)
    print("CACHE VALIDATION")
    print("=" * 70)

    print(f"\nTotal cached extracts: {results['total_extracts']}")
    print(f"Valid extracts: {results['valid_extracts']}")
    print(f"Invalid extracts: {results['invalid_extracts']}")

    if results['missing_files']:
        print(f"\nMissing files ({len(results['missing_files'])}):")
        for missing in results['missing_files']:
            print(f"  [MISSING] {missing['extract_id']}: {missing['file_type']}")
            print(f"            {missing['path']}")

    print()
    if results['valid']:
        print("[OK] All cached files validated successfully")
    else:
        print("[FAIL] Cache validation failed - some files are missing")

    print("\n" + "=" * 70)

    return results


def remove_extract(extract_id: str, keep_files: bool = False, verbose: bool = False) -> bool:
    """Remove specific extract from cache.

    Args:
        extract_id: Extract ID to remove
        keep_files: If True, remove from registry only (keep files on disk)
        verbose: Enable verbose output

    Returns:
        True if removed successfully
    """
    log.info(f"Removing extract from cache", extract_id=extract_id, keep_files=keep_files)

    registry = _load_registry()
    extracts = registry.get('extracts', [])

    # Find extract
    extract_to_remove = None
    for extract in extracts:
        if extract.get('extract_id') == extract_id:
            extract_to_remove = extract
            break

    if not extract_to_remove:
        print(f"\n[ERROR] Extract not found in cache: {extract_id}")
        return False

    # Remove files if requested
    if not keep_files:
        files = extract_to_remove.get('files', {})
        for file_type, file_path in files.items():
            path = Path(file_path)
            if path.exists():
                if verbose:
                    log.info(f"Removing file: {path}")
                path.unlink()
                print(f"  Removed: {file_path}")

    # Remove from registry
    registry['extracts'].remove(extract_to_remove)
    _save_registry(registry)

    print(f"\n[OK] Extract removed from cache: {extract_id}")
    if keep_files:
        print("     (Files kept on disk)")

    return True


def export_manifest(output_file: str, verbose: bool = False) -> bool:
    """Export cache manifest to JSON file.

    Args:
        output_file: Output file path
        verbose: Enable verbose output

    Returns:
        True if exported successfully
    """
    log.info(f"Exporting cache manifest", output_file=output_file)

    registry = _load_registry()

    try:
        output_path = Path(output_file)
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(registry, f, indent=2)

        print(f"\n[OK] Cache manifest exported to: {output_path}")
        print(f"     Extracts: {len(registry.get('extracts', []))}")

        return True

    except Exception as e:
        log.error(f"Failed to export manifest", error=str(e))
        print(f"\n[ERROR] Failed to export manifest: {e}")
        return False


def main():
    """Main cache management workflow."""
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    print("=" * 70)
    print("ACS CACHE MANAGEMENT")
    print("=" * 70)
    print(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Cache directory: {CACHE_ROOT}")
    print()

    try:
        # List caches
        if args.list:
            list_cached_extracts(verbose=args.verbose)

        # Show statistics
        if args.stats:
            show_cache_statistics(verbose=args.verbose)

        # Clean old caches
        if args.clean:
            if not args.days:
                print("[ERROR] --clean requires --days argument")
                return 1

            clean_old_caches(
                days_threshold=args.days,
                dry_run=args.dry_run,
                verbose=args.verbose
            )

        # Validate cache
        if args.validate:
            results = validate_cache_integrity(verbose=args.verbose)
            if not results['valid']:
                return 1

        # Remove specific extract
        if args.remove_extract:
            success = remove_extract(
                extract_id=args.remove_extract,
                keep_files=args.keep_files,
                verbose=args.verbose
            )
            if not success:
                return 1

        # Export manifest
        if args.export:
            success = export_manifest(
                output_file=args.export,
                verbose=args.verbose
            )
            if not success:
                return 1

        # Default: show help
        if not any([args.list, args.stats, args.clean, args.validate,
                   args.remove_extract, args.export]):
            print("No action specified. Use --help for usage information.")
            print()
            print("Quick commands:")
            print("  --list           List all cached extracts")
            print("  --stats          Show cache statistics")
            print("  --validate       Validate cache integrity")
            return 1

        # Summary
        end_time = datetime.now()
        elapsed = (end_time - start_time).total_seconds()

        print(f"\n[OK] Cache management complete")
        print(f"Elapsed time: {elapsed:.2f} seconds")

        return 0

    except Exception as e:
        log.error(
            "Cache management failed",
            error=str(e),
            error_type=type(e).__name__
        )
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
