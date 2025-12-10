################################################################################
# HRTL: Prepare Augmented Dataset (NE25 + NSCH 2022) with Item Recoding
################################################################################
# Combines NE25 and NSCH 2022 data for better Rasch calibration
# Recodes items to start at 0 and validates positive age correlation
################################################################################

library(dplyr)
library(duckdb)

message("=== HRTL Augmented Dataset Preparation ===\n")

# ==============================================================================
# 1. LOAD DATA
# ==============================================================================
message("1. Loading NE25 and NSCH 2022 data...\n")

# Define HRTL items list early for recoding
hrtl_items <- c(
  # Early Learning
  "nom2205", "nom002x", "nom014x", "nom017x", "nom018x", "nom024x", "nom026x", "nom005x", "nom003x",
  # Social-Emotional
  "nom2202", "nom049x", "nom2208", "nom059", "nom053x", "nom006x",
  # Self-Regulation
  "nom054x", "nom052y", "nom062y", "nom056x", "nom060y",
  # Motor
  "nom042x", "nom029x", "nom033x", "nom034x",
  # Health
  "cqfa002", "nom046x"
)

con <- duckdb::dbConnect(duckdb::duckdb(),
                         dbdir = "data/duckdb/kidsights_local.duckdb",
                         read_only = TRUE)

# NE25: All meets_inclusion=TRUE
ne25_full <- DBI::dbReadTable(con, "ne25_transformed") %>%
  dplyr::filter(meets_inclusion == TRUE) %>%
  dplyr::select(pid, record_id, years_old,
                # Early Learning (9 items)
                nom2205, nom002x, nom014x, nom017x, nom018x, nom024x, nom026x, nom005x, nom003x,
                # Social-Emotional (6 items)
                nom2202, nom049x, nom2208, nom059, nom053x, nom006x,
                # Self-Regulation (5 items)
                nom054x, nom052y, nom062y, nom056x, nom060y,
                # Motor (4 items)
                nom042x, nom029x, nom033x, nom034x,
                # Health (2 items + derived)
                cqfa002, nom046x) %>%
  dplyr::mutate(
    source = "ne25",
    SC_AGE_YEARS = floor(years_old)
  )

# NSCH 2022: Ages 0-5 only (match HRTL age range)
nsch_full <- DBI::dbReadTable(con, "nsch_2022") %>%
  dplyr::filter(!is.na(SC_AGE_YEARS), SC_AGE_YEARS >= 0, SC_AGE_YEARS <= 5) %>%
  dplyr::select(
    # Early Learning (use CAHMI-coded names)
    RecogBegin_22, SameSound_22, RhymeWordR_22, RecogLetter_22, WriteName_22,
    ReadOneDigit_22, CountToR_22, GroupOfObjects_22, SimpleAddition_22,
    # Social-Emotional
    ClearExp_22, NameEmotions_22, ShareToys_22, PlayWell_22, HurtSad_22, FocusOn_22,
    # Self-Regulation
    StartNewAct_22, CalmDownR_22, WaitForTurn_22, distracted_22, temperR_22,
    # Motor
    DrawCircle_22, DrawFace_22, DrawPerson_22, BounceBall_22,
    # Health
    K2Q01, K2Q01_D, DailyAct_22, SC_AGE_YEARS
  ) %>%
  dplyr::mutate(
    source = "nsch_2022"
  ) %>%
  dplyr::rename(
    nom2205 = RecogBegin_22,
    nom002x = SameSound_22,
    nom014x = RhymeWordR_22,
    nom017x = RecogLetter_22,
    nom018x = WriteName_22,
    nom024x = ReadOneDigit_22,
    nom026x = CountToR_22,
    nom005x = GroupOfObjects_22,
    nom003x = SimpleAddition_22,
    nom2202 = ClearExp_22,
    nom049x = NameEmotions_22,
    nom2208 = ShareToys_22,
    nom059 = PlayWell_22,
    nom053x = HurtSad_22,
    nom006x = FocusOn_22,
    nom054x = StartNewAct_22,
    nom052y = CalmDownR_22,
    nom062y = WaitForTurn_22,
    nom056x = distracted_22,
    nom060y = temperR_22,
    nom042x = DrawCircle_22,
    nom029x = DrawFace_22,
    nom033x = DrawPerson_22,
    nom034x = BounceBall_22,
    cqfa002 = K2Q01,
    nom046x = K2Q01_D
  ) %>%
  dplyr::select(-DailyAct_22) %>%  # Don't need derived variable from NSCH
  # Recode NSCH items: subtract 1 from all items to make 0-based
  dplyr::mutate(
    across(all_of(hrtl_items),
           function(x) {
             # If value is not missing and not 99, subtract 1
             dplyr::if_else(!is.na(x) & x != 99, x - 1, x)
           })
  ) %>%
  # Recode health items: 99 (no answer) → NA
  dplyr::mutate(
    cqfa002 = dplyr::if_else(cqfa002 == 99, NA_real_, cqfa002),
    nom046x = dplyr::if_else(nom046x == 99, NA_real_, nom046x)
  )

duckdb::dbDisconnect(con, shutdown = TRUE)

message(sprintf("  NE25 records: %d (ages %d-%d)\n", nrow(ne25_full),
                floor(min(ne25_full$years_old)), floor(max(ne25_full$years_old))))
message(sprintf("  NSCH records: %d (ages %d-%d)\n", nrow(nsch_full),
                min(nsch_full$SC_AGE_YEARS), max(nsch_full$SC_AGE_YEARS)))

# ==============================================================================
# 2. CHECK ITEM RESPONSE RANGES
# ==============================================================================
message("\n2. Checking item response ranges in both datasets...\n")

recoding_needed <- data.frame()

for (item in hrtl_items) {
  # Get ranges from both datasets
  ne25_vals <- ne25_full[[item]][!is.na(ne25_full[[item]])]
  nsch_vals <- nsch_full[[item]][!is.na(nsch_full[[item]])]

  if (length(ne25_vals) > 0 && length(nsch_vals) > 0) {
    ne25_min <- min(ne25_vals)
    ne25_max <- max(ne25_vals)
    nsch_min <- min(nsch_vals)
    nsch_max <- max(nsch_vals)

    message(sprintf("%s:", item))
    message(sprintf("  NE25:  min=%.0f, max=%.0f (n=%d)", ne25_min, ne25_max, length(ne25_vals)))
    message(sprintf("  NSCH:  min=%.0f, max=%.0f (n=%d)", nsch_min, nsch_max, length(nsch_vals)))

    # Flag if ranges don't match or don't start at 0
    if (ne25_min != 0 || nsch_min != 0 || ne25_max != nsch_max) {
      message("  [WARN] Range mismatch or doesn't start at 0")
      recoding_needed <- rbind(recoding_needed,
                              data.frame(item = item, ne25_min = ne25_min, ne25_max = ne25_max,
                                       nsch_min = nsch_min, nsch_max = nsch_max))
    }
    message()
  }
}

if (nrow(recoding_needed) > 0) {
  message("Items requiring recoding:\n")
  print(recoding_needed)
} else {
  message("All items have consistent 0-based ranges\n")
}

# ==============================================================================
# 3. VERIFY POSITIVE AGE CORRELATIONS
# ==============================================================================
message("\n3. Verifying positive correlations between items and age...\n")

correlations <- data.frame()

for (item in hrtl_items) {
  ne25_data <- ne25_full %>%
    dplyr::select(all_of(c(item, "SC_AGE_YEARS"))) %>%
    dplyr::filter(!is.na(.[[item]]))

  nsch_data <- nsch_full %>%
    dplyr::select(all_of(c(item, "SC_AGE_YEARS"))) %>%
    dplyr::filter(!is.na(.[[item]]))

  if (nrow(ne25_data) > 2 && nrow(nsch_data) > 2) {
    ne25_cor <- cor(ne25_data[[item]], ne25_data$SC_AGE_YEARS)
    nsch_cor <- cor(nsch_data[[item]], nsch_data$SC_AGE_YEARS)

    message(sprintf("%s:", item))
    message(sprintf("  NE25 r = %.3f (%s)", ne25_cor, if (ne25_cor > 0) "OK" else "NEGATIVE"))
    message(sprintf("  NSCH r = %.3f (%s)", nsch_cor, if (nsch_cor > 0) "OK" else "NEGATIVE"))

    if (ne25_cor < 0 || nsch_cor < 0) {
      message("  [WARN] Negative correlation - may need reverse coding")
      correlations <- rbind(correlations,
                           data.frame(item = item, ne25_cor = ne25_cor, nsch_cor = nsch_cor))
    }
    message()
  }
}

if (nrow(correlations) > 0) {
  message("\nItems with negative correlations:\n")
  print(correlations)
} else {
  message("All items show positive age correlations\n")
}

# ==============================================================================
# 4. COMBINE DATASETS
# ==============================================================================
message("\n4. Combining NE25 and NSCH datasets...\n")

# Standardize column order
ne25_full <- ne25_full %>%
  dplyr::select(source, SC_AGE_YEARS, all_of(hrtl_items))

nsch_full <- nsch_full %>%
  dplyr::select(source, SC_AGE_YEARS, all_of(hrtl_items))

augmented_data <- dplyr::bind_rows(ne25_full, nsch_full)

message(sprintf("Combined dataset: %d records\n", nrow(augmented_data)))
message(sprintf("  NE25: %d (%.1f%%)", sum(augmented_data$source == "ne25"),
               100*sum(augmented_data$source == "ne25")/nrow(augmented_data)))
message(sprintf("  NSCH: %d (%.1f%%)\n", sum(augmented_data$source == "nsch_2022"),
               100*sum(augmented_data$source == "nsch_2022")/nrow(augmented_data)))

# ==============================================================================
# 5. SAVE AUGMENTED DATASET
# ==============================================================================
message("5. Saving augmented dataset...\n")
saveRDS(augmented_data, "scripts/temp/hrtl_augmented_dataset_ne25_nsch2022.rds")
message("[OK] Saved to scripts/temp/hrtl_augmented_dataset_ne25_nsch2022.rds\n")

message("[OK] Augmented dataset preparation complete!")
