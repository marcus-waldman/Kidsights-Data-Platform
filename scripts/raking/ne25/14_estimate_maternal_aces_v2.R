# Phase 3, Task 3.3: Estimate Maternal ACEs
# 3 estimands: 0 ACEs, 1 ACE, 2+ ACEs
# Using ALL adults in North Central (parent linkage has data issues)

library(survey)
library(dplyr)
library(mirt)
library(DBI)
library(duckdb)

cat("\n========================================\n")
cat("Task 3.3: Estimate Maternal ACEs\n")
cat("========================================\n\n")

# 1. Load adult ACE data directly from database
cat("[1] Loading ACE data (North Central adults, ages 18-44)...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Get adults of childbearing age NATIONALLY with ACE data
# (North Central has data quality issue - all 0s)
adult_aces <- DBI::dbGetQuery(con, "
  SELECT
    YEAR, SERIAL, PERNUM, REGION,
    AGE, SEX,
    VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
    ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED,
    SAMPWEIGHT, PSU, STRATA
  FROM nhis_raw
  WHERE AGE BETWEEN 18 AND 44
    AND SEX = 2
    AND VIOLENEV IS NOT NULL
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total women ages 18-44 with ACE data:", nrow(adult_aces), "\n")
cat("    Years:", paste(sort(unique(adult_aces$YEAR)), collapse = ", "), "\n")
cat("    NOTE: Using national data (North Central region has data quality issue)\n")

# 2. Prepare ACE binary matrix
cat("\n[2] Preparing ACE binary items (8 items, 0/1 coding)...\n")

ace_vars <- c("VIOLENEV", "JAILEV", "MENTDEPEV", "ALCDRUGEV",
              "ADLTPUTDOWN", "UNFAIRRACE", "UNFAIRSEXOR", "BASENEED")

ace_items <- matrix(NA, nrow = nrow(adult_aces), ncol = 8)
colnames(ace_items) <- c("Violence", "Incarceration", "MentalIllness", "SubstanceAbuse",
                         "PutDown", "RaceDiscrim", "SexDiscrim", "BasicNeeds")

for (i in 1:8) {
  var <- ace_vars[i]
  # IPUMS/NHIS: 0=No, 1=Yes, 2=Unknown-refused, 7/8/9=Missing
  # Keep only 0/1, set rest to NA
  ace_items[, i] <- ifelse(adult_aces[[var]] %in% c(0, 1), adult_aces[[var]], NA)
}

# Report missingness
cat("    Item-level coverage:\n")
for (i in 1:8) {
  n_valid <- sum(!is.na(ace_items[, i]))
  pct <- round(n_valid / nrow(ace_items) * 100, 1)
  n_yes <- sum(ace_items[, i] == 1, na.rm = TRUE)
  pct_yes <- round(n_yes / n_valid * 100, 1)
  cat("      ", colnames(ace_items)[i], ": ", n_valid, " (", pct, "%), ",
      n_yes, " Yes (", pct_yes, "%)\n", sep = "")
}

# 3. Fit Rasch model
cat("\n[3] Fitting Rasch model...\n")
ace_model <- mirt::mirt(ace_items, model = 1, itemtype = 'Rasch', verbose = FALSE)
cat("    Model fitted\n")

# 4. EAPsum scores
cat("\n[4] Computing EAPsum scores...\n")
ace_eapsum <- mirt::fscores(ace_model, method = "EAPsum")[, 1]

cat("    Min:", round(min(ace_eapsum, na.rm = TRUE), 2), "\n")
cat("    Mean:", round(mean(ace_eapsum, na.rm = TRUE), 2), "\n")
cat("    Max:", round(max(ace_eapsum, na.rm = TRUE), 2), "\n")

# 5. Categorize
cat("\n[5] Categorizing into 0, 1, 2+ ACEs...\n")
adult_aces$ace_category <- case_when(
  ace_eapsum < 0.5 ~ "0 ACEs",
  ace_eapsum < 1.5 ~ "1 ACE",
  ace_eapsum >= 1.5 ~ "2+ ACEs"
)

print(table(adult_aces$ace_category))

# 6. Survey design
cat("\n[6] Creating survey design...\n")
ace_design <- survey::svydesign(
  ids = ~PSU,
  strata = ~STRATA,
  weights = ~SAMPWEIGHT,
  data = adult_aces[!is.na(adult_aces$ace_category), ],
  nest = TRUE
)

# 7. Estimate with year effects
cat("\n[7] Estimating proportions (year main effects)...\n")

categories <- c("0 ACEs", "1 ACE", "2+ ACEs")
raw_est <- numeric(3)

for (i in 1:3) {
  ace_design$variables$y <- as.numeric(ace_design$variables$ace_category == categories[i])
  m <- survey::svyglm(y ~ YEAR, design = ace_design, family = quasibinomial())
  raw_est[i] <- predict(m, newdata = data.frame(YEAR = 2023), type = "response")[1]
}

# Normalize
ace_est <- raw_est / sum(raw_est)

cat("\n    Estimates at 2023:\n")
for (i in 1:3) cat("      ", categories[i], ": ", round(ace_est[i], 4),
                    " (", round(ace_est[i] * 100, 1), "%)\n", sep = "")

# 8. Create result
ace_result <- data.frame(
  age = rep(0:5, each = 3),
  estimand = rep(categories, 6),
  estimate = rep(ace_est, 6)
)

# 9. Save
saveRDS(ace_result, "data/raking/ne25/ace_estimates.rds")

cat("\n========================================\n")
cat("Task 3.3 Complete\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - 0 ACEs:", round(ace_est[1] * 100, 1), "%\n")
cat("  - 1 ACE:", round(ace_est[2] * 100, 1), "%\n")
cat("  - 2+ ACEs:", round(ace_est[3] * 100, 1), "%\n\n")
