"""
Data Loading Utilities for ACS Pipeline

Handles reading IPUMS data files and DDI codebooks, converting to pandas DataFrames,
and writing to Feather format for R compatibility.

Functions:
    read_ipums_ddi: Parse IPUMS DDI codebook (XML metadata)
    load_ipums_data: Load IPUMS data file (CSV or fixed-width) using DDI
    convert_to_feather: Write DataFrame to Feather format with categorical preservation
    get_variable_metadata: Extract variable information from DDI
"""

import pandas as pd
import structlog
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple
from ipumspy import IpumsApiClient, readers, ddi

# Configure structured logging
log = structlog.get_logger()


def read_ipums_ddi(ddi_path: str) -> ddi.Codebook:
    """Parse IPUMS DDI codebook (XML metadata).

    The DDI codebook contains variable definitions, value labels, and data structure
    information needed to properly parse IPUMS data files.

    Args:
        ddi_path: Path to DDI XML file (.xml)

    Returns:
        ddi.Codebook: Parsed DDI codebook object

    Raises:
        FileNotFoundError: If DDI file doesn't exist
        Exception: If DDI parsing fails

    Example:
        >>> codebook = read_ipums_ddi("data/acs/cache/extracts/usa_12345/ddi.xml")
        >>> print(codebook.data_description)
    """
    ddi_file = Path(ddi_path)

    log.info("Reading IPUMS DDI codebook", path=str(ddi_file))

    if not ddi_file.exists():
        log.error("DDI file not found", path=str(ddi_file))
        raise FileNotFoundError(f"DDI codebook not found: {ddi_file}")

    try:
        # Use ipumspy's DDI reader
        codebook = readers.read_ipums_ddi(str(ddi_file))

        log.info(
            "DDI codebook loaded successfully",
            path=str(ddi_file),
            variables=len(codebook.get_variable_info()) if hasattr(codebook, 'get_variable_info') else 'unknown'
        )

        return codebook

    except Exception as e:
        log.error("Failed to parse DDI codebook", path=str(ddi_file), error=str(e))
        raise Exception(f"Failed to parse DDI codebook: {e}") from e


def get_variable_metadata(codebook: ddi.Codebook) -> Dict[str, Dict[str, Any]]:
    """Extract variable metadata from DDI codebook.

    Args:
        codebook: Parsed DDI Codebook object

    Returns:
        Dict mapping variable names to metadata:
            {
                'AGE': {
                    'label': 'Age',
                    'type': 'numeric',
                    'categories': None  # or dict of value labels for categorical
                },
                'SEX': {
                    'label': 'Sex',
                    'type': 'categorical',
                    'categories': {1: 'Male', 2: 'Female'}
                },
                ...
            }
    """
    log.debug("Extracting variable metadata from DDI codebook")

    metadata = {}

    try:
        # ipumspy provides get_variable_info() method
        if hasattr(codebook, 'get_variable_info'):
            var_info = codebook.get_variable_info()

            for var_name, var_data in var_info.items():
                metadata[var_name] = {
                    'label': var_data.get('label', ''),
                    'type': var_data.get('var_type', 'unknown'),
                    'categories': var_data.get('categories', None)
                }

        log.debug(f"Extracted metadata for {len(metadata)} variables")

    except Exception as e:
        log.warning("Could not extract variable metadata", error=str(e))
        # Return empty dict if extraction fails - data will still load

    return metadata


def load_ipums_data(
    data_path: str,
    ddi_path: Optional[str] = None,
    n_rows: Optional[int] = None
) -> pd.DataFrame:
    """Load IPUMS data file (CSV or fixed-width format).

    Uses ipumspy readers to properly parse data according to DDI metadata.
    Automatically handles both CSV and fixed-width formats.

    Args:
        data_path: Path to data file (.csv or .dat)
        ddi_path: Optional path to DDI codebook (.xml). Required for fixed-width format.
        n_rows: Optional limit on number of rows to read (for testing)

    Returns:
        pd.DataFrame: IPUMS data with proper types and categorical variables

    Raises:
        FileNotFoundError: If data file doesn't exist
        ValueError: If fixed-width format but no DDI provided
        Exception: If data loading fails

    Example:
        >>> # CSV format (DDI optional but recommended)
        >>> df = load_ipums_data("data.csv", "ddi.xml")
        >>>
        >>> # Fixed-width format (DDI required)
        >>> df = load_ipums_data("data.dat", "ddi.xml")
        >>>
        >>> # Load first 1000 rows for testing
        >>> df = load_ipums_data("data.csv", "ddi.xml", n_rows=1000)
    """
    data_file = Path(data_path)

    log.info("Loading IPUMS data file", path=str(data_file), n_rows=n_rows or "all")

    if not data_file.exists():
        log.error("Data file not found", path=str(data_file))
        raise FileNotFoundError(f"Data file not found: {data_file}")

    # Determine file format
    file_format = data_file.suffix.lower()
    log.debug("Detected file format", format=file_format)

    try:
        if file_format == '.csv':
            # CSV format - can load with or without DDI
            if ddi_path:
                log.debug("Loading CSV with DDI metadata")
                codebook = read_ipums_ddi(ddi_path)
                df = readers.read_microdata(codebook, str(data_file), n_rows=n_rows)
            else:
                log.debug("Loading CSV without DDI metadata (basic types)")
                df = pd.read_csv(data_file, nrows=n_rows)

        elif file_format in ['.dat', '.txt']:
            # Fixed-width format - REQUIRES DDI for column positions
            if not ddi_path:
                log.error("Fixed-width format requires DDI codebook")
                raise ValueError(
                    "Fixed-width data format requires DDI codebook. "
                    "Provide ddi_path parameter."
                )

            log.debug("Loading fixed-width data with DDI metadata")
            codebook = read_ipums_ddi(ddi_path)
            df = readers.read_microdata(codebook, str(data_file), n_rows=n_rows)

        else:
            log.error("Unsupported file format", format=file_format)
            raise ValueError(
                f"Unsupported file format: {file_format}. "
                f"Expected .csv, .dat, or .txt"
            )

        log.info(
            "IPUMS data loaded successfully",
            path=str(data_file),
            rows=len(df),
            columns=len(df.columns)
        )

        log.debug("Column names", columns=list(df.columns))

        return df

    except Exception as e:
        log.error(
            "Failed to load IPUMS data",
            path=str(data_file),
            error=str(e),
            error_type=type(e).__name__
        )
        raise Exception(f"Failed to load IPUMS data: {e}") from e


def convert_to_feather(
    df: pd.DataFrame,
    output_path: str,
    preserve_categoricals: bool = True
) -> None:
    """Write DataFrame to Feather format for R compatibility.

    Feather format provides fast, lossless data exchange between Python and R.
    Categorical variables are preserved as R factors.

    Args:
        df: pandas DataFrame to write
        output_path: Path for output Feather file (.feather)
        preserve_categoricals: If True, keep categorical dtypes (default: True)

    Raises:
        Exception: If writing fails

    Example:
        >>> df = load_ipums_data("data.csv", "ddi.xml")
        >>> convert_to_feather(df, "output/raw.feather")
    """
    output_file = Path(output_path)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    log.info("Converting to Feather format", path=str(output_file), preserve_categoricals=preserve_categoricals)

    try:
        # Check for categorical columns
        categorical_cols = df.select_dtypes(include=['category']).columns.tolist()

        if categorical_cols:
            log.debug(
                f"Found {len(categorical_cols)} categorical columns",
                columns=categorical_cols[:10]  # Show first 10
            )

            if not preserve_categoricals:
                log.warning("Converting categoricals to strings (preserve_categoricals=False)")
                df = df.copy()
                for col in categorical_cols:
                    df[col] = df[col].astype(str)

        # Write to Feather format
        # Feather preserves pandas categorical dtype → R factor
        df.to_feather(str(output_file))

        # Get file size
        file_size_mb = output_file.stat().st_size / (1024 * 1024)

        log.info(
            "Feather file created successfully",
            path=str(output_file),
            rows=len(df),
            columns=len(df.columns),
            size_mb=f"{file_size_mb:.2f}"
        )

    except Exception as e:
        log.error(
            "Failed to write Feather file",
            path=str(output_file),
            error=str(e),
            error_type=type(e).__name__
        )
        raise Exception(f"Failed to write Feather file: {e}") from e


def load_and_convert(
    data_path: str,
    ddi_path: Optional[str],
    output_path: str,
    n_rows: Optional[int] = None
) -> pd.DataFrame:
    """Convenience function: load IPUMS data and convert to Feather in one step.

    Args:
        data_path: Path to IPUMS data file
        ddi_path: Path to DDI codebook (optional for CSV, required for fixed-width)
        output_path: Path for output Feather file
        n_rows: Optional row limit for testing

    Returns:
        pd.DataFrame: Loaded data (also saved to Feather file)

    Example:
        >>> df = load_and_convert(
        ...     "data/acs/cache/extracts/usa_12345/data.csv",
        ...     "data/acs/cache/extracts/usa_12345/ddi.xml",
        ...     "data/acs/nebraska/2019-2023/raw.feather"
        ... )
    """
    log.info("Load and convert workflow started")

    # Load data
    df = load_ipums_data(data_path, ddi_path, n_rows)

    # Convert to Feather
    convert_to_feather(df, output_path, preserve_categoricals=True)

    log.info("Load and convert workflow completed")

    return df


def validate_ipums_data(df: pd.DataFrame, expected_vars: Optional[List[str]] = None) -> Dict[str, Any]:
    """Validate IPUMS data for common issues.

    Args:
        df: DataFrame to validate
        expected_vars: Optional list of expected variable names

    Returns:
        Dict with validation results:
            {
                'valid': True/False,
                'rows': int,
                'columns': int,
                'missing_vars': list,
                'duplicate_serials': int,
                'missing_weights': int,
                'issues': list of strings
            }
    """
    log.debug("Validating IPUMS data")

    issues = []
    results = {
        'valid': True,
        'rows': len(df),
        'columns': len(df.columns),
        'column_names': list(df.columns),
        'issues': []
    }

    # Check for expected variables
    if expected_vars:
        missing_vars = [var for var in expected_vars if var not in df.columns]
        if missing_vars:
            results['missing_vars'] = missing_vars
            results['valid'] = False
            issues.append(f"Missing {len(missing_vars)} expected variables: {missing_vars[:5]}")

    # Check for critical IPUMS variables
    critical_vars = ['SERIAL', 'PERNUM']
    missing_critical = [var for var in critical_vars if var not in df.columns]
    if missing_critical:
        results['valid'] = False
        issues.append(f"Missing critical variables: {missing_critical}")

    # Check for duplicate person records
    if all(var in df.columns for var in ['SERIAL', 'PERNUM']):
        duplicates = df.duplicated(subset=['SERIAL', 'PERNUM']).sum()
        results['duplicate_serials'] = duplicates
        if duplicates > 0:
            results['valid'] = False
            issues.append(f"Found {duplicates} duplicate SERIAL+PERNUM records")

    # Check for sampling weights
    if 'PERWT' in df.columns:
        missing_weights = (df['PERWT'].isna() | (df['PERWT'] <= 0)).sum()
        results['missing_weights'] = missing_weights
        if missing_weights > 0:
            issues.append(f"Warning: {missing_weights} records with missing/zero PERWT")

    results['issues'] = issues

    if results['valid']:
        log.info("Validation passed", rows=results['rows'], columns=results['columns'])
    else:
        log.warning("Validation issues found", issues=issues)

    return results
