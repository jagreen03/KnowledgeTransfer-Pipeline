cd C:\ODIN

REM CALL C:\ODIN\whisper_venv_312\Scripts\activate.bat
REM python C:\ODIN\_skills\Extract-Keyframes.py

powershell -ExecutionPolicy Bypass -File C:\ODIN\_skills\Analyze-KTPart.ps1 -PromptFile C:\ODIN\_skills\prompt-extract-kt-part.md

powershell -ExecutionPolicy Bypass -File C:\ODIN\_skills\Synthesize-KT.ps1 -PromptFile C:\ODIN\_skills\prompt-synthesize-kt.md
