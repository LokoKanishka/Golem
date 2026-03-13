# Worker Result Extraction

This document explains the first automatic extraction layer for Codex worker results in Golem.

## Goal

Reduce manual closure effort after a controlled Codex run without hiding what happened.

The extraction layer reads the files already produced by the run and turns them into:

- a normalized Markdown artifact
- a minimal extracted summary
- a more convenient finalization path

## Source Files

The extractor reads from the `worker_run` block in the task and looks for:

- `last_message_path`
- `log_path`

Preferred order:

1. `run.last.md`
2. run log fallback

`run.last.md` is preferred because it is usually the cleanest final Codex answer.

## What Gets Extracted

The first version extracts only a minimal useful result:

- task metadata
- worker metadata
- source file references
- a heuristic summary
- a raw result snippet for audit

It does not attempt complex semantic interpretation.

## Technical Result vs Semantic Result

These are different things:

- technical result:
  - whether `codex exec` ran
  - exit code
  - worker state
  - log/last-message files
- semantic result:
  - what Codex actually concluded
  - whether the answer is useful enough for the task

This extraction layer helps with the second one, but it does not replace human judgment.

## Generated Artifact

Use:

```text
./scripts/task_extract_worker_result.sh <task_id>
```

This generates:

```text
handoffs/<task_id>.run.result.md
```

The artifact includes at least:

- H1
- `generated_at:`
- `task_id`
- `task_type`
- `worker_runner`
- `worker_state`
- `exit_code`
- source files used
- `Extracted Summary`
- `Raw Result Snippet`
- notes about extraction limits

The artifact must pass:

```text
./scripts/validate_markdown_artifact.sh handoffs/<task_id>.run.result.md
```

## Automatic Finalization

Use:

```text
./scripts/task_finalize_codex_run.sh <task_id> <done|failed>
```

This wrapper:

1. verifies the task is in a coherent post-run state
2. extracts the worker result if needed
3. reuses the normal finish/record flow
4. stores a minimal summary in the task
5. closes the task

The goal is not full automation. The goal is a standard low-friction closeout path.

## Limits

This first extraction layer is intentionally simple:

- no NLP classification
- no automatic task-quality judgment
- no hidden summarization pipeline
- no background callback logic

If the extracted summary is weak, the raw snippet and source file list still preserve auditability.
