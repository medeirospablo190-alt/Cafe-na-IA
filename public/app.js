const $ = (id) => document.getElementById(id);

const state = {
  files: []
};

function toast(message) {
  const element = $("toast");
  if (!element) return;

  element.textContent = String(message || "");
  element.classList.add("show");

  clearTimeout(window.__cafeinaToast);

  window.__cafeinaToast = setTimeout(() => {
    element.classList.remove("show");
  }, 2300);
}

function formatBytes(bytes) {
  const number = Number(bytes || 0);

  if (number >= 1024 ** 3) {
    return `${(number / 1024 ** 3).toFixed(2)} GB`;
  }

  if (number >= 1024 ** 2) {
    return `${(number / 1024 ** 2).toFixed(2)} MB`;
  }

  if (number >= 1024) {
    return `${(number / 1024).toFixed(1)} KB`;
  }

  return `${number} B`;
}

function formatDate(value) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  return date.toLocaleString("pt-BR");
}

async function api(url, options = {}) {
  const response = await fetch(url, options);

  let data = null;

  try {
    data = await response.json();
  } catch {}

  if (
    !response.ok ||
    !(data?.ok || data?.success)
  ) {
    throw new Error(
      data?.message ||
      `Erro HTTP ${response.status}`
    );
  }

  return data;
}

function updateSummary(files, totalBytes) {
  $("fileCount").textContent =
    String(files.length);

  $("totalSize").textContent =
    formatBytes(totalBytes);

  $("uploadState").textContent =
    files.length ? "PRONTO" : "AGUARDANDO";
}

function fileCard(item) {
  const card = document.createElement("article");
  card.className = "file-card";

  const left = document.createElement("div");

  const title = document.createElement("h3");
  title.textContent = item.name;

  const meta = document.createElement("div");
  meta.className = "file-meta";

  const values = [
    item.area ? `Área: ${item.area}` : null,
    item.placeId ? `PlaceId: ${item.placeId}` : null,
    formatBytes(item.bytes),
    item.records == null
      ? null
      : `${item.records} registros`,
    formatDate(item.modifiedAt)
  ].filter(Boolean);

  for (const value of values) {
    const span = document.createElement("span");
    span.textContent = value;
    meta.appendChild(span);
  }

  left.append(title, meta);

  const actions =
    document.createElement("div");

  actions.className = "file-actions";

  const view = document.createElement("button");
  view.type = "button";
  view.textContent = "Visualizar";

  view.addEventListener("click", () => {
    viewFile(item);
  });

  const download =
    document.createElement("a");

  download.textContent = "Baixar";
  download.href =
    item.downloadUrl ||
    `/files/${encodeURIComponent(item.name)}`;

  actions.append(view, download);
  card.append(left, actions);

  return card;
}

async function loadFiles() {
  const list = $("scanList");
  const refresh = $("refreshBtn");

  try {
    refresh.disabled = true;

    const data = await api("/api/files");
    state.files = data.files || [];

    list.replaceChildren(
      ...state.files.map(fileCard)
    );

    $("scanEmpty").classList.toggle(
      "hidden",
      state.files.length > 0
    );

    updateSummary(
      state.files,
      Number(data.totalBytes || 0)
    );
  } catch (error) {
    toast(
      error.message ||
      "Erro ao carregar arquivos"
    );
  } finally {
    refresh.disabled = false;
  }
}

async function viewFile(item) {
  try {
    const url =
      item.previewUrl ||
      `/api/files/${encodeURIComponent(item.name)}/preview`;

    const data = await api(url);

    $("viewerTitle").textContent =
      data.name;

    $("viewerMeta").textContent =
      `${formatBytes(data.bytes)}` +
      (
        data.truncated
          ? " • visualização parcial; o download contém o arquivo completo"
          : ""
      );

    $("viewerText").textContent =
      data.content;

    $("downloadScan").href =
      item.downloadUrl ||
      `/files/${encodeURIComponent(item.name)}`;

    $("scanViewer").classList.remove(
      "hidden"
    );

    $("scanViewer").scrollIntoView({
      behavior: "smooth",
      block: "start"
    });
  } catch (error) {
    toast(
      error.message ||
      "Erro ao visualizar arquivo"
    );
  }
}

async function checkHealth() {
  const status = $("serverStatus");

  try {
    const data = await api("/health");

    status.classList.add("ok");
    status.innerHTML =
      "<span></span> online";

    if (!data.scannerUpload) {
      status.classList.remove("ok");
      status.innerHTML =
        "<span></span> upload indisponível";
    }
  } catch {
    status.classList.remove("ok");
    status.innerHTML =
      "<span></span> offline";
  }
}

$("refreshBtn")?.addEventListener(
  "click",
  loadFiles
);

$("closeViewer")?.addEventListener(
  "click",
  () => {
    $("scanViewer").classList.add(
      "hidden"
    );
  }
);

document.addEventListener(
  "DOMContentLoaded",
  async () => {
    await Promise.allSettled([
      checkHealth(),
      loadFiles()
    ]);
  }
);
