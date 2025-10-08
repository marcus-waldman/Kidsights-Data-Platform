library(DBI)
library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(), 
                      dbdir = "data/duckdb/kidsights_local.duckdb",
                      read_only = TRUE)

# Check value ranges
cat("Checking ACS variable ranges...\n\n")

cat("SEX:\n")
sex_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT SEX FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5 ORDER BY SEX")
print(sex_vals)

cat("\nHISPAN:\n")
hisp_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT HISPAN FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5 ORDER BY HISPAN")
print(hisp_vals)

cat("\nRACE:\n")
race_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT RACE FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5 ORDER BY RACE")
print(race_vals)

cat("\nPOVERTY range:\n")
pov_range <- DBI::dbGetQuery(con, "SELECT MIN(POVERTY) as min_pov, MAX(POVERTY) as max_pov, COUNT(*) as n FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5")
print(pov_range)

cat("\nEDUC range:\n")
educ_range <- DBI::dbGetQuery(con, "SELECT MIN(EDUC) as min_educ, MAX(EDUC) as max_educ, COUNT(*) as n FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5")
print(educ_range)

cat("\nMARST values:\n")
marst_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT MARST FROM acs_data WHERE STATEFIP = 31 AND AGE <= 5 ORDER BY MARST")
print(marst_vals)

DBI::dbDisconnect(con, shutdown = TRUE)
