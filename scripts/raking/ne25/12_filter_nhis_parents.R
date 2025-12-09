# Phase 3, Task 3.1: Filter to North Central + West Region Parents
# Perform household linkage (parents → children 0-5) and filter to REGION = 2, 4

library(DBI)
library(duckdb)
library(dplyr)

# Source safe_left_join utility
source("R/utils/safe_joins.R")

cat("\n========================================\n")
cat("Task 3.1: Filter NHIS Parents\n")
cat("========================================\n\n")

# 1. Connect to database and load NHIS data
cat("[1] Loading NHIS data from database...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Load all NHIS data
nhis_data <- DBI::dbGetQuery(con, "SELECT * FROM nhis_raw")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total NHIS records:", nrow(nhis_data), "\n")
cat("    Years available:", paste(sort(unique(nhis_data$YEAR)), collapse = ", "), "\n")
cat("    Variables:", ncol(nhis_data), "\n")

# 2. Check REGION distribution
cat("\n[2] Checking REGION distribution...\n")

region_table <- table(nhis_data$REGION, useNA = "ifany")
cat("    REGION distribution:\n")
for (i in 1:length(region_table)) {
  region_code <- names(region_table)[i]
  count <- region_table[i]
  pct <- round(count / nrow(nhis_data) * 100, 1)

  region_name <- switch(region_code,
    "1" = "Northeast",
    "2" = "North Central/Midwest",
    "3" = "South",
    "4" = "West",
    "Unknown"
  )

  cat("      REGION", region_code, "(", region_name, "): ", count,
      " (", pct, "%)\n", sep = "")
}

# 3. Filter to North Central + West regions (REGION = 2 or 4)
cat("\n[3] Filtering to North Central + West regions (REGION = 2 or 4)...\n")

nhis_north_central <- nhis_data %>%
  dplyr::filter(REGION %in% c(2, 4))

cat("    Records in North Central + West:", nrow(nhis_north_central), "\n")
cat("    Reduction:", nrow(nhis_data) - nrow(nhis_north_central), "records removed\n")

# 4. Identify children ages 0-5
cat("\n[4] Identifying children ages 0-5...\n")

nhis_children <- nhis_north_central %>%
  dplyr::filter(AGE <= 5)

cat("    Children ages 0-5 in North Central:", nrow(nhis_children), "\n")

# Age distribution
cat("\n    Age distribution:\n")
age_table <- table(nhis_children$AGE)
for (age in 0:5) {
  if (as.character(age) %in% names(age_table)) {
    cat("      Age", age, ":", age_table[as.character(age)], "children\n")
  } else {
    cat("      Age", age, ": 0 children\n")
  }
}

# 5. Check PAR1REL variable for parent-child linkage
cat("\n[5] Checking parent-child linkage variable (PAR1REL)...\n")

# PAR1REL contains the person number of the child's parent within the household
cat("    Children with parent linkage (PAR1REL > 0):",
    sum(nhis_children$PAR1REL > 0), "\n")
cat("    Children without parent linkage (PAR1REL = 0):",
    sum(nhis_children$PAR1REL == 0), "\n")
cat("    Coverage:",
    round(sum(nhis_children$PAR1REL > 0) / nrow(nhis_children) * 100, 1), "%\n")

# 6. Perform household linkage to get parent records
cat("\n[6] Performing household linkage (children → parents)...\n")

# Strategy: For each child with PAR1REL > 0, find their parent
# Parent is identified by: same SERIAL (household) + PERNUM == child's PAR1REL

# Create parent lookup: all adults in North Central + West households
# Rename parent variables with _parent suffix to avoid collision
parent_pool <- nhis_north_central %>%
  dplyr::filter(AGE >= 18) %>%
  dplyr::select(SERIAL, PERNUM, AGE, SEX, YEAR,
                PHQINTR, PHQDEP,
                GADANX, GADWORCTRL,
                VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED,
                SAMPWEIGHT, PSU, STRATA) %>%
  dplyr::rename(
    AGE_parent = AGE,
    SEX_parent = SEX,
    PHQINTR_parent = PHQINTR,
    PHQDEP_parent = PHQDEP,
    GADANX_parent = GADANX,
    GADWORCTRL_parent = GADWORCTRL,
    VIOLENEV_parent = VIOLENEV,
    JAILEV_parent = JAILEV,
    MENTDEPEV_parent = MENTDEPEV,
    ALCDRUGEV_parent = ALCDRUGEV,
    ADLTPUTDOWN_parent = ADLTPUTDOWN,
    UNFAIRRACE_parent = UNFAIRRACE,
    UNFAIRSEXOR_parent = UNFAIRSEXOR,
    BASENEED_parent = BASENEED,
    SAMPWEIGHT_parent = SAMPWEIGHT,
    PSU_parent = PSU,
    STRATA_parent = STRATA
  )

cat("    Adult pool size:", nrow(parent_pool), "adults\n")

# Join children to their parents (no collision since parent variables renamed)
children_with_parents <- nhis_children %>%
  dplyr::filter(PAR1REL > 0) %>%
  safe_left_join(
    parent_pool,
    by_vars = c("SERIAL" = "SERIAL", "PAR1REL" = "PERNUM", "YEAR" = "YEAR")
  )

cat("    Children successfully linked to parents:",
    sum(!is.na(children_with_parents$AGE_parent)), "\n")
cat("    Children without parent match:",
    sum(is.na(children_with_parents$AGE_parent)), "\n")

# Keep only successful matches
nhis_parent_child <- children_with_parents %>%
  dplyr::filter(!is.na(AGE_parent))

cat("    Final parent-child pairs:", nrow(nhis_parent_child), "\n")

# 7. Check data availability by year
cat("\n[7] Checking data availability by year...\n")

# Check column names to see suffixes
cat("    Sample column names:", paste(head(names(nhis_parent_child), 20), collapse = ", "), "...\n")

year_summary <- nhis_parent_child %>%
  dplyr::group_by(YEAR) %>%
  dplyr::summarise(
    n_pairs = dplyr::n(),
    n_with_phq = sum(!is.na(PHQINTR_parent) & !is.na(PHQDEP_parent)),
    n_with_ace = sum(!is.na(VIOLENEV_parent)),
    .groups = "drop"
  )

cat("\n")
print(year_summary)

# 8. Check PHQ-2 data availability
cat("\n[8] Checking PHQ-2 data availability...\n")

phq_data <- nhis_parent_child %>%
  dplyr::filter(!is.na(PHQINTR_parent) & !is.na(PHQDEP_parent))

cat("    Total parent-child pairs with PHQ-2:", nrow(phq_data), "\n")
cat("    Years with PHQ-2:", paste(sort(unique(phq_data$YEAR)), collapse = ", "), "\n")

# 9. Check GAD-2 data availability
cat("\n[9] Checking GAD-2 data availability...\n")

gad_data <- nhis_parent_child %>%
  dplyr::filter(!is.na(GADANX_parent) & !is.na(GADWORCTRL_parent))

cat("    Total parent-child pairs with GAD-2:", nrow(gad_data), "\n")
cat("    Years with GAD-2:", paste(sort(unique(gad_data$YEAR)), collapse = ", "), "\n")

# 10. Check ACE data availability
cat("\n[10] Checking ACE data availability...\n")

ace_data <- nhis_parent_child %>%
  dplyr::filter(!is.na(VIOLENEV_parent))

cat("    Total parent-child pairs with ACE data:", nrow(ace_data), "\n")
cat("    Years with ACE:", paste(sort(unique(ace_data$YEAR)), collapse = ", "), "\n")

# Check each ACE variable (all have _parent suffix)
ace_vars <- c("VIOLENEV_parent", "JAILEV_parent", "MENTDEPEV_parent", "ALCDRUGEV_parent",
              "ADLTPUTDOWN_parent", "UNFAIRRACE_parent", "UNFAIRSEXOR_parent", "BASENEED_parent")

cat("\n    ACE variable availability:\n")
for (var in ace_vars) {
  n_available <- sum(!is.na(nhis_parent_child[[var]]))
  pct <- round(n_available / nrow(nhis_parent_child) * 100, 1)
  cat("      ", var, ": ", n_available, " (", pct, "%)\n", sep = "")
}

# 11. Save filtered data
cat("\n[11] Saving filtered parent-child data...\n")

# Save full parent-child linkage
saveRDS(nhis_parent_child, "data/raking/ne25/nhis_parent_child_linked.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_parent_child_linked.rds\n")

# Save PHQ-2 subset
saveRDS(phq_data, "data/raking/ne25/nhis_phq2_data.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_phq2_data.rds\n")

# Save GAD-2 subset
saveRDS(gad_data, "data/raking/ne25/nhis_gad2_data.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_gad2_data.rds\n")

# Save ACE subset
saveRDS(ace_data, "data/raking/ne25/nhis_ace_data.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_ace_data.rds\n")

# 12. Summary
cat("\n========================================\n")
cat("Task 3.1 Complete: NHIS Parents Filtered\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Regions: North Central + West (REGION = 2, 4)\n")
cat("  - Children ages 0-5:", nrow(nhis_children), "\n")
cat("  - Parent-child pairs:", nrow(nhis_parent_child), "\n")
cat("  - PHQ-2 available:", nrow(phq_data), "pairs\n")
cat("  - GAD-2 available:", nrow(gad_data), "pairs\n")
cat("  - ACE available:", nrow(ace_data), "pairs\n")
cat("  - Years: ", paste(sort(unique(nhis_parent_child$YEAR)), collapse = ", "), "\n")
cat("\nReady for estimation tasks 3.2-3.3\n\n")
