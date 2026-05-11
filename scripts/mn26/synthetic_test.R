# ==============================================================================
# MN26 Synthetic Data Pipeline Test
# ==============================================================================
# Generates synthetic MN26 data using KidsightsPublic::simulate_responses()
# and runs the full pipeline (pivot → transform → eligibility → scoring).
#
# Usage:
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/mn26/synthetic_test.R
# ==============================================================================

cat("\n========================================\n")
cat("MN26 Synthetic Data Pipeline Test\n")
cat("========================================\n\n")

library(KidsightsPublic)
library(dplyr)

set.seed(42)

# --- Configuration -----------------------------------------------------------
N_HOUSEHOLDS <- 500
N_CHILD2     <- 50   # households with a second child
MN_ZIPS      <- c("55101", "55102", "55401", "55402", "55403", "55408",
                   "55414", "55455", "55901", "55912", "56001", "56301")

# ==============================================================================
# STEP 1: Generate synthetic item responses
# ==============================================================================
cat("Step 1: Generating synthetic item responses...\n")

# Ages: uniform 0-5 years for child 1
ages_c1 <- runif(N_HOUSEHOLDS, min = 0.1, max = 5.0)

# Simulate GRM responses (264 items in equate lexicon)
sim_data <- KidsightsPublic::simulate_responses(
  years_old = ages_c1,
  seed = 42
)

cat("  Simulated: ", nrow(sim_data), " records, ", ncol(sim_data), " columns\n")

# ==============================================================================
# STEP 2: Map equate IDs → MN26 column names (lowercase)
# ==============================================================================
cat("Step 2: Mapping equate IDs to MN26 column names...\n")

cl <- KidsightsPublic::codebook_lookup
mn26_map <- cl[cl$lexicon == "mn26", ]

# Build rename vector: equate_id → lowercase mn26 column name
rename_vec <- setNames(tolower(mn26_map$column_name), mn26_map$equate_id)

# Rename item columns (keep id and years_old as-is)
item_cols <- setdiff(names(sim_data), c("id", "years_old"))
for (old_name in item_cols) {
  if (old_name %in% names(rename_vec)) {
    new_name <- rename_vec[[old_name]]
    names(sim_data)[names(sim_data) == old_name] <- new_name
  } else {
    # Keep equate name lowercase for items without mn26 mapping
    names(sim_data)[names(sim_data) == old_name] <- tolower(old_name)
  }
}

n_mapped <- sum(item_cols %in% names(rename_vec))
cat("  Mapped: ", n_mapped, " of ", length(item_cols), " items to MN26 names\n")

# ==============================================================================
# STEP 3: Generate synthetic demographic/eligibility fields
# ==============================================================================
cat("Step 3: Generating demographic and eligibility fields...\n")

synthetic <- sim_data %>%
  dplyr::rename(record_id = id) %>%
  dplyr::mutate(
    # Identifiers
    pid = "9999",
    redcap_event_name = "baseline_arm_1",
    # survey_link is the join key against id_xwalk (NORC pattern; one URL per
    # REDCap record). Use record_id as a deterministic stand-in for the URL slug.
    survey_link = paste0("syn_url_", record_id),
    retrieved_date = Sys.time(),
    source_project = "mn26_synthetic_test",
    extraction_id = paste0("syn_", format(Sys.time(), "%Y%m%d")),

    # Age (convert years to days for pipeline). Date-class so dob_n <= consent_date_n
    # in norc_elig_screen() compares as Dates, not lexically (issue #16 V2).
    age_in_days_n = round(years_old * 365.25),
    dob_n = Sys.Date() - age_in_days_n,
    consent_date_n = Sys.Date(),

    # NORC eligibility form fields (default: single child u6, MN-born, parent/guardian).
    # Step 4 below overrides c2 households to scenario 3a (both kids eligible).
    kids_u6_n = 1L,
    mn_birth_c1_n = 1L,
    mn_birth_c2_n = NA_integer_,           # NA when kids_u6_n == 1 (issue #16 V3)
    parent_guardian_c1_n = 1L,
    parent_guardian_c2_n = NA_integer_,
    eligibility_form_norc_complete = 2L,

    # Survey completion: module_9 = 2 → last_module_complete = "Compensation",
    # so survey_complete = TRUE for all eligible synthetic households.
    module_9_compensation_information_complete = 2L,

    # Eligibility (legacy 4-criterion fields; retained for any code path that still reads them)
    eq001 = 1L,
    eq002 = 1L,
    eq003 = 1L,
    mn_eqstate = 1L,

    # Child sex (random)
    cqr009 = sample(c(0L, 1L), N_HOUSEHOLDS, replace = TRUE),

    # Child race (one category per child)
    cqr010b___100 = 0L, cqr010b___101 = 0L, cqr010b___102 = 0L,
    cqr010b___103 = 0L, cqr010b___104 = 0L, cqr010b___105 = 0L,
    cqr011 = sample(c(0L, 1L), N_HOUSEHOLDS, replace = TRUE, prob = c(0.75, 0.25)),

    # Caregiver demographics
    mn2 = sample(c(0L, 1L, 97L), N_HOUSEHOLDS, replace = TRUE, prob = c(0.65, 0.30, 0.05)),
    cqr003 = sample(19:45, N_HOUSEHOLDS, replace = TRUE),
    cqr004 = sample(0:8, N_HOUSEHOLDS, replace = TRUE),
    cqr008 = 0L,  # Biological parent
    cqfa001 = sample(0:5, N_HOUSEHOLDS, replace = TRUE),

    # Caregiver race
    sq002b___100 = 0L, sq002b___101 = 0L, sq002b___102 = 0L,
    sq002b___103 = 0L, sq002b___104 = 0L, sq002b___105 = 0L,
    sq003 = sample(c(0L, 1L), N_HOUSEHOLDS, replace = TRUE, prob = c(0.75, 0.25)),

    # Geographic
    sq001 = sample(MN_ZIPS, N_HOUSEHOLDS, replace = TRUE),

    # Income/SES
    cqr006 = sample(seq(10000, 200000, by = 5000), N_HOUSEHOLDS, replace = TRUE),
    fqlive1_1 = sample(1:6, N_HOUSEHOLDS, replace = TRUE),
    fqlive1_2 = sample(0:3, N_HOUSEHOLDS, replace = TRUE)
  )

# Assign random race category (one per child/caregiver)
race_cols_child <- paste0("cqr010b___", 100:105)
race_cols_parent <- paste0("sq002b___", 100:105)
for (i in 1:N_HOUSEHOLDS) {
  synthetic[i, sample(race_cols_child, 1)] <- 1L
  synthetic[i, sample(race_cols_parent, 1)] <- 1L
}

cat("  Demographics generated for ", N_HOUSEHOLDS, " households\n")

# ==============================================================================
# STEP 4: Generate child 2 records (wide format _c2 columns)
# ==============================================================================
cat("Step 4: Generating child 2 records...\n")

# Select households that will have child 2
c2_idx <- sample(1:N_HOUSEHOLDS, N_CHILD2)

# Generate child 2 ages
ages_c2 <- runif(N_CHILD2, min = 0.1, max = 5.0)

# Simulate child 2 item responses
sim_c2 <- KidsightsPublic::simulate_responses(
  years_old = ages_c2,
  seed = 123
)

# Rename to MN26 names
c2_item_cols <- setdiff(names(sim_c2), c("id", "years_old"))
for (old_name in c2_item_cols) {
  if (old_name %in% names(rename_vec)) {
    new_name <- rename_vec[[old_name]]
    names(sim_c2)[names(sim_c2) == old_name] <- new_name
  } else {
    names(sim_c2)[names(sim_c2) == old_name] <- tolower(old_name)
  }
}

# Add _c2 suffix to child 2 item columns and demographics
# Initialize all _c2 columns as NA for the full dataset
c2_item_names <- setdiff(names(sim_c2), c("id", "years_old"))
for (col in c2_item_names) {
  synthetic[[paste0(col, "_c2")]] <- NA
}
synthetic$dob_c2_n <- as.Date(NA)        # Date-class to match dob_n (V2)
synthetic$age_in_days_c2_n <- NA_real_
synthetic$cqr009_c2 <- NA_integer_
synthetic$cqr011_c2 <- NA_integer_
for (rc in paste0("cqr010_c2b___", 100:105)) {
  synthetic[[rc]] <- NA_integer_
}

# Fill child 2 data for selected households
for (k in seq_along(c2_idx)) {
  i <- c2_idx[k]
  synthetic$dob_c2_n[i] <- Sys.Date() - round(ages_c2[k] * 365.25)
  synthetic$age_in_days_c2_n[i] <- round(ages_c2[k] * 365.25)
  synthetic$cqr009_c2[i] <- sample(c(0L, 1L), 1)
  synthetic$cqr011_c2[i] <- sample(c(0L, 1L), 1, prob = c(0.75, 0.25))

  # NORC fields: promote to scenario 3a (2 kids u6, both MN-born → both eligible).
  # Keeps the existing n_eligible == n_total assertion below valid.
  synthetic$kids_u6_n[i] <- 2L
  synthetic$mn_birth_c2_n[i] <- 2L
  synthetic$parent_guardian_c2_n[i] <- 1L

  # Race for child 2
  c2_race_cols <- paste0("cqr010_c2b___", 100:105)
  for (rc in c2_race_cols) synthetic[[rc]][i] <- 0L
  synthetic[[sample(c2_race_cols, 1)]][i] <- 1L

  # Item responses for child 2
  for (col in c2_item_names) {
    synthetic[[paste0(col, "_c2")]][i] <- sim_c2[[col]][k]
  }
}

cat("  Child 2 added for ", N_CHILD2, " households\n")
cat("  Total columns: ", ncol(synthetic), "\n")

# ==============================================================================
# STEP 4.5: Build synthetic id_xwalk (NORC P_SUID crosswalk for Step 2.5)
# ==============================================================================
# Step 2.5 of the orchestrator unconditionally calls apply_norc_replace_records(),
# which requires a P_SUID crosswalk. Build one in tempdir() that matches every
# synthetic record_id under pid 9999 with no smoke cases and no reissues.
cat("Step 4.5: Building synthetic id_xwalk...\n")

id_xwalk_synthetic <- data.frame(
  P_SUID      = paste0("SYN_", synthetic$record_id),
  P_PIN       = paste0("PIN", synthetic$record_id),
  survey_link = paste0("syn_url_", synthetic$record_id),
  PID         = 9999L,                       # matches synthetic$pid = "9999"
  smoke_case  = FALSE,
  record_id   = as.integer(synthetic$record_id),
  stringsAsFactors = FALSE
)
xwalk_path <- file.path(tempdir(), "synthetic_id_xwalk.rds")
saveRDS(id_xwalk_synthetic, xwalk_path)
cat("  Saved: ", xwalk_path, " (", nrow(id_xwalk_synthetic), " rows)\n", sep = "")

# ==============================================================================
# STEP 5: Run MN26 pipeline (pivot → transform → eligibility → scoring)
# ==============================================================================
cat("\nStep 5: Running MN26 pipeline on synthetic data...\n\n")

source("pipelines/orchestration/mn26_pipeline.R")

result <- run_mn26_pipeline(
  config_path = "config/sources/mn26.yaml",
  skip_database = TRUE,
  data = synthetic,
  id_xwalk_path = xwalk_path
)

# ==============================================================================
# STEP 6: Validation
# ==============================================================================
cat("\n========================================\n")
cat("Validation\n")
cat("========================================\n\n")

td <- result$data
n_total <- nrow(td)
n_c1 <- sum(td$child_num == 1, na.rm = TRUE)
n_c2 <- sum(td$child_num == 2, na.rm = TRUE)

# Check 1: Pivot row counts
cat(sprintf("Pivot: %d total (%d child 1 + %d child 2)\n", n_total, n_c1, n_c2))
stopifnot(n_c1 == N_HOUSEHOLDS)
stopifnot(n_c2 == N_CHILD2)
cat("  [OK] Pivot counts correct\n")

# Check 2: Eligibility
n_eligible <- sum(td$eligible, na.rm = TRUE)
cat(sprintf("Eligible: %d of %d\n", n_eligible, n_total))
stopifnot(n_eligible == n_total)
cat("  [OK] All synthetic records eligible\n")

# Check 2.5: NORC sample + meets_inclusion (added with Step 2.5 alignment)
n_meets_inc <- sum(td$meets_inclusion %in% TRUE)
cat(sprintf("Meets inclusion: %d of %d\n", n_meets_inc, n_total))
stopifnot(n_meets_inc == n_total)
cat("  [OK] All synthetic records meet inclusion (eligible & survey_complete)\n")

# Confirm scenario distribution: 450 single-child (type 1) + 50 multi-child (type 3a).
# elig_type lives at HH level pre-pivot; in the pivoted long table both child rows
# of a 3a HH carry the same elig_type, so we count distinct (record_id) per type.
hh_types <- unique(td[, c("record_id", "elig_type")])
n_type_1  <- sum(hh_types$elig_type == "1",  na.rm = TRUE)
n_type_3a <- sum(hh_types$elig_type == "3a", na.rm = TRUE)
cat(sprintf("Scenario distribution: type_1 = %d, type_3a = %d\n", n_type_1, n_type_3a))
stopifnot(n_type_1 == N_HOUSEHOLDS - N_CHILD2)
stopifnot(n_type_3a == N_CHILD2)
cat("  [OK] NORC scenario assignment matches synthetic design\n")

# Check 3: Scoring
if ("kidsights_theta" %in% names(td)) {
  n_scored <- sum(!is.na(td$kidsights_theta))
  cat(sprintf("Kidsights scored: %d of %d\n", n_scored, n_total))

  if (n_scored > 0) {
    theta_range <- range(td$kidsights_theta, na.rm = TRUE)
    cat(sprintf("  Theta range: [%.2f, %.2f]\n", theta_range[1], theta_range[2]))

    # Check age gradient (older children should score higher on average)
    age_cor <- cor(td$years_old, td$kidsights_theta, use = "complete.obs")
    cat(sprintf("  Age-theta correlation: %.3f\n", age_cor))
    stopifnot(age_cor > 0.3)
    cat("  [OK] Positive age gradient confirmed\n")
  } else {
    cat("  [WARN] No children scored (CmdStan may not be available)\n")
  }
} else {
  cat("  [WARN] kidsights_theta column not present\n")
}

cat(sprintf("\nTotal duration: %.1f seconds\n", result$metrics$total_duration))
cat("\n========================================\n")
cat("Synthetic test PASSED\n")
cat("========================================\n")
