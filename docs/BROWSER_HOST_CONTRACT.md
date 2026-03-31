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
- `./scripts/browser_cdp_tool.sh <tabs|open|snapshot|find>`

Those scripts can:

- probe gateway reachability
- inspect browser profiles
- inspect relay tabs
- try raw snapshot paths
- attempt a controlled managed-`openclaw` start path
- persist structured browser readiness/remediation evidence
- talk directly to a live Chrome CDP endpoint without going through `openclaw browser ...`

The repo still does not expose a non-destructive CLI attach path for the `openclaw browser ...` operator lane itself.
What it does expose now is a direct CDP helper that can work against an already attached live Chrome endpoint.

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
- `./scripts/browser_cdp_tool.sh tabs`
- `./scripts/browser_cdp_tool.sh snapshot [selector]`
- `./scripts/browser_cdp_tool.sh find <texto> [selector]`

Missing from the repo surface today:

- a safe non-destructive CLI attach/refresh path that makes `openclaw browser ...` itself reliable when the operator lane is timing out

Present but failing in the current environment:

- the `openclaw browser ...` operator path can time out at `45000ms` even when the backend browser request eventually succeeds later

## Current Operational Reading

The current blocker is now split across two layers:

1. host contract gap:
   the repo still depends on host/runtime state to make the real Chrome profile attachable in the first place
2. operator timeout debt:
   the `openclaw browser ...` CLI/operator lane can still time out before the backend browser request finishes

That means the repo is no longer blocked from reading a live attached browser in absolute terms, but it is still blocked from treating `openclaw browser ...` as a trustworthy operator surface for daily use.

## Condition To Reach PASS

The browser subsystem can move the operator lane from debt to `PASS` when at least one of these becomes true:

- the `openclaw browser ...` operator path returns reliably inside its own timeout budget against the attached live Chrome
- or the managed `openclaw` lane can really start and produce a usable snapshot path

Until that happens, the repo can use `browser_cdp_tool.sh` as the pragmatic live-browser path for focused work such as the docente page, while keeping the OpenClaw CLI timeout as an explicit debt.
