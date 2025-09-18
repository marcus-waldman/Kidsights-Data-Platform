"""
Database connection manager for Kidsights Data Platform.

Provides centralized, robust connection management for DuckDB operations.
Eliminates R DuckDB segmentation faults by handling all database operations in Python.
"""

import duckdb
from pathlib import Path
from contextlib import contextmanager
from typing import Optional, Dict, Any, Generator
import time
import logging
import sys
import os
from .config import load_config, get_database_path
try:
    from utils.logging import DatabaseErrorHandler, PerformanceLogger, with_logging
except ImportError:
    # Fallback for when module structure isn't available
    def DatabaseErrorHandler(logger):
        class DummyHandler:
            def handle_connection_error(self, error, retry_count):
                return retry_count < 3
            def handle_query_error(self, error, query, params=None):
                pass
        return DummyHandler()

    def PerformanceLogger(logger, operation, **kwargs):
        class DummyContext:
            def __enter__(self): return self
            def __exit__(self, *args): pass
        return DummyContext()

    def with_logging(name):
        def decorator(func):
            return func
        return decorator


class DatabaseManager:
    """
    Centralized DuckDB connection management for Kidsights Data Platform.

    This class provides a clean interface for database operations while ensuring
    proper connection handling, automatic retries, and error management.
    """

    def __init__(self, config_path: str = "config/sources/ne25.yaml"):
        """
        Initialize the database manager.

        Args:
            config_path: Path to configuration file
        """
        self.config = load_config(config_path)
        self.db_path = Path(get_database_path(self.config))
        self.logger = logging.getLogger("kidsights.db")
        self.error_handler = DatabaseErrorHandler(self.logger)

        # Ensure database directory exists
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        # Log initialization
        self.logger.info(
            "Database manager initialized",
            extra={
                "database_path": str(self.db_path),
                "database_exists": self.database_exists(),
                "config_path": config_path
            }
        )

    @property
    def database_path(self) -> str:
        """Get the database path as string."""
        return str(self.db_path)

    def database_exists(self) -> bool:
        """Check if the database file exists."""
        return self.db_path.exists()

    def get_database_size_mb(self) -> float:
        """Get database file size in MB."""
        if self.database_exists():
            return self.db_path.stat().st_size / (1024 * 1024)
        return 0.0

    @contextmanager
    def get_connection(
        self,
        read_only: bool = False,
        timeout: int = 30,
        retry_attempts: int = 3
    ) -> Generator[duckdb.DuckDBPyConnection, None, None]:
        """
        Get a database connection with automatic cleanup.

        Args:
            read_only: Whether to open in read-only mode
            timeout: Connection timeout in seconds
            retry_attempts: Number of retry attempts on failure

        Yields:
            DuckDB connection object

        Raises:
            ConnectionError: If connection fails after all retry attempts
        """
        connection = None
        last_error = None

        for attempt in range(retry_attempts):
            try:
                self.logger.debug(
                    f"Attempting database connection (attempt {attempt + 1}/{retry_attempts})",
                    extra={
                        "db_path": self.database_path,
                        "read_only": read_only,
                        "timeout": timeout,
                        "attempt": attempt + 1
                    }
                )

                # Check database file accessibility
                if not self.database_exists():
                    self.logger.warning(f"Database file does not exist: {self.database_path}")

                # Check file permissions (only if file exists)
                if self.database_exists():
                    if not os.access(self.database_path, os.R_OK):
                        raise PermissionError(f"No read access to database: {self.database_path}")

                    if not read_only and not os.access(self.database_path, os.W_OK):
                        raise PermissionError(f"No write access to database: {self.database_path}")
                else:
                    # For new database, check directory permissions
                    db_dir = os.path.dirname(self.database_path)
                    if not os.access(db_dir, os.W_OK):
                        raise PermissionError(f"No write access to database directory: {db_dir}")

                connection = duckdb.connect(
                    database=self.database_path,
                    read_only=read_only,
                    config={
                        'threads': '4',
                        'memory_limit': '2GB',
                        'max_memory': '2GB'
                    }
                )

                # Test connection with timeout
                connection.execute("SELECT 1").fetchone()

                self.logger.debug(
                    "Database connection established successfully",
                    extra={
                        "attempt": attempt + 1,
                        "connection_mode": "read_only" if read_only else "read_write"
                    }
                )
                yield connection
                return

            except Exception as e:
                last_error = e

                # Use specialized error handler
                should_retry = self.error_handler.handle_connection_error(e, attempt)

                if connection:
                    try:
                        connection.close()
                    except Exception as close_error:
                        self.logger.warning(f"Error closing failed connection: {close_error}")
                    connection = None

                if attempt < retry_attempts - 1 and should_retry:
                    backoff_time = min(2 ** attempt, 10)  # Exponential backoff with max 10s
                    self.logger.info(f"Retrying connection in {backoff_time}s...")
                    time.sleep(backoff_time)
                elif not should_retry:
                    self.logger.error(f"Non-retryable error encountered: {e}")
                    break

            finally:
                if connection:
                    try:
                        connection.close()
                        self.logger.debug("Database connection closed")
                    except Exception as e:
                        self.logger.warning(f"Error closing connection: {e}")

        raise ConnectionError(
            f"Failed to connect to database after {retry_attempts} attempts. "
            f"Last error: {last_error}"
        )

    @with_logging("database_connection_test")
    def test_connection(self) -> bool:
        """
        Test database connectivity.

        Returns:
            True if connection successful, False otherwise
        """
        try:
            with self.get_connection(read_only=True) as conn:
                # Run a more comprehensive test
                conn.execute("SELECT 1").fetchone()

                # Test basic DuckDB functionality
                conn.execute("SELECT COUNT(*) FROM information_schema.tables").fetchone()

            self.logger.info("Database connection test successful")
            return True
        except Exception as e:
            self.logger.error(
                f"Database connection test failed: {e}",
                extra={
                    "error_type": type(e).__name__,
                    "database_path": self.database_path,
                    "database_exists": self.database_exists(),
                    "database_size_mb": self.get_database_size_mb()
                }
            )
            return False

    def get_table_info(self, table_name: str) -> Optional[Dict[str, Any]]:
        """
        Get information about a table.

        Args:
            table_name: Name of the table

        Returns:
            Dictionary with table information or None if table doesn't exist
        """
        try:
            with self.get_connection(read_only=True) as conn:
                # Check if table exists
                result = conn.execute(
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
                    [table_name]
                ).fetchone()

                if result[0] == 0:
                    self.logger.debug(f"Table {table_name} does not exist")
                    return None

                # Get table info with error handling
                try:
                    schema_info = conn.execute(f"PRAGMA table_info({table_name})").fetchall()
                    row_count = conn.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]
                except Exception as query_error:
                    self.error_handler.handle_query_error(
                        query_error,
                        f"PRAGMA table_info({table_name})"
                    )
                    raise

                return {
                    "table_name": table_name,
                    "row_count": row_count,
                    "columns": [
                        {
                            "name": col[1],
                            "type": col[2],
                            "not_null": bool(col[3]),
                            "primary_key": bool(col[5])
                        }
                        for col in schema_info
                    ]
                }

        except Exception as e:
            self.logger.error(f"Error getting table info for {table_name}: {e}")
            return None

    def list_tables(self) -> list:
        """
        List all tables in the database.

        Returns:
            List of table names
        """
        try:
            with self.get_connection(read_only=True) as conn:
                result = conn.execute("SHOW TABLES").fetchall()
                return [row[0] for row in result]
        except Exception as e:
            self.logger.error(f"Error listing tables: {e}")
            return []

    def execute_sql_file(self, sql_file_path: str) -> bool:
        """
        Execute SQL commands from a file.

        Args:
            sql_file_path: Path to SQL file

        Returns:
            True if successful, False otherwise
        """
        try:
            sql_path = Path(sql_file_path)
            if not sql_path.exists():
                self.logger.error(f"SQL file not found: {sql_file_path}")
                return False

            with open(sql_path, 'r', encoding='utf-8') as f:
                sql_content = f.read()

            # Split on semicolons and execute each statement
            statements = [stmt.strip() for stmt in sql_content.split(';') if stmt.strip()]

            with self.get_connection() as conn:
                for i, statement in enumerate(statements):
                    try:
                        with PerformanceLogger(self.logger, f"SQL statement {i + 1}"):
                            conn.execute(statement)
                        self.logger.debug(f"Executed statement {i + 1}/{len(statements)}")
                    except Exception as e:
                        self.error_handler.handle_query_error(e, statement)
                        return False

            self.logger.info(f"Successfully executed {len(statements)} statements from {sql_file_path}")
            return True

        except Exception as e:
            self.logger.error(f"Error executing SQL file {sql_file_path}: {e}")
            return False

    def backup_database(self, backup_path: str) -> bool:
        """
        Create a backup of the database.

        Args:
            backup_path: Path for the backup file

        Returns:
            True if successful, False otherwise
        """
        try:
            backup_file = Path(backup_path)
            backup_file.parent.mkdir(parents=True, exist_ok=True)

            with self.get_connection(read_only=True) as conn:
                conn.execute(f"EXPORT DATABASE '{backup_path}' (FORMAT PARQUET)")

            self.logger.info(f"Database backed up to: {backup_path}")
            return True

        except Exception as e:
            self.logger.error(f"Error backing up database: {e}")
            return False