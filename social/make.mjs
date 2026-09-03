/**
 * The colour-pair posts. One cast, one room, one outfit brief per post.
 *
 *   node social/make.mjs            # every post in posts.json that has no png yet
 *   node social/make.mjs 3          # just #3
 *   node social/make.mjs --force    # redo them all
 *
 * ponytail: no deps — node 18+ has fetch, FormData and Blob. The key is read out
 * of the shopify backend's .env because that is where it already lives; export
 * OPENAI_API_KEY yourself and this stops caring.
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ENV = "/Users/itamarstollman/Desktop/images-shopify-app/backend/.env";

const KEY = process.env.OPENAI_API_KEY ||
  (existsSync(ENV) ? readFileSync(ENV, "utf8").match(/^OPENAI_API_KEY=(.+)$/m)?.[1].trim() : "");
if (!KEY) throw new Error(`no OPENAI_API_KEY — not in the environment and not in ${ENV}`);

// --native shoots the headroom in-camera, for when the reference photo already has
// it. Without this the shot is taken short and a band is grown on top — see frame().
const native = process.argv.includes("--native");
const FRAMING = native
  ? `There is CLEAR EMPTY WALL ABOVE THEIR HEADS: roughly the top quarter of the frame
is nothing but wardrobe door, exactly as in the reference photo, and their shoes sit
close to the bottom edge.`
  : `They FILL THE FRAME: heads close
to the top edge, shoes close to the bottom edge, spanning most of the width.`;

/** The cast, the room, the shot. Every post repeats this verbatim — the cast photo
 *  pins the two faces, this pins everything else. Locked casting: duo D on bg 1. */
const CAST = `The SAME two women as the reference photo — identical faces, hair and build.
Both are white women in their early twenties who look young and fresh-faced: bare,
natural-looking skin with almost no makeup, soft natural brows, softer rounder features
rather than sharp editorial bone structure. Girl-next-door, not polished fashion models.
LEFT: golden blonde hair piled into a high messy bun, black oval sunglasses, gold hoops.
RIGHT: dark brunette with a blunt shoulder-length bob, black oval sunglasses.
Behind them, floor-to-ceiling white panelled built-in wardrobe doors filling the entire
wall, with slim matte-black vertical bar handles. Pale grey low-pile carpet visible
across the bottom of the frame.
The camera is DEAD STRAIGHT ON, perfectly perpendicular to the wardrobe doors, lens at
chest height, absolutely no tilt, no angle, no perspective skew — a flat front-on
framing like a mirror photo. They stand side by side with a small gap between them,
shoulders square to the camera, both facing the lens. ${FRAMING} Full body
head to shoes, nothing cropped. Bright natural daylight, sharp, slight grain, authentic
social-media photo. No text, no captions, no watermark, no logo, no graphics.

MATCH THE REFERENCE PHOTO EXACTLY for everything except the clothes: the same room,
the same wardrobe doors and handles in the same places, the same camera position,
height and distance, the same lighting, and the two of them standing in the same
spots at the same size in the frame. Only the outfits change. Vary their arms and
hands slightly — a different natural resting pose — but keep their feet planted
where they are and their shoulders square to the camera.`;

/**
 * 1152x1792 in, exact 9:16 out, with a clean band above their heads for the caption.
 *
 * Asking gpt-image for empty headroom just makes it step back and shrink them, so
 * the band is added afterwards: clone the top 90px of wardrobe door and stretch it
 * to 128px. The doors are flat with *vertical* panel lines, so a vertical stretch
 * is invisible — no seam, no regenerating, subjects stay full size.
 *
 * ponytail: shells out to ImageMagick rather than pulling in sharp. Heads land 15%
 * down, matching the reference. Change 128 to move the band; the crop width has to
 * follow it (w = (1792+band) * 9/16).
 */
function frame(src, dst) {
  execFileSync("magick", [src,
    // Mean of the top 8 rows, extruded to 128 — the wall has only vertical panel
    // lines up there, so one row repeated continues them exactly. Stretching a
    // thicker strip instead replays the wall's own top-to-bottom fall-off and
    // leaves a visible step at the seam.
    "(", "+clone", "-crop", "1152x8+0+0", "+repage", "-resize", "1152x1!", "-resize", "1152x128!",
    // The wall brightens ~2.5% per 116px going down; carry that ramp upward so the
    // band joins the photo with no tonal step, then match its grain (sigma 4.6).
    "-size", "1152x128", "gradient:gray(97.2%)-white", "-compose", "Multiply", "-composite",
    "-attenuate", "0.35", "+noise", "Gaussian",
    ")",
    "-reverse", "-append",
    "-gravity", "center", "-crop", "1080x1920+0+0", "+repage",
    "-resize", "1152x2048!", dst]);
}

const posts = JSON.parse(readFileSync(resolve(HERE, "posts.json"), "utf8"));
// --ref <path> chains off a finished shot instead of the casting photo, which pins
// the room, the camera and where they stand — not just the two faces.
const refArg = process.argv[process.argv.indexOf("--ref") + 1];
const refPath = process.argv.includes("--ref") ? resolve(process.cwd(), refArg) : resolve(HERE, "cast.png");
const cast = readFileSync(refPath);
// A post may name its own reference and cast paragraph — that is how a second
// duo in a second room lives in the same posts.json.
const refCache = new Map();
const refFor = (rel) => {
  const f = resolve(HERE, rel);
  if (!refCache.has(f)) refCache.set(f, readFileSync(f));
  return refCache.get(f);
};
mkdirSync(resolve(HERE, "raw"), { recursive: true });
console.log(`ref: ${refPath}`);

const only = process.argv.find((a) => /^\d+(,\d+)*$/.test(a));
const force = process.argv.includes("--force");

async function shoot(post, i) {
  const out = resolve(HERE, "out", `${String(i + 1).padStart(2, "0")}-${post.slug}.png`);
  if (existsSync(out) && !force) return console.log(`· ${post.slug} — already shot`);

  const form = new FormData();
  form.set("model", "gpt-image-2");
  form.set("prompt", `${post.cast || CAST}\n\nLEFT wears: ${post.left}\nRIGHT wears: ${post.right}`);
  // Shot short so there is room to grow a caption band on top — see frame().
  // gpt-image-2 takes any size whose sides both divide by 16.
  form.set("size", native ? "1152x2048" : "1152x1792");
  form.set("quality", "high");
  form.set("n", "1");
  form.append("image[]", new Blob([post.ref ? refFor(post.ref) : cast], { type: "image/png" }), "cast.png");

  const res = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST", headers: { Authorization: `Bearer ${KEY}` }, body: form,
  });
  if (!res.ok) throw new Error(`${post.slug}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
  const b64 = (await res.json())?.data?.[0]?.b64_json;
  if (!b64) throw new Error(`${post.slug}: no image came back`);
  // The raw 1152x1792 is kept: pass it back as --ref and the next shot inherits
  // this exact room, camera and standing position. The framed copy has a synthetic
  // band on top, which would teach the model the wrong headroom.
  const raw = resolve(HERE, "raw", `${String(i + 1).padStart(2, "0")}-${post.slug}.png`);
  writeFileSync(raw, Buffer.from(b64, "base64"));
  native ? copyFileSync(raw, out) : frame(raw, out);
  console.log(`✓ ${out}`);
}

// ponytail: three at a time. The whole batch at once gets rate-limited and a
// serial run is ten minutes of waiting for twenty posts.
const queue = posts.map((p, i) => [p, i]).filter(([, i]) => !only || only.split(",").includes(String(i + 1)));
for (let i = 0; i < queue.length; i += 3) {
  const slice = queue.slice(i, i + 3);
  const done = await Promise.allSettled(slice.map(([p, n]) => shoot(p, n)));
  done.forEach((d) => d.status === "rejected" && console.error(`✗ ${d.reason.message}`));
}
