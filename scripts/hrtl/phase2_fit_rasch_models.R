################################################################################
# Phase 2: Fit Rasch IRT Models per HRTL Domain
################################################################################
# Purpose: Fit separate Rasch models for each HRTL domain, create EAP 
#          conversion tables mapping CAHMI sum scores to theta/EAP values
################################################################################

library(dplyr)
library(duckdb)
library(mirt)
library(readxl)

message("=== Phase 2: Fitting Rasch Models for HRTL Domains ===\n")

# ==============================================================================
# 1. LOAD DATA
# ==============================================================================
message("1. Loading data from NE25...")

con <- duckdb::dbConnect(duckdb::duckdb(), 
                         dbdir = "data/duckdb/kidsights_local.duckdb", 
                         read_only = TRUE)
ne25_data <- DBI::dbReadTable(con, "ne25_transformed")
duckdb::dbDisconnect(con, shutdown = TRUE)

# Filter to ages 3-5 and meets_inclusion = TRUE
ne25_hrtl <- ne25_data %>%
  dplyr::filter(meets_inclusion == TRUE,
                years_old >= 3 & years_old < 6)

message(sprintf("  Total eligible (ages 3-5): %d children\n", nrow(ne25_hrtl)))

# ==============================================================================
# 2. LOAD ITEM DICTIONARY AND THRESHOLDS
# ==============================================================================
message("2. Loading HRTL item dictionary and thresholds...")

# Load from get_itemdict22.R
source("R/hrtl/get_itemdict22.R")
source("R/hrtl/get_cahmi_values_map.R")

# Get item dictionary (this will show verbose output)
itemdict22 <- get_itemdict22(ne25_hrtl, verbose = FALSE)

# Load thresholds
thresholds <- read_excel("data/reference/hrtl/HRTL-2022-Scoring-Thresholds.xlsx")

message(sprintf("  Items: %d total (28 scored + 1 not scored)\n", nrow(itemdict22)))
message("  Domains to score:")
for (domain in levels(itemdict22$domain_2022)[!is.na(levels(itemdict22$domain_2022))]) {
  n_items <- sum(itemdict22$domain_2022 == domain, na.rm = TRUE)
  message(sprintf("    - %s: %d items", domain, n_items))
}

# ==============================================================================
# 3. MAP NE25 VARIABLES TO CAHMI CODES
# ==============================================================================
message("\n3. Mapping NE25 variables to CAHMI item codes...")

# Create mapping from ne25 column names to cahmi variable names
cahmi_var_map <- data.frame(
  ne25_var = itemdict22$lex_ifa,
  cahmi_var = itemdict22$var_cahmi,
  domain = itemdict22$domain_2022,
  stringsAsFactors = FALSE
)

# Check which variables exist in NE25 data
available_vars <- intersect(tolower(cahmi_var_map$ne25_var), tolower(names(ne25_hrtl)))
message(sprintf("  Found %d/%d HRTL items in NE25 data\n", 
                length(available_vars), nrow(cahmi_var_map)))

# ==============================================================================
# 4. PREPARE DATA FOR RASCH MODELING
# ==============================================================================
message("4. Preparing domain-specific datasets for Rasch modeling...")

# Create list to store domain-specific data and models
domain_data <- list()
rasch_models <- list()
conversion_tables <- list()

domains_to_score <- levels(itemdict22$domain_2022)[!is.na(levels(itemdict22$domain_2022))]

for (domain in domains_to_score) {
  message(sprintf("\n  Domain: %s", domain))
  
  # Get items for this domain
  domain_items <- itemdict22 %>%
    dplyr::filter(domain_2022 == domain) %>%
    dplyr::pull(lex_ifa)
  
  # Select data for this domain
  domain_data_i <- ne25_hrtl %>%
    dplyr::select(pid, record_id, years_old, dplyr::all_of(tolower(domain_items)))
  
  # Calculate missingness
  item_cols <- tolower(domain_items)
  missing_pct <- mean(rowSums(is.na(domain_data_i[, item_cols])) > 0) * 100
  
  message(sprintf("    Items: %d", length(domain_items)))
  message(sprintf("    Children with any missing items: %.1f%%", missing_pct))
  message(sprintf("    Sample size: %d", nrow(domain_data_i)))
  
  # Store for later
  domain_data[[domain]] <- domain_data_i
}

message("\n5. Ready for Rasch model fitting in next step\n")

# Save domain data for Phase 2b
saveRDS(domain_data, "scripts/temp/hrtl_domain_data.rds")
saveRDS(itemdict22, "scripts/temp/hrtl_itemdict22.rds")
saveRDS(thresholds, "scripts/temp/hrtl_thresholds.rds")

message("Saved domain data to scripts/temp/hrtl_domain_data.rds")
message("Phase 2a complete - Ready for Rasch model fitting\n")

