<#
.SYNOPSIS
  Analyzes each KT part: transcript + OCR -> structured JSON via Claude Code.

.DESCRIPTION
  Defensive AND fail-loud. Protections:
    1. Output goes to a .tmp file first, never directly over the real JSON.
    2. The .tmp must parse as JSON AND exceed a size floor to be accepted.
    3. Only a validated .tmp is moved over the real file - a failed/hung/refusing
       call can never overwrite a good extraction with junk.
    4. "Done" means a VALID JSON already exists, so prior junk is retried.

  FAIL-LOUD behavior (new):
    - Every part's outcome is recorded and written to a report file under
      InputRoot (_analyze_report.txt).
    - If ANY part finishes without a valid JSON, the script EXITS NON-ZERO,
      which halts the pipeline bat before synthesis. This prevents an
      incomplete result from silently becoming a finished-looking summary.
    - Pass -AllowIncomplete to proceed anyway (exit 0) once you've reviewed
      the failures and accept synthesizing from the valid subset.

  Runs claude.exe from -ClaudeCwd so its Read tool can access sessions/.

.PARAMETER AllowIncomplete
  Exit 0 even if some parts failed. Lets the pipeline proceed to synthesis
  with whatever valid JSONs exist. Default: strict (exit 1 on any failure).
#>
[CmdletBinding()]
param(
    [string]$InputRoot     = "C:\ODIN\TEST_RUN\sessions",
    [string]$PromptFile    = "C:\ODIN\TEST_RUN\prompts\prompt-extract-kt-part.md",
    [string]$ClaudeCwd     = "",
    [int]$MinValidBytes    = 1500,
    [int]$MaxTurns         = 100,
    [switch]$AllowIncomplete,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$telemetry = @()
$results   = @()   # per-part outcome records

if ([string]::IsNullOrWhiteSpace($ClaudeCwd)) {
    $ClaudeCwd = Split-Path -Parent $InputRoot
}
if (-not (Test-Path -LiteralPath $ClaudeCwd -PathType Container)) {
    Write-Error "ClaudeCwd does not exist: $ClaudeCwd"
    exit 2
}

function Test-ValidExtraction {
    param([string]$Path, [int]$MinBytes)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt $MinBytes) { return $false }
    try {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
        return $true
    } catch { return $false }
}

# Discover work
$parts = @()
Get-ChildItem $InputRoot -Directory | Sort-Object Name | ForEach-Object {
    $folder = $_
    Get-ChildItem $folder.FullName -Filter "*Part*.mp4" | Sort-Object Name | ForEach-Object {
        if ($_.Name -match "Part(\d+)\.mp4$") {
            $partNum    = $matches[1]
            $transcript = Join-Path $folder.FullName "transcripts_part$partNum.txt"
            $ocrFile    = Join-Path $folder.FullName "ocr_part$partNum.json"
            $outFile    = Join-Path $folder.FullName "extracted_part$partNum.json"
            
            $parts += [PSCustomObject]@{
                Folder     = $folder.Name
                Part       = $partNum
                Transcript = $transcript
                OcrFile    = $ocrFile
                OutFile    = $outFile
                Ready      = (Test-Path $transcript)
                Done       = Test-ValidExtraction -Path $outFile -MinBytes $MinValidBytes
            }
        }
    }
}

$todo     = $parts | Where-Object { $_.Ready -and -not $_.Done }
$done     = ($parts | Where-Object { $_.Done }).Count
$notReady = ($parts | Where-Object { -not $_.Ready }).Count

Write-Host ("=" * 70)
Write-Host "KT Analysis (transcript + OCR -> JSON via Claude Code)"
Write-Host "  Source:     $InputRoot"
Write-Host "  Prompt:     $PromptFile"
Write-Host "  Claude cwd: $ClaudeCwd"
Write-Host "  Min valid:  $MinValidBytes bytes"
Write-Host "  Mode:       $(if ($AllowIncomplete) { 'ALLOW INCOMPLETE (exit 0 on failures)' } else { 'STRICT (exit 1 on any failure)' })"
Write-Host ("=" * 70)
Write-Host "  Total parts:       $($parts.Count)"
Write-Host "  Already valid:     $done"
Write-Host "  Not ready:         $notReady (missing transcript)"
Write-Host "  To process/retry:  $($todo.Count)`n"

# Record already-valid parts as OK in the results set.
foreach ($p in ($parts | Where-Object { $_.Done })) {
    $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome="OK (pre-existing)"; Bytes=(Get-Item -LiteralPath $p.OutFile).Length }
}
# Record not-ready parts as a failure category.
foreach ($p in ($parts | Where-Object { -not $_.Ready })) {
    $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome="NOT_READY (missing transcript)"; Bytes=0 }
}

if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt file not found: $PromptFile"
    exit 2
}
$promptTemplate = Get-Content $PromptFile -Raw

$i = 0
foreach ($p in $todo) {
    $i++
    Write-Host "[$i/$($todo.Count)] $($p.Folder) Part$($p.Part)"

    # REPLACED FRAMES_PATH WITH OCR_PATH
    $prompt = $promptTemplate `
        -replace '<TRANSCRIPT_PATH>', $p.Transcript `
        -replace '<OCR_PATH>',        $p.OcrFile `
        -replace '<OUTPUT_PATH>',     $p.OutFile

    if ($DryRun) {
        Write-Host "  (dry run; skipping claude)`n"
        $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome="DRYRUN"; Bytes=0 }
        continue
    }

    $tmpFile = "$($p.OutFile).tmp"
    if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }

    $outcome = "UNKNOWN"
    $bytes   = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Push-Location -LiteralPath $ClaudeCwd
        try {
            $claudeOutput = & claude -p $prompt `
                --dangerously-skip-permissions `
                --allowedTools "Read,Glob" `
                --output-format text `
                --max-turns $MaxTurns
        } finally {
            Pop-Location
        }
        $claudeOutput | Out-File -FilePath $tmpFile -Encoding UTF8
        $sw.Stop()

        $tmpLen = if (Test-Path -LiteralPath $tmpFile) { (Get-Item -LiteralPath $tmpFile).Length } else { 0 }

        if ($tmpLen -lt $MinValidBytes) {
            Write-Warning ("  FAILED_SMALL: {0} bytes < {1}. Existing file (if any) left untouched." -f $tmpLen, $MinValidBytes)
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
            $outcome = "FAILED_SMALL ($tmpLen bytes)"
        }
        else {
            $jsonValid = $false
            try { Get-Content -LiteralPath $tmpFile -Raw | ConvertFrom-Json | Out-Null; $jsonValid = $true } catch { $jsonValid = $false }
            if (-not $jsonValid) {
                Write-Warning "  FAILED_JSON: output not valid JSON. Discarding; existing file (if any) left untouched."
                Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                $outcome = "FAILED_JSON"
            } else {
                Move-Item -LiteralPath $tmpFile -Destination $p.OutFile -Force
                $bytes   = (Get-Item -LiteralPath $p.OutFile).Length
                $outcome = "OK"
                Write-Host ("  -> extracted_part{0}.json ({1} bytes, {2:F1}s) [validated]`n" -f $p.Part, $bytes, $sw.Elapsed.TotalSeconds)
                $telemetry += [PSCustomObject]@{ session=$p.Folder; part=[int]$p.Part; size_bytes=$bytes; time_seconds=[math]::Round($sw.Elapsed.TotalSeconds,1) }
            }
        }
    } catch {
        $sw.Stop()
        Write-Warning "  FAILED_EXCEPTION: $_"
        if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
        $outcome = "FAILED_EXCEPTION"
    }

    $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome=$outcome; Bytes=$bytes }
}

# ---- Report ----
$failed = $results | Where-Object { $_.Outcome -notlike "OK*" -and $_.Outcome -ne "DRYRUN" }
$okCnt  = ($results | Where-Object { $_.Outcome -like "OK*" }).Count

$reportPath = Join-Path $InputRoot "_analyze_report.txt"
$report = @()
$report += "KT Analyze report  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += ("=" * 60)
$report += "Total parts: $($parts.Count)   Valid: $okCnt   Failed: $($failed.Count)"
$report += ("=" * 60)
foreach ($r in ($results | Sort-Object Folder, {[int]$_.Part})) {
    $report += ("{0,-22} Part{1,-3} {2,-12} {3}" -f $r.Folder, $r.Part, "$($r.Bytes)b", $r.Outcome)
}
$report | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host ""
Write-Host ("=" * 70)
Write-Host "Analyze summary: $okCnt valid, $($failed.Count) failed.  Report: $reportPath"
if ($failed.Count -gt 0) {
    Write-Host "Failed parts:" -ForegroundColor Yellow
    foreach ($f in ($failed | Sort-Object Folder, {[int]$_.Part})) {
        Write-Host ("  - {0} Part{1}: {2}" -f $f.Folder, $f.Part, $f.Outcome) -ForegroundColor Yellow
    }
}
Write-Host ("=" * 70)

# Telemetry
if ($telemetry.Count -gt 0) {
    $jsFile = Join-Path $InputRoot "telemetry.js"
    "const telemetryData = " + ($telemetry | ConvertTo-Json -Depth 5 -Compress) + ";" |
        Out-File -FilePath $jsFile -Encoding UTF8 -Force
    Write-Host "[Telemetry Updated] $jsFile"
}

# ---- Fail-loud exit ----
if ($failed.Count -gt 0 -and -not $AllowIncomplete) {
    Write-Host ""
    Write-Host "STRICT MODE: $($failed.Count) part(s) failed - exiting non-zero to halt the pipeline before synthesis." -ForegroundColor Red
    Write-Host "Options: re-run this bat to retry the failed parts, or pass -AllowIncomplete to synthesize from the valid subset." -ForegroundColor Red
    exit 1
}

Write-Host "Complete."
exit 0