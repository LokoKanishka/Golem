#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"
server_log="$tmpdir/server.log"
node_script="$tmpdir/smoke_panel_visible_ui.cjs"
created_task_id_file="$tmpdir/created-task-id.txt"
server_pid=""
dialog_pid=""
window_id=""
title="Panel Visible Host Evidence Smoke $$"

cleanup() {
  if [[ -n "$window_id" ]]; then
    wmctrl -i -c "$window_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$dialog_pid" ]] && kill -0 "$dialog_pid" 2>/dev/null; then
    kill "$dialog_pid" 2>/dev/null || true
    wait "$dialog_pid" 2>/dev/null || true
  fi
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ -f "$created_task_id_file" ]]; then
    task_id="$(cat "$created_task_id_file")"
    if [[ -n "$task_id" && -f "$TASKS_DIR/$task_id.json" ]]; then
      rm -f "$TASKS_DIR/$task_id.json"
    fi
  fi
  if [[ -d "$REPO_ROOT/test-results" ]]; then
    python3 - <<'PY'
from pathlib import Path
import shutil
path = Path("test-results")
if path.exists():
    shutil.rmtree(path)
PY
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

wait_for_active_title() {
  local expected="$1"
  local active_title=""
  for _ in $(seq 1 50); do
    active_title="$(xdotool getactivewindow getwindowname 2>/dev/null || true)"
    if [[ "$active_title" == "$expected" ]]; then
      return 0
    fi
    wmctrl -a "$expected" >/dev/null 2>&1 || true
    sleep 0.1
  done
  printf 'FAIL: active window did not settle on expected title: %s (last=%s)\n' "$expected" "$active_title" >&2
  return 1
}

app_script="$tmpdir/panel_visible_host_app.py"
cat >"$app_script" <<PY
import tkinter as tk

root = tk.Tk()
root.title("${title}")
root.geometry("820x280+220+220")
root.configure(bg="#f7f3ea")

header = tk.Frame(root, bg="#34505d", height=52)
header.pack(fill="x")
header.pack_propagate(False)
tk.Label(header, text="Panel visible host evidence smoke", fg="#ffffff", bg="#34505d", font=("DejaVu Sans", 17, "bold")).pack(side="left", padx=18, pady=10)

body = tk.Frame(root, bg="#f7f3ea")
body.pack(fill="both", expand=True)
for line in [
    "The panel should show real host evidence canonically",
    "Describe evidence stays bridged through the task lane",
    "This window is the active target for the host capture smoke",
]:
    tk.Label(body, text=line, fg="#1f1f1f", bg="#f7f3ea", font=("DejaVu Sans", 14)).pack(anchor="w", padx=20, pady=8)

root.after(45000, root.destroy)
root.mainloop()
PY

python3 "$app_script" >"$tmpdir/app.log" 2>&1 &
dialog_pid="$!"

for _ in $(seq 1 100); do
  window_id="$(xdotool search --name "$title" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$window_id" ]]; then
    break
  fi
  sleep 0.1
done

[[ -n "$window_id" ]] || {
  cat "$tmpdir/app.log" >&2 || true
  echo "FAIL: window with title containing \"$title\" was not found within 10s" >&2
  exit 1
}

xdotool windowactivate "$window_id" >/dev/null 2>&1 || wmctrl -ia "$window_id" >/dev/null 2>&1 || true
wait_for_active_title "$title"

port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

python3 ./scripts/task_panel_http_server.py --host 127.0.0.1 --port "$port" >"$server_log" 2>&1 &
server_pid="$!"

python3 - "$port" <<'PY'
import sys
import time
import urllib.request

port = int(sys.argv[1])
url = f"http://127.0.0.1:{port}/tasks/summary"

deadline = time.time() + 10
while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.2)

raise SystemExit("server did not become ready")
PY

cat >"$node_script" <<'EOF'
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { chromium } = require("playwright");

async function main() {
  const baseUrl = process.env.PANEL_BASE_URL;
  const createdTaskIdFile = process.env.CREATED_TASK_ID_FILE;
  const repoRoot = process.env.REPO_ROOT;
  const hostCapabilitiesRoot = process.env.GOLEM_HOST_CAPABILITIES_ROOT;

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });

  try {
    await page.goto(`${baseUrl}/panel/`, { waitUntil: "networkidle" });
    await page.waitForSelector('[data-testid="summary-total"]');

    const initialTotal = Number((await page.locator('[data-testid="summary-total"]').textContent()).trim());
    if (!Number.isFinite(initialTotal) || initialTotal < 1000) {
      throw new Error(`unexpected summary total: ${initialTotal}`);
    }

    const firstTaskId = ((await page.locator('[data-testid="task-list"] .task-row').first().locator(".mono").textContent()) || "").trim();
    if (!firstTaskId.startsWith("task-")) {
      throw new Error(`unexpected first task id: ${firstTaskId}`);
    }

    await page.locator('[data-testid="task-list"] .task-row').first().click();
    await page.waitForSelector('[data-testid="detail-card"]:not(.hidden)');
    const detailId = ((await page.locator("#detail-id").textContent()) || "").trim();
    if (detailId !== firstTaskId) {
      throw new Error(`detail id mismatch: ${detailId} vs ${firstTaskId}`);
    }

    await page.locator('[data-testid="create-title"]').fill("Smoke panel visible ui");
    await page.locator('[data-testid="create-objective"]').fill("Validate visible panel surface");
    await page.locator('[data-testid="create-type"]').fill("smoke-panel-visible-ui");
    await page.locator('[data-testid="create-owner"]').fill("panel-visible-ui");
    await page.locator('[data-testid="create-accept"]').fill("visible ui create");
    await page.locator('[data-testid="create-submit"]').click();
    await page.waitForFunction((oldId) => {
      const value = document.querySelector("#detail-id")?.textContent?.trim() || "";
      return value.startsWith("task-") && value !== oldId;
    }, firstTaskId);

    const createdTaskId = ((await page.locator("#detail-id").textContent()) || "").trim();
    if (!createdTaskId.startsWith("task-")) {
      throw new Error(`unexpected created task id: ${createdTaskId}`);
    }
    fs.writeFileSync(createdTaskIdFile, createdTaskId, "utf-8");

    const createdSource = ((await page.locator("#detail-source").textContent()) || "").trim();
    if (createdSource !== "panel") {
      throw new Error(`unexpected created source: ${createdSource}`);
    }

    const attachPayload = JSON.parse(
      execFileSync(
        path.join(repoRoot, "scripts", "task_attach_host_describe_evidence.sh"),
        [createdTaskId, "active-window", "--actor", "panel-visible-ui", "--json"],
        {
          cwd: repoRoot,
          env: {
            ...process.env,
            GOLEM_HOST_CAPABILITIES_ROOT: hostCapabilitiesRoot,
          },
          encoding: "utf-8",
        },
      ),
    );
    if (attachPayload.meta.bridge !== "task_attach_host_describe_evidence") {
      throw new Error(`unexpected attach bridge: ${attachPayload.meta.bridge}`);
    }
    if (attachPayload.meta.result.source_kind !== "describe") {
      throw new Error(`unexpected attach source_kind: ${attachPayload.meta.result.source_kind}`);
    }
    if (attachPayload.meta.result.target_kind !== "active-window") {
      throw new Error(`unexpected attach target_kind: ${attachPayload.meta.result.target_kind}`);
    }
    if (!attachPayload.meta.result.summary) {
      throw new Error("attach result summary was empty");
    }
    if (!Array.isArray(attachPayload.meta.attached_artifacts) || attachPayload.meta.attached_artifacts.length < 6) {
      throw new Error(`unexpected attach artifacts: ${JSON.stringify(attachPayload.meta.attached_artifacts)}`);
    }

    await page.locator('[data-testid="update-status"]').selectOption("running");
    await page.locator('[data-testid="update-owner"]').fill("panel-visible-ui");
    await page.locator('[data-testid="update-title"]').fill("Smoke panel visible ui updated");
    await page.locator('[data-testid="update-objective"]').fill("Validate visible panel surface updated");
    await page.locator('[data-testid="update-note"]').fill("visible ui update");
    await page.locator('[data-testid="update-accept"]').fill("visible ui update");
    await page.locator('[data-testid="update-submit"]').click();
    await page.waitForFunction(() => {
      const status = document.querySelector("#detail-status-pill")?.textContent?.trim() || "";
      return status === "running";
    });

    const updatedStatus = ((await page.locator("#detail-status-pill").textContent()) || "").trim();
    if (updatedStatus !== "running") {
      throw new Error(`unexpected updated status: ${updatedStatus}`);
    }

    const hostExpectationBefore = ((await page.locator('[data-testid="host-expectation-summary"]').textContent()) || "").trim();
    if (hostExpectationBefore !== "(none)") {
      throw new Error(`unexpected initial host expectation: ${hostExpectationBefore}`);
    }

    await page.locator('[data-testid="host-target-kind"]').fill("active-window");
    await page.locator('[data-testid="host-require-summary"]').check();
    await page.locator('[data-testid="host-min-artifact-count"]').fill("1");
    await page.locator('[data-testid="host-note"]').fill("visible ui host expectation");
    await page.locator('[data-testid="host-expectation-submit"]').click();
    await page.waitForFunction(() => {
      const summary = document.querySelector('[data-testid="host-expectation-summary"]')?.textContent || "";
      const status = document.querySelector('[data-testid="host-status-pill"]')?.textContent || "";
      const source = document.querySelector('[data-testid="host-source-summary"]')?.textContent || "";
      const evidence = document.querySelector('[data-testid="host-evidence-summary"]')?.textContent || "";
      const meta = document.querySelector('[data-testid="host-evidence-meta"]')?.textContent || "";
      return summary.includes("target=active-window")
        && status.trim() === "match"
        && source.includes("describe")
        && evidence.trim() !== "(none)"
        && meta.includes("artifacts=");
    });

    const hostExpectationSummary = ((await page.locator('[data-testid="host-expectation-summary"]').textContent()) || "").trim();
    const hostVerificationReason = ((await page.locator('[data-testid="host-verification-reason"]').textContent()) || "").trim();
    const hostSourceSummary = ((await page.locator('[data-testid="host-source-summary"]').textContent()) || "").trim();
    const hostSourceMeta = ((await page.locator('[data-testid="host-source-meta"]').textContent()) || "").trim();
    const hostEvidenceSummary = ((await page.locator('[data-testid="host-evidence-summary"]').textContent()) || "").trim();
    const hostEvidenceMeta = ((await page.locator('[data-testid="host-evidence-meta"]').textContent()) || "").trim();
    if (!hostExpectationSummary.includes("target=active-window")) {
      throw new Error(`unexpected host expectation summary: ${hostExpectationSummary}`);
    }
    if (hostVerificationReason !== "host evidence satisfies configured expectation") {
      throw new Error(`unexpected host verification reason after set: ${hostVerificationReason}`);
    }
    if (!hostSourceSummary.includes("describe")) {
      throw new Error(`unexpected host source summary: ${hostSourceSummary}`);
    }
    if (!hostSourceMeta.includes("policy=latest_attached_then_source_precedence")) {
      throw new Error(`unexpected host source meta: ${hostSourceMeta}`);
    }
    if (hostEvidenceSummary === "(none)") {
      throw new Error(`unexpected empty host evidence summary: ${hostEvidenceSummary}`);
    }
    if (!hostEvidenceMeta.includes("artifacts=")) {
      throw new Error(`unexpected host evidence meta: ${hostEvidenceMeta}`);
    }

    await page.locator('[data-testid="host-refresh-submit"]').click();
    await page.waitForFunction(() => {
      const status = document.querySelector('[data-testid="host-status-pill"]')?.textContent || "";
      const meta = document.querySelector('[data-testid="host-verification-meta"]')?.textContent || "";
      const flash = document.querySelector('[data-testid="flash-message"]')?.textContent || "";
      return status.trim() === "match" && meta.includes("source=describe") && meta.includes("by panel-visible") && flash.includes("Refreshed host verification");
    });

    const hostVerificationMeta = ((await page.locator('[data-testid="host-verification-meta"]').textContent()) || "").trim();
    if (!hostVerificationMeta.includes("source=describe") || !hostVerificationMeta.includes("by panel-visible")) {
      throw new Error(`unexpected host verification meta after refresh: ${hostVerificationMeta}`);
    }

    await page.locator('[data-testid="close-status"]').selectOption("done");
    await page.locator('[data-testid="close-owner"]').fill("panel-visible-ui");
    await page.locator('[data-testid="close-note"]').fill("visible ui close");
    await page.locator('[data-testid="close-submit"]').click();
    await page.waitForFunction(() => {
      const status = document.querySelector("#detail-status-pill")?.textContent?.trim() || "";
      const closure = document.querySelector("#detail-closure")?.textContent?.trim() || "";
      return status === "done" && closure === "visible ui close";
    });

    const closedStatus = ((await page.locator("#detail-status-pill").textContent()) || "").trim();
    const closureNote = ((await page.locator("#detail-closure").textContent()) || "").trim();
    if (closedStatus !== "done") {
      throw new Error(`unexpected closed status: ${closedStatus}`);
    }
    if (closureNote !== "visible ui close") {
      throw new Error(`unexpected closure note: ${closureNote}`);
    }

    console.log("SMOKE_PANEL_VISIBLE_UI_OK");
    console.log(`PANEL_VISIBLE_FIRST_ID ${firstTaskId}`);
    console.log(`PANEL_VISIBLE_CREATED_ID ${createdTaskId}`);
    console.log(`PANEL_VISIBLE_SUMMARY_TOTAL ${initialTotal}`);
    console.log(`PANEL_VISIBLE_DETAIL_ID ${detailId}`);
    console.log(`PANEL_VISIBLE_HOST_EXPECTATION ${hostExpectationSummary}`);
    console.log(`PANEL_VISIBLE_HOST_SOURCE ${hostSourceSummary}`);
    console.log(`PANEL_VISIBLE_HOST_SOURCE_META ${hostSourceMeta}`);
    console.log(`PANEL_VISIBLE_HOST_EVIDENCE ${hostEvidenceSummary}`);
    console.log(`PANEL_VISIBLE_HOST_EVIDENCE_META ${hostEvidenceMeta}`);
    console.log(`PANEL_VISIBLE_HOST_VERIFICATION ${hostVerificationReason}`);
    console.log(`PANEL_VISIBLE_HOST_META ${hostVerificationMeta}`);
    console.log(`PANEL_VISIBLE_FINAL_STATUS ${closedStatus}`);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
EOF

cd "$tmpdir"
npm init -y >/dev/null 2>&1
npm install --silent playwright >/dev/null 2>&1
./node_modules/.bin/playwright install chromium >/dev/null 2>&1
PANEL_BASE_URL="http://127.0.0.1:${port}" \
CREATED_TASK_ID_FILE="$created_task_id_file" \
REPO_ROOT="$REPO_ROOT" \
GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
node "$node_script"
