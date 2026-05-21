You are synthesizing a knowledge transfer (KT) reference document for the Anthem Care Management Platform (ACMP), assembled from per-segment JSON extractions of the KT recordings.

Input: a directory tree at <INPUT_ROOT> containing per-session subfolders. Each session subfolder contains one or more files named `extracted_part*.json`. Each JSON has the fields: topics, tech_stack, tools, databases, web_services, web_applications, integrations, acronyms, key_concepts, key_visuals, live_demonstrations, code_repositories, database_objects, page_flows, pain_points_or_limitations, open_questions, summary.

Steps:
1. Glob and read every `extracted_part*.json` under <INPUT_ROOT> recursively.
2. De-duplicate and consolidate entries across all parts:
   - Tools, databases, web services, web applications, code repositories, and acronyms: merge entries with the same name. Combine purpose/definition/context fields by taking the most informative version or merging non-conflicting details.
   - Tech stack: union of all entries.
   - Key concepts: merge by name; concatenate explanations when they differ.
   - Database objects: merge by (database_engine, name). Union the field lists. Prefer the most specific viewer_tool seen.
   - Live demonstrations: do NOT merge - each demonstration is its own datapoint tied to a specific frame and timestamp.
   - Page flows: do NOT merge across sessions. List each as-is.
   - Pain points and open questions: deduplicate similar phrasings.
3. Output the final Markdown document directly to the console with these sections in this order.

# ACMP Knowledge Transfer - Engineering Reference

## Overview
Two paragraphs. First: what ACMP is and what business problem it solves. Second: high-level architecture - what it talks to, what it produces. Draw from the most informative summaries across all parts.

Then a single Mermaid `flowchart LR` block titled "Architecture Overview" showing the major applications, services, and databases as nodes with directed edges. Group related nodes using `subgraph` (e.g., one subgraph for client UIs, one for core services, one for databases, one for external systems). Use these node-shape conventions: applications/UIs as `[Square Brackets]`, services as `(Round Brackets)`, databases as `[(Cylinders)]`, external systems as `{{Hexagons}}`. Keep node count under 15 - this is a zoomed-out view, not a complete catalog. Only include nodes that appear in the consolidated `web_applications`, `web_services`, `databases`, or `integrations` data; do not invent components.

## Tech Stack
Bullet list of all distinct languages, frameworks, and runtimes.

## Tools
Table with columns: Tool | Purpose. Sort alphabetically.

## Code Repositories
Table with columns: Repository | Host | URL | IDE Used | Notable Files. Sort alphabetically by Repository. URL and IDE columns may be empty if never observed; render as `-` in that case. Notable Files: comma-separated, capped at the 5 most informative.

## Databases
Table with columns: Name | Type | What It Stores. Sort alphabetically by name.

## Database Objects
Grouped by database engine. For each engine, a heading-3 (###) with the engine name, followed by a table with columns: Object | Kind | Database | Viewer Tool | Key Fields/Columns | Purpose. Sort by Object name. Key Fields/Columns: comma-separated, capped at the 8 most informative.

## Web Services and APIs
Table with columns: Name | Type | Purpose. Sort alphabetically.

## Web Applications
Bullet list: **Name** - Purpose.

## Page Flows and Service Correlations
This section is the highest-value output. For each `page_flows` entry across all parts:

- Heading-3 (###) with the flow name.
- One sentence on the outcome.
- A numbered list of steps. Each step formatted as: `Page` -> action taken -> **web service** (when a service was identified). When no service correlation exists for a step, omit the service portion but still include the action.
- A "Services exercised:" line enumerating the distinct web services invoked across the flow, comma-separated. If none were identified, write "Services exercised: none identified".
- A Mermaid `sequenceDiagram` block immediately after the Services line. Conventions:
  - `actor User` as the first line.
  - One `participant` per distinct page in the flow (alias the page name to a short identifier if it's long, e.g. `participant Search as Member Search`).
  - One `participant` per distinct web service invoked.
  - Each step becomes either `User->>Page: action` (when the user drives a UI action) or `Page->>Service: action` (when a service is called). Service responses use `Service-->>Page: ...` only when the response shape was observed in the source data.
  - Order arrows by the numbered list above; do not invent steps or responses not present in the source.
  - If a flow has zero service correlations, still emit the sequenceDiagram showing User and the pages, with `Note over` annotations for actions taken.

## Live Demonstrations
Grouped by session folder. For each group, a heading-3 (###) with the session folder name (e.g. `### 20221216_141846`). Under it, a table with columns: Time | Tool | Action | URL/Endpoint | Method | Linked Service | Response. Sort by time within each session. Empty cells render as `-`. Time: extract from the frame_file name (e.g. `t02m11s.jpg` -> `02:11`).

## System Integrations
Two parts:

First, prose description of how systems connect, grouped by data-flow direction (upstream, internal, downstream).

Second, a Mermaid `flowchart LR` block titled "Integration Topology" with three `subgraph` blocks named `Upstream`, `ACMP`, and `Downstream`. Each integration entry becomes an edge with a label describing protocol and cadence (e.g. `-->|REST, on demand|`, `-->|MQ, daily batch|`, `-->|file drop, nightly|`). Only include systems explicitly named in the consolidated `integrations` data; do not invent endpoints. If a direction has no entries, omit that subgraph rather than leaving it empty.

## Glossary
Table with columns: Term | Expansion | Definition. Sort alphabetically by term.

## Key Concepts
For each distinct concept: a heading-3 (###) with the concept name, followed by 1 to 3 sentences of explanation. Group related concepts together.

## Pain Points and Limitations
Consolidated bullet list. Each item should be one clear sentence describing a quirk, workaround, or limitation.

## Key Visuals to Review
Grouped by session folder. For each group, a heading-3 (###) with the session folder name (e.g. `### 20221216_141846`), followed by a bullet list. Each bullet:

`- ` then a code-formatted relative path `<session>/frames_partN/tMMmSSs.jpg` then ` - ` then the description.

Only include the visuals marked as important across the parts. The reader should be able to find each frame on disk from the path.

## Per-Part Index
Table with columns: Session | Part | Topics | Summary. One row per part. Sort by session then part number numerically. Topics column: join with semicolons. Summary column: use the 2-sentence summary from the JSON.

## Open Questions
Consolidated bullet list. Each item: one clear question that needs follow-up from a subject-matter expert before relying on KT alone.

Rules:
- Keep prose tight. Engineers will read this; they want signal, not throat-clearing.
- Use Markdown tables where specified; do not substitute bullet lists.
- Page Flows and Service Correlations is the highest-value section. Render every flow with its sequenceDiagram. Do not drop any flow entries from the source data.
- Mermaid blocks must use valid syntax. Wrap each in ```mermaid ... ``` fences. If a node label contains spaces, use the alias pattern (e.g. `participant S as Member Search Service`) so the syntax stays clean.
- Do not invent components, edges, services, pages, or steps that are not present in the consolidated extraction data. Missing data is fine; fabricated diagrams are not.

## CRITICAL: Do NOT use any tools to write files. Output ONLY the raw markdown text. Do not include any conversational preamble or sign-off. Just the markdown document.