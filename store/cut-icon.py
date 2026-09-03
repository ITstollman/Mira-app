"""Lift one icon off a sheet of them onto a flat tile colour.

ponytail: keying the cream away ate the glass highlights — a specular streak IS cream.
So the sheet's background is found by flooding in from the border (anything the flood
can't reach stays untouched, whatever its colour) and then repainted in the panel
colour, scaled by its own luminance so the icon's contact shadow survives as a darker
tone instead of a dirty smudge. Output is an opaque square — round it in CSS.

Pass the whole image as the crop and it keeps your framing — only the colour changes.

Usage: python3 cut-icon.py <src.png> <x0> <y0> <x1> <y1> <#hex bg> <out.png> [px]
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

UP = 3
FLOOD, EXACT, PAD = 55, 6, .30   # flood tolerance / "this is sheet, not highlight" / margin
OPEN = 25                        # a trapped-sheet region is wide; a stray bright speck is not

SHEET, out_name = sys.argv[1], sys.argv[7]
x0, y0, x1, y1, hexbg = (*map(int, sys.argv[2:6]), sys.argv[6])
OUT = int(sys.argv[8]) if len(sys.argv) > 8 else 512   # the sheet art is small; ask big and it stays smooth, not sharp
bg = np.array([int(hexbg.lstrip('#')[i:i+2], 16) for i in (0, 2, 4)], float)

cell = Image.open(SHEET).convert('RGB').crop((x0, y0, x1, y1))
big = cell.resize((cell.width * UP, cell.height * UP), Image.LANCZOS)  # work at 3x, downscale at the end
seed = np.array(big.getpixel((1, 1)), float)
a = np.array(big, float)

KEY = (0, 255, 0)
flood = big.copy()
spots = [(0, 0), (big.width - 1, 0), (0, big.height - 1), (big.width - 1, big.height - 1)]

# Sheet trapped inside the art (under a bag handle) never touches the border, so the
# corner flood misses it. It is the sheet's exact ivory though, where a specular streak
# runs whiter and bluer — a tight match, opened to drop specks, finds a seed to flood
# from. Flooding (rather than painting the opened blob) keeps the region's real edge.
for _ in range(6):
    for s_ in spots:
        ImageDraw.floodfill(flood, s_, KEY, thresh=FLOOD)
    m = np.all(np.array(flood) == KEY, axis=-1)
    hole = np.all(np.abs(a - seed) <= EXACT, axis=-1) & ~m
    hole = np.array(Image.fromarray((hole * 255).astype('uint8'))
                    .filter(ImageFilter.MinFilter(OPEN)).filter(ImageFilter.MaxFilter(OPEN))) > 127
    if not hole.any():
        break
    ys_, xs_ = np.where(hole)
    spots = [(int(xs_[0]), int(ys_[0]))]

# Repainting cream as something far away (a pink panel) leaves a cream halo on the
# anti-aliased rim, so claim a few pixels of it. Repainting cream as white doesn't —
# and claiming the rim there would flatten the icon's own edge to grey.
RIM = UP * 2 + 1 if np.abs(bg - seed).max() > 40 else 1
m = np.array(Image.fromarray((m * 255).astype('uint8')).filter(ImageFilter.MaxFilter(RIM))) > 127

ratio = np.clip((a @ [.2126, .7152, .0722]) / (seed @ [.2126, .7152, .0722]), 0, 1.15)[..., None]
a[m] = np.clip(bg * ratio, 0, 255)[m]         # cream -> bg, its shadow -> a darker bg

whole = (x0, y0, x1, y1) == (0, 0, *Image.open(SHEET).size)
if whole:                                      # you framed it; only the colour changes
    Image.fromarray(a.astype('uint8')).resize((OUT, OUT), Image.LANCZOS).save(out_name)
    print(out_name, hexbg, 'as framed')
    raise SystemExit

ys, xs = np.where(~m)                          # square up around the art, margin in flat bg
cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
half = max(ys.max() - ys.min(), xs.max() - xs.min()) / 2 * (1 + PAD)
sq = np.tile(bg, (int(half * 2), int(half * 2), 1))
top, left = int(cy - half), int(cx - half)
y0_, x0_ = max(0, top), max(0, left)
y1_, x1_ = min(a.shape[0], top + sq.shape[0]), min(a.shape[1], left + sq.shape[1])
sq[y0_ - top:y1_ - top, x0_ - left:x1_ - left] = a[y0_:y1_, x0_:x1_]

# no unsharp: the sheet art is a smooth 3D render blown up several times over, so a
# sharpen adds a cyan halo along every pink/white edge and no actual detail.
Image.fromarray(sq.astype('uint8')).resize((OUT, OUT), Image.LANCZOS).save(out_name)
print(out_name, hexbg, sq.shape)
