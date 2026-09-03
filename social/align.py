"""
Register posts onto a reference post so the room sits still between frames.

    python3 social/align.py out/09-*.png out/10-*.png [out/11-*.png ...]
    -> aligned/<name>.png   (the first argument is the reference, copied through)

gpt-image rebuilds the room from the reference but drifts a few percent in scale
and tens of pixels in position. Invisible in a still, a hard jump in a video.

ponytail: no search and no OpenCV — the room hands us two rigid landmarks, the
black handle bar and the carpet line, and two points solve a scale + offset
exactly. Rotation is not modelled; the model has never introduced any.
"""
import sys, pathlib, subprocess
import numpy as np
from PIL import Image

W, H = 1152, 2048


def landmarks(path):
    """The left handle bar (x, top, bottom) and the carpet line. Only the left bar
    is used — the right-hand ones fall below the dark threshold in some frames."""
    a = np.asarray(Image.open(path).convert("L"), dtype=float)
    dark = a[:, :200] < 80
    col = int(np.argmax(dark.sum(0)))
    rows = np.where(dark[:, col])[0]
    assert len(rows) > 150, f"{path}: no handle bar found on the left"
    rm = a.mean(1)
    carpet = int(np.argmin(np.diff(rm)[1200:]) + 1200)
    return (col, int(rows.min()), int(rows.max())), carpet


def solve(ref, tgt):
    rb, rc = landmarks(ref)
    tb, tc = landmarks(tgt)
    # two widely separated vertical landmarks -> scale and dy, exactly
    s = (rc - rb[1]) / (tc - tb[1])
    dy = rb[1] - (s * (tb[1] - H / 2) + H / 2)
    dx = rb[0] - (s * (tb[0] - W / 2) + W / 2)
    return s, float(dx), float(dy)


if __name__ == "__main__":
    ref, targets = sys.argv[1], sys.argv[2:]
    out = pathlib.Path("aligned"); out.mkdir(exist_ok=True)
    Image.open(ref).save(out / pathlib.Path(ref).name)
    print(f"ref  {pathlib.Path(ref).name}")
    for t in targets:
        s, dx, dy = solve(ref, t)
        dst = out / pathlib.Path(t).name
        subprocess.run(["magick", t, "-virtual-pixel", "edge", "-distort", "SRT",
                        f"{W/2},{H/2} {s} 0 {W/2+dx},{H/2+dy}", str(dst)], check=True)
        print(f"  -> {dst.name}  scale={s:.4f} dx={dx:+.1f} dy={dy:+.1f}")
