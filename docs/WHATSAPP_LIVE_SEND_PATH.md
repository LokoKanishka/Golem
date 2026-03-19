# WhatsApp Live Send Path

This document defines the canonical threshold for a repo-local live WhatsApp send path.

## Goal

Answer one operational question precisely:

Does the current repository expose a canonical WhatsApp live send path, or does it still depend on a non-canonical external surface?

## Canonical Threshold

A WhatsApp live send path counts as canonical only when all of the following are true:

- the repo exposes a clear local entrypoint under `scripts/`
- the path is invocable without hidden manual steps
- the attempt is auditable by `task_id`
- the result can persist into `delivery.whatsapp`
- machine-readable evidence such as `message_id`, provider result, and confidence can be stored
- wording remains honest across `requested`, `accepted_by_gateway`, `provider_delivery_unproved`, `delivered`, and `verified_by_user`

## Candidate Classes

This verify uses the following candidate classes:

- `missing`
- `present_but_not_invocable`
- `invocable_but_not_auditable`
- `auditable_but_not_canonical`
- `canonical_but_runtime_blocked`
- `canonical_and_usable`

## Current Practical Reading

If the host exposes `openclaw message send` but the repo still lacks a task-bound wrapper, the result stays `BLOCKED`.

If the repo exposes `./scripts/task_send_whatsapp_live.sh` and that wrapper can prove a task-bound dry-run with persisted evidence, the result can move to `PASS` even if later delivery still depends on stronger downstream proof.

That means:

- the send surface exists
- the runtime may even be connected
- but Golem still does not have a canonical repo-local live send path

## Official Verify

Use:

```text
./scripts/verify_whatsapp_live_send_path.sh
```

To verify the stronger task-bound wrapper behavior itself, use:

```text
./scripts/verify_whatsapp_live_send_wrapper_truth.sh
```

To verify the downstream post-send provider-proof ceiling after a real gateway-accepted send, use:

```text
./scripts/verify_whatsapp_provider_post_send_reconciliation_truth.sh
```

The result is:

- `PASS` when a canonical repo-local path exists and is usable
- `BLOCKED` when the surface exists only outside the canonical repo wrapper threshold, or when runtime prevents use
- `FAIL` when the verify cannot classify the surface coherently
