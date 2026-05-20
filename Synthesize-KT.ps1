<#
.SYNOPSIS
  Consolidates per-part JSON extractions into a single KT_Summary.md.

.DESCRIPTION
  Reads all extracted_part*.json files under InputRoot, asks Claude to
  de-duplicate and synthesize into a readable engineering reference.
  Uses --allowedTools constraint.

.NOTES
  Run AFTER Analyze-KTPart.ps1 has produced all per-part JSON files.
#>
[CmdletBinding()]
param(
    [string]$InputRoot  = "C:\ODIN\GeminiReady_ACMP_Modules",
    [string]$PromptFile = "C:\ODIN\_Scripts\prompt-synthesize-kt.md",
    [string]$OutputFile = "C:\ODIN\GeminiReady_ACMP_Modules\KT_Summary.md",
    [int]$MaxTurns      = 80
)

$ErrorActionPreference = "Stop"

$jsons = Get-ChildItem $InputRoot -Recurse -Filter "extracted_part*.json" | Sort-Object FullName
Write-Host "Found $($jsons.Count) per-part JSON extractions."
if ($jsons.Count -eq 0) {
    Write-Error "No extracted_part*.json files. Run Analyze-KTPart.ps1 first."
    return
}

if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
}

<#
if (Test-Path $OutputFile) {
    $confirm = Read-Host "$OutputFile exists. Overwrite? (y/N)"
    if ($confirm -ne 'y') { return }
}
#>

if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt file not found: $PromptFile"
    return
}

$prompt = (Get-Content $PromptFile -Raw) `
    -replace '<INPUT_ROOT>',  $InputRoot `
    -replace '<OUTPUT_FILE>', $OutputFile

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# claude -p $prompt --dangerously-skip-permissions --allowedTools "Read,Write,Glob" --output-format text --max-turns $MaxTurns
<#########
the above line is commented out because it will cause the message below
WARNING:          No output file written.
The fix is the command below where the output is captured in variable $claudeOutput and 
##########>
$claudeOutput = & claude -p $prompt --dangerously-skip-permissions --allowedTools "Read,Glob" --output-format text --max-turns $MaxTurns
$claudeOutput | Out-File -FilePath $OutputFile -Encoding UTF8

$sw.Stop()

if (Test-Path $OutputFile) {
    $size = (Get-Item $OutputFile).Length
    Write-Host ("`nWrote: $OutputFile  ({0} bytes, {1:F1}s)" -f $size, $sw.Elapsed.TotalSeconds)
} else {
    Write-Warning "Output file not created."
}
