import crypto from "crypto";

const N = 16_384;
const r = 8;
const p = 1;
const KEY_BYTES = 32;

const password = await readSecret("Senha de download: ");
if (!password) {
  console.error("Senha vazia. Nada foi gerado.");
  process.exit(1);
}
if (password.length > 512) {
  console.error("A senha excede o limite de 512 caracteres do portal.");
  process.exit(1);
}

const salt = crypto.randomBytes(24);
const derived = crypto.scryptSync(password, salt, KEY_BYTES, {
  N,
  r,
  p,
  maxmem: 64 * 1024 * 1024
});

console.log(`scrypt$${N}$${r}$${p}$${salt.toString("base64url")}$${derived.toString("base64url")}`);

async function readSecret(prompt) {
  if (!process.stdin.isTTY) {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk));
    return Buffer.concat(chunks).toString("utf8").replace(/[\r\n]+$/, "");
  }

  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    const stdout = process.stdout;
    let value = "";

    stdout.write(prompt);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");

    const finish = () => {
      stdin.off("data", onData);
      stdin.setRawMode(false);
      stdin.pause();
      stdout.write("\n");
      resolve(value);
    };

    const onData = (char) => {
      if (char === "\u0003") {
        stdin.off("data", onData);
        stdin.setRawMode(false);
        stdout.write("\n");
        reject(new Error("Cancelado."));
        return;
      }
      if (char === "\r" || char === "\n") return finish();
      if (char === "\u007f" || char === "\b") {
        value = value.slice(0, -1);
        return;
      }
      value += char;
    };

    stdin.on("data", onData);
  });
}
