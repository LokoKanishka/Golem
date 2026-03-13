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
- browser navigation
  runner: `./scripts/task_run_nav.sh`
- precise reading
  runner: `./scripts/task_run_read.sh`

## Not yet integrated as formal tasks

- launcher
  today it is an operational entrypoint, not a task runner

## Meaning of the current state

Golem now has a clear split:

- direct capabilities for immediate operation
- formal task wrappers for repeatable flows that should persist state, outputs, and artifacts

## Next logical step

The next reasonable step after this is to move from capability-specific task runners to session-aware orchestration, so Golem can persist:

- which canonical session requested the work
- how multiple task steps relate to the same objective
- when a future worker should be woken up

That would be the bridge from the current task layer into a future worker phase without losing the discipline already built here.
