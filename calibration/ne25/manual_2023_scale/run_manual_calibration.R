#!/usr/bin/env Rscript

#' Manual 2023 Scale Calibration Pipeline
#'
#' This orchestrator script manages the workflow for calibrating new NE25 items
#' against the 2023 historical scale parameters using Mplus.
#'
#' WORKFLOW:
#'   1. Load item response data from NE25 database (using 00_load_item_response_data.R)
#'   2. Prepare calibration dataset (wide format, equate lexicon names)
#'   3. Load 2023 mirt calibration parameters and generate Mplus MODEL block
#'   4. Create Mplus input file with:
#'      - VARIABLE block (item and person variables)
#'      - DATA block (data file path, format)
#'      - MODEL block (fixed parameters from 2023 calibration)
#'      - OUTPUT block (estimation options)
#'   5. Run Mplus estimation
#'   6. Parse results and export to calibration database
#'
#' DATA FLOW:
#'   NE25 transformed table (DuckDB)
#'     ↓
#'   Item response data + metadata (wide format, equate names)
#'     ↓
#'   Mplus input file (.inp) + data file (.dat)
#'     ↓
#'   Mplus estimation
#'     ↓
#'   Results parsing + database update
#'
#' OUTPUT LOCATIONS:
#'   - calibration/ne25/manual_2023_scale/data/ - Prepared datasets
#'   - calibration/ne25/manual_2023_scale/mplus/ - Mplus files (.inp, .dat, .out)
#'   - calibration/ne25/manual_2023_scale/results/ - Parsed results

rm(list = ls())

cat("\n")
cat("################################################################################\n")
cat("#                                                                              #\n")
cat("#   MANUAL 2023 SCALE CALIBRATION PIPELINE - ORCHESTRATOR                     #\n")
cat("#                                                                              #\n")
cat("################################################################################\n")
cat("\n")


# ==============================================================================
# CONFIGURATION
# ==============================================================================

cat("=== CONFIGURATION ===\n\n")

# Paths
db_path <- "data/duckdb/kidsights_local.duckdb"
codebook_path <- "codebook/data/codebook.json"
mirt_calib_file <- "todo/kidsights-calibration/kidsight_calibration_mirt.rds"
output_dir <- "calibration/ne25/manual_2023_scale"
data_dir <- file.path(output_dir, "data")
utils_dir <- file.path(output_dir, "utils")
mplus_dir <- file.path(output_dir, "mplus")

cat("Database:", db_path, "\n")
cat("Codebook:", codebook_path, "\n")
cat("MIRT calibration:", mirt_calib_file, "\n")
cat("Output directory:", output_dir, "\n\n")

# Create output directories
if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
if (!dir.exists(mplus_dir)) dir.create(mplus_dir, recursive = TRUE)

cat("Directories verified/created\n\n")

# ==============================================================================
# STEP 1: LOAD ITEM RESPONSE DATA AND 
# ==============================================================================

cat("=== STEP 1: LOAD ITEM RESPONSE DATA ===\n\n")

# Source the data loading utility
source(file.path(utils_dir, "00_load_item_response_data.R"))

# Load data with custom output directory
out_list_00 <- load_stage1_data(
  db_path = db_path,
  codebook_path = codebook_path,
  output_dir = data_dir
)

wide_dat <- out_list_00$wide_data          # Item responses (269 items)
person_dat <- out_list_00$person_data      # Person-level covariates
item_metadata <- out_list_00$item_metadata # Item metadata


################################################################################
# STEP 2: Filter High-Influence Persons and Impute Missing Covariates
################################################################################

# Exclude 2 high-influence persons identified from prior Mplus Model 1f analysis
# These persons had overall_influence > 5.5 (extreme outliers in latent space)
person_dat_imp <- person_dat %>%
  # Impute missing values using CART (Classification and Regression Trees)
  # m=1: Single imputation (not multiple imputation)
  # maxit=20: 20 iterations for convergence
  mice::mice(method = "cart", m = 1, maxit = 20, remove.collinear = FALSE, seet.seed = 42) %>%
  mice::complete(1)  # Extract first (only) imputed dataset



################################################################################
# STEP 3: Engineer Demographic and Clinical Predictors
################################################################################

person_dat_imp <- person_dat_imp %>%
  dplyr::mutate(
    # --- Binary demographic indicators ---
    # College education: Bachelor's degree or higher
    college = as.integer(educ_a1 %in% c(
      "Bachelor's Degree (BA, BS, AB)",
      "Master's Degree (MA, MS, MSW, MBA)",
      "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)"
    )),
    nohs = as.integer(educ_a1 %in% c(
      "8th grade or less", 
      "9th-12th grade, No diploma"
    )), 
    school = dplyr::case_when(
      educ_a1 == "8th grade or less" ~ 8, 
      educ_a1 == "9th-12th grade, No diploma" ~ 10, 
      educ_a1 == "High School Graduate or GED Completed" ~ 12,
      educ_a1 == "Completed a vocational, trade, or business school program" ~ 12,
      educ_a1 == "Some College Credit, but No Degree" ~ 13, 
      educ_a1 == "Associate Degree (AA, AS)" ~14, 
      educ_a1 == "Bachelor's Degree (BA, BS, AB)" ~16, 
      educ_a1 == "Master's Degree (MA, MS, MSW, MBA)" ~ 18, 
      educ_a1 == "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)" ~ 20
    ),
    # Federal poverty line
    logfpl = log(fpl+100),
    # Race; 
    hisp = as.integer(raceG == "Hispanic"),
    black = as.integer(raceG == "Black or African American, non-Hisp."), 
    other = as.integer(raceG!= "White, non-Hisp." & black==0 & hisp == 0), 
    # --- PHQ-2 depression screening indicators ---
    # No depression symptoms: PHQ-2 total = 0
    phq2 = phq2_total,
  ) %>%
  dplyr::mutate(
    # --- Age-related predictors ---
    female = as.integer(female),          # Convert logical to 0/1
    logyrs = log(years + 1),              # Logarithmic age scaling
    yrs3 = (years - 3),                   # Age centered at 3 years
    femXyrs3 = female * (years - 3)       # Gender × age interaction
  ) %>%
  dplyr::select(
    # Identifiers
    pid,
    recordid,
    # Main effects
    female,
    logyrs,
    yrs3,
    # Moderators for age interactions
    college,
    nohs,
    school,
    logfpl,
    phq2, 
    black,
    hisp,
    other
  ) %>% 
  dplyr::mutate(
    school = scale(school), 
    logfpl = scale(logfpl), 
    phq2 = scale(phq2)
  ) %>% 
  dplyr::select(
    pid, 
    recordid, 
    logyrs, 
    yrs3, 
    school, 
    logfpl, 
    phq2, 
    black,
    hisp, 
    other
  )


################################################################################
# STEP 4: Create an Mplus Dataset
################################################################################

mplus_dat = person_dat_imp %>% 
  dplyr::mutate(
    schXyrs3 = school*yrs3,
    fplXyrs3 = logfpl*yrs3,
    phqXyrs3 = phq2*yrs3,
    rid = 1:n(),
  ) %>% 
  dplyr::relocate(rid) %>% 
  dplyr::relocate(schXyrs3:phqXyrs3, .after = "phq2") %>% 
  safe_left_join(wide_dat, by_vars = c("pid","recordid")) %>% 
  # UNDO the reverse coding
  dplyr::mutate(
    across(starts_with("ps"), function(y)abs(y-max(y,na.rm = T)))
  )

names(mplus_dat)

#library(MplusAutomation)
#MplusAutomation::prepareMplusData(mplus_dat, filename = "calibration/ne25/manual_2023_scale/mplus/mplus_dat.dat", inpfile = T)


kidsights_gsed_pf_scores_2022_df  <-MplusAutomation::readModels(
  target = "calibration/ne25/manual_2023_scale/mplus/", 
  filefilter = "all_2023_calibration_ne25"
)$savedata %>% 
  dplyr::rename_all(tolower) %>% 
  dplyr::select(
    pid, 
    record_id = recordid,
    kidsights_2022 = f, 
    kidsights_2022_csem = f_se, 
    general_gsed_pf_2022 = gen, 
    feeding_gsed_pf_2022 = eat, 
    externalizing_gsed_pf_2022 = eat, 
    internalizing_gsed_pf_2022 = int, 
    sleeping_gsed_pf_2022 = sle, 
    social_competency_gsed_pf_2022 = soc, 
    sleeping_gsed_pf_2022_csem = sle_se,
    general_gsed_pf_2022_csem = gen_se, 
    feeding_gsed_pf_2022_csem = eat_se,
    externalizing_gsed_pf_2022_csem = eat_se,
    internalizing_gsed_pf_2022_csem = int_se,
    social_competency_gsed_pf_2022_csem = soc_se
  ) %>% 
  dplyr::mutate(
    year = 2025, 
    fips = "031", 
    state = "NE"
  ) %>% 
  dplyr::relocate(year:state)


# Add this to the database
con <- DBI::dbConnect(duckdb::duckdb(),
                      dbdir = "data/duckdb/kidsights_local.duckdb",
                      read_only = FALSE)  # Set to FALSE to allow writes

cat("Connected to DuckDB database\n\n")

# Clean up on exit
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# Pattern 2: From R object already in memory
DBI::dbWriteTable(con, "ne25_kidsights_gsed_pf_scores_2022_scale", kidsights_gsed_pf_scores_2022_df, overwrite = TRUE)

result <- DBI::dbGetQuery(con, "SELECT * FROM ne25_kidsights_gsed_pf_scores_2022_scale LIMIT 5")






## Let's add insufficient resopnse exclusions
too_few_items_df = out_list_00$exclusions %>% 
  dplyr::select(
    pid, 
    record_id = recordid, 
    n_kidsight_psychosocial_responses = n_responses, 
    exclusion_reason
  ) %>% 
  dplyr::mutate(
    year = 2025, 
    fips = "031",
    state = "NE",
    too_few_item_responses = T
  ) %>% 
  dplyr::relocate(year:too_few_item_responses)

DBI::dbWriteTable(con, "ne25_too_few_items", too_few_items_df, overwrite = TRUE)

result <- DBI::dbGetQuery(con, "SELECT * FROM ne25_too_few_items LIMIT 5")



