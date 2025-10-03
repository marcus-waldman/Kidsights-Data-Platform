"""
NHIS Data Extraction Pipeline - Main Script

Extracts National Health Interview Survey data from IPUMS Health Surveys API.
Implements intelligent caching to avoid re-downloading identical extracts.

Usage:
    # First run (submits to IPUMS API, ~30-45 min wait)
    python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

    # Second run (retrieves from cache, ~10 sec)
    python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

    # Force refresh (bypass cache)
    python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --force-refresh

    # Custom config file
    python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --config my_config.yaml

    # Verbose output (shows API polling status)
    python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --verbose

Command-line Arguments:
    --year-range: Year range for NHIS data (e.g., 2019-2024)
    --config: Optional path to config file (defaults to config/sources/nhis/nhis-{year_range}.yaml)
    --force-refresh: Bypass cache and submit new extract
    --no-cache: Disable caching entirely (not recommended)
    --output-dir: Optional output directory (defaults to data/nhis/{year_range}/)
    --verbose: Print detailed status updates during extraction

Output:
    - data/nhis/{year_range}/raw.feather: Raw IPUMS data in Feather format
    - data/nhis/{year_range}/metadata.json: Extract metadata (variables, timestamps, etc.)
    - data/nhis/cache/extracts/{extract_id}/: Cached extract files (if caching enabled)
"""

import argparse
import json
import sys
import structlog
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

# Import our NHIS pipeline modules
from python.nhis.config_manager import get_nhis_config, load_config, validate_config
from python.nhis.extract_manager import get_or_submit_extract
from python.nhis.cache_manager import generate_extract_signature
from python.nhis.data_loader import load_nhis_data, convert_to_feather

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Extract NHIS data from IPUMS Health Surveys API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Extract 2019-2024 data (uses cache if available)
  python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

  # Force fresh extract (bypass cache)
  python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --force-refresh

  # Verbose output
  python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024 --verbose

For more information, see: docs/nhis/pipeline_usage.md
        """
    )

    # Required arguments
    parser.add_argument(
        "--year-range",
        type=str,
        required=True,
        help="Year range for NHIS data (e.g., 2019-2024)"
    )

    # Optional arguments
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to configuration file (defaults to config/sources/nhis/nhis-{year_range}.yaml)"
    )

    parser.add_argument(
        "--force-refresh",
        action="store_true",
        help="Force new extract submission (bypass cache)"
    )

    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable caching entirely (not recommended)"
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Output directory for extracted data (defaults to data/nhis/{year_range}/)"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed status updates during extraction"
    )

    return parser.parse_args()


def main():
    """Main extraction workflow."""

    args = parse_arguments()

    log.info(
        "Starting NHIS data extraction",
        year_range=args.year_range,
        force_refresh=args.force_refresh,
        verbose=args.verbose
    )

    try:
        # 1. Load configuration
        if args.config:
            log.info("Loading custom config", config_path=args.config)
            config = load_config(args.config)
            validate_config(config)
        else:
            log.info("Loading default config", year_range=args.year_range)
            config = get_nhis_config(args.year_range)

        # 2. Set output directory
        if args.output_dir:
            output_dir = Path(args.output_dir)
        else:
            output_dir = Path(f"data/nhis/{args.year_range}")

        output_dir.mkdir(parents=True, exist_ok=True)

        log.info("Output directory", path=str(output_dir))

        # 3. Extract or retrieve from cache
        log.info("Starting extract workflow")

        data_file, from_cache = get_or_submit_extract(
            config=config,
            output_dir=output_dir,
            force_new=args.force_refresh,
            verbose=args.verbose
        )

        if from_cache:
            print(f"\n[OK] Retrieved from cache: {data_file}")
        else:
            print(f"\n[OK] Extract completed: {data_file}")

        # 4. Find DDI file
        ddi_files = list(output_dir.glob("*.xml"))
        if not ddi_files:
            log.error("No DDI file found", output_dir=str(output_dir))
            raise FileNotFoundError(f"No DDI file found in {output_dir}")

        ddi_file = ddi_files[0]

        # 5. Load data
        log.info("Loading NHIS data from fixed-width format")
        df = load_nhis_data(str(data_file), str(ddi_file))

        print(f"\n[OK] Loaded {len(df):,} records with {len(df.columns)} variables")

        # 6. Convert to Feather format
        feather_path = output_dir / "raw.feather"
        log.info("Converting to Feather format", path=str(feather_path))

        convert_to_feather(df, str(feather_path))

        print(f"[OK] Saved to Feather: {feather_path}")

        # 7. Save metadata
        metadata = {
            "year_range": args.year_range,
            "years": config.get('years'),
            "samples": config.get('samples'),
            "extracted_at": datetime.utcnow().isoformat() + "Z",
            "from_cache": from_cache,
            "record_count": len(df),
            "variable_count": len(df.columns),
            "variables": list(df.columns),
            "output_dir": str(output_dir),
            "feather_file": str(feather_path),
            "extract_signature": generate_extract_signature(config)
        }

        metadata_path = output_dir / "metadata.json"
        with open(metadata_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2)

        log.info("Metadata saved", path=str(metadata_path))

        # 8. Success summary
        print("\n" + "="*70)
        print("NHIS EXTRACTION COMPLETE")
        print("="*70)
        print(f"Year Range: {args.year_range}")
        print(f"Records: {len(df):,}")
        print(f"Variables: {len(df.columns)}")
        print(f"Output: {feather_path}")
        print(f"Metadata: {metadata_path}")
        print(f"Source: {'Cache' if from_cache else 'IPUMS API'}")
        print("="*70)

        log.info("NHIS extraction completed successfully")

        return 0

    except KeyboardInterrupt:
        log.warning("Extraction interrupted by user")
        print("\n\nExtraction interrupted by user (Ctrl+C)")
        return 130

    except Exception as e:
        log.error("Extraction failed", error=str(e), error_type=type(e).__name__)
        print(f"\n\n[ERROR] {e}")
        print("\nFor troubleshooting, see: docs/nhis/pipeline_usage.md")
        return 1


if __name__ == "__main__":
    sys.exit(main())
