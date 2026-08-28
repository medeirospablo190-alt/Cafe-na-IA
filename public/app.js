const $ = (id) => document.getElementById(id);

const state = { scans: [], sources: [] };

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
  document.querySelectorAll(".tab").forEach((button) => {
    button.classList.toggle("active", button.dataset.tab === name);
  });
  document.querySelectorAll(".panel").forEach((panel) => {
    panel.classList.toggle("active", panel.id === name);
  });
  if (name === "scanner") loadScans();
  if (name === "diagnostic") loadSources();
}

document.querySelectorAll(".tab").forEach((button) => {
  button.addEventListener("click", () => selectTab(button.dataset.tab));
});

function monitoredLoadstring(source) {
  const loaderUrl = `${location.origin}/api/diagnostic-sources/${encodeURIComponent(source.id)}/loader.lua`;
  return `loadstring(game:HttpGet(${JSON.stringify(loaderUrl)}))()`;
}

async function copyText(text) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }
  const area = document.createElement("textarea");
  area.value = text;
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  document.execCommand("copy");
  area.remove();
}

function statusInfo(status) {
  switch (status) {
    case "success": return { label: "SUCESSO", cls: "success" };
    case "error": return { label: "ERRO", cls: "error" };
    case "running": return { label: "EXECUTANDO", cls: "running" };
    default: return { label: "NUNCA EXECUTADO", cls: "never" };
  }
}

function sourceCard(source) {
  const card = document.createElement("article");
  card.className = "source-card runtime-source";

  const info = document.createElement("div");
  info.className = "source-info";

  const top = document.createElement("div");
  top.className = "runtime-top";
  const title = document.createElement("h3");
  title.textContent = source.filename || "script.lua";
  const status = statusInfo(source.runtimeStatus);
  const badge = document.createElement("span");
  badge.className = `runtime-badge ${status.cls}`;
  badge.textContent = status.label;
  top.append(title, badge);

  const url = document.createElement("div");
  url.className = "source-url";
  url.textContent = source.rawUrl || source.input || "";

  const details = document.createElement("div");
  details.className = "runtime-details";
  const time = document.createElement("span");
  time.textContent = source.lastRuntimeAt ? `Última execução: ${formatDate(source.lastRuntimeAt)}` : "Aguardando primeira execução";
  details.appendChild(time);

  if (source.lastRuntimeLine) {
    const line = document.createElement("span");
    line.className = "runtime-line";
    line.textContent = `Linha do erro: ${source.lastRuntimeLine}`;
    details.appendChild(line);
  }

  if (source.lastRuntimeError) {
    const error = document.createElement("pre");
    error.className = "runtime-error";
    error.textContent = source.lastRuntimeError;
    details.appendChild(error);
  }

  const history = Array.isArray(source.runtimeHistory) ? source.runtimeHistory.slice(0, 5) : [];
  if (history.length) {
    const historyBox = document.createElement("div");
    historyBox.className = "runtime-history";
    const historyTitle = document.createElement("strong");
    historyTitle.textContent = "Execuções recentes";
    historyBox.appendChild(historyTitle);
    history.forEach((run) => {
      const row = document.createElement("div");
      row.className = "runtime-history-row";
      const runStatus = statusInfo(run.status);
      row.innerHTML = `<span class="mini-status ${runStatus.cls}">${runStatus.label}</span><span>${formatDate(run.at)}</span><span>${run.line ? `linha ${run.line}` : run.phase || "runtime"}</span>`;
      historyBox.appendChild(row);
    });
    details.appendChild(historyBox);
  }

  info.append(top, url, details);

  const actions = document.createElement("div");
  actions.className = "source-actions runtime-actions";

  const copy = document.createElement("button");
  copy.className = "source-diagnose";
  copy.textContent = "Copiar loadstring monitorado";
  copy.addEventListener("click", async () => {
    try {
      await copyText(monitoredLoadstring(source));
      toast("Loadstring monitorado copiado");
    } catch {
      toast("Não foi possível copiar");
    }
  });

  if (source.lastDownloadUrl) {
    const download = document.createElement("a");
    download.className = "source-download";
    download.href = source.lastDownloadUrl;
    download.textContent = "Baixar último diagnóstico";
    actions.appendChild(download);
  }

  const remove = document.createElement("button");
  remove.className = "source-remove";
  remove.textContent = "Remover monitoramento";
  remove.addEventListener("click", async () => {
    if (!confirm(`Remover ${source.filename}? Novas execuções deixarão de ser registradas.`)) return;
    try {
      remove.disabled = true;
      await api(`/api/diagnostic-sources/${encodeURIComponent(source.id)}`, { method: "DELETE" });
      await loadSources();
      toast("Monitoramento removido");
    } catch (error) {
      toast(error.message || "Erro ao remover fonte");
      remove.disabled = false;
    }
  });

  actions.prepend(copy);
  actions.append(remove);
  card.append(info, actions);
  return card;
}

async function loadSources() {
  const list = $("sourceList");
  try {
    const data = await api("/api/diagnostic-sources");
    state.sources = data.sources || [];
    list.replaceChildren(...state.sources.map(sourceCard));
    $("sourceEmpty").classList.toggle("hidden", state.sources.length > 0);
  } catch (error) {
    toast(error.message || "Erro ao carregar fontes");
  }
}

$("saveSourceBtn").addEventListener("click", async () => {
  const input = $("sourceInput").value.trim();
  if (!input) return toast("Cole um loadstring ou link do GitHub");
  const button = $("saveSourceBtn");
  try {
    button.disabled = true;
    button.textContent = "Salvando...";
    const data = await api("/api/diagnostic-sources", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ input })
    });
    $("sourceInput").value = "";
    await loadSources();
    toast(data.alreadyExists ? "Fonte já estava salva" : "Monitoramento salvo");
  } catch (error) {
    toast(error.message || "Erro ao salvar fonte");
  } finally {
    button.disabled = false;
    button.textContent = "Salvar e monitorar";
  }
});

function scanCard(item) {
  const card = document.createElement("article");
  card.className = "file-card";
  const left = document.createElement("div");
  const title = document.createElement("h3");
  title.textContent = item.name;
  const meta = document.createElement("div");
  meta.className = "file-meta";
  [`Área: ${item.area || "—"}`, formatBytes(item.bytes), item.records == null ? null : `${item.records} registros`, formatDate(item.modifiedAt)]
    .filter(Boolean).forEach((text) => { const span = document.createElement("span"); span.textContent = text; meta.appendChild(span); });
  left.append(title, meta);

  const actions = document.createElement("div");
  actions.className = "file-actions";
  const view = document.createElement("button");
  view.textContent = "Visualizar";
  view.addEventListener("click", () => viewScan(item));
  const download = document.createElement("a");
  download.textContent = "Baixar";
  download.href = `/api/scans/${encodeURIComponent(item.name)}/download`;
  actions.append(view, download);
  card.append(left, actions);
  return card;
}

async function loadScans() {
  const list = $("scanList");
  try {
    $("refreshBtn").disabled = true;
    const data = await api("/api/scans");
    state.scans = data.files || [];
    list.replaceChildren(...state.scans.map(scanCard));
    $("scanEmpty").classList.toggle("hidden", state.scans.length > 0);
  } catch (error) {
    toast(error.message || "Erro ao carregar arquivos");
  } finally {
    $("refreshBtn").disabled = false;
  }
}

async function viewScan(item) {
  try {
    const data = await api(`/api/scans/${encodeURIComponent(item.name)}`);
    $("viewerTitle").textContent = data.name;
    $("viewerMeta").textContent = `${formatBytes(data.bytes)}${data.truncated ? " • visualização limitada; o download contém o arquivo completo" : ""}`;
    $("viewerText").textContent = data.content;
    $("downloadScan").href = `/api/scans/${encodeURIComponent(item.name)}/download`;
    $("scanViewer").classList.remove("hidden");
    $("scanViewer").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) {
    toast(error.message || "Erro ao visualizar arquivo");
  }
}

$("refreshBtn").addEventListener("click", loadScans);

setInterval(() => {
  if ($("diagnostic").classList.contains("active")) loadSources();
}, 4000);

(async () => {
  loadSources();
  try {
    await api("/api/health");
    $("serverStatus").classList.add("ok");
    $("serverStatus").innerHTML = "<span></span> online";
  } catch {
    $("serverStatus").innerHTML = "<span></span> offline";
  }
})();
