# PowerShell script to check bootstrap pipeline progress
# Run this in a separate terminal while the pipeline is running

$ErrorActionPreference = "Continue"

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
    $pythonPath = "python"  # Fallback to system Python
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Pipeline Status Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host ""

# Navigate to project root
Set-Location "C:\Users\marcu\git-repositories\Kidsights-Data-Platform"

# Check if log file exists
$logFile = "logs\bootstrap_pipeline_production.log"
if (Test-Path $logFile) {
    Write-Host "[1] Log file status:" -ForegroundColor Green
    $logInfo = Get-Item $logFile
    Write-Host "    Size: $([math]::Round($logInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
    Write-Host "    Last modified: $($logInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

    # Show last 20 lines
    Write-Host "`n    Last 20 lines:" -ForegroundColor Yellow
    Get-Content $logFile -Tail 20 | ForEach-Object {
        if ($_ -match "\[OK\]") {
            Write-Host "    $_" -ForegroundColor Green
        } elseif ($_ -match "\[ERROR\]|\[FAILED\]") {
            Write-Host "    $_" -ForegroundColor Red
        } elseif ($_ -match "PHASE|Task|Script") {
            Write-Host "    $_" -ForegroundColor Cyan
        } else {
            Write-Host "    $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "[1] Log file not found: $logFile" -ForegroundColor Red
    Write-Host "    Pipeline may not have started yet" -ForegroundColor Yellow
}

Write-Host ""

# Check bootstrap files generated
Write-Host "[2] Bootstrap files generated:" -ForegroundColor Green
$bootFiles = Get-ChildItem "data\raking\ne25\*_boot.rds" -ErrorAction SilentlyContinue
if ($bootFiles) {
    Write-Host "    Found $($bootFiles.Count) bootstrap files:" -ForegroundColor Gray
    $bootFiles | ForEach-Object {
        $sizeKB = [math]::Round($_.Length / 1KB, 2)
        Write-Host "      - $($_.Name) ($sizeKB KB)" -ForegroundColor Gray
    }

    # Expected files (glm2 versions)
    $expected = @(
        "sex_estimates_boot_glm2.rds",
        "race_ethnicity_estimates_boot_glm2.rds",
        "fpl_estimates_boot_glm2.rds",
        "puma_estimates_boot_glm2.rds",
        "mother_education_estimates_boot_glm2.rds",
        "mother_marital_status_estimates_boot_glm2.rds",
        "phq2_estimate_boot_glm2.rds",
        "ace_exposure_boot_glm2.rds",
        "emotional_behavioral_boot_glm2.rds",
        "excellent_health_boot_glm2.rds",
        "childcare_10hrs_boot.rds"
    )

    $missing = $expected | Where-Object { $_ -notin $bootFiles.Name }
    if ($missing) {
        Write-Host "`n    Missing files:" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
    }
} else {
    Write-Host "    No bootstrap files found yet" -ForegroundColor Yellow
    Write-Host "    Pipeline may be in early stages" -ForegroundColor Gray
}

Write-Host ""

# Check consolidated file
Write-Host "[3] Consolidated file:" -ForegroundColor Green
$consolidatedFile = "data\raking\ne25\all_bootstrap_replicates.rds"
if (Test-Path $consolidatedFile) {
    $fileInfo = Get-Item $consolidatedFile
    $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    Write-Host "    [OK] Found: all_bootstrap_replicates.rds ($sizeMB MB)" -ForegroundColor Green
    Write-Host "    Last modified: $($fileInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
} else {
    Write-Host "    Not created yet (created after all individual files complete)" -ForegroundColor Yellow
}

Write-Host ""

# Check database
Write-Host "[4] Database status:" -ForegroundColor Green
$dbCheck = & $pythonPath -c @"
from python.db.connection import DatabaseManager
db = DatabaseManager()
try:
    result = db.execute_query('SELECT COUNT(*) FROM raking_targets_boot_replicates')
    count = result[0][0]
    print(f'    [OK] Bootstrap table exists: {count:,} rows')
    if count > 0:
        sources = db.execute_query('SELECT data_source, COUNT(*) as n FROM raking_targets_boot_replicates GROUP BY data_source ORDER BY data_source')
        print('    Breakdown by source:')
        for row in sources:
            print(f'      - {row[0]}: {row[1]:,} rows')
except Exception as e:
    print(f'    [INFO] Table not created yet or empty')
"@
Write-Host $dbCheck

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Expected final counts (n_boot = 4096):" -ForegroundColor Yellow
Write-Host "  ACS:  614,400 rows" -ForegroundColor Gray
Write-Host "  NHIS:  24,576 rows" -ForegroundColor Gray
Write-Host "  NSCH:  98,304 rows" -ForegroundColor Gray
Write-Host "  TOTAL: 737,280 rows" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To monitor log in real-time:" -ForegroundColor Yellow
Write-Host "  Get-Content logs\bootstrap_pipeline_production.log -Wait" -ForegroundColor White
Write-Host ""
