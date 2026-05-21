You are analyzing one segment of a knowledge transfer (KT) recording for the Anthem Care Management Platform (ACMP), a healthcare system being transitioned to a new engineering team. The recording is from December 2022.

Your inputs:
- Transcript file: <TRANSCRIPT_PATH>
- Frames directory: <OCR_PATH>

Frames are JPG screenshots captured at scene changes. They typically show architecture diagrams, slide decks, database schemas, code snippets, IDEs, browsers, API testing tools (SoapUI, Postman), or database viewers (MongoDB Compass, SSMS). Filenames encode timestamps - for example `t02m11s.jpg` is the frame at 2 minutes 11 seconds into the segment.

Steps to perform:
1. Read the transcript file in full.
2. List the frames directory and read every frame image. Each frame shows what the speaker was displaying at that timestamp.
3. Build a complete picture by combining what is spoken in the transcript with what is shown in the frames. The frames often contain architectural detail the speaker references but does not fully verbalize.
4. Pay special attention to live tooling demonstrations: SoapUI requests, IDE windows with visible code or repo names, browser address bars with URLs, database viewers showing tables or collections. These are gold and must be captured with their concrete details.
5. Output the result as a single JSON object directly to the console.

The JSON object must have exactly these fields:

- `topics`: array of strings, 3 to 7 short phrases for what this segment covers
- `tech_stack`: array of strings - languages, frameworks, runtimes (e.g. Java, Spring Boot, .NET, Angular)
- `tools`: array of objects with shape `{"name": "...", "purpose": "..."}` - named software like IDEs, build tools, monitoring, API test tools, DB viewers, etc.
- `databases`: array of objects with shape `{"name": "...", "type": "...", "stores": "..."}` - type is DB2/SQL Server/MongoDB/Oracle/etc.
- `web_services`: array of objects with shape `{"name": "...", "type": "...", "purpose": "..."}` - type is REST/SOAP/messaging/etc.
- `web_applications`: array of objects with shape `{"name": "...", "purpose": "..."}`
- `integrations`: array of strings describing how systems connect to each other and why
- `acronyms`: array of objects with shape `{"term": "...", "expansion": "...", "definition": "..."}` - capture every acronym, both ones expanded in speech and ones visible in frames
- `key_concepts`: array of objects with shape `{"name": "...", "explanation": "..."}` - 1 to 2 sentence explanation each
- `key_visuals`: array of objects with shape `{"frame_file": "tMMmSSs.jpg", "description": "..."}` - 2 to 3 sentence vivid description of each frame that contains important architectural or operational detail. Only include frames that genuinely add information; skip frames that are mostly the same as their neighbors.
- `live_demonstrations`: array of objects with shape `{"frame_file": "tMMmSSs.jpg", "tool": "...", "action": "...", "url_or_endpoint": "...", "http_method": "...", "request_summary": "...", "response_summary": "...", "linked_web_service": "..."}` - one entry per frame that shows a tool being used live with concrete data. `tool` examples: SoapUI, Postman, Chrome, Edge, IntelliJ IDEA, Eclipse, VS Code, Notepad++, MongoDB Compass, SSMS, DBeaver. Capture URL or endpoint exactly as visible in the address bar, URL field, or request line. Capture HTTP method if visible (GET/POST/PUT/DELETE/PATCH). Capture request payload summary and response format (JSON/XML/HTML) if observable. `linked_web_service` should reference a name from the `web_services` array when the demonstration exercises one of those services; empty string otherwise. Use empty string for any field not observable.
- `code_repositories`: array of objects with shape `{"name": "...", "url": "...", "host": "...", "ide_shown": "...", "files_or_modules_visible": ["..."]}` - one entry per repository mentioned or shown. `host` is Bitbucket/GitHub/GitLab/Azure DevOps/SVN/other if identifiable. `ide_shown` is the IDE name if the repo is being viewed in one (IntelliJ IDEA, Eclipse, VS Code, etc.); empty otherwise. `files_or_modules_visible` lists filenames, classes, or module names visible in the frame.
- `database_objects`: array of objects with shape `{"name": "...", "kind": "...", "database_name": "...", "database_engine": "...", "viewer_tool": "...", "fields_or_columns": ["..."], "purpose": "..."}` - one entry per specific table, collection, view, or stored procedure mentioned or shown. `kind` is one of table/collection/view/stored_procedure/index. `database_engine` should match one of the entries in the `databases` array. `viewer_tool` is the tool used to display this object if a tool was visible (MongoDB Compass, SSMS, DBeaver, TOAD, mysql workbench, etc.); empty string otherwise. `fields_or_columns` lists visible column or field names.
- `page_flows`: array of objects with shape `{"flow_name": "...", "starting_page": "...", "steps": [{"page": "...", "action": "...", "web_service_called": "..."}], "ending_page": "...", "outcome": "..."}` - one entry per multi-page workflow demonstrated. Each step's `web_service_called` should reference a name from `web_services` when a service call was observable from the demonstration (network tab, console log, server response, or explicit speaker mention); empty string otherwise. The correlation between UI pages and the services they invoke is one of the most valuable outputs - prioritize capturing it accurately over completeness.
- `pain_points_or_limitations`: array of strings - technical debt, manual workarounds, system quirks, or limitations the speaker explicitly mentions
- `open_questions`: array of strings - concepts referenced but deliberately skipped or not fully explained in this segment
- `summary`: string - exactly 2 sentences capturing the core engineering takeaway from this segment

Rules:
- Use both the transcript and the visuals. Visual content carries weight equal to spoken content.
- Be precise and concise. No filler, no hedging, no commentary about the analysis itself.
- The output must be valid JSON. No markdown formatting. No code fences. No preamble. No trailing commentary.
- If a field would be empty, output an empty array `[]` (or empty string `""` for `summary` and inner string fields).
- Frame filenames must match the actual files in the frames directory exactly.
- Do NOT invent URLs, endpoints, repo names, table names, or field names that are not actually visible in a frame or explicitly stated in the transcript. Missing data is fine; fabricated data is not.

## CRITICAL: Do NOT use any tools to write files. Output ONLY the raw, valid JSON. Do not use markdown formatting, do not use ```json code blocks, and do not include any conversational preamble or sign-off. Just the JSON.
