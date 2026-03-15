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

## Implication for future matrix runs

The capability matrix should not treat these browser capabilities as `PASS` until:

1. a tab is really attached to the `chrome` relay profile, or
2. the managed `openclaw` profile can be started and used successfully

The right operational probe for this is `./scripts/verify_browser_stack.sh`.
