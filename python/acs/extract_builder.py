"""
Extract Builder for ACS Pipeline

Constructs IPUMS USA extract requests from configuration files.
Handles variable selection, case selections (filters), and attached characteristics.

Functions:
    build_extract: Main function to build extract from config
    build_variable_list: Construct variable list with attached characteristics
    build_case_selections: Create case selection filters
    build_extract_description: Generate human-readable extract description
"""

import structlog
from typing import Dict, Any, List, Optional, Tuple
from ipumspy import MicrodataExtract, Variable

# Configure structured logging
log = structlog.get_logger()


def build_variable_list(config: Dict[str, Any]) -> List[Variable]:
    """Build list of IPUMS Variable objects from configuration.

    Handles both simple variable names and variables with attached characteristics.

    Args:
        config: Configuration dictionary with 'variables' section

    Returns:
        List[Variable]: List of Variable objects ready for extract request

    Example:
        >>> config = {'variables': {
        ...     'core': ['AGE', 'SEX'],
        ...     'education': [
        ...         {'name': 'EDUC', 'attach_characteristics': ['mother', 'father']}
        ...     ]
        ... }}
        >>> vars = build_variable_list(config)
        >>> len(vars)
        3
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

            # Handle variable objects with attached characteristics
            elif isinstance(var_spec, dict):
                var_name = var_spec.get('name')
                if not var_name:
                    log.warning("Variable spec missing 'name' field", spec=var_spec)
                    continue

                # Get attached characteristics if specified
                attach_chars = var_spec.get('attach_characteristics', [])

                if attach_chars:
                    # Create Variable with attached characteristics
                    var_obj = Variable(
                        name=var_name,
                        attached_characteristics=attach_chars
                    )
                    variables.append(var_obj)
                    log.debug(
                        f"Added variable with attached characteristics",
                        variable=var_name,
                        characteristics=attach_chars
                    )
                else:
                    # No attached characteristics, simple variable
                    variables.append(Variable(name=var_name))
                    log.debug(f"Added variable: {var_name}")

    log.info(f"Built variable list", total_variables=len(variables))
    return variables


def build_case_selections(config: Dict[str, Any]) -> Dict[str, List[int]]:
    """Build case selection filters from configuration.

    Creates filters for STATEFIP (state) and AGE (children 0-5).

    Args:
        config: Configuration dictionary

    Returns:
        Dict[str, List[int]]: Case selections for IPUMS extract
            e.g., {'STATEFIP': [31], 'AGE': [0, 1, 2, 3, 4, 5]}

    Example:
        >>> config = {
        ...     'state_fip': 31,
        ...     'filters': {'age_min': 0, 'age_max': 5}
        ... }
        >>> cases = build_case_selections(config)
        >>> cases['STATEFIP']
        [31]
    """
    log.debug("Building case selections from configuration")

    case_selections = {}

    # State filter (STATEFIP)
    if 'state_fip' in config:
        state_fip = int(config['state_fip'])
        case_selections['STATEFIP'] = [state_fip]
        log.debug(f"Added STATEFIP filter", fip=state_fip)

    # Age filter (AGE)
    filters = config.get('filters', {})
    age_min = filters.get('age_min', 0)
    age_max = filters.get('age_max', 5)

    if age_min is not None and age_max is not None:
        age_range = list(range(int(age_min), int(age_max) + 1))
        case_selections['AGE'] = age_range
        log.debug(f"Added AGE filter", age_range=age_range)

    # Check for explicit case_selections in config (override)
    if 'case_selections' in config:
        explicit_cases = config['case_selections']
        case_selections.update(explicit_cases)
        log.debug("Applied explicit case selections", selections=explicit_cases)

    log.info("Case selections built", filters=list(case_selections.keys()))
    return case_selections


def build_extract_description(config: Dict[str, Any]) -> str:
    """Generate human-readable extract description.

    Args:
        config: Configuration dictionary

    Returns:
        str: Extract description

    Example:
        >>> config = {
        ...     'state': 'nebraska',
        ...     'year_range': '2019-2023',
        ...     'sample_type': '5-year',
        ...     'filters': {'age_min': 0, 'age_max': 5}
        ... }
        >>> desc = build_extract_description(config)
        >>> print(desc)
        Nebraska ACS 2019-2023 5-year, children 0-5 for Kidsights raking
    """
    # Use explicit description if provided
    if 'description' in config and config['description']:
        # Handle template variables in description
        desc = config['description']
        desc = desc.replace('${state}', config.get('state', 'UNKNOWN').title())
        desc = desc.replace('${year_range}', config.get('year_range', 'UNKNOWN'))
        desc = desc.replace('${sample_type}', config.get('sample_type', 'UNKNOWN'))
        return desc

    # Build description from components
    state = config.get('state', 'Unknown').title()
    year_range = config.get('year_range', 'Unknown')
    sample_type = config.get('sample_type', 'ACS')

    filters = config.get('filters', {})
    age_min = filters.get('age_min', 0)
    age_max = filters.get('age_max', 5)

    description = f"{state} ACS {year_range} {sample_type}, children {age_min}-{age_max} for Kidsights raking"

    return description


def build_extract(
    config: Dict[str, Any],
    data_format: str = "csv"
) -> MicrodataExtract:
    """Build IPUMS USA extract request from configuration.

    Main function that orchestrates extract building by calling helper functions.

    Args:
        config: Configuration dictionary (validated)
        data_format: Data format ('csv' or 'fixed_width')
            Default: 'csv' (recommended for easier parsing)

    Returns:
        MicrodataExtract: Configured extract ready to submit to IPUMS API

    Raises:
        KeyError: If required configuration fields are missing
        ValueError: If configuration values are invalid

    Example:
        >>> from python.acs.config_manager import get_state_config
        >>> config = get_state_config("nebraska", "2019-2023")
        >>> extract = build_extract(config)
        >>> print(extract.description)
        Nebraska ACS 2019-2023 5-year, children 0-5 for Kidsights raking
    """
    log.info(
        "Building IPUMS extract",
        state=config.get('state'),
        year_range=config.get('year_range')
    )

    # Get collection (default to 'usa' for ACS data)
    collection = config.get('collection', 'usa')
    log.debug("Using collection", collection=collection)

    # Get sample code
    sample_code = config.get('acs_sample')
    if not sample_code:
        log.error("Missing acs_sample in configuration")
        raise KeyError("Configuration must include 'acs_sample' field")

    samples = [sample_code]
    log.debug("Using sample", sample=sample_code)

    # Build variable list with attached characteristics
    variables = build_variable_list(config)

    # Build case selections (filters)
    case_selections = build_case_selections(config)

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
            data_format=data_format,
            case_selections=case_selections
        )

        log.info(
            "Extract built successfully",
            collection=collection,
            description=description,
            variables_count=len(variables),
            filters_count=len(case_selections)
        )

        return extract

    except Exception as e:
        log.error("Failed to build extract", error=str(e), error_type=type(e).__name__)
        raise ValueError(
            f"Failed to build IPUMS extract: {e}\n\n"
            f"Configuration may have invalid values.\n"
            f"Check sample codes, variable names, and filters."
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
        25
    """
    info = {
        'description': extract.description,
        'samples': extract.samples,
        'data_format': extract.data_format,
        'variable_count': len(extract.variables),
        'variables': [v.name for v in extract.variables],
        'case_selections': extract.case_selections if hasattr(extract, 'case_selections') else {},
    }

    # Extract attached characteristics info
    attached_chars = {}
    for var in extract.variables:
        if hasattr(var, 'attached_characteristics') and var.attached_characteristics:
            attached_chars[var.name] = var.attached_characteristics

    if attached_chars:
        info['attached_characteristics'] = attached_chars

    return info
