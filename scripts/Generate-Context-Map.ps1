<#
.SYNOPSIS
  Generates a technical_context_map.txt by aggregating transitions
  from existing extracted_part*.json files.
#>
[CmdletBinding()]
param(
    [string]$InputRoot     = "C:\ODIN\TEST_RUN\sessions",
    [string]$OutputFile    = "C:\ODIN\TEST_RUN\prompts\technical_context_map.txt"
)

$allJson = Get-ChildItem $InputRoot -Recurse -Filter "extracted_part*.json"
$map = @{}

foreach ($f in $allJson) {
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        if ($j.system_transitions) {
            foreach ($t in $j.system_transitions) {
                # Simple deduplication
                $map[$t] = $true
            }
        }
    } catch { }
}

$content = "### ACMP Technical Context Map (Auto-Generated) ###`n"
foreach ($key in $map.Keys) {
    $content += "- $key`n"
}

$content | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
Write-Host "Generated context map with $($map.Count) transitions at $OutputFile"