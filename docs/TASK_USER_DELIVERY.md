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
- `delivery.whatsapp`
- `delivery.transitions`
- `delivery.claim_history`
- `media`
- `screenshot`

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

When the channel itself matters, the repo can also persist a WhatsApp-specific truth lane under `delivery.whatsapp`.

The minimum WhatsApp states are:

1. `requested`
2. `accepted_by_gateway`
3. `accepted_by_provider`
4. `delivered`
5. `verified_by_user`

That lane persists at least:

- `channel`
- `provider`
- `to`
- `message_id`
- `run_id`
- `timestamp`
- `delivery_state`
- `delivery_confidence`
- `allowed_user_facing_claim`
- `raw_result_excerpt`

The generic final user-facing success claim must not pass for WhatsApp-required tasks unless the WhatsApp lane reached at least `delivered`.

Conservative wording stays canonical:

- `requested` -> `solicitado`
- `accepted_by_gateway` -> `aceptado por gateway`
- `accepted_by_provider` -> `aceptado por proveedor`
- `delivered` -> `entregado`
- `verified_by_user` -> `confirmado por usuario`

When the task also depends on a file or attachment, the repo can persist a separate `media` lane outside `delivery`.

That lane proves:

- which exact file was ingested
- from which source kind it came
- which canonical path, sha256, size, mime, and owner were observed
- whether that material identity still verifies as ready for downstream delivery use

If `media.required = true`, the generic final user-facing success claim must remain blocked until `media.current_state = verified`.

When the task depends on host-side visual proof, the repo can also persist a separate `screenshot` lane outside `delivery`.

That lane proves:

- which screenshot target was requested
- which canonical path was captured
- which sha256, size, mime, and owner were observed
- whether the screenshot stayed only `captured` or became `verified`

If `screenshot.required = true`, the generic final user-facing success claim must remain blocked until `screenshot.current_state = verified`.

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

Record a WhatsApp delivery truth transition:

```text
./scripts/task_record_whatsapp_delivery.sh <task_id> <state> <actor> <provider> <to> <message_id|-> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>]
```

Claim a WhatsApp wording level explicitly:

```text
./scripts/task_claim_whatsapp_delivery.sh <task_id> <actor> <requested_claim_level> <evidence> [claim_text]
```

Register and verify canonical media:

```text
./scripts/task_register_media_ingestion.sh <task_id> <task-artifact|visible-artifact|local-path> <source_ref> <actor> <evidence> [--json]
./scripts/task_verify_media_ready.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
./scripts/task_media_summary.sh <task_id>
```

Capture and verify canonical host screenshots:

```text
./scripts/resolve_host_screenshot_destination.sh <task_id> <target_kind> [output_hint] [--json]
./scripts/task_capture_host_screenshot.sh <task_id> <target_kind> <target_ref|-> <actor> <evidence> [output_hint] [--json]
./scripts/task_verify_host_screenshot.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
./scripts/task_screenshot_summary.sh <task_id>
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

For WhatsApp delivery claim truth specifically, use:

```text
./scripts/verify_whatsapp_delivery_claim_truth.sh
```

For media ingestion truth specifically, use:

```text
./scripts/verify_media_ingestion_truth.sh
```

For host screenshot truth specifically, use:

```text
./scripts/verify_host_screenshot_truth.sh
```

For the aggregate user-facing operational readout, use:

```text
./scripts/verify_user_facing_readiness.sh
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

The WhatsApp verify proves:

- a gateway-accepted-only path that must not be sold as delivered
- a delivered path with authorized `entregado` wording
- a `verified_by_user` path
- an ambiguous provider path that stays conservative
- a drift path where `message_id` evidence becomes inconsistent

The media ingestion verify proves:

- internal task artifact ingestion with canonical identity
- visible artifact ingestion after GOLEM-202 verification
- explicit local path ingestion
- missing-path blocking
- directory rejection
- drift detection through canonical sha256 and size

The host screenshot verify proves:

- valid host-side screenshot capture
- blocked classification when the target cannot be captured
- drift detection after capture
- claim blocked before verification
- claim allowed after verification
