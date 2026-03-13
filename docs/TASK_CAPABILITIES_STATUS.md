# Task Capabilities Status

This document summarizes which Golem capabilities already run as formal tasks and which still exist only as direct capabilities.

## Current live capabilities

- self-check
- browser navigation
- precise reading
- simple artifacts
- simple comparison
- launcher

## Already integrated as formal tasks

- self-check
  runner: `./scripts/task_run_self_check.sh`
- simple artifact generation
  runner: `./scripts/task_run_artifact.sh`
- simple comparison from files
  runner: `./scripts/task_run_compare.sh`

## Not yet integrated as formal tasks

- browser navigation
  today it remains a direct capability via `./scripts/browser_nav.sh`
- precise reading
  today it remains a direct capability via `./scripts/browser_read.sh`
- launcher
  today it is an operational entrypoint, not a task runner

## Meaning of the current state

Golem now has a clear split:

- direct capabilities for immediate operation
- formal task wrappers for repeatable flows that should persist state, outputs, and artifacts

## Next logical step

The next reasonable step after this is to formalize reading and navigation under the same task model, so Golem can persist:

- what page or tab was used
- what was extracted
- what artifact or report resulted

That would complete the first coherent task layer before any future live worker integration.
