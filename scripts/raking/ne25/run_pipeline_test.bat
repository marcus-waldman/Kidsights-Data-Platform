@echo off
REM NE25 Raking Targets Pipeline - End-to-End Test
REM Tests complete pipeline with GAD-2 anxiety estimand included
REM Expected: 186 rows (31 estimands x 6 ages), 761,856 bootstrap replicates

echo ========================================
echo NE25 Raking Targets Pipeline Test
echo ========================================
echo.
echo This will run the complete pipeline including:
echo   - Phase 1: ACS estimates (25 estimands)
echo   - Phase 2: NHIS estimates (PHQ-2 + GAD-2 = 2 estimands)
echo   - Phase 4: NSCH estimates (4 estimands)
echo   - Phase 5: Consolidation and database loading
echo.
echo Expected runtime: 2-3 minutes
echo.

"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R

echo.
echo ========================================
echo Pipeline Test Complete
echo ========================================
echo.
echo Next steps:
echo   1. Check for any errors in the output above
echo   2. Verify database: python -c "from python.db.connection import DatabaseManager; db = DatabaseManager(); print(db.execute_query('SELECT COUNT(*) FROM raking_targets_ne25'))"
echo.

pause
