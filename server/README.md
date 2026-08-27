# Mira server

The only place the Decart key lives, and the only place the spark balance lives. Node 24,
one dependency (`undici`, for proxies).

```sh
cp .env.example .env      # dct_… key, APP_SECRET, and a Firebase service account
npm start                 # :8787
npm test                  # stubs Decart, costs nothing
```

Every `/v1` route needs `x-mira-key: $APP_SECRET`. Send `x-mira-device: <id>` so the
rate limit is per install rather than per NAT.

| Route | |
|---|---|
| `GET /v1/catalog` | the house closet — id, brand, price, and the VTON prompt per garment |
| `GET /v1/account` | `{sparks}` — the balance, which is the only one that can be spent |
| `POST /v1/account/credit` | `{sparks}` → `{sparks}`. **501 unless `MOCK_PURCHASE=1`.** Stands in for StoreKit until there is a receipt to verify. |
| `POST /v1/mirror/token` | `{seconds}` → `{apiKey, model, seconds, grant, sparks}`. Charges the wallet first, then mints an ephemeral `ek_…` key scoped to the VTON model and hard-capped at the seconds it charged for. 402 when the wallet can't cover it. |
| `POST /v1/mirror/refund` | `{grant, seconds}` → `{sparks}`. Hands back the seconds a session never used. |
| `POST /v1/garment/scrape` | `{url}` → a wearable garment: name, brand, price, category, prompt, and an `id` of `scraped:<key>` |
| `GET /v1/garment/image/:key` | the scraped shot itself (the `id` above minus the `scraped:` prefix) |
| `POST /v1/look?garment=g1&size=M` | body = raw jpeg/png/webp of the person, response = rendered look, balance in the `x-mira-sparks` header. `garment=scraped:<key>&prompt=…` uses a scraped piece and attaches its shot as `reference_image`. |

## Sparks

One spark = one second of Decart compute = $0.02 of COGS. A look is 3, the live mirror
is 60/minute, and a new wallet opens with `FREE_SPARKS` (15) in it.

The balance is here, not in the app. `Mira/Account.swift` holds a cache of whatever this
last said; every paid route answers with the settled number and the app adopts it.

```
POST /v1/mirror/token {seconds:120}  → charges 120, returns {grant, sparks: 15+…-120}
   … user quits after 40s …
POST /v1/mirror/refund {grant, seconds:80} → credits 80, returns {sparks}
```

A `grant` is single-use, bound to the device that bought it, and a refund is clamped to
what was actually charged — otherwise the refund route is a spark printer. Charging
happens *before* the expensive thing runs and is put back if the thing didn't happen
(`charged()` in `server.js`).

Set `FIREBASE_SERVICE_ACCOUNT` to the service-account JSON, or base64 of it — a PEM full
of newlines is miserable to paste into a deploy dashboard. Without it the ledger runs in
memory and dies with the process, which is fine for `npm test` and nothing else.

Firestore is reached over its REST API with a hand-rolled RS256 service-account JWT
(`ledger.js`) rather than `firebase-admin`, which keeps the dependency count at one.
Service-account requests use IAM and **bypass security rules** — so the rules on
`mira-live-virtual-try-on` should be deny-all. Nothing in the app touches Firestore.

Wallets are keyed by a hash of `x-mira-device`, so no device id is ever written down.
`node --test` covers the money path: racing debits can't overdraw, refunds can't be
replayed, inflated, or stolen.

## The live mirror

The app never proxies video through here — it mints a token, then talks WebRTC to
Decart directly. `Mira/Mirror.swift` is the client; the shape is:

```swift
let token  = try await API.mirrorToken(seconds: seconds)          // POST /v1/mirror/token
let client = DecartClient(decartConfiguration: .init(apiKey: token.value))
let manager = try client.createRealtimeManager(options: .init(
    model: Models.realtime(.lucyVton3_5),
    initialPrompt: DecartPrompt(text: garment.prompt, referenceImageData: garment.shot),
    resolution: .p720))
let remote = try await manager.connect(
    localStream: client.createLocalCameraStream(model: Models.realtime(.lucyVton3_5)))

try await manager.setPrompt(other)   // swap the garment without reconnecting
```

`maxSessionDuration` on the token is the spend cap: an expired token can't start a new
session, and the session itself dies at the cap. That is what stops a 60-spark/minute
stream from running forever.

## Scraping a product link

`POST /v1/garment/scrape` reads schema.org JSON-LD first, OpenGraph second, `<title>`
last, then writes a Decart-shaped prompt (`Substitute the {region} with {detail}.`) and
caches the product shot in memory for 30 minutes.

Set `SCRAPE_PROXIES` to a comma-separated list to rotate egress:

```
SCRAPE_PROXIES=http://user:pass@a.proxy:8000,http://user:pass@b.proxy:8000
```

Requests round-robin across them. Without it every fetch leaves from the server's own
IP, and the big retailers (Uniqlo, H&M, Bombas…) will hand back 403 or a bot
checkpoint — that is what the proxies are for, not an optimisation.

Outbound URLs are resolved and refused if they land on a private address (RFC1918,
loopback, link-local, CGNAT, IPv6 ULA), so a pasted link can't be used to probe the
network the server sits in.

## What this deliberately isn't yet

- **No user accounts.** A wallet is keyed by the device's `identifierForVendor`, because
  sign-in is still mocked. A reinstall is a fresh wallet with the free grant in it — the
  exposure is `FREE_SPARKS` per reinstall, which is why the grant is small. The day
  `Auth.swift` returns a verified subject, pass that as the device id and nothing else
  changes.
- **No purchases.** `POST /v1/account/credit` is off unless `MOCK_PURCHASE=1`, and
  production never sets it. StoreKit 2's signed transaction goes in that body.
- **Live-session grants are in memory**, so a redeploy mid-session forfeits one unused
  refund — worth at most `MAX_SESSION_SECONDS` sparks, of a session the deploy killed
  anyway. Make it a Firestore doc the day there is more than one instance.
- **No house garment reference images.** `lucy-vton-3.5` wants a garment shot, and
  `catalog.json` has prompts only — the app papers over it by rendering the silhouette
  swatch. Pasted links are the good path until real product photography exists.
- **Most retailers need proxies.** Verified 2026-08-27: Uniqlo, H&M, COS and PacSun all
  answer 403 to this server's own IP, and Zara renders its product data client-side so
  there is nothing in the HTML to read. Shopify stores (Allbirds et al.) work direct.
  `SCRAPE_PROXIES` is the fix for the first group, a headless browser for the second.
- **A dead product link often 302s to the homepage and answers 200**, so `res.ok` proves
  nothing — the route now requires product markup (JSON-LD `Product`, `og:type=product`,
  or a price) and drops obvious logos and share banners rather than sending one to the
  model as the thing to wear.
- **Scraped shots live in memory**, so they die with the process and don't span
  instances. 30-minute TTL, 200-item cap.
- **Rate limit is in-memory** too — resets on deploy, doesn't span instances.
