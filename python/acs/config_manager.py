"""
Configuration Manager for ACS Pipeline

Handles loading, merging, and validating YAML configuration files for
state-specific ACS extracts.

Functions:
    load_config: Load configuration from YAML file
    merge_configs: Merge template with state-specific overrides
    validate_config: Validate configuration parameters
    get_state_config: Convenience function to load state config
"""

import yaml
import structlog
from pathlib import Path
from typing import Dict, Any, List, Optional
from copy import deepcopy

# Configure structured logging
log = structlog.get_logger()

# Default paths
DEFAULT_TEMPLATE_PATH = "config/sources/acs/acs-template.yaml"
DEFAULT_STATES_PATH = "config/sources/acs/states.yaml"
DEFAULT_SAMPLES_PATH = "config/sources/acs/samples.yaml"
DEFAULT_VARIABLES_PATH = "config/acs_variables.yaml"


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
        >>> config = load_config("config/sources/acs/nebraska-2019-2023.yaml")
        >>> print(config['state'])
        nebraska
    """
    config_file = Path(config_path)

    log.debug("Loading configuration", path=config_path)

    if not config_file.exists():
        log.error("Configuration file not found", path=config_path)
        raise FileNotFoundError(
            f"Configuration file not found: {config_path}\n"
            f"Available configs should be in: config/sources/acs/"
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
        override_config: Override configuration (e.g., state-specific)
        deep: If True, recursively merge nested dicts. If False, shallow merge.

    Returns:
        Dict[str, Any]: Merged configuration

    Example:
        >>> template = load_config("config/sources/acs/acs-template.yaml")
        >>> state = {"state": "nebraska", "state_fip": 31}
        >>> merged = merge_configs(template, state)
        >>> print(merged['state'])
        nebraska
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
    """Validate ACS extract configuration parameters.

    Checks for required fields, valid values, and logical consistency.

    Args:
        config: Configuration dictionary to validate

    Returns:
        bool: True if valid, raises exception otherwise

    Raises:
        ValueError: If configuration is invalid with detailed error message

    Example:
        >>> config = load_config("config/sources/acs/nebraska-2019-2023.yaml")
        >>> validate_config(config)
        True
    """
    log.debug("Validating configuration")

    errors = []

    # Required top-level fields
    required_fields = [
        'state', 'state_fip', 'acs_sample', 'year_range',
        'collection', 'variables'
    ]

    for field in required_fields:
        if field not in config:
            errors.append(f"Missing required field: '{field}'")

    # Validate state_fip is an integer
    if 'state_fip' in config:
        try:
            state_fip = int(config['state_fip'])
            if not (1 <= state_fip <= 78):  # Valid FIPS range (includes territories)
                errors.append(f"Invalid state_fip: {state_fip}. Must be 1-78.")
        except (ValueError, TypeError):
            errors.append(f"Invalid state_fip: {config['state_fip']}. Must be an integer.")

    # Validate collection
    if 'collection' in config and config['collection'] != 'usa':
        errors.append(f"Invalid collection: '{config['collection']}'. Must be 'usa' for ACS data.")

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

    # Validate filters if present
    if 'filters' in config:
        filters = config['filters']
        if 'age_min' in filters and 'age_max' in filters:
            try:
                age_min = int(filters['age_min'])
                age_max = int(filters['age_max'])
                if age_min > age_max:
                    errors.append(f"age_min ({age_min}) > age_max ({age_max})")
                if age_min < 0 or age_max > 120:
                    errors.append(f"Invalid age range: {age_min}-{age_max}")
            except (ValueError, TypeError):
                errors.append("age_min and age_max must be integers")

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

    # If any errors, raise exception
    if errors:
        error_msg = "Configuration validation failed:\n" + "\n".join(f"  - {e}" for e in errors)
        log.error("Configuration validation failed", errors=errors)
        raise ValueError(error_msg)

    log.info("Configuration validation passed")
    return True


def get_state_config(
    state: str,
    year_range: str,
    template_path: str = DEFAULT_TEMPLATE_PATH,
    validate: bool = True
) -> Dict[str, Any]:
    """Load and validate state-specific configuration.

    Convenience function that:
    1. Loads the template configuration
    2. Loads the state-specific configuration
    3. Merges them (state overrides template)
    4. Optionally validates the result

    Args:
        state: State name (e.g., "nebraska")
        year_range: Year range (e.g., "2019-2023")
        template_path: Path to template configuration
        validate: Whether to validate merged configuration

    Returns:
        Dict[str, Any]: Merged and validated configuration

    Raises:
        FileNotFoundError: If config files don't exist
        ValueError: If configuration is invalid (when validate=True)

    Example:
        >>> config = get_state_config("nebraska", "2019-2023")
        >>> print(config['state_fip'])
        31
    """
    log.info("Loading state configuration", state=state, year_range=year_range)

    # Construct state config path
    state_config_path = f"config/sources/acs/{state}-{year_range}.yaml"

    # Load template
    log.debug("Loading template configuration", path=template_path)
    template = load_config(template_path)

    # Load state-specific config
    log.debug("Loading state configuration", path=state_config_path)
    state_config = load_config(state_config_path)

    # Merge configurations (state overrides template)
    merged = merge_configs(template, state_config, deep=True)

    # Validate if requested
    if validate:
        validate_config(merged)

    log.info("State configuration ready", state=state, year_range=year_range)
    return merged


def load_auxiliary_configs() -> Dict[str, Dict[str, Any]]:
    """Load auxiliary configuration files (states, samples, variables).

    Returns:
        Dict with keys: 'states', 'samples', 'variables'

    Example:
        >>> aux = load_auxiliary_configs()
        >>> print(aux['states']['nebraska']['fip'])
        31
    """
    log.debug("Loading auxiliary configuration files")

    auxiliary = {}

    # Load states mapping
    try:
        auxiliary['states'] = load_config(DEFAULT_STATES_PATH)
        log.debug("States config loaded", states_count=len(auxiliary['states'].get('states', {})))
    except Exception as e:
        log.warning("Failed to load states config", error=str(e))
        auxiliary['states'] = {}

    # Load samples mapping
    try:
        auxiliary['samples'] = load_config(DEFAULT_SAMPLES_PATH)
        log.debug("Samples config loaded")
    except Exception as e:
        log.warning("Failed to load samples config", error=str(e))
        auxiliary['samples'] = {}

    # Load variables definitions
    try:
        auxiliary['variables'] = load_config(DEFAULT_VARIABLES_PATH)
        log.debug("Variables config loaded")
    except Exception as e:
        log.warning("Failed to load variables config", error=str(e))
        auxiliary['variables'] = {}

    return auxiliary
