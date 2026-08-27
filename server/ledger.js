import { createHash, createSign } from "node:crypto";

// The spark ledger. One integer per wallet, debited before anything expensive runs.
//
// This used to live in the app's UserDefaults, which meant a reinstall was free money
// and a leaked APP_SECRET was unlimited Decart. The balance lives here now; the copy in
// the app is only ever a display of what this last said.
//
// ponytail: a wallet is keyed by the device's identifierForVendor, because sign-in is
// still mocked. A reinstall is therefore a fresh wallet with the free grant in it — the
// exposure is FREE_SPARKS per reinstall, which is why the grant is small. The day
// Auth.swift hands back a verified subject, pass that as `uid` and nothing else changes.

const FREE_SPARKS = Number(process.env.FREE_SPARKS ?? 15);

/// A store is three calls: read one wallet, add to one wallet atomically, open one once.
/// `add` returns the balance *after* the change — that is what makes the debit below safe.
export function ledger(store) {
  // ponytail: per-process memo, so a warm wallet costs one round trip instead of two.
  // Wrong only after the doc is deleted out from under a live process, which nothing does.
  const opened = new Set();

  async function ensure(uid) {
    if (opened.has(uid)) return;
    await store.open(uid, FREE_SPARKS);
    opened.add(uid);
  }

  const api = {
    async balance(uid) {
      await ensure(uid);
      return (await store.get(uid)) ?? 0;
    },

    async credit(uid, n) {
      n = whole(n);
      await ensure(uid);
      return n ? store.add(uid, n) : api.balance(uid);
    },

    /// Optimistic debit: take it first, put it back if that overdrew. Two debits racing
    /// can both overdraw and both put back, and the balance still lands right — which a
    /// read-then-write cannot promise without a transaction round trip.
    /// Returns the new balance, or null when there wasn't enough.
    async debit(uid, n) {
      n = whole(n);
      if (!n) return api.balance(uid);
      await ensure(uid);
      const after = await store.add(uid, -n);
      if (after >= 0) return after;
      await unwind(store, uid, n);
      return null;
    },
  };
  return api;
}

function whole(n) {
  return Math.max(0, Math.floor(Number(n) || 0));
}

/// Putting back what we could not spend is the one write here that must not be lost.
async function unwind(store, uid, n) {
  for (let attempt = 1; ; attempt++) {
    try { return await store.add(uid, n); }
    catch (e) {
      if (attempt === 3) return void console.error(`LEDGER LEAK ${uid} owed ${n}: ${e.message}`);
    }
  }
}

/// Dev and tests. Dies with the process, which is the point.
export function memory() {
  const wallets = new Map();
  return {
    async get(uid) { return wallets.has(uid) ? wallets.get(uid) : null; },
    async add(uid, n) { const v = (wallets.get(uid) ?? 0) + n; wallets.set(uid, v); return v; },
    async open(uid, n) { if (wallets.has(uid)) return false; wallets.set(uid, n); return true; },
  };
}

// ── Firestore ────────────────────────────────────────────────────────────────
//
// Raw REST, no firebase-admin. The whole surface is three calls and a bearer token,
// and admin brings a hundred megabytes of dependency for it.
//
// The debit above works because Firestore's `increment` transform is atomic and its
// commit hands back the value it landed on — one round trip to spend and to know what
// is left. What it will not do is refuse to go below zero, which is exactly why the
// debit puts it back instead of asking Firestore to say no.

const SCOPE = "https://www.googleapis.com/auth/datastore";
const TOKEN_URI = "https://oauth2.googleapis.com/token";

export function firestore(serviceAccount, projectOverride) {
  const sa = credentials(serviceAccount);
  const project = projectOverride ?? sa.project_id;
  const root = `projects/${project}/databases/(default)/documents`;
  const rest = `https://firestore.googleapis.com/v1/${root}`;

  // ponytail: the id is a hash, so an IP or a device uuid never gets written down —
  // and any string is a legal document name. The cost is that a wallet can't be found
  // by eye in the console. Print the hash next to the complaint when that day comes.
  const id = (uid) => createHash("sha256").update(String(uid)).digest("hex").slice(0, 32);
  const name = (uid) => `${root}/wallets/${id(uid)}`;

  // One access token an hour, minted once even when twenty requests notice it expired
  // at the same moment.
  let live = { value: "", until: 0 };
  let minting = null;
  async function bearer() {
    if (live.until > Date.now()) return live.value;
    minting ??= mint(sa).finally(() => { minting = null; });
    live = await minting;
    return live.value;
  }

  async function call(path, init = {}) {
    const r = await fetch(`${rest}${path}`, {
      ...init,
      headers: { authorization: `Bearer ${await bearer()}`, ...init.headers },
      signal: AbortSignal.timeout(10_000),
    });
    return [r, await r.json().catch(() => ({}))];
  }

  /// `tolerate` is the set of google.rpc statuses that mean "that was already true".
  async function commit(writes, tolerate = []) {
    const [r, out] = await call(":commit", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ writes }),
    });
    if (r.ok) return out;
    if (tolerate.includes(out.error?.status)) return null;
    throw new Error(`firestore ${r.status}: ${out.error?.message ?? "commit failed"}`);
  }

  return {
    async get(uid) {
      const [r, doc] = await call(`/wallets/${id(uid)}`);
      if (r.status === 404) return null;
      if (!r.ok) throw new Error(`firestore ${r.status}: ${doc.error?.message ?? "read failed"}`);
      return Number(doc.fields?.sparks?.integerValue ?? 0);
    },

    async add(uid, n) {
      const out = await commit([{
        // ponytail: `wallet: true` exists only to give updateMask a field to name. An
        // empty mask is what the docs imply and never promise, and a mask naming `sparks`
        // would delete the thing we're incrementing. One boolean is a cheap way out.
        update: { name: name(uid), fields: { wallet: { booleanValue: true } } },
        updateMask: { fieldPaths: ["wallet"] },
        updateTransforms: [{ fieldPath: "sparks", increment: { integerValue: String(n) } }],
      }]);
      const landed = out?.writeResults?.[0]?.transformResults?.[0]?.integerValue;
      if (landed == null) throw new Error("firestore committed without saying where it landed");
      return Number(landed);
    },

    async open(uid, n) {
      // No updateMask here on purpose: the precondition guarantees there is nothing to
      // overwrite. Which of the two statuses comes back when there is, is undocumented,
      // so both are read as "someone else opened it first".
      const out = await commit([{
        update: { name: name(uid), fields: { sparks: { integerValue: String(n) }, wallet: { booleanValue: true } } },
        currentDocument: { exists: false },
      }], ["ALREADY_EXISTS", "FAILED_PRECONDITION"]);
      return out !== null;
    },
  };
}

/// The service account, as JSON or as base64 of that JSON — the second because a PEM
/// full of newlines is miserable to paste into a deploy dashboard.
function credentials(raw) {
  const text = raw.trim().startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
  const sa = JSON.parse(text);
  for (const field of ["client_email", "private_key", "project_id"]) {
    if (!sa[field]) throw new Error(`service account is missing ${field}`);
  }
  // JSON.parse already turned \n into newlines; this only catches a double-escaped paste.
  if (sa.private_key.includes("\\n")) sa.private_key = sa.private_key.replace(/\\n/g, "\n");
  return sa;
}

async function mint(sa) {
  const iat = Math.floor(Date.now() / 1000);
  const head = b64url({ alg: "RS256", typ: "JWT", ...(sa.private_key_id && { kid: sa.private_key_id }) });
  // No `sub`: that field is for domain-wide delegation and setting it without one is an error.
  const body = b64url({ iss: sa.client_email, scope: SCOPE, aud: TOKEN_URI, iat, exp: iat + 3600 });
  const signature = createSign("RSA-SHA256").update(`${head}.${body}`).end().sign(sa.private_key).toString("base64url");

  const r = await fetch(sa.token_uri ?? TOKEN_URI, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${head}.${body}.${signature}`,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!r.ok) throw new Error(`google auth ${r.status}: ${await r.text()}`);
  const token = await r.json();
  // A minute of slack, so a token can't expire between being handed out and being used.
  return { value: token.access_token, until: Date.now() + (token.expires_in - 60) * 1000 };
}

const b64url = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
