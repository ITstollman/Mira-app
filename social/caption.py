"""
Hebrew caption baked into the band at the top of a post.

    python3 social/caption.py out/01-brown-denim.png "חום" "ג'ינס" [--note "..."]

White fill, heavy black outline — reads on any wall tone, which is the whole
point of putting it over the photo instead of a flat bar.

ponytail: PIL because it has raqm here (HarfBuzz + FriBidi), so Hebrew shapes and
orders itself — ImageMagick lists Pango but was built without the delegate.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

SF = "/System/Library/Fonts/SFHebrew.ttf"
# SF Hebrew renders "+" as a broken glyph once the weight axis is pushed, so the
# separator comes off the Latin face instead.
LATIN = "/System/Library/Fonts/SFNS.ttf"


def face(size, weight, path=SF):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def draw(img, parts, note=None, size=86, top=None):
    """parts: the phrases, laid out RIGHT to LEFT with a + between, centred."""
    d = ImageDraw.Draw(img)
    f = face(size, 860)
    fp = face(int(size * 0.82), 800, LATIN)
    stroke = max(2, round(size * 0.11))

    run = []
    for i, t in enumerate(parts):
        if i:
            run.append(("+", fp))
        run.append((t, f))
    run.reverse()

    pad = size * 0.30
    widths = [d.textlength(t, font=ff) for t, ff in run]
    x = (img.width - sum(widths) - pad * (len(run) - 1)) / 2
    y = top if top is not None else int(img.height * 0.080)
    for (t, ff), w in zip(run, widths):
        d.text((x, y + (size * 0.10 if ff is fp else 0)), t, font=ff, fill="white",
               stroke_width=stroke, stroke_fill="black", anchor="la")
        x += w + pad
    if note:
        fn = face(int(size * 0.42), 780)
        d.text((img.width / 2, y + size * 1.20), note, font=fn, fill="white",
               stroke_width=max(2, round(size * 0.055)), stroke_fill="black", anchor="ma")
    return img


if __name__ == "__main__":
    src, args = sys.argv[1], sys.argv[2:]
    note = None
    if "--note" in args:
        i = args.index("--note"); note = args[i + 1]; args = args[:i] + args[i + 2:]
    im = Image.open(src).convert("RGB")
    draw(im, args, note)
    out = src.replace(".png", "-cap.png")
    im.save(out)
    print(out)
