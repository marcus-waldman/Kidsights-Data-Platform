#' Create SES Analytic Dataset for Research Questions
#'
#' This script creates an analytic dataset with variables needed for SES-related
#' research questions documented in todo/SES variables.csv
#'
#' USAGE:
#'   source("scripts/analyses/create_ses_analytic_dataset.R")
#'
#' OUTPUT:
#'   - data/analyses/ses_analytic_dataset.sav (SPSS format)
#'   - data/analyses/ses_analytic_dataset.rds (R format)
#'   - data/analyses/ses_analytic_dataset.csv (CSV format)
#'   - data/analyses/ses_analytic_codebook.csv (Variable documentation)
#'
#' AUTHOR: Kidsights Data Platform
#' DATE: December 2025

# ============================================================================
# SETUP
# ============================================================================

# Load required packages
required_packages <- c("duckdb", "DBI", "dplyr", "haven", "tidyr")

cat("[INFO] Loading required packages...\n")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("[INFO] Installing", pkg, "...\n")
    install.packages(pkg, repos = "https://cran.r-project.org")
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

# Create output directory
output_dir <- "data/analyses"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("\n===========================================\n")
cat("  SES Analytic Dataset Creator\n")
cat("===========================================\n\n")

# ============================================================================
# CONNECT TO DATABASE
# ============================================================================

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop("[ERROR] Database not found at: ", db_path)
}

cat("[INFO] Connecting to database...\n")
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(conn, shutdown = TRUE), add = TRUE)

# ============================================================================
# DEFINE VARIABLES FOR EACH RESEARCH QUESTION
# ============================================================================

cat("[INFO] Defining variables by research question...\n")

# Core identifiers
id_vars <- c("pid", "record_id")

# Inclusion criteria
inclusion_vars <- c("meets_inclusion", "eligible", "influential", "too_few_items")

# Demographics and stratification variables
demo_vars <- c(
  "years_old", "age_months", "age_in_days",
  "female", "raceG",
  "educ_a1", "educ_mom", "educ_a2",  # Added educ_a1 (caregiver 1 education)
  "income", "fpl", "family_size"
)

# Geography variables (rural/urban stratification)
geo_vars <- c(
  "county", "county_name", "puma",
  "urban_rural", "urban_pct"
)

# Q1: FPL distribution
fpl_vars <- c("fpl", "fplcat", "income", "family_size")

# Q2-3: Food insecurity
food_vars <- c(
  "cqfa006",  # Food affordability
  paste0("mmifs", sprintf("%03d", 9:16))  # Food insecurity scale items
)

# Q4: Government services uptake
govt_vars <- paste0("cqr007___", 1:7)  # Government services checkboxes

# Q5: Trouble covering basics
basic_needs_vars <- c("cqfa005")

# Q6: Child development (Kidsights scores, D-scores, CREDI, HRTL)
child_dev_vars <- c(
  # 2022 Scale Person-Fit Scores (will be renamed from _gsed_pf_2022 to _pf)
  "kidsights_2022",
  "general_gsed_pf_2022",
  "feeding_gsed_pf_2022",
  "externalizing_gsed_pf_2022",
  "internalizing_gsed_pf_2022",
  "sleeping_gsed_pf_2022",
  "social_competency_gsed_pf_2022",

  # GSED D-scores (all ages)
  "dscore_d",    # D-score
  "dscore_n",    # Number of items

  # CREDI scores (ages 0-3, raw domain scores only)
  "credi_cog",         # Cognitive domain score
  "credi_lang",        # Language domain score
  "credi_mot",         # Motor domain score
  "credi_sem",         # Social-Emotional domain score
  "credi_overall",     # Overall CREDI score

  # HRTL Classifications (ages 3-5)
  "hrtl_early_learning_skills",        # On-Track/Emerging/Needs Support
  "hrtl_health",                       # On-Track/Emerging/Needs Support
  "hrtl_self_regulation",              # On-Track/Emerging/Needs Support
  "hrtl_social_emotional_development", # On-Track/Emerging/Needs Support
  "hrtl_motor_development",            # On-Track/Emerging/Needs Support (masked due to missing data)
  "hrtl_overall"                       # Overall HRTL classification
)

# Q7: Home Learning Environment (HLE)
hle_vars <- DBI::dbGetQuery(conn, "
  SELECT column_name
  FROM information_schema.columns
  WHERE table_name = 'ne25_transformed'
  AND column_name LIKE 'fci_%'
")$column_name

# Q8: Flourishing Index components
flourish_vars <- c(
  "cfqb001",   # Physical health
  "cqfb002",   # Mental/emotional health
  paste0("mmi", sprintf("%03d", 120:123)),  # MMI items
  "cqfa010",   # Emotional support
  "q1502",     # Parenting confidence
  "cqfb009", "cqfb010", "cqfb011", "cqfb012",  # Neighborhood
  "cqfa005",   # Covering basics
  paste0("mmi", sprintf("%03d", 110:113))   # MMI items
)

# Q9: Community/Neighborhood
community_vars <- c(
  "cqfb009",  # Neighborhood help
  "cqfb010",  # Watch children
  "cqfb011",  # Child safety
  "cqfb012"   # Know where to go for help
)

# Q10: ACEs (individual caregiver items + composite scores)
ace_vars <- c(
  # Individual caregiver ACE items (caregiver's childhood)
  paste0("cace", 1:10),
  # Caregiver ACEs (composite)
  "a1_ace_total",      # Caregiver's childhood ACEs total
  "a1_ace_risk_cat",   # Caregiver ACE risk category
  # Child ACEs (composite only)
  "child_ace_total",   # Child's current ACEs
  "child_ace_risk_cat" # Child ACE risk category
)

# Q11: Parenting demands and supports
parenting_vars <- c(
  "cqfa010",  # Emotional support
  "q1502"     # Parenting confidence
)

# Mental health and ACEs (stratification)
mental_health_vars <- c(
  "phq2_interest", "phq2_depressed",  # PHQ-2 items (depression)
  "gad2_nervous", "gad2_worry",       # GAD-2 items (anxiety)
  "phq2_total",                       # PHQ-2 total score (0-6)
  "gad2_total",                       # GAD-2 total score (0-6)
  "phq2_positive", "gad2_positive",   # Clinical cutoffs
  "a1_ace_total", "a1_ace_risk_cat"   # Caregiver ACEs (for stratification)
)

# Weights
weight_vars <- c("calibrated_weight")

# ============================================================================
# COMBINE ALL VARIABLES
# ============================================================================

all_vars <- unique(c(
  id_vars, inclusion_vars, demo_vars, geo_vars,
  fpl_vars, food_vars, govt_vars, basic_needs_vars,
  child_dev_vars, hle_vars, flourish_vars,
  community_vars, ace_vars, parenting_vars,
  mental_health_vars, weight_vars
))

# Check which variables exist in the table
existing_cols <- DBI::dbGetQuery(conn, "
  SELECT column_name
  FROM information_schema.columns
  WHERE table_name = 'ne25_transformed'
")$column_name

missing_vars <- setdiff(all_vars, existing_cols)

if (length(missing_vars) > 0) {
  cat("[WARN] Some requested variables not found in table:\n")
  for (v in missing_vars) {
    cat("       -", v, "\n")
  }
}

# Keep only existing variables
vars_to_extract <- intersect(all_vars, existing_cols)

cat("[OK]   Extracting", length(vars_to_extract), "variables\n\n")

# ============================================================================
# EXTRACT DATA WITH COLUMN RENAMING
# ============================================================================

cat("[INFO] Extracting analytic dataset...\n")

# Define column renaming map
rename_map <- c(
  # Psychosocial scores (_gsed_pf_2022 -> _pf)
  "general_gsed_pf_2022" = "general_pf",
  "feeding_gsed_pf_2022" = "feeding_pf",
  "externalizing_gsed_pf_2022" = "externalizing_pf",
  "internalizing_gsed_pf_2022" = "internalizing_pf",
  "sleeping_gsed_pf_2022" = "sleeping_pf",
  "social_competency_gsed_pf_2022" = "social_competency_pf",

  # Material hardship and food insecurity variables (add descriptive suffixes)
  "cqfa005" = "cqfa005_hardship_basics",
  "cqfa006" = "cqfa006_food_afford",
  "mmifs009" = "mmifs009_food_worry",
  "mmifs010" = "mmifs010_food_unhealthy",
  "mmifs011" = "mmifs011_food_limited_variety",
  "mmifs012" = "mmifs012_food_skip_meal",
  "mmifs013" = "mmifs013_food_ate_less",
  "mmifs014" = "mmifs014_food_ran_out",
  "mmifs015" = "mmifs015_food_hungry",
  "mmifs016" = "mmifs016_food_whole_day_without",

  # Government services (replace ___# with descriptive suffixes)
  "cqr007___1" = "cqr007_medicaid",
  "cqr007___2" = "cqr007_childcare_subsidy",
  "cqr007___3" = "cqr007_cash_assistance",
  "cqr007___4" = "cqr007_free_reduced_meals",
  "cqr007___5" = "cqr007_snap",
  "cqr007___6" = "cqr007_head_start",
  "cqr007___7" = "cqr007_wic",

  # FCI (Family Care Indicators) - Home Learning Environment
  # Section A: Reading materials in home
  "fci_a_1" = "fci_a_1_books_home",
  "fci_a_2" = "fci_a_2_magazines_newspapers",
  "fci_a_3" = "fci_a_3_see_adults_reading",

  # Section B: Children's books
  "fci_b_1" = "fci_b_1_has_childrens_books",
  "fci_b_2" = "fci_b_2_num_childrens_books",

  # Section C: Play materials/toys available
  "fci_c_1" = "fci_c_1_toys_homemade",
  "fci_c_2" = "fci_c_2_toys_store_bought",
  "fci_c_3" = "fci_c_3_toys_household_objects",
  "fci_c_4" = "fci_c_4_toys_music",
  "fci_c_5" = "fci_c_5_toys_drawing_writing",
  "fci_c_6" = "fci_c_6_toys_picture_books",
  "fci_c_7" = "fci_c_7_toys_building",
  "fci_c_8" = "fci_c_8_toys_movement",
  "fci_c_9" = "fci_c_9_toys_learning",
  "fci_c_10" = "fci_c_10_toys_pretend",
  "fci_c_11" = "fci_c_11_electronic_devices",

  # Section D: Caregiver-child activities
  "fci_d_1" = "fci_d_1_read_books",
  "fci_d_2" = "fci_d_2_tell_stories",
  "fci_d_3" = "fci_d_3_sing_songs",
  "fci_d_4" = "fci_d_4_go_outside",
  "fci_d_5" = "fci_d_5_play_together",
  "fci_d_6" = "fci_d_6_count_things",
  "fci_d_7" = "fci_d_7_draw_paint",
  "fci_d_8" = "fci_d_8_build_construct",
  "fci_d_9" = "fci_d_9_chores_together",
  "fci_d_10" = "fci_d_10_physical_activity",
  "fci_d_11" = "fci_d_11_toy_storage_space",

  # Flourishing Index components
  # Caregiver health
  "cfqb001" = "cfqb001_caregiver_phys_health",
  "cqfb002" = "cqfb002_caregiver_mental_health",

  # HRTL domain shortening
  "hrtl_social_emotional_development" = "hrtl_social_emotional",

  # Child positive characteristics
  "mmi110" = "mmi110_child_affectionate",
  "mmi111" = "mmi111_child_resilient",
  "mmi112" = "mmi112_child_curious",
  "mmi113" = "mmi113_child_happy",

  # Family resilience
  "mmi120" = "mmi120_family_communication",
  "mmi121" = "mmi121_family_problem_solving",
  "mmi122" = "mmi122_family_strengths",
  "mmi123" = "mmi123_family_hope",

  # Neighborhood/Community
  "cqfb009" = "cqfb009_neighborhood_help",
  "cqfb010" = "cqfb010_neighborhood_watch",
  "cqfb011" = "cqfb011_neighborhood_safe",
  "cqfb012" = "cqfb012_community_support",

  # Parenting support
  "cqfa010" = "cqfa010_parenting_support",
  "q1502" = "q1502_parenting_confidence",

  # Caregiver ACE items (individual - caregiver's childhood experiences)
  "cace1" = "cace1_neglect",
  "cace2" = "cace2_parent_loss",
  "cace3" = "cace3_mental_illness",
  "cace4" = "cace4_substance_abuse",
  "cace5" = "cace5_domestic_violence",
  "cace6" = "cace6_incarceration",
  "cace7" = "cace7_emotional_abuse",
  "cace8" = "cace8_physical_abuse",
  "cace9" = "cace9_emotional_neglect",
  "cace10" = "cace10_sexual_abuse"
)

# Build SELECT clause with column aliases for renaming
select_parts <- character()
for (var in vars_to_extract) {
  if (var %in% names(rename_map)) {
    # Rename this variable
    select_parts <- c(select_parts, paste0(var, " AS ", rename_map[[var]]))
  } else {
    # Keep original name
    select_parts <- c(select_parts, var)
  }
}

select_clause <- paste(select_parts, collapse = ", ")
query <- sprintf("
  SELECT %s
  FROM ne25_transformed
  WHERE meets_inclusion = TRUE
  ORDER BY pid, record_id
", select_clause)

analytic_data <- DBI::dbGetQuery(conn, query)

cat("[OK]   Extracted", nrow(analytic_data), "records\n")
cat("[OK]   Total variables:", ncol(analytic_data), "\n\n")

# ============================================================================
# MASK D-SCORES FOR CHILDREN >= 42 MONTHS
# ============================================================================

cat("[INFO] Masking D-scores for children 42 months or older...\n")

# Define 42 months threshold in days (42 * 30.4375 = 1278.375 days)
age_threshold_days <- 42 * 30.4375

# Check if age_in_days and D-score variables exist
if ("age_in_days" %in% names(analytic_data)) {
  dscore_vars <- c("dscore_d", "dscore_n")
  dscore_vars_present <- intersect(dscore_vars, names(analytic_data))

  if (length(dscore_vars_present) > 0) {
    # Count records that will be masked
    n_to_mask <- sum(analytic_data$age_in_days >= age_threshold_days, na.rm = TRUE)

    # Mask D-score variables for children >= 42 months
    for (var in dscore_vars_present) {
      analytic_data[[var]][analytic_data$age_in_days >= age_threshold_days] <- NA
    }

    cat("[OK]   Masked", length(dscore_vars_present), "D-score variables for",
        n_to_mask, "children >= 42 months\n\n")
  } else {
    cat("[WARN] No D-score variables found in dataset\n\n")
  }
} else {
  cat("[WARN] age_in_days not found - skipping D-score masking\n\n")
}

# ============================================================================
# RECODE FCI "DON'T KNOW" RESPONSES TO MISSING
# ============================================================================

cat("[INFO] Recoding FCI 'Don't Know' (9) responses to NA...\n")

# List of FCI variables that use 9 = Don't Know
fci_vars_with_dk <- c(
  # Section C: Toys and play materials
  paste0("fci_c_", 1:11, "_", c(
    "toys_homemade", "toys_store_bought", "toys_household_objects",
    "toys_music", "toys_drawing_writing", "toys_picture_books",
    "toys_building", "toys_movement", "toys_learning",
    "toys_pretend", "electronic_devices"
  )),
  # Section D: Activities with child
  paste0("fci_d_", 1:11, "_", c(
    "read_books", "tell_stories", "sing_songs", "go_outside",
    "play_together", "count_things", "draw_paint", "build_construct",
    "chores_together", "physical_activity", "toy_storage_space"
  ))
)

# Recode 9 to NA for FCI variables
fci_vars_present <- intersect(fci_vars_with_dk, names(analytic_data))
n_recoded <- 0

for (var in fci_vars_present) {
  n_dk <- sum(analytic_data[[var]] == 9, na.rm = TRUE)
  if (n_dk > 0) {
    analytic_data[[var]][analytic_data[[var]] == 9] <- NA
    n_recoded <- n_recoded + n_dk
  }
}

cat("[OK]   Recoded", n_recoded, "Don't Know responses to NA across",
    length(fci_vars_present), "FCI variables\n\n")

# ============================================================================
# REORDER VARIABLES LOGICALLY
# ============================================================================

cat("[INFO] Reordering variables...\n")

# Define logical variable ordering
variable_order <- c(
  # 1. Core Identifiers
  "pid", "record_id",

  # 2. Survey Weights
  "calibrated_weight",

  # 3. Geography
  "county", "county_name", "puma", "urban_rural", "urban_pct",

  # 4. Neighborhood/Community
  "cqfb009_neighborhood_help", "cqfb010_neighborhood_watch",
  "cqfb011_neighborhood_safe", "cqfb012_community_support",

  # 5. Demographics
  "years_old", "age_in_days", "female", "raceG",
  "educ_mom", "educ_a1", "educ_a2",

  # 6. Inclusion/Eligibility
  "meets_inclusion", "eligible", "influential",

  # 7. Socioeconomic Status
  "income", "fpl", "fplcat", "family_size",

  # 8. Government Services
  "cqr007_medicaid", "cqr007_childcare_subsidy", "cqr007_cash_assistance",
  "cqr007_free_reduced_meals", "cqr007_snap", "cqr007_head_start", "cqr007_wic",

  # 9. Material Hardship & Food Security
  "cqfa005_hardship_basics", "cqfa006_food_afford",
  "mmifs009_food_worry", "mmifs010_food_unhealthy", "mmifs011_food_limited_variety",
  "mmifs012_food_skip_meal", "mmifs013_food_ate_less", "mmifs014_food_ran_out",
  "mmifs015_food_hungry", "mmifs016_food_whole_day_without",

  # 10. Caregiver Mental Health & ACEs
  "phq2_interest", "phq2_depressed", "phq2_total", "phq2_positive",
  "gad2_nervous", "gad2_worry", "gad2_total", "gad2_positive",
  "cace1_neglect", "cace2_parent_loss", "cace3_mental_illness",
  "cace4_substance_abuse", "cace5_domestic_violence", "cace6_incarceration",
  "cace7_emotional_abuse", "cace8_physical_abuse", "cace9_emotional_neglect",
  "cace10_sexual_abuse",
  "a1_ace_total", "a1_ace_risk_cat",

  # 11. Caregiver Health
  "cfqb001_caregiver_phys_health", "cqfb002_caregiver_mental_health",

  # 12. Parenting Support & Confidence
  "cqfa010_parenting_support", "q1502_parenting_confidence",

  # 13. Family Resilience
  "mmi120_family_communication", "mmi121_family_problem_solving",
  "mmi122_family_strengths", "mmi123_family_hope",

  # 14. Home Learning Environment
  "fci_a_1_books_home", "fci_a_2_magazines_newspapers", "fci_a_3_see_adults_reading",
  "fci_b_1_has_childrens_books", "fci_b_2_num_childrens_books",
  "fci_c_1_toys_homemade", "fci_c_2_toys_store_bought", "fci_c_3_toys_household_objects",
  "fci_c_4_toys_music", "fci_c_5_toys_drawing_writing", "fci_c_6_toys_picture_books",
  "fci_c_7_toys_building", "fci_c_8_toys_movement", "fci_c_9_toys_learning",
  "fci_c_10_toys_pretend", "fci_c_11_electronic_devices",
  "fci_d_1_read_books", "fci_d_2_tell_stories", "fci_d_3_sing_songs",
  "fci_d_4_go_outside", "fci_d_5_play_together", "fci_d_6_count_things",
  "fci_d_7_draw_paint", "fci_d_8_build_construct", "fci_d_9_chores_together",
  "fci_d_10_physical_activity", "fci_d_11_toy_storage_space",

  # 15. Child Positive Characteristics
  "mmi110_child_affectionate", "mmi111_child_resilient",
  "mmi112_child_curious", "mmi113_child_happy",

  # 16. Child ACEs
  "child_ace_total", "child_ace_risk_cat",

  # 17. Child Development Outcomes
  "kidsights_2022", "general_pf", "feeding_pf", "externalizing_pf",
  "internalizing_pf", "sleeping_pf", "social_competency_pf",
  "dscore_d", "dscore_n",
  "credi_cog", "credi_lang", "credi_mot", "credi_sem", "credi_overall",
  "hrtl_early_learning_skills", "hrtl_health", "hrtl_self_regulation",
  "hrtl_social_emotional", "hrtl_motor_development", "hrtl_overall"
)

# Keep only variables that exist in the dataset
vars_present <- intersect(variable_order, names(analytic_data))

# Reorder columns
analytic_data <- analytic_data[, vars_present]

cat("[OK]   Reordered", length(vars_present), "variables into logical groups\n\n")

# ============================================================================
# CREATE CODEBOOK
# ============================================================================

cat("[INFO] Creating variable codebook...\n")

# Get metadata from ne25_metadata table
metadata_query <- sprintf("
  SELECT
    variable_name,
    category,
    variable_label,
    data_type,
    missing_percentage
  FROM ne25_metadata
  WHERE variable_name IN ('%s')
", paste(vars_to_extract, collapse = "', '"))

codebook <- DBI::dbGetQuery(conn, metadata_query)

# Add identifier variables if missing from metadata
identifier_vars <- c("pid", "record_id")
for (id_var in identifier_vars) {
  if (id_var %in% vars_to_extract && !(id_var %in% codebook$variable_name)) {
    # Add row for missing identifier
    new_row <- data.frame(
      variable_name = id_var,
      category = "identifiers",
      variable_label = ifelse(id_var == "pid", "Participant ID", "Record ID"),
      data_type = "character",
      missing_percentage = 0,
      stringsAsFactors = FALSE
    )
    codebook <- rbind(codebook, new_row)
  }
}

# Load REDCap data dictionary for response options
cat("[INFO] Loading REDCap data dictionary for response options...\n")
data_dict_path <- file.path("data", "export", "ne25", "ne25_data_dictionary.csv")
data_dict <- read.csv(data_dict_path, stringsAsFactors = FALSE)

# Create a mapping of field_name to response options
response_options_map <- list()
for (i in seq_len(nrow(data_dict))) {
  field <- data_dict$field_name[i]
  choices <- data_dict$select_choices_or_calculations[i]

  # Only include if there are actual response options (not empty or calculations)
  if (!is.na(choices) && nchar(trimws(choices)) > 0 && !grepl("^if\\(", choices)) {
    # Parse the pipe-separated choices
    # Format: "value1, label1 | value2, label2 | ..."
    response_options_map[[field]] <- choices
  }
}

# Add response_options column to codebook
codebook$response_options <- NA_character_
for (i in seq_len(nrow(codebook))) {
  var <- codebook$variable_name[i]

  # Check if this variable has response options in the data dictionary
  if (var %in% names(response_options_map)) {
    codebook$response_options[i] <- response_options_map[[var]]
  }
}

# Add transformation description column for composite/derived variables
codebook$transformation <- NA_character_

# Define transformations for composite variables
transformations <- list(
  # FCI Variables - All have 9 (Don't Know) recoded to NA
  "fci_c_1_toys_homemade" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_2_toys_store_bought" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_3_toys_household_objects" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_4_toys_music" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_5_toys_drawing_writing" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_6_toys_picture_books" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_7_toys_building" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_8_toys_movement" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_9_toys_learning" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_10_toys_pretend" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_c_11_electronic_devices" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_1_read_books" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_2_tell_stories" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_3_sing_songs" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_4_go_outside" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_5_play_together" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_6_count_things" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_7_draw_paint" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_8_build_construct" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_9_chores_together" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_10_physical_activity" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",
  "fci_d_11_toy_storage_space" = "Recoded 9 (Don't Know) to NA. Binary 0=No, 1=Yes.",

  # PHQ-2 Depression Screening
  "phq2_interest" = "Original item: Little interest or pleasure in doing things (0-3 scale: 0=Not at all, 1=Several days, 2=More than half the days, 3=Nearly every day)",
  "phq2_depressed" = "Original item: Feeling down, depressed, or hopeless (0-3 scale: 0=Not at all, 1=Several days, 2=More than half the days, 3=Nearly every day)",
  "phq2_total" = "Sum of phq2_interest + phq2_depressed (0-6 scale). NA if either item is missing (no partial scoring).",
  "phq2_positive" = "Binary positive screen (1=Yes, 0=No): phq2_total >= 3 indicates likely depression, further evaluation needed.",

  # GAD-2 Anxiety Screening
  "gad2_nervous" = "Original item: Feeling nervous, anxious, or on edge (0-3 scale: 0=Not at all, 1=Several days, 2=More than half the days, 3=Nearly every day)",
  "gad2_worry" = "Original item: Not being able to stop or control worrying (0-3 scale: 0=Not at all, 1=Several days, 2=More than half the days, 3=Nearly every day)",
  "gad2_total" = "Sum of gad2_nervous + gad2_worry (0-6 scale). NA if either item is missing (no partial scoring).",
  "gad2_positive" = "Binary positive screen (1=Yes, 0=No): gad2_total >= 3 indicates likely anxiety, further evaluation needed.",

  # Caregiver ACEs (Individual items - all recoded: 99 'Prefer not to answer' → NA)
  "cace1_neglect" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace2_parent_loss" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace3_mental_illness" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace4_substance_abuse" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace5_domestic_violence" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace6_incarceration" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace7_emotional_abuse" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace8_physical_abuse" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace9_emotional_neglect" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",
  "cace10_sexual_abuse" = "Recoded 99 (Prefer not to answer) to NA. Binary 0=No, 1=Yes. Caregiver's childhood ACE.",

  # Caregiver ACEs Composite
  "a1_ace_total" = "Sum of cace1-cace10 after recoding 99 (Prefer not to answer) to NA (0-10 scale). NA if ANY item is missing (no partial scoring). Measures caregiver's adverse childhood experiences.",
  "a1_ace_risk_cat" = "Categorical risk level based on a1_ace_total: '0' (No ACEs), '1' (1 ACE), '2-3' (2-3 ACEs), '4+' (4+ ACEs = High Risk).",

  # Child ACEs Composite
  "child_ace_total" = "Sum of 8 child ACE items (0-8 scale). NA if ANY item is missing (no partial scoring). Measures child's current adverse childhood experiences.",
  "child_ace_risk_cat" = "Categorical risk level based on child_ace_total: '0' (No ACEs), '1' (1 ACE), '2-3' (2-3 ACEs), '4+' (4+ ACEs = High Risk)."
)

# Apply renaming to codebook FIRST (replace old names with new names)
for (old_name in names(rename_map)) {
  new_name <- rename_map[[old_name]]
  if (old_name %in% codebook$variable_name) {
    codebook$variable_name[codebook$variable_name == old_name] <- new_name
    # Update label to reflect simplified name
    codebook$variable_label[codebook$variable_name == new_name] <-
      gsub("_gsed_pf_2022", "_pf", codebook$variable_label[codebook$variable_name == new_name])
  }
}

# Apply transformations to codebook AFTER renaming
for (var in names(transformations)) {
  idx <- which(codebook$variable_name == var)
  if (length(idx) > 0) {
    codebook$transformation[idx] <- transformations[[var]]
  }
}

# Also apply renaming to child_dev_vars list for correct mapping
child_dev_vars_renamed <- child_dev_vars
for (old_name in names(rename_map)) {
  if (old_name %in% child_dev_vars_renamed) {
    child_dev_vars_renamed[child_dev_vars_renamed == old_name] <- rename_map[[old_name]]
  }
}

# Recalculate missing percentages based on ACTUAL analytic dataset (after renaming)
cat("[INFO] Recalculating missing percentages for analytic dataset...\n")
for (i in seq_len(nrow(codebook))) {
  var <- codebook$variable_name[i]
  if (var %in% names(analytic_data)) {
    n_missing <- sum(is.na(analytic_data[[var]]))
    n_total <- nrow(analytic_data)
    codebook$missing_percentage[i] <- round((n_missing / n_total) * 100, 2)
  }
}

# Add research question mapping
codebook$research_question <- NA_character_

# Map variables to research questions (using renamed variable lists)
for (i in seq_len(nrow(codebook))) {
  var <- codebook$variable_name[i]

  questions <- character()

  if (var %in% id_vars) questions <- c(questions, "Identifiers")
  if (var %in% inclusion_vars) questions <- c(questions, "Inclusion criteria")
  if (var %in% demo_vars) questions <- c(questions, "Demographics/Stratification")
  if (var %in% geo_vars) questions <- c(questions, "Geography (rural/urban)")
  if (var %in% fpl_vars) questions <- c(questions, "Q1: FPL distribution")
  if (var %in% food_vars) questions <- c(questions, "Q2-3: Food insecurity")
  if (var %in% govt_vars) questions <- c(questions, "Q4: Government services")
  if (var %in% basic_needs_vars) questions <- c(questions, "Q5: Covering basics")
  if (var %in% child_dev_vars_renamed) questions <- c(questions, "Q6: Child development")
  if (var %in% hle_vars) questions <- c(questions, "Q7: Home Learning Environment")
  if (var %in% flourish_vars) questions <- c(questions, "Q8: Flourishing Index")
  if (var %in% community_vars) questions <- c(questions, "Q9: Community/Neighborhood")
  if (var %in% ace_vars) questions <- c(questions, "Q10: ACEs")
  if (var %in% parenting_vars) questions <- c(questions, "Q11: Parenting supports")
  if (var %in% mental_health_vars) questions <- c(questions, "Mental health (stratification)")
  if (var %in% weight_vars) questions <- c(questions, "Survey weights")

  codebook$research_question[i] <- paste(unique(questions), collapse = "; ")
}

# Reorder codebook to match dataset column order
# Create ordering based on actual dataset column positions
dataset_var_order <- names(analytic_data)
codebook$order <- match(codebook$variable_name, dataset_var_order)

codebook <- codebook %>%
  dplyr::arrange(order) %>%
  dplyr::select(variable_name, variable_label, data_type,
                missing_percentage, response_options, transformation,
                research_question, category)

cat("[OK]   Created codebook with", nrow(codebook), "variables\n\n")

# ============================================================================
# EXPORT DATA
# ============================================================================

cat("===========================================\n")
cat("  Exporting Analytic Dataset\n")
cat("===========================================\n\n")

# Export to CSV
csv_file <- file.path(output_dir, "ses_analytic_dataset.csv")
cat("[INFO] Exporting to CSV...\n")
tryCatch({
  write.csv(analytic_data, csv_file, row.names = FALSE, na = "")
  cat("[OK]   Created:", csv_file, "\n")
}, error = function(e) {
  cat("[ERROR] CSV export failed:", conditionMessage(e), "\n")
})

# Export to RDS
rds_file <- file.path(output_dir, "ses_analytic_dataset.rds")
cat("[INFO] Exporting to RDS...\n")
tryCatch({
  saveRDS(analytic_data, rds_file, compress = "xz")
  cat("[OK]   Created:", rds_file, "\n")
}, error = function(e) {
  cat("[ERROR] RDS export failed:", conditionMessage(e), "\n")
})

# Export to SPSS
spss_file <- file.path(output_dir, "ses_analytic_dataset.sav")
cat("[INFO] Exporting to SPSS...\n")
tryCatch({
  haven::write_sav(analytic_data, spss_file)
  cat("[OK]   Created:", spss_file, "\n")
}, error = function(e) {
  cat("[ERROR] SPSS export failed:", conditionMessage(e), "\n")
})

# Export codebook
codebook_file <- file.path(output_dir, "ses_analytic_codebook.csv")
cat("[INFO] Exporting codebook...\n")
tryCatch({
  write.csv(codebook, codebook_file, row.names = FALSE, na = "")
  cat("[OK]   Created:", codebook_file, "\n")
}, error = function(e) {
  cat("[ERROR] Codebook export failed:", conditionMessage(e), "\n")
})

# ============================================================================
# SUMMARY STATISTICS
# ============================================================================

cat("\n===========================================\n")
cat("  Dataset Summary\n")
cat("===========================================\n\n")

cat("Sample size:", nrow(analytic_data), "participants\n")
cat("Variables:", ncol(analytic_data), "\n\n")

# Age distribution
cat("Age distribution:\n")
age_summary <- summary(analytic_data$years_old)
print(age_summary)
cat("\n")

# FPL distribution
if ("fplcat" %in% names(analytic_data)) {
  cat("FPL categories:\n")
  print(table(analytic_data$fplcat, useNA = "ifany"))
  cat("\n")
}

# Rural/Urban distribution
if ("urban_rural" %in% names(analytic_data)) {
  cat("Rural/Urban distribution:\n")
  print(table(analytic_data$urban_rural, useNA = "ifany"))
  cat("\n")
}

# Education distribution
if ("educ_mom" %in% names(analytic_data)) {
  cat("Maternal education:\n")
  print(table(analytic_data$educ_mom, useNA = "ifany"))
  cat("\n")
}

cat("===========================================\n")
cat("  Export Complete!\n")
cat("===========================================\n")
cat("Files saved to:", normalizePath(output_dir), "\n")
cat("===========================================\n")
