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
  updateTarget: document.getElementById("update-target"),
  closeTarget: document.getElementById("close-target"),
  flash: document.getElementById("flash-message"),
  filterStatus: document.getElementById("filter-status"),
  filterLimit: document.getElementById("filter-limit"),
  createForm: document.getElementById("create-form"),
  updateForm: document.getElementById("update-form"),
  closeForm: document.getElementById("close-form"),
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

function renderDetail(task) {
  if (!task) {
    els.detailEmpty.classList.remove("hidden");
    els.detailCard.classList.add("hidden");
    els.updateTarget.textContent = "target: none";
    els.closeTarget.textContent = "target: none";
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
    await refreshAll();
  } catch (error) {
    setFlash(error.message, "error");
  }
}

boot();
