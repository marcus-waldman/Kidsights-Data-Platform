#!/usr/bin/env python3
"""
Safe R Script Executor

This module provides utilities for executing R code safely by creating temporary
script files, avoiding the segmentation faults that occur with R.exe -e.

The R installation has persistent issues with inline code execution, but works
reliably when executing script files with the --file flag.

Usage:
    from python.utils.r_executor import execute_r_script

    code = '''
    library(dplyr)
    cat("Hello from R!\\n")
    '''

    result, return_code = execute_r_script(code)
    print(result)

Author: Kidsights Data Platform
"""

import tempfile
import subprocess
import os
from pathlib import Path
from typing import Tuple, Optional
import uuid
import time


class RExecutor:
    """Safe R script executor using temporary files"""

    def __init__(self, r_executable: str = r"C:\Program Files\R\R-4.5.1\bin\R.exe"):
        """
        Initialize R executor

        Args:
            r_executable: Path to R.exe executable
        """
        self.r_executable = r_executable
        self.temp_dir = Path("scripts/temp")

        # Ensure temp directory exists
        self.temp_dir.mkdir(parents=True, exist_ok=True)

        if not Path(self.r_executable).exists():
            raise FileNotFoundError(f"R executable not found: {self.r_executable}")

    def execute_script(self,
                      code: str,
                      working_dir: Optional[str] = None,
                      timeout: int = 300,
                      cleanup: bool = True) -> Tuple[str, str, int]:
        """
        Execute R code via temporary script file

        Args:
            code: R code to execute
            working_dir: Working directory for R execution
            timeout: Timeout in seconds (default 5 minutes)
            cleanup: Whether to delete temporary file after execution

        Returns:
            Tuple of (stdout, stderr, return_code)
        """
        # Create unique temporary script file
        timestamp = int(time.time() * 1000)
        unique_id = str(uuid.uuid4())[:8]
        script_name = f"r_exec_{timestamp}_{unique_id}.R"
        temp_script = self.temp_dir / script_name

        try:
            # Write R code to temporary file
            with open(temp_script, 'w', encoding='utf-8') as f:
                f.write(code)

            # Build R command
            cmd = [
                self.r_executable,
                "--arch", "x64",
                "--slave",
                "--no-save",
                "--no-restore",
                "--no-environ",
                "-f", str(temp_script)
            ]

            # Execute R script
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=working_dir,
                timeout=timeout,
                encoding='cp1252',  # Windows ANSI encoding
                errors='replace'  # Handle encoding issues gracefully
            )

            return result.stdout, result.stderr, result.returncode

        except subprocess.TimeoutExpired:
            return "", f"R script execution timed out after {timeout} seconds", 1
        except Exception as e:
            return "", f"Error executing R script: {str(e)}", 1
        finally:
            # Clean up temporary file
            if cleanup and temp_script.exists():
                try:
                    temp_script.unlink()
                except Exception as e:
                    print(f"Warning: Could not delete temporary file {temp_script}: {e}")

    def execute_script_with_output(self,
                                  code: str,
                                  working_dir: Optional[str] = None,
                                  timeout: int = 300) -> str:
        """
        Execute R code and return combined output (convenient wrapper)

        Args:
            code: R code to execute
            working_dir: Working directory for R execution
            timeout: Timeout in seconds

        Returns:
            Combined stdout and stderr output

        Raises:
            RuntimeError: If R script execution fails
        """
        stdout, stderr, return_code = self.execute_script(code, working_dir, timeout)

        if return_code != 0:
            error_msg = f"R script failed with return code {return_code}"
            if stderr:
                error_msg += f"\nError output: {stderr}"
            if stdout:
                error_msg += f"\nStandard output: {stdout}"
            raise RuntimeError(error_msg)

        # Combine outputs
        output = ""
        if stdout:
            output += stdout
        if stderr:
            output += stderr

        return output


# Convenience functions for common use cases
_executor = None

def get_executor() -> RExecutor:
    """Get singleton R executor instance"""
    global _executor
    if _executor is None:
        _executor = RExecutor()
    return _executor


def execute_r_script(code: str,
                    working_dir: Optional[str] = None,
                    timeout: int = 300) -> Tuple[str, int]:
    """
    Execute R code safely via temporary file (convenience function)

    Args:
        code: R code to execute
        working_dir: Working directory for R execution
        timeout: Timeout in seconds

    Returns:
        Tuple of (combined_output, return_code)
    """
    executor = get_executor()
    stdout, stderr, return_code = executor.execute_script(code, working_dir, timeout)

    # Combine outputs
    combined_output = ""
    if stdout:
        combined_output += stdout
    if stderr:
        if combined_output:
            combined_output += "\n"
        combined_output += stderr

    return combined_output, return_code


def execute_r_script_safe(code: str,
                         working_dir: Optional[str] = None,
                         timeout: int = 300) -> str:
    """
    Execute R code and return output, raising exception on failure

    Args:
        code: R code to execute
        working_dir: Working directory for R execution
        timeout: Timeout in seconds

    Returns:
        Combined output from R execution

    Raises:
        RuntimeError: If R script execution fails
    """
    executor = get_executor()
    return executor.execute_script_with_output(code, working_dir, timeout)


# Example usage for testing
if __name__ == "__main__":
    # Test basic execution
    test_code = '''
    cat("Hello from R!\\n")
    cat("R version:", R.version.string, "\\n")
    cat("Working directory:", getwd(), "\\n")
    '''

    try:
        output, return_code = execute_r_script(test_code)
        print("=== R EXECUTION TEST ===")
        print(f"Return code: {return_code}")
        print(f"Output:\n{output}")
        print("=== TEST COMPLETE ===")
    except Exception as e:
        print(f"Error testing R executor: {e}")