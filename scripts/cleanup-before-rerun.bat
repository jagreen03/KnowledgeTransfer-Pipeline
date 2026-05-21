@echo off
REM ============================================================================
REM cleanup-before-rerun.bat
REM
REM Run AFTER you've manually replaced the two files:
REM   - Extract-Keyframes.py  -> C:\ODIN\TEST_RUN\infrastructure\
REM   - ExtractAnalyzeSynthesize.bat -> C:\ODIN\TEST_RUN\scripts\
REM
REM What this does:
REM   1. Removes any stale Extract-Keyframes.py left over in scripts\
REM      (it belongs in infrastructure\, not scripts\)
REM   2. Removes the empty frames_part*\ dirs that the failed run created
REM      under the legacy C:\ODIN\GeminiReady_ACMP_Modules path
REM
REM After this, your transcripts are intact and idempotent. Re-run:
REM   cd C:\ODIN\TEST_RUN\scripts
REM   .\ExtractAnalyzeSynthesize.bat
REM
REM Stage 2 will skip all 46 already-transcribed parts. Stages 3-5 run fresh.
REM ============================================================================

SETLOCAL

ECHO ============================================================================
ECHO Cleanup before pipeline re-run
ECHO ============================================================================
ECHO.

REM --- Remove misplaced Extract-Keyframes.py from scripts\ ---
IF EXIST "C:\ODIN\TEST_RUN\scripts\Extract-Keyframes.py" (
    del /Q "C:\ODIN\TEST_RUN\scripts\Extract-Keyframes.py"
    ECHO Removed misplaced: C:\ODIN\TEST_RUN\scripts\Extract-Keyframes.py
) ELSE (
    ECHO Already clean:     no Extract-Keyframes.py in scripts\
)

REM --- Sanity-check that the patched version IS in infrastructure\ ---
IF NOT EXIST "C:\ODIN\TEST_RUN\infrastructure\Extract-Keyframes.py" (
    ECHO.
    ECHO ERROR: C:\ODIN\TEST_RUN\infrastructure\Extract-Keyframes.py is MISSING.
    ECHO        Copy the patched Extract-Keyframes.py there before re-running.
    EXIT /B 1
)
ECHO Verified:          infrastructure\Extract-Keyframes.py present
ECHO.

REM --- Remove empty frames_part* dirs from the legacy path ---
ECHO Cleaning legacy frames_part*\ dirs (all are empty from the failed run)...
FOR %%D IN (
    "C:\ODIN\GeminiReady_ACMP_Modules\20221219_140431\frames_part4"
    "C:\ODIN\GeminiReady_ACMP_Modules\20221220_140405\frames_part4"
    "C:\ODIN\GeminiReady_ACMP_Modules\20221221_140404\frames_part2"
) DO (
    IF EXIST %%D (
        rmdir /S /Q %%D
        ECHO   Removed: %%D
    )
)

REM Case_Service folder has the ampersand which cmd needs special handling for
SET "CASE_FRAMES=C:\ODIN\GeminiReady_ACMP_Modules\Case_Service_&_Exec_KT\frames_part2"
IF EXIST "%CASE_FRAMES%" (
    rmdir /S /Q "%CASE_FRAMES%"
    ECHO   Removed: %CASE_FRAMES%
)

ECHO.
ECHO ============================================================================
ECHO Cleanup done. Ready to re-run pipeline:
ECHO   cd C:\ODIN\TEST_RUN\scripts
ECHO   .\ExtractAnalyzeSynthesize.bat
ECHO ============================================================================
EXIT /B 0
