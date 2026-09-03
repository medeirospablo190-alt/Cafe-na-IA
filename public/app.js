const forms = [...document.querySelectorAll("[data-download-form]")];
const cards = [...document.querySelectorAll("[data-artifact-card]")];

loadCatalog().catch(() => {
  for (const card of cards) setCardAvailability(card, null);
});

for (const form of forms) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const artifactId = String(form.dataset.artifact || "");
    const input = form.querySelector("input[type='password']");
    const button = form.querySelector("button[type='submit']");
    const status = form.querySelector("[data-status]");
    if (!artifactId || !(input instanceof HTMLInputElement) || !(button instanceof HTMLButtonElement)) return;

    const password = input.value;
    if (!password || password.length > 512) {
      setStatus(status, "Digite a senha válida deste download.", "error");
      input.value = "";
      input.focus();
      return;
    }

    button.disabled = true;
    input.disabled = true;
    setStatus(status, "Validando com o servidor...", "loading");

    try {
      const response = await fetch(`/api/downloads/${encodeURIComponent(artifactId)}/authorize`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        credentials: "omit",
        cache: "no-store",
        body: JSON.stringify({ password })
      });

      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        if (response.status === 429 && data.retryAfter) {
          throw new Error(`Muitas tentativas. Tente novamente em ${formatWait(data.retryAfter)}.`);
        }
        throw new Error(String(data.message || "Não foi possível liberar este download."));
      }

      const downloadUrl = String(data.downloadUrl || "");
      if (!downloadUrl.startsWith("/api/downloads/t/")) {
        throw new Error("O servidor não retornou uma autorização de download válida.");
      }

      setStatus(status, "Autorizado. Iniciando download...", "success");
      startDownload(downloadUrl);
    } catch (error) {
      setStatus(status, error instanceof Error ? error.message : "Falha ao validar.", "error");
    } finally {
      // A senha nunca permanece no campo depois de uma tentativa.
      input.value = "";
      input.disabled = false;
      button.disabled = false;
    }
  });
}

async function loadCatalog() {
  const response = await fetch("/api/downloads/catalog", {
    cache: "no-store",
    credentials: "omit"
  });
  if (!response.ok) throw new Error("Catálogo indisponível");

  const data = await response.json();
  const byId = new Map((data.items || []).map((item) => [item.id, item]));

  for (const card of cards) {
    const id = String(card.dataset.artifactCard || "");
    setCardAvailability(card, byId.get(id) || null);
  }
}

function setCardAvailability(card, item) {
  const version = card.querySelector("[data-version]");
  const input = card.querySelector("input[type='password']");
  const button = card.querySelector("button[type='submit']");

  if (version) {
    if (!item) version.textContent = "Status indisponível";
    else version.textContent = item.available ? `Versão: ${item.version}` : "Build ainda não publicada";
  }

  const available = Boolean(item?.available);
  if (input instanceof HTMLInputElement) input.disabled = !available;
  if (button instanceof HTMLButtonElement) button.disabled = !available;
  card.classList.toggle("unavailable", !available);
}

function setStatus(node, message, kind) {
  if (!node) return;
  node.textContent = message;
  node.className = `status ${kind || ""}`.trim();
}

function startDownload(url) {
  // Não persistimos a autorização. Ela existe apenas no href temporário,
  // é de uso único e expira no servidor.
  const link = document.createElement("a");
  link.href = url;
  link.rel = "noopener noreferrer";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  link.remove();
}

function formatWait(seconds) {
  const value = Math.max(1, Number(seconds) || 1);
  if (value < 60) return `${Math.ceil(value)}s`;
  return `${Math.ceil(value / 60)} min`;
}
