# Capability Verification Matrix

This document defines the minimum verification matrix for the current Golem repository.

## Goal

Measure the real health of the current system with reproducible evidence instead of trusting declarative summaries.

The official verification layer intentionally separates:

- fast operational self-checks
- deep capability verifies
- deep subsystem verifies
- system readiness verifies

`./scripts/task_run_self_check.sh` stays in the fast lane.

Heavier end-to-end flows such as `worker packet roundtrip` belong to the deep verification matrix instead of the lightweight self-check wrapper.

Multi-worker dependency-barrier orchestration now also belongs to that deep verification lane.

Execution-audit drift detection now belongs to that same deep verification lane too.

The composed worker/orchestration/traceability subsystem verify belongs to the deep subsystem lane and reuses those capability verifies as its source of truth.

The system readiness verify lives one level above that and aggregates:

- the fast self-check lane
- the browser subsystem lane
- the worker/orchestration/traceability subsystem lane

The live smoke profile lives one step above readiness and captures a short real demo-state of the current local stack with generated evidence.

User-facing delivery truth is a separate capability lane from both technical task closure and browser/worker readiness.

Visible artifact delivery truth is the adjacent lane that proves a staged artifact really reached a verified user-visible destination such as `desktop` or `downloads`.

WhatsApp delivery claim truth is the channel-specific lane that prevents gateway acceptance from being sold as real delivery.

Media ingestion truth is the attachment-specific lane that proves which exact file identity was ingested before later delivery steps rely on it.

Host screenshot truth is the visual-evidence lane that proves a host-side capture exists materially and was later verified before it can back a visual claim.

User-facing readiness is the top-level user-facing profile that aggregates those five canonical truths into one operational readout.

Live user journey smoke is the next operational layer above that: it runs two real user journeys and reports exactly where the end-to-end experience still cuts.

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
  - `./scripts/browser_remediate.sh navigation tabs`
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
  - `./scripts/browser_remediate.sh reading snapshot`
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
  - `./scripts/browser_remediate.sh artifacts snapshot`
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

Current browser-specific diagnosis/remediation should be refined with `./scripts/browser_remediate.sh`, `./scripts/browser_ready_check.sh`, `./scripts/verify_browser_host_contract.sh`, `./scripts/verify_browser_stack.sh`, `docs/BROWSER_BLOCKERS_ANALYSIS.md`, and `docs/BROWSER_HOST_CONTRACT.md`.

The browser stack verify now supports:

- `./scripts/verify_browser_stack.sh` for diagnosis plus controlled remediation attempt
- `./scripts/verify_browser_stack.sh --diagnosis-only` for pure diagnosis without the managed-browser recovery attempt

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

### 15. Chain Execution Audit

- name: `chain execution audit`
- objective: verify the official execution audit against `effective_chain_plan`, including coherent, incomplete, and drift-detection paths
- verification lane: `deep verify`
- command(s):
  - `./scripts/verify_chain_execution_audit.sh`
  - `./scripts/task_chain_audit_execution.sh <root_task_id>`
  - `./scripts/task_chain_summary.sh <root_task_id>`
- success criterion: the verify exits `0`, prints `VERIFY_CHAIN_EXECUTION_AUDIT_OK`, proves `WARN execution_incomplete`, proves `OK execution_coherent`, and proves `FAIL execution_drift` on a controlled temporary drift fixture
- failure criterion: the verify exits non-zero or the auditor fails to distinguish incomplete, coherent, and drifted execution paths honestly
- blocked criterion: use `BLOCKED` only when the verify cannot run because a real external repo-local prerequisite is unavailable, such as unwritable repo task/outbox paths
- path coverage: incomplete-path, coherent-path, and drift-path
- environment dependencies:
  - writable `tasks/`
  - writable `outbox/manual/`
  - local shell/python tooling required by the repo scripts

### 16. Worker Orchestration Stack

- name: `worker orchestration stack`
- objective: verify the full worker/orchestration/traceability subsystem through one official deep/system check
- verification lane: `deep subsystem verify`
- command(s):
  - `./scripts/verify_worker_orchestration_stack.sh`
  - `./scripts/verify_worker_packet_roundtrip.sh`
  - `./scripts/verify_multi_worker_await_roundtrip.sh`
  - `./scripts/verify_chain_execution_audit.sh`
- success criterion: the verify exits `0`, prints `VERIFY_WORKER_ORCHESTRATION_STACK_OK`, and shows the three canonical sub-capabilities as `PASS`
- failure criterion: the verify exits non-zero because one or more canonical sub-verifies fail internally
- blocked criterion: use `BLOCKED` only when one or more canonical sub-verifies return a real external block
- path coverage: composed subsystem pass-path, composed subsystem blocked-path, and composed subsystem fail-path through delegated sub-verifies
- environment dependencies:
  - writable `tasks/`
  - writable `handoffs/`
  - writable `outbox/manual/`
  - local shell/python tooling required by the repo scripts

### 17. System Readiness

- name: `system readiness`
- objective: provide one honest operational reading of the whole repo/system by aggregating fast self-check, browser stack, and worker orchestration stack
- verification lane: `system readiness verify`
- command(s):
  - `./scripts/verify_system_readiness.sh`
  - `./scripts/task_run_self_check.sh "System readiness / fast self-check"`
  - `./scripts/verify_browser_stack.sh`
  - `./scripts/verify_worker_orchestration_stack.sh`
- success criterion: the verify exits `0`, prints `VERIFY_SYSTEM_READINESS_OK`, and the aggregated subsystems are all healthy
- blocked criterion: use `BLOCKED` when there is no internal failure but one or more critical subsystems are externally blocked, for example browser stack blocked while worker stack remains healthy
- failure criterion: the verify exits non-zero because a critical subsystem fails internally or the aggregated output is incoherent
- path coverage: global-pass-path, global-blocked-path, and global-fail-path through delegated sub-verifies
- environment dependencies:
  - local shell/python tooling required by the repo scripts
  - writable repo paths required by the delegated verifies

This verify should not collapse a browser/environment block into a generic worker failure.
It should preserve the operational reading that worker stack can be `PASS` while browser stack is `BLOCKED`.

### 18. Orchestration Basic

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

### 19. Orchestration V2 Mixed Local+Worker

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

### 20. Orchestration V3 Conditional

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

### 21. Live Smoke Profile

- name: `live smoke profile`
- objective: capture a short, repeatable, honest live demo-state of the current local Clawbot/OpenClaw stack
- verification lane: `live smoke/demo`
- command(s):
  - `./scripts/verify_live_smoke_profile.sh`
  - `./scripts/task_run_self_check.sh "Live smoke profile / fast self-check"`
  - `./scripts/verify_worker_orchestration_stack.sh`
  - `./scripts/verify_browser_stack.sh`
  - `openclaw browser --browser-profile chrome snapshot`
- success criterion: the smoke profile exits `0`, prints `VERIFY_LIVE_SMOKE_PROFILE_OK`, and emits a markdown report in `outbox/manual/`
- blocked criterion: the smoke profile exits `2`, prints `VERIFY_LIVE_SMOKE_PROFILE_BLOCKED`, and still emits a markdown report that shows the live blocked lane honestly
- failure criterion: the smoke profile exits non-zero without a coherent final smoke report or collapses a blocked live lane into an internal failure
- path coverage: stack availability, fast self-check, worker/orchestration stack, live browser action, generated evidence
- environment dependencies:
  - local gateway/runtime availability
  - dashboard/panel reachable from the host
  - writable repo-local `tasks/`
  - writable repo-local `handoffs/`
  - writable repo-local `outbox/manual/`

### 22. User-Facing Delivery Truth

- name: `user-facing delivery truth`
- objective: prove that technical acceptance and real user-visible delivery are tracked separately and audited by task id
- verification lane: `delivery truth`
- command(s):
  - `./scripts/verify_user_facing_delivery_truth.sh`
  - `./scripts/task_record_delivery_transition.sh <task_id> <state> <actor> <channel> <evidence>`
  - `./scripts/task_delivery_summary.sh <task_id>`
  - `./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]`
- success criterion: the verify exits `0`, prints `VERIFY_USER_FACING_DELIVERY_TRUTH_OK`, and proves the partial, visible, verified, and invalid-drift paths
- failure criterion: the verify exits non-zero or allows a user-facing success claim before `visible`
- path coverage: partial accepted path, visible path, verified-by-user path, invalid drift path
- environment dependencies:
  - writable repo-local `tasks/`
  - writable repo-local `outbox/manual/`

### 23. Visible Artifact Delivery Truth

- name: `visible artifact delivery truth`
- objective: prove that a staged artifact only counts as user-visible after canonical destination resolution and post-delivery verification
- verification lane: `visible artifact truth`
- command(s):
  - `./scripts/verify_visible_artifact_delivery_truth.sh`
  - `./scripts/resolve_user_visible_destination.sh <desktop|downloads> [filename] [--json]`
  - `./scripts/task_materialize_visible_artifact.sh <task_id> <artifact_path> <desktop|downloads> [filename] [--json]`
  - `./scripts/task_delivery_summary.sh <task_id>`
  - `./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]`
- success criterion: the verify exits `0`, prints `VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_OK`, and proves verified `desktop` plus `downloads` paths, an honest blocked unverifiable path, and explicit drift detection
- blocked criterion: the verify exits `2`, prints `VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_BLOCKED`, and reports that the current environment cannot prove a canonical desktop or downloads destination
- failure criterion: the verify exits non-zero, allows an unverified visible artifact claim, or misses a reported-path drift
- path coverage: verified desktop path, verified downloads path, blocked unverifiable path, drift mismatch path
- environment dependencies:
  - writable repo-local `tasks/`
  - writable repo-local `outbox/manual/`
  - at least one readable and writable visible `desktop` and `downloads` destination to prove the pass paths

### 24. WhatsApp Delivery Claim Truth

- name: `whatsapp delivery claim truth`
- objective: prove that WhatsApp gateway/provider evidence degrades to the exact allowed wording instead of inflating technical acceptance into delivery
- verification lane: `whatsapp delivery truth`
- command(s):
  - `./scripts/verify_whatsapp_delivery_claim_truth.sh`
  - `./scripts/task_record_whatsapp_delivery.sh <task_id> <state> <actor> <provider> <to> <message_id|-> <raw_result_excerpt> [--run-id <run_id>] [--channel <channel>] [--confidence <confidence>]`
  - `./scripts/task_claim_whatsapp_delivery.sh <task_id> <actor> <requested_claim_level> <evidence> [claim_text]`
  - `./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]`
  - `./scripts/task_delivery_summary.sh <task_id>`
- success criterion: the verify exits `0`, prints `VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_OK`, and proves gateway-only, delivered, verified-by-user, ambiguous-provider, and drift paths
- failure criterion: the verify exits non-zero, allows inflated WhatsApp wording, or misses `message_id` drift
- path coverage: accepted-by-gateway-only path, delivered path, verified-by-user path, ambiguous provider path, drift mismatch path
- environment dependencies:
  - writable repo-local `tasks/`
  - writable repo-local `outbox/manual/`

### 25. Media Ingestion Truth

- name: `media ingestion truth`
- objective: prove that files are ingested into tasks with a canonical material identity before being treated as downstream-ready media
- verification lane: `media ingestion truth`
- command(s):
  - `./scripts/verify_media_ingestion_truth.sh`
  - `./scripts/task_register_media_ingestion.sh <task_id> <task-artifact|visible-artifact|local-path> <source_ref> <actor> <evidence> [--json]`
  - `./scripts/task_verify_media_ready.sh <task_id> <item_id|latest> <actor> <evidence> [--json]`
  - `./scripts/task_media_summary.sh <task_id>`
  - `./scripts/task_claim_user_facing_success.sh <task_id> <actor> <channel> <evidence> [claim]`
- success criterion: the verify exits `0`, prints `VERIFY_MEDIA_INGESTION_TRUTH_OK`, and proves internal-artifact, visible-artifact, and local-path media ingestion plus missing-path, drift, and directory rejection paths
- failure criterion: the verify exits non-zero, treats unreadable or drifted media as ready, or allows a media-required final claim before verification
- path coverage: internal artifact path, visible artifact path, local path, missing path, drift mismatch, directory mismatch
- environment dependencies:
  - writable repo-local `tasks/`
  - writable repo-local `outbox/manual/`

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

For the official execution-audit capability alone, use:

```text
./scripts/verify_capability_matrix.sh chain-execution-audit
```

For the official worker/orchestration/traceability subsystem verify alone, use:

```text
./scripts/verify_capability_matrix.sh worker-orchestration-stack
```

For the official system-wide readiness view alone, use:

```text
./scripts/verify_capability_matrix.sh system-readiness
```

For the official live smoke/demo profile alone, use:

```text
./scripts/verify_capability_matrix.sh live-smoke-profile
```

For the official user-facing delivery truth capability alone, use:

```text
./scripts/verify_capability_matrix.sh user-facing-delivery-truth
```

For the official visible artifact delivery truth capability alone, use:

```text
./scripts/verify_capability_matrix.sh visible-artifact-delivery-truth
```

For the official WhatsApp delivery claim truth capability alone, use:

```text
./scripts/verify_capability_matrix.sh whatsapp-delivery-claim-truth
```

For the official media ingestion truth capability alone, use:

```text
./scripts/verify_capability_matrix.sh media-ingestion-truth
```

For the official host screenshot truth capability alone, use:

```text
./scripts/verify_capability_matrix.sh host-screenshot-truth
```

For the official user-facing readiness profile alone, use:

```text
./scripts/verify_capability_matrix.sh user-facing-readiness
```

For the official live user journey smoke capability alone, use:

```text
./scripts/verify_capability_matrix.sh live-user-journey-smoke
```

It should:

- run the minimum real checks for the matrix
- keep `./scripts/task_run_self_check.sh` as the fast lane and reserve deep end-to-end checks for matrix capabilities
- include `worker packet roundtrip` as the official deep verify for the canonical manual-controlled worker roundtrip
- include `multi-worker barrier orchestration` as the official deep verify for barrier-aware multi-worker continuation
- include `chain execution audit` as the official deep verify for coherent, incomplete, and drift-aware execution auditing against `effective_chain_plan`
- include `worker orchestration stack` as the official deep subsystem verify for the whole worker/orchestration/traceability column
- include `system readiness` as the official top-level operational view across fast self-check, browser stack, and worker stack
- include `live smoke profile` as the official short live demo-state of the current local stack
- include `user-facing delivery truth` as the official guardrail against claiming user-visible success before `visible`
- include `visible artifact delivery truth` as the official guardrail against claiming that a staged artifact is already on the user's desktop or downloads without post-delivery verification
- include `whatsapp delivery claim truth` as the official guardrail against claiming that a gateway-accepted WhatsApp message was really delivered
- include `media ingestion truth` as the official guardrail against claiming that an attachment is ready before its canonical material identity is verified
- include `host screenshot truth` as the official guardrail against claiming visual confirmation before host-side screenshot evidence is materially verified
- include `user-facing readiness` as the official aggregate readout across the five canonical user-facing truth lanes
- include `live user journey smoke` as the official two-journey product-facing smoke that proves where the real user experience passes, blocks, or fails
- keep per-capability evidence logs
- write one markdown report under `outbox/manual/`
- print a readable summary table at the end
- preserve FAIL and BLOCKED honestly instead of hiding them
