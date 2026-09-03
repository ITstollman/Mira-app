#!/usr/bin/env python3
"""Cut the shop marks once, for both places that show them.

Sources live in store/logos/src/ at 1600px. Output:
  Mira/Assets.xcassets/shop-<slug>.imageset   44 / 88 / 132  — the in-app BrandRow
  store/logos/<slug>.png                      660            — the App Store panel

Keep the SHOPS list here in step with BrandRow.shops (Mira/Onboarding.swift) and
SHOPS in store/screenshots.html — that Swift list is the source of truth.

    python3 store/logos.py        # run from the repo root
"""
import json, os
from PIL import Image, ImageChops, ImageFilter

SHOPS = ["shein", "hm", "zara", "gap", "asos"]
SRC, OUT = "store/logos/src", "store/logos"


def cut(path, side):
    """Trim the mark to its own bounding box, then re-pad every one to the same
    footprint so the row reads as one row and not five differently-cropped pictures.

    Two kinds of artwork come back from the logo services: a wordmark on white
    (Shein, H&M, Zara) and a coloured tile the brand already treats as its icon
    (Gap's navy, ASOS' black). The first wants breathing room; the second wants to
    bleed, so the tile's own rounded corners do the rounding instead of leaving a
    hard-cornered square floating on white.
    """
    im = Image.open(path).convert("RGBA")
    flat = Image.new("RGB", im.size, "white")
    flat.paste(im, mask=im.split()[3])

    box = ImageChops.difference(flat, Image.new("RGB", im.size, "white")) \
        .convert("L").point(lambda p: 255 if p > 12 else 0).getbbox()
    if box:
        flat = flat.crop(box)

    w, h = flat.size
    i = max(1, int(min(w, h) * 0.02))
    bleeds = all(px != (255, 255, 255) for px in
                 (flat.getpixel(p) for p in ((i, i), (w - 1 - i, i), (i, h - 1 - i), (w - 1 - i, h - 1 - i))))

    fill = 1.0 if bleeds else 0.80
    s = (side * fill) / max(w, h)
    flat = flat.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    sq = Image.new("RGB", (side, side), "white")
    sq.paste(flat, ((side - flat.width) // 2, (side - flat.height) // 2))
    return sq


def imageset(sq, name, base):
    d = f"Mira/Assets.xcassets/{name}.imageset"
    os.makedirs(d, exist_ok=True)
    for scale in (1, 2, 3):
        sq.resize((base * scale, base * scale), Image.LANCZOS).save(f"{d}/{name}@{scale}x.png")
    json.dump({"images": [{"filename": f"{name}@{s}x.png", "idiom": "universal", "scale": f"{s}x"}
                          for s in (1, 2, 3)],
               "info": {"author": "xcode", "version": 1}},
              open(f"{d}/Contents.json", "w"), indent=2)


if __name__ == "__main__":
    for slug in SHOPS:
        src = f"{SRC}/{slug}.png"
        imageset(cut(src, 396), f"shop-{slug}", 44)            # 3x is 132
        # ponytail: the app's 132px goes soft blown up to 470 in the panel, so the
        # store gets its own 660 cut with a light unsharp to survive the upscale.
        cut(src, 660).filter(ImageFilter.UnsharpMask(1.2, 60, 3)).save(f"{OUT}/{slug}.png")
        print("cut", slug)
