<#
.SYNOPSIS
  Orchestrates the agentic handoff between Cynthia (Synthesis) and Casey (Audit).
#>

$Manifest = Get-Content "C:\ODIN\TEST_RUN\prompts\technical_context_map.txt"
$AuditPrompt = Get-Content "C:\ODIN\TEST_RUN\prompts\prompt-technical-audit.md"

# Cynthia A. River Handoff
Write-Host "Handoff to Cynthia A. River: Building Architectural Runbook..."
Invoke-Agent-Cynthia -Context $Manifest -SourceRoot "C:\ODIN\TEST_RUN\sessions"

# Casey A. Jones Handoff
Write-Host "Handoff to Casey A. Jones: Performing Architectural Gap Analysis..."
Invoke-Agent-Casey -Context $Manifest -AuditPrompt $AuditPrompt

Write-Host "Agentic Synthesis Complete. Runbook and Audit ready for commit."