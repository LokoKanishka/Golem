# Task Screenshot

This document defines the canonical repo-local lane for host-side screenshot truth.

## Goal

Separate host visual evidence from:

- technical task status
- general user-facing delivery truth
- visible artifact truth
- WhatsApp/channel delivery truth
- generic media ingestion truth

so the repo can prove when a screenshot was only captured versus when it was materially verified.

## Canonical Model

Each task can persist a `screenshot` block with at least:

- `screenshot.protocol_version`
- `screenshot.required`
- `screenshot.current_state`
- `screenshot.ready_for_claim`
- `screenshot.items`
- `screenshot.events`
- `screenshot.last_transition_at`
- `screenshot.last_verified_at`
- `screenshot.block_reason`
- `screenshot.fail_reason`

Minimum states:

1. `none`
2. `requested`
3. `captured`
4. `verified`
5. `blocked`
6. `failed`

`captured` is not enough for visual truth. Only `verified` authorizes screenshot-dependent claims.

## Screenshot Items

Each item persists at least:

- `item_id`
- `target_kind`
- `target_ref`
- `requested_path`
- `resolved_path`
- `normalized_path`
- `sha256`
- `size_bytes`
- `mime_type`
- `owner`
- `exists`
- `readable`
- `requested_at`
- `captured_at`
- `verified_at`
- `evidence`
- `state`

This keeps the screenshot auditable as material evidence instead of a loose side effect.

## Canonical Scripts

Resolve the canonical staging path for a task screenshot:

```text
./scripts/resolve_host_screenshot_destination.sh <task_id> <target_kind> [output_hint] [--json]
```

Capture a host-side screenshot into the task:

```text
./scripts/task_capture_host_screenshot.sh <task_id> <target_kind> <target_ref|-> <actor> <evidence> [output_hint] [--json]
```

Verify the screenshot material identity:

```text
./scripts/task_verify_host_screenshot.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
```

Inspect the compact summary:

```text
./scripts/task_screenshot_summary.sh <task_id>
```

## Supported Targets

The current repo-local lane supports:

- `desktop-root`
- `active-window`
- `region`
- `window-id`
- `explicit-path-context`

Unsupported or non-capturable targets stay `blocked`. This ticket does not solve browser relay/runtime observation in general.

## Verification Rules

Verification checks at least:

- `exists`
- `readable`
- `owner`
- `mime_type` compatible with `image/*`
- `size_bytes > 0`
- `sha256`
- stable `normalized_path`

If the host cannot capture the target safely or the path disappears, the state stays `blocked`.

If the file drifts, becomes non-image, or otherwise breaks canonical identity, the state becomes `failed`.

## Guardrail

If `screenshot.required = true`, the generic final user-facing success claim stays blocked until `screenshot.current_state = verified`.

That guardrail complements delivery/media lanes. It does not replace them.

## Official Verify

Use:

```text
./scripts/verify_host_screenshot_truth.sh
```

It proves:

- valid host screenshot capture
- honest blocked classification when a screenshot cannot be captured
- drift detection after capture
- claim blocked before verification
- claim allowed after verification

At the aggregate level, `./scripts/verify_user_facing_readiness.sh` reuses this lane together with delivery, visible artifact, WhatsApp, and media truth to produce one honest user-facing operational readout.
