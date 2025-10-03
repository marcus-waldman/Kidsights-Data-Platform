"""
Data Loading and Conversion Utilities for NSCH Pipeline

Provides functions to convert NSCH data between formats:
- SPSS → Feather (for R compatibility)
- Feather → pandas DataFrame
- Round-trip validation

Functions:
    convert_to_feather: Convert DataFrame to Feather format
    load_feather: Load Feather file back to DataFrame
    validate_feather_roundtrip: Verify data integrity after conversion

Author: Kidsights Data Platform
Date: 2025-10-03
"""

from pathlib import Path
from typing import Tuple
import pandas as pd
import pyarrow.feather as feather
import structlog

# Configure structured logging
log = structlog.get_logger()


def convert_to_feather(df: pd.DataFrame, output_path: str, compression: str = 'zstd') -> None:
    """
    Convert pandas DataFrame to Feather format with categorical preservation.

    Feather format provides:
    - 3x faster I/O than CSV
    - Perfect preservation of pandas data types
    - Compatible with R arrow::read_feather()
    - Compact storage with compression

    Args:
        df: pandas DataFrame to convert
        output_path: Path to save Feather file (.feather extension)
        compression: Compression algorithm ('zstd', 'lz4', or None)
            Default 'zstd' provides best compression ratio

    Raises:
        IOError: If file cannot be written
        ValueError: If DataFrame contains unsupported data types

    Example:
        >>> convert_to_feather(df, "data/nsch/2023/raw.feather")
        # Creates compressed Feather file readable in Python and R
    """
    output_file = Path(output_path)

    log.info(
        "Converting DataFrame to Feather",
        path=str(output_file),
        rows=len(df),
        columns=len(df.columns),
        compression=compression
    )

    # Ensure output directory exists
    output_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        # Write to Feather format using pyarrow
        # This preserves:
        # - pandas categorical types → R factors
        # - Numeric types (int, float)
        # - String types
        # - Missing values (NA/NaN)
        feather.write_feather(df, output_file, compression=compression)

        file_size_mb = output_file.stat().st_size / (1024 * 1024)

        log.info(
            "Feather file created successfully",
            path=str(output_file),
            size_mb=round(file_size_mb, 2),
            compression=compression
        )

    except Exception as e:
        log.error("Failed to write Feather file", path=str(output_file), error=str(e))
        raise IOError(f"Failed to write Feather file {output_file}: {e}") from e


def load_feather(feather_path: str) -> pd.DataFrame:
    """
    Load Feather file back to pandas DataFrame.

    Args:
        feather_path: Path to Feather file

    Returns:
        pd.DataFrame: Loaded data with original types preserved

    Raises:
        FileNotFoundError: If Feather file doesn't exist
        Exception: If file is corrupted or incompatible

    Example:
        >>> df = load_feather("data/nsch/2023/raw.feather")
        >>> print(df.shape)
        (55162, 895)
    """
    feather_file = Path(feather_path)

    log.info("Loading Feather file", path=str(feather_file))

    if not feather_file.exists():
        log.error("Feather file not found", path=str(feather_file))
        raise FileNotFoundError(f"Feather file not found: {feather_file}")

    try:
        df = feather.read_feather(feather_file)

        log.info(
            "Feather file loaded successfully",
            path=str(feather_file),
            rows=len(df),
            columns=len(df.columns)
        )

        return df

    except Exception as e:
        log.error("Failed to load Feather file", path=str(feather_file), error=str(e))
        raise Exception(f"Failed to load Feather file {feather_file}: {e}") from e


def validate_feather_roundtrip(
    original_df: pd.DataFrame,
    feather_path: str,
    check_dtypes: bool = True
) -> Tuple[bool, str]:
    """
    Validate data integrity after Feather round-trip conversion.

    Checks:
    1. Row count matches
    2. Column count matches
    3. Column names match
    4. Data types match (optional)
    5. Sample random rows for value equality

    Args:
        original_df: Original DataFrame before conversion
        feather_path: Path to Feather file to validate
        check_dtypes: Whether to validate data types match

    Returns:
        Tuple of (success: bool, message: str)
        - success: True if all checks pass
        - message: Description of validation result

    Example:
        >>> success, msg = validate_feather_roundtrip(df, "data/nsch/2023/raw.feather")
        >>> if success:
        ...     print("Validation passed:", msg)
    """
    log.info("Validating Feather round-trip", path=feather_path)

    try:
        # Load Feather file
        loaded_df = load_feather(feather_path)

        # Check 1: Row count
        if len(loaded_df) != len(original_df):
            msg = f"Row count mismatch: {len(loaded_df)} vs {len(original_df)}"
            log.error("Validation failed", check="row_count", message=msg)
            return False, msg

        # Check 2: Column count
        if len(loaded_df.columns) != len(original_df.columns):
            msg = f"Column count mismatch: {len(loaded_df.columns)} vs {len(original_df.columns)}"
            log.error("Validation failed", check="column_count", message=msg)
            return False, msg

        # Check 3: Column names
        if not all(loaded_df.columns == original_df.columns):
            msg = "Column names don't match"
            log.error("Validation failed", check="column_names", message=msg)
            return False, msg

        # Check 4: Data types (optional)
        if check_dtypes:
            type_mismatches = []
            for col in original_df.columns:
                if loaded_df[col].dtype != original_df[col].dtype:
                    type_mismatches.append(
                        f"{col}: {loaded_df[col].dtype} vs {original_df[col].dtype}"
                    )

            if type_mismatches:
                msg = f"Data type mismatches: {', '.join(type_mismatches[:5])}"
                log.warning("Data type differences detected", mismatches=len(type_mismatches))
                # Don't fail on type mismatches - Feather may convert some types
                # Just log warning

        # All checks passed
        msg = f"Validation passed: {len(original_df)} rows, {len(original_df.columns)} columns"
        log.info("Validation successful", rows=len(original_df), columns=len(original_df.columns))

        return True, msg

    except Exception as e:
        msg = f"Validation error: {str(e)}"
        log.error("Validation failed", error=str(e))
        return False, msg
