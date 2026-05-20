You are analyzing one segment of a knowledge transfer (KT) recording for the Anthem Care Management Platform (ACMP), a healthcare system being transitioned to a new engineering team. The recording is from December 2022.

Your inputs:
- Transcript file: <TRANSCRIPT_PATH>
- Frames directory: <FRAMES_PATH>

Frames are JPG screenshots captured at scene changes. They typically show architecture diagrams, slide decks, database schemas, code snippets, or UI screens. Filenames encode timestamps - for example `t02m11s.jpg` is the frame at 2 minutes 11 seconds into the segment.

Steps to perform:
1. Read the transcript file in full.
2. List the frames directory and read every frame image. Each frame shows what the speaker was displaying at that timestamp.
3. Build a complete picture by combining what is spoken in the transcript with what is shown in the frames. The frames often contain architectural detail the speaker references but does not fully verbalize.
4. Output the result as a single JSON object directly to the console.

The JSON object must have exactly these fields:

- `topics`: array of strings, 3 to 7 short phrases for what this segment covers
- `tech_stack`: array of strings - languages, frameworks, runtimes (e.g. Java, Spring Boot, .NET, Angular)
- `tools`: array of objects with shape `{"name": "...", "purpose": "..."}` - named software like IDEs, build tools, monitoring, etc.
- `databases`: array of objects with shape `{"name": "...", "type": "...", "stores": "..."}` - type is DB2/SQL Server/MongoDB/etc.
- `web_services`: array of objects with shape `{"name": "...", "type": "...", "purpose": "..."}` - type is REST/SOAP/messaging/etc.
- `web_applications`: array of objects with shape `{"name": "...", "purpose": "..."}`
- `integrations`: array of strings describing how systems connect to each other and why
- `acronyms`: array of objects with shape `{"term": "...", "expansion": "...", "definition": "..."}` - capture every acronym, both ones expanded in speech and ones visible in frames
- `key_concepts`: array of objects with shape `{"name": "...", "explanation": "..."}` - 1 to 2 sentence explanation each
- `key_visuals`: array of objects with shape `{"frame_file": "tMMmSSs.jpg", "description": "..."}` - 2 to 3 sentence vivid description of each frame that contains important architectural or operational detail. Only include frames that genuinely add information; skip frames that are mostly the same as their neighbors.
- `pain_points_or_limitations`: array of strings - technical debt, manual workarounds, system quirks, or limitations the speaker explicitly mentions
- `open_questions`: array of strings - concepts referenced but deliberately skipped or not fully explained in this segment
- `summary`: string - exactly 2 sentences capturing the core engineering takeaway from this segment

Rules:
- Use both the transcript and the visuals. Visual content carries weight equal to spoken content.
- Be precise and concise. No filler, no hedging, no commentary about the analysis itself.
- The output must be valid JSON. No markdown formatting. No code fences. No preamble. No trailing commentary.
- If a field would be empty, output an empty array `[]` (or empty string `""` for `summary`).
- Frame filenames must match the actual files in the frames directory exactly.

## CRITICAL: Do NOT use any tools to write files. Output ONLY the raw, valid JSON. Do not use markdown formatting, do not use ```json code blocks, and do not include any conversational preamble or sign-off. Just the JSON.