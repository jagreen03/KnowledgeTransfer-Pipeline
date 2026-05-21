<#
.SYNOPSIS
  Splits flat raw MP4 files from -InputDir into ChunkMin-minute chunks
  under -OutputDir\<sessionId>\Part<N>.mp4.

.DESCRIPTION
  Designed for the TEST_RUN layout where raw MP4s live in input_mp4\
  with no subfolder structure. Each source MP4 becomes one session folder.
  The session ID is extracted from the filename via regex (default: a
  YYYYMMDD_HHMMSS date stamp). Uses ffmpeg -c copy so no re-encoding -
  splits are I-frame aligned and fast.

  Idempotent: existing session folders with Part*.mp4 chunks are skipped
  unless -Force is set.

.PARAMETER InputDir
  Folder containing raw MP4 files.

.PARAMETER OutputDir
  Folder where session subfolders are created.

.PARAMETER ChunkMin
  Maximum chunk duration in minutes. Default: 15.

.PARAMETER SessionIdPattern
  Regex to extract a session ID from the source filename. First capture
  group wins. Default: '(\d{8}_\d{6})' which matches yyyyMMdd_HHmmss.

.PARAMETER Limit
  Only process the first N source files. Useful for smoke-testing the
  full pipeline before committing to a multi-hour run. Default: all.

.PARAMETER Force
  Re-split sessions even if they already have Part chunks.

.EXAMPLE
  # Smoke test with one file:
  .\Split-KTInput.ps1 -InputDir C:\ODIN\TEST_RUN\input_mp4 -OutputDir C:\ODIN\TEST_RUN\sessions -Limit 1

.EXAMPLE
  # Full run:
  .\Split-KTInput.ps1 -InputDir C:\ODIN\TEST_RUN\input_mp4 -OutputDir C:\ODIN\TEST_RUN\sessions
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputDir,

    [Parameter(Mandatory)]
    [string]$OutputDir,

    [int]$ChunkMin = 15,

    [string]$SessionIdPattern = '(\d{8}_\d{6})',

    [int]$Limit = 0,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Pre-flight
try {
    & ffmpeg  -version 2>&1 | Out-Null
    & ffprobe -version 2>&1 | Out-Null
} catch {
    Write-Error "ffmpeg/ffprobe not on PATH. Install: winget install Gyan.FFmpeg"
    exit 1
}

if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    Write-Error "Input directory not found: $InputDir"
    exit 1
}

$null = New-Item -ItemType Directory -Path $OutputDir -Force

$ChunkSec = $ChunkMin * 60

Write-Host ("=" * 78)
Write-Host "KT input splitter"
Write-Host "  Input:    $InputDir"
Write-Host "  Output:   $OutputDir"
Write-Host "  Chunk:    $ChunkMin minutes (ffmpeg -c copy, I-frame aligned)"
if ($Limit -gt 0) { Write-Host "  Limit:    first $Limit file(s) only" -ForegroundColor Yellow }
if ($Force)       { Write-Host "  Force:    YES (will re-split existing sessions)" -ForegroundColor Yellow }
Write-Host ("=" * 78)

$mp4s = Get-ChildItem -LiteralPath $InputDir -Filter "*.mp4" -File | Sort-Object Name
if (-not $mp4s -or $mp4s.Count -eq 0) {
    Write-Warning "No MP4 files in $InputDir"
    return
}
if ($Limit -gt 0) {
    $mp4s = $mp4s | Select-Object -First $Limit
}

$summary = New-Object System.Collections.Generic.List[object]

foreach ($file in $mp4s) {
    Write-Host ""
    Write-Host "Source: $($file.Name)" -ForegroundColor White

    # Extract session ID
    if ($file.Name -match $SessionIdPattern) {
        $sessionId = $matches[1]
    } else {
        $sessionId = [IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '[^\w\-]', '_'
        Write-Host "  (no session pattern match; using sanitized filename: $sessionId)" -ForegroundColor DarkYellow
    }

    $sessionDir = Join-Path $OutputDir $sessionId
    $null = New-Item -ItemType Directory -Path $sessionDir -Force

    # Idempotency
    $existing = Get-ChildItem -LiteralPath $sessionDir -Filter "Part*.mp4" -File -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        Write-Host "  Already split: $($existing.Count) part(s) in $sessionId - SKIPPING" -ForegroundColor DarkGray
        $summary.Add([pscustomobject]@{Session=$sessionId; Parts=$existing.Count; Status="SKIPPED"})
        continue
    }
    if ($existing -and $Force) {
        Write-Host "  Removing $($existing.Count) existing part(s)..." -ForegroundColor DarkYellow
        $existing | Remove-Item -Force
    }

    # Duration
    $rawDur = & ffprobe -v quiet -show_entries format=duration -of csv=p=0 -- $file.FullName 2>$null
    $totalSec = 0.0
    if (-not [double]::TryParse($rawDur, [ref]$totalSec)) {
        Write-Host "  Cannot read duration; SKIPPING" -ForegroundColor Red
        $summary.Add([pscustomobject]@{Session=$sessionId; Parts=0; Status="NO_DURATION"})
        continue
    }
    $totalMin   = [math]::Round($totalSec / 60, 1)
    $totalParts = [math]::Ceiling($totalSec / $ChunkSec)
    Write-Host "  Session ID: $sessionId" -ForegroundColor Gray
    Write-Host "  Duration:   $totalMin min  =>  $totalParts part(s) of $ChunkMin min" -ForegroundColor Gray

    # Split
    $part = 1
    for ($start = 0; $start -lt $totalSec; $start += $ChunkSec) {
        $thisDur = [math]::Min($ChunkSec, ($totalSec - $start))
        $outFile = Join-Path $sessionDir "Part$part.mp4"
        & ffmpeg -i $file.FullName -ss $start -t $thisDur -c copy $outFile -y -loglevel quiet
        if (Test-Path -LiteralPath $outFile) {
            $sizeMB = [math]::Round((Get-Item -LiteralPath $outFile).Length / 1MB, 1)
            $durMin = [math]::Round($thisDur / 60, 1)
            Write-Host ("    Part {0,2} of {1}: {2,5} MB, {3,4} min" -f $part, $totalParts, $sizeMB, $durMin) -ForegroundColor Cyan
        } else {
            Write-Host "    Part $part FAILED" -ForegroundColor Red
        }
        $part++
    }
    $summary.Add([pscustomobject]@{Session=$sessionId; Parts=($part-1); Status="OK"})
}

Write-Host ""
Write-Host ("=" * 78)
Write-Host "Summary:"
$summary | Format-Table -AutoSize
