"""
Logging utilities for Kidsights Data Platform.

Provides structured logging for database operations and pipeline execution.
"""

import logging
import structlog
from pathlib import Path
from typing import Optional, Dict, Any, Union
import sys
import time
import traceback
from functools import wraps
from contextlib import contextmanager
import json
import os
from datetime import datetime


def setup_logging(
    level: str = "INFO",
    log_file: Optional[str] = None,
    structured: bool = True,
    console_output: bool = True
) -> logging.Logger:
    """
    Set up logging for the application.

    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Optional file to write logs to
        structured: Whether to use structured logging (JSON format)

    Returns:
        Configured logger instance
    """
    # Configure structlog if requested
    if structured:
        structlog.configure(
            processors=[
                structlog.stdlib.filter_by_level,
                structlog.stdlib.add_logger_name,
                structlog.stdlib.add_log_level,
                structlog.stdlib.PositionalArgumentsFormatter(),
                structlog.processors.TimeStamper(fmt="iso"),
                structlog.processors.StackInfoRenderer(),
                structlog.processors.format_exc_info,
                structlog.processors.UnicodeDecoder(),
                structlog.processors.JSONRenderer()
            ],
            context_class=dict,
            logger_factory=structlog.stdlib.LoggerFactory(),
            wrapper_class=structlog.stdlib.BoundLogger,
            cache_logger_on_first_use=True,
        )

    # Configure standard logging
    logger = logging.getLogger("kidsights")
    logger.setLevel(getattr(logging, level.upper()))

    # Remove existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    # Create formatter
    if structured:
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    else:
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s'
        )

    # Console handler (optional)
    if console_output:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

    # File handler if specified
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        file_handler = logging.FileHandler(log_path)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger with the specified name.

    Args:
        name: Logger name

    Returns:
        Logger instance
    """
    return logging.getLogger(f"kidsights.{name}")


def log_execution_context(logger: logging.Logger, **context):
    """
    Log execution context information.

    Args:
        logger: Logger instance
        **context: Context information to log
    """
    if hasattr(logger, 'bind'):  # structlog logger
        return logger.bind(**context)
    else:  # standard logger
        context_str = ", ".join(f"{k}={v}" for k, v in context.items())
        logger.info(f"Execution context: {context_str}")
        return logger


class PerformanceLogger:
    """
    Context manager for performance logging.
    """

    def __init__(self, logger: logging.Logger, operation_name: str, **context):
        self.logger = logger
        self.operation_name = operation_name
        self.context = context
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        self.logger.info(
            f"Starting operation: {self.operation_name}",
            extra={"operation": self.operation_name, "status": "started", **self.context}
        )
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = time.time() - self.start_time

        if exc_type is None:
            self.logger.info(
                f"Completed operation: {self.operation_name} in {duration:.2f}s",
                extra={
                    "operation": self.operation_name,
                    "status": "completed",
                    "duration_seconds": duration,
                    **self.context
                }
            )
        else:
            self.logger.error(
                f"Failed operation: {self.operation_name} after {duration:.2f}s - {exc_val}",
                extra={
                    "operation": self.operation_name,
                    "status": "failed",
                    "duration_seconds": duration,
                    "error_type": exc_type.__name__,
                    "error_message": str(exc_val),
                    **self.context
                }
            )


def with_logging(operation_name: str = None, logger_name: str = "kidsights"):
    """
    Decorator for automatic logging of function execution.

    Args:
        operation_name: Name of the operation (defaults to function name)
        logger_name: Name of the logger to use
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            logger = get_logger(logger_name)
            op_name = operation_name or func.__name__

            with PerformanceLogger(logger, op_name, function=func.__name__):
                try:
                    result = func(*args, **kwargs)
                    return result
                except Exception as e:
                    logger.error(
                        f"Function {func.__name__} failed: {e}",
                        extra={
                            "function": func.__name__,
                            "args_count": len(args),
                            "kwargs_keys": list(kwargs.keys()),
                            "error_type": type(e).__name__,
                            "traceback": traceback.format_exc()
                        }
                    )
                    raise
        return wrapper
    return decorator


class DatabaseErrorHandler:
    """
    Specialized error handler for database operations.
    """

    def __init__(self, logger: logging.Logger):
        self.logger = logger

    def handle_connection_error(self, error: Exception, retry_count: int = 0) -> bool:
        """
        Handle database connection errors.

        Args:
            error: The exception that occurred
            retry_count: Current retry attempt number

        Returns:
            True if retry should be attempted, False otherwise
        """
        error_msg = str(error).lower()

        # Determine if error is retryable
        retryable_errors = [
            "connection refused",
            "timeout",
            "database is locked",
            "disk i/o error"
        ]

        is_retryable = any(err in error_msg for err in retryable_errors)

        self.logger.error(
            f"Database connection error (attempt {retry_count + 1}): {error}",
            extra={
                "error_type": type(error).__name__,
                "error_message": str(error),
                "retry_count": retry_count,
                "is_retryable": is_retryable,
                "traceback": traceback.format_exc()
            }
        )

        return is_retryable and retry_count < 3

    def handle_query_error(self, error: Exception, query: str, params: Any = None):
        """
        Handle database query errors.

        Args:
            error: The exception that occurred
            query: The SQL query that failed
            params: Query parameters if any
        """
        # Truncate long queries for logging
        query_preview = query[:200] + "..." if len(query) > 200 else query

        self.logger.error(
            f"Database query failed: {error}",
            extra={
                "error_type": type(error).__name__,
                "error_message": str(error),
                "query_preview": query_preview,
                "query_length": len(query),
                "has_params": params is not None,
                "traceback": traceback.format_exc()
            }
        )


@contextmanager
def error_context(logger: logging.Logger, operation: str, **context):
    """
    Context manager for comprehensive error handling and logging.

    Args:
        logger: Logger instance
        operation: Name of the operation being performed
        **context: Additional context to log
    """
    try:
        logger.info(f"Starting {operation}", extra={"operation": operation, **context})
        yield
        logger.info(f"Successfully completed {operation}", extra={"operation": operation, **context})
    except Exception as e:
        logger.error(
            f"Operation {operation} failed: {e}",
            extra={
                "operation": operation,
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc(),
                **context
            }
        )
        raise


def setup_pipeline_logging(
    pipeline_name: str,
    execution_id: str,
    log_dir: str = "logs",
    level: str = "INFO"
) -> logging.Logger:
    """
    Set up logging specifically for pipeline execution.

    Args:
        pipeline_name: Name of the pipeline
        execution_id: Unique execution identifier
        log_dir: Directory to store log files
        level: Logging level

    Returns:
        Configured logger with both console and file output
    """
    # Create log directory
    log_path = Path(log_dir)
    log_path.mkdir(parents=True, exist_ok=True)

    # Create log file name with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_path / f"{pipeline_name}_{execution_id}_{timestamp}.log"

    # Set up logger with file output
    logger = setup_logging(
        level=level,
        log_file=str(log_file),
        structured=False  # Use human-readable format for pipeline logs
    )

    # Log initial context
    logger.info(
        f"Pipeline {pipeline_name} started",
        extra={
            "pipeline_name": pipeline_name,
            "execution_id": execution_id,
            "log_file": str(log_file),
            "python_version": sys.version,
            "working_directory": os.getcwd()
        }
    )

    return logger


def log_memory_usage(logger: logging.Logger, operation: str = None):
    """
    Log current memory usage (if psutil is available).

    Args:
        logger: Logger instance
        operation: Optional operation name for context
    """
    try:
        import psutil
        process = psutil.Process()
        memory_info = process.memory_info()

        logger.info(
            f"Memory usage{' for ' + operation if operation else ''}: "
            f"{memory_info.rss / 1024 / 1024:.1f} MB RSS, "
            f"{memory_info.vms / 1024 / 1024:.1f} MB VMS",
            extra={
                "memory_rss_mb": memory_info.rss / 1024 / 1024,
                "memory_vms_mb": memory_info.vms / 1024 / 1024,
                "operation": operation
            }
        )
    except ImportError:
        # psutil not available, skip memory logging
        pass
    except Exception as e:
        logger.warning(f"Failed to log memory usage: {e}")


def create_error_summary(errors: list) -> Dict[str, Any]:
    """
    Create a summary of errors for reporting.

    Args:
        errors: List of error dictionaries or exception objects

    Returns:
        Summary dictionary with error statistics and details
    """
    if not errors:
        return {"total_errors": 0, "error_types": {}, "sample_errors": []}

    error_types = {}
    sample_errors = []

    for error in errors[:10]:  # Limit to first 10 for summary
        if isinstance(error, dict):
            error_type = error.get("error_type", "Unknown")
            error_msg = error.get("error_message", str(error))
        elif isinstance(error, Exception):
            error_type = type(error).__name__
            error_msg = str(error)
        else:
            error_type = "Unknown"
            error_msg = str(error)

        # Count error types
        error_types[error_type] = error_types.get(error_type, 0) + 1

        # Add to sample
        sample_errors.append({
            "type": error_type,
            "message": error_msg[:200]  # Truncate long messages
        })

    return {
        "total_errors": len(errors),
        "error_types": error_types,
        "sample_errors": sample_errors,
        "has_more_errors": len(errors) > 10
    }