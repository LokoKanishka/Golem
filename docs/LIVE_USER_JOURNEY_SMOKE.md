# Live User Journey Smoke

This document defines the repo-local smoke profile for real user journeys.

## Goal

Prove where a real user-facing journey completes, blocks, or fails without reimplementing the canonical truth lanes underneath it.

The profile intentionally runs exactly two journeys:

- `artifact visible real`
- `whatsapp delivery`

## Canonical Verify

Use:

```text
./scripts/verify_live_user_journey_smoke.sh
```

It emits:

- one row per journey
- `PASS`, `BLOCKED`, and `FAIL` counts
- `overall_status`
- `overall_note`
- one markdown report in `outbox/manual/`

## Journey Policy

Journey A reuses the visible-artifact lane and proves whether a real artifact became materially visible on a canonical user-facing path.

Journey B reuses the delivery, WhatsApp, and media lanes and proves exactly where a channel-facing file journey stops.

Journey B now delegates the send-path question to:

```text
./scripts/verify_whatsapp_live_send_path.sh
```

If that verify cannot prove a canonical repo-local live send path, the journey must stay `BLOCKED`. It must not be inflated into `PASS`.

When the send-path verify passes, Journey B uses:

```text
./scripts/task_send_whatsapp_live.sh
```

Journey B now also delegates the final provider-proof question to:

```text
./scripts/verify_whatsapp_live_provider_canary.sh
```

The official smoke still stops at a safe dry-run unless stronger downstream delivery proof is available. That keeps the journey honest: wrapper existence is not the same thing as delivered WhatsApp truth.

When the dry-run path leaves WhatsApp without provider proof, Journey B must stay `BLOCKED` specifically because provider delivery proof is missing or unavailable. It must not regress to a wrapper-missing diagnosis.

## Aggregation Policy

- `PASS` means both real journeys completed coherently
- `BLOCKED` means no internal inconsistency was found, but one or more journeys still stop before real completion
- `FAIL` means at least one journey failed internally or exposed semantic drift
