# Task User Delivery

This document defines the canonical truth model for user-facing delivery.

## Goal

Separate:

- technical acceptance inside the repo
- actual user-facing delivery truth

so the repo does not claim success before the user can really see the result.

## Delivery States

The minimum ordered states are:

1. `submitted`
2. `accepted`
3. `delivered`
4. `visible`
5. `verified_by_user`

These states live under `task.delivery`.

## Persisted Model

Each relevant task can persist:

- `delivery.protocol_version`
- `delivery.minimum_user_facing_success_state`
- `delivery.current_state`
- `delivery.user_facing_ready`
- `delivery.visible_artifact_required`
- `delivery.visible_artifact_ready`
- `delivery.visible_artifact_deliveries`
- `delivery.transitions`
- `delivery.claim_history`

Each transition stores at least:

- `state`
- `timestamp`
- `actor`
- `channel`
- `evidence`

Each user-facing success claim attempt stores at least:

- `claim`
- `timestamp`
- `actor`
- `channel`
- `evidence`
- `required_state`
- `current_state`
- `allowed`

## Core Rule

`done` is not the same as user-visible success.

The repo must not authorize a final user-facing success claim unless the task reached at least `visible`.

That means:

- `accepted` is not enough
- `delivered` is not enough
- only `visible` or `verified_by_user` can pass the claim gate

When the task depends on a user-visible file result, reaching `visible` also requires a separately verified visible artifact delivery.

That visible artifact truth stores at least:

- `delivery_target`
- `resolved_path`
- `verified_at`
- `verification_result`
- `verification.exists`
- `verification.readable`
- `verification.owner`
- `verification.path_normalized`

If the repo cannot verify the visible destination reliably, the artifact lane stays `BLOCKED` and the final user-facing claim must remain blocked too.

## Canonical Scripts

Record a transition:

```text
./scripts/task_record_delivery_transition.sh <task_id> <state> <actor> <channel> <evidence>
```

Inspect a compact audit summary:

```text
./scripts/task_delivery_summary.sh <task_id>
```

Guard a user-facing success claim:

```text
./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]
```

Resolve a canonical visible destination:

```text
./scripts/resolve_user_visible_destination.sh <desktop|downloads> [filename] [--json]
```

Materialize and verify a visible artifact delivery:

```text
./scripts/task_materialize_visible_artifact.sh <task_id> <artifact_path> <desktop|downloads> [filename] [--json]
```

## Transition Policy

The first transition must be `submitted`.

Transitions then advance one step at a time:

- `submitted -> accepted`
- `accepted -> delivered`
- `delivered -> visible`
- `visible -> verified_by_user`

This conservative policy avoids ambiguous delivery history and keeps the task auditable by `task_id`.

## Official Verify

The canonical verify is:

```text
./scripts/verify_user_facing_delivery_truth.sh
```

For visible artifact truth specifically, use:

```text
./scripts/verify_visible_artifact_delivery_truth.sh
```

It proves:

- a partial path that stops at `accepted` and cannot be sold as user-facing success
- a `visible` path with valid claim authorization
- a `verified_by_user` path
- an invalid drift path that is rejected

The visible artifact verify proves:

- a `desktop` path with verified visibility
- a `downloads` path with verified visibility
- a blocked unverifiable path that cannot be sold as success
- a drift path where the reported visible destination does not match the materialized file
