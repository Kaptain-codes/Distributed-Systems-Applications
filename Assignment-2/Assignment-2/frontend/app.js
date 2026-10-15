"use strict";

/* ---------------------------------------------------------------------------
 * Food Delivery operator console.
 * Talks only to the seven HTTP services, through the API gateway (nginx forwards /api to it).
 * ------------------------------------------------------------------------- */

const SECTIONS = [
  { route: "", label: "Overview", icon: "layout-dashboard" },
  { route: "customers", label: "Customers", icon: "users", service: "customers", port: 8082, base: "/customers", tint: "white" },
  { route: "restaurants", label: "Restaurants", icon: "chef-hat", service: "restaurants", port: 8087, base: "/restaurants", tint: "canary" },
  { route: "orders", label: "Orders", icon: "receipt-text", service: "orders", port: 8081, base: "/orders", tint: "white" },
  { route: "payments", label: "Payments", icon: "credit-card", service: "payments", port: 8084, base: "/payments", tint: "pink" },
  { route: "delivery", label: "Delivery", icon: "bike", service: "delivery", port: 8086, base: "/delivery", tint: "blue" },
  { route: "notifications", label: "Notifications", icon: "bell", service: "notifications", port: 8083, base: "/notifications", tint: "green" },
  { route: "reports", label: "Reports", icon: "chart-column", service: "admin", port: 8085, base: "/admin/reports", tint: "ink" },
];
const SERVICES = SECTIONS.filter((s) => s.service);

const ORDER_FLOW = ["CREATED", "CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY", "DELIVERED"];
const ORDER_NEXT = { CREATED: "CONFIRMED", CONFIRMED: "PREPARING", PREPARING: "READY", READY: "OUT_FOR_DELIVERY", OUT_FOR_DELIVERY: "DELIVERED" };
const ORDER_ACTION = { CONFIRMED: "Confirm order", PREPARING: "Start preparing", READY: "Mark ready", OUT_FOR_DELIVERY: "Hand to driver", DELIVERED: "Mark delivered" };
const ORDER_CANCELLABLE = ["CREATED", "CONFIRMED", "PREPARING"];
const DELIVERY_NEXT = { ASSIGNED: "PICKED_UP", PICKED_UP: "IN_TRANSIT", IN_TRANSIT: "DELIVERED" };
const DELIVERY_ACTION = { PICKED_UP: "Picked up", IN_TRANSIT: "In transit", DELIVERED: "Delivered" };
const DAYS = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"];

/* ---------- small helpers ---------- */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function uid(prefix) {
  const uuid = crypto.randomUUID ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16));
  return `${prefix}-${uuid}`;
}

const nowIso = () => new Date().toISOString();

const moneyFmt = new Intl.NumberFormat("en-NA", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
function money(amount, currency = "NAD") {
  const n = Number(amount);
  if (!Number.isFinite(n)) return "—";
  return `${currency === "NAD" ? "N$" : esc(currency)} ${moneyFmt.format(n)}`;
}

const timeFmt = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
function when(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? esc(iso) : timeFmt.format(d);
}

/** "order-3f9a2c71-0d44-..." -> "order-3f9a2c71" with the full id one copy-click away. */
function shortId(id) {
  const m = String(id).match(/^(.*?-?[0-9a-f]{8})-[0-9a-f]{4}-/i);
  return m ? m[1] : String(id);
}
function orderLink(id) {
  return `<span class="id-wrap inline-flex items-center gap-1"><a class="id row-link rounded hover:underline" title="${esc(id)}" href="#/orders/${encodeURIComponent(id)}">${esc(shortId(id))}</a><button type="button" class="copy-btn p-1 rounded focus-ring text-ink-500 hover:text-ink" data-action="copy" data-value="${esc(id)}" aria-label="Copy ${esc(id)}"><i data-lucide="copy" class="w-3.5 h-3.5"></i></button></span>`;
}
function idCell(id) {
  if (!id) return `<span class="text-ink-300">—</span>`;
  const short = shortId(id);
  return `<span class="id-wrap inline-flex items-center gap-1"><span class="id" title="${esc(id)}">${esc(short)}</span><button type="button" class="copy-btn p-1 rounded focus-ring text-ink-500 hover:text-ink" data-action="copy" data-value="${esc(id)}" aria-label="Copy ${esc(id)}"><i data-lucide="copy" class="w-3.5 h-3.5"></i></button></span>`;
}

const STAMP_TONE = {
  CREATED: "ink", CONFIRMED: "ink", PREPARING: "active", READY: "active", OUT_FOR_DELIVERY: "active",
  DELIVERED: "ok", CANCELLED: "void", PENDING: "warn", COMPLETED: "ok", FAILED: "active", REFUNDED: "void",
  AVAILABLE: "ok", ASSIGNED: "ink", OFFLINE: "void", PICKED_UP: "active", IN_TRANSIT: "active", SENT: "ok",
  UP: "ok", DOWN: "active", ACCEPTING: "ok", PAUSED: "void", OPEN: "ok", CLOSED: "void",
};
function stamp(status, size = "") {
  const tone = STAMP_TONE[status] || "ink";
  return `<span class="stamp stamp-${tone} ${size === "lg" ? "stamp-lg" : ""}">${esc(String(status).replaceAll("_", " "))}</span>`;
}

function icons() {
  if (window.lucide) window.lucide.createIcons({ attrs: { "stroke-width": 1.75 } });
}

/* ---------- session: remembers the IDs you were working with, like the CLI session ---------- */

const session = (() => {
  let data = {};
  try { data = JSON.parse(localStorage.getItem("fd-session") || "{}"); } catch { /* storage unavailable */ }
  return {
    get: (k) => data[k],
    set(k, v) {
      data[k] = v;
      try { localStorage.setItem("fd-session", JSON.stringify(data)); } catch { /* ignore */ }
    },
  };
})();

/* ---------- API ---------- */

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/**
 * Finds the console server. Normally that is this page's own origin; when the page was
 * opened some other way (file://, Live Server) it falls back to the frontend container on port 3000.
 */
const CONSOLE_FALLBACK = "http://localhost:3000";
const apiBase = (async () => {
  for (const base of ["", CONSOLE_FALLBACK]) {
    try {
      const r = await fetch(`${base}/api/console`, { cache: "no-store" });
      if (r.ok && (await r.json()).console === "food-delivery") return base;
    } catch { /* try the next candidate */ }
  }
  return null;
})();

async function api(method, path, body) {
  const base = await apiBase;
  if (base === null) {
    throw new ApiError(0, `The console can't reach the platform. Start the stack (docker compose up -d in infra/docker) and open ${CONSOLE_FALLBACK}.`);
  }
  let res;
  try {
    res = await fetch(`${base}/api${path}`, {
      method,
      headers: body === undefined ? { Accept: "application/json" } : { "Content-Type": "application/json", Accept: "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, `Lost contact with the platform at ${base || location.origin}. Check that the Docker stack is still running.`);
  }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { message: text }; }
  if (!res.ok) throw new ApiError(res.status, (data && data.message) || `${res.status} ${res.statusText}`);
  return data;
}
const GET = (p) => api("GET", p);
const POST = (p, b) => api("POST", p, b ?? {});
const PUT = (p, b) => api("PUT", p, b);

/** Settles every request so one unreachable service only blanks its own part of the page. */
async function settle(map) {
  const keys = Object.keys(map);
  const results = await Promise.allSettled(keys.map((k) => map[k]));
  const out = {};
  keys.forEach((k, i) => { out[k] = results[i].status === "fulfilled" ? { ok: true, data: results[i].value } : { ok: false, error: results[i].reason }; });
  return out;
}

/* ---------- health ---------- */

const health = {};
async function checkHealth() {
  await Promise.all(SERVICES.map(async (s) => {
    if (!health[s.service]) health[s.service] = { state: "checking" };
    const started = performance.now();
    try {
      await GET(`${s.base}/health`);
      health[s.service] = { state: "up", ms: Math.round(performance.now() - started), at: new Date() };
    } catch (e) {
      health[s.service] = { state: "down", error: e.message, at: new Date() };
    }
  }));
  paintHealth();
}

function paintHealth() {
  $$("[data-lamp]").forEach((el) => { el.dataset.state = health[el.dataset.lamp]?.state || "checking"; });
  const up = SERVICES.filter((s) => health[s.service]?.state === "up").length;
  const down = SERVICES.filter((s) => health[s.service]?.state === "down");
  const box = $("#rail-health");
  if (box) {
    box.innerHTML = `<div class="flex items-center gap-2"><span class="num text-paper-white">${up}/${SERVICES.length}</span> services up</div>` +
      (down.length ? `<div class="mt-1 text-[#ffb1a8]">Down: ${down.map((s) => esc(s.label)).join(", ")}</div>` : "");
  }
  const board = $("#service-board");
  if (board) board.innerHTML = serviceBoardRows();
  icons();
}

/* ---------- rail ---------- */

function paintRail(active) {
  $("#rail-nav").innerHTML = SECTIONS.map((s) => `
    <a href="#/${s.route}" class="rail-link" ${s.route === active ? 'aria-current="page"' : ""}>
      <i data-lucide="${s.icon}" class="w-[18px] h-[18px]"></i>
      <span>${s.label}</span>
      <span class="port num">${s.port ?? ""}</span>
      ${s.service ? `<span class="lamp" data-lamp="${s.service}" data-state="${health[s.service]?.state || "checking"}" role="img" aria-label="${s.label} service ${health[s.service]?.state || "checking"}"></span>` : "<span></span>"}
    </a>`).join("");
}

$("#rail-toggle").addEventListener("click", (e) => {
  const aside = e.currentTarget.closest("aside");
  const open = aside.classList.toggle("rail-open");
  e.currentTarget.setAttribute("aria-expanded", String(open));
});

/* ---------- toasts ---------- */

function toast(message, kind = "success") {
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.setAttribute("role", kind === "error" ? "alert" : "status");
  el.innerHTML = `<i data-lucide="${kind === "error" ? "circle-alert" : "circle-check"}"></i><div>${esc(message)}</div>`;
  $("#toasts").append(el);
  icons();
  setTimeout(() => { el.classList.add("is-leaving"); el.addEventListener("animationend", () => el.remove()); }, kind === "error" ? 7000 : 3800);
}

/* ---------- form sheet ---------- */

let sheetState = null;

function openSheet({ title, tint = "white", submitLabel, body, onMount, onSubmit }) {
  const sheet = $("#sheet");
  sheetState = { onSubmit, returnFocus: document.activeElement };
  $("#sheet-title").textContent = title;
  $("#sheet-body").innerHTML = body;
  $("#sheet-submit").textContent = submitLabel;
  $("#sheet-submit").disabled = false;
  $("#sheet-error").hidden = true;
  sheet.style.setProperty("--sheet-tint", tint === "ink" ? "var(--paper-deep)" : `var(--copy-${tint})`);
  sheet.hidden = false;
  sheet.classList.remove("is-closing");
  $("#sheet-backdrop").hidden = false;
  document.body.style.overflow = "hidden";
  icons();
  onMount?.($("#sheet-form"));
  const first = $("#sheet-body").querySelector("input:not([type=hidden]):not([disabled]), select, textarea");
  (first || $("#sheet-submit")).focus();
}

function closeSheet() {
  const sheet = $("#sheet");
  if (sheet.hidden) return;
  sheet.classList.add("is-closing");
  $("#sheet-backdrop").hidden = true;
  document.body.style.overflow = "";
  setTimeout(() => { sheet.hidden = true; sheet.classList.remove("is-closing"); }, 190);
  sheetState?.returnFocus?.focus?.();
  sheetState = null;
}

function sheetError(message) {
  const box = $("#sheet-error");
  box.textContent = message;
  box.hidden = false;
  box.scrollIntoView({ block: "nearest" });
}

$("#sheet-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!sheetState) return;
  const form = e.currentTarget;
  $("#sheet-error").hidden = true;
  const missing = $$("[required]", form).filter((f) => !String(f.value).trim());
  $$("[aria-invalid]", form).forEach((f) => f.removeAttribute("aria-invalid"));
  if (missing.length) {
    missing.forEach((f) => f.setAttribute("aria-invalid", "true"));
    const names = missing.map((f) => $(`label[for="${f.id}"]`, form)?.textContent.replace("*", "").trim() || f.name);
    sheetError(`Fill in ${names.join(", ")}.`);
    missing[0].focus();
    return;
  }
  const btn = $("#sheet-submit");
  btn.setAttribute("aria-busy", "true");
  btn.disabled = true;
  try {
    const data = Object.fromEntries(new FormData(form));
    const message = await sheetState.onSubmit(data, form);
    closeSheet();
    if (message) toast(message);
    rerender();
  } catch (err) {
    sheetError(err instanceof ApiError ? err.message : String(err.message || err));
  } finally {
    btn.removeAttribute("aria-busy");
    btn.disabled = false;
  }
});
$$("[data-close]").forEach((b) => b.addEventListener("click", closeSheet));
$("#sheet-backdrop").addEventListener("click", closeSheet);
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !$("#sheet").hidden) closeSheet();
  if (e.key === "Tab" && !$("#sheet").hidden) {
    const focusables = $$("#sheet button, #sheet input, #sheet select, #sheet textarea, #sheet a[href]").filter((el) => !el.disabled && el.offsetParent !== null);
    const first = focusables[0], last = focusables[focusables.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }
});

/* Field builders */
function field({ id, label, type = "text", value = "", required = false, hint = "", attrs = "", placeholder = "" }) {
  return `<div>
    <label class="field-label" for="${id}">${esc(label)}${required ? ' <span class="text-ink-500" aria-hidden="true">*</span>' : ""}</label>
    ${type === "textarea"
      ? `<textarea class="field" id="${id}" name="${id}" ${required ? "required" : ""} placeholder="${esc(placeholder)}" ${attrs}>${esc(value)}</textarea>`
      : `<input class="field ${type === "number" ? "num" : ""}" id="${id}" name="${id}" type="${type}" value="${esc(value)}" ${required ? "required" : ""} placeholder="${esc(placeholder)}" ${attrs}>`}
    ${hint ? `<p class="field-hint">${hint}</p>` : ""}
  </div>`;
}
function select({ id, label, options, value = "", required = false, hint = "", placeholder = "Choose…", attrs = "" }) {
  return `<div>
    <label class="field-label" for="${id}">${esc(label)}${required ? ' <span class="text-ink-500" aria-hidden="true">*</span>' : ""}</label>
    <select class="field" id="${id}" name="${id}" ${required ? "required" : ""} ${attrs}>
      ${placeholder !== null ? `<option value="">${esc(placeholder)}</option>` : ""}
      ${options.map((o) => `<option value="${esc(o.value)}" ${String(o.value) === String(value) ? "selected" : ""} ${o.disabled ? "disabled" : ""}>${esc(o.label)}</option>`).join("")}
    </select>
    ${hint ? `<p class="field-hint">${hint}</p>` : ""}
  </div>`;
}
function checkbox({ id, label, checked = true }) {
  return `<label class="flex items-center gap-3 text-sm font-medium"><input type="checkbox" class="check" id="${id}" name="${id}" ${checked ? "checked" : ""}> ${esc(label)}</label>`;
}

/* ---------- sortable ledger table ---------- */

const tables = new Map();

function ledger(id, { columns, rows, href, empty, sort, selected }) {
  tables.set(id, { columns, rows, href, empty, sort: sort || null, selected });
  return `<div class="ledger-wrap" id="${id}">${ledgerInner(id)}</div>`;
}

function ledgerInner(id) {
  const t = tables.get(id);
  if (!t.rows.length) return `<div class="empty"><h3>${esc(t.empty?.title || "Nothing here yet")}</h3><p class="text-sm">${t.empty?.body || ""}</p></div>`;
  let rows = [...t.rows];
  if (t.sort) {
    const col = t.columns.find((c) => c.key === t.sort.key);
    // A table may sort by a field it doesn't show (compact layouts keep "newest first").
    const val = col ? col.sort || ((r) => r[col.key]) : (r) => r[t.sort.key];
    rows.sort((a, b) => {
      const x = val(a), y = val(b);
      const cmp = typeof x === "number" && typeof y === "number" ? x - y : String(x ?? "").localeCompare(String(y ?? ""), undefined, { numeric: true });
      return t.sort.dir === "asc" ? cmp : -cmp;
    });
  }
  const head = t.columns.map((c) => {
    const isSorted = t.sort?.key === c.key;
    const aria = isSorted ? `aria-sort="${t.sort.dir === "asc" ? "ascending" : "descending"}"` : "";
    const inner = c.sortable === false ? `<span>${esc(c.label)}</span>`
      : `<button type="button" data-action="sort" data-table="${id}" data-key="${c.key}">${esc(c.label)}<i data-lucide="${isSorted ? (t.sort.dir === "asc" ? "arrow-up" : "arrow-down") : "arrow-up-down"}" class="${isSorted ? "" : "opacity-30"}"></i></button>`;
    return `<th scope="col" class="${c.align === "right" ? "r" : ""}" ${aria}>${inner}</th>`;
  }).join("");
  const body = rows.map((r) => {
    const link = t.href ? t.href(r) : null;
    const sel = t.selected?.(r);
    return `<tr class="${link ? "is-link" : ""} ${sel ? "is-selected" : ""}" ${link ? `data-href="${esc(link)}"` : ""} ${sel ? 'aria-current="true"' : ""}>${t.columns.map((c) => `<td class="${c.align === "right" ? "r" : ""}">${c.render ? c.render(r) : esc(r[c.key])}</td>`).join("")}</tr>`;
  }).join("");
  return `<table class="ledger"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

/* ---------- page scaffolding ---------- */

function pageHead({ title, sub = "", actions = "", back = "" }) {
  return `<header class="mb-7">
    ${back ? `<a href="${back.href}" class="inline-flex items-center gap-1.5 text-sm font-semibold text-ink-700 hover:text-ink mb-4 focus-ring rounded"><i data-lucide="arrow-left" class="w-4 h-4"></i>${esc(back.label)}</a>` : ""}
    <div class="flex flex-wrap items-end justify-between gap-4 pb-4 rule-b">
      <div class="min-w-0">
        <h1 class="heading text-[34px] sm:text-[42px]">${title}</h1>
        ${sub ? `<p class="mt-2 text-sm text-ink-700">${sub}</p>` : ""}
      </div>
      <div class="flex flex-wrap gap-2">${actions}</div>
    </div>
  </header>`;
}

function offline(what, err) {
  return `<div class="offline flex gap-3"><i data-lucide="plug-zap" class="w-5 h-5 shrink-0"></i><div><strong>${esc(what)} is unavailable.</strong> <span>${esc(err?.message || "")}</span></div></div>`;
}

function skeleton() {
  return `<div class="view-enter" aria-busy="true" aria-label="Loading">
    <div class="skeleton h-10 w-64 mb-3"></div><div class="skeleton h-4 w-96 max-w-full mb-8"></div>
    ${Array.from({ length: 6 }, () => '<div class="skeleton h-11 w-full mb-2"></div>').join("")}
  </div>`;
}

/* ---------- router ---------- */

let renderToken = 0;
let pollTimer = null;
let current = { section: "", id: "", query: new URLSearchParams() };

function parseHash() {
  const raw = location.hash.replace(/^#\/?/, "");
  const [path, qs = ""] = raw.split("?");
  const [section = "", id = ""] = path.split("/").map(decodeURIComponent);
  return { section, id, query: new URLSearchParams(qs) };
}

const isWide = () => window.matchMedia("(min-width: 1400px)").matches;
const isNarrow = () => window.matchMedia("(max-width: 640px)").matches;

async function route() {
  const prev = current;
  current = parseHash();
  if (prev.section === current.section && prev.id === current.id && current.section === "orders" && !current.query.get("new")) {
    clearInterval(pollTimer);
    await render({ quiet: true });
    return;
  }
  clearInterval(pollTimer);
  const known = SECTIONS.some((s) => s.route === current.section);
  if (!known) { location.hash = "#/"; return; }
  paintRail(current.section);
  $("aside").classList.remove("rail-open");
  $("#rail-toggle").setAttribute("aria-expanded", "false");
  const label = SECTIONS.find((s) => s.route === current.section).label;
  document.title = `${label} · Food Delivery Console`;
  $("#view").innerHTML = skeleton();
  icons();
  await render();
  $("#view").focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

async function render({ quiet = false } = {}) {
  const token = ++renderToken;
  const view = VIEWS[current.section] || VIEWS[""];
  try {
    const html = await view(current.id, current.query);
    if (token !== renderToken) return;
    const scroll = window.scrollY;
    $("#view").innerHTML = `<div class="${quiet ? "" : "view-enter"}">${html}</div>`;
    if (quiet) window.scrollTo(0, scroll);
    icons();
    paintHealth();
    afterRender[current.section]?.();
  } catch (err) {
    if (token !== renderToken) return;
    $("#view").innerHTML = pageHead({ title: "Something went wrong" }) + offline("This page", err);
    icons();
  }
}
const rerender = () => render({ quiet: true });
const afterRender = {};

window.addEventListener("hashchange", route);

/* ---------- global actions (event delegation) ---------- */

const ACTIONS = {};
document.addEventListener("click", async (e) => {
  const actionEl = e.target.closest("[data-action]");
  if (actionEl) {
    e.preventDefault();
    const fn = ACTIONS[actionEl.dataset.action];
    if (!fn) return;
    if (actionEl.tagName === "BUTTON" && actionEl.dataset.busy !== "off") { actionEl.setAttribute("aria-busy", "true"); actionEl.disabled = true; }
    try { await fn(actionEl.dataset, actionEl); }
    catch (err) { toast(err.message || String(err), "error"); }
    finally { if (actionEl.isConnected) { actionEl.removeAttribute("aria-busy"); actionEl.disabled = false; } }
    return;
  }
  const row = e.target.closest("tr[data-href]");
  if (row && !e.target.closest("a, button, input, select")) location.hash = row.dataset.href;
});

ACTIONS.copy = async ({ value }) => {
  try { await navigator.clipboard.writeText(value); toast(`Copied ${value}`); }
  catch { toast("Copy is blocked in this browser; select the ID instead.", "error"); }
};
ACTIONS.sort = ({ table, key }) => {
  const t = tables.get(table);
  t.sort = t.sort?.key === key ? { key, dir: t.sort.dir === "asc" ? "desc" : "asc" } : { key, dir: "asc" };
  $(`#${table}`).innerHTML = ledgerInner(table);
  icons();
};
ACTIONS.refresh = () => rerender();
ACTIONS.recheck = () => checkHealth();

/* ---------- shared lookups ---------- */

async function directory() {
  const r = await settle({
    customers: GET("/customers"),
    restaurants: GET("/restaurants"),
    drivers: GET("/delivery/drivers"),
  });
  const byId = (res, key) => Object.fromEntries((res.ok ? res.data : []).map((x) => [x[key], x]));
  return {
    raw: r,
    customers: r.customers.ok ? r.customers.data : [],
    restaurants: r.restaurants.ok ? r.restaurants.data : [],
    drivers: r.drivers.ok ? r.drivers.data : [],
    customer: byId(r.customers, "customerId"),
    restaurant: byId(r.restaurants, "restaurantId"),
    driver: byId(r.drivers, "driverId"),
  };
}

function orderCell(o, dir, href) {
  const r = dir.restaurant[o.restaurantId], c = dir.customer[o.customerId];
  const idHtml = href ? `<a class="id row-link rounded hover:underline" title="${esc(o.orderId)}" href="${esc(href)}">${esc(shortId(o.orderId))}</a>` : orderLink(o.orderId);
  return `${idHtml}<div class="text-[13px] mt-0.5 leading-snug">${r ? esc(r.name) : "—"} <span class="text-ink-500">→ ${c ? esc(c.fullName) : "—"}</span></div>`;
}

const nameOr = (obj, key, id) => (obj ? esc(obj[key]) : `<span class="id">${esc(id)}</span>`);

/* ===========================================================================
 * Views
 * ========================================================================= */

const VIEWS = {};

/* ---------- Overview ---------- */

function serviceBoardRows() {
  return SERVICES.map((s) => {
    const h = health[s.service] || { state: "checking" };
    const status = h.state === "up" ? stamp("UP") : h.state === "down" ? stamp("DOWN") : `<span class="text-xs text-ink-500">checking…</span>`;
    return `<div class="svc">
      <span class="swatch ${s.tint === "ink" ? "bg-ink" : s.route === "orders" ? "swatch-waybill" : `tint-${s.tint}`}"></span>
      <div class="min-w-0">
        <a href="#/${s.route}" class="font-semibold hover:underline focus-ring rounded">${s.label}</a>
        <div class="text-xs text-ink-500 num truncate">:${s.port}${s.base}${h.state === "up" ? ` · ${h.ms} ms` : ""}</div>
        ${h.state === "down" ? `<div class="text-xs text-perf-dark mt-0.5">${esc(h.error)}</div>` : ""}
      </div>
      ${status}
    </div>`;
  }).join("");
}

VIEWS[""] = async () => {
  const r = await settle({ orders: GET("/orders"), dir: directory() });
  const dir = r.dir.ok ? r.dir.data : { customer: {}, restaurant: {}, restaurants: [], drivers: [], raw: {} };
  const orders = r.orders.ok ? [...r.orders.data].sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt))) : [];
  const live = orders.filter((o) => !["DELIVERED", "CANCELLED"].includes(o.status));

  const all = r.orders.ok ? r.orders.data : [];
  const delivered = all.filter((o) => o.status === "DELIVERED");
  const tally = r.orders.ok ? `<div class="tally sheet-paper overflow-hidden">
      ${[["Delivered revenue", money(delivered.reduce((n, o) => n + Number(o.totalAmount), 0))], ["Orders", all.length], ["In motion", live.length], ["Delivered", delivered.length],
         ["Cancelled", all.filter((o) => o.status === "CANCELLED").length], ["Restaurants", r.dir.ok && dir.raw.restaurants.ok ? dir.restaurants.length : "—"],
         ["Drivers available", r.dir.ok && dir.raw.drivers.ok ? `${dir.drivers.filter((d) => d.status === "AVAILABLE").length}/${dir.drivers.length}` : "—"]]
        .map(([k, v]) => `<div><div class="label">${k}</div><div class="v">${v}</div></div>`).join("")}
    </div>` : offline("Order service", r.orders.error);

  return pageHead({
    title: "Platform overview",
    sub: "Seven services, one data owner each, coordinated through Kafka. Everything here comes from their HTTP APIs.",
    actions: `<button class="btn" data-action="recheck"><i data-lucide="activity"></i>Re-check health</button><a href="#/orders?new=1" class="btn btn-ink"><i data-lucide="plus"></i>Place order</a>`,
  }) + `
  <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_380px] gap-8 items-start">
    <div class="space-y-9 min-w-0">
      <section aria-labelledby="t-summary">
        <div class="flex flex-wrap items-baseline justify-between gap-2 mb-3"><h2 id="t-summary" class="heading text-xl">Live counts</h2><p class="text-xs text-ink-700">Counted from the order, restaurant and delivery services. Saved report figures are under <a class="underline" href="#/reports">Reports</a>.</p></div>
        ${tally}
      </section>
      <section aria-labelledby="t-live">
        <div class="flex items-end justify-between mb-2">
          <h2 id="t-live" class="heading text-xl">Orders in motion <span class="num text-base text-ink-500 font-medium normal-case">${live.length}</span></h2>
          <a href="#/orders" class="text-sm font-semibold hover:underline focus-ring rounded">All orders</a>
        </div>
        ${r.orders.ok ? ledger("t-overview-orders", {
          rows: live.slice(0, 8),
          href: (o) => `#/orders/${encodeURIComponent(o.orderId)}`,
          empty: { title: "No orders in motion", body: `Every order is delivered or cancelled. <a class="underline" href="#/orders?new=1">Place an order</a> to start one.` },
          columns: [
            { key: "orderId", label: "Order", render: (o) => orderCell(o, dir) },
            { key: "status", label: "Status", sort: (o) => ORDER_FLOW.indexOf(o.status), render: (o) => stamp(o.status) },
            { key: "totalAmount", label: "Total", align: "right", sort: (o) => Number(o.totalAmount), render: (o) => `<span class="num">${money(o.totalAmount)}</span>` },
          ],
        }) : offline("Order service", r.orders.error)}
      </section>
    </div>
    <aside class="space-y-9">
      <section aria-labelledby="t-services">
        <h2 id="t-services" class="heading text-xl mb-3">Services</h2>
        <div class="sheet-paper" id="service-board" aria-live="polite">${serviceBoardRows()}</div>
      </section>
      <section aria-labelledby="t-flow">
        <h2 id="t-flow" class="heading text-xl mb-3">How an order moves</h2>
        <ol class="text-sm space-y-0 sheet-paper">
          ${[["white", "Order placed", "orders.created"], ["pink", "Pending payment created, then completed", "payments.completed"], ["white", "Order confirmed", "orders.confirmed"],
             ["canary", "Kitchen prepares, marks ready", "orders.ready"], ["blue", "Driver assigned, delivers", "delivery.assigned → delivery.completed"], ["green", "Customer notified at each step", "lifecycle events"]]
            .map(([t, what, topic]) => `<li class="grid grid-cols-[10px_minmax(0,1fr)] gap-3 px-4 py-3 border-b border-dashed border-ink-200 last:border-0"><span class="swatch !h-full min-h-[34px] tint-${t}"></span><div><div class="font-semibold">${what}</div><div class="num text-xs text-ink-500 mt-0.5">${topic}</div></div></li>`).join("")}
        </ol>
      </section>
    </aside>
  </div>`;
};

/* ---------- Customers ---------- */

VIEWS.customers = async (id) => (id ? customerDetail(id) : customerList());

async function customerList() {
  const [customers, orders] = await Promise.all([GET("/customers"), GET("/orders").catch(() => null)]);
  const orderCount = {};
  (orders || []).forEach((o) => { orderCount[o.customerId] = (orderCount[o.customerId] || 0) + 1; });
  return pageHead({
    title: "Customers",
    sub: `<span class="num">${customers.length}</span> registered · customer service :8082`,
    actions: `<button class="btn btn-ink" data-action="newCustomer"><i data-lucide="user-plus"></i>Register customer</button>`,
  }) + ledger("t-customers", {
    rows: customers,
    href: (c) => `#/customers/${encodeURIComponent(c.customerId)}`,
    sort: { key: "fullName", dir: "asc" },
    empty: { title: "No customers yet", body: "Register the first customer to start placing orders." },
    columns: [
      { key: "fullName", label: "Name", render: (c) => `<a class="font-semibold hover:underline row-link rounded" href="#/customers/${encodeURIComponent(c.customerId)}">${esc(c.fullName)}</a>` },
      { key: "email", label: "Email" },
      { key: "phoneNumber", label: "Phone", render: (c) => `<span class="num text-[13px]">${esc(c.phoneNumber)}</span>` },
      { key: "addresses", label: "Addresses", align: "right", sort: (c) => c.addresses.length, render: (c) => `<span class="num">${c.addresses.length}</span>` },
      { key: "orders", label: "Orders", align: "right", sort: (c) => orderCount[c.customerId] || 0, render: (c) => `<span class="num">${orderCount[c.customerId] || 0}</span>` },
      { key: "customerId", label: "ID", render: (c) => idCell(c.customerId) },
    ],
  });
}

async function customerDetail(id) {
  const r = await settle({ customer: GET(`/customers/${encodeURIComponent(id)}`), orders: GET(`/orders?customerId=${encodeURIComponent(id)}`), dir: directory() });
  if (!r.customer.ok) return pageHead({ title: "Customer", back: { href: "#/customers", label: "Customers" } }) + offline("This customer", r.customer.error);
  const c = r.customer.data;
  session.set("customerId", c.customerId);
  const orders = r.orders.ok ? r.orders.data : [];
  const known = new Set(c.historicalOrderIds);
  const restaurant = r.dir.ok ? r.dir.data.restaurant : {};
  const unrecorded = orders.filter((o) => !known.has(o.orderId));

  return pageHead({
    title: esc(c.fullName),
    sub: `${idCell(c.customerId)}`,
    back: { href: "#/customers", label: "Customers" },
    actions: `<button class="btn" data-action="editCustomer" data-id="${esc(c.customerId)}"><i data-lucide="pencil"></i>Edit profile</button>
      <a class="btn btn-ink" href="#/orders?new=1&customer=${encodeURIComponent(c.customerId)}"><i data-lucide="plus"></i>Place order</a>`,
  }) + `
  <div class="grid grid-cols-1 lg:grid-cols-[320px_minmax(0,1fr)] gap-8 items-start">
    <section class="sheet-paper p-5 space-y-4" aria-label="Contact">
      <div><div class="label">Email</div><div class="mt-1 break-all">${esc(c.email)}</div></div>
      <div><div class="label">Phone</div><div class="mt-1 num text-sm">${esc(c.phoneNumber)}</div></div>
      <div class="rule-dashed pt-4"><div class="label">Recorded orders</div><div class="mt-1 num text-2xl">${c.historicalOrderIds.length}</div></div>
      <a class="text-sm font-semibold hover:underline inline-flex items-center gap-1.5" href="#/notifications?recipient=${encodeURIComponent(c.customerId)}"><i data-lucide="bell" class="w-4 h-4"></i>Notifications for this customer</a>
    </section>
    <div class="space-y-9 min-w-0">
      <section>
        <div class="flex items-end justify-between mb-2"><h2 class="heading text-xl">Delivery addresses</h2>
          <button class="btn btn-sm" data-action="addAddress" data-id="${esc(c.customerId)}"><i data-lucide="map-pin-plus"></i>Add address</button></div>
        ${ledger("t-addresses", {
          rows: c.addresses,
          empty: { title: "No delivery address", body: "Orders need one. Add the customer's first address." },
          columns: [
            { key: "label", label: "Label", render: (a) => `<span class="font-semibold">${esc(a.label)}</span>` },
            { key: "street", label: "Street" },
            { key: "city", label: "City" },
            { key: "deliveryInstructions", label: "Instructions", render: (a) => esc(a.deliveryInstructions || "—") },
            { key: "addressId", label: "ID", render: (a) => idCell(a.addressId) },
          ],
        })}
      </section>
      <section>
        <div class="flex items-end justify-between mb-2"><h2 class="heading text-xl">Orders</h2>
          ${unrecorded.length ? `<span class="text-xs text-ink-500">${unrecorded.length} not yet in profile history</span>` : ""}</div>
        ${r.orders.ok ? ledger("t-customer-orders", {
          rows: orders,
          href: (o) => `#/orders/${encodeURIComponent(o.orderId)}`,
          sort: { key: "createdAt", dir: "desc" },
          empty: { title: "No orders yet", body: `<a class="underline" href="#/orders?new=1&customer=${encodeURIComponent(c.customerId)}">Place this customer's first order.</a>` },
          columns: [
            { key: "orderId", label: "Order", render: (o) => orderLink(o.orderId) },
            { key: "restaurantId", label: "Restaurant", render: (o) => nameOr(restaurant[o.restaurantId], "name", o.restaurantId) },
            { key: "totalAmount", label: "Total", align: "right", sort: (o) => Number(o.totalAmount), render: (o) => `<span class="num">${money(o.totalAmount)}</span>` },
            { key: "status", label: "Status", render: (o) => stamp(o.status) },
            { key: "createdAt", label: "Placed", render: (o) => `<span class="num text-[13px]">${when(o.createdAt)}</span>` },
            { key: "history", label: "History", sortable: false, render: (o) => known.has(o.orderId) ? `<span class="text-xs text-ok font-semibold">Recorded</span>`
              : `<button class="btn btn-sm" data-action="recordHistory" data-customer="${esc(c.customerId)}" data-order="${esc(o.orderId)}">Record</button>` },
          ],
        }) : offline("Order service", r.orders.error)}
      </section>
    </div>
  </div>`;
}

function customerFields(c = {}) {
  return field({ id: "fullName", label: "Full name", value: c.fullName, required: true, attrs: 'autocomplete="off"' }) +
    field({ id: "email", label: "Email", type: "email", value: c.email, required: true, attrs: 'autocomplete="off"' }) +
    field({ id: "phoneNumber", label: "Phone number", type: "tel", value: c.phoneNumber, required: true, placeholder: "+264 81 000 0000" });
}

ACTIONS.newCustomer = () => openSheet({
  title: "Register customer", submitLabel: "Register customer", tint: "white",
  body: customerFields(),
  async onSubmit(d) {
    const customer = await POST("/customers", { customerId: uid("customer"), fullName: d.fullName.trim(), email: d.email.trim(), phoneNumber: d.phoneNumber.trim(), addresses: [], historicalOrderIds: [] });
    session.set("customerId", customer.customerId);
    location.hash = `#/customers/${encodeURIComponent(customer.customerId)}`;
    return `${customer.fullName} registered`;
  },
});

ACTIONS.editCustomer = async ({ id }) => {
  const c = await GET(`/customers/${encodeURIComponent(id)}`);
  openSheet({
    title: "Edit profile", submitLabel: "Save profile", tint: "white",
    body: customerFields(c),
    async onSubmit(d) {
      await PUT(`/customers/${encodeURIComponent(id)}`, { fullName: d.fullName.trim(), email: d.email.trim(), phoneNumber: d.phoneNumber.trim() });
      return "Profile saved";
    },
  });
};

ACTIONS.addAddress = ({ id }) => openSheet({
  title: "Add delivery address", submitLabel: "Add address", tint: "white",
  body: field({ id: "label", label: "Label", required: true, placeholder: "Home, Work…" }) +
    field({ id: "street", label: "Street", required: true }) +
    field({ id: "city", label: "City", required: true, value: "Windhoek" }) +
    field({ id: "deliveryInstructions", label: "Delivery instructions", type: "textarea", placeholder: "Optional: gate code, landmarks" }),
  async onSubmit(d) {
    await POST(`/customers/${encodeURIComponent(id)}/addresses`, {
      addressId: uid("address"), label: d.label.trim(), street: d.street.trim(), city: d.city.trim(),
      deliveryInstructions: d.deliveryInstructions.trim() || null,
    });
    return "Address added";
  },
});

ACTIONS.recordHistory = async ({ customer, order }) => {
  await POST(`/customers/${encodeURIComponent(customer)}/orders/${encodeURIComponent(order)}`);
  toast("Order recorded in customer history");
  await rerender();
};

/* ---------- Restaurants ---------- */

VIEWS.restaurants = async (id) => (id ? restaurantDetail(id) : restaurantList());

async function restaurantList() {
  const restaurants = await GET("/restaurants");
  return pageHead({
    title: "Restaurants",
    sub: `<span class="num">${restaurants.length}</span> registered · restaurant service :8087`,
    actions: `<button class="btn btn-ink" data-action="newRestaurant"><i data-lucide="store"></i>Register restaurant</button>`,
  }) + ledger("t-restaurants", {
    rows: restaurants,
    href: (x) => `#/restaurants/${encodeURIComponent(x.restaurantId)}`,
    sort: { key: "name", dir: "asc" },
    empty: { title: "No restaurants yet", body: "Register a restaurant, then add its menu." },
    columns: [
      { key: "name", label: "Name", render: (x) => `<a class="font-semibold hover:underline row-link rounded" href="#/restaurants/${encodeURIComponent(x.restaurantId)}">${esc(x.name)}</a>` },
      { key: "address", label: "Address" },
      { key: "menu", label: "Menu items", align: "right", sort: (x) => x.menu.length, render: (x) => `<span class="num">${x.menu.length}</span>` },
      { key: "stock", label: "In stock", align: "right", sort: (x) => x.menu.filter((m) => m.available && m.availableQuantity > 0).length, render: (x) => `<span class="num">${x.menu.filter((m) => m.available && m.availableQuantity > 0).length}</span>` },
      { key: "acceptingOrders", label: "Orders", render: (x) => stamp(x.acceptingOrders ? "ACCEPTING" : "PAUSED") },
      { key: "restaurantId", label: "ID", render: (x) => idCell(x.restaurantId) },
    ],
  });
}

async function restaurantDetail(id) {
  const x = await GET(`/restaurants/${encodeURIComponent(id)}`);
  session.set("restaurantId", x.restaurantId);
  const hours = DAYS.map((d) => x.openingHours.find((h) => h.dayOfWeek.toUpperCase() === d)).filter(Boolean);
  return pageHead({
    title: esc(x.name),
    sub: `${esc(x.address)} · ${idCell(x.restaurantId)}`,
    back: { href: "#/restaurants", label: "Restaurants" },
    actions: `${stamp(x.acceptingOrders ? "ACCEPTING" : "PAUSED", "lg")}
      <a class="btn" href="#/orders?restaurant=${encodeURIComponent(x.restaurantId)}"><i data-lucide="receipt-text"></i>Orders</a>
      <button class="btn btn-ink" data-action="addMenuItem" data-id="${esc(x.restaurantId)}"><i data-lucide="plus"></i>Add menu item</button>`,
  }) + `
  <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_300px] gap-8 items-start">
    <section class="min-w-0">
      <h2 class="heading text-xl mb-2">Menu</h2>
      ${ledger("t-menu", {
        rows: x.menu,
        sort: { key: "name", dir: "asc" },
        empty: { title: "The menu is empty", body: "Add items so customers can order." },
        columns: [
          { key: "name", label: "Item", render: (m) => `<div class="font-semibold">${esc(m.name)}</div><div class="text-xs text-ink-500 mt-0.5 max-w-[46ch]">${esc(m.description)}</div>` },
          { key: "price", label: "Price", align: "right", sort: (m) => Number(m.price), render: (m) => `<span class="num">${money(m.price)}</span>` },
          { key: "availableQuantity", label: "Stock", align: "right", render: (m) => `<span class="num ${m.availableQuantity === 0 ? "text-perf" : ""}">${m.availableQuantity}</span>` },
          { key: "available", label: "Status", render: (m) => stamp(m.available && m.availableQuantity > 0 ? "OPEN" : "CLOSED") },
          { key: "edit", label: "", sortable: false, align: "right", render: (m) => `<button class="btn btn-sm" data-action="editStock" data-restaurant="${esc(x.restaurantId)}" data-item="${esc(m.menuItemId)}" data-name="${esc(m.name)}" data-qty="${m.availableQuantity}"><i data-lucide="package"></i>Stock</button>` },
        ],
      })}
    </section>
    <section class="sheet-paper tint-canary p-5">
      <h2 class="heading text-lg mb-3">Opening hours</h2>
      ${hours.length ? `<dl class="text-sm">${hours.map((h) => `<div class="flex justify-between py-1.5 border-b border-dashed border-ink/25 last:border-0"><dt class="font-semibold capitalize">${esc(h.dayOfWeek.toLowerCase())}</dt><dd class="num text-[13px]">${h.closed ? "Closed" : `${esc(h.opensAt)}–${esc(h.closesAt)}`}</dd></div>`).join("")}</dl>`
        : `<p class="text-sm text-ink-700">No opening hours on record.</p>`}
    </section>
  </div>`;
}

ACTIONS.newRestaurant = () => openSheet({
  title: "Register restaurant", submitLabel: "Register restaurant", tint: "canary",
  body: field({ id: "name", label: "Restaurant name", required: true }) +
    field({ id: "address", label: "Address", required: true, placeholder: "Street, city" }) +
    checkbox({ id: "acceptingOrders", label: "Accepting orders" }) +
    `<fieldset class="fieldset-rule">
      <legend class="field-label">Opening hours</legend>
      <p class="field-hint -mt-1 mb-3">Optional. Untick a day to record it as closed.</p>
      <div class="space-y-2">${DAYS.map((d) => `<div class="grid grid-cols-[110px_1fr_1fr] gap-2 items-center">
        <label class="flex items-center gap-2 text-sm capitalize"><input type="checkbox" class="check" name="open_${d}" checked>${d.toLowerCase()}</label>
        <input class="field num" type="time" name="opens_${d}" value="09:00" aria-label="${d.toLowerCase()} opens">
        <input class="field num" type="time" name="closes_${d}" value="21:00" aria-label="${d.toLowerCase()} closes">
      </div>`).join("")}</div>
      <label class="flex items-center gap-2 text-sm mt-3"><input type="checkbox" class="check" name="includeHours" checked> Save these opening hours</label>
    </fieldset>`,
  async onSubmit(d) {
    const openingHours = d.includeHours ? DAYS.map((day) => ({
      dayOfWeek: day, opensAt: d[`opens_${day}`] || "00:00", closesAt: d[`closes_${day}`] || "00:00", closed: !d[`open_${day}`],
    })) : [];
    const x = await POST("/restaurants", { restaurantId: uid("restaurant"), name: d.name.trim(), address: d.address.trim(), acceptingOrders: Boolean(d.acceptingOrders), openingHours, menu: [] });
    session.set("restaurantId", x.restaurantId);
    location.hash = `#/restaurants/${encodeURIComponent(x.restaurantId)}`;
    return `${x.name} registered`;
  },
});

ACTIONS.addMenuItem = ({ id }) => openSheet({
  title: "Add menu item", submitLabel: "Add to menu", tint: "canary",
  body: field({ id: "name", label: "Item name", required: true }) +
    field({ id: "description", label: "Description", type: "textarea", required: true }) +
    `<div class="grid grid-cols-2 gap-4">${field({ id: "price", label: "Price (N$)", type: "number", required: true, attrs: 'min="0.01" step="0.01" inputmode="decimal"' })}
      ${field({ id: "availableQuantity", label: "Quantity in stock", type: "number", required: true, value: "20", attrs: 'min="0" step="1" inputmode="numeric"' })}</div>` +
    checkbox({ id: "available", label: "Available to order" }),
  async onSubmit(d) {
    const price = Number(d.price), qty = Number(d.availableQuantity);
    if (!(price > 0)) throw new Error("Price must be more than N$ 0.00.");
    if (!Number.isInteger(qty) || qty < 0) throw new Error("Quantity must be a whole number, 0 or more.");
    const m = await POST(`/restaurants/${encodeURIComponent(id)}/menu`, { menuItemId: uid("menu-item"), name: d.name.trim(), description: d.description.trim(), price, availableQuantity: qty, available: Boolean(d.available) });
    return `${m.name} added to the menu`;
  },
});

ACTIONS.editStock = ({ restaurant, item, name, qty }) => openSheet({
  title: "Update stock", submitLabel: "Save stock", tint: "canary",
  body: `<p class="text-sm"><span class="font-semibold">${esc(name)}</span></p>` +
    field({ id: "availableQuantity", label: "Quantity in stock", type: "number", required: true, value: qty, attrs: 'min="0" step="1" inputmode="numeric"' }),
  async onSubmit(d) {
    const q = Number(d.availableQuantity);
    if (!Number.isInteger(q) || q < 0) throw new Error("Quantity must be a whole number, 0 or more.");
    await PUT(`/restaurants/${encodeURIComponent(restaurant)}/menu/${encodeURIComponent(item)}/inventory`, { availableQuantity: q });
    return `${name}: ${q} in stock`;
  },
});

/* ---------- Orders ---------- */

VIEWS.orders = async (id, q) => (id ? orderWaybill(id) : orderList(q));
let waybillTarget = "";

async function orderList(q) {
  const customer = q.get("customer") || "", restaurantId = q.get("restaurant") || "", status = q.get("status") || "";
  const qs = new URLSearchParams();
  if (customer) qs.set("customerId", customer);
  if (restaurantId) qs.set("restaurantId", restaurantId);
  const [orders, dir] = await Promise.all([GET(`/orders${qs.toString() ? `?${qs}` : ""}`), directory()]);
  const shown = status ? orders.filter((o) => o.status === status) : orders;
  const counts = Object.fromEntries([...ORDER_FLOW, "CANCELLED"].map((s) => [s, orders.filter((o) => o.status === s).length]));
  const link = (patch) => {
    const p = new URLSearchParams({ customer, restaurant: restaurantId, status, order: "", ...patch });
    [...p.keys()].forEach((k) => { if (!p.get(k)) p.delete(k); });
    return `#/orders${p.toString() ? `?${p}` : ""}`;
  };
  if (q.get("new")) setTimeout(() => ACTIONS.newOrder({ customer: q.get("customer") || "" }), 0);

  const split = isWide() && shown.length > 0;
  let selId = "", w = null;
  if (split) {
    const newest = [...shown].sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))[0];
    selId = shown.some((o) => o.orderId === q.get("order")) ? q.get("order") : newest.orderId;
    w = await loadWaybill(selId);
    lastWaybill = JSON.stringify(w);
    waybillTarget = selId;
  } else {
    waybillTarget = "";
  }
  const pick = (o) => link({ order: o.orderId });
  const columns = split || isNarrow() ? [
    { key: "orderId", label: "Order", render: (o) => orderCell(o, dir, split ? pick(o) : null) },
    { key: "status", label: "Status", sort: (o) => (o.status === "CANCELLED" ? 99 : ORDER_FLOW.indexOf(o.status)), render: (o) => stamp(o.status) },
    { key: "totalAmount", label: "Total", align: "right", sort: (o) => Number(o.totalAmount), render: (o) => `<span class="num">${money(o.totalAmount)}</span>` },
  ] : null;

  return pageHead({
    title: "Orders",
    sub: `<span class="num">${shown.length}</span> of <span class="num">${orders.length}</span> shown · order service :8081`,
    actions: `<button class="btn btn-ink" data-action="newOrder"><i data-lucide="plus"></i>Place order</button>`,
  }) + `
  <div class="flex flex-wrap items-end gap-3 mb-4">
    <div class="w-full sm:w-56">${select({ id: "f-customer", label: "Customer", value: customer, placeholder: "All customers", options: dir.customers.map((c) => ({ value: c.customerId, label: c.fullName })), attrs: 'data-filter="customer"' })}</div>
    <div class="w-full sm:w-56">${select({ id: "f-restaurant", label: "Restaurant", value: restaurantId, placeholder: "All restaurants", options: dir.restaurants.map((x) => ({ value: x.restaurantId, label: x.name })), attrs: 'data-filter="restaurant"' })}</div>
  </div>
  <div class="flex flex-wrap gap-2 mb-5" role="group" aria-label="Filter by status">
    <a class="chip" href="${link({ status: "" })}" aria-pressed="${!status}">All <span class="num opacity-70">${orders.length}</span></a>
    ${[...ORDER_FLOW, "CANCELLED"].map((s) => `<a class="chip" href="${link({ status: s })}" aria-pressed="${status === s}">${s.replaceAll("_", " ").toLowerCase()} <span class="num opacity-70">${counts[s]}</span></a>`).join("")}
  </div>
  <div class="${split ? "grid grid-cols-[minmax(0,440px)_minmax(0,1fr)] gap-8 items-start" : ""}">
  <div class="min-w-0">${ledger("t-orders", {
    rows: shown,
    href: (o) => (split ? pick(o) : `#/orders/${encodeURIComponent(o.orderId)}`),
    selected: (o) => o.orderId === selId,
    sort: { key: "updatedAt", dir: "desc" },
    empty: { title: status || customer || restaurantId ? "No orders match these filters" : "No orders yet", body: status || customer || restaurantId ? `<a class="underline" href="#/orders">Clear filters</a>` : "Place the first order to watch it move through the services." },
    columns: columns || [
      { key: "orderId", label: "Order", render: (o) => orderLink(o.orderId) },
      { key: "customerId", label: "Customer", render: (o) => nameOr(dir.customer[o.customerId], "fullName", o.customerId) },
      { key: "restaurantId", label: "Restaurant", render: (o) => nameOr(dir.restaurant[o.restaurantId], "name", o.restaurantId) },
      { key: "items", label: "Items", align: "right", sort: (o) => o.items.reduce((n, i) => n + i.quantity, 0), render: (o) => `<span class="num">${o.items.reduce((n, i) => n + i.quantity, 0)}</span>` },
      { key: "totalAmount", label: "Total", align: "right", sort: (o) => Number(o.totalAmount), render: (o) => `<span class="num">${money(o.totalAmount)}</span>` },
      { key: "status", label: "Status", sort: (o) => (o.status === "CANCELLED" ? 99 : ORDER_FLOW.indexOf(o.status)), render: (o) => stamp(o.status) },
      { key: "updatedAt", label: "Updated", render: (o) => `<span class="num text-[13px]">${when(o.updatedAt)}</span>` },
    ],
  })}</div>
  ${split ? `<div id="waybill-slot" class="min-w-0" aria-live="polite">${waybillHtml(w, true)}</div>` : ""}
  </div>`;
}

afterRender.orders = () => {
  $$("[data-filter]").forEach((sel) => sel.addEventListener("change", () => {
    const q = new URLSearchParams(current.query);
    q.delete("new");
    if (sel.value) q.set(sel.dataset.filter, sel.value); else q.delete(sel.dataset.filter);
    location.hash = `#/orders${q.toString() ? `?${q}` : ""}`;
  }));
  if (waybillTarget) startOrderPolling();
};

ACTIONS.newOrder = async ({ customer = "" } = {}) => {
  const dir = await directory();
  current.query.delete("new");
  if (location.hash.includes("new=1")) history.replaceState(null, "", location.hash.replace(/[?&]new=1/, "").replace(/\?$/, ""));
  const preCustomer = customer || session.get("customerId") || "";
  const preRestaurant = session.get("restaurantId") || "";
  openSheet({
    title: "Place order", submitLabel: "Place order", tint: "white",
    body: select({ id: "customerId", label: "Customer", required: true, value: dir.customer[preCustomer] ? preCustomer : "", options: dir.customers.map((c) => ({ value: c.customerId, label: `${c.fullName} · ${c.email}` })) }) +
      `<div id="addr-slot"></div>` +
      select({ id: "restaurantId", label: "Restaurant", required: true, value: dir.restaurant[preRestaurant]?.acceptingOrders ? preRestaurant : "",
        options: dir.restaurants.map((x) => ({ value: x.restaurantId, label: x.acceptingOrders ? x.name : `${x.name} (not accepting orders)`, disabled: !x.acceptingOrders })) }) +
      `<div id="menu-slot"></div>
       <div class="rule pt-3 flex items-baseline justify-between"><span class="label">Total</span><span id="order-total" class="num text-2xl font-semibold">N$ 0.00</span></div>`,
    onMount(form) {
      const paintAddresses = () => {
        const c = dir.customer[form.customerId.value];
        $("#addr-slot").innerHTML = !c ? "" : c.addresses.length
          ? select({ id: "deliveryAddressId", label: "Deliver to", required: true, value: c.addresses[0].addressId, placeholder: null, options: c.addresses.map((a) => ({ value: a.addressId, label: `${a.label} · ${a.street}, ${a.city}` })) })
          : `<div class="form-error">${esc(c.fullName)} has no delivery address. <a class="underline font-semibold" href="#/customers/${encodeURIComponent(c.customerId)}">Add one on their profile</a> first.</div>`;
      };
      const paintMenu = () => {
        const x = dir.restaurant[form.restaurantId.value];
        if (!x) { $("#menu-slot").innerHTML = ""; return totals(); }
        const items = x.menu.filter((m) => m.available && m.availableQuantity > 0);
        $("#menu-slot").innerHTML = `<fieldset><legend class="field-label">Items</legend>${items.length ? `<ul class="divide-y divide-dashed divide-ink-200 border-y border-ink-200">${items.map((m) => `
          <li class="flex items-center justify-between gap-3 py-2.5" data-item="${esc(m.menuItemId)}" data-name="${esc(m.name)}" data-price="${m.price}">
            <div class="min-w-0"><div class="font-semibold text-sm">${esc(m.name)}</div><div class="text-xs text-ink-500"><span class="num">${money(m.price)}</span> · <span class="num">${m.availableQuantity}</span> left</div></div>
            <div class="stepper"><button type="button" data-step="-1" aria-label="One fewer ${esc(m.name)}"><i data-lucide="minus" class="w-4 h-4"></i></button><input type="number" min="0" max="${m.availableQuantity}" value="0" inputmode="numeric" aria-label="Quantity of ${esc(m.name)}"><button type="button" data-step="1" aria-label="One more ${esc(m.name)}"><i data-lucide="plus" class="w-4 h-4"></i></button></div>
          </li>`).join("")}</ul>` : `<div class="empty !py-6">Nothing on this menu is in stock.</div>`}</fieldset>`;
        icons();
        totals();
      };
      const totals = () => {
        let sum = 0;
        $$("#menu-slot li[data-item]").forEach((li) => {
          const input = $("input", li);
          const v = Math.max(0, Math.min(Number(input.max), Math.floor(Number(input.value) || 0)));
          if (String(v) !== input.value) input.value = v;
          $('[data-step="-1"]', li).disabled = v <= 0;
          $('[data-step="1"]', li).disabled = v >= Number(input.max);
          sum += v * Number(li.dataset.price);
        });
        $("#order-total").textContent = money(sum);
        const noAddr = !$("#deliveryAddressId");
        $("#sheet-submit").disabled = sum <= 0 || noAddr;
      };
      form.customerId.addEventListener("change", () => { paintAddresses(); totals(); });
      form.restaurantId.addEventListener("change", paintMenu);
      $("#menu-slot").addEventListener("click", (e) => {
        const b = e.target.closest("[data-step]");
        if (!b) return;
        const input = $("input", b.closest("li"));
        input.value = Number(input.value || 0) + Number(b.dataset.step);
        totals();
      });
      $("#menu-slot").addEventListener("input", totals);
      paintAddresses();
      paintMenu();
    },
    async onSubmit(d, form) {
      const items = $$("#menu-slot li[data-item]", form)
        .map((li) => ({ menuItemId: li.dataset.item, itemName: li.dataset.name, quantity: Number($("input", li).value), unitPrice: Number(li.dataset.price) }))
        .filter((i) => i.quantity > 0);
      if (!items.length) throw new Error("Add at least one item.");
      const totalAmount = Math.round(items.reduce((s, i) => s + i.quantity * i.unitPrice, 0) * 100) / 100;
      const o = await POST("/orders", { orderId: uid("order"), customerId: d.customerId, restaurantId: d.restaurantId, deliveryAddressId: d.deliveryAddressId, items, totalAmount, createdAt: nowIso() });
      session.set("customerId", d.customerId);
      session.set("restaurantId", d.restaurantId);
      location.hash = `#/orders/${encodeURIComponent(o.orderId)}`;
      return "Order placed";
    },
  });
};

/* ---------- The waybill: one order, one tinted copy per owning service ---------- */

const COPIES = [
  { key: "order", label: "Order", tint: "white", owner: "Order service" },
  { key: "restaurant", label: "Restaurant", tint: "canary", owner: "Restaurant service" },
  { key: "payment", label: "Payment", tint: "pink", owner: "Payment service" },
  { key: "delivery", label: "Delivery", tint: "blue", owner: "Delivery service" },
  { key: "notify", label: "Notifications", tint: "green", owner: "Notification service" },
];
let activeCopy = "order";
let lastWaybill = "";

async function loadWaybill(id) {
  const order = await GET(`/orders/${encodeURIComponent(id)}`);
  const r = await settle({
    customer: GET(`/customers/${encodeURIComponent(order.customerId)}`),
    restaurant: GET(`/restaurants/${encodeURIComponent(order.restaurantId)}`),
    payments: GET(`/payments?orderId=${encodeURIComponent(order.orderId)}`),
    deliveries: GET("/delivery/assignments"),
    drivers: GET("/delivery/drivers"),
    notifications: GET(`/notifications?recipientId=${encodeURIComponent(order.customerId)}`),
  });
  if (r.deliveries.ok) r.deliveries.data = r.deliveries.data.filter((d) => d.orderId === order.orderId);
  return { order, ...r };
}

async function orderWaybill(id) {
  waybillTarget = id;
  const w = await loadWaybill(id);
  lastWaybill = JSON.stringify(w);
  if (!COPIES.some((c) => c.key === activeCopy)) activeCopy = "order";
  return waybillHtml(w);
}

function startOrderPolling() {
  clearInterval(pollTimer);
  const id = waybillTarget;
  pollTimer = setInterval(async () => {
    if (document.hidden || !$("#sheet").hidden || current.section !== "orders" || waybillTarget !== id) return;
    try {
      const w = await loadWaybill(id);
      const snapshot = JSON.stringify(w);
      if (snapshot === lastWaybill) return;
      const prev = JSON.parse(lastWaybill);
      lastWaybill = snapshot;
      paintWaybill(w, prev);
      if (prev.order.status !== w.order.status) toast(`Order is now ${w.order.status.replaceAll("_", " ")}`);
    } catch { /* keep the last good copy on screen */ }
  }, 4000);
}

/** Repaints the waybill in place; a copy whose service just filled in (usually a Kafka event) flashes its tab. */
function paintWaybill(w, prev) {
  const slot = $("#waybill-slot");
  if (slot) slot.innerHTML = waybillHtml(w, true);
  else $("#view").firstElementChild.innerHTML = waybillHtml(w);
  icons();
  if (prev) COPIES.forEach((c) => { if (copySummary(c.key, prev) !== copySummary(c.key, w)) $(`#tab-${c.key}`)?.classList.add("just-filled"); });
}

const KITCHEN_STATE = { CREATED: "awaiting payment", CONFIRMED: "to prepare", PREPARING: "preparing", READY: "ready for pickup", OUT_FOR_DELIVERY: "collected", DELIVERED: "collected", CANCELLED: "cancelled" };

function copySummary(key, w) {
  if (key === "order") return w.order.status.replaceAll("_", " ");
  if (key === "restaurant") return w.restaurant.ok ? KITCHEN_STATE[w.order.status] : "offline";
  if (key === "payment") return !w.payments.ok ? "offline" : w.payments.data.length ? w.payments.data[w.payments.data.length - 1].status.toLowerCase() : "none yet";
  if (key === "delivery") return !w.deliveries.ok ? "offline" : w.deliveries.data.length ? w.deliveries.data[w.deliveries.data.length - 1].status.replaceAll("_", " ").toLowerCase() : "none yet";
  if (key === "notify") {
    if (!w.notifications.ok) return "offline";
    const n = w.notifications.data.filter((x) => mentions(x, w.order.orderId)).length;
    return n ? `${n} for this order` : "none yet";
  }
  return "";
}
const mentions = (n, orderId) => `${n.subject} ${n.message}`.includes(orderId);

function waybillHtml(w, embedded = false) {
  const o = w.order;
  const next = ORDER_NEXT[o.status];
  const cancellable = ORDER_CANCELLABLE.includes(o.status);
  const idx = ORDER_FLOW.indexOf(o.status);
  const restaurantName = w.restaurant.ok ? esc(w.restaurant.data.name) : `<span class="id">${esc(o.restaurantId)}</span>`;
  const customerName = w.customer.ok ? esc(w.customer.data.fullName) : `<span class="id">${esc(o.customerId)}</span>`;
  const under = COPIES.filter((c) => c.key !== activeCopy).slice(0, 4).reverse();
  const front = COPIES.find((c) => c.key === activeCopy);

  const head = embedded
    ? `<div class="flex items-start justify-between gap-4 mb-4 pb-3 rule-b"><div class="min-w-0"><h2 class="heading text-3xl">Waybill</h2>
        <div class="flex flex-wrap items-center gap-x-3 mt-1"><span class="num text-[13px] text-ink-700 truncate">${esc(o.orderId)}</span><a class="text-xs font-semibold hover:underline inline-flex items-center gap-1" href="#/orders/${encodeURIComponent(o.orderId)}">Open on its own<i data-lucide="arrow-up-right" class="w-3.5 h-3.5"></i></a></div></div>${stamp(o.status, "lg")}</div>`
    : pageHead({ title: "Waybill", sub: `<span class="num">${esc(o.orderId)}</span>`, back: { href: "#/orders", label: "Orders" }, actions: `${stamp(o.status, "lg")}` });
  return head + `
  <section class="sheet-paper p-5 sm:p-6 ${embedded ? "mb-6" : "mb-8"}" aria-label="Lifecycle">
    <div class="grid grid-cols-1 ${embedded ? "" : "md:grid-cols-[minmax(0,1fr)_auto]"} gap-6 items-start">
      <div class="min-w-0">
        <div class="flex flex-wrap gap-x-10 gap-y-3 text-sm mb-5">
          <div><div class="label">From</div><div class="font-semibold mt-1">${restaurantName}</div></div>
          <div><div class="label">To</div><div class="font-semibold mt-1">${customerName}</div></div>
          <div><div class="label">Placed</div><div class="num mt-1 text-[13px]">${when(o.createdAt)}</div></div>
          <div><div class="label">Last change</div><div class="num mt-1 text-[13px]">${when(o.updatedAt)}</div></div>
        </div>
        <ol class="lifecycle ${o.status === "CANCELLED" ? "is-void" : ""}" aria-label="Order lifecycle">
          ${ORDER_FLOW.map((s, i) => {
            const cls = o.status === "CANCELLED" ? "" : i < idx ? "done" : i === idx ? "current" : s === next ? "next" : "todo";
            return `<li class="${cls}" ${i === idx ? 'aria-current="step"' : ""}>${s.replaceAll("_", " ")}</li>`;
          }).join("")}
        </ol>
      </div>
      <div class="flex flex-wrap gap-2 ${embedded ? "" : "md:flex-col md:items-stretch md:w-56"}">
        ${nextStepButtons(w)}
        ${cancellable ? `<button class="btn" data-action="transition" data-id="${esc(o.orderId)}" data-status="CANCELLED" data-confirm="1">Cancel order</button>` : ""}
        ${!next && !cancellable ? `<p class="text-sm text-ink-700">${o.status === "DELIVERED" ? "Delivered. This waybill is closed." : "Cancelled. No further steps."}</p>` : ""}
      </div>
    </div>
    <p class="text-xs text-ink-500 mt-4 flex items-center gap-1.5"><i data-lucide="radio" class="w-3.5 h-3.5"></i>Kafka events may advance this order on their own; this page refreshes every few seconds.</p>
  </section>

  <div role="tablist" aria-label="Copies of this waybill" class="copy-tabs ${embedded ? "is-compact" : ""}">
    ${COPIES.map((c) => `<button role="tab" type="button" id="tab-${c.key}" class="tab tint-${c.tint}" aria-selected="${c.key === activeCopy}" aria-controls="copy-panel" tabindex="${c.key === activeCopy ? 0 : -1}" data-action="copyTab" data-busy="off" data-key="${c.key}">
      ${embedded && c.key === "notify" ? "Notify" : c.label}<span class="font-medium normal-case tracking-normal opacity-70" title="${esc(copySummary(c.key, w))}">${esc(copySummary(c.key, w))}</span></button>`).join("")}
  </div>
  <div class="waybill">
    ${under.map((c) => `<div class="waybill-under tint-${c.tint}" aria-hidden="true"></div>`).join("")}
    <div class="waybill-front tint-${front.tint}">
      <div id="copy-panel" role="tabpanel" aria-labelledby="tab-${front.key}" class="copy-panel p-5 sm:p-7">
        <div class="flex items-center justify-between gap-4 mb-5"><h2 class="heading text-2xl">${front.label} copy</h2><span class="label !text-ink-700">${front.owner}</span></div>
        ${COPY_BODY[front.key](w)}
      </div>
    </div>
  </div>`;
}

/**
 * The waybill's single red button is the step that really moves the order next.
 * Payment approval and driver hand-off advance the order through Kafka events,
 * so those come first; the direct order transition stays available beside them.
 */
function nextStepButtons(w) {
  const o = w.order;
  const next = ORDER_NEXT[o.status];
  if (!next) return "";
  const direct = (primary) => `<button class="btn ${primary ? "btn-primary" : ""}" data-action="transition" data-id="${esc(o.orderId)}" data-status="${next}">${ORDER_ACTION[next]}${primary ? '<i data-lucide="arrow-right"></i>' : ""}</button>`;
  const pending = w.payments.ok ? w.payments.data.find((p) => p.status === "PENDING") : null;
  const delivery = w.deliveries.ok ? w.deliveries.data.find((d) => !["DELIVERED", "CANCELLED"].includes(d.status)) : null;
  if (o.status === "CREATED" && pending) {
    return `<button class="btn btn-primary" data-action="approvePayment" data-id="${esc(pending.paymentId)}">Approve payment<i data-lucide="arrow-right"></i></button>${direct(false)}`;
  }
  if (o.status === "READY" && w.deliveries.ok && !delivery) {
    return `<button class="btn btn-primary" data-action="newAssignment" data-order="${esc(o.orderId)}">Assign driver<i data-lucide="arrow-right"></i></button>${direct(false)}`;
  }
  if ((o.status === "READY" || o.status === "OUT_FOR_DELIVERY") && delivery && DELIVERY_NEXT[delivery.status]) {
    const step = DELIVERY_NEXT[delivery.status];
    return `<button class="btn btn-primary" data-action="deliveryStatus" data-id="${esc(delivery.deliveryId)}" data-status="${step}">Driver: ${DELIVERY_ACTION[step].toLowerCase()}<i data-lucide="arrow-right"></i></button>${direct(false)}`;
  }
  return direct(true);
}

const COPY_BODY = {
  order(w) {
    const o = w.order;
    const c = w.customer.ok ? w.customer.data : null;
    const addr = c?.addresses.find((a) => a.addressId === o.deliveryAddressId);
    const inHistory = c?.historicalOrderIds.includes(o.orderId);
    return `<div class="grid grid-cols-1 sm:grid-cols-3 gap-5 text-sm mb-6">
        <div><div class="label">Customer</div><div class="mt-1">${c ? `<a class="font-semibold hover:underline" href="#/customers/${encodeURIComponent(c.customerId)}">${esc(c.fullName)}</a><div class="text-ink-700">${esc(c.phoneNumber)}</div>` : offline("Customer service", w.customer.error)}</div></div>
        <div><div class="label">Deliver to</div><div class="mt-1">${addr ? `<div class="font-semibold">${esc(addr.label)}</div><div>${esc(addr.street)}, ${esc(addr.city)}</div>${addr.deliveryInstructions ? `<div class="text-ink-700 italic mt-1">${esc(addr.deliveryInstructions)}</div>` : ""}` : idCell(o.deliveryAddressId)}</div></div>
        <div><div class="label">Customer history</div><div class="mt-1">${!c ? "—" : inHistory ? `<span class="text-ok font-semibold">Recorded on profile</span>`
          : `<button class="btn btn-sm" data-action="recordHistory" data-customer="${esc(c.customerId)}" data-order="${esc(o.orderId)}">Record on profile</button>`}</div></div>
      </div>
      <div class="perforation mb-1"></div>
      <table class="ledger"><thead><tr><th scope="col"><span>Qty</span></th><th scope="col"><span>Item</span></th><th scope="col" class="r"><span>Unit</span></th><th scope="col" class="r"><span>Line</span></th></tr></thead>
        <tbody>${o.items.map((i) => `<tr><td class="num">${i.quantity}</td><td class="font-semibold">${esc(i.itemName)}</td><td class="r num">${money(i.unitPrice)}</td><td class="r num">${money(i.quantity * i.unitPrice)}</td></tr>`).join("")}</tbody></table>
      <div class="flex justify-end items-baseline gap-4 mt-4"><span class="label">Total</span><span class="num text-3xl sm:text-4xl font-semibold tracking-tight">${money(o.totalAmount)}</span></div>`;
  },

  restaurant(w) {
    if (!w.restaurant.ok) return offline("Restaurant service", w.restaurant.error);
    const x = w.restaurant.data;
    const o = w.order;
    const kitchenStep = { CONFIRMED: "PREPARING", PREPARING: "READY" }[o.status];
    return `<div class="flex flex-wrap justify-between gap-4 mb-5">
        <div><a class="font-semibold text-lg hover:underline" href="#/restaurants/${encodeURIComponent(x.restaurantId)}">${esc(x.name)}</a><div class="text-sm">${esc(x.address)}</div></div>
        ${kitchenStep ? `<button class="btn btn-ink" data-action="transition" data-id="${esc(o.orderId)}" data-status="${kitchenStep}">${ORDER_ACTION[kitchenStep]}<i data-lucide="arrow-right"></i></button>`
          : `<p class="text-sm max-w-[34ch]">${o.status === "CREATED" ? "Waiting for payment to confirm the order before the kitchen starts." : "Nothing for the kitchen to do at this step."}</p>`}
      </div>
      <table class="ledger"><thead><tr><th scope="col"><span>Item ordered</span></th><th scope="col" class="r"><span>Qty</span></th><th scope="col" class="r"><span>Stock now</span></th></tr></thead>
        <tbody>${o.items.map((i) => { const m = x.menu.find((mm) => mm.menuItemId === i.menuItemId); return `<tr><td class="font-semibold">${esc(i.itemName)}</td><td class="r num">${i.quantity}</td><td class="r num">${m ? m.availableQuantity : "—"}</td></tr>`; }).join("")}</tbody></table>`;
  },

  payment(w) {
    if (!w.payments.ok) return offline("Payment service", w.payments.error);
    const o = w.order;
    const list = w.payments.data;
    const open = list.some((p) => p.status === "PENDING" || p.status === "COMPLETED");
    return `${list.length ? `<div class="space-y-4">${list.map((p) => `
        <div class="grid grid-cols-1 md:grid-cols-[minmax(0,1fr)_auto] gap-4 items-start border-b border-dashed border-ink/30 pb-4 last:border-0">
          <div class="text-sm space-y-1">
            <div class="flex flex-wrap items-center gap-3">${stamp(p.status)}<span class="num text-xl font-semibold">${money(p.amount, p.currency)}</span></div>
            <div>${idCell(p.paymentId)}</div>
            <div class="text-ink-700">Requested <span class="num">${when(p.requestedAt)}</span>${p.processedAt ? ` · processed <span class="num">${when(p.processedAt)}</span>` : ""}</div>
            ${p.failureReason ? `<div class="text-perf-dark">Declined: ${esc(p.failureReason)}</div>` : ""}
          </div>
          ${p.status === "PENDING" ? `<div class="flex gap-2"><button class="btn btn-ink" data-action="approvePayment" data-id="${esc(p.paymentId)}">Approve</button><button class="btn" data-action="declinePayment" data-id="${esc(p.paymentId)}">Decline</button></div>` : ""}
        </div>`).join("")}</div>`
      : `<p class="text-sm mb-4">No payment yet. The order-created event normally creates a pending payment; you can also request one now.</p>`}
      ${!open && !["CANCELLED", "DELIVERED"].includes(o.status) ? `<button class="btn btn-ink mt-4" data-action="newPayment" data-order="${esc(o.orderId)}"><i data-lucide="credit-card"></i>Request payment of ${money(o.totalAmount)}</button>` : ""}`;
  },

  delivery(w) {
    if (!w.deliveries.ok) return offline("Delivery service", w.deliveries.error);
    const o = w.order;
    const drivers = w.drivers.ok ? Object.fromEntries(w.drivers.data.map((d) => [d.driverId, d])) : {};
    const list = w.deliveries.data;
    const active = list.find((d) => !["DELIVERED", "CANCELLED"].includes(d.status));
    return `${list.length ? `<div class="space-y-4">${list.map((d) => deliveryBlock(d, drivers[d.driverId])).join("")}</div>`
      : `<p class="text-sm mb-4">${o.status === "READY" ? "The order is ready. Assign a driver to collect it." : "No driver assigned yet. Assignment opens once the kitchen marks the order ready."}</p>`}
      ${!active && ["READY", "PREPARING", "CONFIRMED"].includes(o.status) ? `<button class="btn btn-ink mt-4" data-action="newAssignment" data-order="${esc(o.orderId)}"><i data-lucide="bike"></i>Assign driver</button>` : ""}`;
  },

  notify(w) {
    if (!w.notifications.ok) return offline("Notification service", w.notifications.error);
    const o = w.order;
    const forCustomer = w.notifications.data;
    const list = forCustomer.filter((n) => mentions(n, o.orderId)).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
    const others = forCustomer.length - list.length;
    return `<div class="flex flex-wrap justify-between items-center gap-3 mb-4"><p class="text-sm">Messages to the customer about this order.${others ? ` <a class="underline" href="#/notifications?recipient=${encodeURIComponent(o.customerId)}">${others} other${others === 1 ? "" : "s"} for this customer</a>.` : ""}</p>
      <button class="btn btn-ink btn-sm" data-action="newNotification" data-type="CUSTOMER" data-recipient="${esc(o.customerId)}" data-subject="Your order ${esc(o.status.replaceAll("_", " ").toLowerCase())}"><i data-lucide="send"></i>Notify customer</button></div>
      ${list.length ? `<ul class="space-y-3">${list.slice(0, 12).map((n) => `<li class="grid grid-cols-[auto_minmax(0,1fr)_auto] gap-3 items-start text-sm border-b border-dashed border-ink/30 pb-3 last:border-0">
          <span class="mt-0.5"><i data-lucide="${n.channel === "SMS" ? "message-square" : n.channel === "EMAIL" ? "mail" : "smartphone"}" class="w-4 h-4" aria-hidden="true"></i></span>
          <div class="min-w-0"><div class="font-semibold">${esc(n.subject)}</div><div class="text-ink-700">${esc(n.message)}</div><div class="text-xs mt-1"><span class="font-semibold">${esc(n.channel)}</span> · <span class="num">${when(n.createdAt)}</span></div></div>
          ${stamp(n.status)}</li>`).join("")}</ul>` : `<div class="empty !bg-transparent">No messages about this order yet.</div>`}`;
  },
};

function deliveryBlock(d, driver) {
  const next = DELIVERY_NEXT[d.status];
  return `<div class="grid grid-cols-1 md:grid-cols-[minmax(0,1fr)_auto] gap-4 items-start border-b border-dashed border-ink/30 pb-4 last:border-0">
    <div class="text-sm space-y-1">
      <div class="flex flex-wrap items-center gap-3">${stamp(d.status)}<span class="font-semibold">${driver ? esc(driver.fullName) : idCell(d.driverId)}</span>${driver ? `<span class="num text-xs">${esc(driver.vehicleRegistration)}</span>` : ""}</div>
      <div><span class="label">Pickup</span> ${esc(d.restaurantAddress)}</div>
      <div><span class="label">Drop-off</span> ${esc(d.customerAddress)}</div>
      <div class="text-ink-700">Assigned <span class="num">${when(d.assignedAt)}</span> · updated <span class="num">${when(d.updatedAt)}</span> · ${idCell(d.deliveryId)}</div>
    </div>
    <div class="flex flex-wrap gap-2">
      ${next ? `<button class="btn btn-ink btn-sm" data-action="deliveryStatus" data-id="${esc(d.deliveryId)}" data-status="${next}">${DELIVERY_ACTION[next]}<i data-lucide="arrow-right"></i></button>` : ""}
      ${d.status === "ASSIGNED" ? `<button class="btn btn-sm" data-action="deliveryStatus" data-id="${esc(d.deliveryId)}" data-status="CANCELLED" data-confirm="1">Cancel</button>` : ""}
    </div>
  </div>`;
}

ACTIONS.copyTab = ({ key }) => {
  activeCopy = key;
  paintWaybill(JSON.parse(lastWaybill));
  $(`#tab-${key}`)?.focus();
};
document.addEventListener("keydown", (e) => {
  const tab = e.target.closest?.('[role="tab"]');
  if (!tab || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
  e.preventDefault();
  const keys = COPIES.map((c) => c.key);
  let i = keys.indexOf(tab.dataset.key);
  i = e.key === "Home" ? 0 : e.key === "End" ? keys.length - 1 : (i + (e.key === "ArrowRight" ? 1 : -1) + keys.length) % keys.length;
  ACTIONS.copyTab({ key: keys[i] });
});

ACTIONS.transition = async ({ id, status, confirm: needsConfirm }) => {
  if (needsConfirm && !window.confirm("Cancel this order? This cannot be undone.")) return;
  await POST(`/orders/${encodeURIComponent(id)}/transitions`, { status, occurredAt: nowIso() });
  toast(`Order ${status === "CANCELLED" ? "cancelled" : `moved to ${status.replaceAll("_", " ")}`}`);
  await rerender();
};

/* ---------- Payments ---------- */

VIEWS.payments = async (_id, q) => {
  const orderId = q.get("order") || "";
  const payments = await GET(`/payments${orderId ? `?orderId=${encodeURIComponent(orderId)}` : ""}`);
  const dir = await directory();
  const pending = payments.filter((p) => p.status === "PENDING").length;
  return pageHead({
    title: "Payments",
    sub: `<span class="num">${payments.length}</span> payments${pending ? ` · <span class="num">${pending}</span> awaiting a decision` : ""} · payment service :8084`,
    actions: `<button class="btn btn-ink" data-action="newPayment"><i data-lucide="plus"></i>Request payment</button>`,
  }) + `
  <form class="flex flex-wrap items-end gap-2 mb-5" data-search="order">
    <div class="w-full sm:w-80">${field({ id: "q-order", label: "Order ID", value: orderId, placeholder: "order-…" })}</div>
    <button class="btn" type="submit">Find</button>${orderId ? `<a class="btn btn-ghost" href="#/payments">Clear</a>` : ""}
  </form>
  ${ledger("t-payments", {
    rows: payments,
    sort: { key: "requestedAt", dir: "desc" },
    empty: { title: orderId ? "No payment for that order" : "No payments yet", body: orderId ? "Check the order ID, or request a payment for it." : "Payments appear when orders are placed." },
    columns: [
      { key: "paymentId", label: "Payment", render: (p) => idCell(p.paymentId) },
      { key: "orderId", label: "Order", render: (p) => orderLink(p.orderId) },
      { key: "customerId", label: "Customer", render: (p) => nameOr(dir.customer[p.customerId], "fullName", p.customerId) },
      { key: "amount", label: "Amount", align: "right", sort: (p) => Number(p.amount), render: (p) => `<span class="num">${money(p.amount, p.currency)}</span>` },
      { key: "status", label: "Status", render: (p) => `${stamp(p.status)}${p.failureReason ? `<div class="text-xs text-perf-dark mt-1 max-w-[24ch]">${esc(p.failureReason)}</div>` : ""}` },
      { key: "requestedAt", label: "Requested", render: (p) => `<span class="num text-[13px]">${when(p.requestedAt)}</span>` },
      { key: "decide", label: "", sortable: false, align: "right", render: (p) => p.status === "PENDING"
        ? `<div class="flex justify-end gap-2"><button class="btn btn-ink btn-sm" data-action="approvePayment" data-id="${esc(p.paymentId)}">Approve</button><button class="btn btn-sm" data-action="declinePayment" data-id="${esc(p.paymentId)}">Decline</button></div>`
        : `<span class="num text-[13px] text-ink-500">${p.processedAt ? when(p.processedAt) : ""}</span>` },
    ],
  })}`;
};

afterRender.payments = () => bindSearch("order", "#/payments", "order");
afterRender.notifications = () => bindSearch("recipient", "#/notifications", "recipient");

function bindSearch(kind, base, param) {
  const form = $(`[data-search="${kind}"]`);
  form?.addEventListener("submit", (e) => {
    e.preventDefault();
    const v = $("input", form).value.trim();
    location.hash = v ? `${base}?${param}=${encodeURIComponent(v)}` : base;
  });
}

ACTIONS.approvePayment = async ({ id }) => {
  await POST(`/payments/${encodeURIComponent(id)}/process`, { approved: true, processedAt: nowIso() });
  toast("Payment approved");
  await rerender();
};

ACTIONS.declinePayment = ({ id }) => openSheet({
  title: "Decline payment", submitLabel: "Decline payment", tint: "pink",
  body: field({ id: "failureReason", label: "Reason", required: true, placeholder: "Card declined by issuer" }),
  async onSubmit(d) {
    await POST(`/payments/${encodeURIComponent(id)}/process`, { approved: false, processedAt: nowIso(), failureReason: d.failureReason.trim() });
    return "Payment declined";
  },
});

ACTIONS.newPayment = async ({ order = "" } = {}) => {
  const orders = (await GET("/orders")).filter((o) => !["CANCELLED", "DELIVERED"].includes(o.status) || o.orderId === order);
  const byId = Object.fromEntries(orders.map((o) => [o.orderId, o]));
  openSheet({
    title: "Request payment", submitLabel: "Request payment", tint: "pink",
    body: select({ id: "orderId", label: "Order", required: true, value: order, options: orders.map((o) => ({ value: o.orderId, label: `${o.orderId.slice(0, 14)}… · ${money(o.totalAmount)} · ${o.status}` })) }) +
      `<div class="grid grid-cols-[1fr_110px] gap-4">${field({ id: "amount", label: "Amount", type: "number", required: true, attrs: 'min="0.01" step="0.01" inputmode="decimal"' })}${field({ id: "currency", label: "Currency", value: "NAD", required: true })}</div>`,
    onMount(form) {
      const fill = () => { const o = byId[form.orderId.value]; if (o) form.amount.value = Number(o.totalAmount).toFixed(2); };
      form.orderId.addEventListener("change", fill);
      fill();
    },
    async onSubmit(d) {
      const o = byId[d.orderId];
      const amount = Number(d.amount);
      if (!(amount > 0)) throw new Error("Amount must be more than 0.");
      await POST("/payments", { paymentId: uid("payment"), orderId: o.orderId, customerId: o.customerId, amount, currency: d.currency.trim().toUpperCase(), requestedAt: nowIso() });
      return "Payment requested";
    },
  });
};

/* ---------- Delivery ---------- */

VIEWS.delivery = async (tab, q) => {
  tab = tab === "assignments" ? "assignments" : "drivers";
  const status = q.get("status") || "", driverFilter = q.get("driver") || "";
  const [drivers, assignments] = await Promise.all([
    GET(`/delivery/drivers${tab === "drivers" && status ? `?status=${status}` : ""}`),
    GET(`/delivery/assignments${driverFilter ? `?driverId=${encodeURIComponent(driverFilter)}` : ""}`),
  ]);
  const allDrivers = tab === "drivers" && status ? await GET("/delivery/drivers") : drivers;
  const driverById = Object.fromEntries(allDrivers.map((d) => [d.driverId, d]));
  const available = allDrivers.filter((d) => d.status === "AVAILABLE").length;

  const tabs = `<nav class="flex gap-1 border-b border-ink mb-5" aria-label="Delivery views">
    ${[["drivers", "Drivers", allDrivers.length], ["assignments", "Assignments", assignments.length]].map(([k, l, n]) => `<a ${tab === k ? 'aria-current="page"' : ""} href="#/delivery/${k}" class="px-4 py-2.5 -mb-px text-sm font-semibold border border-b-0 rounded-t focus-ring ${tab === k ? "bg-paper-white border-ink" : "border-transparent text-ink-700 hover:text-ink"}">${l} <span class="num opacity-70">${n}</span></a>`).join("")}
  </nav>`;

  const head = pageHead({
    title: "Delivery",
    sub: `<span class="num">${available}</span> of <span class="num">${allDrivers.length}</span> drivers available · delivery service :8086`,
    actions: `<button class="btn" data-action="newDriver"><i data-lucide="user-plus"></i>Register driver</button><button class="btn btn-ink" data-action="newAssignment"><i data-lucide="bike"></i>Assign driver</button>`,
  });

  if (tab === "drivers") {
    return head + tabs + `<div class="flex flex-wrap gap-2 mb-5" role="group" aria-label="Filter drivers by status">
      ${["", "AVAILABLE", "ASSIGNED", "OFFLINE"].map((s) => `<a class="chip" href="#/delivery/drivers${s ? `?status=${s}` : ""}" aria-pressed="${status === s}">${s ? s.toLowerCase() : "All"}</a>`).join("")}</div>` +
      ledger("t-drivers", {
        rows: drivers,
        sort: { key: "fullName", dir: "asc" },
        empty: { title: status ? `No ${status.toLowerCase()} drivers` : "No drivers yet", body: status ? `<a class="underline" href="#/delivery/drivers">Show all drivers</a>` : "Register a driver so orders can be delivered." },
        columns: [
          { key: "fullName", label: "Driver", render: (d) => `<span class="font-semibold">${esc(d.fullName)}</span>` },
          { key: "phoneNumber", label: "Phone", render: (d) => `<span class="num text-[13px]">${esc(d.phoneNumber)}</span>` },
          { key: "vehicleRegistration", label: "Vehicle", render: (d) => `<span class="num text-[13px]">${esc(d.vehicleRegistration)}</span>` },
          { key: "status", label: "Status", render: (d) => stamp(d.status) },
          { key: "driverId", label: "ID", render: (d) => idCell(d.driverId) },
          { key: "jobs", label: "", sortable: false, align: "right", render: (d) => `<a class="text-sm font-semibold hover:underline" href="#/delivery/assignments?driver=${encodeURIComponent(d.driverId)}">Assignments</a>` },
        ],
      });
  }
  return head + tabs + `<div class="w-full sm:w-64 mb-5">${select({ id: "f-driver", label: "Driver", value: driverFilter, placeholder: "All drivers", options: allDrivers.map((d) => ({ value: d.driverId, label: d.fullName })), attrs: 'data-driver-filter' })}</div>` +
    ledger("t-assignments", {
      rows: assignments,
      sort: { key: "updatedAt", dir: "desc" },
      empty: { title: "No assignments", body: "Assign a driver once an order is ready." },
      columns: [
        { key: "deliveryId", label: "Delivery", render: (d) => idCell(d.deliveryId) },
        { key: "orderId", label: "Order", render: (d) => orderLink(d.orderId) },
        { key: "driverId", label: "Driver", render: (d) => nameOr(driverById[d.driverId], "fullName", d.driverId) },
        { key: "route", label: "Route", sortable: false, render: (d) => `<div class="text-[13px] max-w-[34ch]"><div>${esc(d.restaurantAddress)}</div><div class="text-ink-500">→ ${esc(d.customerAddress)}</div></div>` },
        { key: "status", label: "Status", render: (d) => stamp(d.status) },
        { key: "updatedAt", label: "Updated", render: (d) => `<span class="num text-[13px]">${when(d.updatedAt)}</span>` },
        { key: "act", label: "", sortable: false, align: "right", render: (d) => {
          const next = DELIVERY_NEXT[d.status];
          return `<div class="flex justify-end gap-2">${next ? `<button class="btn btn-ink btn-sm" data-action="deliveryStatus" data-id="${esc(d.deliveryId)}" data-status="${next}">${DELIVERY_ACTION[next]}</button>` : ""}${d.status === "ASSIGNED" ? `<button class="btn btn-sm" data-action="deliveryStatus" data-id="${esc(d.deliveryId)}" data-status="CANCELLED" data-confirm="1">Cancel</button>` : ""}</div>`;
        } },
      ],
    });
};

afterRender.delivery = () => {
  $("[data-driver-filter]")?.addEventListener("change", (e) => {
    location.hash = e.target.value ? `#/delivery/assignments?driver=${encodeURIComponent(e.target.value)}` : "#/delivery/assignments";
  });
};

ACTIONS.newDriver = () => openSheet({
  title: "Register driver", submitLabel: "Register driver", tint: "blue",
  body: field({ id: "fullName", label: "Full name", required: true }) +
    field({ id: "phoneNumber", label: "Phone number", type: "tel", required: true, placeholder: "+264 81 000 0000" }) +
    field({ id: "vehicleRegistration", label: "Vehicle registration", required: true, placeholder: "N 12345 W" }),
  async onSubmit(d) {
    const driver = await POST("/delivery/drivers", { driverId: uid("driver"), fullName: d.fullName.trim(), phoneNumber: d.phoneNumber.trim(), vehicleRegistration: d.vehicleRegistration.trim(), status: "AVAILABLE" });
    return `${driver.fullName} registered`;
  },
});

ACTIONS.newAssignment = async ({ order = "" } = {}) => {
  const [orders, drivers, dir] = await Promise.all([GET("/orders"), GET("/delivery/drivers?status=AVAILABLE"), directory()]);
  const open = orders.filter((o) => ["READY", "PREPARING", "CONFIRMED"].includes(o.status) || o.orderId === order);
  const byId = Object.fromEntries(open.map((o) => [o.orderId, o]));
  openSheet({
    title: "Assign driver", submitLabel: "Assign driver", tint: "blue",
    body: select({ id: "orderId", label: "Order", required: true, value: order, options: open.map((o) => ({ value: o.orderId, label: `${o.orderId.slice(0, 14)}… · ${dir.restaurant[o.restaurantId]?.name || "restaurant"} · ${o.status}` })) }) +
      select({ id: "driverId", label: "Driver", required: true, options: drivers.map((d) => ({ value: d.driverId, label: `${d.fullName} · ${d.vehicleRegistration}` })),
        hint: drivers.length ? "Only available drivers are listed." : `No driver is available. <a class="underline" href="#/delivery/drivers">Check drivers</a>.` }) +
      field({ id: "restaurantAddress", label: "Pickup address", required: true }) +
      field({ id: "customerAddress", label: "Drop-off address", required: true }),
    onMount(form) {
      const fill = () => {
        const o = byId[form.orderId.value];
        if (!o) return;
        form.restaurantAddress.value = dir.restaurant[o.restaurantId]?.address || "";
        const a = dir.customer[o.customerId]?.addresses.find((x) => x.addressId === o.deliveryAddressId);
        form.customerAddress.value = a ? `${a.street}, ${a.city}` : "";
      };
      form.orderId.addEventListener("change", fill);
      fill();
    },
    async onSubmit(d) {
      await POST("/delivery/assignments", { deliveryId: uid("delivery"), orderId: d.orderId, driverId: d.driverId, restaurantAddress: d.restaurantAddress.trim(), customerAddress: d.customerAddress.trim(), assignedAt: nowIso() });
      return "Driver assigned";
    },
  });
};

ACTIONS.deliveryStatus = async ({ id, status, confirm: needsConfirm }) => {
  if (needsConfirm && !window.confirm("Cancel this delivery assignment?")) return;
  await POST(`/delivery/assignments/${encodeURIComponent(id)}/status`, { status, occurredAt: nowIso() });
  toast(`Delivery ${status === "CANCELLED" ? "cancelled" : `marked ${status.replaceAll("_", " ").toLowerCase()}`}`);
  await rerender();
};

/* ---------- Notifications ---------- */

VIEWS.notifications = async (_id, q) => {
  const recipient = q.get("recipient") || "";
  const [list, dir] = await Promise.all([GET(`/notifications${recipient ? `?recipientId=${encodeURIComponent(recipient)}` : ""}`), directory()]);
  const who = (n) => {
    const obj = n.recipientType === "CUSTOMER" ? dir.customer[n.recipientId] : n.recipientType === "RESTAURANT" ? dir.restaurant[n.recipientId] : dir.driver[n.recipientId];
    return obj ? esc(obj.fullName || obj.name) : `<span class="id">${esc(n.recipientId)}</span>`;
  };
  return pageHead({
    title: "Notifications",
    sub: `<span class="num">${list.length}</span> on file · notification service :8083`,
    actions: `<button class="btn btn-ink" data-action="newNotification"><i data-lucide="send"></i>Queue notification</button>`,
  }) + `
  <form class="flex flex-wrap items-end gap-2 mb-5" data-search="recipient">
    <div class="w-full sm:w-80">${field({ id: "q-recipient", label: "Recipient ID", value: recipient, placeholder: "customer-…, restaurant-…, driver-…" })}</div>
    <button class="btn" type="submit">Find</button>${recipient ? `<a class="btn btn-ghost" href="#/notifications">Clear</a>` : ""}
  </form>
  ${ledger("t-notifications", {
    rows: list,
    sort: { key: "createdAt", dir: "desc" },
    empty: { title: recipient ? "Nothing for this recipient" : "No notifications yet", body: "Lifecycle events and manual messages appear here." },
    columns: [
      { key: "subject", label: "Message", render: (n) => `<div class="font-semibold">${esc(n.subject)}</div><div class="text-[13px] text-ink-700 max-w-[52ch]">${esc(n.message)}</div>` },
      { key: "recipientId", label: "Recipient", render: (n) => `<div>${who(n)}</div><div class="text-xs text-ink-500">${esc(n.recipientType.toLowerCase())}</div>` },
      { key: "channel", label: "Channel", render: (n) => `<span class="text-xs font-bold tracking-wider">${esc(n.channel)}</span>` },
      { key: "status", label: "Status", render: (n) => stamp(n.status) },
      { key: "createdAt", label: "Created", render: (n) => `<span class="num text-[13px]">${when(n.createdAt)}</span>` },
      { key: "result", label: "", sortable: false, align: "right", render: (n) => n.status === "PENDING"
        ? `<div class="flex justify-end gap-2"><button class="btn btn-ink btn-sm" data-action="notifyResult" data-id="${esc(n.notificationId)}" data-ok="1">Mark sent</button><button class="btn btn-sm" data-action="notifyResult" data-id="${esc(n.notificationId)}">Failed</button></div>`
        : `<span class="num text-[13px] text-ink-500">${n.sentAt ? when(n.sentAt) : ""}</span>` },
    ],
  })}`;
};

ACTIONS.notifyResult = async ({ id, ok }) => {
  await POST(`/notifications/${encodeURIComponent(id)}/delivery_result`, { successful: Boolean(ok), occurredAt: nowIso() });
  toast(ok ? "Marked as sent" : "Marked as failed");
  await rerender();
};

ACTIONS.newNotification = async ({ type = "CUSTOMER", recipient = "", subject = "" } = {}) => {
  const dir = await directory();
  const options = {
    CUSTOMER: dir.customers.map((c) => ({ value: c.customerId, label: c.fullName })),
    RESTAURANT: dir.restaurants.map((x) => ({ value: x.restaurantId, label: x.name })),
    DRIVER: dir.drivers.map((d) => ({ value: d.driverId, label: d.fullName })),
  };
  openSheet({
    title: "Queue notification", submitLabel: "Queue notification", tint: "green",
    body: `<div class="grid grid-cols-2 gap-4">${select({ id: "recipientType", label: "Recipient type", value: type, placeholder: null, options: [["CUSTOMER", "Customer"], ["RESTAURANT", "Restaurant"], ["DRIVER", "Driver"]].map(([value, label]) => ({ value, label })) })}
      ${select({ id: "channel", label: "Channel", value: "EMAIL", placeholder: null, options: ["EMAIL", "SMS", "PUSH"].map((v) => ({ value: v, label: v })) })}</div>
      <div id="recipient-slot"></div>` +
      field({ id: "subject", label: "Subject", required: true, value: subject }) +
      field({ id: "message", label: "Message", type: "textarea", required: true }),
    onMount(form) {
      const paint = () => { $("#recipient-slot").innerHTML = select({ id: "recipientId", label: "Recipient", required: true, value: recipient, options: options[form.recipientType.value] }); };
      form.recipientType.addEventListener("change", () => { recipient = ""; paint(); });
      paint();
    },
    async onSubmit(d) {
      await POST("/notifications", { notificationId: uid("notification"), recipientType: d.recipientType, recipientId: d.recipientId, channel: d.channel, subject: d.subject.trim(), message: d.message.trim(), createdAt: nowIso() });
      return "Notification queued";
    },
  });
};

/* ---------- Reports ---------- */

VIEWS.reports = async () => {
  const r = await settle({ summary: GET("/admin/reports/summary"), restaurants: GET("/admin/reports/restaurant_statistics"), drivers: GET("/admin/reports/delivery_performance") });
  const s = r.summary.ok ? r.summary.data : null;
  const rest = r.restaurants.ok ? r.restaurants.data : [];
  const drv = r.drivers.ok ? r.drivers.data : [];
  const maxRev = Math.max(1, ...rest.map((x) => Number(x.grossRevenue)));
  const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);

  return pageHead({
    title: "Reports",
    sub: "Reporting projections kept by the admin service :8085. They do not own operational data.",
    actions: `<button class="btn" data-action="saveRestaurantStats"><i data-lucide="store"></i>Save restaurant statistics</button><button class="btn" data-action="saveDriverStats"><i data-lucide="bike"></i>Save delivery performance</button>`,
  }) + `
  <section class="mb-10">${s && Object.values(s).every((v) => Number(v) === 0) ? `<div class="empty"><h3>No report figures saved yet</h3><p class="text-sm max-w-[60ch] mx-auto">The admin service reports only figures saved to it. Use <strong>Save restaurant statistics</strong> or <strong>Save delivery performance</strong> above; live counts are on the <a class="underline" href="#/">Overview</a>.</p></div>` : s ? `<div class="tally sheet-paper overflow-hidden">
    ${[["Gross revenue", money(s.grossRevenue)], ["Total orders", s.totalOrders], ["Completed", s.completedOrders], ["Cancelled", s.cancelledOrders], ["Completion rate", `${pct(s.completedOrders, s.totalOrders)}%`],
       ["Restaurants", s.restaurantCount], ["Active drivers", s.activeDriverCount], ["Deliveries done", s.completedDeliveries]]
      .map(([k, v]) => `<div><div class="label">${k}</div><div class="v">${v}</div></div>`).join("")}</div>` : offline("Platform summary", r.summary.error)}</section>
  <section class="mb-10">
    <h2 class="heading text-xl mb-2">Restaurant statistics</h2>
    ${r.restaurants.ok ? ledger("t-rstats", {
      rows: rest, sort: { key: "grossRevenue", dir: "desc" },
      empty: { title: "No restaurant statistics yet", body: "They fill in as orders complete, or save one manually." },
      columns: [
        { key: "restaurantName", label: "Restaurant", render: (x) => `<span class="font-semibold">${esc(x.restaurantName)}</span>` },
        { key: "totalOrders", label: "Orders", align: "right", render: (x) => `<span class="num">${x.totalOrders}</span>` },
        { key: "completedOrders", label: "Completed", align: "right", render: (x) => `<span class="num">${x.completedOrders}</span>` },
        { key: "cancelledOrders", label: "Cancelled", align: "right", render: (x) => `<span class="num">${x.cancelledOrders}</span>` },
        { key: "rate", label: "Completion", sort: (x) => pct(x.completedOrders, x.totalOrders), render: (x) => `<div class="flex items-center gap-2"><div class="bar flex-1"><span style="width:${pct(x.completedOrders, x.totalOrders)}%"></span></div><span class="num text-xs w-9 text-right">${pct(x.completedOrders, x.totalOrders)}%</span></div>` },
        { key: "grossRevenue", label: "Revenue", align: "right", sort: (x) => Number(x.grossRevenue), render: (x) => `<div class="num">${money(x.grossRevenue)}</div><div class="bar mt-1 ml-auto w-24"><span style="width:${(Number(x.grossRevenue) / maxRev) * 100}%"></span></div>` },
      ],
    }) : offline("Restaurant statistics", r.restaurants.error)}
  </section>
  <section>
    <h2 class="heading text-xl mb-2">Delivery performance</h2>
    ${r.drivers.ok ? ledger("t-dstats", {
      rows: drv, sort: { key: "completedDeliveries", dir: "desc" },
      empty: { title: "No delivery performance yet", body: "It fills in as deliveries complete, or save one manually." },
      columns: [
        { key: "driverName", label: "Driver", render: (x) => `<span class="font-semibold">${esc(x.driverName)}</span>` },
        { key: "assignedDeliveries", label: "Assigned", align: "right", render: (x) => `<span class="num">${x.assignedDeliveries}</span>` },
        { key: "completedDeliveries", label: "Completed", align: "right", render: (x) => `<span class="num">${x.completedDeliveries}</span>` },
        { key: "rate", label: "Completion", sort: (x) => pct(x.completedDeliveries, x.assignedDeliveries), render: (x) => `<div class="flex items-center gap-2"><div class="bar flex-1"><span style="width:${pct(x.completedDeliveries, x.assignedDeliveries)}%"></span></div><span class="num text-xs w-9 text-right">${pct(x.completedDeliveries, x.assignedDeliveries)}%</span></div>` },
        { key: "averageDeliveryMinutes", label: "Avg. minutes", align: "right", sort: (x) => Number(x.averageDeliveryMinutes), render: (x) => `<span class="num">${Number(x.averageDeliveryMinutes).toFixed(1)}</span>` },
      ],
    }) : offline("Delivery performance", r.drivers.error)}
  </section>`;
};

ACTIONS.saveRestaurantStats = async () => {
  const restaurants = await GET("/restaurants");
  const byId = Object.fromEntries(restaurants.map((x) => [x.restaurantId, x]));
  const num = (id, label) => field({ id, label, type: "number", required: true, value: "0", attrs: 'min="0" step="1" inputmode="numeric"' });
  openSheet({
    title: "Save restaurant statistics", submitLabel: "Save statistics", tint: "ink",
    body: select({ id: "restaurantId", label: "Restaurant", required: true, options: restaurants.map((x) => ({ value: x.restaurantId, label: x.name })) }) +
      `<div class="grid grid-cols-3 gap-4">${num("totalOrders", "Total orders")}${num("completedOrders", "Completed")}${num("cancelledOrders", "Cancelled")}</div>` +
      field({ id: "grossRevenue", label: "Gross revenue (N$)", type: "number", required: true, value: "0", attrs: 'min="0" step="0.01" inputmode="decimal"' }),
    async onSubmit(d) {
      const x = byId[d.restaurantId];
      await PUT(`/admin/reports/restaurant_statistics/${encodeURIComponent(x.restaurantId)}`, {
        restaurantId: x.restaurantId, restaurantName: x.name, totalOrders: Number(d.totalOrders), completedOrders: Number(d.completedOrders), cancelledOrders: Number(d.cancelledOrders), grossRevenue: Number(d.grossRevenue),
      });
      return `Statistics saved for ${x.name}`;
    },
  });
};

ACTIONS.saveDriverStats = async () => {
  const drivers = await GET("/delivery/drivers");
  const byId = Object.fromEntries(drivers.map((x) => [x.driverId, x]));
  openSheet({
    title: "Save delivery performance", submitLabel: "Save performance", tint: "ink",
    body: select({ id: "driverId", label: "Driver", required: true, options: drivers.map((x) => ({ value: x.driverId, label: x.fullName })) }) +
      `<div class="grid grid-cols-2 gap-4">${field({ id: "assignedDeliveries", label: "Assigned", type: "number", required: true, value: "0", attrs: 'min="0" step="1"' })}${field({ id: "completedDeliveries", label: "Completed", type: "number", required: true, value: "0", attrs: 'min="0" step="1"' })}</div>` +
      field({ id: "averageDeliveryMinutes", label: "Average delivery minutes", type: "number", required: true, value: "0", attrs: 'min="0" step="0.1" inputmode="decimal"' }),
    async onSubmit(d) {
      const x = byId[d.driverId];
      await PUT(`/admin/reports/delivery_performance/${encodeURIComponent(x.driverId)}`, {
        driverId: x.driverId, driverName: x.fullName, assignedDeliveries: Number(d.assignedDeliveries), completedDeliveries: Number(d.completedDeliveries), averageDeliveryMinutes: Number(d.averageDeliveryMinutes),
      });
      return `Performance saved for ${x.fullName}`;
    },
  });
};

/* ---------- boot ---------- */

paintRail(parseHash().section);
checkHealth();
setInterval(() => { if (!document.hidden) checkHealth(); }, 15000);
route();
