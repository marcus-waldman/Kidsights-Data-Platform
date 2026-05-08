# ==============================================================================
# MN26 Pipeline Entry Point
# ==============================================================================
# Usage:
#   "C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_mn26_pipeline.R
#
# Or with custom credentials:
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_mn26_pipeline.R --credentials "C:/my_auths/mn26.csv"
#
# Or skip database (test mode):
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_mn26_pipeline.R --skip-database
#
# Override the NORC P_SUID crosswalk path (defaults to analytic_sample.id_xwalk_path
# in config/sources/mn26.yaml):
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_mn26_pipeline.R --id-xwalk "C:/path/to/id_xwalk.rds"
# ==============================================================================

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
credentials_path <- NULL
skip_database <- FALSE
id_xwalk_path <- NULL

if ("--skip-database" %in% args) {
  skip_database <- TRUE
}

cred_idx <- which(args == "--credentials")
if (length(cred_idx) > 0 && cred_idx < length(args)) {
  credentials_path <- args[cred_idx + 1]
}

xwalk_idx <- which(args == "--id-xwalk")
if (length(xwalk_idx) > 0 && xwalk_idx < length(args)) {
  id_xwalk_path <- args[xwalk_idx + 1]
}

# Source pipeline orchestrator
source("pipelines/orchestration/mn26_pipeline.R")

# Run pipeline
result <- run_mn26_pipeline(
  config_path      = "config/sources/mn26.yaml",
  credentials_path = credentials_path,
  skip_database    = skip_database,
  id_xwalk_path    = id_xwalk_path
)

# Exit with appropriate code
if (!is.null(result$metrics$error)) {
  quit(status = 1)
}
