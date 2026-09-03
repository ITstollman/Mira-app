#!/usr/bin/env python3
"""Cut panel 01 of screenshots.html to an App Preview video, ready to upload.

The panel is already a live thing — a <video> in the device screen and a chip that
swaps as the garment changes. Recording a browser playing it needs a CDP screencast;
this does the same job with three still renders and one ffmpeg pass, because the only
moving parts are the clip itself and which chip is showing, and both are known.

    python3 store/preview.py     -> store/preview/mira-preview-{886x1920,1290x2796}.mp4

ponytail: the panel is rendered with the screen punched transparent and the video laid
in behind it. Beats recording the browser, and the hole's own bounding box tells us
where to put the clip, so no coordinates are hard-coded.
"""
import re, subprocess, sys, tempfile
from pathlib import Path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
STORE = Path(__file__).resolve().parent
OUT = STORE / "preview"
W, H = 1290, 2796                    # the panel. App Store iPhone 6.9".
SRC = OUT / "mira-preview-6.9.mp4"   # the clip that plays inside the phone
TRIM = 3.5                           # dead air at the head of the clip, cut before anything else

# Panel 01 only, at true size, video hidden. `punch` drops the panel's own flat fill and
# the device body's and the screen's, so what is left is every pixel that must sit ABOVE the clip; the flat fill
# goes back in as a solid canvas in ffmpeg. The screen's rounded corners survive because
# the paper device behind it stays opaque.
SOLO = """
<style>
  header, .slot .cap {{ display: none !important }}
  body {{ margin: 0 !important; background: transparent !important }}
  .rail {{ padding: 0 !important; gap: 0 !important; overflow: visible !important }}
  .slot {{ display: none !important }}
  .slot:nth-child(1) {{ display: block !important }}
  .frame {{ border-radius: 0 !important; box-shadow: none !important;
            width: {w}px !important; height: {h}px !important }}
  :root {{ --scale: 1 !important }}
  .device .screen video {{ visibility: hidden !important }}
  {punch}
</style>
<script>
(() => {{
  const panel = document.querySelector('.slot:nth-child(1) .panel');
  panel.querySelector('video')?.remove();      // takes the deck's chip-sync with it
  const chip = panel.querySelector('.chip'), want = '{chip}';
  if (want) {{ chip.src = want; chip.style.visibility = 'visible'; }} else chip.remove();
}})();
</script>"""


PUNCH = """.panel { background-color: transparent !important }
  .device { background: transparent !important }
  .device .screen { background: transparent !important;
                    box-shadow: 0 0 0 14px var(--paper) !important }"""
# opaque panel, screen flooded with a colour nothing else in the deck uses — the render
# is thrown away, we only want the box it lands in
PROBE = """.device .screen { background: #FF00FF !important }"""


def render(html, chip, dest, punch):
    # `punch` is substituted after .format(), so it carries plain braces, not doubled ones
    with tempfile.NamedTemporaryFile("w", dir=STORE, suffix=".html", delete=False) as f:
        f.write(html + SOLO.format(w=W, h=H, chip=chip, punch=punch))  # beside the source, so paths resolve
        tmp = Path(f.name)
    try:
        subprocess.run([
            CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--allow-file-access-from-files", "--default-background-color=00000000",
            "--force-device-scale-factor=1",
            "--virtual-time-budget=8000", f"--window-size={W},{H}",
            f"--screenshot={dest}", tmp.as_uri(),
        ], capture_output=True, timeout=120)
    finally:
        tmp.unlink(missing_ok=True)
    if not dest.exists():
        sys.exit(f"chrome produced nothing for {dest.name}")


def hole(png):
    """Where the screen is, read off the probe's flood colour."""
    out = subprocess.run(["magick", str(png), "-fuzz", "2%", "-transparent", "#FF00FF",
                          "-alpha", "extract", "-negate",
                          "-format", "%@", "info:"], capture_output=True, text=True).stdout
    m = re.match(r"(\d+)x(\d+)\+(\d+)\+(\d+)", out.strip())
    if not m:
        sys.exit(f"no transparent screen found in {png.name} (got {out!r})")
    w, h, x, y = map(int, m.groups())
    return x, y, w, h


def main():
    html = (STORE / "screenshots.html").read_text()
    if not SRC.exists():
        sys.exit(f"missing {SRC}")

    # the deck's own cue table is the manifest — read it rather than restating it here
    cues = re.search(r"const CUES = \[(.+?)\];", html, re.S).group(1)
    cues = [(float(t), c.strip("'") if c.strip() != "null" else None)
            for t, c in re.findall(r"\[([\d.]+), (null|'[^']+')\]", cues)]
    clip = float(re.search(r"const CLIP = ([\d.]+);", html).group(1))

    probe = OUT / ".probe.png"
    render(html, "", probe, PROBE)
    x, y, w, h = hole(probe)
    probe.unlink()
    print(f"screen at {w}x{h}+{x}+{y}")

    layers = []
    for i, (at, chip) in enumerate(cues):
        png = OUT / f".layer{i}.png"
        render(html, chip or "", png, PUNCH)
        layers.append((at, cues[i + 1][0] if i + 1 < len(cues) else clip, png))

    # the panel's flat fill, straight out of the deck's own token
    fill = re.search(r"--core:\s*(#[0-9A-Fa-f]{6})", html).group(1).replace("#", "0x")

    # one full-panel layer active at a time; mod() makes the cues repeat with the loop
    chain = [f"[0:v]scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h}[clip]",
             f"color=c={fill}:s={W}x{H}[bg]", f"[bg][clip]overlay={x}:{y}[v0]"]
    for i, (a, b, png) in enumerate(layers):
        u = f"mod(t+{TRIM},{clip})"
        on = (f"lt({u},{b})" if i == 0 else
              f"gte({u},{a})" if i == len(layers) - 1 else
              f"between({u},{a},{b})")
        chain.append(f"[v{i}][{i+1}:v]overlay=0:0:enable='{on}'[v{i+1}]")
    chain.append(f"[v{len(layers)}]scale=%d:%d[out]")

    # The source is one ~10s cycle recorded twice, so the whole thing plays the same footage
    # over again. `-short` stops after the first pass; the full length stays because App
    # Store Connect refuses an App Preview under 15s, and one pass is only 6.5s.
    # ponytail: the day there is more footage than one cycle, drop the long cut entirely.
    for ow, oh in ((886, 1920), (W, H)):
        for tag, seconds in (("", None), ("-short", round(clip - TRIM, 3))):
            dest = OUT / f"mira-preview{tag}-{ow}x{oh}.mp4"
            fc = ";".join(chain) % (ow, oh)
            cmd = ["ffmpeg", "-v", "error", "-ss", str(TRIM), "-i", str(SRC)]
            for _, _, png in layers:
                cmd += ["-loop", "1", "-i", str(png)]
            # App Store Connect calls a file "corrupted" for things QuickTime plays fine.
            # Three of them bit us: the source's 32kHz audio (Apple wants 44.1 or 48),
            # an `elst` edit list that B-frame CTS offsets drag in, and untagged colour.
            # -bf 0 is what kills the edit list — no reordering, no offset, no atom.
            cmd += ["-filter_complex", fc, "-map", "[out]", "-map", "0:a?",
                    "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
                    "-pix_fmt", "yuv420p", "-bf", "0", "-r", "30", "-crf", "19",
                    "-color_primaries", "bt709", "-color_trc", "bt709",
                    "-colorspace", "bt709", "-video_track_timescale", "30000",
                    # the -color_* flags only reach the container; x264 needs telling too,
                    # or the SPS says "unknown" and the tags disagree with each other
                    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
                    "-c:a", "aac", "-ac", "2", "-ar", "44100", "-b:a", "256k",
                    "-shortest", "-movflags", "+faststart"]
            if seconds:
                cmd += ["-t", str(seconds)]
            subprocess.run(cmd + ["-y", str(dest)], check=True)
            # a .mov of the same stream, for when App Store Connect refuses the .mp4 for
            # reasons it will not name. ponytail: same bytes, different wrapper.
            mov = dest.with_suffix(".mov")
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(dest), "-c", "copy",
                            "-movflags", "+faststart", "-y", str(mov)], check=True)
            print(f"ok  {dest.name}  {seconds or 'full'}")

    for _, _, png in layers:
        png.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
