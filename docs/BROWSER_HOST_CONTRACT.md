# Browser Host Contract

This document isolates the current browser host contract for Golem.

## Goal

Say explicitly what the repo can prove today, what still depends on the host, and what condition would move the browser subsystem from `BLOCKED` to `PASS`.

## Repo-Side Contract

The repo currently provides these non-destructive paths:

- `./scripts/browser_remediate.sh <capability> <mode>`
- `./scripts/browser_ready_check.sh <capability> <mode>`
- `./scripts/verify_browser_stack.sh`
- `./scripts/task_run_nav.sh`
- `./scripts/task_run_read.sh`
- `./scripts/task_run_artifact.sh`

Those scripts can:

- probe gateway reachability
- inspect browser profiles
- inspect relay tabs
- try raw snapshot paths
- attempt a controlled managed-`openclaw` start path
- persist structured browser readiness/remediation evidence

The repo does not currently expose a non-destructive CLI attach path for the `chrome` relay lane.

That means the repo can observe whether a relay tab exists, but it cannot create that attached-tab condition from inside the repo surface.

## Host-Side Contract

The host/runtime is still responsible for:

- having the gateway alive and reachable
- having a browser relay profile available
- exposing at least one usable attached tab on the `chrome` relay lane, or
- allowing the managed `openclaw` browser lane to start and produce a usable snapshot path

The launcher docs already describe the manual side of that contract:

- the relay may still need manual confirmation or a manual `ON` state
- operator-side browser/session state can still be required

## Current Real Paths

Available today:

- `openclaw gateway status`
- `openclaw browser profiles`
- `openclaw browser --browser-profile chrome status`
- `openclaw browser --browser-profile chrome tabs`
- `openclaw browser --browser-profile chrome snapshot`
- `openclaw browser --browser-profile openclaw status`
- `openclaw browser --browser-profile openclaw tabs`
- `openclaw browser --browser-profile openclaw snapshot`
- `openclaw browser --browser-profile openclaw start`

Missing from the repo surface today:

- a safe non-destructive CLI attach/refresh path that can move `chrome` from `0 tabs` to a usable attached relay tab

Present but failing in the current environment:

- the managed `openclaw` start path
- the managed `openclaw` snapshot path

## Current Operational Reading

The current blocker is split across two layers:

1. host contract gap:
   the repo has no CLI attach path for the `chrome` relay lane
2. host runtime failure:
   the managed `openclaw` start/snapshot fallback does not become usable in the current environment

That is why the browser subsystem remains `BLOCKED` even though the repo-side verification/remediation layer is working as designed.

## Condition To Reach PASS

The browser subsystem can move from `BLOCKED` to `PASS` when at least one of these becomes true:

- a usable tab is really attached to the `chrome` relay lane
- the managed `openclaw` lane can really start and produce a usable snapshot path

If OpenClaw later exposes a safe non-destructive CLI attach or refresh path, that would be the right moment to integrate it into the repo remediation ladder.

Until then, the immediate unblock path lives outside the repo.
