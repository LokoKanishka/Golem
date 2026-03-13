# Output Conventions

This document defines the minimum conventions for persisted textual outputs and Markdown artifacts produced by Golem.

## Goal

Keep outputs legible, non-ambiguous, and easy to trace back to the task or flow that generated them.

## Minimum Recommended Header for Markdown Artifacts

Every Markdown artifact should start with:

- an `H1` title
- a timestamp field such as `generated_at:`
- contextual metadata when it applies, for example:
  - `repo:`
  - `task_type:`
  - `profile:`
  - `input_a:` / `input_b:`
  - `task_id:`

Example:

```md
# Golem Repo Analysis Report

generated_at: 2026-03-13T21:43:54Z
repo: /home/lucy-ubuntu/Escritorio/golem
task_type: repo-analysis
```

## Accepted Timestamp Fields

The preferred field is:

- `generated_at:`

For legacy or derived artifacts, these fields are also accepted when they are the primary lifecycle timestamp already persisted by the flow:

- `delegated_at:`
- `created_at:`

This matters especially for older handoff packets or Codex tickets created before `generated_at:` was added explicitly.

## Minimum Expected Sections

The exact section names may vary by artifact type, but a useful Markdown artifact should usually include at least some of these:

- `## Summary`
- `## Inputs`
- `## Results`
- `## Matches`
- `## Findings`
- `## Notes`

Examples by artifact type:

- handoff packet:
  - task/context sections
  - handoff details
  - notes
  - outputs
  - artifacts
- Codex ticket:
  - header/context
  - restrictions
  - expected delivery
  - packet reference
- browser find artifact:
  - summary
  - query/inputs
  - matches
  - notes
- comparison artifact:
  - summary
  - inputs
  - findings
  - notes
- chain final artifact:
  - summary
  - child tasks
  - result
  - aggregated artifacts
  - notes
- worker result artifact:
  - summary
  - source files
  - raw result snippet
  - notes

## Formatting Rules

- Use readable Markdown, not raw dumps without framing.
- Use consistent UTC ISO 8601 timestamps when the script controls the value.
- Prefer stable naming when a script generates files repeatedly, usually timestamp plus slug or task context.
- Do not mark an artifact as success if it is empty, malformed, or clearly ambiguous.
- If there is no useful content, state that explicitly in the body.
- “No matches” or “no findings” is acceptable only when it is clearly written, not silently empty.

## Relationship Between `outputs` and `artifacts`

Use `outputs` when:

- the important result is short textual state
- a command result or summary belongs directly inside the task record
- the text helps audit execution even if no file was produced

Use `artifacts` when:

- a file is part of the deliverable
- the result is structured, longer, or intended for review
- preserving a stable path matters

How they should coexist:

- `outputs` should carry the short execution summary and operational metadata
- `artifacts` should point to the durable file result
- a successful artifact-producing flow should usually register both:
  - an output explaining what happened
  - an artifact path pointing to the file

## Validation Rule

Markdown artifacts should pass:

```text
./scripts/validate_markdown_artifact.sh <path>
```

The validator is intentionally minimal. It checks for:

- file existence
- `.md` extension
- non-empty content
- an `H1` near the top
- a valid timestamp field such as `generated_at:`
  or an accepted equivalent such as `delegated_at:` / `created_at:`
- additional non-trivial body content

## Scope

These conventions are a minimum baseline, not a rigid publishing format.

The goal is to prevent:

- empty success artifacts
- raw unframed dumps
- missing timestamps
- results that cannot be traced back to a task or context
