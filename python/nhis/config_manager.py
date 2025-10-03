"""
Configuration Manager for NHIS Pipeline

Handles loading, merging, and validating YAML configuration files for
NHIS data extracts. Unlike ACS, NHIS extracts are nationwide with no case selection.

Functions:
    load_config: Load configuration from YAML file
    merge_configs: Merge template with year-specific overrides
    validate_config: Validate configuration parameters
    get_nhis_config: Convenience function to load NHIS config
"""

import yaml
import structlog
from pathlib import Path
from typing import Dict, Any, List, Optional
from copy import deepcopy

# Configure structured logging
log = structlog.get_logger()

# Default paths
DEFAULT_TEMPLATE_PATH = "config/sources/nhis/nhis-template.yaml"
DEFAULT_SAMPLES_PATH = "config/sources/nhis/samples.yaml"


def load_config(config_path: str) -> Dict[str, Any]:
    """Load configuration from YAML file.

    Args:
        config_path: Path to YAML configuration file

    Returns:
        Dict[str, Any]: Parsed configuration dictionary

    Raises:
        FileNotFoundError: If config file doesn't exist
        yaml.YAMLError: If YAML parsing fails

    Example:
        >>> config = load_config("config/sources/nhis/nhis-2019-2024.yaml")
        >>> print(config['years'])
        [2019, 2020, 2021, 2022, 2023, 2024]
    """
    config_file = Path(config_path)

    log.debug("Loading configuration", path=config_path)

    if not config_file.exists():
        log.error("Configuration file not found", path=config_path)
        raise FileNotFoundError(
            f"Configuration file not found: {config_path}\n"
            f"Available configs should be in: config/sources/nhis/"
        )

    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)

        if config is None:
            log.error("Configuration file is empty", path=config_path)
            raise ValueError(f"Configuration file is empty: {config_path}")

        log.info("Configuration loaded successfully", path=config_path, keys=list(config.keys()))
        return config

    except yaml.YAMLError as e:
        log.error("Failed to parse YAML configuration", path=config_path, error=str(e))
        raise yaml.YAMLError(
            f"Failed to parse YAML configuration: {config_path}\n"
            f"Error: {e}"
        ) from e


def merge_configs(
    base_config: Dict[str, Any],
    override_config: Dict[str, Any],
    deep: bool = True
) -> Dict[str, Any]:
    """Merge two configuration dictionaries.

    The override_config values take precedence over base_config.
    Supports deep merging for nested dictionaries.

    Args:
        base_config: Base configuration (e.g., template)
        override_config: Override configuration (e.g., year-specific)
        deep: If True, recursively merge nested dicts. If False, shallow merge.

    Returns:
        Dict[str, Any]: Merged configuration

    Example:
        >>> template = load_config("config/sources/nhis/nhis-template.yaml")
        >>> year_config = {"years": [2019, 2020, 2021, 2022, 2023, 2024]}
        >>> merged = merge_configs(template, year_config)
        >>> print(merged['years'])
        [2019, 2020, 2021, 2022, 2023, 2024]
    """
    log.debug("Merging configurations", deep=deep)

    if not deep:
        # Shallow merge: override simply replaces base
        merged = {**base_config, **override_config}
        return merged

    # Deep merge: recursively merge nested dictionaries
    merged = deepcopy(base_config)

    def _deep_merge(base_dict: Dict, override_dict: Dict) -> Dict:
        """Recursively merge dictionaries."""
        for key, value in override_dict.items():
            if key in base_dict and isinstance(base_dict[key], dict) and isinstance(value, dict):
                # Recursively merge nested dicts
                base_dict[key] = _deep_merge(base_dict[key], value)
            else:
                # Override value (or add new key)
                base_dict[key] = value
        return base_dict

    merged = _deep_merge(merged, override_config)

    log.debug("Configuration merge complete", merged_keys=list(merged.keys()))
    return merged


def validate_config(config: Dict[str, Any]) -> bool:
    """Validate NHIS extract configuration parameters.

    Checks for required fields, valid values, and logical consistency.
    NHIS has simpler validation than ACS (no state filters, no case selection).

    Args:
        config: Configuration dictionary to validate

    Returns:
        bool: True if valid, raises exception otherwise

    Raises:
        ValueError: If configuration is invalid with detailed error message

    Example:
        >>> config = load_config("config/sources/nhis/nhis-2019-2024.yaml")
        >>> validate_config(config)
        True
    """
    log.debug("Validating configuration")

    errors = []

    # Required top-level fields
    required_fields = [
        'years', 'samples', 'collection', 'variables'
    ]

    for field in required_fields:
        if field not in config:
            errors.append(f"Missing required field: '{field}'")

    # Validate collection
    if 'collection' in config and config['collection'] != 'nhis':
        errors.append(f"Invalid collection: '{config['collection']}'. Must be 'nhis' for NHIS data.")

    # Validate years is a list
    if 'years' in config:
        if not isinstance(config['years'], list):
            errors.append("'years' must be a list of years (e.g., [2019, 2020, 2021])")
        elif len(config['years']) == 0:
            errors.append("'years' list cannot be empty")
        else:
            # Validate each year is an integer in valid range
            for year in config['years']:
                try:
                    year_int = int(year)
                    if not (2000 <= year_int <= 2030):
                        errors.append(f"Invalid year: {year}. Expected range: 2000-2030")
                except (ValueError, TypeError):
                    errors.append(f"Invalid year: {year}. Must be an integer.")

    # Validate samples is a list matching years
    if 'years' in config and 'samples' in config:
        if not isinstance(config['samples'], list):
            errors.append("'samples' must be a list of sample codes (e.g., ['ih2019', 'ih2020'])")
        elif len(config['samples']) != len(config['years']):
            errors.append(
                f"'samples' length ({len(config['samples'])}) must match 'years' length ({len(config['years'])})"
            )

    # Validate variables structure
    if 'variables' in config:
        if not isinstance(config['variables'], dict):
            errors.append("'variables' must be a dictionary with variable groups")
        else:
            # Check for at least some variables
            total_vars = sum(
                len(vars_list) if isinstance(vars_list, list) else 1
                for vars_list in config['variables'].values()
            )
            if total_vars == 0:
                errors.append("No variables specified in configuration")

    # Validate cache settings if present
    if 'cache' in config:
        cache = config['cache']
        if 'enabled' in cache and not isinstance(cache['enabled'], bool):
            errors.append("cache.enabled must be a boolean")
        if 'max_age_days' in cache:
            try:
                max_age = int(cache['max_age_days'])
                if max_age < 0:
                    errors.append("cache.max_age_days must be non-negative")
            except (ValueError, TypeError):
                errors.append("cache.max_age_days must be an integer")

    # Validate output directory if present
    if 'output_directory' in config:
        if not isinstance(config['output_directory'], str):
            errors.append("output_directory must be a string")

    # If any errors, raise exception
    if errors:
        error_msg = "Configuration validation failed:\n" + "\n".join(f"  - {e}" for e in errors)
        log.error("Configuration validation failed", errors=errors)
        raise ValueError(error_msg)

    log.info("Configuration validation passed")
    return True


def get_nhis_config(
    year_range: str,
    template_path: str = DEFAULT_TEMPLATE_PATH,
    validate: bool = True
) -> Dict[str, Any]:
    """Load and validate NHIS configuration for specified year range.

    Convenience function that:
    1. Loads the template configuration
    2. Loads the year-specific configuration
    3. Merges them (year-specific overrides template)
    4. Optionally validates the result

    Args:
        year_range: Year range (e.g., "2019-2024")
        template_path: Path to template configuration
        validate: Whether to validate merged configuration

    Returns:
        Dict[str, Any]: Merged and validated configuration

    Raises:
        FileNotFoundError: If config files don't exist
        ValueError: If configuration is invalid (when validate=True)

    Example:
        >>> config = get_nhis_config("2019-2024")
        >>> print(config['collection'])
        nhis
        >>> print(len(config['years']))
        6
    """
    log.info("Loading NHIS configuration", year_range=year_range)

    # Construct year config path
    year_config_path = f"config/sources/nhis/nhis-{year_range}.yaml"

    # Load template
    log.debug("Loading template configuration", path=template_path)
    template = load_config(template_path)

    # Load year-specific config
    log.debug("Loading year configuration", path=year_config_path)
    year_config = load_config(year_config_path)

    # Merge configurations (year-specific overrides template)
    merged = merge_configs(template, year_config, deep=True)

    # Validate if requested
    if validate:
        validate_config(merged)

    log.info("NHIS configuration ready", year_range=year_range, years=merged.get('years'))
    return merged


def load_samples_mapping() -> Dict[str, Any]:
    """Load NHIS samples mapping (years to sample codes).

    Returns:
        Dict with NHIS sample code mappings

    Example:
        >>> samples = load_samples_mapping()
        >>> print(samples['2019'])
        ih2019
    """
    log.debug("Loading NHIS samples mapping")

    try:
        samples = load_config(DEFAULT_SAMPLES_PATH)
        log.debug("Samples mapping loaded", sample_count=len(samples.get('samples', {})))
        return samples
    except Exception as e:
        log.warning("Failed to load samples mapping", error=str(e))
        return {}
