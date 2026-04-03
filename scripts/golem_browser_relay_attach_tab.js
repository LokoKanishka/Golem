#!/usr/bin/env node

const DEFAULT_RELAY_URL =
  process.env.GOLEM_BROWSER_RELAY_URL ||
  `http://${process.env.GOLEM_BROWSER_RELAY_HOST || "127.0.0.1"}:${process.env.GOLEM_BROWSER_RELAY_PORT || "18792"}`;

function fatal(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function usage() {
  console.log(`Usage:
  node scripts/golem_browser_relay_attach_tab.js [--json] [--match-url <url-prefix>] [--relay-url http://127.0.0.1:18792]
`);
}

async function fetchJson(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${url}`);
  }
  return response.json();
}

async function main() {
  const args = process.argv.slice(2);
  let outputJson = false;
  let matchUrl = "";
  let relayUrl = DEFAULT_RELAY_URL;

  while (args.length > 0) {
    const arg = args.shift();
    if (arg === "--json") {
      outputJson = true;
      continue;
    }
    if (arg === "--match-url") {
      matchUrl = args.shift() || "";
      if (!matchUrl) fatal("faltante --match-url");
      continue;
    }
    if (arg === "--relay-url") {
      relayUrl = args.shift() || "";
      if (!relayUrl) fatal("faltante --relay-url");
      continue;
    }
    if (arg === "--cdp-url" || arg === "--extension-id" || arg === "--relay-ws-url") {
      const ignored = args.shift() || "";
      if (!ignored) fatal(`faltante valor para ${arg}`);
      continue;
    }
    if (arg === "-h" || arg === "--help") {
      usage();
      return;
    }
    fatal(`argumento no soportado: ${arg}`);
  }

  const attachUrl = new URL("/admin/attach", relayUrl.replace(/\/+$/, "/"));
  if (matchUrl) {
    attachUrl.searchParams.set("url_prefix", matchUrl);
  }

  const payload = await fetchJson(attachUrl.toString());
  const result = {
    ok: Boolean(payload?.ok),
    relay_url: relayUrl.replace(/\/+$/, ""),
    match_url: matchUrl,
    attached_tab_count: payload?.ok ? 1 : 0,
    attached_tab_id: String(payload?.targetId || ""),
    attached_tab_title: String(payload?.title || ""),
    attached_tab_url: String(payload?.url || ""),
    session_id: String(payload?.sessionId || ""),
    attached: Boolean(payload?.attached),
    error: String(payload?.error || ""),
    result: payload || {},
  };

  if (outputJson) {
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.ok ? 0 : 1);
  }

  if (!result.ok) {
    console.log("relay_attach: blocked");
    console.log(`relay_url: ${result.relay_url}`);
    if (result.match_url) {
      console.log(`match_url: ${result.match_url}`);
    }
    if (result.error) {
      console.log(`error: ${result.error}`);
    }
    console.log("RELAY_ATTACH_BLOCKED");
    process.exit(1);
  }

  console.log("relay_attach: ok");
  console.log(`relay_url: ${result.relay_url}`);
  console.log(`attached_tab_url: ${result.attached_tab_url}`);
  console.log(`attached_tab_title: ${result.attached_tab_title}`);
  console.log("RELAY_ATTACH_TRIGGERED");
}

main().catch((error) => fatal(error instanceof Error ? error.message : String(error)));
