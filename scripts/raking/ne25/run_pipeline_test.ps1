# PowerShell script to run complete NE25 raking targets pipeline
# Tests all phases with GAD-2 anxiety estimand included
# Expected output: 186 rows (31 estimands × 6 ages) in raking_targets_ne25 table

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NE25 Raking Targets Pipeline - End-to-End Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will run the complete pipeline including:" -ForegroundColor Yellow
Write-Host "  - Phase 1: ACS estimates (25 estimands)" -ForegroundColor White
Write-Host "  - Phase 2: NHIS estimates (PHQ-2 + GAD-2 = 2 estimands)" -ForegroundColor White
Write-Host "  - Phase 4: NSCH estimates (4 estimands)" -ForegroundColor White
Write-Host "  - Phase 5: Consolidation and database loading" -ForegroundColor White
Write-Host ""
Write-Host "Expected results:" -ForegroundColor Yellow
Write-Host "  - Point estimates: 186 rows (31 estimands × 6 ages)" -ForegroundColor White
Write-Host "  - Bootstrap replicates: 761,856 rows (31 × 6 × 4,096)" -ForegroundColor White
Write-Host "  - Database table: raking_targets_ne25" -ForegroundColor White
Write-Host ""
Write-Host "Configuration: n_boot = 4096 (PRODUCTION MODE)" -ForegroundColor Green
Write-Host "Estimated runtime: 2-3 minutes" -ForegroundColor Yellow
Write-Host ""

# Record start time
$startTime = Get-Date
Write-Host "Start time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# Navigate to project root
$projectRoot = "C:\Users\marcu\git-repositories\Kidsights-Data-Platform"
Set-Location $projectRoot

# Run the pipeline
Write-Host "[RUNNING] Executing run_raking_targets_pipeline.R..." -ForegroundColor Cyan
Write-Host ""

& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts\raking\ne25\run_raking_targets_pipeline.R

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Pipeline failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

# Calculate elapsed time
$endTime = Get-Date
$elapsed = $endTime - $startTime
$elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Pipeline Test Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Start time:    $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "End time:      $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "Elapsed time:  $elapsedMinutes minutes" -ForegroundColor Yellow
Write-Host ""

# Verification
Write-Host "Quick Verification:" -ForegroundColor Cyan
Write-Host ""

# Check point estimates file
if (Test-Path "data\raking\ne25\raking_targets_consolidated.rds") {
    Write-Host "[OK] Point estimates file exists" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Point estimates file missing!" -ForegroundColor Red
}

# Check bootstrap file
if (Test-Path "data\raking\ne25\all_bootstrap_replicates.rds") {
    Write-Host "[OK] Bootstrap replicates file exists" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Bootstrap replicates file missing!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify point estimates:" -ForegroundColor White
Write-Host "     Rscript -e `"d <- readRDS('data/raking/ne25/raking_targets_consolidated.rds'); cat('Rows:', nrow(d), '\n'); cat('Estimands:', length(unique(d\$estimand)), '\n')`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Verify bootstrap replicates:" -ForegroundColor White
Write-Host "     Rscript -e `"d <- readRDS('data/raking/ne25/all_bootstrap_replicates.rds'); cat('Rows:', nrow(d), '\n'); cat('Estimands:', length(unique(d\$estimand)), '\n')`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Check database (if populated):" -ForegroundColor White
Write-Host "     python -c `"from python.db.connection import DatabaseManager; db=DatabaseManager(); print('Rows:', db.execute_query('SELECT COUNT(*) FROM raking_targets_ne25')[0][0])`"" -ForegroundColor Gray
Write-Host ""
