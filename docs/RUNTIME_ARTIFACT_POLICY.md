# Runtime Artifact Policy

This document defines which Golem artifacts are:

- durable local evidence
- runtime-only files
- ignored by Git by default
- regenerable or disposable

The goal is to keep the repo coherent without flooding Git with every worker byproduct.

## Core rule

Do not treat every file produced during a worker run as equally durable.

Golem now separates:

- durable local evidence under `handoffs/`;
- runtime-only traces also under `handoffs/`, but explicitly excluded from Git;
- final user-facing artifacts in `outbox/manual/`, which stay ignored by default.

## Classification

| Artifact | Default location | Durable evidence | Regenerable | Git default |
| --- | --- | --- | --- | --- |
| handoff packet | `handoffs/<task_id>.md` | yes | yes, from task + handoff | ignored |
| canonical handoff packet | `handoffs/<task_id>.packet.json` | yes | yes, from task + handoff | ignored |
| Codex ticket | `handoffs/<task_id>.codex.md` | yes | yes, from task + handoff packet | ignored |
| normalized worker result | `handoffs/<task_id>.run.result.md` | yes | yes, from runtime traces while available | ignored |
| controlled run prompt | `handoffs/<task_id>.run.prompt.md` | no | yes | ignored |
| controlled run log | `handoffs/<task_id>.run.log` | no | no, debug-only | ignored |
| raw final worker message | `handoffs/<task_id>.run.last.md` | no | no, debug-only | ignored |
| final chain/manual artifact | `outbox/manual/...` | yes | usually no | ignored |
| temp or scratch files | `*.tmp`, transient runtime files | no | n/a | ignored |

## Git policy

Tracked by default:

- policy docs
- scripts
- source files that define behavior
- `handoffs/README.md`

Ignored by default:

- task-specific handoff packets
- task-specific canonical handoff packets
- task-specific Codex tickets
- normalized worker result artifacts
- runtime prompts, logs, and raw final messages
- `outbox/manual/*`

This keeps Git focused on durable repo behavior instead of per-run evidence churn.

## Runtime-only files

These files are operational and should not live as first-class evidence:

- `run.prompt.md`
- `run.log`
- `run.last.md`

Rules:

- keep them under `handoffs/` only as local runtime traces
- keep them out of Git
- use them for active debugging and extraction only
- treat them as disposable once `run.result.md` exists and the task is closed

## Durable local evidence

These files are still useful after the run:

- handoff packet
- canonical handoff packet
- Codex ticket
- normalized worker result

Rules:

- keep them readable and timestamped
- allow tasks to reference them
- keep them ignored by default
- promote them only when there is una razon deliberada para preservarlos en Git

## Regeneration rules

Safe to regenerate:

- `handoffs/<task_id>.md`
- `handoffs/<task_id>.packet.json`
- `handoffs/<task_id>.codex.md`
- `handoffs/<task_id>.run.prompt.md`
- `handoffs/<task_id>.run.result.md` while the runtime sources still exist

Not worth regenerating bit-for-bit:

- `handoffs/<task_id>.run.log`
- `handoffs/<task_id>.run.last.md`

Those are runtime traces, not canonical deliverables.

## Current Repo Rule

The repo already contains some handoff artifacts that were promoted intentionally in commits previos.

That is allowed.

The hard line is:

- handoff evidence stays local by default
- runtime-only traces stay ignored
- if a handoff artifact was promoted intentionally, Git keeps tracking that specific file without changing the default rule for the whole folder

## Practical rule of thumb

If the file answers "what did we intend, what did we hand off, or what durable result came back?", it is persistible local evidence.

If the file answers "what happened during this exact live run, line by line?", it is runtime-only and should stay out of Git.
