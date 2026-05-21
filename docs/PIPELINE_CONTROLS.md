# Pipeline Operational Controls

## The "Dream" Manifest
The repository maintains a living architectural state via `technical_context_map.txt`. 

### The Harvest Loop
1. **Extraction**: `Analyze-KTPart-Local.ps1` identifies Nouns (architecture) and Verbs (transitions).
2. **Seeding**: `scripts/Sync-ArchitectureManifest.ps1` harvests new causal edges into the manifest.
3. **Synthesis**: `Synthesize-KT-Local.ps1` uses the manifest as ground truth to generate the `TECHNICAL_RUNBOOK.md`.

## PBG-H Specification (Hierarchical Visualization)
To keep diagrams readable, the engine enforces PBG-H:
* **L0 View**: High-level system interactions (Causal Edges).
* **L1 View**: Domain-specific logic flows (e.g., Clinical Review Workflow).
* **L2 View**: Component-level interaction (e.g., MongoDB/DB2 Data Sync).