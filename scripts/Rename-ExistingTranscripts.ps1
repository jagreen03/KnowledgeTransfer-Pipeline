<#
.SYNOPSIS
  Renames legacy transctips_part<N>.txt files to transcripts_part<N>.txt
  under a given root. Dry-run by default - prints the proposed renames
  without touching the filesystem.

.DESCRIPTION
  This is a non-breaking migration helper. Use it AFTER you've updated
  the writer scripts (transcribe-whisper.py, Transcribe-GeminiReady.ps1)
  and reader script (Analyze-KTPart.ps1) to use the corrected spelling.
  Then run this once with -Apply to rename existing files on disk so the
  updated readers can find them.

.PARAMETER Root
  Top-level directory to recurse under. Defaults to C:\ODIN.

.PARAMETER Apply
  Actually perform the renames. Without this switch, the script only
  prints what it would do.

.PARAMETER ExcludePath
  Optional substring; any path containing this substring is skipped.
  Use this to protect your prototype folder from rename, e.g.:
    -ExcludePath "Prototype"

.EXAMPLE
  # See what would happen, no changes made
  .\Rename-ExistingTranscripts.ps1 -Root C:\ODIN

.EXAMPLE
  # Actually rename, but leave the prototype folder alone
  .\Rename-ExistingTranscripts.ps1 -Root C:\ODIN -ExcludePath "Prototype" -Apply
#>
[CmdletBinding()]
param(
    [string]$Root        = "C:\ODIN",
    [string]$ExcludePath = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root not found or not a directory: $Root"
    exit 1
}

Write-Host ("=" * 70)
Write-Host "Transcript file rename: transctips_part*.txt -> transcripts_part*.txt"
Write-Host "  Root:    $Root"
if ($ExcludePath) { Write-Host "  Exclude: paths containing '$ExcludePath'" }
Write-Host "  Mode:    $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ("=" * 70)

$candidates = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "transctips_part*.txt" -ErrorAction SilentlyContinue
if ($ExcludePath) {
    $candidates = $candidates | Where-Object { $_.FullName -notlike "*$ExcludePath*" }
}

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host "No transctips_part*.txt files found under $Root." -ForegroundColor Yellow
    return
}

Write-Host "Found $($candidates.Count) file(s) to rename:`n"

$renamed   = 0
$skipped   = 0
$conflicts = 0

foreach ($f in $candidates | Sort-Object FullName) {
    $newName = $f.Name -replace '^transctips_', 'transcripts_'
    $newPath = Join-Path $f.DirectoryName $newName

    if (Test-Path -LiteralPath $newPath) {
        Write-Host ("  CONFLICT  " + $f.FullName) -ForegroundColor Red
        Write-Host ("            target already exists: $newName") -ForegroundColor DarkRed
        $conflicts++
        continue
    }

    if ($Apply) {
        try {
            Rename-Item -LiteralPath $f.FullName -NewName $newName -ErrorAction Stop
            Write-Host ("  RENAMED   " + $f.FullName) -ForegroundColor Green
            Write-Host ("            -> $newName") -ForegroundColor DarkGreen
            $renamed++
        } catch {
            Write-Host ("  FAILED    " + $f.FullName) -ForegroundColor Red
            Write-Host ("            $_") -ForegroundColor DarkRed
            $skipped++
        }
    } else {
        Write-Host ("  WOULD     " + $f.FullName) -ForegroundColor Yellow
        Write-Host ("            -> $newName") -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host ("=" * 70)
if ($Apply) {
    Write-Host "Renamed:   $renamed" -ForegroundColor Green
    Write-Host "Skipped:   $skipped"
    Write-Host "Conflicts: $conflicts" -ForegroundColor $(if ($conflicts) { "Red" } else { "Gray" })
} else {
    Write-Host "Dry run only. Re-run with -Apply to perform the renames." -ForegroundColor Yellow
    if ($conflicts -gt 0) {
        Write-Host "$conflicts conflict(s) detected - resolve those manually before -Apply." -ForegroundColor Red
    }
}
Write-Host ""
