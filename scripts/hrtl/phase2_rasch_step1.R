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
# 1B. DERIVE DailyAct_22 (Health Domain Item 3)
# ==============================================================================
message("1B. Deriving DailyAct_22 from CQR014X (HCABILITY) and NOM044 (HCEXTENT)...")

# CQR014X coding: 0=no conditions, 1=never, 2=sometimes, 3=usually, 4=always
# NOM044 coding: 0=very little, 1=somewhat, 2=a great deal
# DailyAct_22 output: 0=no/never, 1=sometimes, 2=usually, 3=always/great deal

ne25_hrtl <- ne25_hrtl %>%
  dplyr::mutate(
    dailyact_22 = dplyr::case_when(
      is.na(cqr014x) ~ NA_real_,
      cqr014x %in% c(0, 1) ~ 0,  # No conditions or never affected
      cqr014x == 2 ~ 1,           # Sometimes affected
      cqr014x == 3 ~ 2,           # Usually affected
      cqr014x == 4 ~ 3,           # Always affected
      TRUE ~ NA_real_
    )
  ) %>%
  dplyr::mutate(
    # Override with HCEXTENT if available (handles the rare NOM044 cases)
    # NOM044=2 (a great deal) → DailyAct_22=3 (regardless of CQR014X)
    dailyact_22 = dplyr::if_else(!is.na(nom044) & nom044 == 2, 3, dailyact_22)
  )

# Verify derivation
n_dailyact <- sum(!is.na(ne25_hrtl$dailyact_22))
n_cqr <- sum(!is.na(ne25_hrtl$cqr014x))
message(sprintf("  Derived: %d records (from %d with CQR014X)\n", n_dailyact, n_cqr))

# ==============================================================================
# 2. LOAD THRESHOLDS AND ITEM DICTIONARY
# ==============================================================================
message("2. Loading HRTL thresholds and item dictionary...")

thresholds <- read_excel("data/reference/hrtl/HRTL-2022-Scoring-Thresholds.xlsx")
itemdict_csv <- read.csv("data/reference/hrtl/itemdict22.csv")

message(sprintf("  Thresholds: %d rows (age-specific cutoffs)\n", nrow(thresholds)))
message(sprintf("  Item dict: %d items\n", nrow(itemdict_csv)))

# ==============================================================================
# 3. GET NE25-TO-CAHMI MAPPINGS FROM CODEBOOK
# ==============================================================================
message("3. Extracting ne25-to-cahmi22 mappings from codebook...")

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
    if (!is.null(ne25_var) && !is.null(cahmi22_var)) {
      ne25_cahmi_map <- rbind(ne25_cahmi_map, 
                              data.frame(ne25 = tolower(ne25_var), 
                                       cahmi22 = cahmi22_var,
                                       stringsAsFactors = FALSE))
    }
  }
}

message(sprintf("  Found %d ne25-cahmi22 item mappings\n", nrow(ne25_cahmi_map)))

# Fix naming mismatch: itemdict has CALMDOWNR (no underscore) but codebook has CALMDOWN_R
# Manually add this mapping to ensure Self-Regulation domain completeness
ne25_cahmi_map <- rbind(ne25_cahmi_map,
                        data.frame(ne25 = "nom060y",
                                  cahmi22 = "CALMDOWNR",
                                  stringsAsFactors = FALSE))

message(sprintf("  Added manual mapping for CALMDOWNR (nom060y)\n"))
message(sprintf("  Total mappings after fix: %d\n", nrow(ne25_cahmi_map)))

# ==============================================================================
# 4. BUILD DOMAIN-SPECIFIC DATASETS
# ==============================================================================
message("4. Building domain-specific datasets...")

domains <- unique(itemdict_csv$domain_2022)
domains <- domains[!is.na(domains)]

domain_datasets <- list()

for (domain in domains) {
  message(sprintf("\n  Domain: %s", domain))
  
  # Get CAHMI codes for this domain
  domain_cahmi_codes <- itemdict_csv %>%
    dplyr::filter(domain_2022 == domain) %>%
    dplyr::pull(lex_cahmi22)
  
  # Map to NE25 variable names
  domain_ne25_vars <- ne25_cahmi_map %>%
    dplyr::filter(toupper(cahmi22) %in% toupper(domain_cahmi_codes)) %>%
    dplyr::pull(ne25)
  
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

    # Special handling for Health domain: add derived dailyact_22 variable
    if (domain == "Health") {
      domain_data <- domain_data %>%
        dplyr::left_join(
          ne25_hrtl %>% dplyr::select(pid, record_id, dailyact_22),
          by = c("pid", "record_id")
        )
      available_with_derived <- c(available, "dailyact_22")
      message(sprintf("    Added derived variable: dailyact_22"))
    } else {
      available_with_derived <- available
    }

    # Filter to children with at least one CAHMI item response in this domain
    # (handles age routing where not all children answered all items)
    n_before_filter <- nrow(domain_data)
    domain_data <- domain_data %>%
      dplyr::filter(rowSums(is.na(dplyr::across(dplyr::all_of(available_with_derived)))) < length(available_with_derived))
    n_after_filter <- nrow(domain_data)

    message(sprintf("    Children with at least one response: %d/%d (%.1f%%)",
                    n_after_filter, n_before_filter, 100*n_after_filter/n_before_filter))

    # Calculate missingness for included children (check only CAHMI items, not auxiliary columns)
    n_children_complete <- sum(rowSums(is.na(domain_data[, available_with_derived])) == 0)

    message(sprintf("    Children with complete data: %d (%.1f%%)",
                    n_children_complete, 100*n_children_complete/nrow(domain_data)))

    # Check auxiliary columns
    kidsights_na <- sum(is.na(domain_data$kidsights_2022))
    gsed_na <- sum(is.na(domain_data$general_gsed_pf_2022))
    message(sprintf("    Auxiliary columns - kidsights_2022: %d missing, general_gsed_pf_2022: %d missing",
                    kidsights_na, gsed_na))

    domain_datasets[[domain]] <- list(
      data = domain_data,
      variables = available_with_derived,
      cahmi_codes = domain_cahmi_codes
    )
  }
}

message("\n\n5. Domain Summary:")
message(sprintf("  Domains prepared for Rasch modeling: %d", length(domain_datasets)))
for (domain in names(domain_datasets)) {
  n_items <- length(domain_datasets[[domain]]$variables)
  n_children <- nrow(domain_datasets[[domain]]$data)
  message(sprintf("    - %s: %d items, %d children", domain, n_items, n_children))
}

# ==============================================================================
# 6. SAVE FOR PHASE 2B
# ==============================================================================
message("\n6. Saving domain datasets...")

saveRDS(domain_datasets, "scripts/temp/hrtl_domain_datasets.rds")
saveRDS(thresholds, "scripts/temp/hrtl_thresholds.rds")
saveRDS(itemdict_csv, "scripts/temp/hrtl_itemdict_csv.rds")
saveRDS(ne25_cahmi_map, "scripts/temp/hrtl_ne25_cahmi_map.rds")

message("\nPhase 2a complete - Domain datasets ready for Rasch modeling")

