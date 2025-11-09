# Child ACEs Stage: Impute 8 Child ACE Items + Derive Total for NE25
#
# Generates M=5 imputations for child ACE (Adverse Childhood Experiences) items
# using random forest method. Derives child_ace_total (0-8 scale) after imputation.
# Uses chained imputation approach where each mice run uses geography + sociodem
# + mental health from imputation m as fixed auxiliary variables.
#
# Usage:
#   Rscript scripts/imputation/ne25/06_impute_child_aces.R
#
# Variables Imputed (8 total):
#   - child_ace_parent_divorce (cqr017) - Parent divorced/separated (0/1)
#   - child_ace_parent_death (cqr018) - Parent died (0/1)
#   - child_ace_parent_jail (cqr019) - Parent served time in jail (0/1)
#   - child_ace_domestic_violence (cqr020) - Saw/heard domestic violence (0/1)
#   - child_ace_neighborhood_violence (cqr021) - Victim/witness neighborhood violence (0/1)
#   - child_ace_mental_illness (cqr022) - Lived with mentally ill person (0/1)
#   - child_ace_substance_use (cqr023) - Lived with substance abuser (0/1)
#   - child_ace_discrimination (cqr024) - Treated unfairly due to race (0/1)
#
# Derived Variables (1 total, computed after imputation):
#   - child_ace_total - Sum of 8 ACE items (0-8 scale)
#
# Auxiliary Variables (11 total):
#   - puma (from geography imputation m)
#   - raceG, educ_mom, income, family_size, fplcat (from sociodem imputation m if imputed, else base)
#   - phq2_positive, gad2_positive (from mental health imputation m if imputed, else base)
#   - authentic.x, age_in_days, female (from base data)

# =============================================================================
# SETUP
# =============================================================================

cat("Child ACEs: Impute 8 ACE Items + Derive Total for NE25\n")
cat(strrep("=", 60), "\n")

# Load required packages
library(duckdb)
library(dplyr)
library(mice)
library(ranger)
library(arrow)

# Load safe join utilities
source("R/utils/safe_joins.R")

if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
}
if (!requireNamespace("dplyr", quietly = TRUE)) {
  stop("Package 'dplyr' is required. Install with: install.packages('dplyr')")
}
if (!requireNamespace("mice", quietly = TRUE)) {
  stop("Package 'mice' is required. Install with: install.packages('mice')")
}
if (!requireNamespace("arrow", quietly = TRUE)) {
  stop("Package 'arrow' is required. Install with: install.packages('arrow')")
}
if (!requireNamespace("reticulate", quietly = TRUE)) {
  stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
}

# Source configuration
source("R/utils/environment_config.R")
source("R/imputation/config.R")

# Configure reticulate to use .env Python executable
python_path <- get_python_path()
reticulate::use_python(python_path, required = TRUE)

# Load recode_missing function (used in NE25 transforms)
source("R/transform/ne25_transforms.R")

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

study_id <- "ne25"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

cat("\nConfiguration:\n")
cat("  Study ID:", study_id, "\n")
cat("  Study Name:", study_config$study_name, "\n")
cat("  Number of imputations (M):", config$n_imputations, "\n")
cat("  Random seed:", config$random_seed, "\n")
cat("  Data directory:", study_config$data_dir, "\n")
cat("  Variables to impute: 8 child ACE items (cqr017-cqr024)\n")
cat("  Method: Random Forest (all 8 variables)\n")
cat("  Defensive filtering: meets_inclusion = TRUE\n")

M <- config$n_imputations
seed <- config$random_seed

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Load base child ACE data from DuckDB
#'
#' @param db_path Path to DuckDB database
#' @param eligible_only Logical, filter to meets_inclusion == TRUE
#'
#' @return data.frame with base child ACE data
load_base_child_aces_data <- function(db_path, eligible_only = TRUE) {
  cat("\n[INFO] Loading base child ACE data from DuckDB...\n")

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Build query
  query <- "
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      source_project,
      'ne25' as study_id,

      -- Variables to impute (8 child ACE items)
      cqr017,
      cqr018,
      cqr019,
      cqr020,
      cqr021,
      cqr022,
      cqr023,
      cqr024,

      -- Auxiliary variables (complete or mostly complete)
      \"authentic.x\",
      age_in_days,
      female,

      -- Eligibility flag
      \"eligible.x\"

    FROM ne25_transformed
  "

  if (eligible_only) {
    # DEFENSIVE FILTERING: meets_inclusion (eligible with non-NA authenticity_weight)
    query <- paste0(query, "\n    WHERE meets_inclusion = TRUE")
  }

  dat <- DBI::dbGetQuery(con, query)

  # Apply recode_missing to all child ACE items (missing codes: 99, 9)
  ace_items <- c("cqr017", "cqr018", "cqr019", "cqr020", "cqr021", "cqr022", "cqr023", "cqr024")
  for (var in ace_items) {
    if (var %in% names(dat)) {
      dat[[var]] <- recode_missing(dat[[var]], missing_codes = c(99, 9))
    }
  }

  cat("  [OK] Loaded", nrow(dat), "records (defensive filtering applied)\n")
  cat("  [OK] Applied recode_missing() to 8 ACE items (codes 99, 9 → NA)\n")

  return(dat)
}


#' Load PUMA imputation from database
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with PUMA for imputation m
load_puma_imputation <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading PUMA imputation m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  query <- sprintf("
    SELECT
      CAST(pid AS INTEGER) as pid,
      CAST(record_id AS INTEGER) as record_id,
      puma
    FROM %s_imputed_puma
    WHERE study_id = '%s' AND imputation_m = %d
  ", study_id, study_id, m)

  puma_data <- DBI::dbGetQuery(con, query)

  cat(sprintf("  [OK] Loaded %d PUMA imputations\n", nrow(puma_data)))

  return(puma_data)
}


#' Load sociodemographic imputations for child ACEs
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with sociodem variables for imputation m
load_sociodem_imputations_for_child_aces <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading sociodemographic imputations m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Variables: raceG, educ_mom, income, family_size, fplcat
  sociodem_vars <- c("raceG", "educ_mom", "income", "family_size", "fplcat")

  sociodem_list <- list()

  for (var in sociodem_vars) {
    query <- sprintf("
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        \"%s\" as %s
      FROM %s_imputed_%s
      WHERE study_id = '%s' AND imputation_m = %d
    ", var, var, study_id, var, study_id, m)

    var_data <- DBI::dbGetQuery(con, query)
    sociodem_list[[var]] <- var_data
  }

  # Merge all sociodem variables
  sociodem_merged <- sociodem_list[[1]]
  for (i in 2:length(sociodem_list)) {
    sociodem_merged <- dplyr::full_join(sociodem_merged, sociodem_list[[i]], by = c("pid", "record_id"))
  }

  cat(sprintf("  [OK] Loaded %d sociodem records with %d variables\n",
              nrow(sociodem_merged), length(sociodem_vars)))

  return(sociodem_merged)
}


#' Load mental health imputations for child ACEs
#'
#' @param db_path Path to DuckDB database
#' @param m Integer, imputation number (1 to M)
#' @param study_id Study identifier
#'
#' @return data.frame with mental health variables for imputation m
load_mental_health_imputations_for_child_aces <- function(db_path, m, study_id = "ne25") {
  cat(sprintf("\n[INFO] Loading mental health imputations m=%d...\n", m))

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

  # Variables: phq2_positive, gad2_positive
  mh_vars <- c("phq2_positive", "gad2_positive")

  mh_list <- list()

  for (var in mh_vars) {
    query <- sprintf("
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        %s
      FROM %s_imputed_%s
      WHERE study_id = '%s' AND imputation_m = %d
    ", var, study_id, var, study_id, m)

    var_data <- DBI::dbGetQuery(con, query)
    mh_list[[var]] <- var_data
  }

  # Merge mental health variables
  mh_merged <- dplyr::full_join(mh_list[[1]], mh_list[[2]], by = c("pid", "record_id"))

  cat(sprintf("  [OK] Loaded %d mental health records with %d variables\n",
              nrow(mh_merged), length(mh_vars)))

  return(mh_merged)
}


#' Merge imputed data with base data
#'
#' @param base_data data.frame with base child ACE data
#' @param puma_imp data.frame with PUMA imputation
#' @param sociodem_imp data.frame with sociodem imputations
#' @param mh_imp data.frame with mental health imputations
#' @param db_path Path to DuckDB database
#'
#' @return data.frame with merged data
merge_imputed_data <- function(base_data, puma_imp, sociodem_imp, mh_imp, db_path) {
  cat("\n[INFO] Merging base data with imputations...\n")

  # Merge PUMA
  dat_merged <- base_data %>%
    safe_left_join(puma_imp, by_vars = c("pid", "record_id"))

  # For records without geography ambiguity, fill from ne25_transformed
  if (any(is.na(dat_merged$puma))) {
    con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con, shutdown = FALSE))

    geo_observed <- DBI::dbGetQuery(con, "
      SELECT
        CAST(pid AS INTEGER) as pid,
        CAST(record_id AS INTEGER) as record_id,
        puma as puma_observed
      FROM ne25_transformed
      WHERE meets_inclusion = TRUE
    ")

    dat_merged <- dat_merged %>%
      safe_left_join(geo_observed, by_vars = c("pid", "record_id")) %>%
      dplyr::mutate(puma = ifelse(is.na(puma), puma_observed, puma)) %>%
      dplyr::select(-puma_observed)
  }

  # Merge sociodem imputations
  dat_merged <- dat_merged %>%
    safe_left_join(sociodem_imp, by_vars = c("pid", "record_id"))

  # Fill missing sociodem values from ne25_transformed (for records with observed values)
  sociodem_vars <- c("raceG", "educ_mom", "income", "family_size", "fplcat")

  has_missing_sociodem <- any(sapply(sociodem_vars, function(v) any(is.na(dat_merged[[v]]))))

  if (has_missing_sociodem) {
    con_sociodem <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con_sociodem, shutdown = FALSE), add = TRUE)

    for (var in sociodem_vars) {
      if (any(is.na(dat_merged[[var]]))) {
        query <- sprintf("
          SELECT
            CAST(pid AS INTEGER) as pid,
            CAST(record_id AS INTEGER) as record_id,
            \"%s\" as %s_observed
          FROM ne25_transformed
          WHERE meets_inclusion = TRUE
        ", var, var)

        var_observed <- DBI::dbGetQuery(con_sociodem, query)

        dat_merged <- dat_merged %>%
          safe_left_join(var_observed, by_vars = c("pid", "record_id")) %>%
          dplyr::mutate(!!var := ifelse(is.na(.data[[var]]), .data[[paste0(var, "_observed")]], .data[[var]])) %>%
          dplyr::select(-!!paste0(var, "_observed"))
      }
    }
  }

  # Merge mental health imputations
  dat_merged <- dat_merged %>%
    safe_left_join(mh_imp, by_vars = c("pid", "record_id"))

  # Fill missing mental health values from ne25_transformed
  mh_vars <- c("phq2_positive", "gad2_positive")

  has_missing_mh <- any(sapply(mh_vars, function(v) any(is.na(dat_merged[[v]]))))

  if (has_missing_mh) {
    con_mh <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(duckdb::dbDisconnect(con_mh, shutdown = FALSE), add = TRUE)

    for (var in mh_vars) {
      if (any(is.na(dat_merged[[var]]))) {
        query <- sprintf("
          SELECT
            CAST(pid AS INTEGER) as pid,
            CAST(record_id AS INTEGER) as record_id,
            %s as %s_observed
          FROM ne25_transformed
          WHERE meets_inclusion = TRUE
        ", var, var)

        var_observed <- DBI::dbGetQuery(con_mh, query)

        dat_merged <- dat_merged %>%
          safe_left_join(var_observed, by_vars = c("pid", "record_id")) %>%
          dplyr::mutate(!!var := ifelse(is.na(.data[[var]]), .data[[paste0(var, "_observed")]], .data[[var]])) %>%
          dplyr::select(-!!paste0(var, "_observed"))
      }
    }
  }

  cat(sprintf("  [OK] Merged data: %d records with %d columns\n", nrow(dat_merged), ncol(dat_merged)))

  return(dat_merged)
}


#' Save child ACE imputation to Feather (single variable)
#'
#' @param completed_data data.frame, completed dataset from mice
#' @param original_data data.frame, original data before imputation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#' @param variable_name Character, name of variable to save
#'
#' @return Invisible NULL
save_child_ace_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  cat(sprintf("\n[INFO] Saving %s imputation m=%d to Feather...\n", variable_name, m))

  # Save ONLY originally-missing records (space-efficient design)
  originally_missing <- is.na(original_data[[variable_name]])

  imputed_records <- completed_data[originally_missing, c("study_id", "pid", "record_id", variable_name)]
  imputed_records$imputation_m <- m

  # DEFENSIVE FILTERING: Remove records where imputation failed (value still NA)
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  n_null_filtered <- sum(!successfully_imputed)
  if (n_null_filtered > 0) {
    cat(sprintf("  [INFO] Filtered %d records with incomplete auxiliary variables\n", n_null_filtered))
  }

  if (nrow(imputed_records) > 0) {
    # Reorder columns: study_id, pid, record_id, imputation_m, [variable]
    imputed_records <- imputed_records[, c("study_id", "pid", "record_id", "imputation_m", variable_name)]

    # Save to Feather file
    output_path <- file.path(output_dir, sprintf("%s_m%d.feather", variable_name, m))
    arrow::write_feather(imputed_records, output_path)

    cat(sprintf("  [OK] %s: %d values -> %s\n", variable_name, nrow(imputed_records), basename(output_path)))
  } else {
    cat(sprintf("  [WARN] %s: No imputed values to save\n", variable_name))
  }

  return(invisible(NULL))
}


#' Derive and save child ACE total score
#'
#' @param completed_data data.frame with completed child ACE items
#' @param original_data data.frame with original data to identify which records need derivation
#' @param m Integer, imputation number
#' @param output_dir Path to output directory
#'
#' @return Invisible NULL
derive_child_ace_total <- function(completed_data, original_data, m, output_dir) {
  cat(sprintf("\n[INFO] Deriving child ACE total for m=%d...\n", m))

  # Child ACE items in completed data
  ace_items <- c("child_ace_parent_divorce", "child_ace_parent_death", "child_ace_parent_jail",
                 "child_ace_domestic_violence", "child_ace_neighborhood_violence",
                 "child_ace_mental_illness", "child_ace_substance_use", "child_ace_discrimination")

  # Calculate child ACE total (0-8 scale)
  completed_data$child_ace_total <- rowSums(
    completed_data[, ace_items],
    na.rm = FALSE  # Conservative: if ANY item is NA, total is NA
  )

  # Report distribution
  ace_dist <- table(completed_data$child_ace_total, useNA = "always")
  cat("  Child ACE total distribution (all completed):\n")
  for (i in seq_along(ace_dist)) {
    ace_value <- names(ace_dist)[i]
    ace_count <- ace_dist[i]
    cat(sprintf("    %s: %d (%.1f%%)\n", ace_value, ace_count, 100 * ace_count / nrow(completed_data)))
  }

  # CRITICAL: Only save records where ANY of the 8 items needed imputation
  # This matches the storage convention used throughout the platform

  # Get original ACE items (cqr017-cqr024)
  ace_items_original <- c("cqr017", "cqr018", "cqr019", "cqr020", "cqr021", "cqr022", "cqr023", "cqr024")

  # Identify records where ANY ACE item was originally missing
  any_ace_missing <- rowSums(is.na(original_data[, ace_items_original])) > 0

  records_needing_total <- original_data[any_ace_missing, c("pid", "record_id")]

  # Only proceed if there are records that need derivation
  if (nrow(records_needing_total) > 0) {
    records_needing_total$needs_derivation <- TRUE

    # Merge with completed data to identify which records need derived values
    total_data <- safe_left_join(
      completed_data[, c("study_id", "pid", "record_id", "child_ace_total")],
      records_needing_total,
      by = c("pid", "record_id")
    )

    # Filter to only records that needed derivation
    total_data <- total_data[!is.na(total_data$needs_derivation), ]
    total_data <- total_data[, c("study_id", "pid", "record_id", "child_ace_total")]

    # DEFENSIVE FILTERING: Remove NULL values before adding imputation_m column
    total_data <- total_data[!is.na(total_data$child_ace_total), ]

    if (nrow(total_data) > 0) {
      total_data$imputation_m <- m
      total_data <- total_data[, c("study_id", "pid", "record_id", "imputation_m", "child_ace_total")]

      output_path <- file.path(output_dir, sprintf("child_ace_total_m%d.feather", m))
      arrow::write_feather(total_data, output_path)

      cat(sprintf("  [OK] child_ace_total: %d derived values -> %s\n", nrow(total_data), basename(output_path)))
    } else {
      cat("  [INFO] No child_ace_total values needed derivation (all filtered due to NULL)\n")
    }
  } else {
    cat("  [INFO] No child_ace_total values needed derivation (all have complete ACE items)\n")
  }

  return(invisible(NULL))
}

# =============================================================================
# MAIN IMPUTATION WORKFLOW
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("Starting Child ACEs Imputation\n")
cat(strrep("=", 60), "\n")

# Setup study-specific output directory
output_dir <- file.path(study_config$data_dir, "child_aces_feather")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("[INFO] Created output directory:", output_dir, "\n")
}

# Load base data once
db_path <- config$database$db_path
base_data <- load_base_child_aces_data(db_path, eligible_only = TRUE)

# Check missing data
ace_items_original <- c("cqr017", "cqr018", "cqr019", "cqr020", "cqr021", "cqr022", "cqr023", "cqr024")

cat("\nMissing data summary:\n")
for (var in ace_items_original) {
  n_missing <- sum(is.na(base_data[[var]]))
  pct_missing <- 100 * n_missing / nrow(base_data)
  cat(sprintf("  %s: %d of %d (%.1f%%)\n", var, n_missing, nrow(base_data), pct_missing))
}

# Rename ACE items to descriptive names for mice
ace_item_mapping <- c(
  "cqr017" = "child_ace_parent_divorce",
  "cqr018" = "child_ace_parent_death",
  "cqr019" = "child_ace_parent_jail",
  "cqr020" = "child_ace_domestic_violence",
  "cqr021" = "child_ace_neighborhood_violence",
  "cqr022" = "child_ace_mental_illness",
  "cqr023" = "child_ace_substance_use",
  "cqr024" = "child_ace_discrimination"
)

# Rename columns in base_data
for (old_name in names(ace_item_mapping)) {
  new_name <- ace_item_mapping[[old_name]]
  if (old_name %in% names(base_data)) {
    base_data[[new_name]] <- base_data[[old_name]]
  }
}

# LOOP OVER GEOGRAPHY/SOCIODEM/MENTAL HEALTH IMPUTATIONS
for (m in 1:M) {
  cat("\n", strrep("-", 60), "\n")
  cat(sprintf("IMPUTATION m=%d/%d\n", m, M))
  cat(strrep("-", 60), "\n")

  # Step 1: Load PUMA imputation m
  puma_m <- load_puma_imputation(db_path, m)

  # Step 2: Load sociodem imputations m
  sociodem_m <- load_sociodem_imputations_for_child_aces(db_path, m)

  # Step 3: Load mental health imputations m
  mh_m <- load_mental_health_imputations_for_child_aces(db_path, m)

  # Step 4: Merge all data
  dat_m <- merge_imputed_data(base_data, puma_m, sociodem_m, mh_m, db_path)

  # Step 5: Prepare data for mice
  # Variables: 8 child ACE items (to impute) + 11 auxiliary variables
  imp_vars <- unname(ace_item_mapping)
  aux_vars <- c("puma", "raceG", "educ_mom", "income", "family_size", "fplcat",
                "phq2_positive", "gad2_positive", "authentic.x", "age_in_days", "female")

  all_vars <- c(imp_vars, aux_vars, "study_id", "pid", "record_id")

  # Check which variables actually exist in dat_m
  existing_vars <- all_vars[all_vars %in% names(dat_m)]
  missing_vars <- all_vars[!all_vars %in% names(dat_m)]

  if (length(missing_vars) > 0) {
    cat(sprintf("\n[WARN] Missing columns (will skip): %s\n", paste(missing_vars, collapse = ", ")))
  }

  dat_mice <- dat_m[, existing_vars]

  # Step 6: Configure mice
  # Set up predictor matrix (which variables predict which)
  predictor_matrix <- mice::make.predictorMatrix(dat_mice)

  # Get auxiliary variables that actually exist in the data
  aux_vars_existing <- aux_vars[aux_vars %in% names(dat_mice)]

  # Each child ACE item can use all auxiliary variables as predictors
  for (var in imp_vars) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0  # Reset row
      predictor_matrix[var, aux_vars_existing] <- 1
    }
  }

  # Auxiliary variables are NOT imputed (use complete cases or pre-imputed)
  for (var in c(aux_vars_existing, "study_id", "pid", "record_id")) {
    if (var %in% rownames(predictor_matrix)) {
      predictor_matrix[var, ] <- 0
    }
  }

  # Set up methods vector (Random Forest for all 8 child ACE items)
  method_vector <- rep("", ncol(dat_mice))
  names(method_vector) <- colnames(dat_mice)
  for (var in imp_vars) {
    if (var %in% names(method_vector)) {
      method_vector[var] <- "rf"
    }
  }

  cat("\nmice Configuration:\n")
  cat("  Imputations: 1 (chained approach)\n")
  cat("  Iterations: 5\n")
  cat("  Method: Random Forest (all 8 variables)\n")
  cat("  Auxiliary variables:", paste(aux_vars_existing, collapse = ", "), "\n")
  cat("  remove.collinear: FALSE (RF handles multicollinearity)\n")

  # Step 7: Run mice
  cat("\n[INFO] Running mice imputation...\n")

  set.seed(seed + m)  # Unique seed for each imputation

  mice_result <- mice::mice(
    data = dat_mice,
    m = 1,
    method = method_vector,
    predictorMatrix = predictor_matrix,
    maxit = 5,
    remove.collinear = FALSE,
    printFlag = FALSE
  )

  cat("  [OK] mice imputation complete\n")

  # Step 8: Extract completed dataset
  completed_m <- mice::complete(mice_result, 1)

  # Step 9: Save each child ACE item to Feather (only originally-missing records)
  for (new_name in unname(ace_item_mapping)) {
    # Find corresponding original variable name for checking missingness
    old_name <- names(ace_item_mapping)[ace_item_mapping == new_name]

    # Create a temporary version of dat_m with the new variable name for save function
    dat_m_temp <- dat_m
    dat_m_temp[[new_name]] <- dat_m[[old_name]]

    save_child_ace_feather(completed_m, dat_m_temp, m, output_dir, new_name)
  }

  # Step 10: Derive and save child ACE total
  derive_child_ace_total(completed_m, base_data, m, output_dir)

  cat(sprintf("\n[OK] Imputation m=%d complete\n", m))
}

cat("\n", strrep("=", 60), "\n")
cat("Child ACEs Imputation Complete!\n")
cat(strrep("=", 60), "\n")

cat("\nImputation Summary:\n")
cat(sprintf("  Imputations generated: %d\n", M))
cat(sprintf("  Variables imputed: %s\n", paste(unname(ace_item_mapping), collapse = ", ")))
cat(sprintf("  Derived variable: child_ace_total\n"))
cat(sprintf("  Method: Random Forest (all variables)\n"))
cat(sprintf("  Output directory: %s\n", output_dir))
cat(sprintf("  Total output files: %d (8 items × M + 1 total × M)\n", 9 * M))

cat("\nNext steps:\n")
cat("  1. Run: python scripts/imputation/ne25/06b_insert_child_aces.py\n")
cat(strrep("=", 60), "\n")
