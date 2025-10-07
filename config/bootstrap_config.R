# Bootstrap Replicate Configuration for NE25 Raking Targets
# Single source of truth for n_boot across all pipelines
# Created: January 2025
# Purpose: Centralize bootstrap configuration to avoid inconsistencies

# =============================================================================
# BOOTSTRAP CONFIGURATION
# =============================================================================

BOOTSTRAP_CONFIG <- list(
  # Number of bootstrap replicates
  # Production: 4096 (stable variance, precise CI)
  # Testing: 96 (fast iteration, ~2 minutes)
  # Development: 8 (very fast prototyping, <30 seconds)
  n_boot = 96,  # ← CHANGE THIS to 96 for testing or 8 for development

  # Bootstrap method (Rao-Wu-Yue-Beaumont preserves complex survey design)
  method = "Rao-Wu-Yue-Beaumont",

  # Parallel processing
  parallel_workers = 16,  # Half of 32 logical processors

  # Memory settings (for future.globals.maxSize)
  max_globals_gb = 128,

  # Paths (relative to project root)
  data_dir = "data/raking/ne25",

  # Mode detection functions
  is_production = function() {
    BOOTSTRAP_CONFIG$n_boot >= 4096
  },

  is_testing = function() {
    BOOTSTRAP_CONFIG$n_boot >= 50 && BOOTSTRAP_CONFIG$n_boot < 1000
  },

  is_development = function() {
    BOOTSTRAP_CONFIG$n_boot < 50
  }
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Get current bootstrap mode
#'
#' @return Character string: "PRODUCTION", "TESTING", or "DEVELOPMENT"
get_bootstrap_mode <- function() {
  if (BOOTSTRAP_CONFIG$is_production()) {
    return("PRODUCTION")
  } else if (BOOTSTRAP_CONFIG$is_testing()) {
    return("TESTING")
  } else {
    return("DEVELOPMENT")
  }
}

#' Get expected total bootstrap replicates across all data sources
#'
#' @return Named list with expected replicate counts
get_expected_replicates <- function() {
  n <- BOOTSTRAP_CONFIG$n_boot
  list(
    acs = 25 * 6 * n,      # 25 estimands × 6 ages × n_boot
    nhis = 1 * 6 * n,      # 1 estimand × 6 ages × n_boot
    nsch = 4 * 6 * n,      # 4 estimands × 6 ages × n_boot
    total = 30 * 6 * n     # 30 total estimands × 6 ages × n_boot
  )
}

#' Print configuration summary
print_bootstrap_config <- function() {
  mode <- get_bootstrap_mode()
  expected <- get_expected_replicates()

  cat("\n========================================\n")
  cat("Bootstrap Configuration\n")
  cat("========================================\n")
  cat("Mode:", mode, "\n")
  cat("n_boot:", BOOTSTRAP_CONFIG$n_boot, "\n")
  cat("Method:", BOOTSTRAP_CONFIG$method, "\n")
  cat("Workers:", BOOTSTRAP_CONFIG$parallel_workers, "\n")
  cat("\n")
  cat("Expected total replicates:\n")
  cat("  ACS:", format(expected$acs, big.mark = ","), "\n")
  cat("  NHIS:", format(expected$nhis, big.mark = ","), "\n")
  cat("  NSCH:", format(expected$nsch, big.mark = ","), "\n")
  cat("  TOTAL:", format(expected$total, big.mark = ","), "\n")
  cat("========================================\n\n")

  # Warning for development mode
  if (BOOTSTRAP_CONFIG$is_development()) {
    cat("[WARNING] Running in DEVELOPMENT mode (n_boot < 50)\n")
    cat("          Results are for prototyping only, NOT for inference\n\n")
  } else if (BOOTSTRAP_CONFIG$is_testing()) {
    cat("[INFO] Running in TESTING mode (50 <= n_boot < 1000)\n")
    cat("       Sufficient for validation, but not production precision\n\n")
  } else {
    cat("[PRODUCTION] n_boot >= 4096 for stable variance estimation\n\n")
  }
}

# =============================================================================
# AUTO-PRINT ON SOURCE
# =============================================================================

# Automatically print configuration when this file is sourced
print_bootstrap_config()
