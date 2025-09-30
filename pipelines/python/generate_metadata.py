#!/usr/bin/env python3
"""
Metadata generation script for NE25 pipeline.

This script generates comprehensive variable metadata from the transformed data,
replacing R's metadata generation functionality to avoid segmentation faults.
"""

import sys
import argparse
import pandas as pd
import numpy as np
from pathlib import Path
from typing import Dict, Any, List, Optional
import json
from datetime import datetime
import traceback
import re
import yaml

# Add python module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "python"))

from db import DatabaseManager, DatabaseOperations
try:
    from utils.logging import setup_logging, with_logging, PerformanceLogger, error_context
except ImportError:
    # Basic logging fallback
    import logging
    def setup_logging(level="INFO", **kwargs):
        logging.basicConfig(level=getattr(logging, level))
        return logging.getLogger()

    def with_logging(name):
        def decorator(func):
            return func
        return decorator

    def PerformanceLogger(logger, operation, **kwargs):
        class DummyContext:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        return DummyContext()

    def error_context(logger, operation, **kwargs):
        class DummyContext:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        return DummyContext()


def load_derived_variables_config(config_path: str) -> Optional[List[str]]:
    """
    Load derived variables configuration from YAML file.

    Args:
        config_path: Path to the derived variables YAML configuration file

    Returns:
        List of derived variable names, or None if file not found or invalid
    """
    try:
        config_file = Path(config_path)
        if not config_file.exists():
            return None

        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

        if 'all_derived_variables' in config:
            return config['all_derived_variables']
        else:
            return None

    except Exception as e:
        print(f"Warning: Could not load derived variables config from {config_path}: {e}")
        return None


def load_variable_labels(config_path: str) -> Dict[str, str]:
    """
    Load variable labels from derived variables YAML configuration.

    Args:
        config_path: Path to the derived variables YAML configuration file

    Returns:
        Dictionary mapping variable names to descriptive labels
    """
    try:
        config_file = Path(config_path)
        if not config_file.exists():
            return {}

        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

        if 'variable_labels' in config:
            return config['variable_labels']
        else:
            return {}

    except Exception as e:
        print(f"Warning: Could not load variable labels from {config_path}: {e}")
        return {}


@with_logging("analyze_variable")
def analyze_variable(series: pd.Series, var_name: str) -> Dict[str, Any]:
    """
    Analyze a pandas Series to generate metadata.

    Args:
        series: Pandas Series to analyze
        var_name: Variable name

    Returns:
        Dictionary with variable metadata
    """
    if series.empty:
        raise ValueError(f"Cannot analyze empty series for variable {var_name}")
    metadata = {
        "variable_name": var_name,
        "n_total": len(series),
        "n_missing": series.isna().sum(),
        "missing_percentage": round((series.isna().sum() / len(series)) * 100, 2),
        "unique_values": series.nunique()
    }

    # Determine data type
    if pd.api.types.is_bool_dtype(series):
        metadata["data_type"] = "logical"
        metadata["storage_mode"] = "logical"
    elif pd.api.types.is_numeric_dtype(series):
        metadata["data_type"] = "numeric"
        metadata["storage_mode"] = "double" if series.dtype == 'float64' else "integer"

        # Numeric summary statistics
        if not series.isna().all():
            metadata["min_value"] = float(series.min()) if not pd.isna(series.min()) else None
            metadata["max_value"] = float(series.max()) if not pd.isna(series.max()) else None
            metadata["mean_value"] = float(series.mean()) if not pd.isna(series.mean()) else None
    else:
        metadata["data_type"] = "character"
        metadata["storage_mode"] = "character"

        # For categorical data, try to identify if it should be a factor
        if metadata["unique_values"] <= 20 and metadata["unique_values"] < metadata["n_total"] * 0.5:
            metadata["data_type"] = "factor"

            # Generate enhanced factor metadata
            factor_metadata = analyze_factor_variable(series, var_name)
            metadata.update(factor_metadata)

    return metadata


def analyze_factor_variable(series: pd.Series, var_name: str) -> Dict[str, Any]:
    """
    Analyze a factor variable to extract levels, labels, and ordering.

    Args:
        series: Pandas Series containing factor data
        var_name: Variable name for context

    Returns:
        Dictionary with factor-specific metadata
    """
    # Get value counts (excluding missing values for ordering)
    value_counts = series.value_counts(dropna=False)

    # Create factor levels with proper ordering
    factor_levels = []
    value_labels = {}
    value_counts_dict = {}

    # Sort levels logically based on variable type
    sorted_values = sort_factor_levels(list(value_counts.index), var_name)

    # Build factor metadata
    for i, level in enumerate(sorted_values):
        if pd.isna(level):
            level_key = "NA"
            level_label = "Missing/Not Available"
        else:
            level_key = str(i + 1)  # 1-based indexing for R compatibility
            level_label = str(level)

        factor_levels.append({
            "code": level_key,
            "label": level_label,
            "original_value": level,
            "count": int(value_counts.get(level, 0)),
            "percentage": round((value_counts.get(level, 0) / len(series)) * 100, 2)
        })

        value_labels[level_key] = level_label
        value_counts_dict[level_key] = int(value_counts.get(level, 0))

    # Identify reference level (typically the most common non-missing value)
    non_missing_levels = [level for level in factor_levels if level["original_value"] is not pd.NA and not pd.isna(level["original_value"])]
    reference_level = None
    if non_missing_levels:
        # Use the most frequent level as reference, or first level if tie
        reference_level = max(non_missing_levels, key=lambda x: x["count"])["code"]

    return {
        "factor_levels": factor_levels,
        "value_labels": json.dumps(value_labels, ensure_ascii=False),
        "value_counts": json.dumps(value_counts_dict),
        "reference_level": reference_level,
        "ordered_factor": is_ordered_factor(var_name),
        "factor_type": determine_factor_type(var_name)
    }


def sort_factor_levels(levels: List[Any], var_name: str) -> List[Any]:
    """
    Sort factor levels in a logical order based on variable type.

    Args:
        levels: List of factor levels to sort
        var_name: Variable name for context

    Returns:
        Sorted list of levels
    """
    var_lower = var_name.lower()

    # Custom sorting for specific variable types
    if 'educ' in var_lower:
        # Education levels: Less than HS < HS Graduate < Some College < College Degree < Graduate/Professional
        education_order = {
            'less than high school graduate': 1,
            'high school graduate (including equivalency)': 2,
            'some college or associate\'s degree': 3,
            'college degree': 4,
            'graduate or professional degree': 5
        }

        def edu_sort_key(level):
            if pd.isna(level):
                return 999  # Missing values last
            level_str = str(level).lower()
            return education_order.get(level_str, 100)  # Unknown levels after known ones

        return sorted(levels, key=edu_sort_key)

    elif 'fpl' in var_lower or 'poverty' in var_lower:
        # Income/poverty levels: typically ordered from low to high
        fpl_order = {
            'below federal poverty level': 1,
            'at or above federal poverty level': 2,
            '<100% fpl': 1,
            '100-199% fpl': 2,
            '200-299% fpl': 3,
            '300-399% fpl': 4,
            '400%+ fpl': 5
        }

        def fpl_sort_key(level):
            if pd.isna(level):
                return 999
            level_str = str(level).lower()
            return fpl_order.get(level_str, 100)

        return sorted(levels, key=fpl_sort_key)

    elif 'age' in var_lower and 'cat' in var_lower:
        # Age categories: sort numerically by age ranges
        def age_sort_key(level):
            if pd.isna(level):
                return 999
            level_str = str(level)
            # Extract first number from age ranges like "0-11 months", "1-2 years"
            numbers = re.findall(r'\d+', level_str)
            return int(numbers[0]) if numbers else 100

        return sorted(levels, key=age_sort_key)

    else:
        # Default sorting: missing values last, then alphabetical
        def default_sort_key(level):
            if pd.isna(level):
                return ('zzz_missing', '')
            return ('a_value', str(level))

        return sorted(levels, key=default_sort_key)


def is_ordered_factor(var_name: str) -> bool:
    """
    Determine if a factor variable should be treated as ordered.

    Args:
        var_name: Variable name

    Returns:
        True if factor should be ordered, False otherwise
    """
    var_lower = var_name.lower()

    # Variables that are typically ordered
    ordered_patterns = [
        'educ',  # Education levels
        'fpl',   # Income/poverty levels
        'age',   # Age categories
        'grade', # Grade levels
        'level', # General level variables
        'scale', # Scale variables
        'severity' # Severity scales
    ]

    return any(pattern in var_lower for pattern in ordered_patterns)


def determine_factor_type(var_name: str) -> str:
    """
    Determine the type/category of a factor variable.

    Args:
        var_name: Variable name

    Returns:
        Factor type string
    """
    var_lower = var_name.lower()

    if any(term in var_lower for term in ['race', 'ethnic']):
        return 'demographic_race'
    elif any(term in var_lower for term in ['sex', 'gender']):
        return 'demographic_sex'
    elif 'educ' in var_lower:
        return 'socioeconomic_education'
    elif any(term in var_lower for term in ['fpl', 'poverty', 'income']):
        return 'socioeconomic_income'
    elif 'age' in var_lower:
        return 'demographic_age'
    elif any(term in var_lower for term in ['relation', 'caregiver']):
        return 'relationship'
    elif any(term in var_lower for term in ['county', 'state', 'zip', 'geographic']):
        return 'geographic'
    else:
        return 'other'


def categorize_variable(var_name: str) -> str:
    """
    Categorize a variable based on its name.

    Args:
        var_name: Variable name

    Returns:
        Category string
    """
    var_lower = var_name.lower()

    # Core identifiers
    if var_name in ['record_id', 'pid', 'retrieved_date']:
        return 'core'

    # Eligibility flags
    if var_name in ['eligible', 'authentic', 'include'] or 'cid' in var_lower:
        return 'eligibility'

    # Age variables
    if any(age_term in var_lower for age_term in ['age', 'years_old', 'months_old', 'days_old']):
        return 'age'

    # Sex/gender variables
    if any(sex_term in var_lower for sex_term in ['sex', 'gender', 'female', 'male']):
        return 'sex'

    # Race/ethnicity variables
    if any(race_term in var_lower for race_term in ['race', 'hisp', 'ethnic', 'raceg', 'a1_race']):
        return 'race'

    # Education variables
    if any(educ_term in var_lower for educ_term in ['educ', 'education', 'mom', 'maternal']):
        return 'education'

    # Income/poverty variables
    if any(income_term in var_lower for income_term in ['income', 'fpl', 'poverty', 'family_size']):
        return 'income'

    # Caregiver relationship variables
    if any(rel_term in var_lower for rel_term in ['relation', 'caregiver', 'a1_', 'a2_']):
        return 'caregiver relationship'

    # Geographic variables
    if any(geo_term in var_lower for geo_term in [
        'zip', 'county', 'state', 'geographic',
        'puma', 'tract', 'cbsa', 'urban_rural',
        'school', 'sldl', 'sldu', 'congress',
        'aiannh'
    ]):
        return 'geography'

    return 'other'


def generate_transformation_notes(var_name: str, category: str) -> str:
    """
    Generate transformation notes for a variable.

    Args:
        var_name: Variable name
        category: Variable category

    Returns:
        Transformation notes string
    """
    notes_map = {
        'core': 'Core identifier or system variable',
        'eligibility': 'Eligibility determination based on CID criteria',
        'age': 'Age calculated from date of birth in various units',
        'sex': 'Sex/gender variable from demographic data',
        'race': 'Race/ethnicity variables harmonized from checkbox responses',
        'education': 'Education levels recoded into standardized categories',
        'income': 'Income and federal poverty level calculations',
        'caregiver relationship': 'Caregiver relationship and demographic variables',
        'geography': 'Geographic location and residence variables',
        'other': 'Other transformed variable'
    }

    base_note = notes_map.get(category, 'Transformed variable')

    # Add specific notes for certain patterns
    if 'educ4' in var_name:
        return f"{base_note} (4-category system)"
    elif 'educ6' in var_name:
        return f"{base_note} (6-category system)"
    elif 'educ8' in var_name:
        return f"{base_note} (8-category system)"
    elif 'fpl' in var_name:
        return f"{base_note} - Federal Poverty Level calculations"
    elif 'a1_' in var_name:
        return f"{base_note} - Primary caregiver"
    elif 'a2_' in var_name:
        return f"{base_note} - Secondary caregiver"

    return base_note


@with_logging("generate_metadata_from_table")
def generate_metadata_from_table(
    table_name: str,
    db_ops: DatabaseOperations,
    exclude_columns: List[str] = None,
    derived_variables_list: Optional[List[str]] = None,
    variable_labels: Optional[Dict[str, str]] = None
) -> List[Dict[str, Any]]:
    """
    Generate metadata for all columns in a table.

    Args:
        table_name: Name of the table to analyze
        db_ops: Database operations instance
        exclude_columns: Columns to exclude from metadata generation
        derived_variables_list: List of derived variables to filter to
        variable_labels: Dictionary of variable names to descriptive labels

    Returns:
        List of metadata dictionaries
    """
    logger = setup_logging()

    if variable_labels is None:
        variable_labels = {}

    if exclude_columns is None:
        exclude_columns = ['record_id', 'pid', 'retrieved_date', 'transformation_version', 'transformed_at']

    # Validate inputs
    if not table_name or not table_name.strip():
        raise ValueError("Table name cannot be empty")

    if not db_ops.table_exists(table_name):
        raise ValueError(f"Table {table_name} does not exist")

    try:
        with error_context(logger, "data_extraction", table_name=table_name):
            # Get data from table with row limit for metadata analysis
            logger.info(f"Querying data from {table_name} for metadata analysis...")

            # Check table size first
            total_rows = db_ops.get_table_count(table_name)
            sample_size = min(5000, total_rows)

            query = f"SELECT * FROM {table_name} LIMIT {sample_size}"
            df = db_ops.query_to_dataframe(query)

            if df is None or df.empty:
                logger.error(f"No data found in table {table_name}")
                return []

            logger.info(
                f"Analyzing {len(df.columns)} columns from {len(df)} rows (sample of {total_rows} total)",
                extra={
                    "table_name": table_name,
                    "columns_count": len(df.columns),
                    "sample_rows": len(df),
                    "total_rows": total_rows
                }
            )

        metadata_list = []
        failed_variables = []

        # Filter columns for analysis
        columns_to_analyze = df.columns.tolist()

        # Remove excluded columns
        columns_to_analyze = [col for col in columns_to_analyze if col not in exclude_columns]

        # If derived_variables_list is provided, only analyze those variables
        if derived_variables_list is not None:
            # Filter to only include derived variables that exist in the table
            available_derived = [col for col in derived_variables_list if col in df.columns]
            columns_to_analyze = available_derived
            logger.info(f"Filtering to derived variables only: {len(available_derived)} of {len(derived_variables_list)} derived variables found in table")

        with PerformanceLogger(logger, "variable_analysis", column_count=len(columns_to_analyze)):
            for col_name in columns_to_analyze:

                try:
                    with error_context(logger, "variable_analysis", variable=col_name):
                        logger.debug(f"Analyzing variable: {col_name}")

                        # Generate basic metadata
                        var_metadata = analyze_variable(df[col_name], col_name)

                        # Add category and transformation notes
                        category = categorize_variable(col_name)
                        var_metadata["category"] = category

                        # Use custom label if available, otherwise generate from variable name
                        if col_name in variable_labels:
                            var_metadata["variable_label"] = variable_labels[col_name]
                        else:
                            var_metadata["variable_label"] = col_name.replace('_', ' ').title()

                        var_metadata["transformation_notes"] = generate_transformation_notes(col_name, category)
                        var_metadata["creation_date"] = datetime.now().isoformat()

                        # Add empty fields for compatibility (only if not already set by factor analysis)
                        if "summary_statistics" not in var_metadata:
                            var_metadata["summary_statistics"] = "{}"
                        if "value_labels" not in var_metadata:
                            var_metadata["value_labels"] = "{}"

                        metadata_list.append(var_metadata)

                except Exception as var_error:
                    failed_variables.append({
                        "variable_name": col_name,
                        "error": str(var_error),
                        "error_type": type(var_error).__name__
                    })
                    logger.error(
                        f"Failed to analyze variable {col_name}: {var_error}",
                        extra={
                            "variable_name": col_name,
                            "error_type": type(var_error).__name__,
                            "error_message": str(var_error)
                        }
                    )

        if failed_variables:
            logger.warning(
                f"Failed to analyze {len(failed_variables)} variables out of {len(df.columns)}",
                extra={"failed_variables": failed_variables[:5]}  # Log first 5 failures
            )

        logger.info(
            f"Generated metadata for {len(metadata_list)} variables (failed: {len(failed_variables)})",
            extra={
                "successful_variables": len(metadata_list),
                "failed_variables": len(failed_variables),
                "success_rate": len(metadata_list) / len(df.columns) * 100
            }
        )
        return metadata_list

    except Exception as e:
        logger.error(
            f"Error generating metadata for {table_name}: {e}",
            extra={
                "table_name": table_name,
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
        )
        return []


@with_logging("export_metadata_to_feather")
def export_metadata_to_feather(
    metadata_list: List[Dict[str, Any]],
    output_path: str = "temp/ne25_metadata.feather"
) -> bool:
    """
    Export metadata to Feather file for reliable import via insert_raw_data.py.

    This approach mirrors the successful R → Feather → Python → DuckDB workflow,
    avoiding DataFrame insertion issues while preserving data types.

    Args:
        metadata_list: List of metadata dictionaries
        output_path: Path to output Feather file

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    if not metadata_list:
        logger.warning("No metadata to export")
        return True

    try:
        from pathlib import Path

        # Ensure output directory exists
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)

        # Convert to DataFrame with validation
        logger.info(f"Converting {len(metadata_list)} metadata records to DataFrame")
        df = pd.DataFrame(metadata_list)

        # Validate DataFrame structure
        required_columns = ['variable_name', 'data_type', 'category']
        missing_columns = [col for col in required_columns if col not in df.columns]
        if missing_columns:
            raise ValueError(f"Missing required columns in metadata: {missing_columns}")

        logger.info(
            f"Metadata DataFrame created: {len(df)} rows, {len(df.columns)} columns",
            extra={
                "metadata_rows": len(df),
                "metadata_columns": len(df.columns),
                "column_names": list(df.columns)
            }
        )

        # Export to Feather with data type preservation
        logger.info(f"Exporting metadata to Feather file: {output_path}")
        df.to_feather(output_path)

        # Verify export
        file_size = output_file.stat().st_size
        logger.info(
            f"Successfully exported metadata to Feather file",
            extra={
                "output_path": output_path,
                "file_size_bytes": file_size,
                "records_exported": len(df),
                "columns_exported": len(df.columns)
            }
        )

        return True

    except Exception as e:
        logger.error(
            f"Error exporting metadata to Feather: {e}",
            extra={
                "output_path": output_path,
                "metadata_count": len(metadata_list),
                "error_type": type(e).__name__,
                "error_message": str(e)
            }
        )
        return False


@with_logging("insert_metadata")
def insert_metadata(
    metadata_list: List[Dict[str, Any]],
    db_ops: DatabaseOperations,
    table_name: str = "ne25_metadata"
) -> bool:
    """
    Insert metadata into the database.

    Args:
        metadata_list: List of metadata dictionaries
        db_ops: Database operations instance
        table_name: Target metadata table name

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    if not metadata_list:
        logger.warning("No metadata to insert")
        return True

    # Validate inputs
    if not isinstance(metadata_list, list):
        raise ValueError("metadata_list must be a list")

    if not table_name or not table_name.strip():
        raise ValueError("table_name cannot be empty")

    try:
        with error_context(logger, "metadata_insertion", table_name=table_name, record_count=len(metadata_list)):
            # Convert to DataFrame with validation
            logger.info(f"Converting {len(metadata_list)} metadata records to DataFrame")
            df = pd.DataFrame(metadata_list)

            # Validate DataFrame structure
            required_columns = ['variable_name', 'data_type', 'category']
            missing_columns = [col for col in required_columns if col not in df.columns]
            if missing_columns:
                raise ValueError(f"Missing required columns in metadata: {missing_columns}")

            logger.info(
                f"Metadata DataFrame created: {len(df)} rows, {len(df.columns)} columns",
                extra={
                    "metadata_rows": len(df),
                    "metadata_columns": len(df.columns),
                    "column_names": list(df.columns)
                }
            )

            # Clear existing metadata
            logger.info(f"Clearing existing metadata from {table_name}")
            with db_ops.db_manager.get_connection() as conn:
                if db_ops.table_exists(table_name):
                    initial_count = db_ops.get_table_count(table_name)
                    conn.execute(f"DELETE FROM {table_name}")
                    logger.info(f"Deleted {initial_count} existing records from {table_name}")

            # Insert new metadata
            logger.info(f"Inserting {len(df)} metadata records into {table_name}")

            with PerformanceLogger(logger, "metadata_database_insertion", records=len(df)):
                success = db_ops.insert_dataframe(
                    df=df,
                    table_name=table_name,
                    if_exists="replace",
                    chunk_size=100
                )

            if success:
                final_count = db_ops.get_table_count(table_name)
                logger.info(
                    f"Successfully inserted metadata. Table {table_name} now has {final_count} rows",
                    extra={
                        "table_name": table_name,
                        "records_inserted": len(df),
                        "final_count": final_count
                    }
                )
            else:
                logger.error(
                    f"Failed to insert metadata into {table_name}",
                    extra={"table_name": table_name, "attempted_records": len(df)}
                )

            return success

    except Exception as e:
        logger.error(
            f"Error inserting metadata: {e}",
            extra={
                "table_name": table_name,
                "metadata_count": len(metadata_list),
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
        )
        return False


@with_logging("metadata_generation_main")
def main():
    """Main function for command line execution."""
    parser = argparse.ArgumentParser(
        description="Generate metadata for NE25 transformed variables",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_metadata.py
  python generate_metadata.py --source-table ne25_transformed --log-level DEBUG
  python generate_metadata.py --config config/sources/custom.yaml
        """
    )
    parser.add_argument(
        "--source-table",
        default="ne25_transformed",
        help="Source table to analyze (default: ne25_transformed)"
    )
    parser.add_argument(
        "--metadata-table",
        default="ne25_metadata",
        help="Target metadata table (default: ne25_metadata)"
    )
    parser.add_argument(
        "--config",
        default="config/sources/ne25.yaml",
        help="Configuration file path (default: config/sources/ne25.yaml)"
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level (default: INFO)"
    )
    parser.add_argument(
        "--log-file",
        help="Optional log file path"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate metadata but don't insert into database"
    )
    parser.add_argument(
        "--output-feather",
        default="temp/ne25_metadata.feather",
        help="Output Feather file path (default: temp/ne25_metadata.feather)"
    )
    parser.add_argument(
        "--export-only",
        action="store_true",
        help="Only export to Feather file, don't insert into database"
    )
    parser.add_argument(
        "--derived-only",
        action="store_true",
        help="Only analyze derived/transformed variables (not raw variables)"
    )
    parser.add_argument(
        "--derived-config",
        default="config/derived_variables.yaml",
        help="Configuration file with derived variable definitions (default: config/derived_variables.yaml)"
    )

    args = parser.parse_args()

    # Setup logging with optional file output
    logger = setup_logging(
        level=args.log_level,
        log_file=args.log_file,
        structured=False
    )

    # Log execution parameters
    logger.info(
        "Starting metadata generation",
        extra={
            "source_table": args.source_table,
            "metadata_table": args.metadata_table,
            "config": args.config,
            "log_level": args.log_level,
            "dry_run": args.dry_run
        }
    )

    try:
        with error_context(logger, "initialization", config=args.config):
            # Validate configuration file exists
            if not Path(args.config).exists():
                raise FileNotFoundError(f"Configuration file not found: {args.config}")

            # Initialize database components
            logger.info("Initializing database components...")
            db_manager = DatabaseManager(args.config)
            db_ops = DatabaseOperations(db_manager)

        with error_context(logger, "connection_validation"):
            # Test connection
            logger.info("Testing database connection...")
            if not db_manager.test_connection():
                raise ConnectionError("Database connection test failed")

            # Check if source table exists
            if not db_ops.table_exists(args.source_table):
                raise ValueError(f"Source table {args.source_table} does not exist")

            # Check source table has data
            row_count = db_ops.get_table_count(args.source_table)
            if row_count == 0:
                raise ValueError(f"Source table {args.source_table} is empty")

            logger.info(f"Source table {args.source_table} validated: {row_count} rows")

        # Load derived variables configuration if requested
        derived_variables_list = None
        if args.derived_only:
            logger.info(f"Loading derived variables configuration from: {args.derived_config}")
            derived_variables_list = load_derived_variables_config(args.derived_config)

            if derived_variables_list is None:
                raise FileNotFoundError(f"Could not load derived variables config from {args.derived_config}")

            logger.info(f"Loaded {len(derived_variables_list)} derived variables from configuration")

        # Load variable labels from configuration
        logger.info(f"Loading variable labels from: {args.derived_config}")
        variable_labels = load_variable_labels(args.derived_config)
        if variable_labels:
            logger.info(f"Loaded {len(variable_labels)} variable labels from configuration")
        else:
            logger.warning("No variable labels found in configuration - using auto-generated labels")

        # Generate metadata
        with PerformanceLogger(logger, "metadata_generation", source_table=args.source_table):
            logger.info(f"Generating metadata from table: {args.source_table}")

            if derived_variables_list is not None:
                logger.info("Filtering to derived variables only")

            metadata_list = generate_metadata_from_table(
                args.source_table,
                db_ops,
                derived_variables_list=derived_variables_list,
                variable_labels=variable_labels
            )

            if not metadata_list:
                raise ValueError("No metadata generated - check source table structure")

            logger.info(f"Generated metadata for {len(metadata_list)} variables")

        # Export metadata to Feather file
        # Adjust output filename for derived variables
        output_feather = args.output_feather
        if args.derived_only and not args.output_feather.endswith("_derived.feather"):
            output_feather = args.output_feather.replace(".feather", "_derived.feather")

        with PerformanceLogger(logger, "metadata_export", records=len(metadata_list)):
            logger.info(f"Exporting metadata to Feather file: {output_feather}")
            export_success = export_metadata_to_feather(metadata_list, output_feather)

            if not export_success:
                raise RuntimeError("Failed to export metadata to Feather file")

        # Insert metadata (unless dry run or export-only)
        if args.dry_run:
            logger.info("Dry run mode: skipping database insertion")
            logger.info(f"Would have inserted {len(metadata_list)} metadata records")
            success = True
        elif args.export_only:
            logger.info("Export-only mode: skipping database insertion")
            logger.info(f"Metadata exported to {args.output_feather}")
            success = True
        else:
            with PerformanceLogger(logger, "metadata_insertion", records=len(metadata_list)):
                success = insert_metadata(metadata_list, db_ops, args.metadata_table)

        if success:
            logger.info(
                "Metadata generation completed successfully",
                extra={
                    "variables_processed": len(metadata_list),
                    "dry_run": args.dry_run
                }
            )
            sys.exit(0)
        else:
            logger.error("Metadata generation failed during insertion")
            sys.exit(1)

    except FileNotFoundError as e:
        logger.error(f"File not found: {e}")
        sys.exit(2)
    except ConnectionError as e:
        logger.error(f"Database connection error: {e}")
        sys.exit(3)
    except ValueError as e:
        logger.error(f"Validation error: {e}")
        sys.exit(4)
    except Exception as e:
        logger.error(
            f"Fatal error during metadata generation: {e}",
            extra={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()
            }
        )
        sys.exit(1)


if __name__ == "__main__":
    main()