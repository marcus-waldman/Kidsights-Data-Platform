# PowerShell script to run bootstrap pipeline in production mode (n_boot = 4096)
# Expected runtime: 15-20 minutes
# Expected output: 737,280 bootstrap replicates in database

$ErrorActionPreference = "Stop"

# Read Python path from .env file
function Get-EnvVariable {
    param([string]$VarName)

    $envFile = ".env"
    if (Test-Path $envFile) {
        $content = Get-Content $envFile
        foreach ($line in $content) {
            if ($line -match "^$VarName=(.+)$") {
                return $matches[1].Trim('"').Trim("'")
            }
        }
    }
    return $null
}

$pythonPath = Get-EnvVariable "PYTHON_EXECUTABLE"
if (-not $pythonPath) {
    Write-Host "[ERROR] PYTHON_EXECUTABLE not found in .env file" -ForegroundColor Red
    Write-Host "Please add to .env: PYTHON_EXECUTABLE=C:/Path/To/python.exe" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $pythonPath)) {
    Write-Host "[ERROR] Python executable not found at: $pythonPath" -ForegroundColor Red
    Write-Host "Please update PYTHON_EXECUTABLE in .env file" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Pipeline - Production Run" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  n_boot: 4096" -ForegroundColor Yellow
Write-Host "  Expected rows: 737,280" -ForegroundColor Yellow
Write-Host "  Estimated time: 15-20 minutes" -ForegroundColor Yellow
Write-Host "  Log file: logs/bootstrap_pipeline_production.log" -ForegroundColor Yellow
Write-Host "  Python: $pythonPath" -ForegroundColor Yellow
Write-Host ""

# Record start time
$startTime = Get-Date
Write-Host "Start time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# Navigate to project root
Set-Location "C:\Users\marcu\git-repositories\Kidsights-Data-Platform"

# Clean existing bootstrap files for fresh run
Write-Host "[1/4] Cleaning existing bootstrap files..." -ForegroundColor Cyan
if (Test-Path "data\raking\ne25\*_boot.rds") {
    Remove-Item "data\raking\ne25\*_boot.rds" -Force
    Write-Host "      Removed existing bootstrap files" -ForegroundColor Gray
}
if (Test-Path "data\raking\ne25\all_bootstrap_replicates.rds") {
    Remove-Item "data\raking\ne25\all_bootstrap_replicates.rds" -Force
    Write-Host "      Removed consolidated file" -ForegroundColor Gray
}
if (Test-Path "data\raking\ne25\*_bootstrap_design.rds") {
    Remove-Item "data\raking\ne25\*_bootstrap_design.rds" -Force
    Write-Host "      Removed old bootstrap design files (force regeneration)" -ForegroundColor Gray
}
Write-Host ""

# Drop existing bootstrap table
Write-Host "[2/4] Dropping existing bootstrap database table..." -ForegroundColor Cyan
& $pythonPath -c @"
from python.db.connection import DatabaseManager
db = DatabaseManager()
with db.get_connection() as conn:
    try:
        conn.execute('DROP TABLE IF EXISTS raking_targets_boot_replicates')
        print('      [OK] Dropped existing table')
    except Exception as e:
        print(f'      [ERROR] {e}')
"@
Write-Host ""

# Run R pipeline
Write-Host "[3/4] Running bootstrap pipeline (R)..." -ForegroundColor Cyan
Write-Host "      This will take 15-20 minutes..." -ForegroundColor Yellow
Write-Host "      Monitor progress: Get-Content logs\bootstrap_pipeline_production.log -Wait" -ForegroundColor Yellow
Write-Host ""

& "C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts\raking\ne25\run_bootstrap_pipeline.R

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] R pipeline failed. Check logs/bootstrap_pipeline_production.log" -ForegroundColor Red
    exit 1
}

# Insert into database
Write-Host "`n[4/4] Inserting bootstrap replicates into database (Python)..." -ForegroundColor Cyan
& $pythonPath scripts\raking\ne25\23_insert_boot_replicates.py

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Database insertion failed" -ForegroundColor Red
    exit 1
}

# Calculate elapsed time
$endTime = Get-Date
$elapsed = $endTime - $startTime
$elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Bootstrap Pipeline Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Start time:    $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "End time:      $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "Elapsed time:  $elapsedMinutes minutes" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Validate: python scripts/raking/ne25/24_validate_bootstrap_database.py" -ForegroundColor White
Write-Host "  2. Check row count: python -c `"from python.db.connection import DatabaseManager; db=DatabaseManager(); print(db.execute_query('SELECT COUNT(*) FROM raking_targets_boot_replicates')[0][0])`"" -ForegroundColor White
Write-Host ""
