<#
.SYNOPSIS
  Final stage: a single Claude Code pass over the locally-built KT_Summary.md to
  produce a high-level executive software-architecture overview.

.DESCRIPTION
  The local Ollama pipeline does the heavy per-part extraction and synthesis
  (free, unthrottled, sovereign). This one optional pass spends a single Claude
  call to add the kind of high-level architectural narrative + diagram that a 7B
  local model is weaker at: naming the system's role, summarizing the dominant
  patterns, and producing one clean top-level Mermaid architecture diagram.

  Defensive: reads the local summary, runs claude from -ClaudeCwd so Read works,
  temp-writes and size-validates the output before replacing any existing
  overview. Never clobbers a good overview with a tiny failed response.

  This stage is OPTIONAL and is the only part of the pipeline that uses the
  network / Claude. If claude.exe is absent or unauthenticated, it warns and
  exits 0 (does not fail the pipeline) unless -Strict is given.
#>
[CmdletBinding()]
param(
    [string]$SummaryFile   = "C:\ODIN\TEST_RUN\output_analysis\KT_Summary.md",
    [string]$OverviewFile  = "C:\ODIN\TEST_RUN\output_analysis\KT_Overview.md",
    [string]$PromptFile    = "C:\ODIN\TEST_RUN\prompts\prompt-overview-claude.md",
    [string]$ClaudeCwd     = "C:\ODIN\TEST_RUN",
    [int]$MinValidBytes    = 800,
    [int]$MaxTurns         = 30,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

function Fail-Or-Skip { param([string]$Msg)
    if ($Strict) { Write-Error $Msg; exit 1 }
    Write-Warning "$Msg  (optional stage; exiting 0)"
    exit 0
}

if (-not (Test-Path -LiteralPath $SummaryFile)) {
    Fail-Or-Skip "Summary not found: $SummaryFile - run synthesis first."
}
if (-not (Test-Path -LiteralPath $ClaudeCwd -PathType Container)) {
    Fail-Or-Skip "ClaudeCwd does not exist: $ClaudeCwd"
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Fail-Or-Skip "claude.exe not found on PATH - skipping high-level overview."
}

# Prompt: use file if present, else a sensible built-in default.
if (Test-Path -LiteralPath $PromptFile) {
    $promptTemplate = Get-Content -LiteralPath $PromptFile -Raw
} else {
    $promptTemplate = @'
You are an enterprise software architect. You are given a Markdown knowledge-transfer
summary of the Anthem Care Management Platform (ACMP), assembled from many KT session
extractions. Read the file at <SUMMARY_PATH> in full.

Produce a concise, high-level EXECUTIVE ARCHITECTURE OVERVIEW in Markdown with exactly
these sections:

# ACMP - High-Level Architecture Overview

## What ACMP Is
2-3 sentences: the system's business purpose and where it sits in the enterprise.

## Dominant Technical Patterns
A short bullet list of the 4-6 most important architectural patterns evident in the
summary (e.g. mixed SOAP/REST middleware, dual SQL+NoSQL persistence, batch + event
flows). One sentence each.

## Top-Level Architecture Diagram
A single Mermaid `flowchart LR` showing the major layers as subgraphs (Intake/UI,
Middleware/Gateway, Core Services, Data Stores, External Vendors) with directed edges
for the principal data flows. Use [(cylinders)] for databases, {{hexagons}} for
external systems, (rounded) for services, [rectangles] for UIs. Keep it under 14 nodes.
Only include components actually named in the summary; do not invent.

## Key Risks and Open Questions
A short bullet list of the most important things a new engineering team must clarify
before relying on this KT.

Rules: tight prose, valid Mermaid in a ```mermaid fence, no preamble, no sign-off.
Output ONLY the Markdown document.

## CRITICAL: Do NOT use any tools to write files. Output ONLY the raw markdown text.
'@
}

$prompt = $promptTemplate -replace '<SUMMARY_PATH>', $SummaryFile

$tmpFile = "$OverviewFile.tmp"
if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }

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
} catch {
    if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
    Fail-Or-Skip "Claude overview call failed: $_"
}
$sw.Stop()

$tmpLen = if (Test-Path -LiteralPath $tmpFile) { (Get-Item -LiteralPath $tmpFile).Length } else { 0 }
if ($tmpLen -lt $MinValidBytes) {
    if (Test-Path -LiteralPath $OverviewFile) { Write-Warning "Existing overview left intact (new output too small)." }
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    Fail-Or-Skip ("Overview output too small ({0} bytes < {1})." -f $tmpLen, $MinValidBytes)
}

Move-Item -LiteralPath $tmpFile -Destination $OverviewFile -Force
$size = (Get-Item -LiteralPath $OverviewFile).Length
Write-Host ("Wrote: $OverviewFile  ({0} bytes, {1:F1}s)" -f $size, $sw.Elapsed.TotalSeconds)
exit 0
