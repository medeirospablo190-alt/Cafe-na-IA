const state = {
  files: [],
  diagnostics: [],
  diagnosticFilter: "all",
  diagnosticTimer: null
};

// ============================================================
// HELPERS
// ============================================================

function $(id) {
  return document.getElementById(id);
}

function showToast(message) {
  const toast = $("toast");

  if (!toast) {
    return;
  }

  toast.textContent =
    String(message || "");

  toast.classList.add("show");

  clearTimeout(
    window.__cafeinaToastTimer
  );

  window.__cafeinaToastTimer =
    setTimeout(() => {
      toast.classList.remove(
        "show"
      );
    }, 2400);
}

function formatBytes(bytes) {
  const number =
    Number(bytes || 0);

  if (!Number.isFinite(number)) {
    return "0 B";
  }

  if (number < 1024) {
    return `${number} B`;
  }

  if (number < 1024 * 1024) {
    return `${(
      number / 1024
    ).toFixed(1)} KB`;
  }

  if (
    number <
    1024 * 1024 * 1024
  ) {
    return `${(
      number /
      (1024 * 1024)
    ).toFixed(1)} MB`;
  }

  return `${(
    number /
    (1024 * 1024 * 1024)
  ).toFixed(2)} GB`;
}

function formatDate(value) {
  if (!value) {
    return "—";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return String(value);
  }

  try {
    return date.toLocaleString(
      "pt-BR"
    );
  } catch {
    return date.toString();
  }
}

function escapeHtml(value) {
  return String(
    value ?? ""
  )
    .replaceAll(
      "&",
      "&amp;"
    )
    .replaceAll(
      "<",
      "&lt;"
    )
    .replaceAll(
      ">",
      "&gt;"
    )
    .replaceAll(
      '"',
      "&quot;"
    )
    .replaceAll(
      "'",
      "&#039;"
    );
}

async function copyText(text) {
  const value =
    String(text || "");

  if (!value) {
    showToast(
      "Nada para copiar."
    );

    return false;
  }

  try {
    if (
      navigator.clipboard &&
      window.isSecureContext
    ) {
      await navigator.clipboard
        .writeText(value);

      showToast(
        "Copiado."
      );

      return true;
    }
  } catch {
    // fallback abaixo
  }

  try {
    const textarea =
      document.createElement(
        "textarea"
      );

    textarea.value =
      value;

    textarea.setAttribute(
      "readonly",
      ""
    );

    textarea.style.position =
      "fixed";

    textarea.style.opacity =
      "0";

    document.body.appendChild(
      textarea
    );

    textarea.select();

    document.execCommand(
      "copy"
    );

    textarea.remove();

    showToast(
      "Copiado."
    );

    return true;

  } catch (error) {
    console.error(error);

    showToast(
      "Não foi possível copiar."
    );

    return false;
  }
}

async function fetchJson(
  url,
  options = {}
) {
  const response =
    await fetch(
      url,
      {
        cache:
          "no-store",

        ...options,

        headers: {
          Accept:
            "application/json",

          ...(
            options.headers ||
            {}
          )
        }
      }
    );

  let data = null;

  try {
    data =
      await response.json();
  } catch {
    data = null;
  }

  if (!response.ok) {
    const message =
      data?.message ||
      data?.error ||
      `Erro HTTP ${response.status}`;

    throw new Error(
      message
    );
  }

  return data || {};
}

// ============================================================
// NAVEGAÇÃO
// ============================================================

function setActivePage(
  pageName
) {
  const pages =
    document.querySelectorAll(
      ".page"
    );

  const buttons =
    document.querySelectorAll(
      "[data-page]"
    );

  pages.forEach(page => {
    page.classList.remove(
      "active"
    );
  });

  buttons.forEach(button => {
    button.classList.remove(
      "active"
    );
  });

  const page =
    document.getElementById(
      `page-${pageName}`
    );

  if (page) {
    page.classList.add(
      "active"
    );
  }

  buttons.forEach(button => {
    if (
      button.dataset.page ===
      pageName
    ) {
      button.classList.add(
        "active"
      );
    }
  });

  try {
    localStorage.setItem(
      "cafeina-page",
      pageName
    );
  } catch {
    // ignore
  }

  if (
    pageName ===
    "files"
  ) {
    loadFiles();
  }

  if (
    pageName ===
    "diagnostics"
  ) {
    loadDiagnostics();
  }
}

function initNavigation() {
  const buttons =
    document.querySelectorAll(
      "[data-page]"
    );

  buttons.forEach(button => {
    button.addEventListener(
      "click",
      () => {
        const page =
          button.dataset.page;

        if (page) {
          setActivePage(
            page
          );
        }
      }
    );
  });

  let savedPage =
    "home";

  try {
    savedPage =
      localStorage.getItem(
        "cafeina-page"
      ) ||
      "home";
  } catch {
    savedPage =
      "home";
  }

  const exists =
    document.getElementById(
      `page-${savedPage}`
    );

  setActivePage(
    exists
      ? savedPage
      : "home"
  );
}

// ============================================================
// HEALTH
// ============================================================

async function checkHealth() {
  const serverStatus =
    $("statusServer");

  const filesStatus =
    $("statusFiles");

  const diagnosticsStatus =
    $("statusDiagnostics");

  const aiStatus =
    $("statusAI");

  try {
    const data =
      await fetchJson(
        "/health"
      );

    if (serverStatus) {
      serverStatus.textContent =
        data.ok
          ? "Online"
          : "Erro";

      serverStatus.className =
        `status-value ${
          data.ok
            ? "good"
            : "bad"
        }`;
    }

    if (filesStatus) {
      filesStatus.textContent =
        data.files
          ? "Disponível"
          : "Indisponível";

      filesStatus.className =
        `status-value ${
          data.files
            ? "good"
            : "warn"
        }`;
    }

    if (
      diagnosticsStatus
    ) {
      diagnosticsStatus
        .textContent =
          data.diagnostics
            ? "Disponível"
            : "Indisponível";

      diagnosticsStatus
        .className =
          `status-value ${
            data.diagnostics
              ? "good"
              : "warn"
          }`;
    }

    if (aiStatus) {
      aiStatus.textContent =
        data.ai === true
          ? "Disponível"
          : "Não configurada";

      aiStatus.className =
        `status-value ${
          data.ai === true
            ? "good"
            : "warn"
        }`;
    }

    const aiDescription =
      $("aiDescription");

    if (aiDescription) {
      aiDescription.textContent =
        data.ai === true
          ? "Integração disponível no backend. A chave permanece protegida no servidor."
          : "OPENAI_API_KEY ainda não está configurada no backend.";
    }

    const uptime =
      $("statusUptime");

    if (uptime) {
      const seconds =
        Math.floor(
          Number(
            data.uptime ||
            0
          )
        );

      const minutes =
        Math.floor(
          seconds / 60
        );

      uptime.textContent =
        minutes > 0
          ? `${minutes} min`
          : `${seconds} s`;
    }

  } catch (error) {
    console.error(
      "Health error:",
      error
    );

    if (serverStatus) {
      serverStatus.textContent =
        "Offline";

      serverStatus.className =
        "status-value bad";
    }

    if (filesStatus) {
      filesStatus.textContent =
        "Indisponível";

      filesStatus.className =
        "status-value bad";
    }

    if (
      diagnosticsStatus
    ) {
      diagnosticsStatus
        .textContent =
          "Indisponível";

      diagnosticsStatus
        .className =
          "status-value bad";
    }

    if (aiStatus) {
      aiStatus.textContent =
        "Indisponível";

      aiStatus.className =
        "status-value bad";
    }
  }
}

// ============================================================
// ARQUIVOS
// ============================================================

function renderFiles() {
  const container =
    $("filesList");

  const count =
    $("filesCount");

  const total =
    $("filesTotal");

  if (count) {
    count.textContent =
      String(
        state.files.length
      );
  }

  if (total) {
    const totalBytes =
      state.files.reduce(
        (
          sum,
          file
        ) =>
          sum +
          Number(
            file.bytes ||
            file.size ||
            0
          ),
        0
      );

    total.textContent =
      formatBytes(
        totalBytes
      );
  }

  if (!container) {
    return;
  }

  container.innerHTML =
    "";

  if (
    state.files.length ===
    0
  ) {
    const empty =
      document.createElement(
        "div"
      );

    empty.className =
      "empty-state";

    empty.innerHTML = `
      <strong>Nenhum arquivo disponível</strong>
      <span>
        Os arquivos enviados pelo Explorer aparecerão aqui.
      </span>
    `;

    container.appendChild(
      empty
    );

    return;
  }

  state.files.forEach(
    file => {
      const item =
        document.createElement(
          "article"
        );

      item.className =
        "file-item";

      const name =
        String(
          file.name ||
          file.filename ||
          "arquivo.json"
        );

      const bytes =
        Number(
          file.bytes ||
          file.size ||
          0
        );

      const updated =
        file.updatedAt ||
        file.createdAt ||
        "";

      const downloadUrl =
        file.downloadUrl ||
        `/files/${encodeURIComponent(
          name
        )}`;

      item.innerHTML = `
        <div class="file-info">
          <strong class="file-name">
            ${escapeHtml(name)}
          </strong>

          <div class="file-meta">
            <span>
              ${escapeHtml(
                formatBytes(
                  bytes
                )
              )}
            </span>

            <span>
              ${escapeHtml(
                formatDate(
                  updated
                )
              )}
            </span>
          </div>
        </div>

        <div class="file-actions">
          <a
            class="btn primary"
            href="${escapeHtml(
              downloadUrl
            )}"
            download
          >
            Baixar
          </a>

          <button
            class="btn"
            type="button"
            data-copy-link
          >
            Copiar link
          </button>
        </div>
      `;

      const copyButton =
        item.querySelector(
          "[data-copy-link]"
        );

      if (copyButton) {
        copyButton
          .addEventListener(
            "click",
            () => {
              const fullUrl =
                new URL(
                  downloadUrl,
                  window.location
                    .origin
                ).href;

              copyText(
                fullUrl
              );
            }
          );
      }

      container.appendChild(
        item
      );
    }
  );
}

async function loadFiles() {
  const container =
    $("filesList");

  if (container) {
    container.innerHTML = `
      <div class="empty-state">
        <strong>Carregando arquivos...</strong>
      </div>
    `;
  }

  try {
    const data =
      await fetchJson(
        "/api/files"
      );

    state.files =
      Array.isArray(
        data.files
      )
        ? data.files
        : [];

    renderFiles();

  } catch (error) {
    console.error(
      "Files error:",
      error
    );

    state.files = [];

    if (container) {
      container.innerHTML = `
        <div class="empty-state error">
          <strong>
            Não foi possível carregar os arquivos
          </strong>

          <span>
            ${escapeHtml(
              error.message
            )}
          </span>
        </div>
      `;
    }
  }
}

// ============================================================
// DIAGNÓSTICOS
// ============================================================

function getDiagnosticType(
  diagnostic
) {
  const type =
    String(
      diagnostic?.type ||
      "runtime"
    )
      .trim()
      .toLowerCase();

  if (
    type.includes(
      "warn"
    )
  ) {
    return "warning";
  }

  if (
    type.includes(
      "error"
    )
  ) {
    return "error";
  }

  if (
    type.includes(
      "fatal"
    )
  ) {
    return "error";
  }

  if (
    type.includes(
      "info"
    )
  ) {
    return "info";
  }

  return type ||
    "runtime";
}

function diagnosticMatchesFilter(
  diagnostic
) {
  const filter =
    state.diagnosticFilter;

  if (
    !filter ||
    filter === "all"
  ) {
    return true;
  }

  return (
    getDiagnosticType(
      diagnostic
    ) === filter
  );
}

function diagnosticToText(
  diagnostic
) {
  const lines = [];

  lines.push(
    "CAFEÍNA • DIAGNÓSTICO"
  );

  lines.push(
    "=============================="
  );

  lines.push(
    `Tipo: ${
      diagnostic.type ||
      "runtime"
    }`
  );

  if (
    diagnostic.scriptName
  ) {
    lines.push(
      `Script: ${diagnostic.scriptName}`
    );
  }

  if (
    diagnostic.version
  ) {
    lines.push(
      `Versão: ${diagnostic.version}`
    );
  }

  if (
    diagnostic.placeId
  ) {
    lines.push(
      `PlaceId: ${diagnostic.placeId}`
    );
  }

  if (
    diagnostic.gameId
  ) {
    lines.push(
      `GameId: ${diagnostic.gameId}`
    );
  }

  if (
    diagnostic.executor
  ) {
    lines.push(
      `Executor: ${diagnostic.executor}`
    );
  }

  if (
    diagnostic.receivedAt
  ) {
    lines.push(
      `Recebido: ${formatDate(
        diagnostic.receivedAt
      )}`
    );
  }

  lines.push("");

  lines.push(
    "MENSAGEM"
  );

  lines.push(
    String(
      diagnostic.message ||
      "Sem mensagem."
    )
  );

  if (
    diagnostic.trace
  ) {
    lines.push("");

    lines.push(
      "TRACE"
    );

    lines.push(
      String(
        diagnostic.trace
      )
    );
  }

  if (
    diagnostic.scriptUrl
  ) {
    lines.push("");

    lines.push(
      `URL: ${diagnostic.scriptUrl}`
    );
  }

  return lines.join(
    "\n"
  );
}

function renderDiagnostics() {
  const container =
    $("diagnosticsList");

  const count =
    $("diagnosticsCount");

  if (!container) {
    return;
  }

  const filtered =
    state.diagnostics.filter(
      diagnosticMatchesFilter
    );

  if (count) {
    count.textContent =
      String(
        state.diagnostics
          .length
      );
  }

  container.innerHTML =
    "";

  if (
    filtered.length ===
    0
  ) {
    const empty =
      document.createElement(
        "div"
      );

    empty.className =
      "empty-state";

    empty.innerHTML = `
      <strong>
        Nenhum diagnóstico
      </strong>

      <span>
        Os erros enviados pelo script aparecerão aqui.
      </span>
    `;

    container.appendChild(
      empty
    );

    return;
  }

  filtered
    .slice()
    .reverse()
    .forEach(
      diagnostic => {
        const item =
          document.createElement(
            "article"
          );

        const type =
          getDiagnosticType(
            diagnostic
          );

        item.className =
          `diagnostic-item diagnostic-${type}`;

        const title =
          diagnostic.scriptName ||
          diagnostic.type ||
          "Diagnóstico";

        const message =
          diagnostic.message ||
          "Sem mensagem.";

        item.innerHTML = `
          <div class="diagnostic-head">
            <div>
              <span class="diagnostic-type">
                ${escapeHtml(
                  type
                )}
              </span>

              <strong>
                ${escapeHtml(
                  title
                )}
              </strong>
            </div>

            <span class="diagnostic-date">
              ${escapeHtml(
                formatDate(
                  diagnostic
                    .receivedAt
                )
              )}
            </span>
          </div>

          <pre class="diagnostic-message">${escapeHtml(
            message
          )}</pre>

          ${
            diagnostic.trace
              ? `
                <details class="diagnostic-trace">
                  <summary>
                    Ver detalhes
                  </summary>

                  <pre>${escapeHtml(
                    diagnostic.trace
                  )}</pre>
                </details>
              `
              : ""
          }

          <div class="diagnostic-actions">
            <button
              class="btn primary"
              type="button"
              data-copy-diagnostic
            >
              Copiar diagnóstico
            </button>
          </div>
        `;

        const copy =
          item.querySelector(
            "[data-copy-diagnostic]"
          );

        if (copy) {
          copy.addEventListener(
            "click",
            () => {
              copyText(
                diagnosticToText(
                  diagnostic
                )
              );
            }
          );
        }

        container.appendChild(
          item
        );
      }
    );
}

async function loadDiagnostics() {
  const container =
    $("diagnosticsList");

  try {
    const data =
      await fetchJson(
        "/api/diagnostics"
      );

    state.diagnostics =
      Array.isArray(
        data.diagnostics
      )
        ? data.diagnostics
        : [];

    renderDiagnostics();

  } catch (error) {
    console.error(
      "Diagnostics error:",
      error
    );

    if (container) {
      container.innerHTML = `
        <div class="empty-state error">
          <strong>
            Erro ao carregar diagnósticos
          </strong>

          <span>
            ${escapeHtml(
              error.message
            )}
          </span>
        </div>
      `;
    }
  }
}

async function clearDiagnostics() {
  const button =
    $("clearDiagnostics");

  if (button) {
    button.disabled =
      true;
  }

  try {
    await fetchJson(
      "/api/diagnostics",
      {
        method:
          "DELETE"
      }
    );

    state.diagnostics =
      [];

    renderDiagnostics();

    showToast(
      "Diagnósticos apagados."
    );

  } catch (error) {
    console.error(
      error
    );

    showToast(
      error.message ||
      "Erro ao limpar diagnósticos."
    );

  } finally {
    if (button) {
      button.disabled =
        false;
    }
  }
}

// ============================================================
// FILTROS DE DIAGNÓSTICO
// ============================================================

function initDiagnosticFilters() {
  const filters =
    document.querySelectorAll(
      "[data-diagnostic-filter]"
    );

  filters.forEach(button => {
    button.addEventListener(
      "click",
      () => {
        const filter =
          button.dataset
            .diagnosticFilter ||
          "all";

        state.diagnosticFilter =
          filter;

        filters.forEach(
          item => {
            item.classList
              .remove(
                "active"
              );
          }
        );

        button.classList.add(
          "active"
        );

        renderDiagnostics();
      }
    );
  });
}

// ============================================================
// COPIAR TODOS OS DIAGNÓSTICOS
// ============================================================

function copyAllDiagnostics() {
  if (
    state.diagnostics.length ===
    0
  ) {
    showToast(
      "Nenhum diagnóstico para copiar."
    );

    return;
  }

  const text =
    state.diagnostics
      .map(
        diagnostic =>
          diagnosticToText(
            diagnostic
          )
      )
      .join(
        "\n\n\n"
      );

  copyText(text);
}

// ============================================================
// AUTO REFRESH
// ============================================================

function startDiagnosticPolling() {
  if (
    state.diagnosticTimer
  ) {
    clearInterval(
      state.diagnosticTimer
    );
  }

  state.diagnosticTimer =
    setInterval(
      () => {
        const page =
          document.getElementById(
            "page-diagnostics"
          );

        if (
          page &&
          page.classList.contains(
            "active"
          )
        ) {
          loadDiagnostics();
        }
      },
      5000
    );
}

// ============================================================
// BOTÕES
// ============================================================

function initButtons() {
  const refreshFiles =
    $("refreshFiles");

  if (refreshFiles) {
    refreshFiles
      .addEventListener(
        "click",
        loadFiles
      );
  }

  const refreshDiagnostics =
    $("refreshDiagnostics");

  if (
    refreshDiagnostics
  ) {
    refreshDiagnostics
      .addEventListener(
        "click",
        loadDiagnostics
      );
  }

  const clear =
    $("clearDiagnostics");

  if (clear) {
    clear.addEventListener(
      "click",
      () => {
        const confirmed =
          window.confirm(
            "Apagar todos os diagnósticos?"
          );

        if (confirmed) {
          clearDiagnostics();
        }
      }
    );
  }

  const copyAll =
    $("copyAllDiagnostics");

  if (copyAll) {
    copyAll.addEventListener(
      "click",
      copyAllDiagnostics
    );
  }

  const checkServer =
    $("checkServer");

  if (checkServer) {
    checkServer.addEventListener(
      "click",
      async () => {
        await checkHealth();

        showToast(
          "Status atualizado."
        );
      }
    );
  }
}

// ============================================================
// ERROS DO PRÓPRIO SITE
// ============================================================

window.addEventListener(
  "error",
  event => {
    console.error(
      "Frontend error:",
      event.error ||
      event.message
    );
  }
);

window.addEventListener(
  "unhandledrejection",
  event => {
    console.error(
      "Unhandled promise:",
      event.reason
    );
  }
);

// ============================================================
// INICIALIZAÇÃO
// ============================================================

document.addEventListener(
  "DOMContentLoaded",
  async () => {
    initNavigation();

    initDiagnosticFilters();

    initButtons();

    startDiagnosticPolling();

    await checkHealth();

    const activeFiles =
      document
        .getElementById(
          "page-files"
        )
        ?.classList
        .contains(
          "active"
        );

    const activeDiagnostics =
      document
        .getElementById(
          "page-diagnostics"
        )
        ?.classList
        .contains(
          "active"
        );

    if (activeFiles) {
      await loadFiles();
    }

    if (
      activeDiagnostics
    ) {
      await loadDiagnostics();
    }

    setInterval(
      checkHealth,
      30000
    );
  }
);
