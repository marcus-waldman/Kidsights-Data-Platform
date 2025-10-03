"""
SPSS File Loader for NSCH Data

Provides functions to read SPSS (.sav) files from NSCH surveys and extract
comprehensive metadata including variable labels and value labels.

Functions:
    read_spss_file: Load SPSS file and return DataFrame + metadata
    extract_variable_metadata: Extract variable information from SPSS metadata
    extract_value_labels: Extract value label mappings for categorical variables
    get_year_from_filename: Parse year from NSCH SPSS filename
    save_metadata_json: Export metadata to JSON file

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import re
import json
from pathlib import Path
from typing import Tuple, Dict, Any, Optional
from datetime import datetime

import pandas as pd
import pyreadstat
import structlog

# Configure structured logging
log = structlog.get_logger()


def get_year_from_filename(file_path: str) -> int:
    """
    Parse year from NSCH SPSS filename.

    Handles various NSCH filename formats:
    - NSCH_2023e_Topical_CAHMI_DRC.sav → 2023
    - 2022e NSCH_Topical_DRC_CAHMIv3.sav → 2022
    - NSCH2016_Topical_SPSS_CAHM_DRCv2.sav → 2016

    Args:
        file_path: Path to SPSS file

    Returns:
        int: Four-digit year (2016-2023)

    Raises:
        ValueError: If year cannot be parsed from filename

    Example:
        >>> get_year_from_filename("data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav")
        2023
    """
    filename = Path(file_path).name

    # Try multiple patterns to match year in filename
    patterns = [
        r'NSCH_(\d{4})',      # NSCH_2023e_...
        r'^(\d{4})[e\s]',     # 2022e NSCH_...
        r'NSCH(\d{4})_',      # NSCH2016_...
    ]

    for pattern in patterns:
        match = re.search(pattern, filename)
        if match:
            year = int(match.group(1))
            if 2016 <= year <= 2023:
                log.debug("Parsed year from filename", filename=filename, year=year)
                return year

    # If no pattern matched, raise error
    log.error("Could not parse year from filename", filename=filename)
    raise ValueError(f"Could not parse year from filename: {filename}")


def read_spss_file(file_path: str) -> Tuple[pd.DataFrame, pyreadstat._readstat_parser.metadata_container]:
    """
    Read SPSS (.sav) file and return DataFrame with metadata.

    Uses pyreadstat to load SPSS file, which preserves:
    - Variable labels (descriptive names)
    - Value labels (categorical mappings)
    - Variable formats and types

    Args:
        file_path: Path to SPSS .sav file

    Returns:
        Tuple of (DataFrame, metadata_object):
        - DataFrame: Data with column names as variables
        - metadata: pyreadstat metadata container with labels/formats

    Raises:
        FileNotFoundError: If SPSS file doesn't exist
        Exception: If SPSS file is corrupted or can't be read

    Example:
        >>> df, meta = read_spss_file("data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav")
        >>> print(df.shape)
        (54890, 312)
    """
    file_path_obj = Path(file_path)

    log.info("Reading SPSS file", path=str(file_path_obj))

    if not file_path_obj.exists():
        log.error("SPSS file not found", path=str(file_path_obj))
        raise FileNotFoundError(f"SPSS file not found: {file_path_obj}")

    try:
        # Read SPSS file with pyreadstat
        df, meta = pyreadstat.read_sav(str(file_path_obj))

        log.info(
            "SPSS file loaded successfully",
            path=str(file_path_obj),
            rows=len(df),
            columns=len(df.columns)
        )

        return df, meta

    except Exception as e:
        log.error("Failed to read SPSS file", path=str(file_path_obj), error=str(e))
        raise Exception(f"Failed to read SPSS file {file_path_obj}: {e}") from e


def extract_variable_metadata(meta: pyreadstat._readstat_parser.metadata_container) -> Dict[str, Dict[str, Any]]:
    """
    Extract variable metadata from pyreadstat metadata object.

    Extracts for each variable:
    - label: Descriptive variable label
    - type: Data type (numeric, string)
    - format: SPSS format specification

    Args:
        meta: pyreadstat metadata container from read_sav()

    Returns:
        Dict mapping variable names to metadata:
        {
            "HHID": {
                "label": "Household identifier",
                "type": "string",
                "format": "A15"
            },
            "ChHlthSt_23": {
                "label": "Children's overall health status",
                "type": "numeric",
                "format": "F8.0"
            }
        }

    Example:
        >>> var_meta = extract_variable_metadata(meta)
        >>> print(var_meta["HHID"]["label"])
        "Household identifier"
    """
    log.debug("Extracting variable metadata", variable_count=len(meta.column_names))

    var_metadata = {}

    # column_labels is a list parallel to column_names
    for idx, var_name in enumerate(meta.column_names):
        # Get variable label (description) from parallel list
        label = meta.column_labels[idx] if idx < len(meta.column_labels) else ""

        # Check if variable has value labels (categorical)
        has_value_labels = var_name in meta.variable_value_labels

        var_metadata[var_name] = {
            "label": label if label else "",
            "has_value_labels": has_value_labels
        }

    log.info("Variable metadata extracted", variable_count=len(var_metadata))

    return var_metadata


def extract_value_labels(meta: pyreadstat._readstat_parser.metadata_container) -> Dict[str, Dict[str, str]]:
    """
    Extract value labels for categorical variables.

    Value labels map numeric codes to text descriptions, e.g.:
    - 1 → "Excellent"
    - 2 → "Very Good"
    - 3 → "Good"

    Args:
        meta: pyreadstat metadata container from read_sav()

    Returns:
        Dict mapping variable names to value label dictionaries:
        {
            "ChHlthSt_23": {
                "1": "Excellent",
                "2": "Very Good",
                "3": "Good",
                "4": "Fair",
                "5": "Poor"
            }
        }

    Example:
        >>> value_labels = extract_value_labels(meta)
        >>> print(value_labels["ChHlthSt_23"]["1"])
        "Excellent"
    """
    log.debug("Extracting value labels")

    value_labels = {}

    # In pyreadstat, variable_value_labels directly contains the {value: label} dicts
    # (not label set names like in some other formats)

    if hasattr(meta, 'variable_value_labels') and meta.variable_value_labels:
        for var_name, labels_dict in meta.variable_value_labels.items():
            if labels_dict:
                # Convert all keys to strings for JSON compatibility
                value_labels[var_name] = {str(k): str(v) for k, v in labels_dict.items()}

    log.info("Value labels extracted", variable_count=len(value_labels))

    return value_labels


def save_metadata_json(
    year: int,
    file_name: str,
    df: pd.DataFrame,
    var_metadata: Dict[str, Dict[str, Any]],
    value_labels: Dict[str, Dict[str, str]],
    output_path: str
) -> None:
    """
    Save extracted metadata to JSON file.

    Creates a comprehensive JSON file with:
    - Survey year
    - Source file name
    - Record and variable counts
    - Variable metadata (labels, types)
    - Value labels for categorical variables
    - Extraction timestamp

    Args:
        year: Survey year (2016-2023)
        file_name: Original SPSS filename
        df: DataFrame (for row/column counts)
        var_metadata: Variable metadata from extract_variable_metadata()
        value_labels: Value labels from extract_value_labels()
        output_path: Path to save JSON file

    Raises:
        IOError: If JSON file cannot be written

    Example:
        >>> save_metadata_json(
        ...     year=2023,
        ...     file_name="NSCH_2023e_Topical_CAHMI_DRC.sav",
        ...     df=df,
        ...     var_metadata=var_meta,
        ...     value_labels=val_labels,
        ...     output_path="data/nsch/2023/metadata.json"
        ... )
    """
    output_file = Path(output_path)

    log.info("Saving metadata to JSON", path=str(output_file))

    # Build comprehensive metadata structure
    metadata = {
        "year": year,
        "file_name": file_name,
        "record_count": len(df),
        "variable_count": len(df.columns),
        "variables": {},
        "extracted_date": datetime.now().isoformat()
    }

    # Merge variable metadata and value labels
    for var_name in df.columns:
        var_info = var_metadata.get(var_name, {})

        metadata["variables"][var_name] = {
            "label": var_info.get("label", ""),
            "has_value_labels": var_name in value_labels,
            "value_labels": value_labels.get(var_name, None)
        }

    # Ensure output directory exists
    output_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        log.info("Metadata saved successfully", path=str(output_file), size_kb=output_file.stat().st_size / 1024)

    except Exception as e:
        log.error("Failed to save metadata JSON", path=str(output_file), error=str(e))
        raise IOError(f"Failed to save metadata JSON to {output_file}: {e}") from e
