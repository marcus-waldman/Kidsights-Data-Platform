"""
Extract Caching System for NHIS Pipeline

Implements intelligent caching to avoid re-downloading identical IPUMS extracts.
Uses SHA256 signatures to identify identical extract requests and stores
metadata in a JSON registry.

Critical for performance: First extract ~30-45 min, cached retrieval ~10 sec

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
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

# Configure structured logging
log = structlog.get_logger()

# Default paths
CACHE_ROOT = Path("data/nhis/cache")
CACHE_EXTRACTS_DIR = CACHE_ROOT / "extracts"
REGISTRY_FILE = CACHE_ROOT / "registry.json"


def generate_extract_signature(config: Dict[str, Any]) -> str:
    """Generate unique SHA256 signature for extract configuration.

    Creates a reproducible hash from the extract parameters to identify
    identical requests. Two configs with same years, samples, and variables
    will produce the same signature.

    Args:
        config: Extract configuration dictionary

    Returns:
        str: SHA256 hex digest (64 characters)

    Example:
        >>> config1 = {'years': [2019, 2020, 2021], ...}
        >>> config2 = {'years': [2019, 2020, 2021], ...}
        >>> generate_extract_signature(config1) == generate_extract_signature(config2)
        True
    """
    log.debug("Generating extract signature")

    # Extract relevant fields for signature (order matters for reproducibility)
    signature_components = {
        'years': sorted(config.get('years', [])),  # Sort for consistency
        'samples': sorted(config.get('samples', [])),  # Sort for consistency
        'collection': config.get('collection', 'nhis'),
        'variables': {},  # Will populate below
    }

    # Process variables (NHIS variables are simpler, no attached characteristics)
    variables_dict = config.get('variables', {})
    for group, var_list in sorted(variables_dict.items()):
        signature_components['variables'][group] = sorted(var_list) if isinstance(var_list, list) else [var_list]

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
            "pipeline": "nhis",
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
            "pipeline": "nhis",
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
        Optional[str]: Cache directory if found, None if not in cache

    Example:
        >>> sig = generate_extract_signature(config)
        >>> cache_dir = check_cache_exists(sig)
        >>> if cache_dir:
        ...     print(f"Cache hit! Directory: {cache_dir}")
        ... else:
        ...     print("Cache miss, need to submit new extract")
    """
    log.debug("Checking cache", signature=extract_signature[:16] + "...")

    registry = _load_registry()

    for extract_entry in registry.get('extracts', []):
        if extract_entry.get('extract_signature') == extract_signature:
            cache_dir = extract_entry.get('cache_directory')
            # Verify cache directory still exists
            if cache_dir and Path(cache_dir).exists():
                log.info("Cache HIT", cache_dir=cache_dir, signature=extract_signature[:16] + "...")
                return cache_dir
            else:
                log.warning("Cache entry found but directory missing", cache_dir=cache_dir)
                return None

    log.info("Cache MISS", signature=extract_signature[:16] + "...")
    return None


def register_extract(
    extract_signature: str,
    cache_directory: Path,
    extract_id: str,
    metadata: Optional[Dict[str, Any]] = None
) -> bool:
    """Register completed extract in cache.

    Args:
        extract_signature: SHA256 signature from generate_extract_signature()
        cache_directory: Directory containing extract files
        extract_id: IPUMS extract ID (e.g., "nhis:12345")
        metadata: Optional additional metadata (timestamps, record count, etc.)

    Returns:
        bool: True if successfully registered

    Example:
        >>> sig = generate_extract_signature(config)
        >>> register_extract(sig, Path("data/nhis/cache/extracts/abc123"), "nhis:12345")
        True
    """
    log.info(
        "Registering extract in cache",
        extract_id=extract_id,
        cache_directory=str(cache_directory),
        signature=extract_signature[:16] + "..."
    )

    # Load registry
    registry = _load_registry()

    # Check if already registered
    for extract_entry in registry.get('extracts', []):
        if extract_entry.get('extract_signature') == extract_signature:
            log.info("Extract already registered, updating entry")
            extract_entry['extract_id'] = extract_id
            extract_entry['cache_directory'] = str(cache_directory)
            extract_entry['last_accessed'] = datetime.utcnow().isoformat() + "Z"
            if metadata:
                extract_entry['metadata'] = metadata
            _save_registry(registry)
            return True

    # Add new entry
    new_entry = {
        'extract_signature': extract_signature,
        'extract_id': extract_id,
        'cache_directory': str(cache_directory),
        'created_at': datetime.utcnow().isoformat() + "Z",
        'last_accessed': datetime.utcnow().isoformat() + "Z",
        'metadata': metadata or {}
    }

    registry['extracts'].append(new_entry)

    # Save updated registry
    _save_registry(registry)

    log.info("Extract registered successfully", extract_id=extract_id)
    return True


def load_cached_extract(
    extract_signature: str,
    destination: Path
) -> Dict[str, Any]:
    """Retrieve cached extract and copy to destination.

    Args:
        extract_signature: SHA256 signature
        destination: Directory to copy files to

    Returns:
        Dict with extract info including file paths

    Raises:
        FileNotFoundError: If cache not found or files missing
    """
    log.info("Loading cached extract", signature=extract_signature[:16] + "...")

    # Check cache exists
    cache_dir = check_cache_exists(extract_signature)
    if not cache_dir:
        raise FileNotFoundError(f"No cached extract found for signature {extract_signature[:16]}...")

    cache_path = Path(cache_dir)

    # Find data files
    data_files = list(cache_path.glob("*.dat*")) + list(cache_path.glob("*.csv*"))
    if not data_files:
        raise FileNotFoundError(f"No data files found in cache: {cache_path}")

    # Create destination directory
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)

    # Check if source and destination are the same (avoid self-copy)
    cache_path_resolved = cache_path.resolve()
    destination_resolved = destination.resolve()

    if cache_path_resolved == destination_resolved:
        log.debug("Cache already in destination, skipping copy", path=str(destination))
    else:
        # Copy all files from cache to destination
        log.debug("Copying cached files", source=str(cache_path), destination=str(destination))

        for file in cache_path.glob("*"):
            if file.is_file():
                dest_file = destination / file.name
                shutil.copy2(file, dest_file)
                log.debug("Copied file", file=file.name)

    # Update last_accessed in registry
    registry = _load_registry()
    for extract_entry in registry.get('extracts', []):
        if extract_entry.get('extract_signature') == extract_signature:
            extract_entry['last_accessed'] = datetime.utcnow().isoformat() + "Z"
            break

    _save_registry(registry)

    log.info("Cached extract loaded successfully", destination=str(destination))

    return {
        'cache_directory': str(cache_path),
        'destination': str(destination),
        'data_file': str(destination / data_files[0].name)
    }


def clear_old_caches(max_age_days: int = 90) -> int:
    """Remove cache entries older than threshold.

    Args:
        max_age_days: Maximum age in days (default: 90)

    Returns:
        int: Number of caches removed
    """
    log.info("Clearing old caches", max_age_days=max_age_days)

    registry = _load_registry()
    threshold = datetime.utcnow() - timedelta(days=max_age_days)

    removed_count = 0
    updated_extracts = []

    for extract_entry in registry.get('extracts', []):
        last_accessed_str = extract_entry.get('last_accessed', extract_entry.get('created_at'))
        last_accessed = datetime.fromisoformat(last_accessed_str.replace('Z', '+00:00'))

        if last_accessed < threshold:
            # Remove cache directory
            cache_dir = Path(extract_entry.get('cache_directory'))
            if cache_dir.exists():
                shutil.rmtree(cache_dir)
                log.info("Removed old cache", cache_dir=str(cache_dir))
            removed_count += 1
        else:
            # Keep this entry
            updated_extracts.append(extract_entry)

    # Update registry with remaining entries
    registry['extracts'] = updated_extracts
    _save_registry(registry)

    log.info("Old caches cleared", removed_count=removed_count)
    return removed_count
