#!/usr/bin/env python3
"""Each still -> a talking-head clip on fal's MiniMax H3-max, in parallel.

    python3 social/fal.py 17 18 19 20 21 22

Writes video/<n>-<slug>.mp4. The spoken line lives in LINES below; everything
else is the same locked-off, feet-planted paragraph every post in the series
uses, because H3 will otherwise satisfy "stay in place" by moving the camera.

ponytail: no fal sdk — it is a queue endpoint and two curl calls. The key comes
straight out of Railway so nothing lands on disk; this repo is public.
"""
import base64, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "video")
EP = "minimax/h3-max/image-to-video"

# Colour pair -> what she says.
LINES = {
    17: "rust and cream זה cozy",
    18: "teal and sand זה calm",
    19: "burgundy and camel זה elegant",
    20: "cobalt and white זה sharp",
    21: "mint and denim זה light",
    22: "charcoal and blush זה smart",
}

BEATS = {17: "RUST / CREAM / COZY", 18: "TEAL / SAND / CALM",
         19: "BURGUNDY / CAMEL / ELEGANT", 20: "COBALT / WHITE / SHARP",
         21: "MINT / DENIM / LIGHT", 22: "CHARCOAL / BLUSH / SMART"}

TMPL = """The woman on the LEFT speaks to camera. The woman on the RIGHT does not speak —
mouth closed, she blinks and shifts her weight slightly.

SHE SAYS, ONCE, AND NOTHING ELSE: "{line}"

Israeli Hebrew with English colour words mixed in, the way Israelis actually talk —
code-switching, completely natural, not translated. She is Israeli — the one Hebrew
word, "ze", is said with a native Israeli accent, not an English one.

Three stressed beats: {beats}. Everything between them is light
and unstressed. She starts straight in on the first word, no pause before it.

She is talking to a friend, not presenting.

BOTH WOMEN STAY EXACTLY WHERE THEY ARE STANDING. Their feet stay planted on the
same spot on the floor for the entire shot — nobody steps, walks, drifts sideways,
turns away, moves toward or away from the camera, or swaps places. They may pose:
shift their weight, move their arms and hands, tilt their head, adjust the bag on
the shoulder, small natural movement from the waist up. But their footing does not
change and their shoulders stay square to the camera.

The camera is locked off on a tripod: no pan, no tilt, no zoom, no push in, no
handheld drift. Same room, same wardrobe doors, same framing, same distance, from
the first frame to the last.

Pace it conversational, about two seconds, low and confident — a friend stating
something she considers settled, not a presenter announcing it.

She says the line ONCE and then stops talking. After the line her mouth is closed and
she is silent for the rest of the shot — no second sentence, no muttering, no extra
words. Silence to the end. No music, no text, no captions, no watermark."""


def sh(c, **kw):
    return subprocess.check_output(c, stderr=subprocess.DEVNULL, **kw).decode()


KEY = json.loads(sh(["railway", "variables", "-s", "shopify-images-app-backend", "--json"],
                    cwd="/Users/itamarstollman/Desktop/images-shopify-app/backend"))["FAL_KEY"]
H = ["-H", f"Authorization: Key {KEY}", "-H", "Content-Type: application/json"]


def data_uri(png):
    """JPEG, not PNG — a 2.5MB still becomes ~400KB of base64 in the request body."""
    jpg = subprocess.check_output(["magick", png, "-quality", "92", "jpg:-"])
    return "data:image/jpeg;base64," + base64.b64encode(jpg).decode()


def clip(n, slug, still):
    body = os.path.join(OUT, f".fal-{n}.json")
    json.dump({"prompt": TMPL.format(line=LINES[n], beats=BEATS[n]),
               "prompt_expansion_mode": "disabled", "image_url": data_uri(still),
               "duration": 5, "resolution": "768P"}, open(body, "w"), ensure_ascii=False)
    r = json.loads(sh(["curl", "-sS", "-m", "300", "-X", "POST", *H, "-d", f"@{body}",
                       f"https://queue.fal.run/{EP}"]))
    # Use the URLs fal hands back: a namespaced endpoint's status path is not
    # simply {EP}/requests/{id} and guessing it 404s.
    if not r.get("status_url"):
        return print(f"[{n}] SUBMIT FAILED {str(r)[:300]}", flush=True)
    print(f"[{n}] {r['request_id']}", flush=True)
    for _ in range(160):
        time.sleep(10)
        st = json.loads(sh(["curl", "-sS", *H, r["status_url"]]))
        if st.get("status") == "COMPLETED":
            d = json.loads(sh(["curl", "-sS", *H, r["response_url"]]))
            url = (d.get("video") or {}).get("url")
            dst = os.path.join(OUT, f"{n}-{slug}.mp4")
            subprocess.check_call(["curl", "-sS", "-L", url, "-o", dst])
            return print(f"[{n}] -> {dst}", flush=True)
        if st.get("status") not in ("IN_QUEUE", "IN_PROGRESS"):
            return print(f"[{n}] {st.get('status')} {str(st)[:300]}", flush=True)
    print(f"[{n}] TIMED OUT", flush=True)


posts = json.load(open(os.path.join(HERE, "posts.json")))
want = [int(a) for a in sys.argv[1:]] or sorted(LINES)
jobs = [(n, posts[n - 1]["slug"], os.path.join(HERE, "out", f"{n}-{posts[n-1]['slug']}.png"))
        for n in want]
for n, _, p in jobs:
    assert os.path.exists(p), f"missing still for {n}: {p}"
with ThreadPoolExecutor(len(jobs)) as ex:
    list(ex.map(lambda a: clip(*a), jobs))
