#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

python3 - "$REPO_ROOT" <<'PY'
import pathlib
import subprocess
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
handoffs_dir = repo_root / "handoffs"
outbox_manual_dir = repo_root / "outbox" / "manual"


def git_tracked(path: pathlib.Path) -> bool:
    rel = path.relative_to(repo_root).as_posix()
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", rel],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def git_ignored(path: pathlib.Path) -> bool:
    rel = path.relative_to(repo_root).as_posix()
    result = subprocess.run(
        ["git", "check-ignore", "-q", rel],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def classify(path: pathlib.Path):
    rel = path.relative_to(repo_root).as_posix()
    name = path.name

    if rel == "handoffs/README.md":
        return ("repo_doc", "repo_doc", "n/a", "tracked repository guidance")
    if rel.startswith("handoffs/") and name.endswith(".run.prompt.md"):
        return ("run_prompt", "runtime_only", "yes", "ignored runtime prompt")
    if rel.startswith("handoffs/") and name.endswith(".run.log"):
        return ("run_log", "runtime_only", "no", "ignored runtime log")
    if rel.startswith("handoffs/") and name.endswith(".run.last.md"):
        return ("run_last_message", "runtime_only", "no", "ignored raw final message")
    if rel.startswith("handoffs/") and name.endswith(".run.result.md"):
        return ("worker_result", "durable_local_evidence", "yes", "normalized worker result")
    if rel.startswith("handoffs/") and name.endswith(".codex.md"):
        return ("codex_ticket", "durable_local_evidence", "yes", "Codex ticket")
    if rel.startswith("handoffs/") and name.startswith("task-") and name.endswith(".md"):
        return ("handoff_packet", "durable_local_evidence", "yes", "handoff packet")
    if rel.startswith("outbox/manual/") and path.is_file():
        return ("final_artifact", "durable_local_evidence", "usually_no", "final useful artifact")
    if name.endswith(".tmp") or name.startswith("."):
        return ("temp_noise", "temporary_noise", "n/a", "temporary scratch file")
    return ("unknown", "unknown", "unknown", "unknown file shape")


entries = []
for base in (handoffs_dir, outbox_manual_dir):
    if not base.exists():
        continue
    for path in sorted(base.rglob("*")):
        if path.is_dir():
            continue
        artifact_class, policy_bucket, regenerable, rationale = classify(path)
        entries.append(
            {
                "path": path.relative_to(repo_root).as_posix(),
                "class": artifact_class,
                "bucket": policy_bucket,
                "regenerable": regenerable,
                "rationale": rationale,
                "git": "tracked" if git_tracked(path) else ("ignored" if git_ignored(path) else "untracked"),
            }
        )

bucket_order = [
    "repo_doc",
    "durable_local_evidence",
    "runtime_only",
    "temporary_noise",
    "unknown",
]

counts = {bucket: 0 for bucket in bucket_order}
for entry in entries:
    counts.setdefault(entry["bucket"], 0)
    counts[entry["bucket"]] += 1

print("RUNTIME_ARTIFACT_AUDIT")
print(f"repo: {repo_root.as_posix()}")
print("policy_doc: docs/RUNTIME_ARTIFACT_POLICY.md")
print(f"handoffs_dir: {handoffs_dir.relative_to(repo_root).as_posix()}")
print("runtime_policy: task-specific runtime files stay in handoffs/ but are ignored by Git")
print()
print("summary:")
for bucket in bucket_order:
    print(f"- {bucket}: {counts.get(bucket, 0)}")

unknown = [entry for entry in entries if entry["bucket"] == "unknown"]
print()
print("highlights:")
print(f"- runtime_only_files: {counts.get('runtime_only', 0)}")
if unknown:
    print(f"- unknown_files: {len(unknown)}")
else:
    print("- unknown_files: 0")

for bucket in bucket_order:
    bucket_entries = [entry for entry in entries if entry["bucket"] == bucket]
    if not bucket_entries:
        continue
    print()
    print(f"[{bucket}]")
    for entry in bucket_entries:
        print(
            "- {path} | class={klass} | git={git_state} | regenerable={regen} | {rationale}".format(
                path=entry["path"],
                klass=entry["class"],
                git_state=entry["git"],
                regen=entry["regenerable"],
                rationale=entry["rationale"],
            )
        )
PY
