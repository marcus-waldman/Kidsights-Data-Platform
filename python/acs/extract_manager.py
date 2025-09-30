"""
Extract Manager for ACS Pipeline

Orchestrates the complete IPUMS extract lifecycle:
1. Check cache for existing extract
2. Submit new extract if needed
3. Poll for completion
4. Download results
5. Register in cache

Critical for performance: Uses intelligent caching to avoid 15-60 minute waits.

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
from python.acs.auth import get_client
from python.acs.extract_builder import build_extract, get_extract_info
from python.acs.cache_manager import (
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
        str: Extract ID (e.g., "usa:12345")

    Raises:
        Exception: If submission fails

    Example:
        >>> from python.acs.extract_builder import build_extract
        >>> extract = build_extract(config)
        >>> extract_id = submit_extract(extract)
        >>> print(f"Extract submitted: {extract_id}")
    """
    log.info("Submitting extract to IPUMS API", description=extract.description)

    # Get client if not provided
    if client is None:
        log.debug("No client provided, initializing new client")
        client = get_client()

    try:
        # Submit extract
        log.debug("Calling IPUMS API submit_extract()")
        client.submit_extract(extract)

        # Get extract number from response
        # After submission, the extract object should have a 'number' attribute
        if hasattr(extract, 'number') and extract.number:
            extract_id = f"usa:{extract.number}"
        else:
            log.error("Extract submitted but no extract number returned")
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
            f"Failed to submit IPUMS extract: {e}\n\n"
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
    timeout: int = DEFAULT_TIMEOUT
) -> bool:
    """Poll extract status until complete or timeout.

    Args:
        extract_id: Extract ID (e.g., "usa:12345")
        client: IPUMS API client
        poll_interval: Seconds between status checks (default: 30)
        timeout: Maximum seconds to wait (default: 7200 = 2 hours)

    Returns:
        bool: True if extract completed successfully

    Raises:
        TimeoutError: If extract doesn't complete within timeout
        Exception: If extract fails or API error

    Example:
        >>> extract_id = submit_extract(extract)
        >>> wait_for_extract(extract_id)
        True
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
        client = get_client()

    # Parse extract number from ID
    try:
        extract_number = int(extract_id.split(":")[-1])
    except (ValueError, IndexError) as e:
        log.error("Invalid extract ID format", extract_id=extract_id)
        raise ValueError(f"Invalid extract ID format: {extract_id}. Expected 'usa:12345'") from e

    start_time = time.time()
    poll_count = 0

    while True:
        poll_count += 1
        elapsed = time.time() - start_time

        # Check timeout
        if elapsed > timeout:
            log.error(
                "Extract timeout",
                extract_id=extract_id,
                elapsed_seconds=int(elapsed),
                timeout_seconds=timeout
            )
            raise TimeoutError(
                f"Extract did not complete within {timeout} seconds\n"
                f"Extract ID: {extract_id}\n"
                f"Elapsed: {int(elapsed)} seconds\n\n"
                f"Try checking status manually at: https://usa.ipums.org/usa/\n"
                f"Or increase timeout parameter."
            )

        try:
            # Get extract status
            log.debug(
                "Polling extract status",
                extract_id=extract_id,
                poll_count=poll_count,
                elapsed_seconds=int(elapsed)
            )

            # Use client to get extract status
            extract_status = client.extract_status("usa", extract_number)

            status = extract_status.get('status', 'unknown').lower()

            log.info(
                "Extract status check",
                extract_id=extract_id,
                status=status,
                poll_count=poll_count,
                elapsed_seconds=int(elapsed)
            )

            # Check status
            if status == 'completed':
                log.info(
                    "Extract completed successfully",
                    extract_id=extract_id,
                    elapsed_seconds=int(elapsed),
                    polls=poll_count
                )
                return True

            elif status == 'failed':
                log.error("Extract failed", extract_id=extract_id, status_info=extract_status)
                raise Exception(
                    f"Extract failed on IPUMS servers\n"
                    f"Extract ID: {extract_id}\n"
                    f"Status: {extract_status}"
                )

            elif status in ['queued', 'started', 'produced', 'downloading_files', 'processing']:
                # Extract still processing, continue polling
                log.debug(
                    "Extract still processing",
                    extract_id=extract_id,
                    status=status
                )
                time.sleep(poll_interval)
                continue

            else:
                log.warning(
                    "Unknown extract status",
                    extract_id=extract_id,
                    status=status
                )
                # Continue polling for unknown statuses
                time.sleep(poll_interval)
                continue

        except Exception as e:
            log.error(
                "Error checking extract status",
                extract_id=extract_id,
                error=str(e),
                error_type=type(e).__name__
            )
            # Don't fail immediately on status check errors
            # Sleep and retry
            log.debug("Retrying after error", retry_in_seconds=poll_interval)
            time.sleep(poll_interval)
            continue


def download_extract(
    extract_id: str,
    client: Optional[IpumsApiClient] = None,
    output_dir: Optional[Path] = None
) -> Dict[str, str]:
    """Download completed extract files.

    Args:
        extract_id: Extract ID (e.g., "usa:12345")
        client: IPUMS API client
        output_dir: Directory to save files (default: data/acs/cache/extracts/<extract_id>/)

    Returns:
        Dict[str, str]: File paths {'raw_data': ..., 'ddi_codebook': ...}

    Raises:
        Exception: If download fails

    Example:
        >>> files = download_extract("usa:12345")
        >>> print(files['raw_data'])
        data/acs/cache/extracts/usa_12345/raw_data.csv
    """
    log.info("Downloading extract files", extract_id=extract_id)

    # Get client if not provided
    if client is None:
        log.debug("No client provided, initializing new client")
        client = get_client()

    # Parse extract number
    try:
        extract_number = int(extract_id.split(":")[-1])
    except (ValueError, IndexError) as e:
        log.error("Invalid extract ID format", extract_id=extract_id)
        raise ValueError(f"Invalid extract ID format: {extract_id}") from e

    # Create output directory
    if output_dir is None:
        # Default: data/acs/cache/extracts/usa_12345/
        extract_dir_name = extract_id.replace(":", "_")
        output_dir = CACHE_EXTRACTS_DIR / extract_dir_name

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    log.debug("Created output directory", path=str(output_dir))

    try:
        # Download extract
        log.debug("Downloading extract from IPUMS API")
        client.download_extract("usa", extract_number, download_dir=str(output_dir))

        # Find downloaded files
        # IPUMS typically provides: data file (.csv or .dat) and codebook (.xml)
        data_files = list(output_dir.glob("*.csv")) + list(output_dir.glob("*.dat"))
        codebook_files = list(output_dir.glob("*.xml"))

        if not data_files:
            log.error("No data file found after download", directory=str(output_dir))
            raise FileNotFoundError(
                f"No data file (.csv or .dat) found in {output_dir}\n"
                f"Download may have failed."
            )

        # Use first matches
        raw_data_file = str(data_files[0])
        ddi_codebook_file = str(codebook_files[0]) if codebook_files else None

        file_paths = {
            'raw_data': raw_data_file,
        }

        if ddi_codebook_file:
            file_paths['ddi_codebook'] = ddi_codebook_file

        log.info(
            "Extract downloaded successfully",
            extract_id=extract_id,
            files=list(file_paths.keys()),
            directory=str(output_dir)
        )

        return file_paths

    except Exception as e:
        log.error(
            "Failed to download extract",
            extract_id=extract_id,
            error=str(e),
            error_type=type(e).__name__
        )
        raise Exception(
            f"Failed to download IPUMS extract: {e}\n"
            f"Extract ID: {extract_id}\n"
            f"Output directory: {output_dir}"
        ) from e


def get_or_submit_extract(
    config: Dict[str, Any],
    force_refresh: bool = False,
    client: Optional[IpumsApiClient] = None
) -> Tuple[str, Dict[str, str], bool]:
    """Main orchestration function: check cache, submit if needed, download.

    This is the primary function for the ACS pipeline. It implements intelligent
    caching to minimize API calls and wait times.

    Workflow:
    1. Generate extract signature from config
    2. Check cache registry
    3. If cache HIT: return cached file paths (fast: ~10 sec)
    4. If cache MISS or force_refresh:
       a. Build extract request
       b. Submit to IPUMS API
       c. Wait for completion (slow: 15-60 min)
       d. Download files
       e. Register in cache
       f. Return file paths

    Args:
        config: Validated configuration dictionary
        force_refresh: If True, bypass cache and submit new extract
        client: IPUMS API client (optional)

    Returns:
        Tuple[str, Dict[str, str], bool]:
            - extract_id: Extract ID (e.g., "usa:12345")
            - file_paths: Dict with 'raw_data', 'ddi_codebook' keys
            - from_cache: True if retrieved from cache, False if newly submitted

    Example:
        >>> from python.acs.config_manager import get_state_config
        >>> config = get_state_config("nebraska", "2019-2023")
        >>> extract_id, files, cached = get_or_submit_extract(config)
        >>> if cached:
        ...     print(f"Cache hit! Retrieved in ~10 seconds")
        ... else:
        ...     print(f"Cache miss. Waited 45 minutes for new extract")
        >>> print(files['raw_data'])
    """
    log.info(
        "Starting extract retrieval",
        state=config.get('state'),
        year_range=config.get('year_range'),
        force_refresh=force_refresh
    )

    # Generate extract signature
    extract_signature = generate_extract_signature(config)
    log.debug("Generated extract signature", signature=extract_signature[:16] + "...")

    # Check cache (unless force_refresh)
    if not force_refresh:
        cached_extract_id = check_cache_exists(extract_signature)

        if cached_extract_id:
            log.info(
                "Cache HIT - retrieving cached extract",
                extract_id=cached_extract_id,
                signature=extract_signature[:16] + "..."
            )

            try:
                file_paths = load_cached_extract(cached_extract_id, validate=True)

                log.info(
                    "Cached extract retrieved successfully",
                    extract_id=cached_extract_id,
                    files=list(file_paths.keys())
                )

                return cached_extract_id, file_paths, True

            except (ValueError, FileNotFoundError) as e:
                log.warning(
                    "Cache validation failed, will submit new extract",
                    extract_id=cached_extract_id,
                    error=str(e)
                )
                # Fall through to submit new extract

    # Cache MISS or force_refresh or cache validation failed
    log.info(
        "Cache MISS - submitting new extract",
        signature=extract_signature[:16] + "...",
        force_refresh=force_refresh
    )

    # Build extract
    extract = build_extract(config)
    extract_info = get_extract_info(extract)

    # Submit extract
    extract_id = submit_extract(extract, client=client)

    # Wait for completion
    log.info("Waiting for extract to complete (this may take 15-60 minutes)")
    wait_for_extract(extract_id, client=client)

    # Download files
    file_paths = download_extract(extract_id, client=client)

    # Register in cache
    log.info("Registering extract in cache", extract_id=extract_id)

    metadata = {
        'description': extract_info.get('description'),
        'variable_count': extract_info.get('variable_count'),
        'variables': extract_info.get('variables'),
        'case_selections': extract_info.get('case_selections'),
    }

    register_extract(
        extract_signature=extract_signature,
        extract_id=extract_id,
        config=config,
        file_paths=file_paths,
        metadata=metadata
    )

    log.info(
        "Extract retrieval complete",
        extract_id=extract_id,
        from_cache=False,
        files=list(file_paths.keys())
    )

    return extract_id, file_paths, False
