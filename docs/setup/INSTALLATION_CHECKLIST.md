# Kidsights Data Platform - Installation Checklist

**For Claude Installation Agent**

This checklist can be loaded into Claude's todo system to track installation progress step-by-step. Each item includes a verification command to confirm success.

---

## Quick Verification

**Run all checks at once:**
```bash
python scripts/setup/verify_installation.py
```

---

## Detailed Checklist

### 1. Environment Setup

#### ☐ Clone Repository
**Verification:**
```bash
cd Kidsights-Data-Platform && git status
```
**Expected:** Shows "On branch main" or similar

**Fix if failed:**
```bash
git clone https://github.com/your-org/Kidsights-Data-Platform.git
cd Kidsights-Data-Platform
```

---

#### ☐ Python 3.13+ Installed
**Verification:**
```bash
python --version
```
**Expected:** Python 3.13.0 or higher

**Fix if failed:**
- Download from https://www.python.org/downloads/
- Install and restart terminal

---

#### ☐ R 4.5.1+ Installed
**Verification:**
```bash
R --version
```
**Expected:** R version 4.5.1 or higher

**Fix if failed:**
- Windows: Download from https://cran.r-project.org/bin/windows/base/
- Mac: Download from https://cran.r-project.org/bin/macosx/
- Linux: `sudo apt-get install r-base` or equivalent

---

### 2. Python Dependencies

#### ☐ Core Python Packages
**Verification:**
```bash
python -c "import duckdb, pandas, yaml, structlog, dotenv; print('[OK] All core packages installed')"
```
**Expected:** `[OK] All core packages installed`

**Fix if failed:**
```bash
pip install duckdb pandas pyyaml structlog python-dotenv
```

---

#### ☐ IPUMS Python Packages (for ACS/NHIS)
**Verification:**
```bash
python -c "import ipumspy, requests; print('[OK] IPUMS packages installed')"
```
**Expected:** `[OK] IPUMS packages installed`

**Fix if failed:**
```bash
pip install ipumspy requests
```

---

#### ☐ NSCH Python Packages
**Verification:**
```bash
python -c "import pyreadstat; print('[OK] NSCH packages installed')"
```
**Expected:** `[OK] NSCH packages installed`

**Fix if failed:**
```bash
pip install pyreadstat
```

---

### 3. R Dependencies

#### ☐ Core R Packages
**Verification:**
```bash
Rscript -e "pkgs <- c('dplyr','tidyr','stringr','yaml','REDCapR','arrow','duckdb'); if(all(sapply(pkgs, requireNamespace, quietly=TRUE))) cat('[OK] All R packages installed\n') else cat('[FAIL] Some packages missing\n')"
```
**Expected:** `[OK] All R packages installed`

**Fix if failed:**
```r
# Run in R console
install.packages(c("dplyr", "tidyr", "stringr", "yaml", "REDCapR", "arrow", "duckdb"))
```

---

### 4. Configuration Files

#### ☐ Create .env File
**Verification:**
```bash
ls -la .env
```
**Expected:** `.env` file exists

**Fix if failed:**
```bash
cp .env.template .env
# Edit .env with your paths (see next steps)
```

---

#### ☐ Configure IPUMS API Key Path
**Verification:**
```bash
python -c "from dotenv import load_dotenv; import os; load_dotenv(); print(os.getenv('IPUMS_API_KEY_PATH') or '[NOT SET]')"
```
**Expected:** Shows your IPUMS API key file path

**Fix if failed:**
Edit `.env` and set:
```
IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
```
(or your preferred location)

---

#### ☐ Configure REDCap API Credentials Path
**Verification:**
```bash
python -c "from dotenv import load_dotenv; import os; load_dotenv(); print(os.getenv('REDCAP_API_CREDENTIALS_PATH') or '[NOT SET]')"
```
**Expected:** Shows your REDCap credentials file path

**Fix if failed:**
Edit `.env` and set:
```
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv
```
(or your preferred location)

---

### 5. API Keys

#### ☐ Create IPUMS API Key File
**Verification:**
```bash
python -c "from dotenv import load_dotenv; import os; from pathlib import Path; load_dotenv(); path=os.getenv('IPUMS_API_KEY_PATH'); print('[OK] File exists' if path and Path(path).exists() else '[FAIL] File not found')"
```
**Expected:** `[OK] File exists`

**Fix if failed:**
1. Register at https://usa.ipums.org/ and https://nhis.ipums.org/
2. Get API key from https://account.ipums.org/api_keys
3. Save to file:
```bash
mkdir -p C:/Users/YOUR_USERNAME/my-APIs
echo YOUR_API_KEY_HERE > C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
```

---

#### ☐ Create REDCap API Credentials File
**Verification:**
```bash
python -c "from dotenv import load_dotenv; import os; from pathlib import Path; load_dotenv(); path=os.getenv('REDCAP_API_CREDENTIALS_PATH'); print('[OK] File exists' if path and Path(path).exists() else '[FAIL] File not found')"
```
**Expected:** `[OK] File exists`

**Fix if failed:**
Create CSV file with format:
```csv
project,pid,api_code
kidsights_data_survey,7679,YOUR_TOKEN_HERE
kidsights_email_registration,7943,YOUR_TOKEN_HERE
kidsights_public,7999,YOUR_TOKEN_HERE
kidsights_public_birth,8014,YOUR_TOKEN_HERE
```

Save to the path specified in your `.env` file.

---

### 6. Directory Structure

#### ☐ Create Data Directories
**Verification:**
```bash
ls -d data/duckdb data/acs data/nhis data/nsch 2>/dev/null && echo "[OK] All directories exist" || echo "[FAIL] Missing directories"
```
**Expected:** `[OK] All directories exist`

**Fix if failed:**
```bash
mkdir -p data/duckdb data/acs data/nhis data/nsch
```

---

### 7. Database

#### ☐ Test DuckDB Connection
**Verification:**
```bash
python -c "from python.db.connection import DatabaseManager; result = DatabaseManager().test_connection(); print('[OK] Database connection works' if result else '[FAIL] Connection failed')"
```
**Expected:** `[OK] Database connection works`

**Fix if failed:**
1. Ensure `data/duckdb/` directory exists
2. Check file permissions
3. Run: `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().database_path)"`

---

### 8. API Connectivity

#### ☐ Test IPUMS API Connection
**Verification:**
```bash
python scripts/acs/test_ipums_api_connection.py
```
**Expected:** `[OK] All tests passed! IPUMS API is ready to use.`

**Fix if failed:**
1. Verify IPUMS API key is correct
2. Check API key file path in `.env`
3. Ensure you're registered at https://usa.ipums.org/

---

#### ☐ Test REDCap API Connection (if applicable)
**Verification:**
```bash
python -c "from python.db.config import get_api_credentials_file; from pathlib import Path; path=get_api_credentials_file(); print('[OK] REDCap credentials configured' if Path(path).exists() else '[SKIP] No credentials file')"
```
**Expected:** `[OK] REDCap credentials configured` or `[SKIP] No credentials file`

**Fix if failed:**
1. Verify REDCap API tokens are correct
2. Check credentials file format (CSV with headers)
3. Ensure credentials file path is correct in `.env`

---

### 9. Pipeline Test

#### ☐ Run Full Verification
**Verification:**
```bash
python scripts/setup/verify_installation.py
```
**Expected:** Exit code 0, all checks pass

**Fix if failed:**
Review output for specific failures and address each one

---

### 10. Final Checks

#### ☐ NE25 Pipeline Ready (if REDCap configured)
**Verification:**
```bash
python -c "from python.db.config import load_config; config = load_config(); print('[OK] NE25 pipeline configured' if 'redcap' in config else '[FAIL] Config missing')"
```
**Expected:** `[OK] NE25 pipeline configured`

---

#### ☐ ACS Pipeline Ready (if IPUMS configured)
**Verification:**
```bash
python -c "from python.acs.auth import get_client; client = get_client(); print('[OK] ACS pipeline configured')"
```
**Expected:** `[OK] ACS pipeline configured`

---

## Checklist Summary

**Total Steps:** 18
- Environment: 3 steps
- Python Packages: 3 steps
- R Packages: 1 step
- Configuration: 3 steps
- API Keys: 2 steps
- Infrastructure: 2 steps
- Testing: 4 steps

---

## For Claude Installation Agent

**To load this checklist into Claude's todo system:**

1. Read this file
2. Convert each `☐` item into a todo item with:
   - Content: Item description
   - Status: pending
   - Verification command from the "Verification:" section

3. Run verification commands sequentially
4. Mark as completed when verification passes
5. Provide fix commands when verification fails

**Example workflow:**
```
1. Run verification command
2. If [OK] → Mark todo as completed, move to next
3. If [FAIL] → Show fix command, wait for user
4. If [SKIP] → Mark as skipped, move to next
```

---

## Success Criteria

**Installation is complete when:**
- ✅ All environment checks pass
- ✅ All package checks pass
- ✅ .env file configured
- ✅ At least one API configured (IPUMS or REDCap)
- ✅ Database connection works
- ✅ `verify_installation.py` returns exit code 0

**Then you're ready to run pipelines!**
