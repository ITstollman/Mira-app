/**
 * One-off shots. node social/gen.mjs <briefs.json>
 * Each brief: { slug, prompt }. Nothing runs that isn't in the file.
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ENV = "/Users/itamarstollman/Desktop/images-shopify-app/backend/.env";
const KEY = process.env.OPENAI_API_KEY ||
  (existsSync(ENV) ? readFileSync(ENV, "utf8").match(/^OPENAI_API_KEY=(.+)$/m)?.[1].trim() : "");
if (!KEY) throw new Error("no OPENAI_API_KEY");

const briefs = JSON.parse(readFileSync(resolve(HERE, process.argv[2]), "utf8"));
const OUT = resolve(HERE, "casting");
mkdirSync(OUT, { recursive: true });

async function shoot({ slug, prompt }) {
  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-image-2", prompt, size: "1152x2048", quality: "high", n: 1 }),
  });
  if (!res.ok) throw new Error(`${slug}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
  const b64 = (await res.json())?.data?.[0]?.b64_json;
  if (!b64) throw new Error(`${slug}: nothing came back`);
  writeFileSync(resolve(OUT, `${slug}.png`), Buffer.from(b64, "base64"));
  console.log(`✓ ${slug}`);
}

for (let i = 0; i < briefs.length; i += 3) {
  const r = await Promise.allSettled(briefs.slice(i, i + 3).map(shoot));
  r.forEach((d) => d.status === "rejected" && console.error(`✗ ${d.reason.message}`));
}
