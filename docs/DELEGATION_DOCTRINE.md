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

Use `worker_future` when the task is a better fit for a future worker but not for Golem alone today, for example:

- long-running execution
- structured multi-step production
- tasks that will need a real delegated worker loop once integration exists

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

## Central rule

Golem resolves alone only what is operational, reversible, and well defined.

Humans keep structural or risky changes.

`worker_future` is reserved for longer, structured work once a real worker integration exists.

If classification is unclear, the safe result is `review_required`.
