# Browser Blockers Analysis

diagnosis_date: 2026-03-15
repo: /home/lucy-ubuntu/Escritorio/golem

## Goal

Diagnose whether the current browser capability blockers come from:

- environment state
- browser relay/runtime fragility
- script-level failures

without upgrading blocked capabilities to `PASS`.

## Current diagnosis

As observed on March 15, 2026:

- the gateway is reachable and the OpenClaw RPC probe responds
- the `chrome` browser relay profile exists and is `running`
- the `chrome` profile has `0 tabs`
- raw `chrome snapshot` fails because the extension relay is running but no tab is connected
- the managed `openclaw` profile exists but is `stopped`
- attempts to use the managed `openclaw` profile do not currently provide a usable success-path in this environment

## Readiness layer now in repo

The repo now includes an explicit remediation-aware readiness layer:

- `./scripts/browser_ready_check.sh <capability> <mode>`
- `./scripts/browser_remediate.sh <capability> <mode>`

The canonical remediation ladder now records structured evidence for:

- gateway reachability
- browser profiles
- whether `chrome` has a usable tab
- whether there is any non-destructive chrome-side attach path in repo
- whether `openclaw` is already usable as a fallback
- whether a minimal, non-destructive managed-browser recovery attempt can make `openclaw` usable
- the exact remediation steps attempted vs skipped

The remediation evidence exposes:

- `remediation_step`
- `attempted`
- `result`
- `chosen_profile`
- `final_decision`
- `reason`

It classifies the current state as:

- `READY`
- `DEGRADED`
- `BLOCKED`

The browser task runners now consume that decision before calling the browser action itself:

- `./scripts/task_run_nav.sh`
- `./scripts/task_run_read.sh`
- `./scripts/task_run_artifact.sh`

Those wrappers persist the nested `browser_readiness` payload, which now also contains the remediation ladder evidence.

If readiness is `BLOCKED`, the runner no longer fires blindly. Instead it:

- closes the task as `status: blocked`
- records `exit_code: 2`
- records `BROWSER_BLOCKED ...` as the task output content
- persists the nested `browser_readiness` evidence block
- appends an explicit note such as `browser blocked before navigation execution`

The browser subsystem verify now reuses that same source of truth and can be run in two honest modes:

- `./scripts/verify_browser_stack.sh` for diagnosis plus remediation attempt
- `./scripts/verify_browser_stack.sh --diagnosis-only` for pure diagnosis without the managed-browser recovery attempt

For the finer split between repo-side capability, missing attach path, and host/runtime blocking, use:

- `./scripts/verify_browser_host_contract.sh`
- `docs/BROWSER_HOST_CONTRACT.md`

## What is blocked by environment

The main environment blocker is clear:

- there is no usable attached tab on the `chrome` relay profile

Without a connected tab, the browser success-path cannot be proven for:

- navigation
- reading
- artifacts

## What also looks fragile

There is also runtime fragility around the managed `openclaw` profile:

- `openclaw browser --browser-profile openclaw start` timed out against the local gateway
- `openclaw browser --browser-profile openclaw snapshot` failed with `Failed to start Chrome CDP on port 18800`

That does not prove a bug in the repo scripts by itself, but it does show that the documented fallback path is not currently usable in this environment.

There is also one smaller repo-side fragility:

- `browser_nav.sh` and `browser_read.sh` are still centered on the `chrome` relay path, unlike `browser_artifact.sh`
- the task wrappers report the managed `openclaw` fallback mostly as a no-tabs condition, while the raw browser probes expose the deeper runtime cause

## Classification rule for this stage

Use these rules:

- `PASS`: a real browser success-path produced useful output or a valid artifact
- `BLOCKED`: no usable attached tab or no usable managed-browser target prevented proof of success
- `FAIL`: the environment was usable enough to test, but the repo script still failed for an internal reason

## Current honest classification

Based on the current evidence:

- `navigation`: `BLOCKED`
- `reading`: `BLOCKED`
- `artifacts`: `BLOCKED`

The blocker is primarily environmental (`chrome` without an attached tab), with an additional managed-profile fragility that prevents using `openclaw` as a clean fallback today.

The repo-side improvement is that this now becomes a first-class `blocked` task state instead of a generic task failure.

## Implication for future matrix runs

The capability matrix should not treat these browser capabilities as `PASS` until:

1. a tab is really attached to the `chrome` relay profile, or
2. the managed `openclaw` profile can be started and used successfully

The right operational probes for this stage are:

- `./scripts/browser_remediate.sh <capability> <mode>`
- `./scripts/browser_ready_check.sh <capability> <mode>`
- `./scripts/verify_browser_host_contract.sh`
- `./scripts/verify_browser_stack.sh`
