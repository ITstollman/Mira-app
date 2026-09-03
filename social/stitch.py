#!/usr/bin/env python3
"""Trim each talking-head clip at the end of its line, concat, emit the sub cues.

    python3 social/stitch.py video/reel4.mp4 video/reel4-cues.json

H3's floor is a 5s render but the lines run ~2-3.5s, so every clip babbles in the
tail. CUTS below come from an ElevenLabs pass (stt.py) — end of the result word,
plus a breath.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
V = os.path.join(HERE, "video")

# clip, cut at, caption
REEL = [
    ("17-rust-cream", 2.40, "rust + cream = cozy 🍂"),
    ("18-teal-sand", 4.30, "teal + sand = calm 🌾"),
    ("19-burgundy-camel", 2.60, "burgundy + camel = elegant 🍷"),
    ("20-cobalt-white", 3.85, "cobalt + white = sharp 🔷"),
    ("21-mint-denim", 2.10, "mint + denim = light 🌱"),
    ("22-charcoal-blush", 3.70, "charcoal + blush = smart 💼"),
]
GAP = 0.12  # the caption clears before the cut, so it never straddles two looks
# Just enough frozen first frame to land on, then the video rolls under the hook
# caption — the clips start on the first spoken word, there is no head to borrow.
HEAD, HOOK, HOOK_OUT = 0.30, "שימי לב ❤️", 1.00

dst, cues_path = sys.argv[1], sys.argv[2]
still = os.path.join(V, ".head.png")
subprocess.check_call(["ffmpeg", "-y", "-v", "error", "-i", os.path.join(V, f"{REEL[0][0]}.mp4"),
                       "-frames:v", "1", still])
ins = ["-loop", "1", "-t", str(HEAD), "-i", still,
       "-f", "lavfi", "-t", str(HEAD), "-i", "anullsrc=r=44100:cl=stereo"]
filt = ["[0:v]scale=720:1280,fps=24,setpts=PTS-STARTPTS[vh]", "[1:a]asetpts=PTS-STARTPTS[ah]"]
parts, cues, t = ["[vh]", "[ah]"], [[0.0, HOOK_OUT, HOOK]], HEAD
for j, (name, cut, cap) in enumerate(REEL):
    i = j + 2
    ins += ["-i", os.path.join(V, f"{name}.mp4")]
    filt.append(f"[{i}:v]trim=0:{cut},setpts=PTS-STARTPTS,scale=720:1280,fps=24[v{i}]")
    filt.append(f"[{i}:a]atrim=0:{cut},asetpts=PTS-STARTPTS[a{i}]")
    parts += [f"[v{i}]", f"[a{i}]"]
    cues.append([round(max(t + 0.10, HOOK_OUT + 0.15), 2), round(t + cut - GAP, 2), cap])
    t += cut

filt.append("".join(parts) + f"concat=n={len(REEL) + 1}:v=1:a=1[v][a]")
subprocess.check_call(["ffmpeg", "-y", "-v", "error"] + ins +
                      ["-filter_complex", ";".join(filt), "-map", "[v]", "-map", "[a]",
                       "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
                       "-c:a", "aac", "-b:a", "192k", dst])
json.dump(cues, open(cues_path, "w"), ensure_ascii=False, indent=1)
print(f"{dst}  {t:.2f}s")
