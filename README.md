# ACMP Knowledge Transfer Extractor

An automated pipeline that uses local CPU frame extraction and Claude Code to synthesize video knowledge transfer (KT) sessions into a consolidated engineering reference document.

## Architecture
1. **Extract-Keyframes.py:** Python/FFmpeg script that detects scene changes and extracts frames.
2. **Analyze-KTPart.ps1:** PowerShell script that feeds transcripts and frames into Claude to extract structured JSON.
3. **Synthesize-KT.ps1:** Consolidates all per-part JSONs into a final `KT_Summary.md`.

## Prerequisites
* Python 3.12+ (with `ffmpeg` installed in PATH)
* PowerShell 5.1+
* Claude Code CLI authenticated and in PATH

## Usage
1. Place all session folders containing `PartN.mp4` and `transcript_partN.txt` in the target directory.
2. Run `ExtractAnalyzeSyntesize.bat`.
3. The pipeline will automatically generate `KT_Summary.md`.