// The fragile half: reading a product page nobody wrote for us.  node --test
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseProduct, garmentPrompt, isPrivate, assertPublic } from "./scrape.js";

const LD = `<html><head>
<title>Buy Now | Shopfront</title>
<meta property="og:title" content="Ignore me">
<script type="application/ld+json">
{"@context":"https://schema.org","@graph":[
 {"@type":"WebPage","name":"nope"},
 {"@type":"Product","name":"Ribbed Knit Midi Dress","brand":{"name":"Lune"},
  "description":"A long sleeve ribbed knit midi dress with a high neck.",
  "image":["https://cdn.shop/img/dress.jpg"],
  "offers":{"@type":"Offer","price":"189.00","priceCurrency":"GBP"}}]}
</script></head></html>`;

const OG = `<html><head>
<meta content="Cropped Denim Jacket - Saint Rose" property="og:title">
<meta property="og:image" content="/img/jacket.jpg">
<meta name="og:description" content="Oversized fit with a button front and chest pockets.">
<meta property="og:site_name" content="Saint Rose">
<meta property="product:price:amount" content="132.50">
</head></html>`;

test("json-ld wins over og, even buried in @graph", () => {
  const p = parseProduct(LD, "https://shop.example.com/p/1");
  assert.equal(p.name, "Ribbed Knit Midi Dress");
  assert.equal(p.brand, "Lune");
  assert.equal(p.price, 189);
  assert.equal(p.currency, "GBP");
  assert.equal(p.image, "https://cdn.shop/img/dress.jpg");
});

test("og is the fallback, with attributes in either order and relative images", () => {
  const p = parseProduct(OG, "https://saintrose.com/p/2");
  assert.equal(p.name, "Cropped Denim Jacket - Saint Rose");
  assert.equal(p.brand, "Saint Rose");
  assert.equal(p.price, 133);                                  // rounded
  assert.equal(p.image, "https://saintrose.com/img/jacket.jpg"); // resolved against the page
});

test("a page with nothing on it still yields a usable garment", () => {
  const p = parseProduct("<html><head></head></html>", "https://www.bare.com/x");
  assert.equal(p.name, "Untitled piece");
  assert.equal(p.brand, "bare.com");                           // host, minus www
  assert.equal(p.price, null);
  assert.equal(p.image, null);
});

test("entities and whitespace come out clean", () => {
  const p = parseProduct(`<html><head><meta property="og:title" content="Bardot &amp;  Co&#39;s  Slip"></head></html>`, "https://x.com/");
  assert.equal(p.name, "Bardot & Co's Slip");
});

test("prompt names the region the listing is actually about", () => {
  const cases = [
    ["Ribbed Knit Midi Dress", "outfit", "dresses"],
    ["High Waisted Wide Leg Trousers", "lower body garment", "bottoms"],
    ["Cropped Denim Jacket", "upper body garment", "tops"],
    ["White Low Top Sneakers", "footwear", "shoes"],
    ["Ribbed Beanie", "hat", "accessories"],
  ];
  for (const [name, region, category] of cases) {
    const g = garmentPrompt({ name, description: "" });
    assert.match(g.prompt, new RegExp(`^Substitute the ${region} with `), name);
    assert.equal(g.category, category, name);
  }
});

test("prompt drops the trailing brand and marketing, keeps garment detail", () => {
  const g = garmentPrompt({
    name: "Shop Cropped Denim Jacket | Saint Rose",
    description: "Oversized fit with a button front and chest pockets.",
  });
  assert.equal(g.prompt, "Substitute the upper body garment with cropped denim jacket, oversized fit with a button front and chest pockets.");
});

test("a blurb with no garment words is left out", () => {
  const g = garmentPrompt({ name: "Sugar Mini", description: "Our best seller! Ships free today." });
  assert.equal(g.prompt, "Substitute the upper body garment with sugar mini.");
});

test("private ranges are private", () => {
  for (const ip of ["127.0.0.1", "10.0.0.5", "172.16.3.1", "172.31.255.255", "192.168.0.1", "169.254.169.254", "100.64.0.1", "::1", "fd00::1", "fe80::1"])
    assert.ok(isPrivate(ip), ip);
  for (const ip of ["8.8.8.8", "172.15.0.1", "172.32.0.1", "1.1.1.1", "2606:4700::1"])
    assert.ok(!isPrivate(ip), ip);
});

test("assertPublic rejects the schemes and hosts we never want to fetch", async () => {
  await assert.rejects(() => assertPublic("file:///etc/passwd"), /http\(s\) only/);
  await assert.rejects(() => assertPublic("not a url"), /not a url/);
  await assert.rejects(() => assertPublic("http://localhost:8080/x"), /private address/);
});

// A dead product link that redirects to the homepage is the common case, not the rare
// one — allbirds.com does it — and 200 OK is what comes back.
const HOMEPAGE = `<html><head>
<title>Page Not Found - Allbirds</title>
<meta property='og:type' content='website'>
<meta property='og:title' content='The World&#39;s Most Comfortable Shoes'>
<meta property='og:description' content='The world&#39;s most comfortable shoes, made with natural materials like merino wool and sugar cane.'>
<meta property='og:image' content='https://cdn.shop/files/logo-seo.jpg'>
<meta property='og:site_name' content='Allbirds'>
</head></html>`;

test("a landing page is not a garment", () => {
  const p = parseProduct(HOMEPAGE, "https://www.allbirds.com/products/gone");
  assert.equal(p.isProduct, false, "nothing here is selling one thing");
  assert.equal(p.image, null, "a logo is not something you can wear");
  // The three things that would each be enough on their own.
  assert.equal(parseProduct(LD, "https://s.com/p").isProduct, true, "json-ld Product");
  assert.equal(parseProduct(OG, "https://s.com/p").isProduct, true, "a price");
  assert.equal(parseProduct(`<meta property="og:type" content="product">`, "https://s.com/p").isProduct, true, "og:type");
});

test("the model is not told the same thing twice", () => {
  const { prompt } = garmentPrompt({
    name: "Ribbed Knit Midi Dress",
    description: "Ribbed knit midi dress in a soft cotton, with a high neck and long sleeves.",
  });
  assert.equal(prompt.match(/ribbed knit midi dress/g).length, 1, `said it twice: ${prompt}`);
  // A description that starts somewhere else is still worth keeping.
  assert.match(garmentPrompt({ name: "Aphrodite Slip", description: "Bias-cut silk satin with thin straps." }).prompt,
               /silk satin/);
});
