#!/usr/bin/env python3
"""
Kidsights Data Platform - Installation Verification Script

This script performs comprehensive checks of your installation to ensure
all components are properly configured. Run this after initial setup or
when troubleshooting issues.

Usage:
    python scripts/setup/verify_installation.py

Exit Codes:
    0 - All critical checks passed
    1 - One or more critical checks failed
    2 - Warnings present (non-critical issues)

Author: Kidsights Data Platform Team
Version: 1.0.0
"""

import sys
import os
import subprocess
from pathlib import Path
from typing import Tuple, List, Optional
import platform

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))


class Colors:
    """ANSI color codes for terminal output."""
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


class VerificationStatus:
    """Track verification results."""
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.warnings = 0
        self.errors = []

    def add_pass(self):
        self.passed += 1

    def add_fail(self, message: str):
        self.failed += 1
        self.errors.append(message)

    def add_skip(self):
        self.skipped += 1

    def add_warning(self):
        self.warnings += 1


# Global status tracker
status = VerificationStatus()


def print_header(text: str):
    """Print section header."""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 70}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 70}{Colors.RESET}\n")


def print_check(name: str, result: bool, message: str = "", skip: bool = False):
    """Print check result with color coding."""
    if skip:
        print(f"  {Colors.YELLOW}[SKIP]{Colors.RESET} {name}")
        if message:
            print(f"         {message}")
        status.add_skip()
    elif result:
        print(f"  {Colors.GREEN}[OK]{Colors.RESET}   {name}")
        if message:
            print(f"         {message}")
        status.add_pass()
    else:
        print(f"  {Colors.RED}[FAIL]{Colors.RESET} {name}")
        if message:
            print(f"         {Colors.RED}{message}{Colors.RESET}")
        status.add_fail(name)


def run_command(cmd: List[str], capture_output: bool = True) -> Tuple[bool, str]:
    """Run a command and return success status and output."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            timeout=10
        )
        return result.returncode == 0, result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as e:
        return False, str(e)


def check_python_version() -> bool:
    """Check Python version is 3.13 or higher."""
    version = sys.version_info
    required = (3, 13)

    current = f"{version.major}.{version.minor}.{version.micro}"
    is_valid = (version.major, version.minor) >= required

    if is_valid:
        print_check(
            "Python version",
            True,
            f"Python {current} (required: {required[0]}.{required[1]}+)"
        )
    else:
        print_check(
            "Python version",
            False,
            f"Python {current} found, but {required[0]}.{required[1]}+ required"
        )

    return is_valid


def check_python_packages() -> bool:
    """Check required Python packages are installed."""
    required_packages = {
        'duckdb': 'Database operations',
        'pandas': 'Data manipulation',
        'yaml': 'Configuration files (PyYAML)',
        'structlog': 'Structured logging',
        'dotenv': 'Environment variables (python-dotenv)',
        'ipumspy': 'IPUMS API client (for ACS/NHIS)',
        'pyreadstat': 'SPSS file reading (for NSCH)'
    }

    all_installed = True
    missing = []

    for package, description in required_packages.items():
        # Special case for yaml (package is PyYAML)
        import_name = package
        package_name = 'PyYAML' if package == 'yaml' else package
        package_name = 'python-dotenv' if package == 'dotenv' else package_name

        try:
            __import__(import_name)
            print_check(f"Python package: {package_name}", True, description)
        except ImportError:
            print_check(
                f"Python package: {package_name}",
                False,
                f"Install with: pip install {package_name}"
            )
            missing.append(package_name)
            all_installed = False

    if missing:
        print(f"\n  {Colors.YELLOW}Install all missing packages:{Colors.RESET}")
        print(f"  pip install {' '.join(missing)}")

    return all_installed


def check_r_installation() -> bool:
    """Check R is installed and accessible."""
    # Common R locations
    r_paths = [
        "C:/Program Files/R/R-4.5.1/bin/R.exe",
        "C:/Program Files/R/R-4.5.1/bin/Rscript.exe",
        "/usr/bin/R",
        "/usr/local/bin/R",
        "/opt/homebrew/bin/R"
    ]

    # Try to find R in PATH
    success, output = run_command(['R', '--version'])

    if success:
        # Extract version from output
        lines = output.split('\n')
        version_line = lines[0] if lines else ''
        print_check("R installation", True, version_line)
        return True

    # Try specific paths
    for r_path in r_paths:
        if Path(r_path).exists():
            success, output = run_command([r_path, '--version'])
            if success:
                lines = output.split('\n')
                version_line = lines[0] if lines else ''
                print_check("R installation", True, f"Found at {r_path}")
                return True

    print_check(
        "R installation",
        False,
        "R not found. Install from https://cran.r-project.org/"
    )
    return False


def check_r_packages() -> bool:
    """Check required R packages are installed."""
    required_packages = [
        'dplyr', 'tidyr', 'stringr', 'yaml', 'REDCapR', 'arrow', 'duckdb'
    ]

    # Create R script to check packages
    r_script = '; '.join([
        f"if (!requireNamespace('{pkg}', quietly = TRUE)) cat('{pkg}\\n')"
        for pkg in required_packages
    ])

    # Try to run R
    try:
        # Try different R commands
        for r_cmd in ['Rscript', 'R']:
            success, output = run_command([r_cmd, '-e', r_script])
            if success:
                if output:
                    # Some packages are missing
                    missing = output.strip().split('\n')
                    for pkg in required_packages:
                        if pkg in missing:
                            print_check(
                                f"R package: {pkg}",
                                False,
                                f"Install in R: install.packages('{pkg}')"
                            )
                        else:
                            print_check(f"R package: {pkg}", True)
                    return False
                else:
                    # All packages installed
                    for pkg in required_packages:
                        print_check(f"R package: {pkg}", True)
                    return True
    except Exception as e:
        print_check("R packages", False, f"Could not check R packages: {e}", skip=True)
        return False

    print_check("R packages", False, "Could not verify R packages", skip=True)
    return False


def check_env_file() -> Tuple[bool, dict]:
    """Check .env file exists and has required variables."""
    env_file = project_root / '.env'

    if not env_file.exists():
        print_check(
            ".env file",
            False,
            "Copy .env.template to .env and configure your paths"
        )
        return False, {}

    # Load .env file
    env_vars = {}
    try:
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip().strip('"').strip("'")

        print_check(".env file", True, f"Found with {len(env_vars)} variables")
        return True, env_vars
    except Exception as e:
        print_check(".env file", False, f"Error reading .env: {e}")
        return False, {}


def check_api_keys(env_vars: dict) -> bool:
    """Check API key files exist and are readable."""
    checks_passed = True

    # Check IPUMS API key
    ipums_path = env_vars.get('IPUMS_API_KEY_PATH')
    if ipums_path:
        ipums_file = Path(ipums_path)
        if ipums_file.exists():
            try:
                with open(ipums_file, 'r') as f:
                    key = f.read().strip()
                    if key and len(key) > 20:
                        print_check(
                            "IPUMS API key file",
                            True,
                            f"Found at {ipums_path} ({len(key)} chars)"
                        )
                    else:
                        print_check(
                            "IPUMS API key file",
                            False,
                            "File exists but appears empty or invalid"
                        )
                        checks_passed = False
            except Exception as e:
                print_check("IPUMS API key file", False, f"Error reading file: {e}")
                checks_passed = False
        else:
            print_check(
                "IPUMS API key file",
                False,
                f"File not found: {ipums_path}"
            )
            checks_passed = False
    else:
        print_check(
            "IPUMS API key file",
            False,
            "IPUMS_API_KEY_PATH not set in .env",
            skip=True
        )

    # Check REDCap API credentials
    redcap_path = env_vars.get('REDCAP_API_CREDENTIALS_PATH')
    if redcap_path:
        redcap_file = Path(redcap_path)
        if redcap_file.exists():
            try:
                with open(redcap_file, 'r') as f:
                    lines = [line.strip() for line in f if line.strip()]
                    if len(lines) > 1:  # Header + at least one data row
                        print_check(
                            "REDCap API credentials file",
                            True,
                            f"Found at {redcap_path} ({len(lines)-1} projects)"
                        )
                    else:
                        print_check(
                            "REDCap API credentials file",
                            False,
                            "File exists but appears empty"
                        )
                        checks_passed = False
            except Exception as e:
                print_check("REDCap API credentials file", False, f"Error reading file: {e}")
                checks_passed = False
        else:
            print_check(
                "REDCap API credentials file",
                False,
                f"File not found: {redcap_path}"
            )
            checks_passed = False
    else:
        print_check(
            "REDCap API credentials file",
            False,
            "REDCAP_API_CREDENTIALS_PATH not set in .env",
            skip=True
        )

    return checks_passed


def check_directory_structure() -> bool:
    """Check required directories exist."""
    required_dirs = [
        'data',
        'data/duckdb',
        'data/acs',
        'data/nhis',
        'data/nsch',
        'config',
        'scripts',
        'python',
        'R'
    ]

    all_exist = True
    for dir_path in required_dirs:
        full_path = project_root / dir_path
        if full_path.exists():
            print_check(f"Directory: {dir_path}", True)
        else:
            print_check(
                f"Directory: {dir_path}",
                False,
                f"Create with: mkdir -p {dir_path}"
            )
            all_exist = False

    return all_exist


def check_database_connection() -> bool:
    """Check DuckDB database connection works."""
    try:
        from python.db.connection import DatabaseManager

        db = DatabaseManager()
        if db.test_connection():
            print_check(
                "DuckDB connection",
                True,
                f"Database at: {db.database_path}"
            )
            return True
        else:
            print_check(
                "DuckDB connection",
                False,
                "Connection test failed"
            )
            return False
    except Exception as e:
        print_check(
            "DuckDB connection",
            False,
            f"Error: {e}"
        )
        return False


def check_ipums_api() -> bool:
    """Check IPUMS API connection if configured."""
    try:
        from python.acs.auth import get_client

        client = get_client()
        print_check(
            "IPUMS API connection",
            True,
            "API client initialized successfully"
        )
        return True
    except FileNotFoundError as e:
        print_check(
            "IPUMS API connection",
            False,
            str(e),
            skip=True
        )
        return False
    except Exception as e:
        print_check(
            "IPUMS API connection",
            False,
            f"Error: {e}"
        )
        return False


def print_summary():
    """Print summary of verification results."""
    print_header("VERIFICATION SUMMARY")

    total = status.passed + status.failed + status.skipped

    print(f"  Total checks: {total}")
    print(f"  {Colors.GREEN}Passed:  {status.passed}{Colors.RESET}")
    print(f"  {Colors.RED}Failed:  {status.failed}{Colors.RESET}")
    print(f"  {Colors.YELLOW}Skipped: {status.skipped}{Colors.RESET}")

    if status.failed == 0:
        print(f"\n  {Colors.GREEN}{Colors.BOLD}[OK] All critical checks passed!{Colors.RESET}")
        print(f"  {Colors.GREEN}Your installation is ready to use.{Colors.RESET}\n")
        return 0
    elif status.failed <= 3 and status.passed > status.failed:
        print(f"\n  {Colors.YELLOW}{Colors.BOLD}[WARN] Some checks failed{Colors.RESET}")
        print(f"  {Colors.YELLOW}You can proceed but may encounter issues.{Colors.RESET}\n")
        return 2
    else:
        print(f"\n  {Colors.RED}{Colors.BOLD}[FAIL] Critical checks failed{Colors.RESET}")
        print(f"  {Colors.RED}Please fix the errors above before proceeding.{Colors.RESET}\n")
        return 1


def main():
    """Run all verification checks."""
    print_header("KIDSIGHTS DATA PLATFORM - INSTALLATION VERIFICATION")

    print(f"Project root: {project_root}")
    print(f"Platform: {platform.system()} {platform.release()}")
    print(f"Python: {sys.version.split()[0]}")

    # Environment checks
    print_header("1. ENVIRONMENT")
    check_python_version()
    check_r_installation()

    # Package checks
    print_header("2. PYTHON PACKAGES")
    check_python_packages()

    print_header("3. R PACKAGES")
    check_r_packages()

    # Configuration checks
    print_header("4. CONFIGURATION")
    env_exists, env_vars = check_env_file()

    # API key checks
    print_header("5. API KEYS")
    if env_exists:
        check_api_keys(env_vars)
    else:
        print("  Skipping API key checks (.env file not found)")

    # Directory structure
    print_header("6. DIRECTORY STRUCTURE")
    check_directory_structure()

    # Database checks
    print_header("7. DATABASE")
    check_database_connection()

    # API connectivity
    print_header("8. API CONNECTIVITY")
    check_ipums_api()

    # Print summary and exit
    exit_code = print_summary()

    # Next steps
    if exit_code == 0:
        print("Next steps:")
        print("  - Run NE25 pipeline: python run_ne25_pipeline.R")
        print("  - Run ACS pipeline: python pipelines/python/acs/extract_acs_data.py")
        print("  - See docs/QUICK_REFERENCE.md for more commands\n")

    return exit_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Verification interrupted by user.{Colors.RESET}")
        sys.exit(130)
    except Exception as e:
        print(f"\n{Colors.RED}Unexpected error: {e}{Colors.RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
