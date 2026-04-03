const state = {
  tasks: [],
  listMeta: null,
  selectedTaskId: "",
  selectedTask: null,
  listStatus: "",
  listLimit: "20",
};

const els = {
  summaryTotal: document.getElementById("summary-total"),
  summaryUpdated: document.getElementById("summary-updated"),
  summaryTodo: document.getElementById("summary-todo"),
  summaryRunning: document.getElementById("summary-running"),
  summaryDone: document.getElementById("summary-done"),
  summaryBlocked: document.getElementById("summary-blocked"),
  summaryFailed: document.getElementById("summary-failed"),
  listMeta: document.getElementById("list-meta"),
  taskList: document.getElementById("task-list"),
  detailEmpty: document.getElementById("detail-empty"),
  detailCard: document.getElementById("detail-card"),
  detailTitle: document.getElementById("detail-title"),
  detailId: document.getElementById("detail-id"),
  detailStatusPill: document.getElementById("detail-status-pill"),
  detailOwner: document.getElementById("detail-owner"),
  detailSource: document.getElementById("detail-source"),
  detailUpdated: document.getElementById("detail-updated"),
  detailType: document.getElementById("detail-type"),
  detailObjective: document.getElementById("detail-objective"),
  detailAcceptance: document.getElementById("detail-acceptance"),
  detailNotes: document.getElementById("detail-notes"),
  detailClosure: document.getElementById("detail-closure"),
  hostStatusPill: document.getElementById("host-status-pill"),
  hostExpectationSummary: document.getElementById("host-expectation-summary"),
  hostExpectationMeta: document.getElementById("host-expectation-meta"),
  hostVerificationReason: document.getElementById("host-verification-reason"),
  hostVerificationMeta: document.getElementById("host-verification-meta"),
  hostSourceSummary: document.getElementById("host-source-summary"),
  hostSourceMeta: document.getElementById("host-source-meta"),
  hostEvidenceSummary: document.getElementById("host-evidence-summary"),
  hostEvidenceMeta: document.getElementById("host-evidence-meta"),
  updateTarget: document.getElementById("update-target"),
  closeTarget: document.getElementById("close-target"),
  flash: document.getElementById("flash-message"),
  filterStatus: document.getElementById("filter-status"),
  filterLimit: document.getElementById("filter-limit"),
  createForm: document.getElementById("create-form"),
  updateForm: document.getElementById("update-form"),
  closeForm: document.getElementById("close-form"),
  hostExpectationForm: document.getElementById("host-expectation-form"),
  hostRefreshForm: document.getElementById("host-refresh-form"),
  refreshAll: document.getElementById("refresh-all"),
  reloadDetail: document.getElementById("reload-detail"),
  listControls: document.getElementById("list-controls"),
};

async function request(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.message || payload.error || "request failed");
  }
  return payload;
}

function setFlash(message, tone = "") {
  els.flash.textContent = message;
  els.flash.className = tone ? `flash-${tone}` : "";
}

function splitLines(value) {
  return value
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function statusClass(status) {
  return `status-pill status-${(status || "").toLowerCase()}`;
}

function setFormDisabled(form, disabled) {
  for (const element of form.elements) {
    element.disabled = disabled;
  }
}

function compactJoin(parts, fallback = "(none)") {
  const filtered = parts.map((part) => String(part || "").trim()).filter(Boolean);
  return filtered.length ? filtered.join(" | ") : fallback;
}

function hostStatusClass(verification) {
  if (!verification?.present) {
    return "status-pill status-neutral";
  }
  return statusClass(verification.status || "neutral");
}

function renderSummary(inventory) {
  const counts = inventory.status_counts || {};
  els.summaryTotal.textContent = String(inventory.total ?? 0);
  els.summaryUpdated.textContent = `latest: ${inventory.latest_updated_at || "(none)"}`;
  els.summaryTodo.textContent = String(counts.todo || 0);
  els.summaryRunning.textContent = String(counts.running || 0);
  els.summaryDone.textContent = String(counts.done || 0);
  els.summaryBlocked.textContent = String(counts.blocked || 0);
  els.summaryFailed.textContent = String(counts.failed || 0);
}

function renderTaskList(meta, tasks) {
  els.listMeta.textContent = `source=${meta.source_of_truth} matched=${meta.matched} returned=${meta.returned}`;
  els.taskList.innerHTML = "";

  if (!tasks.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No tasks matched the current filter.";
    els.taskList.appendChild(empty);
    return;
  }

  for (const task of tasks) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "task-row";
    if (task.id === state.selectedTaskId) {
      button.classList.add("active");
    }
    button.dataset.taskId = task.id;
    button.innerHTML = `
      <div class="task-topline">
        <span class="task-title">${escapeHtml(task.title)}</span>
        <span class="${statusClass(task.status)}">${escapeHtml(task.status)}</span>
      </div>
      <div class="task-meta mono">${escapeHtml(task.id)}</div>
      <div class="task-meta">owner=${escapeHtml(task.owner)} source=${escapeHtml(task.source_channel)}</div>
    `;
    button.addEventListener("click", () => selectTask(task.id));
    els.taskList.appendChild(button);
  }
}

function renderHost(task) {
  const expectation = task?.host_expectation || { present: false };
  const verification = task?.host_verification || { present: false };
  const evidence = task?.host_evidence_summary || { present: false };

  if (!task) {
    els.hostStatusPill.textContent = "not configured";
    els.hostStatusPill.className = "status-pill status-neutral";
    els.hostExpectationSummary.textContent = "(none)";
    els.hostExpectationMeta.textContent = "Select a task to configure host expectation.";
    els.hostVerificationReason.textContent = "(none)";
    els.hostVerificationMeta.textContent = "No host verification available.";
    els.hostSourceSummary.textContent = "(none)";
    els.hostSourceMeta.textContent = "No host evidence selected.";
    els.hostEvidenceSummary.textContent = "(none)";
    els.hostEvidenceMeta.textContent = "No host evidence attached.";
    els.hostExpectationForm.reset();
    els.hostExpectationForm.elements.min_artifact_count.value = "0";
    els.hostRefreshForm.reset();
    setFormDisabled(els.hostExpectationForm, true);
    setFormDisabled(els.hostRefreshForm, true);
    return;
  }

  const expectationChecks = [];
  if (expectation.target_kind) {
    expectationChecks.push(`target=${expectation.target_kind}`);
  }
  if (expectation.surface_category) {
    expectationChecks.push(`surface=${expectation.surface_category}`);
  }
  if (expectation.min_surface_confidence) {
    expectationChecks.push(`confidence>=${expectation.min_surface_confidence}`);
  }
  if (expectation.require_summary) {
    expectationChecks.push("summary required");
  }
  if (Number(expectation.min_artifact_count || 0) > 0) {
    expectationChecks.push(`artifacts>=${expectation.min_artifact_count}`);
  }
  if (expectation.require_structured_fields) {
    expectationChecks.push("structured fields required");
  }

  els.hostStatusPill.textContent = verification.present ? verification.status || "unknown" : "not configured";
  els.hostStatusPill.className = hostStatusClass(verification);
  els.hostExpectationSummary.textContent = expectation.present
    ? compactJoin(expectationChecks, "configured with no explicit checks")
    : "(none)";
  els.hostExpectationMeta.textContent = expectation.present
    ? compactJoin(
        [
          expectation.configured_at ? `configured ${expectation.configured_at}` : "",
          expectation.configured_by ? `by ${expectation.configured_by}` : "",
          expectation.note ? `note: ${expectation.note}` : "",
        ],
        "Host expectation configured.",
      )
    : "No host expectation configured.";

  els.hostVerificationReason.textContent = verification.present
    ? verification.reason || verification.status || "(none)"
    : "(none)";
  els.hostVerificationMeta.textContent = verification.present
    ? compactJoin(
        [
          verification.source_kind ? `source=${verification.source_kind}` : "",
          verification.capture_lane ? `lane=${verification.capture_lane}` : "",
          verification.last_evaluated_at ? `evaluated ${verification.last_evaluated_at}` : "",
          verification.evaluated_by ? `by ${verification.evaluated_by}` : "",
          verification.stale_reasons?.length ? `stale: ${verification.stale_reasons.join(", ")}` : "",
          verification.mismatch_checks?.length ? `mismatch: ${verification.mismatch_checks.join(", ")}` : "",
          verification.insufficient_checks?.length ? `insufficient: ${verification.insufficient_checks.join(", ")}` : "",
        ],
        "Host verification present.",
      )
    : "No host verification available.";

  els.hostSourceSummary.textContent = evidence.present
    ? compactJoin(
        [
          evidence.source_kind || "",
          evidence.capture_lane || "",
        ],
        "(none)",
      )
    : "(none)";
  els.hostSourceMeta.textContent = evidence.present
    ? compactJoin(
        [
          evidence.selection_policy ? `policy=${evidence.selection_policy}` : "",
          evidence.selection_reason || "",
          evidence.last_attached_at ? `attached ${evidence.last_attached_at}` : "",
        ],
        "Host evidence selected.",
      )
    : "No host evidence selected.";

  const actualSurface = compactJoin(
    [
      evidence.target_kind ? `target=${evidence.target_kind}` : "",
      evidence.surface_category ? `surface=${evidence.surface_category}` : "",
      evidence.surface_confidence ? `confidence=${evidence.surface_confidence}` : "",
    ],
    "",
  );
  els.hostEvidenceSummary.textContent = evidence.present
    ? evidence.summary || actualSurface || "(none)"
    : "(none)";
  els.hostEvidenceMeta.textContent = evidence.present
    ? compactJoin(
        [
          actualSurface,
          Number(evidence.artifact_count || 0) > 0 ? `artifacts=${evidence.artifact_count}` : "",
          evidence.evidence_path ? `evidence=${evidence.evidence_path}` : "",
        ],
        "Host evidence attached.",
      )
    : "No host evidence attached.";

  els.hostExpectationForm.elements.target_kind.value = expectation.target_kind || "";
  els.hostExpectationForm.elements.surface_category.value = expectation.surface_category || "";
  els.hostExpectationForm.elements.min_surface_confidence.value = expectation.min_surface_confidence || "";
  els.hostExpectationForm.elements.min_artifact_count.value = String(expectation.min_artifact_count || 0);
  els.hostExpectationForm.elements.require_summary.checked = Boolean(expectation.require_summary);
  els.hostExpectationForm.elements.require_structured_fields.checked = Boolean(expectation.require_structured_fields);
  els.hostExpectationForm.elements.note.value = expectation.note || "";
  els.hostRefreshForm.elements.source.value = "";
  setFormDisabled(els.hostExpectationForm, false);
  setFormDisabled(els.hostRefreshForm, false);
}

function renderDetail(task) {
  if (!task) {
    els.detailEmpty.classList.remove("hidden");
    els.detailCard.classList.add("hidden");
    els.updateTarget.textContent = "target: none";
    els.closeTarget.textContent = "target: none";
    renderHost(null);
    return;
  }

  els.detailEmpty.classList.add("hidden");
  els.detailCard.classList.remove("hidden");
  els.detailTitle.textContent = task.title || "(untitled)";
  els.detailId.textContent = task.id;
  els.detailStatusPill.textContent = task.status;
  els.detailStatusPill.className = statusClass(task.status);
  els.detailOwner.textContent = task.owner || "(none)";
  els.detailSource.textContent = task.source_channel || "(none)";
  els.detailUpdated.textContent = task.updated_at || "(none)";
  els.detailType.textContent = task.type || "(none)";
  els.detailObjective.textContent = task.objective || "(none)";
  els.detailAcceptance.textContent = (task.acceptance_criteria || []).join("\n") || "(none)";
  els.detailNotes.textContent = (task.notes || []).slice(-5).join("\n") || "(none)";
  els.detailClosure.textContent = task.closure_note || "(none)";
  els.updateTarget.textContent = `target: ${task.id}`;
  els.closeTarget.textContent = `target: ${task.id}`;
  renderHost(task);
}

async function loadSummary() {
  const payload = await request("/tasks/summary");
  renderSummary(payload.inventory);
}

async function loadTasks() {
  const query = new URLSearchParams();
  if (state.listStatus) {
    query.set("status", state.listStatus);
  }
  if (state.listLimit) {
    query.set("limit", state.listLimit);
  }
  const suffix = query.toString() ? `?${query.toString()}` : "";
  const payload = await request(`/tasks${suffix}`);
  state.tasks = payload.tasks;
  state.listMeta = payload.meta;
  renderTaskList(payload.meta, state.tasks);
}

async function selectTask(taskId) {
  state.selectedTaskId = taskId;
  const payload = await request(`/tasks/${encodeURIComponent(taskId)}`);
  state.selectedTask = payload.task;
  renderDetail(state.selectedTask);
  renderTaskList(
    state.listMeta || {
      source_of_truth: "tasks/*.json",
      matched: state.tasks.length,
      returned: state.tasks.length,
    },
    state.tasks,
  );
}

async function refreshAll() {
  setFlash("Refreshing panel...");
  await loadSummary();
  await loadTasks();
  if (state.selectedTaskId) {
    await selectTask(state.selectedTaskId);
  }
  setFlash("Panel refreshed.", "success");
}

async function onCreate(event) {
  event.preventDefault();
  const formData = new FormData(els.createForm);
  const payload = {
    title: formData.get("title").trim(),
    objective: formData.get("objective").trim(),
    type: formData.get("type").trim(),
    owner: formData.get("owner").trim(),
    accept: splitLines(formData.get("accept")),
    source: "panel",
    canonical_session: "panel-visible-ui",
    origin: "panel-visible-ui",
  };
  const response = await request("/tasks", { method: "POST", body: JSON.stringify(payload) });
  els.createForm.reset();
  els.createForm.elements.type.value = "panel-visible-ui";
  els.createForm.elements.owner.value = "panel-visible";
  await refreshAll();
  await selectTask(response.task.id);
  setFlash(`Created ${response.task.id}.`, "success");
}

async function onUpdate(event) {
  event.preventDefault();
  if (!state.selectedTaskId) {
    setFlash("Select a task before updating it.", "error");
    return;
  }

  const formData = new FormData(els.updateForm);
  const payload = {
    status: formData.get("status").trim(),
    owner: formData.get("owner").trim(),
    title: formData.get("title").trim(),
    objective: formData.get("objective").trim(),
    note: formData.get("note").trim(),
    append_accept: splitLines(formData.get("append_accept")),
    source: "panel",
    actor: "panel-visible",
  };
  await request(`/tasks/${encodeURIComponent(state.selectedTaskId)}/update`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  els.updateForm.reset();
  await refreshAll();
  await selectTask(state.selectedTaskId);
  setFlash(`Updated ${state.selectedTaskId}.`, "success");
}

async function onClose(event) {
  event.preventDefault();
  if (!state.selectedTaskId) {
    setFlash("Select a task before closing it.", "error");
    return;
  }

  const formData = new FormData(els.closeForm);
  const payload = {
    status: formData.get("status").trim(),
    note: formData.get("note").trim(),
    owner: formData.get("owner").trim(),
    source: "panel",
    actor: "panel-visible",
  };
  await request(`/tasks/${encodeURIComponent(state.selectedTaskId)}/close`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  els.closeForm.reset();
  await refreshAll();
  await selectTask(state.selectedTaskId);
  setFlash(`Closed ${state.selectedTaskId}.`, "success");
}

async function onSetHostExpectation(event) {
  event.preventDefault();
  if (!state.selectedTaskId) {
    setFlash("Select a task before configuring host expectation.", "error");
    return;
  }

  const formData = new FormData(els.hostExpectationForm);
  const minArtifactCount = Number(formData.get("min_artifact_count") || 0);
  const payload = {
    target_kind: formData.get("target_kind").trim(),
    surface_category: formData.get("surface_category").trim(),
    min_surface_confidence: formData.get("min_surface_confidence").trim(),
    require_summary: formData.get("require_summary") === "on",
    min_artifact_count: Number.isFinite(minArtifactCount) && minArtifactCount >= 0 ? minArtifactCount : 0,
    require_structured_fields: formData.get("require_structured_fields") === "on",
    note: formData.get("note").trim(),
    actor: "panel-visible",
  };
  await request(`/tasks/${encodeURIComponent(state.selectedTaskId)}/host-expectation`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  await refreshAll();
  setFlash(`Saved host expectation for ${state.selectedTaskId}.`, "success");
}

async function onRefreshHostVerification(event) {
  event.preventDefault();
  if (!state.selectedTaskId) {
    setFlash("Select a task before refreshing host verification.", "error");
    return;
  }

  const formData = new FormData(els.hostRefreshForm);
  const payload = {
    source: formData.get("source").trim(),
    actor: "panel-visible",
  };
  await request(`/tasks/${encodeURIComponent(state.selectedTaskId)}/host-verification/refresh`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  await refreshAll();
  setFlash(`Refreshed host verification for ${state.selectedTaskId}.`, "success");
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function boot() {
  els.filterStatus.value = state.listStatus;
  els.filterLimit.value = state.listLimit;

  els.listControls.addEventListener("submit", async (event) => {
    event.preventDefault();
    state.listStatus = els.filterStatus.value;
    state.listLimit = els.filterLimit.value;
    await refreshAll();
  });
  els.createForm.addEventListener("submit", (event) => {
    onCreate(event).catch((error) => setFlash(error.message, "error"));
  });
  els.updateForm.addEventListener("submit", (event) => {
    onUpdate(event).catch((error) => setFlash(error.message, "error"));
  });
  els.closeForm.addEventListener("submit", (event) => {
    onClose(event).catch((error) => setFlash(error.message, "error"));
  });
  els.hostExpectationForm.addEventListener("submit", (event) => {
    onSetHostExpectation(event).catch((error) => setFlash(error.message, "error"));
  });
  els.hostRefreshForm.addEventListener("submit", (event) => {
    onRefreshHostVerification(event).catch((error) => setFlash(error.message, "error"));
  });
  els.refreshAll.addEventListener("click", () => {
    refreshAll().catch((error) => setFlash(error.message, "error"));
  });
  els.reloadDetail.addEventListener("click", () => {
    if (!state.selectedTaskId) {
      setFlash("No task selected.", "error");
      return;
    }
    selectTask(state.selectedTaskId).catch((error) => setFlash(error.message, "error"));
  });

  try {
    renderHost(null);
    await refreshAll();
  } catch (error) {
    setFlash(error.message, "error");
  }
}

boot();
