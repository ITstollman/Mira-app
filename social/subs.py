"""
Burn the spoken line onto a talking-head clip as timed subtitles.

    python3 social/subs.py in.mp4 out.mp4

Heavy black outline, same look as caption.py — but each colour word is drawn
in its own colour, so the pairing reads before you finish the sentence.

ponytail: one transparent PNG per cue + ffmpeg overlay enable=between(t,..),
not per-frame compositing. ffmpeg here has no libass, so the text still has to
come from PIL (raqm = HarfBuzz + FriBidi, so the Hebrew orders itself).
"""
import json, os, re, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont
from caption import face, LATIN

HEB = re.compile(r"[֐-׿]")
EMO = re.compile(r"[\U0001F000-\U0001FAFF☀-➿️]")
# Apple's emoji font is bitmap strikes — 160 is the largest PIL will open.
EMOJI = "/System/Library/Fonts/Apple Color Emoji.ttc"
Y = 0.175  # caption baseline, above their heads

# Lifted off the garments, then lightened until each one reads inside the black
# outline. Only black stays dark enough to need the outline flipped to white.
COLORS = {
    "yellow": "#F5CE5A", "green": "#9CAF6B", "olive": "#9CAF6B", "red": "#EC3B2E",
    "denim": "#5B8FD6", "black": "#1A1A1A", "white": "#FFFFFF", "pink": "#F2A8C4",
    "chocolate": "#B0764E", "navy": "#4C74C8", "burgundy": "#C0405F",
    "powder": "#A8C6E8", "blue": "#A8C6E8", "camel": "#C19A6B",
    "cream": "#F0E6D2", "grey": "#9AA0A6", "gray": "#9AA0A6", "brown": "#8A5A3B",
    "mustard": "#E0B33C", "lilac": "#C3A6E0", "forest": "#7FA383",
    # Two-word key wins over the single: "green" on its own is 04's olive.
    "forest green": "#7FA383",
    "rust": "#D2662F", "teal": "#3E8E8E", "sand": "#DCC9A6", "cobalt": "#4A6FE0",
    "mint": "#8FD6B0", "charcoal": "#6E7378", "blush": "#F2C4CE",
}

# Timings from an ElevenLabs scribe pass on the clip, padded to the next breath.
CUES = [
    (0.00, 0.60, "שימי לב ❤️"),
    (0.70, 4.40, "pink + red = bold 💋"),
    (4.55, 8.10, "black + white = classic 🖤"),
    (8.25, 11.95, "mustard + navy = retro 🎞️"),
    (12.10, 15.65, "forest green + camel = luxury ✨"),
    (15.75, 19.35, "lilac + grey = soft ☁️"),
]


def style(tok, prev=""):
    """Colour words in their colour, everything else white. Outline follows the fill."""
    k = re.sub(r"[^a-z]", "", tok.lower())
    c = COLORS.get(f"{re.sub(r'[^a-z]', '', prev.lower())} {k}") or COLORS.get(k)
    if not c:
        return "white", "black"
    lum = (0.2126 * int(c[1:3], 16) + 0.7152 * int(c[3:5], 16) + 0.0722 * int(c[5:7], 16)) / 255
    return c, ("black" if lum > 0.2 else "white")


def runs(text):
    """Split into script runs — SF Hebrew has no Latin glyphs, so each needs its own face."""
    out = []
    for tok in text.split():
        k = "emoji" if EMO.search(tok) else "heb" if HEB.search(tok) else "lat"
        if out and out[-1][0] == k:
            out[-1][1].append(tok)
        else:
            out.append((k, [tok]))
    return out


_EMOJI_CACHE = {}


def emoji_img(ch, px):
    if (ch, px) not in _EMOJI_CACHE:
        im = Image.new("RGBA", (240, 240), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((10, 10), ch, font=ImageFont.truetype(EMOJI, 160),
                                embedded_color=True, anchor="la")
        im = im.crop(im.getbbox())
        # Not all emoji are square — measure the real width or a wide one overlaps.
        _EMOJI_CACHE[ch, px] = im.resize((round(px * im.width / im.height), px), Image.LANCZOS)
    return _EMOJI_CACHE[ch, px]


def cue_png(text, W, H, path):
    """One cue, centred at the top, sized down until it fits the frame."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rr = runs(text)
    # SF Hebrew runs wide; only shrink the Latin face when it has to sit beside it.
    scale = 0.94 if any(k == "heb" for k, _ in rr) else 1.0
    size = round(W * 0.082)
    while True:
        heb, lat = face(size, 860), face(round(size * scale), 800, LATIN)
        space, gap, laid = d.textlength(" ", font=lat), size * 0.26, []
        for k, toks in rr:
            f = None if k == "emoji" else heb if k == "heb" else lat
            dr = "rtl" if k == "heb" else "ltr"
            w = [emoji_img(t, round(size * 0.95)).width if f is None
                 else d.textlength(t, font=f, direction=dr) for t in toks]
            laid.append((f, dr, toks, w, sum(w) + space * (len(toks) - 1)))
        total = sum(r[4] for r in laid) + gap * (len(laid) - 1)
        if total <= W * 0.90 or size <= 12:
            break
        size -= 2

    # A Hebrew line lays its runs right to left; an all-English one goes the
    # other way, or the trailing emoji lands in front of the sentence.
    rtl = any(k == "heb" for k, _ in rr)
    y = H * Y
    x = (W + total) / 2 if rtl else (W - total) / 2
    for f, dr, toks, widths, rw in laid:
        if rtl:
            x -= rw
        cx = x if dr == "ltr" else x + rw
        for i, (t, w) in enumerate(zip(toks, widths)):
            if dr == "rtl":
                cx -= w
            if f is None:
                e = emoji_img(t, round(size * 0.95))
                im.alpha_composite(e, (round(cx), round(y - size * 0.90)))
            else:
                fill, stroke = style(t, toks[i - 1] if i else "")
                d.text((cx, y), t, font=f, fill=fill, direction=dr, anchor="ls",
                       stroke_width=max(2, round(size * 0.13)), stroke_fill=stroke)
            cx += (w + space) if dr == "ltr" else -space
        x += -gap if rtl else rw + gap
    im.save(path)


src, dst = sys.argv[1], sys.argv[2]
if len(sys.argv) > 3:  # [[start, end, text], ...]
    CUES = [tuple(c) for c in json.load(open(sys.argv[3]))]
W, H = (int(x) for x in subprocess.check_output(
    ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
     "stream=width,height", "-of", "csv=p=0:s=x", src]).decode().strip().split("x"))

with tempfile.TemporaryDirectory() as tmp:
    ins, filt, last = [], [], "[0:v]"
    for i, (a, b, t) in enumerate(CUES):
        p = os.path.join(tmp, f"{i}.png")
        cue_png(t, W, H, p)
        ins += ["-i", p]
        lbl = f"[v{i}]"
        filt.append(f"{last}[{i+1}:v]overlay=0:0:enable='between(t,{a},{b})'{lbl}")
        last = lbl
    subprocess.check_call(
        ["ffmpeg", "-y", "-v", "error", "-i", src] + ins +
        ["-filter_complex", ";".join(filt), "-map", last, "-map", "0:a?",
         "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "copy", dst])
print(dst)
