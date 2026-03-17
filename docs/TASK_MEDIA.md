# Task Media

This document defines the canonical repo-local media ingestion lane for tasks.

## Goal

Separate:

- technical task status
- general user-facing delivery truth
- visible artifact truth
- WhatsApp/channel delivery truth
- canonical media identity

so the repo can prove exactly which file was ingested before a later channel tries to use it.

## Canonical Model

Each task can persist a `media` block with at least:

- `media.protocol_version`
- `media.required`
- `media.current_state`
- `media.ready`
- `media.allowed_for_delivery`
- `media.items`
- `media.events`

The minimum states are:

1. `none`
2. `registered`
3. `verified`
4. `blocked`
5. `failed`

## Media Items

Each item persists at least:

- `item_id`
- `source_kind`
- `source_path`
- `normalized_path`
- `basename`
- `extension`
- `mime_type`
- `size_bytes`
- `sha256`
- `readable`
- `exists`
- `owner`
- `collected_at`
- `evidence`

That lets the repo keep a stable material identity for later audits.

## Supported Sources

The current repo-local capability supports:

- `task-artifact`
- `visible-artifact`
- `local-path`

This ticket does not add remote URLs, downloads, or provider/runtime ingestion.

Host screenshots now have their own dedicated `screenshot` lane. If a verified screenshot later needs to act as downstream media, it should still be registered into `media` explicitly instead of assuming implicit readiness.

The top-level user-facing readiness profile consumes `media` as one of its five canonical truth sources without redefining media semantics.

## Canonical Scripts

Register media into the task model:

```text
./scripts/task_register_media_ingestion.sh <task_id> <task-artifact|visible-artifact|local-path> <source_ref> <actor> <evidence> [--json]
```

Verify that a registered item still matches its canonical material identity:

```text
./scripts/task_verify_media_ready.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
```

Inspect the compact media audit summary:

```text
./scripts/task_media_summary.sh <task_id>
```

## Verification Rules

Verification checks at least:

- `exists`
- `readable`
- `path_normalized`
- `owner`
- `size_bytes`
- `sha256`
- `mime_type`
- file-vs-directory mismatch

If the file disappears or becomes unreadable, the result stays `blocked`.

If the path resolves to a directory, or if the canonical identity drifts, the result becomes `failed`.

Only `verified` means the media is ready for downstream delivery use.

## Guardrail

If `media.required = true`, the generic final user-facing success claim must remain blocked until `media.current_state = verified`.

That guardrail does not replace visible artifact truth or WhatsApp delivery truth. It complements them.

## Official Verify

Use:

```text
./scripts/verify_media_ingestion_truth.sh
```

It proves:

- valid internal artifact ingestion
- valid visible artifact ingestion
- valid explicit local path ingestion
- missing-path blocking
- material drift detection
- directory rejection
