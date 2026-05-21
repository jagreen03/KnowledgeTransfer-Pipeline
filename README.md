# ACMP Knowledge Transfer Pipeline

A local-first pipeline that turns raw KT recording MP4s into a consolidated
engineering reference with relationship diagrams. Heavy lifting runs on your
own hardware (Whisper + Ollama); a single optional final pass uses Claude for a
high-level architecture overview.

## Pipeline stages

1. **Split** (`Split-KTInput.ps1`) - raw MP4 -> `sessions/<id>/PartN.mp4`, 15-min chunks, ffmpeg stream-copy.
2. **Transcribe** (`transcribe-whisper.py`) - faster-whisper large-v3, auto GPU/CPU -> `transcripts_partN.txt`.
3. **Keyframes** (`Extract-Keyframes.py`) - ffmpeg scene detection -> `frames_partN/tMMmSSs.jpg`.
4. **OCR** (`Extract-OCR.py`) - Tesseract over keyframes -> `ocr_partN.json`. Gives the local LLM the on-screen text it cannot see.
5. **Analyze** (`Analyze-KTPart-Local.ps1`) - transcript + OCR -> `extracted_partN.json` via local Ollama.
6. **Synthesize** (`Synthesize-KT-Local.ps1`) - all valid JSON -> `KT_Summary.md`, with deterministic Mermaid landscape + relationship diagrams plus LLM prose.
7. **Overview** (`Overview-Claude.ps1`, optional) - one Claude pass -> `KT_Overview.md`, executive architecture view + top-level Mermaid diagram.

Every stage is idempotent: re-running resumes where it stopped and never
overwrites a good output with a failed/tiny one.

## Prerequisites (one-time install)

### ffmpeg (stages 1, 3)
```
winget install Gyan.FFmpeg
```
Ensure `ffmpeg` and `ffprobe` are on PATH.

### Python venv + faster-whisper (stage 2)
```
py -3.12 -m venv C:\ODIN\whisper_venv_312
C:\ODIN\whisper_venv_312\Scripts\activate
pip install faster-whisper
```
GPU acceleration uses the pip-installed NVIDIA CUDA wheels; the script registers
their DLL directories automatically on Windows.

### Tesseract OCR (stage 4)
```
winget install UB-Mannheim.TesseractOCR
pip install pytesseract pillow
```
Ensure `tesseract.exe` is on PATH, or pass `--tesseract-exe "C:\Program Files\Tesseract-OCR\tesseract.exe"`.

### Ollama + local model (stages 5, 6)
```
# In PowerShell:
irm https://ollama.com/install.ps1 | iex
ollama run qwen2.5:7b
```
The `ollama run` pulls the model (~4.7 GB) and confirms it loads. The pipeline
talks to Ollama over `http://localhost:11434`. qwen2.5:7b fits comfortably on a
6 GB GPU; the analyzer requests `num_ctx 32768` and the synthesizer `24576`.

### Claude Code CLI (stage 7, optional)
Install per Anthropic docs and authenticate (`claude` once interactively). This
is the only stage that uses the network. If `claude.exe` is absent or
unauthenticated, stage 7 warns and skips without failing the pipeline.

## Layout
```
C:\ODIN\TEST_RUN\
  input_mp4\          raw recordings (gitignored)
  sessions\           split parts, transcripts, frames, OCR, extractions (gitignored)
  prompts\            prompt templates
  scripts\            PowerShell + bat orchestration
  infrastructure\     Python stages (Extract-Keyframes.py, Extract-OCR.py)
  output_analysis\    KT_Summary.md, KT_Overview.md (gitignored)
```

## Run
```
cd C:\ODIN\TEST_RUN\scripts
.\ExtractAnalyzeSynthesize.bat
```

## Output bias
The analyzer runs with `-AllowIncomplete` in the bat, so the pipeline always
produces a summary from whatever parts succeeded rather than halting on a few
failures. Per-part outcomes are logged to `sessions\_analyze_report.txt`. Check
the tail of that file after each run; a part that fails repeatedly is worth a
one-off manual debug.

## Notes
- `taskkill_command.bat` is a convenience to free RAM/VRAM before a big local run; it force-closes browsers/Office, so save work first.
- `Analyze-KTPart.ps1` / `Synthesize-KT.ps1` (non-`-Local`) are the Claude-based equivalents, kept for reference / fallback.
