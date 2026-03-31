#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");

function usage() {
  console.log(`Uso:
  ./scripts/browser_cdp_tool.sh tabs
  ./scripts/browser_cdp_tool.sh open <url>
  ./scripts/browser_cdp_tool.sh snapshot [selector]
  ./scripts/browser_cdp_tool.sh find <texto> [selector]

Variables opcionales:
  GOLEM_BROWSER_CDP_URL      URL base del browser remoto (default: http://127.0.0.1:9222)
  GOLEM_BROWSER_DEVTOOLS_FILE Ruta a DevToolsActivePort para resolver el browser URL
  GOLEM_BROWSER_TARGET       Selector por defecto para snapshot/find
`);
}

function fatal(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}

function candidateDevtoolsFiles() {
  const out = [];
  if (process.env.GOLEM_BROWSER_DEVTOOLS_FILE) {
    out.push(process.env.GOLEM_BROWSER_DEVTOOLS_FILE);
  }
  out.push(path.join(os.homedir(), ".config/google-chrome/DevToolsActivePort"));
  return out;
}

function resolveBrowserBaseUrl() {
  const explicit = process.env.GOLEM_BROWSER_CDP_URL;
  if (explicit) {
    return trimTrailingSlash(explicit);
  }
  for (const file of candidateDevtoolsFiles()) {
    try {
      const raw = fs.readFileSync(file, "utf8").trim();
      const [port] = raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
      if (!port) {
        continue;
      }
      return `http://127.0.0.1:${port}`;
    } catch (_) {
      // keep trying known locations
    }
  }
  return "http://127.0.0.1:9222";
}

async function fetchJson(url, init) {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(`fallo HTTP ${response.status} en ${url}`);
  }
  return response.json();
}

async function fetchText(url, init) {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(`fallo HTTP ${response.status} en ${url}`);
  }
  return response.text();
}

function normalizeTabs(rawTabs) {
  return rawTabs
    .filter((tab) => tab && tab.type === "page")
    .map((tab, index) => ({
      index,
      id: tab.id || tab.targetId || "",
      title: tab.title || "",
      url: tab.url || "",
      wsUrl: tab.webSocketDebuggerUrl || "",
    }));
}

function isInternalTab(tab) {
  return /^chrome:\/\//.test(tab.url) || /^devtools:\/\//.test(tab.url);
}

function pickDefaultTab(tabs) {
  const nonInternal = tabs.filter((tab) => !isInternalTab(tab));
  if (nonInternal.length > 0) {
    return nonInternal[nonInternal.length - 1];
  }
  return tabs[tabs.length - 1] || null;
}

function resolveTab(tabs, selector) {
  if (tabs.length === 0) {
    throw new Error("no hay tabs disponibles en el browser remoto");
  }
  const wanted = (selector || process.env.GOLEM_BROWSER_TARGET || "").trim();
  if (!wanted) {
    const fallback = pickDefaultTab(tabs);
    if (!fallback) {
      throw new Error("no se pudo elegir una tab por defecto");
    }
    return fallback;
  }
  if (/^\d+$/.test(wanted)) {
    const byIndex = tabs.find((tab) => tab.index === Number(wanted));
    if (!byIndex) {
      throw new Error(`no existe una tab con indice ${wanted}`);
    }
    return byIndex;
  }
  const needle = wanted.toLowerCase();
  const match = tabs.find((tab) =>
    tab.title.toLowerCase().includes(needle) || tab.url.toLowerCase().includes(needle)
  );
  if (!match) {
    throw new Error(`no se encontro una tab que coincida con "${wanted}"`);
  }
  return match;
}

class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.socket = null;
    this.nextId = 1;
    this.pending = new Map();
  }

  async connect() {
    await new Promise((resolve, reject) => {
      const socket = new WebSocket(this.wsUrl);
      socket.addEventListener("open", () => {
        this.socket = socket;
        resolve();
      });
      socket.addEventListener("message", (event) => {
        let payload;
        try {
          payload = JSON.parse(String(event.data));
        } catch (error) {
          return;
        }
        if (!payload || typeof payload.id !== "number") {
          return;
        }
        const waiter = this.pending.get(payload.id);
        if (!waiter) {
          return;
        }
        this.pending.delete(payload.id);
        if (payload.error) {
          waiter.reject(new Error(payload.error.message || "CDP error"));
          return;
        }
        waiter.resolve(payload.result);
      });
      socket.addEventListener("error", () => {
        reject(new Error(`no se pudo abrir WebSocket CDP: ${this.wsUrl}`));
      });
      socket.addEventListener("close", () => {
        for (const waiter of this.pending.values()) {
          waiter.reject(new Error("conexion CDP cerrada"));
        }
        this.pending.clear();
      });
    });
  }

  async send(method, params = {}) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("conexion CDP no disponible");
    }
    const id = this.nextId++;
    const payload = JSON.stringify({ id, method, params });
    return await new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(payload);
    });
  }

  async close() {
    if (!this.socket) {
      return;
    }
    await new Promise((resolve) => {
      const socket = this.socket;
      this.socket = null;
      socket.addEventListener("close", () => resolve(), { once: true });
      socket.close();
      setTimeout(resolve, 250);
    });
  }
}

async function listTabs(baseUrl) {
  const rawTabs = await fetchJson(`${baseUrl}/json/list`);
  return normalizeTabs(rawTabs);
}

async function openTab(baseUrl, url) {
  if (!/^https?:\/\//.test(url)) {
    throw new Error("la URL debe empezar con http:// o https://");
  }
  return fetchJson(`${baseUrl}/json/new?${encodeURIComponent(url)}`, {
    method: "PUT",
  });
}

async function snapshotTab(tab) {
  if (!tab.wsUrl) {
    throw new Error("la tab elegida no expone webSocketDebuggerUrl");
  }
  const client = new CdpClient(tab.wsUrl);
  await client.connect();
  try {
    await client.send("Runtime.enable");
    const evaluation = await client.send("Runtime.evaluate", {
      returnByValue: true,
      awaitPromise: true,
      expression: `(() => {
        const root = document.body || document.documentElement;
        const text = root ? root.innerText : "";
        const normalized = text
          .replace(/\\u00a0/g, " ")
          .replace(/\\r/g, "")
          .split("\\n")
          .map((line) => line.trim())
          .filter(Boolean)
          .slice(0, 400);
        const links = Array.from(document.querySelectorAll("a[href]"))
          .map((node) => ({
            text: (node.innerText || node.textContent || "").trim(),
            href: node.href || ""
          }))
          .filter((item) => item.text || item.href)
          .slice(0, 80);
        return {
          title: document.title || "",
          url: location.href,
          lines: normalized,
          links
        };
      })()`,
    });
    return evaluation.result.value;
  } finally {
    await client.close();
  }
}

function printTabs(tabs) {
  if (tabs.length === 0) {
    console.log("No tabs.");
    return;
  }
  for (const tab of tabs) {
    console.log(`${tab.index}. ${tab.title || "(sin titulo)"}`);
    console.log(`   url: ${tab.url || "(sin url)"}`);
    console.log(`   id: ${tab.id || "(sin id)"}`);
  }
}

function printSnapshot(snapshot, selector) {
  console.log(`# CDP Snapshot`);
  console.log(`captured_at: ${new Date().toISOString()}`);
  if (selector) {
    console.log(`selector: ${selector}`);
  }
  console.log(`title: ${snapshot.title}`);
  console.log(`url: ${snapshot.url}`);
  console.log("");
  console.log("## Text");
  if (snapshot.lines.length === 0) {
    console.log("(sin texto visible)");
  } else {
    for (const line of snapshot.lines) {
      console.log(`- ${line}`);
    }
  }
  if (snapshot.links.length > 0) {
    console.log("");
    console.log("## Links");
    for (const link of snapshot.links) {
      console.log(`- ${link.text || "(sin texto)"} :: ${link.href}`);
    }
  }
}

function printFind(snapshot, query, selector) {
  const needle = query.toLowerCase();
  const matches = [];
  snapshot.lines.forEach((line, index) => {
    if (line.toLowerCase().includes(needle)) {
      matches.push({ index, line });
    }
  });

  console.log(`# CDP Find`);
  console.log(`captured_at: ${new Date().toISOString()}`);
  if (selector) {
    console.log(`selector: ${selector}`);
  }
  console.log(`title: ${snapshot.title}`);
  console.log(`url: ${snapshot.url}`);
  console.log(`query: ${query}`);
  console.log("");
  console.log("## Matches");
  if (matches.length === 0) {
    console.log(`Sin coincidencias para: ${query}`);
    return;
  }
  for (const match of matches) {
    const start = Math.max(0, match.index - 2);
    const end = Math.min(snapshot.lines.length, match.index + 3);
    console.log(`- linea ${match.index + 1}: ${match.line}`);
    for (let i = start; i < end; i += 1) {
      const prefix = i === match.index ? "  >" : "   ";
      console.log(`${prefix} ${i + 1}. ${snapshot.lines[i]}`);
    }
  }
}

async function main() {
  const [, , command, ...args] = process.argv;
  if (!command || command === "-h" || command === "--help") {
    usage();
    return;
  }

  const baseUrl = resolveBrowserBaseUrl();

  if (command === "tabs") {
    const tabs = await listTabs(baseUrl);
    printTabs(tabs);
    return;
  }

  if (command === "open") {
    const url = args[0];
    if (!url) {
      fatal("falta URL");
    }
    const created = await openTab(baseUrl, url);
    console.log("TAB_OPENED");
    console.log(`title: ${created.title || ""}`);
    console.log(`url: ${created.url || ""}`);
    return;
  }

  if (command === "snapshot") {
    const selector = args[0] || "";
    const tabs = await listTabs(baseUrl);
    const tab = resolveTab(tabs, selector);
    const snapshot = await snapshotTab(tab);
    printSnapshot(snapshot, selector);
    return;
  }

  if (command === "find") {
    const query = args[0];
    const selector = args[1] || "";
    if (!query) {
      fatal("falta texto a buscar");
    }
    const tabs = await listTabs(baseUrl);
    const tab = resolveTab(tabs, selector);
    const snapshot = await snapshotTab(tab);
    printFind(snapshot, query, selector);
    return;
  }

  fatal(`comando no soportado: ${command}`);
}

main().catch((error) => {
  fatal(error.message || String(error));
});
