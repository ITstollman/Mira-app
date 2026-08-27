# Mira pricing

## The unit

Everything is priced in **sparks**. 1 spark = 1 second of Mira compute = **$0.02 COGS**.

| Action | Sparks | COGS |
|---|---|---|
| A look (still try-on render, ~3s) | 3 | $0.06 |
| A minute in the live mirror | 60 | $1.20 |

One currency, one number in the UI, and margin is knowable per tap. Live time is
~20× a look — that is the entire cost story of this business.

## Plans

Apple takes 15% (Small Business Program, under $1M/yr). 30% above that.

| | Weekly | Monthly | Yearly |
|---|---|---|---|
| Price | **$8.99** | **$24.99** | **$149.99** |
| Net after Apple | $7.64 | $21.24 | $127.49 |
| Sparks | 150 / week | 600 / month | 600 / month |
| Trial | 3 days (30 sparks) | — | — |
| COGS if 100% burned | $3.00 | $12.00 | $144.00 |
| **GM at 100% burn** | **61%** | **44%** | **-13%** |
| **GM at 40% burn** | **84%** | **77%** | **55%** |
| Annualized | $467 | $300 | $150 |

Unused sparks do not roll over. That is the margin protector, and it is standard.

**Monthly is a decoy.** Industry data says monthly underperforms both weekly and
annual at every price tier — its job here is to make $149.99/yr read as *"half the
price of monthly"* (it is: $300 → $150). Do not optimize it.

**Yearly is the exposure.** A yearly subscriber who actually burns 600 sparks every
month for 12 months loses money. It survives on breakage — annual cohorts typically
use ~25–35% of allowance after month two, which puts real GM at 60–72%. Watch the
P90 user. Levers if the tail bites: drop the yearly grant to 400/mo, or price at
$179.99.

## Topups

Consumables, priced *above* the monthly ($0.042/spark) and yearly ($0.021/spark)
rate. Weekly is the exception at $0.060 — the 350 and 800 packs undercut it on
paper, and that is fine: weekly sells the trial and the refill, not the unit price,
and at 40% burn its effective rate is $0.15 a spark, above every pack.

| Pack | Price | Net | COGS | GM | $/spark |
|---|---|---|---|---|---|
| 150 sparks | $9.99 | $8.49 | $3.00 | **65%** | $0.067 |
| 350 sparks | $19.99 | $16.99 | $7.00 | **59%** | $0.057 |
| 800 sparks | $39.99 | $33.99 | $16.00 | **53%** | $0.050 |

Volume discount with a 53% floor. Subscribers still buy these — that is the point of
hybrid monetization, and it is the default model for AI apps in 2026 precisely because
subscription alone cannot absorb variable inference cost.

## Free tier

**15 sparks (5 looks). No live mirror.** Costs $0.30 to acquire an activated user.

The paywall fires on first mirror open, not on the fifth look. Hard paywalls convert
5× better than freemium (10.7% vs 2.1% download-to-paid by day 35) with the same
year-one retention, and the majority of trial cancellations happen on day zero —
first session is the only shot.

## Why these numbers

- **Weekly leads.** Weekly plans are 55.5% of all subscription app revenue and convert
  installs to trials at up to 5.4× annual (9.8% vs 1.8%). Weekly + trial is the
  highest-LTV paywall configuration measured.
- **Trial is 3 days, not 17.** Longer trials convert ~70% better (42.5% at 17–32 days
  vs 25.5% under 4 days) — but a month of free live mirror at $1.20/min is a giveaway.
  The 3-day / 30-spark trial buys the taste without the bill. Revisit once live-mirror
  COGS drops (below).
- **Priced above median on purpose.** Global medians are $7.48/wk, $12.99/mo,
  $38.42/yr. AI apps monetize at ~2× pre-AI ARPU and this one has real COGS behind
  every tap. Annual sits at $149.99 because $38 cannot carry $0.02/second.
- **50–70% gross margin is the target**, not the old 80% SaaS rule, and token cost is
  never passed through 1:1.

## What to test, in order

Structure beats price: a 2-plan vs 3-plan test drives ~63% more conversion uplift than
a price change. So:

1. **Structure** — 3 plans vs weekly+yearly only. (Biggest expected lift.)
2. **Paywall placement** — first mirror open vs after look #1.
3. **Comparison table** — Free vs Pro columns on the paywall. Consistently additive
   across categories; a lot of users at the paywall still don't know what they're buying.
4. **Localization** — price per market before touching USD.
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
