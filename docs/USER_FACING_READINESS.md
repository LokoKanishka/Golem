# User-Facing Readiness

This document defines the top-level user-facing readiness profile for Golem.

## Goal

Aggregate the canonical user-facing lanes into one honest operational readout without reimplementing their internal logic.

The profile reuses:

- `user-facing delivery truth`
- `visible artifact delivery truth`
- `whatsapp delivery claim truth`
- `media ingestion truth`
- `host screenshot truth`

## Canonical Verify

Use:

```text
./scripts/verify_user_facing_readiness.sh
```

It emits:

- one row per user-facing sub-capability
- `PASS`, `BLOCKED`, and `FAIL` counts
- `overall_status`
- `overall_note`
- a markdown report in `outbox/manual/`

## Aggregation Policy

- `PASS` means every critical user-facing lane passed
- `BLOCKED` means no lane failed internally, but one or more remain externally blocked
- `FAIL` means at least one lane failed internally or exposed drift/inconsistency

The profile must not present the system as user-facing ready when any critical lane is `BLOCKED` or `FAIL`.

## Next Operational Layer

Once the canonical truths are passing, use the live journey smoke profile to see where real user experience still cuts:

```text
./scripts/verify_live_user_journey_smoke.sh
```

That profile reuses the same lanes but organizes them as two real journeys:

- visible artifact to a verified user path
- WhatsApp-oriented delivery with honest channel semantics
