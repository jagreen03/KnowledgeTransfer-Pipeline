# Transcribe-GeminiReady.ps1
# Transcribes all *_Part<N>.mp4 chunks under C:\ODIN\GeminiReady_ACMP_Modules
# using Gemini Files API + generateContent. Saves as transcripts_part<N>.txt
# alongside the source video (matches your existing manual output convention).
#
# Prerequisites:
#   - Gemini API key in environment variable GEMINI_API_KEY
#       setx GEMINI_API_KEY "your_key_here"     (new shell after this)
#     Get a key at: https://aistudio.google.com/apikey
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File C:\ODIN\_Scripts\Transcribe-GeminiReady.ps1
#
# Idempotent: skips any chunk whose transcripts_part<N>.txt already exists.
# Your two manually-done files (transcripts_part1.txt, transcripts_part2.txt
# in the 12-16 folder) will be preserved and treated as ground truth.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# =============================================================================
# CONFIGURATION
# =============================================================================

$INPUT_ROOT = "C:\ODIN\GeminiReady_ACMP_Modules"
$MODEL      = "gemini-2.5-flash"  # use gemini-2.5-pro for higher quality, slower
$API_BASE   = "https://generativelanguage.googleapis.com"

# Polling for file readiness after upload
$POLL_INTERVAL_SEC = 5
$POLL_TIMEOUT_SEC  = 300   # 5 min per file (large videos take longer to process)

# Transcription prompt - adjust to match the style of your manual examples
$PROMPT = @'
Transcribe this video recording verbatim into clean readable text.

Requirements:
- Capture all spoken content - do not summarize or paraphrase
- Use speaker labels (Speaker 1, Speaker 2, etc.) when speakers change
- Insert [MM:SS] timestamp at major topic shifts or every few minutes
- Preserve technical terms, code references, file paths, URLs, and product names exactly as spoken
- Use proper punctuation, capitalization, and paragraph breaks
- Skip filler words (um, uh) and false starts unless they affect meaning
- Mark inaudible segments as [inaudible]

Return only the transcript text. No preamble, no summary, no concluding remarks.
'@

# =============================================================================
# PRE-FLIGHT
# =============================================================================

Write-Host ""
Write-Host "Gemini Transcription - ACMP Module Chunks" -ForegroundColor Cyan
Write-Host "Source: $INPUT_ROOT"
Write-Host "Model:  $MODEL"
Write-Host ""

if (-not $env:GEMINI_API_KEY -or $env:GEMINI_API_KEY.Length -lt 20) {
    Write-Host "ERROR: GEMINI_API_KEY env var not set." -ForegroundColor Red
    Write-Host "Get key at https://aistudio.google.com/apikey then:" -ForegroundColor Yellow
    Write-Host '  setx GEMINI_API_KEY "your_key_here"' -ForegroundColor Yellow
    Write-Host "  (open a new shell after that for the var to take effect)" -ForegroundColor Yellow
    exit 1
}
$API_KEY = $env:GEMINI_API_KEY

if (-not (Test-Path $INPUT_ROOT)) {
    Write-Host "ERROR: input root not found: $INPUT_ROOT" -ForegroundColor Red
    exit 1
}

# =============================================================================
# COLLECT WORK
# =============================================================================

$jobs = @()
$folders = Get-ChildItem $INPUT_ROOT -Directory -ErrorAction SilentlyContinue

foreach ($folder in $folders) {
    $videos = Get-ChildItem $folder.FullName -Filter "*Part*.mp4" -ErrorAction SilentlyContinue |
              Sort-Object Name

    foreach ($v in $videos) {
        if ($v.Name -match 'Part(\d+)\.mp4$') {
            $partNum = $matches[1]
            $outFile = Join-Path $folder.FullName "transcripts_part$partNum.txt"

            $jobs += [pscustomobject]@{
                Folder  = $folder.Name
                Video   = $v.FullName
                Name    = $v.Name
                PartNum = $partNum
                OutFile = $outFile
                Exists  = (Test-Path $outFile)
                SizeMB  = [math]::Round($v.Length / 1MB, 1)
            }
        }
    }
}

if ($jobs.Count -eq 0) {
    Write-Host "No video chunks found." -ForegroundColor Yellow
    exit 0
}

$todo = $jobs | Where-Object { -not $_.Exists }
$done = $jobs | Where-Object { $_.Exists }

Write-Host "Total chunks:  $($jobs.Count)" -ForegroundColor White
Write-Host "Already done:  $($done.Count)" -ForegroundColor DarkGray
Write-Host "To transcribe: $($todo.Count)" -ForegroundColor Yellow
Write-Host ""

if ($todo.Count -eq 0) {
    Write-Host "Nothing to do. All chunks have transcripts." -ForegroundColor Green
    exit 0
}

# =============================================================================
# FUNCTIONS
# =============================================================================

function Upload-VideoToGemini {
    param([string]$VideoPath, [string]$ApiKey)

    $size = (Get-Item $VideoPath).Length
    $name = [System.IO.Path]::GetFileName($VideoPath)

    # Step 1: initiate resumable upload
    $initHeaders = @{
        "X-Goog-Upload-Protocol"   = "resumable"
        "X-Goog-Upload-Command"    = "start"
        "X-Goog-Upload-Header-Content-Length" = "$size"
        "X-Goog-Upload-Header-Content-Type"   = "video/mp4"
        "Content-Type"             = "application/json"
    }
    $initBody = @{ file = @{ display_name = $name } } | ConvertTo-Json -Compress

    $initResp = Invoke-WebRequest `
        -Uri "$API_BASE/upload/v1beta/files?key=$ApiKey" `
        -Method POST `
        -Headers $initHeaders `
        -Body $initBody `
        -UseBasicParsing

    $uploadUrl = $initResp.Headers["X-Goog-Upload-URL"]
    if (-not $uploadUrl) {
        if ($initResp.Headers["x-goog-upload-url"]) { $uploadUrl = $initResp.Headers["x-goog-upload-url"] }
    }
    if (-not $uploadUrl) { throw "no upload URL returned" }

    # Step 2: upload the bytes
    $uploadHeaders = @{
        "Content-Length"        = "$size"
        "X-Goog-Upload-Offset"  = "0"
        "X-Goog-Upload-Command" = "upload, finalize"
    }

    $uploadResp = Invoke-WebRequest `
        -Uri $uploadUrl `
        -Method POST `
        -Headers $uploadHeaders `
        -InFile $VideoPath `
        -ContentType "video/mp4" `
        -UseBasicParsing

    $fileInfo = $uploadResp.Content | ConvertFrom-Json
    return $fileInfo.file
}

function Wait-FileActive {
    param([string]$FileName, [string]$ApiKey, [int]$TimeoutSec, [int]$IntervalSec)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $IntervalSec
        $info = Invoke-RestMethod -Uri "$API_BASE/v1beta/$FileName`?key=$ApiKey" -Method GET
        if ($info.state -eq "ACTIVE")  { return $info }
        if ($info.state -eq "FAILED")  { throw "file processing FAILED" }
        Write-Host "         ... still processing ($($info.state))" -ForegroundColor DarkGray
    }
    throw "timeout waiting for file to become ACTIVE"
}

function Generate-Transcript {
    param([string]$FileUri, [string]$Prompt, [string]$Model, [string]$ApiKey)

    $body = @{
        contents = @(
            @{
                parts = @(
                    @{ file_data = @{ mime_type = "video/mp4"; file_uri = $FileUri } },
                    @{ text = $Prompt }
                )
            }
        )
        generationConfig = @{
            temperature     = 0.1
            maxOutputTokens = 8192
        }
    } | ConvertTo-Json -Depth 10 -Compress

    $resp = Invoke-RestMethod `
        -Uri "$API_BASE/v1beta/models/$Model`:generateContent?key=$ApiKey" `
        -Method POST `
        -ContentType "application/json" `
        -Body $body

    # Extract text from first candidate
    if ($resp.candidates -and $resp.candidates[0].content.parts) {
        return ($resp.candidates[0].content.parts | ForEach-Object { $_.text }) -join ""
    }
    throw "no transcript in response"
}

# =============================================================================
# PROCESS
# =============================================================================

$success = 0
$fail    = 0
$idx     = 0

foreach ($job in $todo) {
    $idx++
    $progress = "[$idx/$($todo.Count)]".PadRight(8)
    $label    = "$($job.Folder) Part$($job.PartNum) ($($job.SizeMB)MB)"

    Write-Host "$progress $label" -ForegroundColor Yellow

    try {
        Write-Host "         uploading..." -ForegroundColor DarkGray
        $file = Upload-VideoToGemini -VideoPath $job.Video -ApiKey $API_KEY
        Write-Host "         uploaded as $($file.name)" -ForegroundColor DarkGray

        if ($file.state -ne "ACTIVE") {
            Write-Host "         waiting for processing..." -ForegroundColor DarkGray
            $file = Wait-FileActive -FileName $file.name -ApiKey $API_KEY `
                    -TimeoutSec $POLL_TIMEOUT_SEC -IntervalSec $POLL_INTERVAL_SEC
        }

        Write-Host "         transcribing..." -ForegroundColor DarkGray
        $transcript = Generate-Transcript -FileUri $file.uri -Prompt $PROMPT `
                      -Model $MODEL -ApiKey $API_KEY

        if (-not $transcript -or $transcript.Trim().Length -lt 50) {
            throw "transcript too short or empty"
        }

        Set-Content -Path $job.OutFile -Value $transcript -Encoding UTF8
        $charCount = $transcript.Length
        Write-Host "         -> $($job.OutFile.Split('\')[-1]) ($charCount chars)" -ForegroundColor Green
        $success++
    }
    catch {
        Write-Host "         FAILED: $_" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host ("=" * 78)
Write-Host "Complete: $success transcribed, $fail failed" -ForegroundColor White
Write-Host ""
if ($fail -gt 0) {
    Write-Host "Re-run the script to retry failed files." -ForegroundColor Yellow
}
Write-Host ""
