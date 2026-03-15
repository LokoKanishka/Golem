# Runtime Artifact Policy

This document defines which Golem artifacts are:

- durable local evidence
- runtime-only files
- ignored by Git by default
- regenerable or disposable

The goal is to stop the repo from accumulating operational noise while keeping useful evidence available.

## Core rule

Do not treat every file produced during a worker run as equally durable.

Golem now separates:

- durable local evidence in `handoffs/`
- runtime-only files also under `handoffs/`, but explicitly excluded from Git
- final user-facing artifacts in `outbox/manual/`

Git should track the policy and the scripts, not every per-run operational byproduct.

## Classification

| Artifact | Default location | Durable evidence | Regenerable | Git default |
| --- | --- | --- | --- | --- |
| handoff packet | `handoffs/<task_id>.md` | yes | yes, from task + handoff | ignored |
| Codex ticket | `handoffs/<task_id>.codex.md` | yes | yes, from task + handoff packet | ignored |
| controlled run prompt | `handoffs/<task_id>.run.prompt.md` | no | yes, from ticket + run policy | ignored |
| controlled run log | `handoffs/<task_id>.run.log` | no | no, but considered debug-only | ignored |
| raw final worker message | `handoffs/<task_id>.run.last.md` | no | no, but replaceable by normalized result | ignored |
| normalized worker result | `handoffs/<task_id>.run.result.md` | yes | yes, from `run.last.md` and/or `run.log` while available | ignored |
| final chain/manual artifact | `outbox/manual/...` | yes | usually no | ignored |
| temp or scratch files | `*.tmp`, transient runtime files | no | n/a | ignored |

## What "persistible" means here

Persistible does not mean "track in Git by default".

For this repo, persistible means:

- worth keeping locally for audit or review
- stable enough to reference from `tasks/*.json`
- durable enough to survive beyond the active run

But still excluded from Git unless someone intentionally promotes a file with `git add -f`.

## Git policy

Tracked by default:

- policy docs
- scripts
- source files that define behavior
- `handoffs/README.md`

Ignored by default:

- task-specific handoff packets
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
- Codex ticket
- normalized worker result
- final artifacts in `outbox/manual/`

Rules:

- keep them readable and timestamped
- allow tasks to reference them
- do not auto-track them in Git
- promote only when a human explicitly decides they belong in version control

## Regeneration rules

Safe to regenerate:

- `handoffs/<task_id>.md`
- `handoffs/<task_id>.codex.md`
- `handoffs/<task_id>.run.prompt.md`
- `handoffs/<task_id>.run.result.md` while the runtime sources still exist

Not worth regenerating bit-for-bit:

- `handoffs/<task_id>.run.log`
- `handoffs/<task_id>.run.last.md`

Those are runtime traces, not canonical deliverables.

## Legacy files

Runtime files may live next to durable handoff evidence in the same folder.

That is acceptable only because the Git policy draws a hard line:

- runtime files stay ignored
- durable local evidence also stays ignored by default
- `handoffs/README.md` is the only tracked file in that folder

## Practical rule of thumb

If the file answers "what did we intend, what did we hand off, or what durable result came back?", it is persistible local evidence.

If the file answers "what happened during this exact live run, line by line?", it is runtime-only and should stay out of Git.
