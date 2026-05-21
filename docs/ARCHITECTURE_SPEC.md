# Technical Runbook Specification (Deep-Dive Engine)

## 1. Functional Objective
The Deep-Dive Engine replaces chronological meeting summaries with a Component-Oriented Audit. The output is an Architectural Manifest that details system state, business logic, and causal workflows.

## 2. Core Operational Logic
The pipeline implements three logical layers to ensure deterministic, agentic output:

* **Layer A: Semantic Clustering (Hierarchical PBG-H)**: Groups fragmented extractions into logical clusters (e.g., EventGateway, CaseSync, ClinicalReview) using `technical_context_map.txt` as the lookup manifest.
* **Layer B: Causal Delta Analysis**: Moves from "Noun Extraction" to "Logic Extraction" by treating `system_transitions` as a state-machine definition. 
* **Layer C: Deterministic Synthesis**: Restricted from using conversational prose, the system outputs formatted Markdown tables and logic flow diagrams based on extracted causal verbs.

## 3. Implementation Blueprint (The "Auditor" Prompt)
The audit is driven by the following system directive, intended to be used with the local LLM:

> "You are an ACMP Principal Architect. You are auditing a set of KT extractions to produce a Technical Runbook.
> 1. DO NOT summarize the meetings chronologically.
> 2. AGGREGATE by Business Domain (e.g., Clinical Review, Event Management).
> 3. IDENTIFY logic flows: For every system_transition, explain the business rule driving it.
> 4. GAP ANALYSIS: Explicitly list any missing state transitions or logic gaps identified.
> 5. Output format: Markdown Tables for components and Logic Flow diagrams for processes."