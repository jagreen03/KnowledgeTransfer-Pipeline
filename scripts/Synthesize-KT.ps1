<#
.SYNOPSIS
  Consolidates per-part JSON extractions into a single KT_Summary.md.

.DESCRIPTION
  DEFENSIVE version. Key protections:
    1. Only counts extracted_part*.json files that are VALID JSON above a size
       floor - junk/placeholder files are excluded from the synthesis input.
    2. Writes the summary to a .tmp file first; validates it exceeds a size
       floor before replacing the real KT_Summary.md. A failed synthesis call
       can no longer destroy a good existing summary.
    3. Runs claude.exe from -ClaudeCwd so its Read tool can access the JSONs.

.NOTES
  Run AFTER Analyze-KTPart.ps1 has produced per-part JSON files.
#>
[CmdletBinding()]
param(
    [string]$InputRoot      = "C:\ODIN\TEST_RUN\sessions",
    [string]$PromptFile     = "C:\ODIN\TEST_RUN\prompts\prompt-synthesize-kt.md",
    [string]$OutputFile     = "C:\ODIN\TEST_RUN\output_analysis\KT_Summary.md",
    [string]$ClaudeCwd      = "C:\ODIN\TEST_RUN",
    [int]$MinPartBytes      = 1500,   # per-part JSON smaller than this is junk
    [int]$MinSummaryBytes   = 2000,   # summary smaller than this = failed call
    [int]$MaxTurns          = 80
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ClaudeCwd -PathType Container)) {
    Write-Error "ClaudeCwd does not exist: $ClaudeCwd"
    return
}

# Gather only VALID per-part JSONs. A junk file (too small or unparseable)
# is excluded so it cannot poison the synthesis.
$allJson = Get-ChildItem $InputRoot -Recurse -Filter "extracted_part*.json" | Sort-Object FullName
$valid   = @()
$skipped = @()
foreach ($f in $allJson) {
    $ok = $false
    if ($f.Length -ge $MinPartBytes) {
        try {
            Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json | Out-Null
            $ok = $true
        } catch { $ok = $false }
    }
    if ($ok) { $valid += $f } else { $skipped += $f }
}

Write-Host "Per-part JSONs found:  $($allJson.Count)"
Write-Host "  Valid (used):        $($valid.Count)"
Write-Host "  Skipped (junk):      $($skipped.Count)"
if ($skipped.Count -gt 0) {
    Write-Host "  Skipped files:"
    foreach ($s in $skipped) {
        Write-Host ("    - {0} ({1} bytes)" -f $s.FullName, $s.Length)
    }
}

if ($valid.Count -eq 0) {
    Write-Error "No VALID extracted_part*.json files. Run Analyze-KTPart.ps1 first."
    return
}

# If some parts are junk, warn loudly - the summary will be incomplete.
if ($skipped.Count -gt 0) {
    Write-Warning "$($skipped.Count) part(s) are junk and will be MISSING from the summary."
    Write-Warning "Re-run Analyze-KTPart.ps1 to regenerate them, then re-run this."
}

if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt file not found: $PromptFile"
    return
}

$prompt = (Get-Content $PromptFile -Raw) `
    -replace '<INPUT_ROOT>',  $InputRoot `
    -replace '<OUTPUT_FILE>', $OutputFile

$tmpFile = "$OutputFile.tmp"
if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Run claude from ClaudeCwd so Read can reach the JSONs. Write to TEMP first.
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

# ---- VALIDATION GATE: don't clobber a good summary with a tiny one ----
$tmpLen = if (Test-Path -LiteralPath $tmpFile) { (Get-Item -LiteralPath $tmpFile).Length } else { 0 }

if ($tmpLen -lt $MinSummaryBytes) {
    Write-Warning ("Synthesis output too small ({0} bytes < {1}). Treating as failed call." -f $tmpLen, $MinSummaryBytes)
    if (Test-Path -LiteralPath $OutputFile) {
        Write-Warning "Existing KT_Summary.md left intact (NOT overwritten)."
    }
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    return
}

# Commit: validated tmp replaces the real summary.
Move-Item -LiteralPath $tmpFile -Destination $OutputFile -Force
$size = (Get-Item -LiteralPath $OutputFile).Length
Write-Host ("`nWrote: $OutputFile  ({0} bytes, {1:F1}s) [validated, from {2} parts]" -f $size, $sw.Elapsed.TotalSeconds, $valid.Count)
