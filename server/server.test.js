// One runnable check: routing, auth, the session cap and the render proxy.
// Stubs Decart so it costs nothing.  node --test
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";

let mira, base, seen = {};

const stub = createServer((req, res) => {
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    seen.path = req.url;
    seen.key = req.headers["x-api-key"];
    seen.body = raw;
    if (req.url === "/v1/client/tokens") {
      if (seen.refuse) return void res.writeHead(500).end("decart is having a day");
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ apiKey: "ek_test", expiresAt: "2099-01-01T00:00:00Z" }));
    } else {
      res.writeHead(200, { "content-type": "image/png" }).end(Buffer.from("PNGBYTES"));
    }
  });
});

before(async () => {
  await new Promise((r) => stub.listen(0, r));
  base = `http://127.0.0.1:${stub.address().port}`;
  Object.assign(process.env, {
    NODE_ENV: "test", DECART_BASE: base, DECART_API_KEY: "dct_test",
    APP_SECRET: "s3cret", MAX_SESSION_SECONDS: "120", MOCK_PURCHASE: "1",
  });
  ({ server: mira } = await import("./server.js"));
  await new Promise((r) => mira.listen(0, r));
});

after(() => { mira.close(); stub.close(); });

const call = (path, opts = {}, device = Math.random().toString(36)) =>
  fetch(`http://127.0.0.1:${mira.address().port}${path}`, {
    ...opts,
    headers: { "x-mira-key": "s3cret", "x-mira-device": device, ...opts.headers },
  });

const GRANT = 15;   // FREE_SPARKS default
const sparks = async (device) => (await (await call("/v1/account", {}, device)).json()).sparks;
const fund = (device, n) => call("/v1/account/credit", { method: "POST", body: JSON.stringify({ sparks: n }) }, device);
const mint = (device, seconds) => call("/v1/mirror/token", { method: "POST", body: JSON.stringify({ seconds }) }, device);

test("health needs no key", async () => {
  const r = await fetch(`http://127.0.0.1:${mira.address().port}/health`);
  assert.equal(r.status, 200);
});

test("v1 without the app secret is rejected", async () => {
  const r = await call("/v1/catalog", { headers: { "x-mira-key": "wrong" } });
  assert.equal(r.status, 401);
});

test("catalog every garment carries a try-on prompt", async () => {
  const items = await (await call("/v1/catalog")).json();
  assert.equal(items.length, 12);
  assert.ok(items.every((g) => g.id && /^(Substitute|Add) /.test(g.prompt)));
});

test("a new wallet opens on the house", async () => {
  assert.equal(await sparks("fresh"), GRANT);
});

test("token mint caps the session no matter what the app asks for", async () => {
  await fund("rich", 500);
  const t = await (await mint("rich", 99999)).json();
  assert.equal(t.apiKey, "ek_test");
  assert.equal(t.seconds, 120);
  assert.equal(t.sparks, GRANT + 500 - 120, "charged for the capped session, not the one asked for");
  assert.ok(t.grant, "a receipt has to come back or the refund is impossible");
  assert.equal(seen.key, "dct_test");                       // the real key never leaves here
  const sent = JSON.parse(seen.body);
  assert.equal(sent.constraints.realtime.maxSessionDuration, 120);
  assert.deepEqual(sent.allowedModels, ["lucy-vton-3.5"], "scope the id the app connects with, nothing else");
  assert.ok(sent.expiresIn > sent.constraints.realtime.maxSessionDuration, "the token must outlive the socket handshake");
});

test("token mint floors a silly-short request", async () => {
  assert.equal((await (await mint("floor", 0)).json()).seconds, 10);
});

test("a session nobody can afford is refused, and costs nothing", async () => {
  const r = await mint("poor", 120);
  assert.equal(r.status, 402);
  assert.equal(await sparks("poor"), GRANT, "a refusal must not take the money");
});

test("a mint the upstream refuses is not charged for", async () => {
  await fund("unlucky", 200);
  seen.refuse = true;
  try {
    assert.equal((await mint("unlucky", 120)).status, 502);
  } finally { seen.refuse = false; }
  assert.equal(await sparks("unlucky"), GRANT + 200, "charged for a token that never existed");
});

test("the unused half of a session comes back", async () => {
  await fund("quitter", 200);
  const t = await (await mint("quitter", 60)).json();
  assert.equal(t.sparks, GRANT + 200 - 60);
  const back = await (await call("/v1/mirror/refund", {
    method: "POST", body: JSON.stringify({ grant: t.grant, seconds: 40 }),
  }, "quitter")).json();
  assert.equal(back.sparks, GRANT + 200 - 20, "only the 20 seconds actually used stay spent");
});

test("a refund cannot be replayed, inflated, or stolen", async () => {
  await fund("sly", 200);
  const t = await (await mint("sly", 60)).json();
  const refund = (device, seconds) => call("/v1/mirror/refund", {
    method: "POST", body: JSON.stringify({ grant: t.grant, seconds }),
  }, device);

  assert.equal((await (await refund("thief", 60)).json()).sparks, GRANT, "another device cannot cash it");
  assert.equal((await (await refund("sly", 99999)).json()).sparks, GRANT + 200, "never more than was charged");
  assert.equal((await (await refund("sly", 60)).json()).sparks, GRANT + 200, "and never twice");
});

test("purchases stay off unless something explicitly turns them on", async () => {
  delete process.env.MOCK_PURCHASE;
  try {
    assert.equal((await fund("shopper", 100)).status, 501);
  } finally { process.env.MOCK_PURCHASE = "1"; }
  assert.equal(await sparks("shopper"), GRANT);
});

test("look rejects unknown garment, bad size and non-images", async () => {
  const img = { "content-type": "image/jpeg" };
  assert.equal((await call("/v1/look?garment=nope", { method: "POST", headers: img, body: "x" })).status, 404);
  assert.equal((await call("/v1/look?garment=g1&size=XXL", { method: "POST", headers: img, body: "x" })).status, 400);
  assert.equal((await call("/v1/look?garment=g1", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" })).status, 415);
});

test("look forwards the frame and returns the render", async () => {
  const r = await call("/v1/look?garment=g4&size=L", {
    method: "POST", headers: { "content-type": "image/jpeg" }, body: Buffer.from("JPEGBYTES"),
  }, "shooter");
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("x-mira-sparks"), String(GRANT - 3), "the render is charged for");
  assert.equal(await r.text(), "PNGBYTES");
  assert.equal(seen.path, "/v1/generate/lucy-image-2");
  assert.match(seen.body, /Substitute the upper body garment with a deep cherry red/);
  assert.match(seen.body, /a relaxed fit/);                 // size L reached the prompt
});

test("a runaway device gets throttled", async () => {
  const codes = [];
  for (let i = 0; i < 32; i++) codes.push((await call("/v1/catalog", {}, "greedy")).status);
  assert.equal(codes.filter((c) => c === 429).length, 2);
});

test("scrape refuses to fetch our own network", async () => {
  for (const link of ["http://127.0.0.1:80/x", "http://192.168.1.1/", "http://[::1]/"]) {
    const r = await call("/v1/garment/scrape", { method: "POST", body: JSON.stringify({ url: link }) });
    assert.equal(r.status, 403, link);
  }
  const bad = await call("/v1/garment/scrape", { method: "POST", body: JSON.stringify({ url: "file:///etc/passwd" }) });
  assert.equal(bad.status, 400);
});

test("an expired garment shot says so instead of 500ing", async () => {
  const r = await call("/v1/garment/image/does-not-exist");
  assert.equal(r.status, 404);
});
