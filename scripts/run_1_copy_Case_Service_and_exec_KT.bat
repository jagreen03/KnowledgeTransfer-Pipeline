@echo off
REM ============================================================================
REM Stage the missing Case_Service_&_Exec_KT parts into TEST_RUN, then run the
REM full pipeline. Idempotent: the pipeline skips work already done in the
REM first run, so only the 4 new parts get transcribed/analyzed; the master
REM KT_Summary.md is re-synthesized over all 50 parts.
REM
REM RUN ONLY AFTER the first ExtractAnalyzeSynthesize.bat shows
REM "Pipeline complete." If you launch this while the first bat is still in
REM stage 2-4, Whisper/Claude has already enumerated its work list and the
REM new 4 parts won't be picked up.
REM ============================================================================

SETLOCAL EnableDelayedExpansion

SET "SRC=C:\ODIN\GeminiReady_ACMP_Modules\Case_Service_&_Exec_KT"
SET "DEST=C:\ODIN\TEST_RUN\sessions\Case_Service_Exec_KT"
SET "FILESTEM=Case creation _ Case Service & Exec flow KT-20241227_022958-Meeting Recording"

REM --- Create destination (silent if already exists) ---
IF NOT EXIST "%DEST%" mkdir "%DEST%"

REM --- Copy and rename the 4 parts ---
copy "%SRC%\%FILESTEM%_Part1.mp4" "%DEST%\Part1.mp4"
copy "%SRC%\%FILESTEM%_Part2.mp4" "%DEST%\Part2.mp4"
copy "%SRC%\%FILESTEM%_Part3.mp4" "%DEST%\Part3.mp4"
copy "%SRC%\%FILESTEM%_Part4.mp4" "%DEST%\Part4.mp4"

REM --- Verify all 4 are in place before kicking off the pipeline ---
SET "MISSING=0"
FOR %%i IN (1 2 3 4) DO IF NOT EXIST "%DEST%\Part%%i.mp4" (
    ECHO ERROR: %DEST%\Part%%i.mp4 not present after copy.
    SET "MISSING=1"
)
IF "!MISSING!"=="1" (
    ECHO Aborting pipeline launch - investigate the missing file(s) above.
    EXIT /B 1
)

ECHO All 4 Case_Service parts staged into:
ECHO   %DEST%
ECHO.
ECHO Launching ExtractAnalyzeSynthesize.bat ...
ECHO.

cd /d C:\ODIN\TEST_RUN\scripts
CALL .\ExtractAnalyzeSynthesize.bat
EXIT /B %ERRORLEVEL%