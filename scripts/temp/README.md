# Temporary Scripts Directory

This directory is used for temporary script files to avoid R segmentation faults when executing R code programmatically.

## Purpose

R.exe experiences frequent segmentation faults when executing code via the `-e` flag:
```bash
# ❌ CAUSES SEGMENTATION FAULTS
Rscript -e "library(dplyr); cat('Hello')"
R.exe -e "source('script.R')"
```

To avoid this, we create temporary script files and execute them using the `--file` flag:
```bash
# ✅ RELIABLE APPROACH
echo 'library(dplyr); cat("Hello")' > scripts/temp/temp_script.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/temp/temp_script.R
```

## Usage

### Manual Approach
1. Create temporary script in this directory
2. Execute with `R.exe --slave --no-restore --file=script_name.R`
3. Clean up the temporary file

### Programmatic Approach
Use the Python utility `python/utils/r_executor.py`:
```python
from python.utils.r_executor import execute_r_script

code = """
library(dplyr)
cat('Hello from R!\\n')
"""

result, return_code = execute_r_script(code)
print(result)
```

## File Management

- All files in this directory are gitignored (except this README)
- Temporary files should be cleaned up after execution
- Files are created with unique names to avoid conflicts

## Safety

This approach eliminates the segmentation fault issues that plague direct R execution, providing a reliable way to run R code from Python or other scripts in the Kidsights Data Platform.

## Debug Scripts for Pipeline Functions

In addition to avoiding segmentation faults, this directory contains specialized debug scripts that use cached test data for rapid pipeline debugging.

### 🎯 Cached Test Data Approach

During pipeline debugging, repeatedly running the full pipeline (54+ seconds of REDCap API calls) is inefficient. These scripts cache function inputs and test functions in isolation.

### 📁 Debug Scripts Created

- **`test_cid8_standalone.R`** - Tests CID8 function with cached inputs
- **`test_value_labels_standalone.R`** - Tests extract_value_labels function
- **`test_value_labels_transform_standalone.R`** - Tests value_labels transform function
- **`debug_mapvalues_simple.R`** - Simple test for extract_value_labels errors

### 📂 Cached Data Directories

- **`temp/cid8_test_data/`** - CID8 function inputs (data, codebook, calibdat)
- **`temp/value_labels_test_data/`** - extract_value_labels inputs (field_name, dictionary)
- **`temp/value_labels_transform_test_data/`** - value_labels transform inputs (lex, dict, varname)

### 🚀 Usage Pattern for Pipeline Debug

1. **Initial Setup** (Run once to cache data):
   ```bash
   "C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
   ```

2. **Rapid Iteration** (Debug cycle, 2-3 seconds):
   ```bash
   "C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/temp/test_cid8_standalone.R
   ```

3. **Function Fix Implementation**: Edit main function, re-test with cached data

4. **Final Validation**: Run full pipeline to confirm end-to-end fix

### ✅ Success Story: CID8 Debug (September 17, 2025)

**Problem**: CID8 finding 0 items, completely failing
**Solution**:
- Cached function inputs during pipeline execution
- Used standalone test to isolate pivot_wider data flow issue
- Fixed namespace conflicts with explicit dplyr:: prefixes
- Verified with cached test: 2,308 participants authenticated (59% pass rate)
- Confirmed with full pipeline: 187 quality items found

**Time Saved**: ~30 pipeline runs (45+ minutes) → ~10 standalone tests (30 seconds)