# Delegation Doctrine

This document defines the first formal delegation doctrine for Golem.

## General principle

Golem should resolve only work that is:

- operational
- reversible
- well defined
- already supported by the current repo and live capability layer

Structural, risky, ambiguous, or context-heavy decisions stay out of full autonomy.

## Owners

### `golem`

Use `golem` when the task is:

- operational
- read-only or low-risk
- reversible
- already supported by a stable script or task runner

### `human`

Use `human` when the task:

- changes structure or policy
- can break the host or a live integration
- depends on human judgment, business priority, or non-local context

### `worker_future`

Use `worker_future` when the task is a better fit for the delegated worker path than for Golem alone, for example:

- long-running execution
- structured multi-step production
- tasks that already have a governed delegated worker loop in this repo

Today this includes explicitly allowed delegated types such as `repo-analysis`.

### `review_required`

Use `review_required` when the task is not clearly safe to hand to Golem alone and also does not cleanly belong to a human-only or worker-future bucket.

This is the ambiguity lane.

## Decision criteria

Delegation decisions should consider:

- risk
  high-risk tasks should not default to Golem
- reversibility
  easy rollback favors Golem
- need for human context
  if intent or judgment is unclear, escalate
- complexity and time
  longer structured work trends toward future worker ownership
- need for external access or unfinished integration
  weakly governed integrations should not default to autonomous execution

## Source of truth

Delegation decisions should follow this order:

1. `config/delegation_policy.json` is the source of truth for `owner`, `rationale`, and `escalation`
2. `docs/DELEGATION_MATRIX.md` is the human-readable summary of the current policy
3. other docs may explain related handoff or worker flows, but should not contradict the policy

## Central rule

Golem resolves alone only what is operational, reversible, and well defined.

Humans keep structural or risky changes.

`worker_future` is reserved for longer, structured work that the current policy explicitly marks as delegated.

If classification is unclear, the safe result is `review_required`.
