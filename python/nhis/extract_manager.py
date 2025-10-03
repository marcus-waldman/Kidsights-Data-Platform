"""
Extract Manager for NHIS Pipeline

Orchestrates the complete IPUMS NHIS extract lifecycle:
1. Check cache for existing extract
2. Submit new extract if needed
3. Poll for completion
4. Download results
5. Register in cache

Critical for performance: Uses intelligent caching to avoid 30-45 minute waits.

Functions:
    submit_extract: Submit extract request to IPUMS API
    wait_for_extract: Poll extract status until complete
    download_extract: Download and save extract files
    get_or_submit_extract: Main orchestration with caching
"""

import time
import structlog
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
from ipumspy import MicrodataExtract, IpumsApiClient

# Import our modules
from python.nhis.auth import get_ipums_client
from python.nhis.extract_builder import build_extract, get_extract_info
from python.nhis.cache_manager import (
    generate_extract_signature,
    check_cache_exists,
    register_extract,
    load_cached_extract,
    CACHE_EXTRACTS_DIR
)

# Configure structured logging
log = structlog.get_logger()

# Default polling settings
DEFAULT_POLL_INTERVAL = 30  # seconds
DEFAULT_TIMEOUT = 7200  # 2 hours


def submit_extract(
    extract: MicrodataExtract,
    client: Optional[IpumsApiClient] = None
) -> str:
    """Submit extract request to IPUMS API.

    Args:
        extract: MicrodataExtract object from build_extract()
        client: IPUMS API client (will create one if None)

    Returns:
        str: Extract ID (e.g., "nhis:12345")

    Raises:
        Exception: If submission fails

    Example:
        >>> from python.nhis.extract_builder import build_extract
        >>> extract = build_extract(config)
        >>> extract_id = submit_extract(extract)
        >>> print(f"Extract submitted: {extract_id}")
    """
    log.info("Submitting extract to IPUMS API", description=extract.description)

    # Get client if not provided
    if client is None:
        log.debug("No client provided, initializing new client")
        client = get_ipums_client()

    try:
        # Submit extract
        log.debug("Calling IPUMS API submit_extract()")
        client.submit_extract(extract)

        # Get extract ID from response
        if hasattr(extract, 'extract_id') and extract.extract_id:
            extract_id = f"nhis:{extract.extract_id}"
        else:
            log.error("Extract submitted but no extract ID returned")
            raise ValueError("Extract submission succeeded but no extract ID returned")

        log.info(
            "Extract submitted successfully",
            extract_id=extract_id,
            description=extract.description
        )

        return extract_id

    except Exception as e:
        log.error(
            "Failed to submit extract",
            error=str(e),
            error_type=type(e).__name__,
            description=extract.description
        )
        raise Exception(
            f"Failed to submit IPUMS NHIS extract: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify API key is valid\n"
            f"  2. Check IPUMS API status: https://status.ipums.org/\n"
            f"  3. Verify extract configuration is valid\n"
            f"  4. Check network connectivity"
        ) from e


def wait_for_extract(
    extract_id: str,
    client: Optional[IpumsApiClient] = None,
    poll_interval: int = DEFAULT_POLL_INTERVAL,
    timeout: int = DEFAULT_TIMEOUT,
    verbose: bool = False
) -> bool:
    """Poll extract status until complete or timeout.

    Args:
        extract_id: Extract ID (e.g., "nhis:12345")
        client: IPUMS API client
        poll_interval: Seconds between status checks (default: 30)
        timeout: Maximum seconds to wait (default: 7200 = 2 hours)
        verbose: Print status updates to console

    Returns:
        bool: True if extract completed successfully

    Raises:
        TimeoutError: If extract doesn't complete within timeout
        Exception: If extract fails or API error
    """
    log.info(
        "Waiting for extract to complete",
        extract_id=extract_id,
        poll_interval=poll_interval,
        timeout=timeout
    )

    # Get client if not provided
    if client is None:
        log.debug("No client provided, initializing new client")
        client = get_ipums_client()

    # Parse extract number from ID
    try:
        collection, extract_number = extract_id.split(':')
        extract_number = int(extract_number)
    except ValueError:
        log.error("Invalid extract ID format", extract_id=extract_id)
        raise ValueError(f"Invalid extract ID format: {extract_id}. Expected 'nhis:12345'")

    start_time = time.time()
    elapsed = 0

    while elapsed < timeout:
        try:
            # Get extract status (match ACS pattern)
            # get_extract_info returns a DICTIONARY, not an object
            extract_info = client.get_extract_info(extract_number, collection=collection)

            # Extract info is a dict - get status from it
            status = extract_info.get('status', 'unknown').lower()

            log.debug(
                "Extract status check",
                extract_id=extract_id,
                status=status,
                elapsed=int(elapsed)
            )

            if verbose:
                print(f"[{int(elapsed)}s] Extract status: {status}")

            # Check status
            if status == "completed":
                log.info(
                    "Extract completed successfully",
                    extract_id=extract_id,
                    elapsed=int(elapsed)
                )
                return True

            elif status == "failed":
                log.error("Extract failed", extract_id=extract_id)
                raise Exception(f"Extract {extract_id} failed on IPUMS server")

            elif status in ["queued", "started", "produced", "downloading"]:
                # Still processing, wait and check again
                time.sleep(poll_interval)
                elapsed = time.time() - start_time

            else:
                log.warning("Unknown extract status", extract_id=extract_id, status=status)
                time.sleep(poll_interval)
                elapsed = time.time() - start_time

        except Exception as e:
            if "failed" in str(e).lower():
                raise
            log.error("Error checking extract status", extract_id=extract_id, error=str(e))
            raise

    # Timeout reached
    log.error("Extract processing timeout", extract_id=extract_id, timeout=timeout)
    raise TimeoutError(
        f"Extract {extract_id} did not complete within {timeout} seconds\n"
        f"Check extract status at: https://nhis.ipums.org/nhis/extract_status.shtml"
    )


def download_extract(
    extract_id: str,
    output_dir: Path,
    client: Optional[IpumsApiClient] = None
) -> Path:
    """Download completed extract files.

    Args:
        extract_id: Extract ID (e.g., "nhis:12345")
        output_dir: Directory to save files
        client: IPUMS API client

    Returns:
        Path: Path to downloaded data file

    Raises:
        Exception: If download fails
    """
    log.info("Downloading extract", extract_id=extract_id, output_dir=str(output_dir))

    # Get client if not provided
    if client is None:
        log.debug("No client provided, initializing new client")
        client = get_ipums_client()

    # Create output directory
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Parse extract ID
    try:
        collection, extract_number = extract_id.split(':')
        extract_number = int(extract_number)
    except ValueError:
        log.error("Invalid extract ID format", extract_id=extract_id)
        raise ValueError(f"Invalid extract ID format: {extract_id}")

    try:
        # Download extract (ipumspy handles all files)
        log.debug("Calling IPUMS API download_extract()")
        client.download_extract(extract_number, collection=collection, download_dir=str(output_dir))

        # Find the downloaded data file
        data_files = list(output_dir.glob("*.dat*")) + list(output_dir.glob("*.csv*"))

        if not data_files:
            log.error("No data files found after download", output_dir=str(output_dir))
            raise FileNotFoundError(f"No data files found in {output_dir}")

        # Use the first (should be only) data file
        data_file = data_files[0]

        log.info(
            "Extract downloaded successfully",
            extract_id=extract_id,
            data_file=str(data_file)
        )

        return data_file

    except Exception as e:
        log.error("Failed to download extract", extract_id=extract_id, error=str(e))
        raise Exception(
            f"Failed to download extract {extract_id}: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify extract completed successfully\n"
            f"  2. Check network connectivity\n"
            f"  3. Verify disk space available"
        ) from e


def get_or_submit_extract(
    config: Dict[str, Any],
    output_dir: Path,
    force_new: bool = False,
    verbose: bool = False
) -> Tuple[Path, bool]:
    """Main orchestration: Check cache, submit if needed, download.

    Args:
        config: Configuration dictionary
        output_dir: Directory for extract files
        force_new: Force new extract even if cached
        verbose: Print status updates

    Returns:
        Tuple[Path, bool]: (data_file_path, from_cache)
    """
    log.info("Starting extract workflow", output_dir=str(output_dir))

    # Generate extract signature for caching
    signature = generate_extract_signature(config)

    # Check cache unless force_new
    if not force_new:
        cached_extract = check_cache_exists(signature)
        if cached_extract:
            log.info("Found cached extract", signature=signature)
            # Copy cached files to output directory
            cache_info = load_cached_extract(signature, output_dir)
            return Path(cache_info['data_file']), True

    # Build and submit extract
    log.info("No cached extract, submitting new request")
    extract = build_extract(config)
    extract_id = submit_extract(extract)

    # Wait for completion
    wait_for_extract(extract_id, verbose=verbose)

    # Download files
    data_file = download_extract(extract_id, output_dir)

    # Register in cache (extract only JSON-serializable fields like ACS does)
    extract_info = get_extract_info(extract)

    # Create clean metadata dict with only serializable values
    metadata = {
        'collection': extract_info.get('collection'),
        'description': extract_info.get('description'),
        'data_format': extract_info.get('data_format'),
        'status': extract_info.get('status'),
        'download_links': extract_info.get('download_links'),
        'sample_count': len(extract_info.get('samples', [])),
        'samples': [s.name if hasattr(s, 'name') else str(s) for s in extract_info.get('samples', [])],
        'variable_count': len(extract_info.get('variables', [])),
        'variables': [v.name if hasattr(v, 'name') else str(v) for v in extract_info.get('variables', [])],
    }

    register_extract(signature, output_dir, extract_id, metadata)

    return data_file, False
