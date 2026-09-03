#!/usr/bin/env python3
"""One still + the Hebrew mp3 -> Seedance 2.5 VIDEO-EDIT render, best of 2 takes.

Edit mode is the whole trick: normal Seedance re-sings Hebrew through its vocoder,
but a reference *video* is passed through, so the ElevenLabs track survives intact
and only the lips get animated. See DROP-PINKIE/hebpod/HANDOFF.md.
"""
import difflib, json, os, re, shutil, subprocess, sys, time, unicodedata, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "video")
API = "https://api.atlascloud.ai/api/v1/model"
FF = ["ffmpeg", "-y", "-v", "error"]

STILL = os.path.join(HERE, "out", "09-powderblue-white.png")
MP3 = os.path.join(OUT, "line.mp3")
SCRIPT = "תזכרו, כחול עם לבן זה אלגנטי"
LEAD, TAIL = 0.30, 0.75  # source must be >= 4s or Atlas rejects it outright
SC = "scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,fps=24"

# Verbatim from the handoff; only man->woman and the speaker line are swapped.
PROMPT = (
    "Use the reference video as a storyboard: re-render this exact scene faithfully — the same two "
    "women, the same room, the same locked-off medium shot, the same timing of gestures and "
    "expressions. THE REFERENCE AUDIO IS FINAL AND FIXED: the output audio must be the reference "
    "audio, unchanged — identical voice, words, timing. Do NOT re-perform or re-speak it. "
    "Re-animate the woman on the left so her lips sync precisely to that audio, frame for frame, "
    "natural native articulation. Photorealistic, real skin texture. No music, no text, no watermark."
)


def sh(c):
    return subprocess.check_output(c, stderr=subprocess.DEVNULL).decode()


def keys():
    """Straight out of Railway so nothing lands on disk — this repo is public."""
    d = json.loads(sh(["railway", "variables", "-s", "shopify-images-app-backend", "--json"]))
    return d["ATLAS_API"], d["ELEVENLABS_API_KEY"]


def host(p):
    return json.loads(sh(["curl", "-sS", "-m", "180", "-F", f"files[]=@{p}",
                          "https://uguu.se/upload.php"]))["files"][0]["url"]


def atlas(key, path, body=None):
    c = ["curl", "-sS", "-H", f"Authorization: Bearer {key}", "-H", "Content-Type: application/json"]
    if body:
        c += ["-X", "POST", "-d", f"@{body}"]
    return json.loads(subprocess.check_output(c + [API + path]))


def norm(t):
    return re.sub(r"\s+", " ", "".join(c for c in unicodedata.normalize("NFKD", t)
                  if unicodedata.category(c)[0] in "LN" or c == " ")).strip().lower()


def rd(p):
    w = wave.open(p)
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    return a / (np.abs(a).max() + 1e-9)


def corr(a, b):
    """Waveform match over +-1s of lag. >0.9 = the track passed through; ~0.1 = re-sung."""
    n = min(len(a), len(b))
    x, y, best = a[:n], b[:n], 0.0
    for lag in range(-16000, 16001, 40):
        xx, yy = (x[lag:], y[:n - lag]) if lag >= 0 else (x[:n + lag], y[-lag:])
        best = max(best, abs(np.dot(xx, yy) / (np.linalg.norm(xx) * np.linalg.norm(yy) + 1e-9)))
    return best


ATLAS_KEY, XI = keys()
speech = float(sh(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                   "-of", "csv=p=0", MP3]))
tot = LEAD + speech + TAIL
assert tot >= 4.0, f"source {tot:.2f}s is under the 4s floor Atlas enforces"

COND = f"{OUT}/cond.mp4"
subprocess.check_call(FF + [
    "-loop", "1", "-t", f"{tot:.3f}", "-i", STILL, "-i", MP3,
    "-filter_complex", f"[0:v]{SC}[v];[1:a]adelay={int(LEAD*1000)}:all=1,apad[a]",
    "-map", "[v]", "-map", "[a]", "-t", f"{tot:.3f}",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", COND])
url = host(COND)
print(f"cond {tot:.2f}s -> {url}", flush=True)

live = {}
for take in "ab":
    g = {"model": "bytedance/seedance-2.5/reference-to-video", "prompt": PROMPT,
         "reference_images": [], "reference_videos": [url],
         # adaptive/-1 are mandatory for an edit task; anything else 400s.
         "duration": -1, "ratio": "adaptive", "resolution": "720p",
         "generate_audio": True, "watermark": False, "return_last_frame": False,
         "output_format": "mp4"}
    b = f"{OUT}/.body-{take}.json"
    json.dump(g, open(b, "w"), ensure_ascii=False)
    sub = atlas(ATLAS_KEY, "/generateVideo", b)
    gid = (sub.get("data") or {}).get("id")
    if gid:
        live[take] = gid
        print(f"[{take}] submitted {gid}", flush=True)
    else:
        print(f"[{take}] SUBMIT FAILED {str(sub)[:400]}", flush=True)

t0, done = time.time(), []
while live and time.time() - t0 < 2400:
    time.sleep(15)
    for k, gid in list(live.items()):
        d = atlas(ATLAS_KEY, f"/prediction/{gid}").get("data") or {}
        st = d.get("status")
        if st in ("completed", "succeeded"):
            del live[k]
            subprocess.check_call(["curl", "-sS", "-L", d["outputs"][0], "-o", f"{OUT}/take-{k}.mp4"])
            done.append(k)
            print(f"[{k}] DONE", flush=True)
        elif st in ("failed", "error", "cancelled"):
            del live[k]
            print(f"[{k}] FAILED {str(d.get('error'))[:300]}", flush=True)

subprocess.check_call(FF + ["-i", COND, "-vn", "-ac", "1", "-ar", "16000", "-f", "wav", f"{OUT}/.src.wav"])
src = rd(f"{OUT}/.src.wav")
best = (0.0, None)
for k in sorted(done):
    f = f"{OUT}/take-{k}.mp4"
    subprocess.check_call(FF + ["-i", f, "-vn", "-ac", "1", "-ar", "16000", "-f", "wav", f"{OUT}/.{k}.wav"])
    subprocess.check_call(FF + ["-i", f, "-vn", "-b:a", "128k", f"{OUT}/.{k}.mp3"])
    heard = json.loads(sh(["curl", "-sS", "-m", "180", "-H", f"xi-api-key: {XI}",
                           "-F", "model_id=scribe_v1", "-F", "language_code=heb",
                           "-F", f"file=@{OUT}/.{k}.mp3",
                           "https://api.elevenlabs.io/v1/speech-to-text"])).get("text", "")
    cer = 1 - difflib.SequenceMatcher(None, norm(SCRIPT), norm(heard)).ratio()
    c = corr(rd(f"{OUT}/.{k}.wav"), src)
    dur = sh(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).strip()[:5]
    print(f"{k} dur={dur}s CER={cer*100:.1f}% corr={c:.3f} heard: {heard}", flush=True)
    if c > best[0]:
        best = (c, k)
if best[1]:
    # Seedance pads ~0.4s past the last word and sometimes invents a word in it.
    end = LEAD + speech + 0.15
    subprocess.check_call(FF + ["-i", f"{OUT}/take-{best[1]}.mp4", "-t", f"{end:.3f}",
                                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
                                f"{OUT}/09-powderblue-white.mp4"])
    print(f"PICKED {best[1]} corr {best[0]:.3f} -> video/09-powderblue-white.mp4", flush=True)
else:
    sys.exit("no take survived")
