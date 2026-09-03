const required = [
  "DATABASE_URL",
  "KEYMASTER_ACCESS_HASH",
  "SESSION_PEPPER",
  "DEVICE_FINGERPRINT_PEPPER",
  "PUBLIC_BASE_URL"
];

const failures = [];
const warnings = [];

for (const key of required) {
  const value = String(process.env[key] || "").trim();
  if (!value) failures.push(`${key} ausente`);
}

const keymasterHash = String(process.env.KEYMASTER_ACCESS_HASH || "").trim();
if (keymasterHash && !/^scrypt\$\d+\$\d+\$\d+\$[^$]+\$[^$]+$/.test(keymasterHash)) {
  failures.push("KEYMASTER_ACCESS_HASH não parece um verificador scrypt válido");
}

for (const key of ["SESSION_PEPPER", "DEVICE_FINGERPRINT_PEPPER"]) {
  const value = String(process.env[key] || "");
  if (value && value.length < 32) failures.push(`${key} precisa ter pelo menos 32 caracteres`);
}

const publicBase = String(process.env.PUBLIC_BASE_URL || "").trim();
if (publicBase && !/^https:\/\//i.test(publicBase)) {
  failures.push("PUBLIC_BASE_URL deve usar HTTPS em produção");
}
if (/cafe-na-ia\.onrender\.com/i.test(publicBase)) {
  failures.push("PUBLIC_BASE_URL não pode apontar para o portal público de downloads");
}
if (/\.invalid(?:\/|$)/i.test(publicBase) || /localhost|127\.0\.0\.1/i.test(publicBase)) {
  failures.push("PUBLIC_BASE_URL precisa apontar para a Control API pública real");
}

const databaseUrl = String(process.env.DATABASE_URL || "").trim();
if (databaseUrl && !/^postgres(?:ql)?:\/\//i.test(databaseUrl)) {
  failures.push("DATABASE_URL precisa ser uma URL PostgreSQL");
}

const integrityMode = String(process.env.APP_INTEGRITY_MODE || "report").toLowerCase();
if (!["off", "report", "enforce"].includes(integrityMode)) {
  failures.push("APP_INTEGRITY_MODE deve ser off, report ou enforce");
}
if (integrityMode === "enforce" && !String(process.env.APP_INTEGRITY_VERIFY_URL || "").trim()) {
  failures.push("APP_INTEGRITY_VERIFY_URL é obrigatório quando APP_INTEGRITY_MODE=enforce");
}
if (integrityMode !== "enforce") {
  warnings.push("App Integrity ainda não está em modo enforce");
}

const criticalEnabled = String(process.env.CRITICAL_ACTIONS_ENABLED || "false").toLowerCase() === "true";
const restartWebhook = String(process.env.APP1_RESTART_WEBHOOK || "").trim();
if (criticalEnabled && !/^https:\/\//i.test(restartWebhook)) {
  failures.push("APP1_RESTART_WEBHOOK HTTPS é obrigatório quando CRITICAL_ACTIONS_ENABLED=true");
}

if (failures.length) {
  console.error("CONTROL_API_PRODUCTION_NOT_READY");
  for (const item of failures) console.error(`- ${item}`);
  process.exit(1);
}

console.log("CONTROL_API_PRODUCTION_READY");
console.log("- database: configured");
console.log("- keymaster verifier: configured");
console.log("- session/device peppers: configured");
console.log(`- app integrity mode: ${integrityMode}`);
console.log("- public base: configured");
console.log(`- external critical actions: ${criticalEnabled ? "enabled" : "disabled"}`);
for (const warning of warnings) console.warn(`WARNING: ${warning}`);
