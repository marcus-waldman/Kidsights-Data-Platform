"""
Common database operations for Kidsights Data Platform.

Provides high-level database operations built on top of the connection manager.
All operations are designed to replace R DuckDB functionality without segfaults.
"""

import pandas as pd
import duckdb
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
import logging
import json
from datetime import datetime
import traceback

from .connection import DatabaseManager
try:
    from utils.logging import PerformanceLogger, with_logging, error_context
except ImportError:
    # Fallback for when module structure isn't available
    def PerformanceLogger(logger, operation, **kwargs):
        class DummyContext:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        return DummyContext()

    def with_logging(name):
        def decorator(func):
            return func
        return decorator

    def error_context(logger, operation, **kwargs):
        class DummyContext:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        return DummyContext()


class DatabaseOperations:
    """
    High-level database operations for the Kidsights Data Platform.

    This class provides commonly used database operations while ensuring
    proper error handling and logging.
    """

    def __init__(self, db_manager: Optional[DatabaseManager] = None):
        """
        Initialize database operations.

        Args:
            db_manager: Database manager instance (creates default if None)
        """
        self.db_manager = db_manager or DatabaseManager()
        self.logger = logging.getLogger("kidsights.db.operations")
        self.logger.info(
            "Database operations initialized",
            extra={"database_path": self.db_manager.database_path}
        )

    @with_logging("insert_dataframe")
    def insert_dataframe(
        self,
        df: pd.DataFrame,
        table_name: str,
        if_exists: str = "append",
        chunk_size: int = 1000
    ) -> bool:
        """
        Insert a pandas DataFrame into a database table.

        Args:
            df: DataFrame to insert
            table_name: Target table name
            if_exists: What to do if table exists ('append', 'replace', 'fail')
            chunk_size: Number of rows to insert at once

        Returns:
            True if successful, False otherwise
        """
        # Validate inputs
        if df.empty:
            self.logger.warning(
                f"Attempted to insert empty DataFrame to {table_name}",
                extra={"table_name": table_name, "if_exists": if_exists}
            )
            return True

        if chunk_size < 1:
            raise ValueError("chunk_size must be positive")

        if if_exists not in ["append", "replace", "fail"]:
            raise ValueError("if_exists must be 'append', 'replace', or 'fail'")

        self.logger.info(
            f"Starting DataFrame insertion: {len(df)} rows to {table_name}",
            extra={
                "table_name": table_name,
                "rows": len(df),
                "columns": len(df.columns),
                "if_exists": if_exists,
                "chunk_size": chunk_size
            }
        )

        try:
            with self.db_manager.get_connection() as conn:
                with error_context(self.logger, "table_preparation", table_name=table_name):
                    # Handle different if_exists options
                    if if_exists == "replace":
                        conn.execute(f"DROP TABLE IF EXISTS {table_name}")
                        self.logger.debug(f"Dropped existing table {table_name}")
                    elif if_exists == "fail":
                        tables = [row[0] for row in conn.execute("SHOW TABLES").fetchall()]
                        if table_name in tables:
                            raise ValueError(f"Table {table_name} already exists")

                # Insert data in chunks for better memory management
                total_rows = len(df)
                rows_inserted = 0
                failed_chunks = []

                with PerformanceLogger(
                    self.logger,
                    f"chunked_insertion_{table_name}",
                    total_rows=total_rows,
                    chunk_size=chunk_size
                ):
                    for i in range(0, total_rows, chunk_size):
                        chunk_num = i // chunk_size + 1
                        chunk = df.iloc[i:i + chunk_size]

                        try:
                            # Use DuckDB's register and INSERT FROM VALUES approach
                            conn.register("temp_df", chunk)

                            if i == 0 and if_exists in ["replace", "fail"]:
                                # Create table from first chunk
                                conn.execute(f"CREATE TABLE {table_name} AS SELECT * FROM temp_df")
                                self.logger.debug(f"Created table {table_name} from first chunk")
                            else:
                                # Insert subsequent chunks
                                conn.execute(f"INSERT INTO {table_name} SELECT * FROM temp_df")

                            conn.unregister("temp_df")
                            rows_inserted += len(chunk)

                            self.logger.debug(
                                f"Inserted chunk {chunk_num}/{(total_rows + chunk_size - 1) // chunk_size}",
                                extra={
                                    "chunk_number": chunk_num,
                                    "chunk_rows": len(chunk),
                                    "total_inserted": rows_inserted,
                                    "progress_percent": (rows_inserted / total_rows) * 100
                                }
                            )

                        except Exception as chunk_error:
                            failed_chunks.append({
                                "chunk_number": chunk_num,
                                "start_row": i,
                                "end_row": min(i + chunk_size, total_rows),
                                "error": str(chunk_error)
                            })
                            self.logger.error(
                                f"Failed to insert chunk {chunk_num}: {chunk_error}",
                                extra={
                                    "chunk_number": chunk_num,
                                    "chunk_start": i,
                                    "chunk_size": len(chunk),
                                    "error_type": type(chunk_error).__name__
                                }
                            )
                            # Try to unregister in case of failure
                            try:
                                conn.unregister("temp_df")
                            except:
                                pass

                if failed_chunks:
                    self.logger.error(
                        f"Failed to insert {len(failed_chunks)} chunks out of {(total_rows + chunk_size - 1) // chunk_size}",
                        extra={
                            "failed_chunks": len(failed_chunks),
                            "successful_rows": rows_inserted,
                            "failed_chunk_details": failed_chunks[:5]  # Log first 5 failures
                        }
                    )
                    return False

                self.logger.info(
                    f"Successfully inserted {rows_inserted} rows into {table_name}",
                    extra={
                        "table_name": table_name,
                        "rows_inserted": rows_inserted,
                        "chunks_processed": (total_rows + chunk_size - 1) // chunk_size
                    }
                )
                return True

        except Exception as e:
            self.logger.error(
                f"Error inserting DataFrame into {table_name}: {e}",
                extra={
                    "table_name": table_name,
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "rows_attempted": len(df),
                    "traceback": traceback.format_exc()
                }
            )
            return False

    @with_logging("query_to_dataframe")
    def query_to_dataframe(
        self,
        query: str,
        params: Optional[List] = None
    ) -> Optional[pd.DataFrame]:
        """
        Execute a SQL query and return results as a DataFrame.

        Args:
            query: SQL query to execute
            params: Optional query parameters

        Returns:
            DataFrame with query results or None if error
        """
        query_preview = query[:200] + "..." if len(query) > 200 else query

        self.logger.debug(
            f"Executing query: {query_preview}",
            extra={
                "query_length": len(query),
                "has_params": params is not None,
                "param_count": len(params) if params else 0
            }
        )

        try:
            with self.db_manager.get_connection(read_only=True) as conn:
                with PerformanceLogger(self.logger, "sql_query_execution"):
                    if params:
                        result = conn.execute(query, params).fetchdf()
                    else:
                        result = conn.execute(query).fetchdf()

                self.logger.info(
                    f"Query executed successfully: {len(result)} rows returned",
                    extra={
                        "rows_returned": len(result),
                        "columns_returned": len(result.columns),
                        "memory_usage_mb": result.memory_usage(deep=True).sum() / 1024 / 1024
                    }
                )
                return result

        except Exception as e:
            self.db_manager.error_handler.handle_query_error(e, query, params)
            return None

    @with_logging("get_table_count")
    def get_table_count(self, table_name: str) -> int:
        """
        Get the number of rows in a table.

        Args:
            table_name: Name of the table

        Returns:
            Number of rows (0 if table doesn't exist or error)
        """
        try:
            with self.db_manager.get_connection(read_only=True) as conn:
                result = conn.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()
                count = result[0] if result else 0

                self.logger.debug(
                    f"Table {table_name} has {count} rows",
                    extra={"table_name": table_name, "row_count": count}
                )
                return count

        except Exception as e:
            self.logger.error(
                f"Error getting count for {table_name}: {e}",
                extra={
                    "table_name": table_name,
                    "error_type": type(e).__name__,
                    "error_message": str(e)
                }
            )
            return 0

    def table_exists(self, table_name: str) -> bool:
        """
        Check if a table exists in the database.

        Args:
            table_name: Name of the table

        Returns:
            True if table exists, False otherwise
        """
        try:
            with self.db_manager.get_connection(read_only=True) as conn:
                result = conn.execute(
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
                    [table_name]
                ).fetchone()
                return result[0] > 0
        except Exception as e:
            self.logger.error(f"Error checking if table {table_name} exists: {e}")
            return False

    def create_table_from_schema(
        self,
        table_name: str,
        schema: Dict[str, str],
        primary_key: Optional[List[str]] = None,
        if_exists: str = "fail"
    ) -> bool:
        """
        Create a table with the specified schema.

        Args:
            table_name: Name of the table to create
            schema: Dictionary mapping column names to SQL types
            primary_key: Optional list of primary key columns
            if_exists: What to do if table exists ('fail', 'replace', 'skip')

        Returns:
            True if successful, False otherwise
        """
        try:
            with self.db_manager.get_connection() as conn:
                # Check if table exists
                if self.table_exists(table_name):
                    if if_exists == "fail":
                        raise ValueError(f"Table {table_name} already exists")
                    elif if_exists == "skip":
                        self.logger.info(f"Table {table_name} already exists, skipping creation")
                        return True
                    elif if_exists == "replace":
                        conn.execute(f"DROP TABLE IF EXISTS {table_name}")

                # Build CREATE TABLE statement
                columns = []
                for col_name, col_type in schema.items():
                    columns.append(f"{col_name} {col_type}")

                if primary_key:
                    pk_clause = f"PRIMARY KEY ({', '.join(primary_key)})"
                    columns.append(pk_clause)

                create_sql = f"CREATE TABLE {table_name} ({', '.join(columns)})"

                conn.execute(create_sql)
                self.logger.info(f"Created table {table_name} with {len(schema)} columns")
                return True

        except Exception as e:
            self.logger.error(f"Error creating table {table_name}: {e}")
            return False

    def bulk_insert_dict_data(
        self,
        data: List[Dict[str, Any]],
        table_name: str,
        chunk_size: int = 1000
    ) -> bool:
        """
        Insert a list of dictionaries into a table.

        Args:
            data: List of dictionaries to insert
            table_name: Target table name
            chunk_size: Number of records to insert at once

        Returns:
            True if successful, False otherwise
        """
        if not data:
            self.logger.warning(f"No data provided for {table_name}")
            return True

        try:
            # Convert to DataFrame and use existing insert method
            df = pd.DataFrame(data)
            return self.insert_dataframe(df, table_name, chunk_size=chunk_size)

        except Exception as e:
            self.logger.error(f"Error bulk inserting data into {table_name}: {e}")
            return False

    def upsert_data(
        self,
        df: pd.DataFrame,
        table_name: str,
        key_columns: List[str],
        chunk_size: int = 1000
    ) -> bool:
        """
        Upsert (insert or update) data based on key columns.

        Args:
            df: DataFrame with data to upsert
            table_name: Target table name
            key_columns: Columns to use for matching existing records
            chunk_size: Number of rows to process at once

        Returns:
            True if successful, False otherwise
        """
        if df.empty:
            self.logger.warning(f"No data provided for upsert to {table_name}")
            return True

        try:
            with self.db_manager.get_connection() as conn:
                # Create temporary table
                temp_table = f"temp_{table_name}_{int(datetime.now().timestamp())}"

                # Register DataFrame as temporary table
                conn.register(temp_table, df)

                # Build MERGE statement (DuckDB doesn't support MERGE, so use INSERT OR REPLACE)
                if not self.table_exists(table_name):
                    # If target table doesn't exist, just insert
                    conn.execute(f"CREATE TABLE {table_name} AS SELECT * FROM {temp_table}")
                else:
                    # Delete existing records that match key columns
                    key_conditions = []
                    for key_col in key_columns:
                        key_conditions.append(f"{table_name}.{key_col} = {temp_table}.{key_col}")

                    delete_sql = f"""
                    DELETE FROM {table_name}
                    WHERE EXISTS (
                        SELECT 1 FROM {temp_table}
                        WHERE {' AND '.join(key_conditions)}
                    )
                    """
                    conn.execute(delete_sql)

                    # Insert all records from temp table
                    conn.execute(f"INSERT INTO {table_name} SELECT * FROM {temp_table}")

                conn.unregister(temp_table)

                self.logger.info(f"Successfully upserted {len(df)} rows into {table_name}")
                return True

        except Exception as e:
            self.logger.error(f"Error upserting data into {table_name}: {e}")
            return False

    def export_table_to_csv(
        self,
        table_name: str,
        output_path: str,
        where_clause: Optional[str] = None
    ) -> bool:
        """
        Export a table to CSV file.

        Args:
            table_name: Name of the table to export
            output_path: Path for the output CSV file
            where_clause: Optional WHERE clause to filter data

        Returns:
            True if successful, False otherwise
        """
        try:
            output_file = Path(output_path)
            output_file.parent.mkdir(parents=True, exist_ok=True)

            with self.db_manager.get_connection(read_only=True) as conn:
                query = f"SELECT * FROM {table_name}"
                if where_clause:
                    query += f" WHERE {where_clause}"

                conn.execute(f"COPY ({query}) TO '{output_path}' (FORMAT CSV, HEADER)")

            self.logger.info(f"Exported {table_name} to {output_path}")
            return True

        except Exception as e:
            self.logger.error(f"Error exporting {table_name} to CSV: {e}")
            return False

    def get_database_summary(self) -> Dict[str, Any]:
        """
        Get a summary of the database contents.

        Returns:
            Dictionary with database summary information
        """
        try:
            summary = {
                "database_path": self.db_manager.database_path,
                "database_size_mb": self.db_manager.get_database_size_mb(),
                "tables": {}
            }

            tables = self.db_manager.list_tables()
            for table in tables:
                table_info = self.db_manager.get_table_info(table)
                if table_info:
                    summary["tables"][table] = {
                        "row_count": table_info["row_count"],
                        "column_count": len(table_info["columns"])
                    }

            return summary

        except Exception as e:
            self.logger.error(f"Error getting database summary: {e}")
            return {"error": str(e)}