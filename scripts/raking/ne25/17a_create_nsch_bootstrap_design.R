# Phase 4, Task 4.1a: Create Shared NSCH Bootstrap Design
# Generate ONE bootstrap design for all 4 NSCH estimands
# This design will be used by 18_estimate_nsch_outcomes.R and 20_estimate_childcare_2022.R

library(survey)
library(svrep)
library(dplyr)
library(mice)
library(future)
library(parallel)

cat("\n========================================\n")
cat("Create Shared NSCH Bootstrap Design\n")
cat("========================================\n\n")

# Load bootstrap configuration from centralized config
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot

cat("[CONFIG] Bootstrap replicates:", n_boot, "\n")
cat("         Mode:", get_bootstrap_mode(), "\n\n")

# ========================================
# SECTION 1: DATA LOADING (Multi-Year)
# ========================================
cat("[1] Loading multi-year NSCH data (2020-2023)...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Load Nebraska children ages 0-5 from all four years
nsch_ne_multi <- DBI::dbGetQuery(con, "
  SELECT
    2020 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10,
    NULL as ACE11,
    MEDB10ScrQ5_20 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2020_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2021 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_21 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2021_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2022 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_22 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2022_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2023 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_23 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2023_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total records:", nrow(nsch_ne_multi), "\n")
cat("    Years:", paste(sort(unique(nsch_ne_multi$survey_year)), collapse = ", "), "\n")
cat("    Sample sizes by year:\n")
for (yr in 2020:2023) {
  n <- sum(nsch_ne_multi$survey_year == yr)
  cat("      ", yr, ":", n, "\n")
}
cat("\n")

# ========================================
# SECTION 2: PREPARE ACE BINARY VARIABLES FOR MICE
# ========================================
cat("[2] Preparing ACE binary variables for MICE imputation...\n")

# Recode ACE items to binary (1=Yes, 2=No, 95/96/99=NA)
nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(
    ACE1_binary = dplyr::case_when(ACE1 == 1 ~ 1, ACE1 == 2 ~ 0, TRUE ~ NA_real_),
    ACE3_binary = dplyr::case_when(ACE3 == 1 ~ 1, ACE3 == 2 ~ 0, TRUE ~ NA_real_),
    ACE4_binary = dplyr::case_when(ACE4 == 1 ~ 1, ACE4 == 2 ~ 0, TRUE ~ NA_real_),
    ACE5_binary = dplyr::case_when(ACE5 == 1 ~ 1, ACE5 == 2 ~ 0, TRUE ~ NA_real_),
    ACE6_binary = dplyr::case_when(ACE6 == 1 ~ 1, ACE6 == 2 ~ 0, TRUE ~ NA_real_),
    ACE7_binary = dplyr::case_when(ACE7 == 1 ~ 1, ACE7 == 2 ~ 0, TRUE ~ NA_real_),
    ACE8_binary = dplyr::case_when(ACE8 == 1 ~ 1, ACE8 == 2 ~ 0, TRUE ~ NA_real_),
    ACE9_binary = dplyr::case_when(ACE9 == 1 ~ 1, ACE9 == 2 ~ 0, TRUE ~ NA_real_),
    ACE10_binary = dplyr::case_when(ACE10 == 1 ~ 1, ACE10 == 2 ~ 0, TRUE ~ NA_real_),
    ACE11_binary = dplyr::case_when(ACE11 == 1 ~ 1, ACE11 == 2 ~ 0, TRUE ~ NA_real_)
  )

cat("    ACE binary variables created\n\n")

# ========================================
# SECTION 3: MICE SINGLE IMPUTATION
# ========================================
cat("[3] Running MICE single imputation for ACE variables...\n")

# Setup parallel processing
n_cores <- parallel::detectCores()
n_workers <- floor(n_cores / 2)
cat("    System cores:", n_cores, "\n")
cat("    Workers allocated:", n_workers, "\n\n")

future::plan(future::multisession, workers = n_workers)

# Prepare data for MICE
mice_data <- nsch_ne_multi %>%
  dplyr::select(
    ACE1_binary, ACE3_binary, ACE4_binary, ACE5_binary, ACE6_binary,
    ACE7_binary, ACE8_binary, ACE9_binary, ACE10_binary, ACE11_binary,
    SC_AGE_YEARS, survey_year, SC_SEX, SC_RACE_R, SC_HISPANIC_R
  )

# Run MICE with single imputation (m=1)
set.seed(2025)
imp_result <- mice::mice(
  data = mice_data,
  method = "cart",
  m = 1,
  maxit = 10,
  printFlag = FALSE  # Suppress verbose output
)

cat("    MICE imputation complete\n")

# Extract completed dataset
mice_complete <- mice::complete(imp_result, 1)

# Replace ACE binary variables in main dataset
ace_vars <- c("ACE1_binary", "ACE3_binary", "ACE4_binary", "ACE5_binary",
              "ACE6_binary", "ACE7_binary", "ACE8_binary", "ACE9_binary",
              "ACE10_binary", "ACE11_binary")

for (var in ace_vars) {
  nsch_ne_multi[[var]] <- mice_complete[[var]]
}

# Close parallel workers
future::plan(future::sequential)

cat("    ACE variables now complete (no missing values)\n\n")

# ========================================
# SECTION 4: SURVEY DESIGN CREATION
# ========================================
cat("[4] Creating base NSCH survey design...\n")

# Create composite stratum (FIPSST × STRATUM)
nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(composite_stratum = paste0(FIPSST, "_", STRATUM))

cat("    Number of composite strata:", length(unique(nsch_ne_multi$composite_stratum)), "\n")
cat("    Number of clusters (HHID):", length(unique(nsch_ne_multi$HHID)), "\n\n")

# Create survey design object
nsch_design <- survey::svydesign(
  ids = ~HHID,                    # Household clustering
  strata = ~composite_stratum,     # State × household type strata
  weights = ~FWC,                  # Survey weights
  data = nsch_ne_multi,
  nest = TRUE                      # Nested design
)

cat("    Survey design created successfully\n")
cat("    Sample size:", nrow(nsch_design), "\n\n")

# ========================================
# SECTION 5: GENERATE BOOTSTRAP DESIGN
# ========================================
cat("[5] Generating bootstrap replicate weights...\n")
cat("    Method: Rao-Wu-Yue-Beaumont\n")
cat("    Number of replicates:", n_boot, "\n\n")

# Create bootstrap design with replicate weights
boot_design <- svrep::as_bootstrap_design(
  design = nsch_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = n_boot
)

cat("    Bootstrap design created successfully\n")
cat("    Replicate weights matrix:", nrow(boot_design$repweights), "observations x",
    ncol(boot_design$repweights), "replicates\n\n")

# ========================================
# SECTION 6: VERIFY BOOTSTRAP DESIGN
# ========================================
cat("[6] Verifying bootstrap design structure...\n")

# Check that repweights matrix exists and has correct dimensions
if (!is.null(boot_design$repweights)) {
  cat("    [OK] Replicate weights matrix exists\n")

  if (ncol(boot_design$repweights) == n_boot) {
    cat("    [OK] Correct number of replicates (", n_boot, ")\n", sep = "")
  } else {
    stop("ERROR: Expected ", n_boot, " replicates, got ", ncol(boot_design$repweights))
  }

  if (nrow(boot_design$repweights) == nrow(nsch_ne_multi)) {
    cat("    [OK] Replicate weights match sample size (", nrow(nsch_ne_multi), " rows)\n", sep = "")
  } else {
    stop("ERROR: Replicate weights have ", nrow(boot_design$repweights),
         " rows, expected ", nrow(nsch_ne_multi))
  }
} else {
  stop("ERROR: Replicate weights matrix not found in bootstrap design")
}

# Check for missing values
n_missing <- sum(is.na(boot_design$repweights))
if (n_missing == 0) {
  cat("    [OK] No missing values in replicate weights\n")
} else {
  cat("    [WARN] Found", n_missing, "missing values in replicate weights\n")
}

cat("\n")

# ========================================
# SECTION 7: SAVE BOOTSTRAP DESIGN
# ========================================
cat("[7] Saving NSCH bootstrap design...\n")

saveRDS(boot_design, "data/raking/ne25/nsch_bootstrap_design.rds")

# Get file size
file_info <- file.info("data/raking/ne25/nsch_bootstrap_design.rds")
file_size_mb <- round(file_info$size / 1024^2, 2)

cat("    Saved to: data/raking/ne25/nsch_bootstrap_design.rds\n")
cat("    File size:", file_size_mb, "MB\n")
cat("    Dimensions:", nrow(boot_design$repweights), "observations x",
    ncol(boot_design$repweights), "replicates\n\n")

cat("========================================\n")
cat("NSCH Bootstrap Design Creation Complete\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Sample size:", nrow(nsch_ne_multi), "children (pooled 2020-2023)\n")
cat("  - Bootstrap method: Rao-Wu-Yue-Beaumont\n")
cat("  - Number of replicates:", n_boot, "\n")
cat("  - File size:", file_size_mb, "MB\n")
cat("  - MICE imputation: ACE variables complete (m=1)\n")
cat("  - Shared design ready for use in 18_estimate_nsch_outcomes.R and 20_estimate_childcare_2022.R\n\n")

if (n_boot < 100) {
  cat("NOTE: Running in TEST MODE with", n_boot, "replicates\n")
  cat("      For production, change n_boot to 4096 and re-run\n\n")
}

# Return design for inspection
boot_design
