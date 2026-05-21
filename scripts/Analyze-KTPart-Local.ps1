<#
.SYNOPSIS
  Analyzes each KT part: transcript -> structured JSON via Local Ollama.
#>
[CmdletBinding()]
param(
    [string]$InputRoot     = "C:\ODIN\TEST_RUN\sessions",
    [string]$OllamaUrl     = "http://localhost:11434/api/generate",
    [string]$OllamaModel = "qwen2.5-coder:7b",
    [int]$MinValidBytes    = 150, 
    [switch]$AllowIncomplete,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$results   = @()

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
            $outFile    = Join-Path $folder.FullName "extracted_part$partNum.json"
            
            $parts += [PSCustomObject]@{
                Folder     = $folder.Name
                Part       = $partNum
                Transcript = $transcript
                OutFile    = $outFile
                Ready      = (Test-Path $transcript)
                Done       = Test-ValidExtraction -Path $outFile -MinBytes $MinValidBytes
            }
        }
    }
}

$todo = $parts | Where-Object { $_.Ready -and -not $_.Done }
$done = ($parts | Where-Object { $_.Done }).Count

Write-Host ("=" * 70)
Write-Host "KT Analysis (Local LLM via Ollama -> JSON)"
Write-Host "  Model:      $OllamaModel"
Write-Host "  Endpoint:   $OllamaUrl"
Write-Host ("=" * 70)
Write-Host "  Total parts:       $($parts.Count)"
Write-Host "  Already valid:     $done"
Write-Host "  To process/retry:  $($todo.Count)`n"

foreach ($p in ($parts | Where-Object { $_.Done })) {
    $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome="OK (pre-existing)"; Bytes=(Get-Item -LiteralPath $p.OutFile).Length }
}

# STRICT JSON ENFORCEMENT
$systemString = "You are an architectural extraction engine. You must output a single, valid JSON object. Do not include XML, code snippets, or conversational text. Output ONLY: { 'core_architecture_and_languages': [], 'development_environments_and_ides': [], 'database_and_testing_utilities': [], 'infrastructure_and_deployment': [], 'action_items': [], 'system_transitions': [] }"

$schemaString = '{"core_architecture_and_languages": ["list of strings"], "development_environments_and_ides": ["list of strings"], "database_and_testing_utilities": ["list of strings"], "infrastructure_and_deployment": ["list of strings"], "action_items": ["list of strings"], "system_transitions": ["SourceComponent -> Action -> TargetComponent"]}'

$i = 0
foreach ($p in $todo) {
    $i++
    Write-Host "[$i/$($todo.Count)] $($p.Folder) Part$($p.Part)"

    if ($DryRun) {
        Write-Host "  (dry run; skipping Ollama)`n"
        $results += [PSCustomObject]@{ Folder=$p.Folder; Part=$p.Part; Outcome="DRYRUN"; Bytes=0 }
        continue
    }

    $tmpFile = "$($p.OutFile).tmp"
    if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force }

    $outcome = "UNKNOWN"
    $bytes   = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $transcriptText = Get-Content -LiteralPath $p.Transcript -Raw
        $ocrText = ""
        $sessionDir = Join-Path $InputRoot $p.Folder
        $ocrFile = Join-Path $sessionDir "ocr_part$($p.Part).json"
        
        if (Test-Path -LiteralPath $ocrFile) {
            $ocrData = Get-Content -LiteralPath $ocrFile -Raw | ConvertFrom-Json
            $ocrText = "`n`n### VISUAL TEXT FROM PRESENTATION SLIDES ###`n"
            $ocrCharLimit = 15000 
            
            foreach ($prop in $ocrData.psobject.properties) {
                if ($ocrText.Length -gt $ocrCharLimit) {
                    $ocrText += "`n[Notice: Remaining slides truncated to prevent memory overflow]`n"
                    break
                }
                $ocrText += "`n[Slide Ref: $($prop.Name)]`n$($prop.Value)`n"
            }
        }

        # Load the auto-generated context map
        $contextMap = ""
        if (Test-Path "C:\ODIN\TEST_RUN\prompts\technical_context_map.txt") {
            $contextMap = Get-Content "C:\ODIN\TEST_RUN\prompts\technical_context_map.txt" -Raw
        }
		
        # Build the final payload
        $combinedPayload = "Extract the following information as a valid JSON object matching this schema: $schemaString. `n`nUse this Technical Context Map for architectural alignment:`n$contextMap`n`n### SPOKEN TRANSCRIPT ###`n$transcriptText`n`n### VISUAL TEXT FROM SLIDES ###`n$ocrText"
        $combinedPayload = $combinedPayload -replace "[\x00-\x08\x0B-\x0C\x0E-\x1F]", " "
		
        $bodyObj = [ordered]@{
            model  = $OllamaModel
            system = $systemString
            prompt = $combinedPayload
            format = "json"
            stream = $false
            options = @{
                temperature = 0.1
                num_ctx = 32768 
            }
        }
        
        $jsonString = $bodyObj | ConvertTo-Json -Depth 5 -Compress
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonString)

        $response = Invoke-RestMethod -Uri $OllamaUrl -Method Post -Body $utf8Bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 600
        
        $response.response | Out-File -FilePath $tmpFile -Encoding UTF8
        $sw.Stop()

        $tmpLen = if (Test-Path -LiteralPath $tmpFile) { (Get-Item -LiteralPath $tmpFile).Length } else { 0 }

        if ($tmpLen -lt $MinValidBytes) {
            Write-Warning ("  FAILED_SMALL: {0} bytes < {1}. Existing file left untouched." -f $tmpLen, $MinValidBytes)
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
            $outcome = "FAILED_SMALL ($tmpLen bytes)"
        }
        else {
            $jsonValid = $false
            try { Get-Content -LiteralPath $tmpFile -Raw | ConvertFrom-Json | Out-Null; $jsonValid = $true } catch { $jsonValid = $false }
            if (-not $jsonValid) {
                Write-Warning "  FAILED_JSON: output not valid JSON. Discarding."
                Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                $outcome = "FAILED_JSON"
            } else {
                Move-Item -LiteralPath $tmpFile -Destination $p.OutFile -Force
                $bytes   = (Get-Item -LiteralPath $p.OutFile).Length
                $outcome = "OK"
                Write-Host ("  -> extracted_part{0}.json ({1} bytes, {2:F1}s) [validated]`n" -f $p.Part, $bytes, $sw.Elapsed.TotalSeconds)
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

$failed = $results | Where-Object { $_.Outcome -notlike "OK*" -and $_.Outcome -ne "DRYRUN" }
if ($failed.Count -gt 0 -and -not $AllowIncomplete) {
    Write-Host "STRICT MODE: $($failed.Count) part(s) failed - exiting non-zero." -ForegroundColor Red
    exit 1
}
exit 0