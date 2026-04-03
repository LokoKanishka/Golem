#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
server_log="$tmpdir/server.log"
node_script="$tmpdir/smoke_panel_visible_ui.cjs"
created_task_id_file="$tmpdir/created-task-id.txt"
server_pid=""

cleanup() {
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
const { chromium } = require("playwright");

async function main() {
  const baseUrl = process.env.PANEL_BASE_URL;
  const createdTaskIdFile = process.env.CREATED_TASK_ID_FILE;

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
      const meta = document.querySelector('[data-testid="host-verification-meta"]')?.textContent || "";
      return summary.includes("target=active-window") && status.trim() === "insufficient_evidence" && meta.includes("by panel");
    });

    const hostExpectationSummary = ((await page.locator('[data-testid="host-expectation-summary"]').textContent()) || "").trim();
    const hostVerificationReason = ((await page.locator('[data-testid="host-verification-reason"]').textContent()) || "").trim();
    if (!hostExpectationSummary.includes("target=active-window")) {
      throw new Error(`unexpected host expectation summary: ${hostExpectationSummary}`);
    }
    if (hostVerificationReason !== "no host evidence attached") {
      throw new Error(`unexpected host verification reason after set: ${hostVerificationReason}`);
    }

    await page.locator('[data-testid="host-refresh-submit"]').click();
    await page.waitForFunction(() => {
      const meta = document.querySelector('[data-testid="host-verification-meta"]')?.textContent || "";
      const flash = document.querySelector('[data-testid="flash-message"]')?.textContent || "";
      return meta.includes("by panel-visible") && flash.includes("Refreshed host verification");
    });

    const hostVerificationMeta = ((await page.locator('[data-testid="host-verification-meta"]').textContent()) || "").trim();
    if (!hostVerificationMeta.includes("by panel-visible")) {
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
node "$node_script"
