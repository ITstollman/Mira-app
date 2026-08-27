// The check behind the money. Runs the ledger against a store that is atomic per call
// but slow between them, which is the only interesting thing about the real one.
// node --test
import { test } from "node:test";
import assert from "node:assert/strict";
import { ledger, memory } from "./ledger.js";

const GRANT = 15;  // FREE_SPARKS default

/// Atomic where it must be, interleaved everywhere else — so a race in the ledger shows.
const slow = (s) => ({
  ...s,
  async add(uid, n) { const v = await s.add(uid, n); await tick(); return v; },
});
const tick = () => new Promise((r) => setImmediate(r));

test("a wallet nobody has seen starts on the house", async () => {
  const l = ledger(memory());
  assert.equal(await l.balance("new"), GRANT);
});

test("a debit returns what is left", async () => {
  const l = ledger(memory());
  assert.equal(await l.debit("a", 3), GRANT - 3);
  assert.equal(await l.balance("a"), GRANT - 3);
});

test("an unaffordable debit is refused and costs nothing", async () => {
  const l = ledger(memory());
  assert.equal(await l.debit("b", GRANT + 1), null);
  assert.equal(await l.balance("b"), GRANT, "the refusal must leave the wallet alone");
});

test("spending every last spark is allowed; the next one is not", async () => {
  const l = ledger(memory());
  assert.equal(await l.debit("c", GRANT), 0);
  assert.equal(await l.debit("c", 1), null);
  assert.equal(await l.balance("c"), 0);
});

test("racing debits can never overdraw", async () => {
  const l = ledger(slow(memory()));
  // twenty at once on a fifteen-spark wallet: seven fit, thirteen must bounce
  const out = await Promise.all(Array.from({ length: 20 }, () => l.debit("hot", 2)));
  const won = out.filter((v) => v !== null);
  const left = await l.balance("hot");
  assert.ok(out.some((v) => v === null), "twenty twos do not fit in fifteen");
  assert.ok(out.every((v) => v === null || v >= 0), "no caller was ever shown a negative balance");
  assert.ok(left >= 0, `wallet went to ${left}`);
  assert.equal(won.length * 2 + left, GRANT, "every spark is either spent or still there");
});

test("a credit lands and a refund is just a credit", async () => {
  const l = ledger(memory());
  await l.debit("d", 10);
  assert.equal(await l.credit("d", 7), GRANT - 10 + 7);
});

test("nonsense amounts move nothing", async () => {
  const l = ledger(memory());
  for (const junk of [0, -5, NaN, undefined, "abc", 0.4]) {
    assert.equal(await l.debit("e", junk), GRANT, `debit ${junk}`);
    assert.equal(await l.credit("e", junk), GRANT, `credit ${junk}`);
  }
});

test("the grant lands once, not once per process", async () => {
  const store = memory();
  await ledger(store).debit("f", 10);
  assert.equal(await ledger(store).balance("f"), GRANT - 10, "a restart must not re-grant");
});

test("a store that cannot give it back shouts instead of throwing", async () => {
  const store = memory();
  const errs = [];
  const say = console.error;
  console.error = (m) => errs.push(m);
  try {
    const l = ledger({
      ...store,
      async add(uid, n) { if (n > 0 && uid === "g") throw new Error("firestore is down"); return store.add(uid, n); },
    });
    assert.equal(await l.debit("g", GRANT + 1), null, "the caller still gets a clean refusal");
  } finally { console.error = say; }
  assert.match(errs.join(), /LEDGER LEAK g owed 16/);
});
