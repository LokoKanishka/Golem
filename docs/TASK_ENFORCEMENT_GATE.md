# Task Enforcement Gate

This document defines the official enforcement gate for the canonical task lane.

## Official gate

Run:

```text
./scripts/verify_task_lane_enforcement.sh
```

This is the repo-local gate that now protects the task lane.

There is no versioned CI workflow in this repo today, so this gate is the official merge and tranche-close barrier until a small CI hook is added deliberately.

## What it covers

The gate must fail if any of these drift:

- `scripts/task_create.sh` stops being the real canonical entrypoint;
- `scripts/task_new.sh` stops being wrapper-only compatibility over `task_create.sh`;
- active `tasks/task-*.json` become ignored or untracked again;
- the active inventory stops validating under `./scripts/task_validate.sh --all --strict`;
- the base task smoke path stops passing.

## Current checks

The gate currently runs:

- `./scripts/task_entrypoint_policy_check.sh`
- `./scripts/verify_task_cli_minimal.sh`
- `./scripts/task_git_trace_check.sh`
- `./scripts/task_validate.sh --all --strict`
- `./tests/smoke_task_core.sh`

## When to run it

Run the gate before:

- closing a task-lane tranche;
- merging changes that touch task scripts, task docs, validation, or task JSON policy;
- accepting refactors around creation, delegation, handoff, or traceability.

## What blocks merge or closure

Treat the gate as mandatory.

If `verify_task_lane_enforcement.sh` fails, the tranche is not closed and the merge is not considered safe for the canonical task lane.
