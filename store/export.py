#!/usr/bin/env python3
"""Cut every panel in screenshots.html to a 1290x2796 PNG, ready to upload.

Does by script what the header tells you to do by hand (DevTools -> right-click the
.panel node -> Capture node screenshot), so a change to the deck is one command away
from a full set instead of six right-clicks.

    python3 store/export.py        # run from the repo root -> store/export/

ponytail: one headless Chrome per panel. Six panels, a few seconds — not worth a
driver library to keep one browser alive across them.
"""
import re, shutil, subprocess, sys, tempfile
from pathlib import Path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
STORE = Path(__file__).resolve().parent
OUT = STORE / "export"
W, H = 1290, 2796          # App Store iPhone 6.9". Never change these two numbers.

# Show one slot at true size, square-cornered, with nothing else on the page.
SOLO = """
<style>
  header, .slot .cap {{ display: none !important }}
  body {{ margin: 0 !important; background: #fff !important }}
  .rail {{ padding: 0 !important; gap: 0 !important; overflow: visible !important }}
  .slot {{ display: none !important }}
  .slot:nth-child({i}) {{ display: block !important }}
  .frame {{ border-radius: 0 !important; box-shadow: none !important;
            width: {w}px !important; height: {h}px !important }}
  :root {{ --scale: 1 !important }}
</style>"""


def panels(html):
    """The deck's own PANELS array is the manifest — read it rather than keeping a
    second list here that can drift."""
    body = html.split("const PANELS = [", 1)[1].split("\n];", 1)[0]
    return [(n, s) for n, s in
            zip(re.findall(r"\{n:'([^']+)'", body),
                re.findall(r"screen:'([^']+)'", body))]


def main():
    src = STORE / "screenshots.html"
    html = src.read_text()
    deck = panels(html)
    if not deck:
        sys.exit("no panels found in screenshots.html")

    if OUT.exists():
        shutil.rmtree(OUT)          # a stale panel in the folder is worse than no folder
    OUT.mkdir()

    for i, (n, screen) in enumerate(deck, start=1):
        name = f"{i:02d}-{re.sub(r'[^a-z0-9]+', '-', screen.lower()).strip('-')}.png"
        with tempfile.NamedTemporaryFile("w", dir=STORE, suffix=".html", delete=False) as f:
            # written beside screenshots.html so its relative image paths still resolve
            f.write(html + SOLO.format(i=i, w=W, h=H))
            tmp = Path(f.name)
        try:
            subprocess.run([
                CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                "--allow-file-access-from-files", "--autoplay-policy=no-user-gesture-required",
                "--virtual-time-budget=8000", f"--window-size={W},{H}",
                f"--screenshot={OUT / name}", tmp.as_uri(),
            ], capture_output=True, timeout=120)
        finally:
            tmp.unlink(missing_ok=True)
        got = (OUT / name)
        print(f"{'ok ' if got.exists() else 'FAILED'} {name}  ({n} · {screen})")


if __name__ == "__main__":
    main()
