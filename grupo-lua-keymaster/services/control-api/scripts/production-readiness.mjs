const required = [
  "DATABASE_URL",
  "KEYMASTER_ACCESS_HASH",
  "SESSION_PEPPER",
  "DEVICE_FINGERPRINT_PEPPER"
];

const failures = [];
for (const key of required) {
  const value = String(process.env[key] || "");
  if (!value) failures.push(`${key} ausente`);
}

const keymasterHash = String(process.env.KEYMASTER_ACCESS_HASH || "");
if (keymasterHash && !keymasterHash.startsWith("scrypt$")) {
  failures.push("KEYMASTER_ACCESS_HASH não parece um verificador scrypt válido");
}

for (const key of ["SESSION_PEPPER", "DEVICE_FINGERPRINT_PEPPER"]) {
  const value = String(process.env[key] || "");
  if (value && value.length < 32) failures.push(`${key} precisa ter pelo menos 32 caracteres`);
}

const integrityMode = String(process.env.APP_INTEGRITY_MODE || "report").toLowerCase();
if (!["off", "report", "enforce"].includes(integrityMode)) {
  failures.push("APP_INTEGRITY_MODE deve ser off, report ou enforce");
}
if (integrityMode === "enforce" && !String(process.env.APP_INTEGRITY_VERIFY_URL || "").trim()) {
  failures.push("APP_INTEGRITY_VERIFY_URL é obrigatório quando APP_INTEGRITY_MODE=enforce");
}

const publicBase = String(process.env.PUBLIC_BASE_URL || "").trim();
if (publicBase && !/^https:\/\//i.test(publicBase)) {
  failures.push("PUBLIC_BASE_URL deve usar HTTPS em produção");
}
if (/cafe-na-ia\.onrender\.com/i.test(publicBase)) {
  failures.push("PUBLIC_BASE_URL não pode apontar para o portal público de downloads");
}

if (failures.length) {
  console.error("CONTROL_API_PRODUCTION_NOT_READY");
  for (const item of failures) console.error(`- ${item}`);
  process.exit(1);
}

console.log("CONTROL_API_PRODUCTION_READY");
console.log(`- database: configured`);
console.log(`- keymaster verifier: configured`);
console.log(`- session/device peppers: configured`);
console.log(`- app integrity mode: ${integrityMode}`);
console.log(`- public base: ${publicBase ? "configured" : "request-derived"}`);
