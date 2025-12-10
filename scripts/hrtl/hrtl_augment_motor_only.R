################################################################################
# HRTL: Augment Motor Development Only (NE25 + NSCH 2022)
################################################################################
# Combines NE25 and NSCH 2022 data ONLY for Motor Development items
# to get better calibrations for DrawFace, DrawPerson, BounceBall
################################################################################

library(dplyr)
library(duckdb)

message("=== HRTL Motor Development Augmentation (NE25 + NSCH 2022) ===\n")

# ==============================================================================
# 1. LOAD DATA
# ==============================================================================
message("1. Loading NE25 and NSCH 2022 Motor Development data...\n")

con <- duckdb::dbConnect(duckdb::duckdb(),
                         dbdir = "data/duckdb/kidsights_local.duckdb",
                         read_only = TRUE)

# NE25: Motor Development items only (all ages)
ne25_motor <- DBI::dbReadTable(con, "ne25_transformed") %>%
  dplyr::filter(meets_inclusion == TRUE) %>%
  dplyr::select(pid, record_id, years_old,
                nom042x, nom029x, nom033x, nom034x) %>%
  dplyr::mutate(
    source = "ne25",
    SC_AGE_YEARS = floor(years_old)
  ) %>%
  dplyr::select(source, SC_AGE_YEARS, nom042x, nom029x, nom033x, nom034x)

# NSCH 2022: Motor Development items only (ages 0-5)
nsch_motor <- DBI::dbReadTable(con, "nsch_2022") %>%
  dplyr::filter(!is.na(SC_AGE_YEARS), SC_AGE_YEARS >= 0, SC_AGE_YEARS <= 5) %>%
  dplyr::select(DrawCircle_22, DrawFace_22, DrawPerson_22, BounceBall_22, SC_AGE_YEARS) %>%
  dplyr::mutate(
    source = "nsch_2022"
  ) %>%
  # Recode NSCH to 0-based (subtract 1 from all values)
  dplyr::mutate(
    DrawCircle_22 = if_else(!is.na(DrawCircle_22) & DrawCircle_22 != 99, DrawCircle_22 - 1, DrawCircle_22),
    DrawFace_22 = if_else(!is.na(DrawFace_22) & DrawFace_22 != 99, DrawFace_22 - 1, DrawFace_22),
    DrawPerson_22 = if_else(!is.na(DrawPerson_22) & DrawPerson_22 != 99, DrawPerson_22 - 1, DrawPerson_22),
    BounceBall_22 = if_else(!is.na(BounceBall_22) & BounceBall_22 != 99, BounceBall_22 - 1, BounceBall_22)
  ) %>%
  dplyr::rename(
    nom042x = DrawCircle_22,
    nom029x = DrawFace_22,
    nom033x = DrawPerson_22,
    nom034x = BounceBall_22
  ) %>%
  dplyr::select(source, SC_AGE_YEARS, nom042x, nom029x, nom033x, nom034x)

duckdb::dbDisconnect(con, shutdown = TRUE)

message(sprintf("  NE25 Motor Development: %d records (ages %d-%d)\n",
                nrow(ne25_motor),
                floor(min(ne25_motor$SC_AGE_YEARS)), floor(max(ne25_motor$SC_AGE_YEARS))))
message(sprintf("  NSCH Motor Development: %d records (ages %d-%d)\n",
                nrow(nsch_motor),
                min(nsch_motor$SC_AGE_YEARS), max(nsch_motor$SC_AGE_YEARS)))

# ==============================================================================
# 2. VERIFY RECODING AND AGE CORRELATIONS
# ==============================================================================
message("\n2. Verifying item ranges and age correlations...\n")

motor_items <- c("nom042x", "nom029x", "nom033x", "nom034x")
item_names <- c("DrawCircle", "DrawFace", "DrawPerson", "BounceBall")

for (i in seq_along(motor_items)) {
  item <- motor_items[i]
  name <- item_names[i]

  ne25_vals <- ne25_motor[[item]][!is.na(ne25_motor[[item]])]
  nsch_vals <- nsch_motor[[item]][!is.na(nsch_motor[[item]])]

  message(sprintf("%s (%s):", name, item))
  message(sprintf("  NE25: min=%.0f, max=%.0f, n=%d",
                 min(ne25_vals), max(ne25_vals), length(ne25_vals)))
  message(sprintf("  NSCH: min=%.0f, max=%.0f, n=%d",
                 min(nsch_vals), max(nsch_vals), length(nsch_vals)))

  # Test correlations
  ne25_data <- data.frame(item = ne25_vals, age = ne25_motor$SC_AGE_YEARS[!is.na(ne25_motor[[item]])])
  nsch_data <- data.frame(item = nsch_vals, age = nsch_motor$SC_AGE_YEARS[!is.na(nsch_motor[[item]])])

  ne25_cor <- cor(ne25_data$item, ne25_data$age)
  nsch_cor <- cor(nsch_data$item, nsch_data$age)

  message(sprintf("  NE25 age correlation: r = %.3f %s", ne25_cor, if (ne25_cor > 0) "(OK)" else "(NEGATIVE)"))
  message(sprintf("  NSCH age correlation: r = %.3f %s\n", nsch_cor, if (nsch_cor > 0) "(OK)" else "(NEGATIVE)"))
}

# ==============================================================================
# 3. COMBINE DATASETS
# ==============================================================================
message("\n3. Combining NE25 and NSCH Motor Development data...\n")

augmented_motor <- dplyr::bind_rows(ne25_motor, nsch_motor)

message(sprintf("Combined Motor Development dataset: %d records\n", nrow(augmented_motor)))
message(sprintf("  NE25: %d (%.1f%%)\n",
               sum(augmented_motor$source == "ne25"),
               100*sum(augmented_motor$source == "ne25")/nrow(augmented_motor)))
message(sprintf("  NSCH: %d (%.1f%%)\n",
               sum(augmented_motor$source == "nsch_2022"),
               100*sum(augmented_motor$source == "nsch_2022")/nrow(augmented_motor)))

# ==============================================================================
# 4. SAVE AUGMENTED MOTOR DEVELOPMENT DATASET
# ==============================================================================
message("4. Saving augmented Motor Development dataset...\n")
saveRDS(augmented_motor, "scripts/temp/hrtl_augmented_motor_ne25_nsch2022.rds")
message("[OK] Saved to scripts/temp/hrtl_augmented_motor_ne25_nsch2022.rds\n")

message("[OK] Motor Development augmentation complete!")
