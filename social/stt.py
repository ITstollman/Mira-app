#!/usr/bin/env python3
"""ElevenLabs scribe on a clip -> transcript + word timings. python3 stt.py x.mp4"""
import json, os, subprocess, sys

BE = "/Users/itamarstollman/Desktop/images-shopify-app/backend"


def sh(c, **kw):
    return subprocess.check_output(c, stderr=subprocess.DEVNULL, **kw).decode()


XI = json.loads(sh(["railway", "variables", "-s", "shopify-images-app-backend", "--json"],
                   cwd=BE))["ELEVENLABS_API_KEY"]
mp3 = "/tmp/.stt.mp3"
subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", sys.argv[1], "-vn", "-b:a", "128k", mp3])
d = json.loads(sh(["curl", "-sS", "-m", "300", "-H", f"xi-api-key: {XI}",
                   "-F", "model_id=scribe_v1", "-F", "language_code=heb", "-F", f"file=@{mp3}",
                   "https://api.elevenlabs.io/v1/speech-to-text"]))
print(d.get("text"))
for w in d.get("words", []):
    if w.get("type") == "word":
        print(f'{w["start"]:.2f}-{w["end"]:.2f}  {w["text"]}')
