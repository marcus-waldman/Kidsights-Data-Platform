# PowerShell script to run COMPLETE NE25 raking targets pipeline from scratch
# Deletes all estimation outputs and regenerates everything (ACS + NHIS + NSCH)
# This is the full end-to-end test including all GLM model fitting

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Complete NE25 Raking Targets Pipeline" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. DELETE all existing estimate files" -ForegroundColor Red
Write-Host "  2. Run Phase 1: ACS estimation (7 GLM2 scripts, 25 estimands)" -ForegroundColor White
Write-Host "  3. Run Phase 2: NHIS estimation (PHQ-2 + GAD-2 = 2 estimands)" -ForegroundColor White
Write-Host "  4. Run Phase 4: NSCH estimation (4 estimands)" -ForegroundColor White
Write-Host "  5. Run Phase 5: Consolidation and database loading" -ForegroundColor White
Write-Host ""
Write-Host "Expected output: 186 rows (31 estimands × 6 ages)" -ForegroundColor Green
Write-Host "Configuration: n_boot = 4096 (PRODUCTION MODE)" -ForegroundColor Green
Write-Host ""
Write-Host "WARNING: This will regenerate EVERYTHING from scratch" -ForegroundColor Red
Write-Host "Estimated runtime: 8-12 minutes (includes bootstrap design + all estimates)" -ForegroundColor Yellow
Write-Host ""

# Confirm with user
$confirmation = Read-Host "Continue? (y/n)"
if ($confirmation -ne 'y') {
    Write-Host "Aborted by user" -ForegroundColor Yellow
    exit 0
}

# Record start time
$startTime = Get-Date
Write-Host "`nStart time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# Navigate to project root
$projectRoot = "C:\Users\marcu\git-repositories\Kidsights-Data-Platform"
Set-Location $projectRoot

# Clean existing estimation files (INCLUDING bootstrap design for complete test)
Write-Host "[CLEANUP] Removing ALL estimation files..." -ForegroundColor Cyan
Write-Host "  This includes the bootstrap design (will be regenerated, ~1-2 min)" -ForegroundColor Yellow

$filesToDelete = @(
    "data\raking\ne25\acs_design.rds",
    "data\raking\ne25\acs_bootstrap_design.rds",
    "data\raking\ne25\nhis_bootstrap_design.rds",
    "data\raking\ne25\nsch_bootstrap_design.rds",
    "data\raking\ne25\*_estimate*.rds",
    "data\raking\ne25\*_boot*.rds",
    "data\raking\ne25\*bootstrap_consolidated.rds",
    "data\raking\ne25\raking_targets_consolidated.rds",
    "data\raking\ne25\all_bootstrap_replicates.rds"
)

foreach ($pattern in $filesToDelete) {
    $files = Get-ChildItem $pattern -ErrorAction SilentlyContinue
    if ($files) {
        $files | Remove-Item -Force
        Write-Host "  Removed: $($files.Count) files matching $pattern" -ForegroundColor Gray
    }
}

Write-Host "  [OK] Cleanup complete`n" -ForegroundColor Green

# Run the complete pipeline
Write-Host "[RUNNING] Executing run_complete_pipeline.R..." -ForegroundColor Cyan
Write-Host "  This will fit all GLM models and generate bootstrap replicates" -ForegroundColor Gray
Write-Host ""

& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts\raking\ne25\run_complete_pipeline.R

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Pipeline failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

# Calculate elapsed time
$endTime = Get-Date
$elapsed = $endTime - $startTime
$elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Complete Pipeline Test Finished!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Start time:    $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "End time:      $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "Elapsed time:  $elapsedMinutes minutes" -ForegroundColor Yellow
Write-Host ""

# Verification
Write-Host "Quick Verification:" -ForegroundColor Cyan
Write-Host ""

# Check files exist
$filesToCheck = @(
    @{Path="data\raking\ne25\acs_estimates.rds"; Name="ACS estimates"},
    @{Path="data\raking\ne25\phq2_estimate_glm2.rds"; Name="PHQ-2 estimates"},
    @{Path="data\raking\ne25\gad2_estimate_glm2.rds"; Name="GAD-2 estimates"},
    @{Path="data\raking\ne25\nsch_estimates.rds"; Name="NSCH estimates"},
    @{Path="data\raking\ne25\raking_targets_consolidated.rds"; Name="Consolidated estimates"},
    @{Path="data\raking\ne25\all_bootstrap_replicates.rds"; Name="Bootstrap replicates"}
)

foreach ($file in $filesToCheck) {
    if (Test-Path $file.Path) {
        Write-Host "[OK] $($file.Name) created" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] $($file.Name) missing!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Verification commands:" -ForegroundColor Cyan
Write-Host "  1. Check consolidated estimates:" -ForegroundColor White
Write-Host "     Rscript -e `"d <- readRDS('data/raking/ne25/raking_targets_consolidated.rds'); cat('Rows:', nrow(d), 'Estimands:', length(unique(d\$estimand)), '\n')`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Check bootstrap replicates:" -ForegroundColor White
Write-Host "     Rscript -e `"b <- readRDS('data/raking/ne25/all_bootstrap_replicates.rds'); cat('Bootstrap rows:', nrow(b), 'Expected: 761856 (31 x 6 x 4096)\n')`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Verify database:" -ForegroundColor White
Write-Host "     Rscript -e `"library(duckdb); con <- dbConnect(duckdb(), 'data/duckdb/kidsights_local.duckdb'); result <- dbGetQuery(con, 'SELECT COUNT(*) as n FROM raking_targets_ne25'); cat('Database rows:', result\$n, '\n'); dbDisconnect(con, shutdown=TRUE)`"" -ForegroundColor Gray
Write-Host ""
