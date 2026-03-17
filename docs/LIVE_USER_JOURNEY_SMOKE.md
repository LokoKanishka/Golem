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

If the repo cannot prove an actual live WhatsApp send path without leaving the repo-local safety envelope, the journey must stay `BLOCKED`. It must not be inflated into `PASS`.

## Aggregation Policy

- `PASS` means both real journeys completed coherently
- `BLOCKED` means no internal inconsistency was found, but one or more journeys still stop before real completion
- `FAIL` means at least one journey failed internally or exposed semantic drift
