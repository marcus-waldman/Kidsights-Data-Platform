"""
Extract Builder for NHIS Pipeline

Constructs IPUMS Health Surveys (NHIS) extract requests from configuration files.
Handles variable selection for nationwide, all-ages extraction without case selection.

Functions:
    build_extract: Main function to build extract from config
    build_variable_list: Construct variable list
    build_extract_description: Generate human-readable extract description
    get_extract_info: Extract metadata for logging/caching
"""

import structlog
from typing import Dict, Any, List, Optional
from ipumspy import MicrodataExtract, Variable

# Configure structured logging
log = structlog.get_logger()


def build_variable_list(config: Dict[str, Any]) -> List[Variable]:
    """Build list of IPUMS Variable objects from configuration.

    Args:
        config: Configuration dictionary with 'variables' section

    Returns:
        List[Variable]: List of Variable objects ready for extract request

    Note:
        NHIS variables are simpler than ACS - no attached characteristics needed
        since parent variables (PAR1AGE, PAR2AGE, etc.) are already in dataset.

    Example:
        >>> config = {'variables': {
        ...     'identifiers': ['YEAR', 'SERIAL', 'PERNUM'],
        ...     'demographics': ['AGE', 'SEX']
        ... }}
        >>> vars = build_variable_list(config)
        >>> len(vars)
        5
    """
    log.debug("Building variable list from configuration")

    variables = []
    variable_groups = config.get('variables', {})

    for group_name, var_list in variable_groups.items():
        log.debug(f"Processing variable group: {group_name}", count=len(var_list))

        for var_spec in var_list:
            # Handle simple string variable names
            if isinstance(var_spec, str):
                variables.append(Variable(name=var_spec))
                log.debug(f"Added variable: {var_spec}")

            # Handle variable objects (for future extensibility)
            elif isinstance(var_spec, dict):
                var_name = var_spec.get('name')
                if not var_name:
                    log.warning("Variable spec missing 'name' field", spec=var_spec)
                    continue

                variables.append(Variable(name=var_name))
                log.debug(f"Added variable: {var_name}")

    log.info(f"Built variable list", total_variables=len(variables))
    return variables


def build_extract_description(config: Dict[str, Any]) -> str:
    """Generate human-readable extract description for NHIS.

    Args:
        config: Configuration dictionary

    Returns:
        str: Extract description

    Example:
        >>> config = {
        ...     'years': [2019, 2020, 2021, 2022, 2023, 2024],
        ...     'description': 'NHIS ${years} for Kidsights research'
        ... }
        >>> desc = build_extract_description(config)
        >>> print(desc)
        NHIS 2019-2024 (6 years) for Kidsights research, nationwide all ages
    """
    # Use explicit description if provided with template substitution
    if 'description' in config and config['description']:
        desc = config['description']

        # Build years string
        years = config.get('years', [])
        if years:
            year_range = f"{min(years)}-{max(years)}"
            desc = desc.replace('${years}', year_range)
            desc = desc.replace('${year_count}', str(len(years)))

        return desc

    # Build description from components
    years = config.get('years', [])

    if years:
        year_min = min(years)
        year_max = max(years)
        year_count = len(years)
        year_str = f"{year_min}-{year_max} ({year_count} years)"
    else:
        year_str = "Unknown years"

    description = f"NHIS {year_str} for Kidsights research, nationwide all ages"

    return description


def build_extract(
    config: Dict[str, Any],
    data_format: str = "fixed_width"
) -> MicrodataExtract:
    """Build IPUMS NHIS extract request from configuration.

    Main function that orchestrates extract building. NHIS extracts are simpler
    than ACS: nationwide with no case selection, multiple annual samples.

    Args:
        config: Configuration dictionary (validated)
        data_format: Data format ('csv' or 'fixed_width')
            Default: 'fixed_width' (IPUMS NHIS standard)

    Returns:
        MicrodataExtract: Configured extract ready to submit to IPUMS API

    Raises:
        KeyError: If required configuration fields are missing
        ValueError: If configuration values are invalid

    Example:
        >>> from python.nhis.config_manager import get_nhis_config
        >>> config = get_nhis_config("2019-2024")
        >>> extract = build_extract(config)
        >>> print(extract.description)
        NHIS 2019-2024 (6 years) for Kidsights research, nationwide all ages
    """
    log.info(
        "Building IPUMS NHIS extract",
        years=config.get('years')
    )

    # Get collection (must be 'nhis')
    collection = config.get('collection', 'nhis')
    if collection != 'nhis':
        log.warning(
            "Collection is not 'nhis', this may cause issues",
            collection=collection
        )
    log.debug("Using collection", collection=collection)

    # Get sample codes (list of annual samples: ih2019, ih2020, etc.)
    samples = config.get('samples')
    if not samples:
        log.error("Missing samples in configuration")
        raise KeyError("Configuration must include 'samples' field (e.g., ['ih2019', 'ih2020'])")

    if not isinstance(samples, list) or len(samples) == 0:
        log.error("Samples must be a non-empty list", samples=samples)
        raise ValueError("'samples' must be a non-empty list")

    log.debug("Using samples", samples=samples, count=len(samples))

    # Build variable list
    variables = build_variable_list(config)

    # Build description
    description = build_extract_description(config)

    # Get data format from config or use parameter
    if 'data_format' in config:
        data_format = config['data_format']

    # Create MicrodataExtract object
    try:
        extract = MicrodataExtract(
            collection=collection,
            samples=samples,
            variables=variables,
            description=description,
            data_format=data_format
        )

        # NOTE: No case selections for NHIS - nationwide, all ages
        # Unlike ACS which filters by state and age, NHIS extracts
        # include all records to allow flexible analysis

        log.info(
            "Extract built successfully",
            collection=collection,
            description=description,
            samples_count=len(samples),
            variables_count=len(variables)
        )

        return extract

    except Exception as e:
        log.error("Failed to build extract", error=str(e), error_type=type(e).__name__)
        raise ValueError(
            f"Failed to build IPUMS NHIS extract: {e}\n\n"
            f"Configuration may have invalid values.\n"
            f"Check sample codes and variable names.\n"
            f"NHIS samples format: ['ih2019', 'ih2020', ...]"
        ) from e


def get_extract_info(extract: MicrodataExtract) -> Dict[str, Any]:
    """Extract metadata from MicrodataExtract object for logging/caching.

    Args:
        extract: MicrodataExtract object

    Returns:
        Dict with extract metadata

    Example:
        >>> extract = build_extract(config)
        >>> info = get_extract_info(extract)
        >>> print(info['variable_count'])
        66
        >>> print(info['samples'])
        ['ih2019', 'ih2020', 'ih2021', 'ih2022', 'ih2023', 'ih2024']
    """
    info = {
        'description': extract.description,
        'collection': extract.collection,
        'samples': extract.samples,
        'data_format': extract.data_format,
        'variable_count': len(extract.variables),
        'variables': [v.name for v in extract.variables],
    }

    # NHIS has no case selections (unlike ACS)
    info['case_selections'] = None
    info['nationwide'] = True
    info['all_ages'] = True

    return info
