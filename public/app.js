const $ = (id) => document.getElementById(id);
const state = { file: null, scans: [], diagnostics: [], scripts: [], filter: "all" };

function toast(message) {
  const el = $("toast");
  el.textContent = String(message || "");
  el.classList.add("show");
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => el.classList.remove("show"), 2300);
}

function formatBytes(bytes) {
  const n = Number(bytes || 0);
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(2)} GB`;
  if (n >= 1024 ** 2) return `${(n / 1024 ** 2).toFixed(2)} MB`;
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${n} B`;
}

function formatDate(value) {
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleString("pt-BR");
}

async function api(url, options = {}) {
  const response = await fetch(url, options);
  let data = null;
  try { data = await response.json(); } catch {}
  if (!response.ok || !data?.ok) throw new Error(data?.message || `Erro HTTP ${response.status}`);
  return data;
}

function selectTab(name) {
  document.querySelectorAll(".tab").forEach((button) => button.classList.toggle("active", button.dataset.tab === name));
  document.querySelectorAll(".panel").forEach((panel) => panel.classList.toggle("active", panel.id === name));
  if (name === "scans") loadScans();
  if (name === "diagnostics") loadDiagnostics();
}

document.querySelectorAll(".tab").forEach((button) => button.addEventListener("click", () => selectTab(button.dataset.tab)));

function statusClass(status) {
  const s = String(status || "unknown").toLowerCase();
  if (["success", "ok", "completed", "complete"].includes(s)) return "success";
  if (["error", "failed", "failure", "interrupted"].includes(s)) return "error";
  if (["running", "started", "processing"].includes(s)) return "running";
  return "unknown";
}

function renderFilters() {
  const wrap = $("scriptFilters");
  const names = ["all", ...state.scripts];
  wrap.replaceChildren(...names.map((name) => {
    const button = document.createElement("button");
    button.className = `filter-chip${state.filter === name ? " active" : ""}`;
    button.textContent = name === "all" ? "Todos" : name;
    button.addEventListener("click", () => { state.filter = name; renderFilters(); renderDiagnostics(); });
    return button;
  }));
}

function diagnosticCard(item) {
  const card = document.createElement("article");
  card.className = "file-card diagnostic-card";
  const left = document.createElement("div");
  const top = document.createElement("div");
  top.className = "card-title-row";
  const title = document.createElement("h3");
  title.textContent = item.script;
  const pill = document.createElement("span");
  pill.className = `state-pill ${statusClass(item.status)}`;
  pill.textContent = String(item.status || "unknown").toUpperCase();
  top.append(title, pill);
  const meta = document.createElement("div");
  meta.className = "file-meta";
  [`Run: ${item.runId}`, `Etapa: ${item.phase || "—"}`, formatDate(item.updatedAt)].forEach((text) => {
    const span = document.createElement("span"); span.textContent = text; meta.appendChild(span);
  });
  if (item.message) { const msg = document.createElement("p"); msg.className = "card-message"; msg.textContent = item.message; left.append(top, meta, msg); }
  else left.append(top, meta);
  const actions = document.createElement("div"); actions.className = "file-actions";
  const view = document.createElement("button"); view.textContent = "Abrir"; view.addEventListener("click", () => viewDiagnostic(item));
  const download = document.createElement("a"); download.textContent = "Baixar"; download.href = `/api/runtime-diagnostics/${encodeURIComponent(item.script)}/${encodeURIComponent(item.runId)}/download`;
  actions.append(view, download); card.append(left, actions); return card;
}

function renderDiagnostics() {
  const filtered = state.filter === "all" ? state.diagnostics : state.diagnostics.filter((d) => d.script === state.filter);
  $("diagnosticList").replaceChildren(...filtered.map(diagnosticCard));
  $("diagnosticEmpty").classList.toggle("hidden", filtered.length > 0);
  $("diagTotal").textContent = String(filtered.length);
  $("diagSuccess").textContent = String(filtered.filter((d) => statusClass(d.status) === "success").length);
  $("diagErrors").textContent = String(filtered.filter((d) => statusClass(d.status) === "error").length);
  $("diagRunning").textContent = String(filtered.filter((d) => statusClass(d.status) === "running").length);
}

async function loadDiagnostics() {
  try {
    $("refreshDiagnostics").disabled = true;
    if (!state.scripts.length) {
      const scripts = await api("/api/runtime-diagnostics/scripts");
      state.scripts = scripts.scripts || [];
      renderFilters();
    }
    const data = await api("/api/runtime-diagnostics");
    state.diagnostics = data.diagnostics || [];
    renderDiagnostics();
  } catch (error) { toast(error.message || "Erro ao carregar diagnósticos"); }
  finally { $("refreshDiagnostics").disabled = false; }
}

async function viewDiagnostic(item) {
  try {
    const data = await api(`/api/runtime-diagnostics/${encodeURIComponent(item.script)}/${encodeURIComponent(item.runId)}`);
    $("diagnosticViewerTitle").textContent = `${item.script} • ${item.runId}`;
    $("diagnosticViewerMeta").textContent = `${String(data.diagnostic?.status || "unknown").toUpperCase()} • ${formatDate(data.diagnostic?.updatedAt)}`;
    $("diagnosticViewerText").textContent = JSON.stringify(data.diagnostic, null, 2);
    $("downloadRuntimeDiagnostic").href = `/api/runtime-diagnostics/${encodeURIComponent(item.script)}/${encodeURIComponent(item.runId)}/download`;
    $("diagnosticViewer").classList.remove("hidden");
    $("diagnosticViewer").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) { toast(error.message || "Erro ao abrir diagnóstico"); }
}

function scanCard(item) {
  const card = document.createElement("article"); card.className = "file-card";
  const left = document.createElement("div");
  const title = document.createElement("h3"); title.textContent = item.name;
  const meta = document.createElement("div"); meta.className = "file-meta";
  [`Área: ${item.area || "—"}`, formatBytes(item.bytes), item.records == null ? null : `${item.records} registros`, formatDate(item.modifiedAt)].filter(Boolean).forEach((text) => { const span = document.createElement("span"); span.textContent = text; meta.appendChild(span); });
  left.append(title, meta);
  const actions = document.createElement("div"); actions.className = "file-actions";
  const view = document.createElement("button"); view.textContent = "Visualizar"; view.addEventListener("click", () => viewScan(item));
  const download = document.createElement("a"); download.textContent = "Baixar"; download.href = `/api/scans/${encodeURIComponent(item.name)}/download`;
  actions.append(view, download); card.append(left, actions); return card;
}

async function loadScans() {
  try {
    $("refreshScans").disabled = true;
    const data = await api("/api/scans");
    state.scans = data.files || [];
    $("scanList").replaceChildren(...state.scans.map(scanCard));
    $("scanEmpty").classList.toggle("hidden", state.scans.length > 0);
  } catch (error) { toast(error.message || "Erro ao carregar arquivos do Scam"); }
  finally { $("refreshScans").disabled = false; }
}

async function viewScan(item) {
  try {
    const data = await api(`/api/scans/${encodeURIComponent(item.name)}`);
    $("viewerTitle").textContent = data.name;
    $("viewerMeta").textContent = `${formatBytes(data.bytes)}${data.truncated ? " • visualização limitada; download contém o arquivo completo" : ""}`;
    $("viewerText").textContent = data.content;
    $("downloadScan").href = `/api/scans/${encodeURIComponent(item.name)}/download`;
    $("scanViewer").classList.remove("hidden");
    $("scanViewer").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) { toast(error.message || "Erro ao visualizar arquivo"); }
}

function setFile(file) {
  state.file = file || null;
  $("fileLabel").textContent = file ? file.name : "Escolher script";
  $("diagnoseBtn").disabled = !file;
  $("diagResult").classList.add("hidden");
}

$("scriptFile").addEventListener("change", (event) => setFile(event.target.files?.[0]));
const dropzone = $("dropzone");
["dragenter", "dragover"].forEach((name) => dropzone.addEventListener(name, (e) => { e.preventDefault(); dropzone.classList.add("drag"); }));
["dragleave", "drop"].forEach((name) => dropzone.addEventListener(name, (e) => { e.preventDefault(); dropzone.classList.remove("drag"); }));
dropzone.addEventListener("drop", (event) => setFile(event.dataTransfer?.files?.[0]));

$("diagnoseBtn").addEventListener("click", async () => {
  if (!state.file) return;
  const button = $("diagnoseBtn");
  try {
    button.disabled = true; $("diagProgress").classList.remove("hidden"); $("diagResult").classList.add("hidden");
    const content = await state.file.text();
    const data = await api("/api/diagnose", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ filename: state.file.name, content }) });
    $("diagTitle").textContent = `${data.filename} / diagnóstico`;
    $("diagText").textContent = data.diagnostic;
    $("downloadDiagnostic").href = data.downloadUrl;
    $("downloadDiagnostic").setAttribute("download", data.downloadName || "diagnostico.txt");
    $("diagResult").classList.remove("hidden"); toast("Diagnóstico concluído");
  } catch (error) { toast(error.message || "Erro no diagnóstico"); }
  finally { $("diagProgress").classList.add("hidden"); button.disabled = !state.file; }
});

$("refreshDiagnostics").addEventListener("click", loadDiagnostics);
$("refreshScans").addEventListener("click", loadScans);

(async () => {
  try {
    await api("/api/health");
    $("serverStatus").classList.add("ok");
    $("serverStatus").innerHTML = "<span></span> online";
    await loadDiagnostics();
  } catch { $("serverStatus").innerHTML = "<span></span> offline"; }
})();
