# Delegation Matrix

| task_type | current_default_owner | reason | escalation_rule |
| --- | --- | --- | --- |
| self-check | golem | Operational health check, reversible, already formalized as task. | Escalate only if health output implies structural remediation. |
| artifact-find | golem | Read-only artifact generation from existing browser state. | Escalate if browser/relay state is broken or if artifact target is ambiguous. |
| artifact-snapshot | golem | Read-only snapshot persistence, bounded and reversible. | Escalate if snapshot output is invalid or if source context is unclear. |
| compare-files | golem | Local file comparison inside repo, deterministic and reversible. | Escalate if inputs are missing, outside repo, or comparison scope is ambiguous. |
| repo-analysis | worker_future | Multi-file structured analysis already aligned with worker handoff policy and controlled Codex runs. | Escalate only if analysis scope or expected report format is still undefined. |
| nav-tabs | golem | Simple inspection of current tabs, low-risk and reversible. | Escalate if relay/browser state is unavailable. |
| nav-open | review_required | Opens an external destination and depends on destination intent/trust boundary. | Require review when URL intent or trust is unclear. |
| nav-snapshot | golem | Read-only inspection of current browser state. | Escalate if relay/browser state is unavailable or snapshot output is invalid. |
| read-find | golem | Read-only search over current page state, bounded and operational. | Escalate if relay/browser state is unavailable. |
| read-snapshot | golem | Read-only extraction of current page snapshot. | Escalate if relay/browser state is unavailable or output is malformed. |

## Notes

- `config/delegation_policy.json` is the source of truth; this table is only a readable mirror.
- `repo-analysis` now defaults to `worker_future` because the delegated handoff and controlled run path already exist in the repo.
- `human` remains the correct owner for structural repo changes, policy changes, or host-level mutations, but those are not represented by the current task types above.
- Unknown task types must default to `review_required`.
