You are synthesizing a knowledge transfer (KT) reference document for the Anthem Care Management Platform (ACMP), assembled from per-segment JSON extractions of the KT recordings.

Input: a directory tree at <INPUT_ROOT> containing per-session subfolders. Each session subfolder contains one or more files named `extracted_part*.json`. Each JSON has the fields: topics, tech_stack, tools, databases, web_services, web_applications, integrations, acronyms, key_concepts, key_visuals, pain_points_or_limitations, open_questions, summary.

Steps:
1. Glob and read every `extracted_part*.json` under <INPUT_ROOT> recursively.
2. De-duplicate and consolidate entries across all parts:
   - Tools, databases, web services, web applications, and acronyms: merge entries with the same name. Combine purpose/definition fields by taking the most informative version or merging non-conflicting details.
   - Tech stack: union of all entries.
   - Key concepts: merge by name; concatenate explanations when they differ.
   - Pain points and open questions: deduplicate similar phrasings.
3. Output the final Markdown document directly to the console with these sections in this order:

# ACMP Knowledge Transfer - Engineering Reference

## Overview
Two paragraphs. First: what ACMP is and what business problem it solves. Second: high-level architecture - what it talks to, what it produces. Draw from the most informative summaries across all parts.

## Tech Stack
Bullet list of all distinct languages, frameworks, and runtimes.

## Tools
Table with columns: Tool | Purpose. Sort alphabetically.

## Databases
Table with columns: Name | Type | What It Stores. Sort alphabetically by name.

## Web Services and APIs
Table with columns: Name | Type | Purpose. Sort alphabetically.

## Web Applications
Bullet list: **Name** - Purpose.

## System Integrations
Prose description of how systems connect, grouped by data-flow direction (upstream, internal, downstream). Include an ASCII diagram if the integration topology is clear from the source material.

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

## CRITICAL: Do NOT use any tools to write files. Output ONLY the raw markdown text. Do not include any conversational preamble or sign-off. Just the markdown document.