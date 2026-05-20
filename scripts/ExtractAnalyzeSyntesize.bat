@echo off
:: Updated orchestration for the restructured repository
:: This assumes your scripts are in \scripts and prompts are in \prompts

SET "SCRIPT_DIR=%~dp0scripts"
SET "PROMPT_DIR=%~dp0prompts"

:: Run Analysis
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Analyze-KTPart.ps1" -PromptFile "%PROMPT_DIR%\prompt-extract-kt-part.md"

:: Run Synthesis
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Synthesize-KT.ps1" -PromptFile "%PROMPT_DIR%\prompt-synthesize-kt.md"