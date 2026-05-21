@echo off
REM ============================================================================
REM Full KT pipeline (LOCAL-FIRST) anchored under C:\ODIN\TEST_RUN
REM Stages: split -> transcribe -> keyframes -> OCR -> analyze -> synthesize -> overview
REM
REM Stages 1-6 are fully local (ffmpeg, whisper, tesseract, ollama).
REM Stage 7 (Claude overview) is optional and the only networked stage; it
REM skips cleanly if claude.exe is absent. Every stage is idempotent.
REM ============================================================================

SETLOCAL EnableDelayedExpansion

REM --- Paths ---
SET "ROOT=C:\ODIN\TEST_RUN"
SET "INPUT=%ROOT%\input_mp4"
SET "SESSIONS=%ROOT%\sessions"
SET "PROMPTS=%ROOT%\prompts"
SET "SCRIPTS=%ROOT%\scripts"
SET "INFRA=%ROOT%\infrastructure"
SET "OUTPUT=%ROOT%\output_analysis"

REM Python stages read KT_INPUT_ROOT; export BEFORE venv activation.
SET "KT_INPUT_ROOT=%SESSIONS%"

REM --- Optional: activate Python venv if it exists ---
IF EXIST "C:\ODIN\whisper_venv_312\Scripts\activate.bat" (
    ECHO Activating whisper_venv_312...
    CALL "C:\ODIN\whisper_venv_312\Scripts\activate.bat"
)

REM --- Stage 1: Split raw MP4s ---
ECHO.
ECHO ============================================================================
ECHO [Stage 1/7] Split raw MP4s -^> sessions\^<id^>\PartN.mp4
ECHO ============================================================================
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Split-KTInput.ps1" -InputDir "%INPUT%" -OutputDir "%SESSIONS%"
IF ERRORLEVEL 1 GOTO :error

REM --- Stage 2: Transcribe via local faster-whisper ---
ECHO.
ECHO ============================================================================
ECHO [Stage 2/7] Transcribe with faster-whisper (auto GPU/CPU)
ECHO ============================================================================
python "%SCRIPTS%\transcribe-whisper.py"
IF ERRORLEVEL 1 GOTO :error

REM --- Stage 3: Scene-change keyframe extraction ---
ECHO.
ECHO ============================================================================
ECHO [Stage 3/7] Extract scene-change keyframes
ECHO ============================================================================
python "%INFRA%\Extract-Keyframes.py" --input "%SESSIONS%"
IF ERRORLEVEL 1 GOTO :error

REM --- Stage 4: OCR the keyframes (feeds the local analyzer) ---
ECHO.
ECHO ============================================================================
ECHO [Stage 4/7] OCR keyframes (Tesseract) -^> ocr_partN.json
ECHO ============================================================================
python "%INFRA%\Extract-OCR.py" --input "%SESSIONS%"
IF ERRORLEVEL 1 GOTO :error

REM --- Stage 4.5: Update Context Map ---
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Generate-Context-Map.ps1" -InputRoot "%SESSIONS%" -OutputFile "%PROMPTS%\technical_context_map.txt"

REM --- Stage 5: Per-part analysis via local Ollama ---
ECHO.
ECHO ============================================================================
ECHO [Stage 5/7] Analyze parts -^> extracted_partN.json (Local LLM / Ollama)
ECHO ============================================================================
REM -AllowIncomplete: bias toward producing output from whatever parts succeed.
REM Per-part outcomes are logged to %SESSIONS%\_analyze_report.txt regardless.
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Analyze-KTPart-Local.ps1" -InputRoot "%SESSIONS%" -OllamaModel "qwen2.5-coder:7b" -AllowIncomplete
IF ERRORLEVEL 1 GOTO :error

ECHO ============================================================================
ECHO [Stage 5.5/7] Auto-harvest context for next run
ECHO ============================================================================
REM --- Stage 5.5: Auto-harvest context for next run ---
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Harvest-Context.ps1"

REM --- Stage 6: Synthesize master summary (local + deterministic Mermaid) ---
ECHO.
ECHO ============================================================================
ECHO [Stage 6/7] Synthesize -^> KT_Summary.md (local LLM + Mermaid diagrams)
ECHO ============================================================================
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Synthesize-KT-Local.ps1" -InputRoot "%SESSIONS%" -OutputFile "%OUTPUT%\KT_Summary.md" -OllamaModel "qwen2.5-coder:7b"
IF ERRORLEVEL 1 GOTO :error

REM --- Stage 7: High-level architecture overview via Claude (optional) ---
ECHO.
ECHO ============================================================================
ECHO [Stage 7/7] High-level overview -^> KT_Overview.md (Claude, optional)
ECHO ============================================================================
REM This stage skips cleanly (exit 0) if claude.exe is missing/unauthenticated.
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Overview-Claude.ps1" -SummaryFile "%OUTPUT%\KT_Summary.md" -OverviewFile "%OUTPUT%\KT_Overview.md"
IF ERRORLEVEL 1 GOTO :error

ECHO.
ECHO ============================================================================
ECHO Pipeline complete.
ECHO Summary:   %OUTPUT%\KT_Summary.md
ECHO Overview:  %OUTPUT%\KT_Overview.md  (if Claude stage ran)
ECHO Report:    %SESSIONS%\_analyze_report.txt
ECHO ============================================================================
EXIT /B 0

:error
ECHO.
ECHO ============================================================================
ECHO Pipeline FAILED at the stage shown above.
ECHO All stages are idempotent - re-run this bat to resume from where it stopped.
ECHO ============================================================================
EXIT /B 1
