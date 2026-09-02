// Integração server-side com Play Integrity / App Attest.
// O app envia o token/prova obtido por @expo/app-integrity. Em produção, este
// módulo deve encaminhar a prova para um verificador server-side confiável.

export async function verifyAppIntegrity({ platform, integrityProof, requestHash }) {
  const mode = String(process.env.APP_INTEGRITY_MODE || "report").toLowerCase();
  if (mode === "off") return { accepted: true, verified: false, mode };

  const verifyUrl = String(process.env.APP_INTEGRITY_VERIFY_URL || "").trim();
  const verifyToken = String(process.env.APP_INTEGRITY_VERIFY_TOKEN || "").trim();

  if (!verifyUrl) {
    if (mode === "enforce") {
      return { accepted: false, verified: false, mode, reason: "INTEGRITY_VERIFIER_NOT_CONFIGURED" };
    }
    return { accepted: true, verified: false, mode, reason: "REPORT_ONLY_NO_VERIFIER" };
  }

  try {
    const response = await fetch(verifyUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(verifyToken ? { authorization: `Bearer ${verifyToken}` } : {})
      },
      body: JSON.stringify({ platform, integrityProof, requestHash }),
      signal: AbortSignal.timeout(10_000)
    });
    const data = await response.json().catch(() => ({}));
    const verified = response.ok && data?.verified === true;
    return { accepted: verified || mode !== "enforce", verified, mode, details: data };
  } catch (error) {
    return {
      accepted: mode !== "enforce",
      verified: false,
      mode,
      reason: "INTEGRITY_VERIFIER_UNAVAILABLE",
      error: String(error?.message || error)
    };
  }
}
