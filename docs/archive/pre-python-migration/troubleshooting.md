# Troubleshooting Guide

This guide helps diagnose and resolve common issues when running the Kidsights NE25 pipeline.

## Quick Diagnostics

### Pipeline Status Check
```r
# Check if pipeline completed successfully
source("run_ne25_pipeline.R")
# Look for final status: "✅ STATUS: SUCCESS" or "❌ STATUS: FAILED"
```

### Database Connection Test
```r
library(duckdb)
source("R/duckdb/connection.R")
con <- connect_kidsights_db()
DBI::dbListTables(con)  # Should show: ne25_raw, ne25_eligibility, ne25_harmonized, ne25_pipeline_log
disconnect_kidsights_db(con)
```

### API Credentials Test
```r
# Verify credentials file exists and is readable
creds_path <- "C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv"
file.exists(creds_path)
creds <- read.csv(creds_path)
names(creds)  # Should show: "project" "pid" "api_code"
```

## Common Errors and Solutions

### 1. Pipeline Setup Errors

#### Error: "Failed to load pipeline functions"
```
❌ Failed to load pipeline functions:
Error: could not find function "run_ne25_pipeline"
```

**Causes**:
- Missing R packages
- File path issues
- Syntax errors in pipeline files

**Solutions**:
1. **Install missing packages**:
   ```r
   install.packages(c("dplyr", "yaml", "REDCapR", "duckdb", "DBI"))
   ```

2. **Check working directory**:
   ```r
   getwd()  # Should be: C:/Users/waldmanm/git-repositories/Kidsights-Data-Platform
   setwd("C:/Users/waldmanm/git-repositories/Kidsights-Data-Platform")
   ```

3. **Source files manually**:
   ```r
   source("R/extract/ne25.R")
   source("R/harmonize/ne25_eligibility.R")
   source("R/duckdb/connection.R")
   source("pipelines/orchestration/ne25_pipeline.R")
   ```

### 2. Configuration Errors

#### Error: "Failed to load configuration"
```
Error: Failed to load configuration: Scanner error
```

**Causes**:
- YAML syntax errors
- Missing configuration file
- Invalid file encoding

**Solutions**:
1. **Check file exists**:
   ```r
   file.exists("config/sources/ne25.yaml")
   ```

2. **Validate YAML syntax**:
   ```r
   yaml::read_yaml("config/sources/ne25.yaml")
   ```

3. **Fix common YAML issues**:
   - Ensure proper indentation (spaces, not tabs)
   - Quote string values containing special characters
   - Check for missing colons or hyphens

#### Error: "API credentials file not found"
```
Error: API credentials file not found: C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv
```

**Solutions**:
1. **Create credentials file**:
   ```csv
   project,pid,api_code
   kidsights_data_survey,7679,YOUR_API_TOKEN_HERE
   kidsights_followup_survey,7943,YOUR_API_TOKEN_HERE
   kidsights_additional_survey,7999,YOUR_API_TOKEN_HERE
   kidsights_final_survey,8014,YOUR_API_TOKEN_HERE
   ```

2. **Verify file path**:
   ```r
   file.exists("C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv")
   ```

3. **Check file permissions**: Ensure the file is readable and not locked

### 3. API and Data Extraction Errors

#### Error: "API token not found in environment variable"
```
Error: API token not found in environment variable: KIDSIGHTS_API_TOKEN_7679
```

**Causes**:
- Missing or invalid API tokens in CSV
- Environment variable setting failure
- Incorrect PID in configuration

**Solutions**:
1. **Verify API tokens in CSV**:
   ```r
   creds <- read.csv("C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv")
   print(creds)  # Check pid and api_code columns
   ```

2. **Test environment variable setting**:
   ```r
   source("pipelines/orchestration/ne25_pipeline.R")
   load_api_credentials("C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv")
   Sys.getenv("KIDSIGHTS_API_TOKEN_7679")  # Should return token
   ```

3. **Test API connection manually**:
   ```r
   library(REDCapR)
   token <- "YOUR_ACTUAL_TOKEN"
   result <- REDCapR::redcap_read(
     redcap_uri = "https://redcap.ucdenver.edu/api/",
     token = token
   )
   ```

#### Error: "The API token you provided is not valid"
```
Error in REDCapR::redcap_read: The API token you provided is not valid
```

**Solutions**:
1. **Verify token in REDCap**:
   - Log in to https://redcap.ucdenver.edu/
   - Check API section of each project
   - Regenerate tokens if needed

2. **Check token format**:
   - Should be 32-character alphanumeric string
   - No extra spaces or special characters

3. **Verify API permissions**:
   - Ensure "API Export" permission is enabled
   - Check for project-specific restrictions

#### Error: "Can't combine ..1$field <datetime> and ..2$field <character>"
```
Error: Can't combine ..1$eligibility_form_timestamp <datetime<UTC>> and ..2$eligibility_form_timestamp <character>
```

**Causes**:
- Type mismatches between REDCap projects
- Different field formats across projects

**Solutions**:
1. **This should be handled automatically** by `flexible_bind_rows()` function
2. **If error persists, check function implementation**:
   ```r
   source("R/extract/ne25.R")
   # Ensure flexible_bind_rows function is properly loaded
   ```

3. **Manual type harmonization**:
   ```r
   # Convert problematic fields to character before binding
   for(i in seq_along(projects_data)) {
     projects_data[[i]]$eligibility_form_timestamp <- as.character(projects_data[[i]]$eligibility_form_timestamp)
   }
   ```

### 4. Database Errors

#### Error: "Failed to connect to database"
```
Error: Failed to connect to database: IO Error: Cannot open file
```

**Causes**:
- OneDrive folder not accessible
- Database file locked
- Insufficient permissions

**Solutions**:
1. **Check OneDrive folder exists**:
   ```r
   db_dir <- "C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB"
   dir.exists(db_dir)
   ```

2. **Create directory if missing**:
   ```r
   dir.create(db_dir, recursive = TRUE)
   ```

3. **Check OneDrive sync status**:
   - Ensure OneDrive is running and synced
   - Check for sync conflicts in the folder

4. **Test database connection manually**:
   ```r
   library(duckdb)
   drv <- duckdb::duckdb()
   con <- DBI::dbConnect(drv, dbdir = "C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb")
   DBI::dbDisconnect(con, shutdown = TRUE)
   ```

#### Error: "Table with name ne25_raw does not exist"
```
Error: Table with name ne25_raw does not exist
```

**Solutions**:
1. **Initialize schema**:
   ```r
   source("R/duckdb/connection.R")
   con <- connect_kidsights_db()
   init_ne25_schema(con)
   disconnect_kidsights_db(con)
   ```

2. **Use insert_ne25_data which creates tables**:
   ```r
   # This function automatically creates tables if they don't exist
   insert_ne25_data(con, data, "ne25_raw")
   ```

### 5. Eligibility Validation Issues

#### Error: "All eligibility criteria return 0"
```
Processing completed: 3902 records
Eligible participants: 0
Authentic participants: 0
Included participants: 0
```

**Causes**:
- Eligibility function not working correctly
- Missing required fields for validation
- Incorrect validation logic

**Solutions**:
1. **Debug eligibility function**:
   ```r
   source("R/harmonize/ne25_eligibility.R")
   # Test with sample data
   test_result <- check_ne25_eligibility(combined_data[1:10,], config)
   View(test_result)
   ```

2. **Check required fields exist**:
   ```r
   required_fields <- c("eq001", "eq002", "eq003", "age_in_days", "eqstate")
   missing_fields <- setdiff(required_fields, names(combined_data))
   if (length(missing_fields) > 0) {
     print(paste("Missing fields:", paste(missing_fields, collapse = ", ")))
   }
   ```

3. **Manual eligibility check**:
   ```r
   # Check individual criteria
   table(combined_data$eq001, useNA = "always")  # Consent
   table(combined_data$eq002, useNA = "always")  # Primary caregiver
   table(combined_data$eqstate, useNA = "always") # State residence
   ```

### 6. Performance Issues

#### Error: "Pipeline timeout or very slow execution"

**Solutions**:
1. **Check internet connection**: API calls require stable connection
2. **Reduce data volume for testing**:
   ```r
   # Modify config to test with fewer projects
   config$redcap$projects <- config$redcap$projects[1:2]
   ```

3. **Monitor API rate limits**: Pipeline includes 1-second delays
4. **Check OneDrive sync**: Large database operations may be slow during sync

## Advanced Diagnostics

### View Pipeline Execution History
```sql
-- Connect to DuckDB and check execution logs
library(duckdb)
source("R/duckdb/connection.R")
con <- connect_kidsights_db()

# Recent pipeline runs
DBI::dbGetQuery(con, "
  SELECT
    execution_id,
    execution_date,
    pipeline_type,
    total_records_extracted,
    records_eligible,
    records_included,
    status,
    error_message
  FROM ne25_pipeline_log
  ORDER BY execution_date DESC
  LIMIT 10
")

disconnect_kidsights_db(con)
```

### Data Quality Checks
```r
# Check for data inconsistencies
source("R/duckdb/connection.R")
con <- connect_kidsights_db()

# Record counts by table
summary_stats <- get_ne25_summary(con)
print(summary_stats)

# Check for duplicate records
DBI::dbGetQuery(con, "
  SELECT record_id, pid, COUNT(*) as count
  FROM ne25_raw
  GROUP BY record_id, pid
  HAVING COUNT(*) > 1
")

disconnect_kidsights_db(con)
```

### System Information
```r
# R and package versions
sessionInfo()

# Check R installation path
R.home()

# Check installed packages
installed.packages()[c("dplyr", "yaml", "REDCapR", "duckdb", "DBI"), "Version"]
```

## Getting Additional Help

### Log Files and Error Messages
1. **Save console output**: Copy full error messages and stack traces
2. **Check working directory**: Ensure you're in the correct project folder
3. **Document steps taken**: Note exactly what commands were run

### Support Channels
- **Technical Issues**: Review [API Setup Guide](api-setup.md) and [Pipeline Architecture](pipeline-architecture.md)
- **Data Issues**: Check the [DuckDB Schema Documentation](schema-documentation.md)
- **Configuration**: Refer to main [README.md](../README.md)

### Debugging Tips
1. **Run step-by-step**: Execute pipeline components individually
2. **Use small data**: Test with subset of projects or records
3. **Check intermediate results**: Examine data at each pipeline stage
4. **Enable verbose logging**: Add `message()` statements for debugging

---

**Last Updated**: January 2025