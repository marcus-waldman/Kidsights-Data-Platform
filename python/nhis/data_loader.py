"""
Data Loading Utilities for NHIS Pipeline

Handles reading IPUMS NHIS data files and DDI codebooks, converting to pandas DataFrames,
and writing to Feather format for R compatibility.

Functions:
    read_ipums_ddi: Parse IPUMS DDI codebook (XML metadata)
    load_nhis_data: Load IPUMS NHIS data file (fixed-width format) using DDI
    convert_to_feather: Write DataFrame to Feather format with categorical preservation
    get_variable_metadata: Extract variable information from DDI
"""

import pandas as pd
import structlog
from pathlib import Path
from typing import Dict, Any, Optional
from ipumspy import readers, ddi

# Configure structured logging
log = structlog.get_logger()


def read_ipums_ddi(ddi_path: str) -> ddi.Codebook:
    """Parse IPUMS DDI codebook (XML metadata).

    The DDI codebook contains variable definitions, value labels, and data structure
    information needed to properly parse IPUMS fixed-width data files.

    Args:
        ddi_path: Path to DDI XML file (.xml)

    Returns:
        ddi.Codebook: Parsed DDI codebook object

    Raises:
        FileNotFoundError: If DDI file doesn't exist
        Exception: If DDI parsing fails

    Example:
        >>> codebook = read_ipums_ddi("data/nhis/cache/extracts/nhis_12345/ddi.xml")
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

        # Get variable count safely
        var_count = 'unknown'
        if hasattr(codebook, 'var_info'):
            var_count = len(codebook.var_info)

        log.info(
            "DDI codebook loaded successfully",
            path=str(ddi_file),
            variables=var_count
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
                    'categories': None
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


def load_nhis_data(
    data_path: str,
    ddi_path: str,
    n_rows: Optional[int] = None
) -> pd.DataFrame:
    """Load IPUMS NHIS data file (fixed-width format).

    Uses ipumspy readers to properly parse data according to DDI metadata.
    NHIS data is typically provided in fixed-width format (.dat files).

    Args:
        data_path: Path to data file (.dat)
        ddi_path: Path to DDI codebook (.xml) - REQUIRED for fixed-width format
        n_rows: Optional limit on number of rows to read (for testing)

    Returns:
        pd.DataFrame: NHIS data with proper types and categorical variables

    Raises:
        FileNotFoundError: If data file doesn't exist
        ValueError: If DDI path not provided
        Exception: If data loading fails

    Example:
        >>> # Fixed-width format (DDI required)
        >>> df = load_nhis_data("data.dat", "ddi.xml")
        >>> print(df.shape)
        (50000, 66)
    """
    data_file = Path(data_path)
    ddi_file = Path(ddi_path)

    log.info(
        "Loading NHIS data",
        data_path=str(data_file),
        ddi_path=str(ddi_file),
        n_rows=n_rows
    )

    # Validate file existence
    if not data_file.exists():
        log.error("Data file not found", path=str(data_file))
        raise FileNotFoundError(f"NHIS data file not found: {data_file}")

    if not ddi_file.exists():
        log.error("DDI file not found", path=str(ddi_file))
        raise FileNotFoundError(
            f"DDI codebook not found: {ddi_file}\n"
            f"DDI file is required to parse fixed-width NHIS data."
        )

    try:
        # Read DDI codebook
        codebook = read_ipums_ddi(str(ddi_file))

        # Use ipumspy reader for fixed-width format (match ACS pattern)
        log.debug("Reading fixed-width data using ipumspy")

        # ipumspy readers.read_microdata uses 'nrows', not 'n_rows'
        kwargs = {'nrows': n_rows} if n_rows else {}
        df = readers.read_microdata(codebook, str(data_file), **kwargs)

        log.info(
            "NHIS data loaded successfully",
            rows=len(df),
            columns=len(df.columns),
            memory_mb=df.memory_usage(deep=True).sum() / 1024 / 1024
        )

        return df

    except Exception as e:
        log.error("Failed to load NHIS data", data_path=str(data_file), error=str(e))
        raise Exception(
            f"Failed to load NHIS data: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify data file is complete (not truncated)\n"
            f"  2. Verify DDI codebook matches data file\n"
            f"  3. Check ipumspy version: pip list | grep ipumspy"
        ) from e


def convert_to_feather(
    df: pd.DataFrame,
    output_path: str
) -> Path:
    """Write DataFrame to Feather format with categorical preservation.

    Feather format is optimal for R/Python interoperability, preserving
    pandas categorical types as R factors.

    Args:
        df: DataFrame to save
        output_path: Path for output Feather file (.feather or .arrow)

    Returns:
        Path: Path to created file

    Raises:
        Exception: If writing fails

    Example:
        >>> df = load_nhis_data("data.dat", "ddi.xml")
        >>> feather_path = convert_to_feather(df, "nhis_2019-2024.feather")
        >>> print(f"Saved to: {feather_path}")
    """
    output_file = Path(output_path)

    log.info(
        "Converting to Feather format",
        output_path=str(output_file),
        rows=len(df),
        columns=len(df.columns)
    )

    # Create output directory if needed
    output_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        # Write to Feather format
        # Uses pyarrow backend, which preserves categorical types as dictionary encoding
        df.to_feather(str(output_file))

        file_size_mb = output_file.stat().st_size / 1024 / 1024

        log.info(
            "Feather file created successfully",
            path=str(output_file),
            size_mb=round(file_size_mb, 2)
        )

        return output_file

    except Exception as e:
        log.error("Failed to write Feather file", path=str(output_file), error=str(e))
        raise Exception(
            f"Failed to write Feather file: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify disk space available\n"
            f"  2. Check write permissions for output directory\n"
            f"  3. Verify pyarrow is installed: pip list | grep pyarrow"
        ) from e
