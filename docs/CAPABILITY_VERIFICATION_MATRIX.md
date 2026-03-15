# Capability Verification Matrix

This document defines the minimum verification matrix for the current Golem repository.

## Goal

Measure the real health of the current system with reproducible evidence instead of trusting declarative summaries.

The official verification layer intentionally separates:

- fast operational self-checks
- deep capability verifies

`./scripts/task_run_self_check.sh` stays in the fast lane.

Heavier end-to-end flows such as `worker packet roundtrip` belong to the deep verification matrix instead of the lightweight self-check wrapper.

Multi-worker dependency-barrier orchestration now also belongs to that deep verification lane.

Every verification should prefer:

- exact command executed
- real exit code
- real stdout/stderr
- generated artifact when applicable
- final task state when applicable
- cross-check with existing inspection scripts

## Classification Rules

Use only:

- `PASS`
- `FAIL`
- `BLOCKED`

Important:

- `BLOCKED` does not mean `PASS`
- `BLOCKED` means the capability could not be proven in the current environment
- warnings must not be silently upgraded into clean success

## Matrix

### 1. Self-check

- name: `self-check`
- objective: verify that Golem can execute the local health check wrapper and persist the result as a task
- verification lane: `fast self-check`
- command(s):
  - `./scripts/task_run_self_check.sh "Capability verification / self-check"`
  - `./scripts/task_summary.sh <task_id>`
- success criterion: command exits `0` and the created task closes as `done`
- failure criterion: wrapper exits non-zero or the task does not close coherently
- path coverage: success-path
- environment dependencies:
  - local gateway/runtime availability
  - whatsapp/browser relay local state

### 2. Navigation

- name: `navigation`
- objective: verify that navigation can read browser state through the task wrapper
- command(s):
  - `./scripts/browser_ready_check.sh navigation tabs`
  - `./scripts/task_run_nav.sh tabs "Capability verification / navigation tabs"`
  - `./scripts/task_summary.sh <task_id>`
- success criterion: readiness reports `READY` or `DEGRADED`, wrapper exits `0`, and the task closes as `done`
- failure criterion: readiness reports `READY` or `DEGRADED` but the wrapper still exits non-zero or closes as `failed` for an internal reason
- path coverage: success-path or BLOCKED path
- environment dependencies:
  - browser relay available
  - at least one usable attached tab

When readiness reports `BLOCKED`, the wrapper should exit with the blocked convention and the task should close as `blocked`, not `failed`.

### 3. Reading

- name: `reading`
- objective: verify that reading can capture browser text through the task wrapper
- command(s):
  - `./scripts/browser_ready_check.sh reading snapshot`
  - `./scripts/task_run_read.sh snapshot "Capability verification / reading snapshot"`
  - `./scripts/task_summary.sh <task_id>`
- success criterion: readiness reports `READY` or `DEGRADED`, wrapper exits `0`, and the task closes as `done`
- failure criterion: readiness reports `READY` or `DEGRADED` but the wrapper exits non-zero or closes as `failed` for an internal reason
- path coverage: success-path or BLOCKED path
- environment dependencies:
  - browser relay available
  - at least one usable attached tab

### 4. Artifacts

- name: `artifacts`
- objective: verify that browser-derived markdown artifacts can be produced and validated
- command(s):
  - `./scripts/browser_ready_check.sh artifacts snapshot`
  - `./scripts/task_run_artifact.sh snapshot "Capability verification / artifact snapshot" capability-matrix-artifact-snapshot`
  - `./scripts/validate_markdown_artifact.sh <artifact>`
  - `./scripts/task_summary.sh <task_id>`
- success criterion: readiness reports `READY` or `DEGRADED`, wrapper exits `0`, task closes as `done`, and the markdown artifact validates
- failure criterion: readiness reports `READY` or `DEGRADED` but no artifact is produced, the task closes as `failed`, or validation fails for an internal reason
- path coverage: success-path or BLOCKED path
- environment dependencies:
  - browser relay available
  - at least one usable attached tab

Current browser-specific diagnosis should be refined with `./scripts/browser_ready_check.sh`, `./scripts/verify_browser_stack.sh`, and `docs/BROWSER_BLOCKERS_ANALYSIS.md`.

### 5. Comparison

- name: `comparison`
- objective: verify that local file comparison still produces a reviewable markdown artifact
- command(s):
  - `./scripts/task_run_compare.sh files "Capability verification / compare files" capability-matrix-compare docs/TASK_MODEL.md docs/TASK_CHAIN_RESULTS.md`
  - `./scripts/validate_markdown_artifact.sh <artifact>`
  - `./scripts/task_summary.sh <task_id>`
- success criterion: command exits `0`, task closes as `done`, and the comparison artifact validates
- failure criterion: comparison task or artifact generation fails
- path coverage: success-path
- environment dependencies:
  - repo files available locally

### 6. Task Core

- name: `task core`
- objective: verify the minimal create/output/artifact/close task loop
- command(s):
  - `./tests/smoke_task_core.sh`
- success criterion: smoke test exits `0`
- failure criterion: smoke test exits non-zero
- path coverage: success-path
- environment dependencies:
  - writable `tasks/`
  - writable `outbox/manual/`

### 7. Task Lifecycle

- name: `task lifecycle`
- objective: verify direct lifecycle transitions with evidence in task JSON
- command(s):
  - `./scripts/task_new.sh verification-lifecycle "Capability verification / task lifecycle"`
  - `./scripts/task_update.sh <task_id> running`
  - `./scripts/task_add_output.sh <task_id> lifecycle-check 0 "lifecycle output recorded"`
  - `./scripts/task_close.sh <task_id> done "task lifecycle verification completed"`
  - `./scripts/task_show.sh <task_id>`
- success criterion: task transitions through `queued/running/done` coherently
- failure criterion: any lifecycle transition fails or the final task state is wrong
- path coverage: success-path
- environment dependencies:
  - writable `tasks/`

### 8. Delegation Decision

- name: `delegation decision`
- objective: verify that delegation policy still returns an explicit owner/rationale for known task types
- command(s):
  - `./scripts/delegation_decide.sh type repo-analysis`
- success criterion: command exits `0` and prints owner/rationale
- failure criterion: policy command exits non-zero for a known supported type
- path coverage: success-path
- environment dependencies:
  - readable `config/delegation_policy.json`

### 9. Worker Handoff Packet

- name: `worker handoff packet`
- objective: verify that a delegated task can produce the durable handoff packet
- command(s):
  - `./scripts/task_new.sh repo-analysis "Capability verification / direct worker flow"`
  - `./scripts/task_delegate.sh <task_id>`
  - `./scripts/task_prepare_codex_handoff.sh <task_id>`
  - `./scripts/validate_markdown_artifact.sh handoffs/<task_id>.md`
- success criterion: handoff packet exists and validates
- failure criterion: packet generation fails or packet is invalid
- path coverage: success-path
- environment dependencies:
  - writable `handoffs/`
  - readable delegation policy

### 10. Codex-ready Ticket

- name: `codex-ready ticket`
- objective: verify that the delegated task can produce the normalized Codex ticket
- command(s):
  - `./scripts/task_prepare_codex_ticket.sh <task_id>`
  - `./scripts/validate_markdown_artifact.sh handoffs/<task_id>.codex.md`
- success criterion: ticket exists and validates
- failure criterion: ticket generation fails or ticket is invalid
- path coverage: success-path
- environment dependencies:
  - valid delegated task
  - writable `handoffs/`

### 11. Controlled Codex Run

- name: `controlled codex run`
- objective: verify that a real controlled worker run can start and finish from a delegated task
- command(s):
  - `./scripts/task_start_codex_run.sh <task_id>`
  - `tail -n 40 handoffs/<task_id>.run.log`
  - `./scripts/task_worker_summary.sh <task_id>`
- success criterion: real run exits cleanly and leaves `worker_run.state=finished`
- failure criterion: worker run fails without a clear environment block or policy denial
- path coverage: success-path or BLOCKED path
- environment dependencies:
  - Codex CLI available
  - worker policy allows the task type
  - writable `handoffs/`

### 12. Worker Result Extraction/Finalization

- name: `worker result extraction/finalization`
- objective: verify that worker output can be normalized into `run.result.md` and persisted back to the task
- command(s):
  - `./scripts/task_extract_worker_result.sh <task_id>`
  - `./scripts/task_finalize_codex_run.sh <task_id> <done|failed>`
  - `./scripts/validate_markdown_artifact.sh handoffs/<task_id>.run.result.md`
  - `./scripts/task_worker_summary.sh <task_id>`
- success criterion: extraction exits `0`, result artifact validates, and task closes coherently
- failure criterion: extraction/finalization fails or no valid result artifact exists
- path coverage: success-path or failure-path depending on worker outcome
- environment dependencies:
  - completed controlled run
  - writable `handoffs/`

### 13. Worker Packet Roundtrip

- name: `worker packet roundtrip`
- objective: verify the canonical packetized roundtrip for a manual-controlled worker chain, including outbound handoff packet, inbound result packet import, settlement, and honest root closure
- verification lane: `deep verify`
- command(s):
  - `./scripts/verify_worker_packet_roundtrip.sh`
  - `./scripts/task_chain_summary.sh <success_root_task_id>`
  - `./scripts/task_chain_summary.sh <blocked_root_task_id>`
- success criterion: the verify exits `0`, prints `VERIFY_WORKER_PACKET_ROUNDTRIP_OK`, validates the final artifacts, and proves both the success path and the blocked path end-to-end
- failure criterion: the verify exits non-zero or any packet import/settlement/finalization assertion fails inside the roundtrip flow
- blocked criterion: use `BLOCKED` only when the verify cannot run because a real external repo-local prerequisite is unavailable, such as an unwritable repo task/handoff/outbox path
- path coverage: success-path and blocked-path
- environment dependencies:
  - writable `tasks/`
  - writable `handoffs/`
  - writable `outbox/manual/`
  - local shell/python tooling required by the repo scripts

### 14. Multi-worker Barrier Orchestration

- name: `multi-worker barrier orchestration`
- objective: verify the official multi-worker dependency-barrier orchestration, including partial continuation after `architecture-ready`, full continuation only after `analysis-workers`, and blocked closure when the critical full barrier breaks
- verification lane: `deep verify`
- command(s):
  - `./scripts/verify_multi_worker_await_roundtrip.sh`
  - `./scripts/task_chain_summary.sh <partial_root_task_id>`
  - `./scripts/task_chain_summary.sh <blocked_root_task_id>`
- success criterion: the verify exits `0`, prints `VERIFY_MULTI_WORKER_AWAIT_OK`, proves `architecture-ready` becomes satisfied while `analysis-workers` is still waiting, proves the full continuation runs only after `analysis-workers` is satisfied, and proves the blocked path leaves the final continuation as `skipped`
- failure criterion: the verify exits non-zero or any barrier, continuation, settlement, or finalization assertion fails inside the canonical multi-worker flow
- blocked criterion: use `BLOCKED` only when the verify cannot run because a real external repo-local prerequisite is unavailable, such as an unwritable repo task/handoff/outbox path
- path coverage: partial-success-path, full-success-path, and blocked-path
- environment dependencies:
  - writable `tasks/`
  - writable `handoffs/`
  - writable `outbox/manual/`
  - local shell/python tooling required by the repo scripts

### 15. Orchestration Basic

- name: `orchestration básica`
- objective: verify the original root-plus-children chain still closes coherently
- command(s):
  - `./scripts/task_chain_run.sh self-check-compare "Capability verification / basic orchestration"`
  - `./scripts/task_chain_summary.sh <root_task_id>`
  - `./scripts/task_chain_status.sh <root_task_id>`
  - `./scripts/validate_markdown_artifact.sh <final_artifact>`
- success criterion: chain exits `0`, root closes as `done`, and final artifact validates
- failure criterion: chain aborts or root/result artifact is inconsistent
- path coverage: success-path
- environment dependencies:
  - local self-check
  - local comparison scripts

### 16. Orchestration V2 Mixed Local+Worker

- name: `orchestration v2 mixta local+worker`
- objective: verify the mixed root chain with one real worker step and aggregated summary/artifact
- command(s):
  - `./scripts/task_chain_run_v2.sh repo-analysis-worker "Capability verification / orchestration v2"`
  - `./scripts/task_chain_summary.sh <root_task_id>`
  - `./scripts/task_chain_status.sh <root_task_id>`
  - `./scripts/validate_markdown_artifact.sh <final_artifact>`
- success criterion: chain exits `0`, root closes as `done`, real worker evidence exists, and final artifact validates
- failure criterion: mixed chain does not close coherently or loses worker evidence
- path coverage: success-path
- environment dependencies:
  - controlled worker run available
  - local comparison scripts

### 17. Orchestration V3 Conditional

- name: `orchestration v3 condicional`
- objective: verify that the root can decide what to do after a real worker outcome and persist that decision honestly
- command(s):
  - `./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "Capability verification / orchestration v3 success"`
  - `./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "Capability verification / orchestration v3 failover" --force-worker-result failed`
  - `./scripts/task_chain_summary.sh <root_task_id>`
  - `./scripts/task_chain_status.sh <root_task_id>`
  - `./scripts/validate_markdown_artifact.sh <success_final_artifact>`
- success criterion: success-path chooses and executes the local follow-up, and failover path skips it with persisted `decision_reason`, `next_step_selected`, `skipped_steps`, and `conditional_outcomes`
- failure criterion: conditional decision is missing, dishonest, or not reflected in root state/artifacts
- path coverage: both success-path and failure-path
- environment dependencies:
  - controlled worker run available
  - local comparison scripts

## Final Classification Table

| status | meaning |
| --- | --- |
| `PASS` | The capability was proven with real evidence under the current environment. |
| `FAIL` | The capability was exercised and did not meet its success criteria. |
| `BLOCKED` | The capability could not be proven because an environment dependency was missing or unavailable. |

## Automation Entry Point

The matrix runner is:

```text
./scripts/verify_capability_matrix.sh
```

For a focused official run of just the new deep verify capability, use:

```text
./scripts/verify_capability_matrix.sh worker-packet-roundtrip
```

For the official barrier-aware multi-worker capability alone, use:

```text
./scripts/verify_capability_matrix.sh multi-worker-barrier-orchestration
```

It should:

- run the minimum real checks for the matrix
- keep `./scripts/task_run_self_check.sh` as the fast lane and reserve deep end-to-end checks for matrix capabilities
- include `worker packet roundtrip` as the official deep verify for the canonical manual-controlled worker roundtrip
- include `multi-worker barrier orchestration` as the official deep verify for barrier-aware multi-worker continuation
- keep per-capability evidence logs
- write one markdown report under `outbox/manual/`
- print a readable summary table at the end
- preserve FAIL and BLOCKED honestly instead of hiding them
