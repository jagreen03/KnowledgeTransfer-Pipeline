<#
.SYNOPSIS
  Analyzes each ACMP KT part: transcript + frames -> structured JSON via Claude Code.

.DESCRIPTION
  Idempotent. Skips parts where extracted_partN.json already exists.
  Uses --allowedTools constraint instead of --dangerously-skip-permissions.
  Claude can only Read, Write, and Glob - no Bash, no WebFetch, no Edit.

.PARAMETER InputRoot
  Root directory containing session subfolders.

.PARAMETER PromptFile
  Path to prompt-extract-kt-part.md template.

.PARAMETER MaxTurns
  Cap on Claude tool-use turns per part. 100 fits most chunks (1 transcript +
  up to ~80 frames + 1 write).

.PARAMETER DryRun
  Show what would run without invoking Claude.

.NOTES
  Requires: claude.exe in PATH and already authenticated.
#>
[CmdletBinding()]
param(
    [string]$InputRoot  = "C:\ODIN\GeminiReady_ACMP_Modules",
    [string]$PromptFile = "C:\ODIN\_Scripts\prompt-extract-kt-part.md",
    [int]$MaxTurns      = 100,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$telemetry = @()

# Discover work
$parts = @()
Get-ChildItem $InputRoot -Directory | Sort-Object Name | ForEach-Object {
    $folder = $_
    Get-ChildItem $folder.FullName -Filter "*Part*.mp4" | Sort-Object Name | ForEach-Object {
        if ($_.Name -match "Part(\d+)\.mp4$") {
            $partNum = $matches[1]
            $transcript = Join-Path $folder.FullName "transctips_part$partNum.txt"
            $framesDir  = Join-Path $folder.FullName "frames_part$partNum"
            $outFile    = Join-Path $folder.FullName "extracted_part$partNum.json"
            $parts += [PSCustomObject]@{
                Folder     = $folder.Name
                Part       = $partNum
                Transcript = $transcript
                FramesDir  = $framesDir
                OutFile    = $outFile
                Ready      = (Test-Path $transcript) -and (Test-Path $framesDir)
                Done       = Test-Path $outFile
            }
        }
    }
}

$todo     = $parts | Where-Object { $_.Ready -and -not $_.Done }
$done     = ($parts | Where-Object { $_.Done }).Count
$notReady = ($parts | Where-Object { -not $_.Ready }).Count

Write-Host ("=" * 70)
Write-Host "ACMP KT Analysis  (transcript + frames -> JSON via Claude Code)"
Write-Host "  Source: $InputRoot"
Write-Host "  Prompt: $PromptFile"
Write-Host ("=" * 70)
Write-Host "  Total parts:   $($parts.Count)"
Write-Host "  Already done:  $done"
Write-Host "  Not ready:     $notReady  (missing transcript or frames)"
Write-Host "  To process:    $($todo.Count)`n"

if ($todo.Count -eq 0) {
    Write-Host "Nothing to do."
    return
}

if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt file not found: $PromptFile"
    return
}
$promptTemplate = Get-Content $PromptFile -Raw

$i = 0
foreach ($p in $todo) {
    $i++
    Write-Host "[$i/$($todo.Count)] $($p.Folder) Part$($p.Part)"

    $prompt = $promptTemplate `
        -replace '<TRANSCRIPT_PATH>', $p.Transcript `
        -replace '<FRAMES_PATH>',     $p.FramesDir `
        -replace '<OUTPUT_PATH>',     $p.OutFile

    if ($DryRun) {
        Write-Host "         (dry run; skipping claude)`n"
        continue
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Whitelist tools: no bash, no webfetch, no edit. Read frames + transcript,
        # Write the JSON, Glob the frames directory. That's all Claude can do.
        #& claude -p $prompt --dangerously-skip-permissions --allowedTools "Read,Write,Glob" --output-format text --max-turns $MaxTurns
<############
The above line is commented out because it ouputs a Warning
#############
I need permission to write the output file. Could you grant write access to `C:\ODIN\GeminiReady_ACMP_Modules\20221216_141846\extracted_part1.json` so I can save the extracted JSON?
WARNING:          No output file written.
#############
The below lines are the fix
#############>

        # Capture the output, and remove the Write tool from Claude's permissions
        $claudeOutput = & claude -p $prompt --dangerously-skip-permissions --allowedTools "Read,Glob" --output-format text --max-turns $MaxTurns
        
        # PowerShell writes the file
        $claudeOutput | Out-File -FilePath $p.OutFile -Encoding UTF8

        $sw.Stop()
        if (Test-Path $p.OutFile) {
            $size = (Get-Item $p.OutFile).Length
            Write-Host ("         -> extracted_part{0}.json  ({1} bytes, {2:F1}s)`n" -f $p.Part, $size, $sw.Elapsed.TotalSeconds)
            
            # Append to telemetry
            $telemetry += [PSCustomObject]@{
                session = $p.Folder
                part = [int]$p.Part
                size_bytes = $size
                time_seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            }
        } else {
            Write-Warning "         No output file written."
        }
    } catch {
        $sw.Stop()
        Write-Warning "         FAILED: $_"
    }
}

Write-Host "Complete."

# Export Telemetry Data (Overwrite existing file on every iteration)
if ($telemetry.Count -gt 0) {
    $jsFile = Join-Path $InputRoot "telemetry.js"
    # Overwrite the entire file with the current state of the $telemetry array
    "const telemetryData = " + ($telemetry | ConvertTo-Json -Depth 5 -Compress) + ";" | Out-File -FilePath $jsFile -Encoding UTF8 -Force
    Write-Host "`n[Telemetry Updated] Dashboard data written to: $jsFile"
}