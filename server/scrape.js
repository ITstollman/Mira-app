// Product page -> a garment you can try on.
//
// Retailers all ship OpenGraph + schema.org JSON-LD, so a regex over the head beats
// pulling in a DOM. ponytail: if a store renders its product data client-side only,
// this returns nothing and the caller falls back to asking the user for a photo —
// upgrade path is a headless browser, and that is a service, not a function.
import { lookup } from "node:dns/promises";
import { ProxyAgent } from "undici";

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36";

// Round-robin whatever proxies are configured. One egress IP gets blocked; a rotating
// pool does not. ponytail: no health checks or per-host stickiness — add when a dead
// proxy in the list starts costing more than a retry.
const POOL = (process.env.SCRAPE_PROXIES ?? "").split(",").map((s) => s.trim()).filter(Boolean);
let turn = 0;
const agents = POOL.map((url) => new ProxyAgent(url));
function nextAgent() {
  if (!agents.length) return undefined;
  return agents[turn++ % agents.length];
}

/** Blocks the obvious SSRF: our own metadata service, the LAN, localhost. */
export async function assertPublic(raw) {
  let url;
  try { url = new URL(raw); } catch { throw new HttpError(400, "not a url"); }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new HttpError(400, "http(s) only");

  const host = url.hostname.replace(/^\[|\]$/g, "");        // WHATWG keeps the brackets on v6 literals
  const { address } = await lookup(host).catch(() => { throw new HttpError(400, "cannot resolve host"); });
  if (isPrivate(address)) throw new HttpError(403, "refusing to fetch a private address");
  return url;
}

// ponytail: checks the first resolved address only. A DNS rebind or a redirect into the
// LAN slips through — the fix is a custom dispatcher that re-checks every hop, and it is
// only worth writing once this server sits inside a network with something worth reaching.
export function isPrivate(ip) {
  if (ip.includes(":")) return ip === "::1" || /^(f[cd]|fe80)/i.test(ip);   // v6 loopback / ULA / link-local
  const [a, b] = ip.split(".").map(Number);
  return a === 10 || a === 127 || a === 0 ||
         (a === 172 && b >= 16 && b <= 31) ||
         (a === 192 && b === 168) ||
         (a === 169 && b === 254) ||
         (a === 100 && b >= 64 && b <= 127);                                // CGNAT
}

export class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function get(url, headers = {}) {
  return fetch(url, {
    headers: { "user-agent": UA, "accept-language": "en-US,en;q=0.9", ...headers },
    dispatcher: nextAgent(),
    redirect: "follow",
    signal: AbortSignal.timeout(15_000),
  });
}

// MARK: - parsing

const meta = (html, prop) => {
  // property= and name= both appear in the wild, in either attribute order.
  const re = new RegExp(`<meta[^>]+(?:property|name)=["']${prop}["'][^>]*>`, "i");
  const tag = html.match(re)?.[0] ?? html.match(new RegExp(`<meta[^>]+content=["'][^"']*["'][^>]*(?:property|name)=["']${prop}["'][^>]*>`, "i"))?.[0];
  return tag?.match(/content=["']([^"']*)["']/i)?.[1];
};

/** Every Product node in every ld+json block, flattened out of @graph and arrays. */
function jsonLD(html) {
  const out = [];
  for (const m of html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const walk = (n) => {
        if (Array.isArray(n)) return n.forEach(walk);
        if (!n || typeof n !== "object") return;
        if (n["@graph"]) walk(n["@graph"]);
        if (String(n["@type"] ?? "").includes("Product")) out.push(n);
      };
      walk(JSON.parse(m[1].trim()));
    } catch { /* one malformed block shouldn't lose the others */ }
  }
  return out;
}

const first = (v) => (Array.isArray(v) ? v[0] : v);
const decode = (s) => s && s.replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) =>
  ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " " }[e])).replace(/\s+/g, " ").trim();

/** A logo or a social banner is not a garment, and feeding one to the model is worse
 *  than having no picture at all — it is a confident wrong answer. */
const JUNK = /(logo|placeholder|default|sprite|favicon|-seo|swatch|share[-_]image)/i;

export function parseProduct(html, pageURL) {
  const products = jsonLD(html);
  const ld = products[0] ?? {};
  const offer = first(ld.offers) ?? {};
  const imageRaw = first(ld.image)?.url ?? first(ld.image) ?? meta(html, "og:image") ?? meta(html, "twitter:image");
  const image = imageRaw ? new URL(decode(imageRaw), pageURL).toString() : null;
  const price = Math.round(Number(offer.price ?? offer.lowPrice ?? meta(html, "product:price:amount") ?? meta(html, "og:price:amount"))) || null;

  return {
    name: decode(ld.name ?? meta(html, "og:title") ?? html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]) || "Untitled piece",
    brand: decode(first(ld.brand)?.name ?? ld.brand ?? meta(html, "og:site_name")) || new URL(pageURL).hostname.replace(/^www\./, ""),
    price,
    currency: offer.priceCurrency ?? meta(html, "product:price:currency") ?? "USD",
    description: decode(ld.description ?? meta(html, "og:description")) ?? "",
    image: image && !JUNK.test(new URL(image).pathname) ? image : null,
    // Evidence the page is selling one thing, rather than being the homepage a dead
    // product link quietly redirected to. Allbirds does exactly that, and without this
    // a 404 comes back as a garment called "The World's Most Comfortable Shoes" with
    // the site logo attached as the thing to wear.
    isProduct: products.length > 0 || /product/i.test(meta(html, "og:type") ?? "") || price !== null,
  };
}

// MARK: - prompt

// Decart's substitute/add patterns, keyed off what the listing calls the thing.
// https://docs.platform.decart.ai/models/realtime/vton-3.5-prompting
const REGIONS = [
  [/\b(dress|gown|jumpsuit|romper|playsuit|co-?ord|two[- ]piece|matching set|outfit)\b/i, "outfit",             "dresses"],
  [/\b(shoe|sneaker|boot|bootie|heel|sandal|loafer|trainer|slipper|mule|clog|pump|espadrille|slide|flat|flip[- ]?flop)s?\b/i, "footwear", "shoes"],
  [/\b(hat|cap|beanie|beret)\b/i,                                                          "hat",                "accessories"],
  [/\b(necklace|pendant|choker)\b/i,                                                       "necklace",           "accessories"],
  [/\b(trouser|pant|jean|skirt|short|legging|culotte)s?\b/i,                                "lower body garment", "bottoms"],
];
const UPPER = ["upper body garment", "tops"];

export function garmentPrompt({ name, description }) {
  const hay = `${name} ${description}`;
  const [, region, category] = REGIONS.find(([re]) => re.test(hay)) ?? [null, ...UPPER];

  // The listing title is already the garment description a stylist would write.
  // ponytail: no vision model in the loop. Decart recommends one for user-supplied
  // garments — swap this line for a call to it if try-on accuracy needs the lift.
  const blurb = describes(description) && !restates(name, description) ? `, ${clean(description)}` : "";
  const detail = words(`${strip(name)}${blurb}`, 40);
  return { prompt: `Substitute the ${region} with ${detail}.`, category };
}

const clean = (s) =>
  (s ?? "").replace(/\b(shop|buy|free shipping|new in|sale)\b/gi, "")
           .replace(/\s+/g, " ").trim().toLowerCase().replace(/[.\s]+$/, "");

/** Retailer *titles* carry the brand and boilerplate; the model only wants the garment.
 *  Descriptions get `clean` instead — a bare hyphen there is inside a word ("bias-cut",
 *  "long-sleeve", "V-neck"), and cutting at it threw away everything worth saying. */
const strip = (s) => clean((s ?? "").replace(/(?:\s*[|–—]|\s+-)\s*[^|–—]*$/, ""));

/** Plenty of stores open the description with the title. Saying it twice to the model
 *  is noise at best, and at 40 words it crowds out the half that carries detail. */
const restates = (name, d) => (d ?? "").toLowerCase().startsWith(strip(name).slice(0, 24));

/** Marketing blurbs ("our best seller!") add nothing; garment nouns do. */
const describes = (d) => /\b(cotton|silk|linen|denim|leather|knit|satin|wool|sleeve|neck|collar|hem|fit|button|zip|pocket|waist|strap|print|stripe|floral)\b/i.test(d ?? "");

const words = (s, n) => s.split(" ").slice(0, n).join(" ");
