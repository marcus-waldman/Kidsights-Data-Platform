################################################################################
# Phase 2a: Extract Domain Data and Prepare for Rasch Modeling
################################################################################

library(dplyr)
library(duckdb)
library(readxl)
library(jsonlite)

message("=== Phase 2a: Extract Domain Data for Rasch Modeling ===\n")

# ==============================================================================
# 1. LOAD NE25 DATA
# ==============================================================================
message("1. Loading NE25 data...")
con <- duckdb::dbConnect(duckdb::duckdb(), 
                         dbdir = "data/duckdb/kidsights_local.duckdb", 
                         read_only = TRUE)
ne25_data <- DBI::dbReadTable(con, "ne25_transformed")
duckdb::dbDisconnect(con, shutdown = TRUE)

# Filter to HRTL eligible (ages 2.5+ to handle age routing, meets_inclusion = TRUE)
# 30 months = 2.5 years
ne25_hrtl <- ne25_data %>%
  dplyr::filter(meets_inclusion == TRUE)

message(sprintf("  Total HRTL-eligible children (ages >= 30 months / 2.5 years): %d\n", nrow(ne25_hrtl)))

# ==============================================================================
# 2. DERIVE DAILYACT_22 FOR HEALTH DOMAIN
# ==============================================================================
message("2. Deriving DailyAct_22 (Health domain computed indicator)...")

# DailyAct_22 combines:
#   - cqr014x (HCABILITY): "How often have health conditions affected ability..."
#     Values: 0=no conditions, 1=never, 2=sometimes, 3=usually, 4=always
#   - nom044 (HCEXTENT): "To what extent do conditions affect ability..." (conditional on cqr014x)
#     Values: 0=very little, 1=somewhat, 2=a great deal
#
# Derivation logic:
#   - 0 if cqr014x ∈ {0,1} (no conditions / never affected)
#   - 1 if cqr014x = 2 (sometimes affected)
#   - 2 if cqr014x = 3 (usually affected)
#   - 3 if cqr014x = 4 (always affected)
#   - Override to 3 if nom044 = 2 (a great deal)

ne25_hrtl <- ne25_hrtl %>%
  dplyr::mutate(
    dailyact_22 = dplyr::case_when(
      is.na(cqr014x) ~ NA_real_,
      cqr014x %in% c(0, 1) ~ 0,
      cqr014x == 2 ~ 1,
      cqr014x == 3 ~ 2,
      cqr014x == 4 ~ 3,
      TRUE ~ NA_real_
    ),
    # Override with nom044 if available and indicates "a great deal"
    dailyact_22 = if_else(!is.na(nom044) & nom044 == 2, 3, dailyact_22)
  )

n_dailyact <- sum(!is.na(ne25_hrtl$dailyact_22))
message(sprintf("  DailyAct_22 derived for %d children (%.1f%%)\n",
                n_dailyact, 100 * n_dailyact / nrow(ne25_hrtl)))

# ==============================================================================
# 3. LOAD THRESHOLDS AND ITEM DICTIONARY
# ==============================================================================
message("3. Loading HRTL thresholds and item dictionary...")

thresholds <- read_excel("data/reference/hrtl/HRTL-2022-Scoring-Thresholds.xlsx")
itemdict_csv <- read.csv("data/reference/hrtl/itemdict22.csv")

message(sprintf("  Thresholds: %d rows (age-specific cutoffs)\n", nrow(thresholds)))
message(sprintf("  Item dict: %d items\n", nrow(itemdict_csv)))

# ==============================================================================
# 4. GET NE25-TO-CAHMI MAPPINGS FROM CODEBOOK
# ==============================================================================
message("4. Extracting ne25-to-cahmi22 mappings from codebook...")

codebook <- jsonlite::fromJSON("codebook/data/codebook.json")

ne25_cahmi_map <- data.frame(
  ne25 = character(),
  cahmi22 = character(),
  stringsAsFactors = FALSE
)

for (item_key in names(codebook$items)) {
  item_data <- codebook$items[[item_key]]
  if (is.list(item_data) && !is.null(item_data$lexicons)) {
    ne25_var <- item_data$lexicons$ne25
    cahmi22_var <- item_data$lexicons$cahmi22
    cahmi21_var <- item_data$lexicons$cahmi21

    if (!is.null(ne25_var) && !is.null(cahmi22_var)) {
      # Handle case where cahmi22_var is an array (e.g., ["TEMPERR", "TEMPER_R"])
      # Create one row per cahmi22 alias
      if (length(cahmi22_var) > 1) {
        for (cahmi_alias in cahmi22_var) {
          ne25_cahmi_map <- rbind(ne25_cahmi_map,
                                  data.frame(ne25 = tolower(ne25_var),
                                           cahmi22 = cahmi_alias,
                                           stringsAsFactors = FALSE))
        }
      } else {
        ne25_cahmi_map <- rbind(ne25_cahmi_map,
                                data.frame(ne25 = tolower(ne25_var),
                                         cahmi22 = cahmi22_var,
                                         stringsAsFactors = FALSE))
      }

      # ALSO add cahmi21 aliases (e.g., CALMDOWNR is in cahmi21, not cahmi22)
      if (!is.null(cahmi21_var)) {
        if (length(cahmi21_var) > 1) {
          for (cahmi_alias in cahmi21_var) {
            ne25_cahmi_map <- rbind(ne25_cahmi_map,
                                    data.frame(ne25 = tolower(ne25_var),
                                             cahmi22 = cahmi_alias,
                                             stringsAsFactors = FALSE))
          }
        } else {
          ne25_cahmi_map <- rbind(ne25_cahmi_map,
                                  data.frame(ne25 = tolower(ne25_var),
                                           cahmi22 = cahmi21_var,
                                           stringsAsFactors = FALSE))
        }
      }
    }
  }
}

message(sprintf("  Found %d ne25-cahmi22 item mappings\n", nrow(ne25_cahmi_map)))

# Debug: Check TEMPERR mapping
temper_rows <- ne25_cahmi_map %>% dplyr::filter(grepl("TEMPER", cahmi22, ignore.case = TRUE))
if (nrow(temper_rows) > 0) {
  message("  [DEBUG] TEMPERR mappings:")
  for (i in 1:nrow(temper_rows)) {
    message(sprintf("    %s -> %s", temper_rows$ne25[i], temper_rows$cahmi22[i]))
  }
} else {
  message("  [DEBUG] No TEMPERR mappings found!")
}

# ==============================================================================
# 5. BUILD DOMAIN-SPECIFIC DATASETS
# ==============================================================================
message("5. Building domain-specific datasets...")

domains <- unique(itemdict_csv$domain_2022)
domains <- domains[!is.na(domains)]

domain_datasets <- list()

for (domain in domains) {
  message(sprintf("\n  Domain: %s", domain))

  # Get CAHMI codes for this domain
  domain_cahmi_codes <- itemdict_csv %>%
    dplyr::filter(domain_2022 == domain) %>%
    dplyr::pull(lex_cahmi22)

  # Map to NE25 variable names (deduplicate with unique())
  domain_ne25_vars <- ne25_cahmi_map %>%
    dplyr::filter(toupper(cahmi22) %in% toupper(domain_cahmi_codes)) %>%
    dplyr::pull(ne25) %>%
    unique()

  # Debug Self-Regulation
  if (domain == "Self-Regulation") {
    message("  [DEBUG] Self-Reg CAHMI codes:")
    for (code in domain_cahmi_codes) {
      matching_rows <- ne25_cahmi_map %>% dplyr::filter(toupper(cahmi22) == toupper(code))
      if (nrow(matching_rows) > 0) {
        message(sprintf("    %s -> %s", code, paste(matching_rows$ne25, collapse = ", ")))
      } else {
        message(sprintf("    %s -> [NO MAPPING]", code))
      }
    }
    message(sprintf("  [DEBUG] domain_ne25_vars: %s", paste(domain_ne25_vars, collapse = ", ")))
  }
  
  # Check what's actually in NE25 data
  available <- intersect(tolower(domain_ne25_vars), tolower(names(ne25_hrtl)))
  
  message(sprintf("    CAHMI items in domain: %d", length(unique(domain_cahmi_codes))))
  message(sprintf("    Mapped to NE25 vars: %d", length(domain_ne25_vars)))
  message(sprintf("    Found in NE25 data: %d", length(available)))
  
  if (length(available) > 0) {
    # Extract domain data
    domain_data <- ne25_hrtl %>%
      dplyr::select(pid, record_id, years_old,
                    kidsights_2022, general_gsed_pf_2022,
                    dplyr::all_of(available))

    # Filter to children with at least one CAHMI item response in this domain
    # (handles age routing where not all children answered all items)
    n_before_filter <- nrow(domain_data)
    domain_data <- domain_data %>%
      dplyr::filter(rowSums(is.na(dplyr::across(dplyr::all_of(available)))) < length(available))
    n_after_filter <- nrow(domain_data)

    message(sprintf("    Children with at least one response: %d/%d (%.1f%%)",
                    n_after_filter, n_before_filter, 100*n_after_filter/n_before_filter))

    # Calculate missingness for included children (check only CAHMI items, not auxiliary columns)
    n_children_complete <- sum(rowSums(is.na(domain_data[, available])) == 0)

    message(sprintf("    Children with complete data: %d (%.1f%%)",
                    n_children_complete, 100*n_children_complete/nrow(domain_data)))

    # Check auxiliary columns
    kidsights_na <- sum(is.na(domain_data$kidsights_2022))
    gsed_na <- sum(is.na(domain_data$general_gsed_pf_2022))
    message(sprintf("    Auxiliary columns - kidsights_2022: %d missing, general_gsed_pf_2022: %d missing",
                    kidsights_na, gsed_na))

    # Special handling for Health domain: Add derived DailyAct_22
    if (domain == "Health") {
      message("    [SPECIAL] Adding derived DailyAct_22 to Health domain")

      # Add dailyact_22 to domain_data
      domain_data <- domain_data %>%
        dplyr::left_join(
          ne25_hrtl %>% dplyr::select(pid, record_id, dailyact_22),
          by = c("pid", "record_id")
        )

      # Update available variables to include dailyact_22
      available_with_derived <- c(available, "dailyact_22")

      # Recalculate completeness with 3 items
      n_children_complete_3items <- sum(rowSums(is.na(domain_data[, available_with_derived])) == 0)
      message(sprintf("    Children with complete data (3 items): %d (%.2f%%)",
                      n_children_complete_3items,
                      100 * n_children_complete_3items / nrow(domain_data)))

      # Store with updated variables list
      domain_datasets[[domain]] <- list(
        data = domain_data,
        variables = available_with_derived,
        cahmi_codes = domain_cahmi_codes
      )
    } else {
      domain_datasets[[domain]] <- list(
        data = domain_data,
        variables = available,
        cahmi_codes = domain_cahmi_codes
      )
    }
  }
}

message("\n\n6. Domain Summary:")
message(sprintf("  Domains prepared for Rasch modeling: %d", length(domain_datasets)))
for (domain in names(domain_datasets)) {
  n_items <- length(domain_datasets[[domain]]$variables)
  n_children <- nrow(domain_datasets[[domain]]$data)
  message(sprintf("    - %s: %d items, %d children", domain, n_items, n_children))
}

# ==============================================================================
# 7. SAVE FOR PHASE 2B
# ==============================================================================
message("\n7. Saving domain datasets...")

saveRDS(domain_datasets, "scripts/hrtl/hrtl_domain_datasets.rds")
saveRDS(thresholds, "scripts/hrtl/hrtl_thresholds.rds")
saveRDS(itemdict_csv, "scripts/hrtl/hrtl_itemdict_csv.rds")
saveRDS(ne25_cahmi_map, "scripts/hrtl/hrtl_ne25_cahmi_map.rds")

message("\nPhase 2a complete - Domain datasets ready for Rasch modeling")

