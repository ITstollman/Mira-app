# Mira pricing

## The unit

The wallet counts **sparks**. 1 spark = 1 second of Mira compute = **$0.02 COGS**.
The screen never says spark. It says **fitting**, and one fitting is 15 sparks:

| Action | Sparks | COGS |
|---|---|---|
| A fitting — 15 seconds in the live mirror | 15 | $0.30 |
| A photograph (still try-on render, ~3s) | 15 | $0.06 |

A photograph is priced at a fitting and renders for a fifth of one. That spread is
what pays for the mirror, and it is the whole cost story of this business: live time
is ~5× a still at the same price.

The wire and the ledger still count seconds, because margin is only knowable per
second and `/v1/mirror/refund` hands back the ones a session never used.
`Spend.said` is the only place the two meet.

A session is capped at **120 seconds** (`MAX_SESSION_SECONDS`) — eight fittings back
to back. Long enough to stop feeling metered, short enough that a mirror left running
can't empty a month.

## Plans

Mira Pro grants **12 fittings a month** (180 sparks, $3.60 of compute).
Apple takes 15% (Small Business Program, under $1M/yr). 30% above that.

| | Monthly | Yearly |
|---|---|---|
| Price | **$24.99** | **$149.99** |
| Net after Apple | $21.24 | $127.49 |
| Grant | 12 fittings / month | 12 fittings / month |
| COGS if 100% burned | $3.60 / mo | $43.20 / yr |
| **GM at 100% burn** | **83%** | **66%** |
| **GM at 40% burn** | **93%** | **86%** |
| Annualized | $300 | $150 |
| Net per fitting at 100% burn | $1.77 | $0.89 |

Fittings **do not roll over**. That is the margin protector and it is standard — and
since the shipping build derives the grant from `Transaction.currentEntitlements`,
Apple offers one entitlement no matter how many months you were away. Three months
lapsed is one refill, not three. Nothing stockpiles.

**Monthly is a decoy.** Industry data says monthly underperforms both weekly and
annual at every price tier — its job here is to make $149.99/yr read as *"half the
price of monthly"* ($300 → $150), which is the "Save 50%" badge on the top row.
Do not optimize it.

**Yearly is the exposure**, and much less than it used to be: at 12 fittings a month
it clears 66% even if every one is burned. It survives comfortably on breakage —
annual cohorts typically use ~25–35% of allowance after month two.

**No weekly plan ships today.** Weekly is the single biggest measured lever on this
page (below) and the slot is deliberately empty, not decided against.

## Topups

Consumables, priced *above* the plan's per-fitting rate ($1.04 gross on the yearly),
because a topup is what you buy when you did not want to subscribe.

| Pack | Price | Net | COGS | GM | $/fitting |
|---|---|---|---|---|---|
| 10 fittings | $19.99 | $16.99 | $3.00 | **82%** | $2.00 |
| 30 fittings | $49.99 | $42.49 | $9.00 | **79%** | $1.67 |
| 75 fittings | $99.99 | $84.99 | $22.50 | **74%** | $1.33 |

Volume discount with a 74% floor, and every rung still dearer than subscribing.
[Checks.swift](Mira/Checks.swift) asserts all three of those relationships at launch —
the ladder gets cheaper, no pack undercuts Mira Pro, and every rung clears 2× compute.

Subscribers still buy these. That is the point of hybrid monetization, and it is the
default model for AI apps in 2026 precisely because subscription alone cannot absorb
variable inference cost.

## Free tier

**One fitting** (`FREE_SPARKS=15`). Costs $0.30 to acquire an activated user.

It is one fitting rather than five looks because a stranger who has not seen herself
in the mirror has not seen the product. The paywall fires the moment that fitting is
spent — hard paywalls convert 5× better than freemium (10.7% vs 2.1% download-to-paid
by day 35) with the same year-one retention, and most trial cancellations happen on
day zero. First session is the only shot.

There is no free trial on the plans. The badge on the yearly row says BEST VALUE, not
a promise of something that isn't given.

## Where the numbers actually live

Four places, and they drift independently — this file is the argument, not the source:

| | Owns |
|---|---|
| [Account.swift](Mira/Account.swift) | `Spend`, `Plan`, `Pack` — the grant, and the USD fallback prices |
| App Store Connect | the real prices, in every currency. The app reads them at runtime and the strings above are only shown until the store answers |
| `SOLD` in [server/server.js](server/server.js) | what each product id is worth in sparks. **The only copy that pays out** |
| [Checks.swift](Mira/Checks.swift) | asserts the arithmetic on this page still holds at launch |

The client never tells the server what it bought. It hands over Apple's signed
transactions; [server/apple.js](server/apple.js) verifies each against a pinned Apple
Root CA and the ledger credits per transaction id exactly once.

## Why these numbers

- **Priced above median on purpose.** Global medians are $7.48/wk, $12.99/mo,
  $38.42/yr. AI apps monetize at ~2× pre-AI ARPU and this one has real COGS behind
  every tap. Annual sits at $149.99 because $38 cannot carry $0.02/second.
- **50–70% gross margin is the target**, not the old 80% SaaS rule, and token cost is
  never passed through 1:1. Everything on this page clears it.
- **12 fittings, not unlimited.** The grant is the one number the subscription is
  priced on. It is written once, in `Plan.fittings`, and read by both the copy and
  the paywall so they cannot disagree.

## What to test, in order

Structure beats price: a 2-plan vs 3-plan test drives ~63% more conversion uplift than
a price change. So:

1. **Add weekly.** Weekly plans are 55.5% of all subscription app revenue and convert
   installs to trials at up to 5.4× annual (9.8% vs 1.8%). Weekly + trial is the
   highest-LTV paywall configuration measured, and it is the empty slot above.
2. **Paywall placement** — on the free fitting being spent vs before it.
3. **Comparison table** — Free vs Pro columns on the paywall. Consistently additive
   across categories; a lot of users at the paywall still don't know what they're buying.
4. **Localization** — price per market before touching USD. The client already renders
   Apple's own price, so this is an App Store Connect change and no code.
5. **Price** — last, not first.

## The biggest lever isn't pricing

At $0.02/second, the live mirror costs $72/hour. No consumer subscription absorbs that.
Rendering keyframes at ~2fps and interpolating on device cuts effective live cost by
roughly an order of magnitude, which is what makes "unlimited live mirror" sayable on
the paywall. That is an engineering decision, and it is worth more than any price test
on this page.

---

Sources: [RevenueCat — State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps),
[RevenueCat — benchmarks in 10 minutes](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026),
[RevenueCat — why hybrid monetization is the default in 2026](https://www.revenuecat.com/blog/growth/ai-hybrid-monetization/),
[Adapty — State of In-App Subscriptions 2026](https://adapty.io/state-of-in-app-subscriptions/),
[Adapty — what a high-performing paywall looks like in 2026](https://adapty.io/blog/high-performing-paywall-2026/),
[Causo — how to price an AI product: the margin playbook](https://hub.causo.ai/guides/how-to-price-ai-product-token-costs-margins-2026),
[Digital Applied — AI unit economics](https://www.digitalapplied.com/blog/ai-unit-economics-pricing-margins-services-2026-framework)
