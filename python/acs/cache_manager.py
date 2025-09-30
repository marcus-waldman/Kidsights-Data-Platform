"""
Extract Caching System for ACS Pipeline

Implements intelligent caching to avoid re-downloading identical IPUMS extracts.
Uses SHA256 signatures to identify identical extract requests and stores
metadata in a JSON registry.

Critical for performance: First extract ~45 min, cached retrieval ~10 sec

Functions:
    generate_extract_signature: Create SHA256 hash from extract config
    check_cache_exists: Look up extract in cache registry
    register_extract: Add completed extract to cache
    load_cached_extract: Retrieve cached extract with validation
    invalidate_cache: Remove extract from cache
    clear_old_caches: Remove caches older than threshold
"""

import json
import hashlib
import structlog
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
from datetime import datetime, timedelta

# Configure structured logging
log = structlog.get_logger()

# Default paths
CACHE_ROOT = Path("data/acs/cache")
CACHE_EXTRACTS_DIR = CACHE_ROOT / "extracts"
REGISTRY_FILE = CACHE_ROOT / "registry.json"


def generate_extract_signature(config: Dict[str, Any]) -> str:
    """Generate unique SHA256 signature for extract configuration.

    Creates a reproducible hash from the extract parameters to identify
    identical requests. Two configs with same state, year, variables, and
    filters will produce the same signature.

    Args:
        config: Extract configuration dictionary

    Returns:
        str: SHA256 hex digest (64 characters)

    Example:
        >>> config1 = {'state': 'nebraska', 'year_range': '2019-2023', ...}
        >>> config2 = {'state': 'nebraska', 'year_range': '2019-2023', ...}
        >>> generate_extract_signature(config1) == generate_extract_signature(config2)
        True
    """
    log.debug("Generating extract signature")

    # Extract relevant fields for signature (order matters for reproducibility)
    signature_components = {
        'state': config.get('state'),
        'state_fip': config.get('state_fip'),
        'year_range': config.get('year_range'),
        'acs_sample': config.get('acs_sample'),
        'collection': config.get('collection', 'usa'),
        'filters': config.get('filters', {}),
        'case_selections': config.get('case_selections', {}),
        'variables': {},  # Will populate below
    }

    # Process variables to include attached characteristics
    variables_dict = config.get('variables', {})
    for group, var_list in variables_dict.items():
        signature_components['variables'][group] = []
        for var in var_list:
            if isinstance(var, str):
                signature_components['variables'][group].append(var)
            elif isinstance(var, dict):
                # Include attached characteristics in signature
                var_sig = {
                    'name': var.get('name'),
                    'attach': var.get('attach_characteristics', [])
                }
                signature_components['variables'][group].append(var_sig)

    # Convert to JSON string (sorted keys for reproducibility)
    json_str = json.dumps(signature_components, sort_keys=True)

    # Generate SHA256 hash
    signature = hashlib.sha256(json_str.encode('utf-8')).hexdigest()

    log.debug("Extract signature generated", signature=signature[:16] + "...")
    return signature


def _load_registry() -> Dict[str, Any]:
    """Load cache registry from JSON file.

    Returns:
        Dict: Registry data, or empty registry if file doesn't exist
    """
    if not REGISTRY_FILE.exists():
        log.debug("Registry file does not exist, returning empty registry")
        return {
            "version": "1.0",
            "last_updated": datetime.utcnow().isoformat() + "Z",
            "extracts": []
        }

    try:
        with open(REGISTRY_FILE, 'r', encoding='utf-8') as f:
            registry = json.load(f)
        log.debug("Registry loaded", extract_count=len(registry.get('extracts', [])))
        return registry
    except (json.JSONDecodeError, IOError) as e:
        log.error("Failed to load registry", error=str(e))
        # Return empty registry on error (don't crash pipeline)
        return {
            "version": "1.0",
            "last_updated": datetime.utcnow().isoformat() + "Z",
            "extracts": []
        }


def _save_registry(registry: Dict[str, Any]):
    """Save cache registry to JSON file.

    Args:
        registry: Registry data to save
    """
    # Ensure cache directory exists
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)

    # Update last_updated timestamp
    registry['last_updated'] = datetime.utcnow().isoformat() + "Z"

    try:
        # Atomic write: write to temp file, then rename
        temp_file = REGISTRY_FILE.with_suffix('.tmp')
        with open(temp_file, 'w', encoding='utf-8') as f:
            json.dump(registry, f, indent=2)

        # Rename (atomic on most filesystems)
        temp_file.replace(REGISTRY_FILE)

        log.debug("Registry saved", extract_count=len(registry.get('extracts', [])))

    except IOError as e:
        log.error("Failed to save registry", error=str(e))
        raise IOError(f"Failed to save cache registry: {e}") from e


def check_cache_exists(extract_signature: str) -> Optional[str]:
    """Check if extract exists in cache registry.

    Args:
        extract_signature: SHA256 signature from generate_extract_signature()

    Returns:
        Optional[str]: Extract ID if cached, None if not found

    Example:
        >>> sig = generate_extract_signature(config)
        >>> extract_id = check_cache_exists(sig)
        >>> if extract_id:
        ...     print(f"Cache hit! Extract: {extract_id}")
        ... else:
        ...     print("Cache miss, need to submit new extract")
    """
    log.debug("Checking cache", signature=extract_signature[:16] + "...")

    registry = _load_registry()

    for extract_entry in registry.get('extracts', []):
        if extract_entry.get('extract_signature') == extract_signature:
            extract_id = extract_entry.get('extract_id')
            log.info("Cache HIT", extract_id=extract_id, signature=extract_signature[:16] + "...")
            return extract_id

    log.info("Cache MISS", signature=extract_signature[:16] + "...")
    return None


def register_extract(
    extract_signature: str,
    extract_id: str,
    config: Dict[str, Any],
    file_paths: Dict[str, str],
    metadata: Optional[Dict[str, Any]] = None
) -> bool:
    """Register completed extract in cache.

    Args:
        extract_signature: SHA256 signature from generate_extract_signature()
        extract_id: IPUMS extract ID (e.g., "usa:12345")
        config: Original configuration used for extract
        file_paths: Dict with keys 'raw_data', 'ddi_codebook', etc.
        metadata: Optional additional metadata (timestamps, record count, etc.)

    Returns:
        bool: True if successfully registered

    Example:
        >>> sig = generate_extract_signature(config)
        >>> files = {
        ...     'raw_data': 'data/acs/cache/extracts/usa_12345/raw_data.csv',
        ...     'ddi_codebook': 'data/acs/cache/extracts/usa_12345/ddi.xml'
        ... }
        >>> register_extract(sig, "usa:12345", config, files)
        True
    """
    log.info("Registering extract in cache", extract_id=extract_id)

    registry = _load_registry()

    # Check if already registered
    for entry in registry.get('extracts', []):
        if entry.get('extract_id') == extract_id:
            log.warning("Extract already registered", extract_id=extract_id)
            return True

    # Build registry entry
    entry = {
        'extract_signature': extract_signature,
        'extract_id': extract_id,
        'state': config.get('state'),
        'state_fip': config.get('state_fip'),
        'year_range': config.get('year_range'),
        'acs_sample': config.get('acs_sample'),
        'registration_timestamp': datetime.utcnow().isoformat() + "Z",
        'files': file_paths,
    }

    # Add optional metadata
    if metadata:
        entry.update(metadata)

    # Add to registry
    registry.setdefault('extracts', []).append(entry)

    # Save registry
    _save_registry(registry)

    log.info("Extract registered successfully", extract_id=extract_id)
    return True


def load_cached_extract(extract_id: str, validate: bool = True) -> Dict[str, str]:
    """Load cached extract file paths with optional validation.

    Args:
        extract_id: IPUMS extract ID
        validate: If True, verify files exist (default: True)

    Returns:
        Dict[str, str]: File paths {'raw_data': ..., 'ddi_codebook': ...}

    Raises:
        ValueError: If extract not in cache
        FileNotFoundError: If cached files don't exist (when validate=True)

    Example:
        >>> files = load_cached_extract("usa:12345")
        >>> print(files['raw_data'])
        data/acs/cache/extracts/usa_12345/raw_data.csv
    """
    log.info("Loading cached extract", extract_id=extract_id)

    registry = _load_registry()

    # Find extract entry
    extract_entry = None
    for entry in registry.get('extracts', []):
        if entry.get('extract_id') == extract_id:
            extract_entry = entry
            break

    if not extract_entry:
        log.error("Extract not found in cache", extract_id=extract_id)
        raise ValueError(f"Extract not in cache: {extract_id}")

    # Get file paths
    file_paths = extract_entry.get('files', {})

    if not file_paths:
        log.error("No file paths in cache entry", extract_id=extract_id)
        raise ValueError(f"Cache entry has no file paths: {extract_id}")

    # Validate files exist if requested
    if validate:
        for file_key, file_path in file_paths.items():
            if not Path(file_path).exists():
                log.error("Cached file not found", file=file_path, extract_id=extract_id)
                raise FileNotFoundError(
                    f"Cached file not found: {file_path}\n"
                    f"Extract: {extract_id}\n"
                    f"Cache may be corrupted. Try --force-refresh."
                )

    log.info("Cached extract loaded", extract_id=extract_id, files=list(file_paths.keys()))
    return file_paths


def invalidate_cache(extract_id: str, delete_files: bool = False) -> bool:
    """Remove extract from cache registry.

    Args:
        extract_id: IPUMS extract ID to invalidate
        delete_files: If True, also delete cached files from disk

    Returns:
        bool: True if successfully invalidated

    Example:
        >>> invalidate_cache("usa:12345", delete_files=True)
        True
    """
    log.info("Invalidating cache", extract_id=extract_id, delete_files=delete_files)

    registry = _load_registry()

    # Find and remove entry
    extracts = registry.get('extracts', [])
    initial_count = len(extracts)

    file_paths = None
    registry['extracts'] = [
        entry for entry in extracts
        if entry.get('extract_id') != extract_id
    ]

    if len(registry['extracts']) == initial_count:
        log.warning("Extract not found in cache", extract_id=extract_id)
        return False

    # Get file paths before removing entry
    for entry in extracts:
        if entry.get('extract_id') == extract_id:
            file_paths = entry.get('files', {})
            break

    # Save updated registry
    _save_registry(registry)

    # Delete files if requested
    if delete_files and file_paths:
        for file_path in file_paths.values():
            try:
                Path(file_path).unlink(missing_ok=True)
                log.debug("Deleted cached file", file=file_path)
            except OSError as e:
                log.warning("Failed to delete cached file", file=file_path, error=str(e))

    log.info("Cache invalidated", extract_id=extract_id)
    return True


def clear_old_caches(days: int = 365, dry_run: bool = False) -> int:
    """Remove cache entries older than threshold.

    Args:
        days: Remove caches older than this many days
        dry_run: If True, report what would be deleted without deleting

    Returns:
        int: Number of caches removed

    Example:
        >>> # Remove caches older than 1 year
        >>> count = clear_old_caches(days=365)
        >>> print(f"Removed {count} old caches")
    """
    log.info("Clearing old caches", days=days, dry_run=dry_run)

    registry = _load_registry()
    threshold = datetime.utcnow() - timedelta(days=days)

    extracts = registry.get('extracts', [])
    removed_count = 0

    new_extracts = []
    for entry in extracts:
        # Parse timestamp
        timestamp_str = entry.get('registration_timestamp', '')
        try:
            # Handle Z suffix
            if timestamp_str.endswith('Z'):
                timestamp_str = timestamp_str[:-1]
            entry_date = datetime.fromisoformat(timestamp_str)

            if entry_date < threshold:
                extract_id = entry.get('extract_id')
                if dry_run:
                    log.info("Would remove old cache", extract_id=extract_id, age_days=(datetime.utcnow() - entry_date).days)
                else:
                    log.info("Removing old cache", extract_id=extract_id, age_days=(datetime.utcnow() - entry_date).days)
                    # Delete files
                    for file_path in entry.get('files', {}).values():
                        Path(file_path).unlink(missing_ok=True)

                removed_count += 1
            else:
                new_extracts.append(entry)

        except (ValueError, KeyError) as e:
            log.warning("Failed to parse timestamp, keeping entry", error=str(e))
            new_extracts.append(entry)

    if not dry_run:
        registry['extracts'] = new_extracts
        _save_registry(registry)

    log.info("Cache cleanup complete", removed=removed_count, dry_run=dry_run)
    return removed_count
