<#
.SYNOPSIS
  Consolidates per-part JSON extractions into KT_Summary.md using local Ollama,
  with deterministically-generated Mermaid relationship diagrams.

.DESCRIPTION
  Two-part output, by design (SOLID separation of concerns):

    1. DETERMINISTIC (PowerShell): parses the structured JSON fields and emits
       Mermaid diagrams showing relationships between software nouns. A 7B local
       model is unreliable at free-form Mermaid across 50 inputs, so we do not
       ask it to. Code does what code can do reliably.

    2. GENERATIVE (Ollama): the local LLM writes the prose narrative sections.

  Defensive: only VALID per-part JSON is consumed; output is temp-written and
  size-validated before replacing any existing good KT_Summary.md.

  Schema consumed (the local 5-field extraction schema):
    core_architecture_and_languages, development_environments_and_ides,
    database_and_testing_utilities, infrastructure_and_deployment, action_items
  Also tolerates the richer Claude schema fields if present (system_transitions,
  web_service_calls, database_operations, ui_interactions) for the diagrams.
#>
[CmdletBinding()]
param(
    [string]$InputRoot      = "C:\ODIN\TEST_RUN\sessions",
    [string]$OutputFile     = "C:\ODIN\TEST_RUN\output_analysis\KT_Summary.md",
    [string]$OllamaUrl      = "http://localhost:11434/api/generate",
    [string]$OllamaModel    = "qwen2.5:7b",
    [int]$MinPartBytes      = 150,
    [int]$MinSummaryBytes   = 1000,
    [switch]$SkipLLM        # emit only the deterministic diagram doc (fast, no model)
)

$ErrorActionPreference = "Stop"

# ---- Gather VALID per-part JSONs ----
$allJson = Get-ChildItem $InputRoot -Recurse -Filter "extracted_part*.json" | Sort-Object FullName
$valid   = @()
foreach ($f in $allJson) {
    if ($f.Length -ge $MinPartBytes) {
        try { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json | Out-Null; $valid += $f } catch { }
    }
}

Write-Host "Per-part JSONs found:  $($allJson.Count)"
Write-Host "  Valid (used):        $($valid.Count)"
if ($valid.Count -eq 0) {
    Write-Error "No VALID extracted_part*.json files found."
    return
}

# ---- Aggregate software nouns + relationships across all parts ----
# Buckets keyed by category. Use hashtables as sets to dedupe.
$langs   = @{}   # core_architecture_and_languages
$ides    = @{}   # development_environments_and_ides
$dbtools = @{}   # database_and_testing_utilities
$infra   = @{}   # infrastructure_and_deployment
$actions = New-Object System.Collections.Generic.List[string]
$transitions = New-Object System.Collections.Generic.List[string]

function Add-Set { param($Set, $Items) if ($Items) { foreach ($x in $Items) { if ($x -and "$x".Trim() -and "$x" -ne "...") { $Set["$x".Trim()] = $true } } } }

foreach ($f in $valid) {
    try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
    Add-Set $langs   $j.core_architecture_and_languages
    Add-Set $ides    $j.development_environments_and_ides
    Add-Set $dbtools $j.database_and_testing_utilities
    Add-Set $infra   $j.infrastructure_and_deployment
    if ($j.action_items) { foreach ($a in $j.action_items) { if ($a -and "$a".Trim() -and "$a" -ne "...") { $actions.Add("$a".Trim()) } } }
    # Relationship source: prefer rich-schema system_transitions if present.
    if ($j.system_transitions) { foreach ($t in $j.system_transitions) { if ($t -and "$t".Trim()) { $transitions.Add("$t".Trim()) } } }
}

# ---- Mermaid helper: sanitize a node label into a safe id ----
function Get-NodeId { param([string]$Label)
    $id = ($Label -replace '[^A-Za-z0-9]', '_')
    if ($id -match '^[0-9]') { $id = "n$id" }
    return $id
}

# ---- Build deterministic Mermaid: software-category landscape ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('```mermaid')
[void]$sb.AppendLine('flowchart LR')
[void]$sb.AppendLine('  subgraph Languages_and_Frameworks')
foreach ($k in ($langs.Keys | Sort-Object)) { [void]$sb.AppendLine("    $(Get-NodeId $k)([""$k""])") }
[void]$sb.AppendLine('  end')
[void]$sb.AppendLine('  subgraph IDEs_and_Editors')
foreach ($k in ($ides.Keys | Sort-Object)) { [void]$sb.AppendLine("    $(Get-NodeId $k)([""$k""])") }
[void]$sb.AppendLine('  end')
[void]$sb.AppendLine('  subgraph Databases_and_Test_Tools')
foreach ($k in ($dbtools.Keys | Sort-Object)) { [void]$sb.AppendLine("    $(Get-NodeId $k)[(""$k"")]") }
[void]$sb.AppendLine('  end')
[void]$sb.AppendLine('  subgraph Infrastructure_and_Services')
foreach ($k in ($infra.Keys | Sort-Object)) { [void]$sb.AppendLine("    $(Get-NodeId $k){{""$k""}}") }
[void]$sb.AppendLine('  end')
[void]$sb.AppendLine('```')
$landscapeMermaid = $sb.ToString()

# ---- Build deterministic Mermaid: relationship graph from transitions ----
$allNouns = @()
$allNouns += $langs.Keys; $allNouns += $ides.Keys; $allNouns += $dbtools.Keys; $allNouns += $infra.Keys
$allNouns = $allNouns | Sort-Object -Unique

$edges = @{}   # "idA-->idB" => $true (dedupe)

foreach ($t in $transitions) {
    # NEW LOGIC: Split chained strings like "A -> B -> C" into nodes [A, B, C]
    $parts = $t -split "->" | ForEach-Object { $_.Trim() }
    
    # Create edges for each step in the chain
    for ($k = 0; $k -lt $parts.Count - 1; $k++) {
        $a = Get-NodeId $parts[$k]
        $b = Get-NodeId $parts[$k+1]
        
        # Only add if both nodes exist in our extracted architecture
        if ($a -ne $b -and $a -and $b) { 
            $edges["$a-->$b"] = $true 
        }
    }
}

$relMermaid = ""
if ($edges.Count -gt 0) {
    $rb = New-Object System.Text.StringBuilder
    [void]$rb.AppendLine('```mermaid')
    [void]$rb.AppendLine('flowchart LR')
    # declare nodes with friendly labels
    foreach ($noun in $allNouns) {
        $touched = $false
        foreach ($e in $edges.Keys) { if ($e -match (Get-NodeId $noun)) { $touched = $true; break } }
        if ($touched) { [void]$rb.AppendLine("  $(Get-NodeId $noun)([""$noun""])") }
    }
    foreach ($e in ($edges.Keys | Sort-Object)) { [void]$rb.AppendLine("  $e") }
    [void]$rb.AppendLine('```')
    $relMermaid = $rb.ToString()
}

# ---- Optional LLM prose ----
$proseSection = ""
if (-not $SkipLLM) {
    $systemString = "You are an expert technical writer. Synthesize the provided JSON fragments into a cohesive, professional Markdown narrative. Group related topics, maintain technical accuracy, and consolidate action items. Do NOT emit Mermaid diagrams or code fences - diagrams are added separately. Output Markdown prose and tables only."

    $combinedJsonData = ""
    foreach ($f in $valid) {
        $partName = $f.Directory.Name + " - " + $f.Name
        $combinedJsonData += "`n`n### SOURCE: $partName ###`n" + (Get-Content -LiteralPath $f.FullName -Raw)
    }

    $promptString = "Synthesize the following JSON KT extractions into a comprehensive Markdown document with sections for Core Architecture, Development Environments, Databases and Tools, Infrastructure, and a consolidated Action Items list:`n$combinedJsonData"
    $promptString = $promptString -replace "[\x00-\x08\x0B-\x0C\x0E-\x1F]", " "

    $bodyObj = [ordered]@{
        model   = $OllamaModel
        system  = $systemString
        prompt  = $promptString
        stream  = $false
        options = @{ temperature = 0.2; num_ctx = 24576 }
    }
    $jsonString = $bodyObj | ConvertTo-Json -Depth 5 -Compress
    $utf8Bytes  = [System.Text.Encoding]::UTF8.GetBytes($jsonString)

    Write-Host "Synthesizing prose from $($valid.Count) parts via $OllamaModel ..."
    try {
        $response = Invoke-RestMethod -Uri $OllamaUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 1800
        $proseSection = $response.response
    } catch {
        Write-Warning "LLM prose synthesis failed: $_  (continuing with diagrams + structured lists only)"
        $proseSection = ""
    }
}

# ---- Assemble final document ----
$today = Get-Date -Format 'yyyy-MM-dd'
$doc = New-Object System.Text.StringBuilder
[void]$doc.AppendLine("# ACMP Knowledge Transfer & Architecture Summary")
[void]$doc.AppendLine("**Generated:** $today  ")
[void]$doc.AppendLine("**Source parts:** $($valid.Count) valid extractions")
[void]$doc.AppendLine("")
[void]$doc.AppendLine("## Software Landscape")
[void]$doc.AppendLine("Categorized inventory of every software noun extracted across the KT corpus.")
[void]$doc.AppendLine("")
[void]$doc.AppendLine($landscapeMermaid)
[void]$doc.AppendLine("")
if ($relMermaid) {
    [void]$doc.AppendLine("## System Relationships")
    [void]$doc.AppendLine("Directed edges are derived from causal `system_transitions` statements where two known software components co-occur. Arrow direction follows the order described in the source.")
    [void]$doc.AppendLine("")
    [void]$doc.AppendLine($relMermaid)
    [void]$doc.AppendLine("")
} else {
    [void]$doc.AppendLine("## System Relationships")
    [void]$doc.AppendLine("_No causal relationships could be derived deterministically from the source data (no `system_transitions` field populated, or no two known components co-occurred in one statement)._")
    [void]$doc.AppendLine("")
}
if ($proseSection) {
    [void]$doc.AppendLine("## Narrative Summary")
    [void]$doc.AppendLine("")
    [void]$doc.AppendLine($proseSection.Trim())
    [void]$doc.AppendLine("")
}
# Consolidated action items (deterministic, deduped)
$uniqActions = $actions | Sort-Object -Unique
if ($uniqActions.Count -gt 0) {
    [void]$doc.AppendLine("## Consolidated Action Items")
    foreach ($a in $uniqActions) { [void]$doc.AppendLine("- $a") }
    [void]$doc.AppendLine("")
}

$finalText = $doc.ToString()

# ---- Validate + commit (temp-write, never clobber a good summary with junk) ----
$tmpFile = "$OutputFile.tmp"
if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }
$finalText | Out-File -FilePath $tmpFile -Encoding UTF8

$tmpLen = if (Test-Path -LiteralPath $tmpFile) { (Get-Item -LiteralPath $tmpFile).Length } else { 0 }
if ($tmpLen -lt $MinSummaryBytes) {
    Write-Warning ("Summary too small ({0} bytes < {1}). Not overwriting any existing good summary." -f $tmpLen, $MinSummaryBytes)
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    return
}

Move-Item -LiteralPath $tmpFile -Destination $OutputFile -Force
$size = (Get-Item -LiteralPath $OutputFile).Length
Write-Host ("`nWrote: $OutputFile  ({0} bytes) [from {1} parts, {2} relationship edges]" -f $size, $valid.Count, $edges.Count)
