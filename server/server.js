// Mira server — the only thing that ever sees the Decart key.
//
//   GET  /v1/account          what this wallet has left
//   POST /v1/mirror/token     mint a short-lived Decart client token for the live mirror
//   POST /v1/mirror/refund    hand back the seconds a live session never used
//   POST /v1/look             still try-on: person frame in, rendered look out
//   POST /v1/garment/scrape   a product link in, a wearable garment out
//   GET  /v1/garment/image/:id  the scraped garment shot
//   GET  /v1/catalog          the house closet
//
// Docs: https://docs.platform.decart.ai/getting-started/client-tokens
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { assertPublic, get, parseProduct, garmentPrompt, HttpError } from "./scrape.js";
import { ledger, memory, firestore } from "./ledger.js";

const BASE        = process.env.DECART_BASE ?? "https://api.decart.ai";
const KEY         = process.env.DECART_API_KEY;
const SECRET      = process.env.APP_SECRET;
const VTON_MODEL  = process.env.VTON_MODEL ?? "lucy-vton-3.5";
const IMAGE_MODEL = process.env.IMAGE_MODEL ?? "lucy-image-2";
const MAX_SESSION = Number(process.env.MAX_SESSION_SECONDS ?? 120);

// One spark = one second of compute = $0.02 of COGS. These two numbers are the same
// two in `Spend` in Mira/Account.swift; the app quotes them, this charges them.
const LOOK_SPARKS = 3;
const LIVE_SPARKS_PER_MINUTE = 60;
const liveSparks = (seconds) => Math.ceil((seconds * LIVE_SPARKS_PER_MINUTE) / 60);

const wallet = ledger(walletStore());
function walletStore() {
  const account = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (account) return firestore(account, process.env.FIREBASE_PROJECT);
  console.warn("no FIREBASE_SERVICE_ACCOUNT — sparks are in memory and die with this process");
  return memory();
}

if (!KEY || !SECRET) {
  console.error("DECART_API_KEY and APP_SECRET are required — see .env.example");
  process.exit(1);
}

const catalog = JSON.parse(readFileSync(new URL("./catalog.json", import.meta.url), "utf8"));
const byID = new Map(catalog.map((g) => [g.id, g]));

const MAX_UPLOAD = 10 * 1024 * 1024;
const MAX_GARMENT = 8 * 1024 * 1024;
const SIZES = ["XS", "S", "M", "L", "XL"];
const FIT = { XS: "a snug fit", S: "a fitted cut", M: "a true-to-size fit", L: "a relaxed fit", XL: "an oversized fit" };

// ponytail: scraped garment shots live in memory for 30 minutes — long enough to try on,
// short enough that nobody has to run a bucket. Ceiling: they die with the process and
// don't span instances, so a saved look pointing at one 404s after a deploy. Move to
// object storage the day looks become shareable.
const shots = new Map();
function keep(bytes, type) {
  const id = randomUUID();
  shots.set(id, { bytes, type, at: Date.now() });
  for (const [k, v] of shots) {
    if (Date.now() - v.at > 30 * 60_000 || shots.size > 200) shots.delete(k); else break;
  }
  return id;
}

// What a minted token was actually worth, so /v1/mirror/refund can never hand back more
// than was charged. Single-use — without that this route is a spark printer.
//
// ponytail: in memory, so a redeploy mid-session forfeits one unused refund, worth at
// most MAX_SESSION sparks, of a session the deploy killed anyway. Make it a Firestore
// doc the day there is more than one instance.
const grants = new Map();
function grant(who, seconds) {
  const id = randomUUID();
  grants.set(id, { who, seconds, at: Date.now() });
  for (const [k, v] of grants) {
    if (Date.now() - v.at > 2 * 60 * 60_000) grants.delete(k); else break;
  }
  return id;
}

/// Charge before the expensive thing runs, and put it back if the thing didn't happen.
/// Every way out of `work` that isn't a plain return is a refund — that is the point of
/// funnelling both paid routes through here rather than writing the refund twice.
async function charged(who, cost, work) {
  const left = await wallet.debit(who, cost);
  if (left === null) throw new HttpError(402, "not enough sparks");
  try { return { out: await work(), sparks: left }; }
  catch (e) { await wallet.credit(who, cost); throw e; }
}

// ponytail: fixed 30/min per caller, in memory. The ledger below is what actually bounds
// spend now; this just stops a leaked APP_SECRET hammering the free routes.
const hits = new Map();
function throttled(who) {
  const now = Date.now(), win = hits.get(who)?.filter((t) => now - t < 60_000) ?? [];
  win.push(now);
  hits.set(who, win);
  return win.length > 30;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const send = (code, body, type = "application/json") =>
    res.writeHead(code, { "content-type": type }).end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));

  try {
    if (url.pathname === "/health") return send(200, { ok: true });

    if (req.headers["x-mira-key"] !== SECRET) return send(401, { error: "unauthorized" });
    const who = req.headers["x-mira-device"] ?? req.socket.remoteAddress ?? "anon";
    if (throttled(who)) return send(429, { error: "slow down" });

    if (url.pathname === "/v1/catalog" && req.method === "GET") return send(200, catalog);

    if (url.pathname === "/v1/account" && req.method === "GET")
      return send(200, { sparks: await wallet.balance(who) });

    if (url.pathname === "/v1/account/credit" && req.method === "POST") {
      // ponytail: no receipt behind this, so it is a spark printer and stays off unless
      // MOCK_PURCHASE=1 asks for it. StoreKit 2 goes here: verify the signed transaction,
      // then credit that product's sparks once per transaction id.
      if (process.env.MOCK_PURCHASE !== "1") return send(501, { error: "purchases aren't wired up yet" });
      const { sparks } = await json(req);
      return send(200, { sparks: await wallet.credit(who, clamp(sparks, 0, 1000)) });
    }

    if (url.pathname === "/v1/mirror/token" && req.method === "POST") {
      const { seconds } = await json(req);
      // The token is the budget: it cannot outlive what the caller paid for.
      const capped = clamp(seconds ?? MAX_SESSION, 10, MAX_SESSION);
      const minted = await charged(who, liveSparks(capped), async () => {
        const r = await fetch(`${BASE}/v1/client/tokens`, {
          method: "POST",
          headers: { "x-api-key": KEY, "content-type": "application/json" },
          body: JSON.stringify({
            // Seconds. The token only has to live long enough to *open* the socket —
            // a session already running outlives its token. Docs' own example pairs a
            // 300s token with a 120s cap, so this is theirs.
            expiresIn: 300,
            // Exactly the id the app connects with — the SDK puts `?model=lucy-vton-3.5`
            // on the socket URL, and scoping compares the strings. Adding the
            // `lucy-vton-latest` alias here would whitelist something nothing asks for.
            // Mira/Checks.swift asserts the SDK still spells it this way.
            allowedModels: [VTON_MODEL],
            constraints: { realtime: { maxSessionDuration: capped } },
          }),
          signal: AbortSignal.timeout(10_000),
        });
        if (!r.ok) throw new HttpError(502, `token mint failed (${r.status}) ${await r.text()}`);
        return r.json();
      });
      return send(200, {
        ...minted.out, model: VTON_MODEL, seconds: capped,
        grant: grant(who, capped), sparks: minted.sparks,
      });
    }

    if (url.pathname === "/v1/mirror/refund" && req.method === "POST") {
      const { grant: id, seconds } = await json(req);
      const owed = grants.get(id);
      // An unknown or someone else's grant is worth nothing, and says so quietly — a
      // stale refund after a restart shouldn't look like a failure to the app.
      if (!owed || owed.who !== who) return send(200, { sparks: await wallet.balance(who) });
      grants.delete(id);
      const back = liveSparks(clamp(seconds ?? 0, 0, owed.seconds));
      return send(200, { sparks: await wallet.credit(who, back) });
    }

    // A product link from anywhere -> something the mirror can put on you.
    if (url.pathname === "/v1/garment/scrape" && req.method === "POST") {
      const { url: link } = await json(req);
      const target = await assertPublic(link);

      const page = await get(target);
      if (!page.ok) return send(502, { error: "could not read that page", status: page.status });
      const product = parseProduct(await page.text(), target.toString());
      // A dead product link that 302s to the homepage still answers 200, so `page.ok`
      // proves nothing. Refuse anything with no product markup rather than hand back a
      // confident garment scraped off a landing page.
      if (!product.isProduct) return send(422, { error: "that link doesn't look like a product page" });
      if (!product.image) return send(422, { error: "no product image on that page" });

      const shot = await get(product.image, { referer: target.origin });
      if (!shot.ok) return send(502, { error: "could not read the product image", status: shot.status });
      const bytes = Buffer.from(await shot.arrayBuffer());
      if (bytes.length > MAX_GARMENT) return send(413, { error: "product image too large" });

      const { prompt, category } = garmentPrompt(product);
      return send(200, {
        id: `scraped:${keep(bytes, shot.headers.get("content-type") ?? "image/jpeg")}`,
        name: product.name, brand: product.brand, price: product.price, currency: product.currency,
        category, prompt, source: target.toString(),
      });
    }

    const shotID = url.pathname.match(/^\/v1\/garment\/image\/(.+)$/)?.[1];
    if (shotID && req.method === "GET") {
      const shot = shots.get(shotID);
      if (!shot) return send(404, { error: "that garment expired — paste the link again" });
      return send(200, shot.bytes, shot.type);
    }

    if (url.pathname === "/v1/look" && req.method === "POST") {
      const size = (url.searchParams.get("size") ?? "M").toUpperCase();
      if (!SIZES.includes(size)) return send(400, { error: "bad size" });

      // Either a piece from the house closet, or one the user pasted a link to.
      const id = url.searchParams.get("garment") ?? "";
      const ref = id.startsWith("scraped:") ? shots.get(id.slice(8)) : null;
      const garment = ref ? null : byID.get(id);
      const prompt = ref ? url.searchParams.get("prompt") : garment?.prompt;
      if (!prompt) return send(404, { error: "unknown garment" });

      const type = (req.headers["content-type"] ?? "").split(";")[0];
      if (!["image/jpeg", "image/png", "image/webp"].includes(type)) return send(415, { error: "send a jpeg, png or webp body" });
      const frame = await body(req);
      if (!frame.length) return send(400, { error: "empty body" });

      const form = new FormData();
      form.append("data", new Blob([frame], { type }), "frame.jpg");
      form.append("prompt", `${prompt} Worn with ${FIT[size]}.`);
      form.append("resolution", "720p");
      // The garment shot is the source of truth — Decart says image + prompt beats either alone.
      if (ref) form.append("reference_image", new Blob([ref.bytes], { type: ref.type }), "garment.jpg");

      const look = await charged(who, LOOK_SPARKS, async () => {
        const r = await fetch(`${BASE}/v1/generate/${IMAGE_MODEL}`, {
          method: "POST",
          headers: { "x-api-key": KEY },
          body: form,
          signal: AbortSignal.timeout(120_000),
        });
        if (!r.ok) throw new HttpError(502, `render failed (${r.status}) ${await r.text()}`);
        return { bytes: Buffer.from(await r.arrayBuffer()), type: r.headers.get("content-type") ?? "image/png" };
      });
      res.writeHead(200, { "content-type": look.out.type, "x-mira-sparks": String(look.sparks) });
      return res.end(look.out.bytes);
    }

    send(404, { error: "no such route" });
  } catch (e) {
    if (e instanceof HttpError) return send(e.status, { error: e.message });
    // TimeoutError included: upstream was too slow, the app should retry not crash.
    send(e.name === "TimeoutError" ? 504 : 500, { error: e.message });
  }
});

function clamp(n, lo, hi) { return Math.min(hi, Math.max(lo, Math.floor(Number(n) || lo))); }

function body(req) {
  return new Promise((ok, no) => {
    const parts = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_UPLOAD) { no(new HttpError(413, "body too large")); req.destroy(); return; }
      parts.push(c);
    });
    req.on("end", () => ok(Buffer.concat(parts)));
    req.on("error", no);
  });
}

async function json(req) {
  const raw = (await body(req)).toString() || "{}";
  try { return JSON.parse(raw); } catch { throw new HttpError(400, "bad json"); }
}

const port = Number(process.env.PORT ?? 8787);
// 0.0.0.0 explicitly: the phone has to reach this over the LAN in dev, and Railway
// health-checks the container from outside it.
if (process.env.NODE_ENV !== "test") server.listen(port, "0.0.0.0", () => console.log(`mira server on :${port}`));

export { server };
