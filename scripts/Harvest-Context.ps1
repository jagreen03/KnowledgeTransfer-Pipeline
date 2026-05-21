$InputRoot = "C:\ODIN\TEST_RUN\sessions"
$OutputFile = "C:\ODIN\TEST_RUN\prompts\technical_context_map.txt"

$allJson = Get-ChildItem $InputRoot -Recurse -Filter "extracted_part*.json"
$map = New-Object System.Collections.Generic.HashSet[string]

foreach ($f in $allJson) {
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        # Harvest the architectural nouns
        if ($j.system_transitions) {
            foreach ($t in $j.system_transitions) { $map.Add($t) | Out-Null }
        }
        # Also harvest core architectural components to build the noun-map
        if ($j.core_architecture_and_languages) {
            foreach ($n in $j.core_architecture_and_languages) { $map.Add("Noun: $n") | Out-Null }
        }
    } catch { }
}

$content = "### ACMP Technical Context Map (Harvested from Existing Extractions) ###`n"
foreach ($entry in $map) { $content += "- $entry`n" }

$content | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
Write-Host "Harvested $($map.Count) architectural facts into $OutputFile"