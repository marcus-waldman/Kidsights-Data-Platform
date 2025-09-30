"""
ACS Data Extraction Pipeline - Main Script

Extracts American Community Survey data from IPUMS API for statistical raking.
Implements intelligent caching to avoid re-downloading identical extracts.

Usage:
    # First run (submits to IPUMS API, ~45 min wait)
    python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023

    # Second run (retrieves from cache, ~10 sec)
    python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023

    # Force refresh (bypass cache)
    python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023 --force-refresh

    # Custom config file
    python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023 --config my_config.yaml

Command-line Arguments:
    --state: State name (e.g., nebraska, iowa, kansas)
    --year-range: Year range for 5-year ACS (e.g., 2019-2023)
    --config: Optional path to config file (defaults to config/sources/acs/{state}-{year_range}.yaml)
    --force-refresh: Bypass cache and submit new extract
    --no-cache: Disable caching entirely (not recommended)
    --output-dir: Optional output directory (defaults to data/acs/{state}/{year_range}/)

Output:
    - data/acs/{state}/{year_range}/raw.feather: Raw IPUMS data in Feather format
    - data/acs/{state}/{year_range}/metadata.json: Extract metadata (variables, timestamps, etc.)
    - data/acs/cache/extracts/{extract_id}/: Cached extract files (if caching enabled)
"""

import argparse
import json
import sys
import structlog
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional

# Import our ACS pipeline modules
from python.acs.config_manager import get_state_config, load_config, validate_config
from python.acs.extract_manager import get_or_submit_extract
from python.acs.cache_manager import generate_extract_signature
from python.acs.data_loader import load_and_convert, validate_ipums_data

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Extract ACS data from IPUMS API for statistical raking",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Extract Nebraska 2019-2023 data (uses cache if available)
  python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023

  # Force fresh extract (bypass cache)
  python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023 --force-refresh

  # Use custom config file
  python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023 --config my_acs_config.yaml

For more information, see: docs/acs/pipeline_usage.md
        """
    )

    # Required arguments
    parser.add_argument(
        "--state",
        type=str,
        required=True,
        help="State name (lowercase, e.g., nebraska, iowa, kansas)"
    )

    parser.add_argument(
        "--year-range",
        type=str,
        required=True,
        help="Year range for 5-year ACS sample (e.g., 2019-2023)"
    )

    # Optional arguments
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to configuration file (defaults to config/sources/acs/{state}-{year_range}.yaml)"
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Output directory for processed data (defaults to data/acs/{state}/{year_range}/)"
    )

    # Cache control flags
    parser.add_argument(
        "--force-refresh",
        action="store_true",
        help="Bypass cache and submit new extract to IPUMS API"
    )

    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable caching entirely (not recommended - extracts take 15-60 min)"
    )

    # Logging verbosity
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Validate arguments
    if args.no_cache and args.force_refresh:
        parser.error("--no-cache and --force-refresh are mutually exclusive")

    return args


def load_configuration(state: str, year_range: str, config_path: Optional[str] = None) -> Dict[str, Any]:
    """Load and validate ACS extraction configuration.

    Args:
        state: State name (e.g., nebraska)
        year_range: Year range (e.g., 2019-2023)
        config_path: Optional path to config file

    Returns:
        Dict: Validated configuration dictionary

    Raises:
        FileNotFoundError: If config file not found
        ValueError: If configuration is invalid
    """
    log.info("Loading configuration", state=state, year_range=year_range, config_path=config_path)

    if config_path:
        # Load custom config file
        log.debug("Loading custom config file", path=config_path)
        config = load_config(config_path)
        validate_config(config)
    else:
        # Load standard state config (template + state overrides)
        log.debug("Loading standard state config")
        config = get_state_config(state, year_range, validate=True)

    log.info("Configuration loaded successfully", state=config.get('state'), year_range=config.get('year_range'))
    return config


def create_output_directory(state: str, year_range: str, custom_output_dir: Optional[str] = None) -> Path:
    """Create output directory for processed data.

    Args:
        state: State name
        year_range: Year range
        custom_output_dir: Optional custom output directory

    Returns:
        Path: Output directory path
    """
    if custom_output_dir:
        output_dir = Path(custom_output_dir)
    else:
        output_dir = Path(f"data/acs/{state}/{year_range}")

    output_dir.mkdir(parents=True, exist_ok=True)
    log.info("Output directory created", path=str(output_dir))

    return output_dir


def save_metadata(
    output_dir: Path,
    config: Dict[str, Any],
    extract_id: str,
    from_cache: bool,
    file_paths: Dict[str, str]
) -> None:
    """Save extract metadata to JSON file.

    Args:
        output_dir: Output directory
        config: Configuration dictionary
        extract_id: IPUMS extract ID
        from_cache: Whether data was retrieved from cache
        file_paths: Paths to extract files
    """
    metadata = {
        "extract_id": extract_id,
        "state": config.get('state'),
        "state_fip": config.get('state_fip'),
        "year_range": config.get('year_range'),
        "acs_sample": config.get('acs_sample'),
        "from_cache": from_cache,
        "extraction_timestamp": datetime.utcnow().isoformat() + "Z",
        "extract_signature": generate_extract_signature(config),
        "variables": config.get('variables', {}),
        "filters": config.get('filters', {}),
        "case_selections": config.get('case_selections', {}),
        "file_paths": file_paths,
        "ipumspy_version": "0.7.0"
    }

    metadata_path = output_dir / "metadata.json"
    with open(metadata_path, 'w', encoding='utf-8') as f:
        json.dump(metadata, f, indent=2)

    log.info("Metadata saved", path=str(metadata_path))


def main():
    """Main extraction pipeline."""
    # Parse arguments
    args = parse_arguments()

    # Configure logging
    if args.verbose:
        structlog.configure(
            wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG)
        )

    log.info(
        "Starting ACS data extraction pipeline",
        state=args.state,
        year_range=args.year_range,
        force_refresh=args.force_refresh,
        no_cache=args.no_cache
    )

    try:
        # 1. Load configuration
        log.info("=" * 60)
        log.info("STEP 1: Load Configuration")
        log.info("=" * 60)

        config = load_configuration(args.state, args.year_range, args.config)

        # Override cache settings if --no-cache specified
        if args.no_cache:
            log.warning("Caching disabled via --no-cache flag")
            config['cache'] = {'enabled': False}

        # 2. Create output directory
        log.info("=" * 60)
        log.info("STEP 2: Create Output Directory")
        log.info("=" * 60)

        output_dir = create_output_directory(args.state, args.year_range, args.output_dir)

        # 3. Get or submit extract (with caching)
        log.info("=" * 60)
        log.info("STEP 3: Get or Submit Extract")
        log.info("=" * 60)

        if args.force_refresh:
            log.warning("Force refresh requested - bypassing cache")

        # This function handles the entire cache-first workflow
        extract_id, file_paths, from_cache = get_or_submit_extract(
            config=config,
            force_refresh=args.force_refresh
        )

        if from_cache:
            log.info("✓ Data retrieved from cache (~10 sec)", extract_id=extract_id)
        else:
            log.info("✓ New extract completed and cached", extract_id=extract_id)

        # 4. Load data and convert to Feather format
        log.info("=" * 60)
        log.info("STEP 4: Load Data and Convert to Feather Format")
        log.info("=" * 60)

        raw_data_path = file_paths.get('raw_data')
        ddi_path = file_paths.get('ddi_codebook')
        feather_path = output_dir / "raw.feather"

        log.info("Loading IPUMS data and converting to Feather",
                 input=raw_data_path, output=str(feather_path))

        # Load and convert in one step
        df = load_and_convert(
            data_path=raw_data_path,
            ddi_path=ddi_path,
            output_path=str(feather_path)
        )

        log.info(
            "Data loaded and converted successfully",
            rows=len(df),
            columns=len(df.columns),
            output=str(feather_path)
        )

        # 4.5 Validate data
        log.info("Validating IPUMS data quality")
        validation_results = validate_ipums_data(df)

        if validation_results['valid']:
            log.info("✓ Data validation passed")
        else:
            log.warning("⚠ Data validation issues found", issues=validation_results['issues'])
            # Continue anyway - validation issues are warnings, not errors

        # 5. Save metadata
        log.info("=" * 60)
        log.info("STEP 5: Save Metadata")
        log.info("=" * 60)

        save_metadata(output_dir, config, extract_id, from_cache, file_paths)

        # 6. Summary
        log.info("=" * 60)
        log.info("EXTRACTION PIPELINE COMPLETE")
        log.info("=" * 60)

        summary = {
            "Extract ID": extract_id,
            "State": config.get('state'),
            "Year Range": config.get('year_range'),
            "From Cache": "Yes" if from_cache else "No",
            "Records": len(df),
            "Variables": len(df.columns),
            "Output Directory": str(output_dir),
            "Feather File": str(feather_path),
            "Raw Data (cached)": file_paths.get('raw_data'),
            "DDI Codebook": file_paths.get('ddi_codebook', 'N/A'),
            "Data Valid": "Yes" if validation_results['valid'] else "Issues Found"
        }

        for key, value in summary.items():
            log.info(f"{key}: {value}")

        log.info("✓ Pipeline completed successfully")
        return 0

    except FileNotFoundError as e:
        log.error("Configuration file not found", error=str(e))
        log.error("Check that config file exists at expected path")
        return 1

    except ValueError as e:
        log.error("Configuration validation failed", error=str(e))
        return 1

    except Exception as e:
        log.error(
            "Pipeline failed with unexpected error",
            error=str(e),
            error_type=type(e).__name__
        )
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
