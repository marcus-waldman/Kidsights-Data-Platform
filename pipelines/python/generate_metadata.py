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
from typing import Dict, Any, List
import json
from datetime import datetime
import traceback

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

            # Get value counts for factor levels
            value_counts = series.value_counts(dropna=False).to_dict()
            metadata["value_labels"] = json.dumps(value_counts)

    return metadata


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
    if any(geo_term in var_lower for geo_term in ['zip', 'county', 'state', 'geographic']):
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
    exclude_columns: List[str] = None
) -> List[Dict[str, Any]]:
    """
    Generate metadata for all columns in a table.

    Args:
        table_name: Name of the table to analyze
        db_ops: Database operations instance
        exclude_columns: Columns to exclude from metadata generation

    Returns:
        List of metadata dictionaries
    """
    logger = setup_logging()

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

        with PerformanceLogger(logger, "variable_analysis", column_count=len(df.columns)):
            for col_name in df.columns:
                if col_name in exclude_columns:
                    logger.debug(f"Skipping excluded column: {col_name}")
                    continue

                try:
                    with error_context(logger, "variable_analysis", variable=col_name):
                        logger.debug(f"Analyzing variable: {col_name}")

                        # Generate basic metadata
                        var_metadata = analyze_variable(df[col_name], col_name)

                        # Add category and transformation notes
                        category = categorize_variable(col_name)
                        var_metadata["category"] = category
                        var_metadata["variable_label"] = col_name.replace('_', ' ').title()
                        var_metadata["transformation_notes"] = generate_transformation_notes(col_name, category)
                        var_metadata["creation_date"] = datetime.now().isoformat()

                        # Add empty fields for compatibility
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
                    if_exists="append",
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

        # Generate metadata
        with PerformanceLogger(logger, "metadata_generation", source_table=args.source_table):
            logger.info(f"Generating metadata from table: {args.source_table}")
            metadata_list = generate_metadata_from_table(args.source_table, db_ops)

            if not metadata_list:
                raise ValueError("No metadata generated - check source table structure")

            logger.info(f"Generated metadata for {len(metadata_list)} variables")

        # Insert metadata (unless dry run)
        if args.dry_run:
            logger.info("Dry run mode: skipping database insertion")
            logger.info(f"Would have inserted {len(metadata_list)} metadata records")
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