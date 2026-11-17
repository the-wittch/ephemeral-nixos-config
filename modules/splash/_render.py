# _render.py <flake.png> <JetBrainsMono dir> <out>
# Draws the boot splash images: the snowflake breaking into drifting pixels as on the
# wallpaper, the glitch frames, the wordmark, the background and the passphrase box.
# Everything is drawn at 1.5x; the script scales it to the screen.
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

src, fonts, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
X = 1.5
rng = random.Random(7)

flake = Image.open(src).convert("RGBA")
W, H = flake.size
DRIFT = int(200 * X)
px = np.asarray(flake).astype(np.float32)
B = round(5 * X)


def save(img, name):
    # a palette keeps the initrd small; the gradients survive it
    img.quantize(256, method=Image.Quantize.LIBIMAGEQUANT, dither=Image.Dither.FLOYDSTEINBERG).save(
        f"{out}/{name}.png", optimize=True
    )


blocks = []
for by in range(0, H, B):
    for bx in range(0, W, B):
        cell = px[by : by + B, bx : bx + B]
        a = cell[..., 3].mean()
        if a < 40:
            continue
        rgb = (cell[..., :3] * cell[..., 3:4]).sum((0, 1)) / max(cell[..., 3].sum(), 1)
        blocks.append(
            dict(
                x=bx,
                y=by,
                rgb=tuple(int(c) for c in rgb),
                a=a,
                # the right side goes first, as on the wallpaper
                t0=0.62 * (1 - bx / W) + 0.38 * rng.random(),
                dx=(90 + rng.random() * 260) * X * 0.75,
                dy=(rng.random() - 0.62) * 140 * X * 0.75,
            )
        )

SPREAD = 0.4


def dissolved(p):
    """p from 0 (whole) to 1 (gone)."""
    canvas = np.zeros((H, W + DRIFT, 4), np.float32)
    # the glow around the blocks fades as the blocks leave
    mask = np.full((H, W), (1 - min(p, 1)) ** 1.5, np.float32)
    for b in blocks:
        mask[b["y"] : b["y"] + B, b["x"] : b["x"] + B] = 1
    parts = []
    for b in blocks:
        l = (p * (1 + SPREAD) - b["t0"]) / SPREAD
        if l <= 0:
            continue
        mask[b["y"] : b["y"] + B, b["x"] : b["x"] + B] = 0
        if l >= 1:
            continue
        e = l**1.5
        s = max(1, round(B * (1 - 0.5 * l)))
        rgb = tuple(min(255, int(c * (1 + 0.6 * (1 - l)))) for c in b["rgb"])
        parts.append((int(b["x"] + b["dx"] * e), int(b["y"] + b["dy"] * e - 20 * X * e), s, rgb, (1 - l) * min(255, b["a"] * 1.4)))
    canvas[:, :W] = px * mask[..., None]
    for x, y, s, rgb, alpha in parts:
        if 0 <= x < W + DRIFT - s and 0 <= y < H - s:
            canvas[y : y + s, x : x + s, :3] = rgb
            canvas[y : y + s, x : x + s, 3] = np.maximum(canvas[y : y + s, x : x + s, 3], alpha)
    return Image.fromarray(canvas.clip(0, 255).astype(np.uint8))


def glitch(img, strength, seed):
    r = random.Random(seed)
    a = np.asarray(img).copy()
    for _ in range(int(3 + 6 * strength)):
        y0 = r.randrange(0, a.shape[0] - 12)
        hh = r.randrange(4, 20)
        shift = r.choice([-1, 1]) * r.randrange(6, int(12 + 33 * strength))
        a[y0 : y0 + hh] = np.roll(a[y0 : y0 + hh], shift, axis=1)
    sliced = Image.fromarray(a)
    # the wallpaper's cyan and violet ghosts
    al = sliced.getchannel("A").point(lambda v: v * 0.45 * strength)
    g = Image.new("RGBA", sliced.size, (0, 0, 0, 0))
    k = int((3 + 5 * strength) * X)
    for color, dx in (((56, 189, 248), -k), ((168, 85, 247), k)):
        ghost = Image.new("RGBA", sliced.size, color + (0,))
        ghost.putalpha(al)
        g.alpha_composite(ghost, (dx, 0))
    g.alpha_composite(sliced)
    return g


N = 30
for i in range(N):
    save(dissolved(i / (N - 1)), f"dissolve-{i:02}")
whole = dissolved(0)
for i, s in enumerate((0.5, 1.0, 0.4, 0.7)):
    save(glitch(whole, s, i), f"glitch-{i}")

# where the script sheds pixels from, on the right edge, with their colours
edge = sorted(blocks, key=lambda b: -b["x"])[:120]
shed = rng.sample(edge, 28)
with open(f"{out}/shed.script", "w") as f:
    for i, b in enumerate(shed):
        f.write(f"shed_x[{i}] = {b['x']}; shed_y[{i}] = {b['y']}; shed_dx[{i}] = {b['dx'] * 0.5:.1f}; shed_dy[{i}] = {b['dy'] * 0.5:.1f}; shed_phase[{i}] = {rng.random():.3f};\n")
        Image.new("RGBA", (B, B), tuple(min(255, int(c * 1.4)) for c in b["rgb"]) + (230,)).save(f"{out}/pixel-{i}.png")
    f.write(f"shed_count = {len(shed)};\nflake_w = {W};\nflake_h = {H};\n")
    # file names spelled out, so the script never turns a number into text
    for i in range(N):
        f.write(f'frame_names[{i}] = "dissolve-{i:02}.png";\n')
    for i in range(4):
        f.write(f'glitch_names[{i}] = "glitch-{i}.png";\n')
    for i in range(len(shed)):
        f.write(f'pixel_names[{i}] = "pixel-{i}.png";\n')

# the background: the site's ground, the wallpaper's halo, a faint grid fading out, a vignette
BW, BH = 1920, 1080
yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
d = np.hypot(xx - BW / 2, yy - BH * 0.40)
bg = np.zeros((BH, BW, 3), np.float32) + (14, 13, 22)
bg += (np.clip(1 - d / 700, 0, 1) ** 1.6)[..., None] * np.array([124, 58, 237]) * 0.30
grid = ((xx % 64) < 1.5) | ((yy % 64) < 1.5)
bg += (grid * np.clip(1 - d / 800, 0, 1))[..., None] * np.array([109, 93, 252]) * 0.10
bg *= (1 - np.clip((d / 1200 - 0.5) / 0.5, 0, 1) * 0.7)[..., None]
Image.fromarray(bg.clip(0, 255).astype(np.uint8)).save(f"{out}/background.png", optimize=True)


def font(name, size):
    return ImageFont.truetype(f"{fonts}/JetBrainsMono-{name}.ttf", round(size * X))


def tracked(draw, x, y, text, f, fill, track):
    widths = [f.getlength(c) for c in text]
    x0 = x - (sum(widths) + track * (len(text) - 1)) / 2
    for c, w in zip(text, widths):
        draw.text((x0, y), c, font=f, fill=fill)
        x0 += w + track


big = font("ExtraBold", 34)
ww, wh = int(560 * X), int(70 * X)
word = Image.new("RGBA", (ww, wh), (0, 0, 0, 0))
dw = ImageDraw.Draw(word)
t = 10 * X
tracked(dw, ww / 2 - 2 * X, 10 * X, "EPHEMERAL NIX", big, (56, 189, 248, 120), t)
tracked(dw, ww / 2 + 2 * X, 10 * X, "EPHEMERAL NIX", big, (168, 85, 247, 120), t)
glow = Image.new("RGBA", (ww, wh), (0, 0, 0, 0))
tracked(ImageDraw.Draw(glow), ww / 2, 10 * X, "EPHEMERAL NIX", big, (196, 181, 253, 200), t)
word.alpha_composite(glow.filter(ImageFilter.GaussianBlur(6 * X)))
tracked(dw, ww / 2, 10 * X, "EPHEMERAL NIX", big, (238, 240, 255, 255), t)
word.save(f"{out}/wordmark.png", optimize=True)

small = font("Regular", 15)


def label(text, fill, name):
    w = int(small.getlength(text)) + 4
    img = Image.new("RGBA", (w, int(24 * X)), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((2, 2), text, font=small, fill=fill)
    img.save(f"{out}/{name}.png", optimize=True)


label("disk passphrase", (154, 151, 179, 255), "label")
label("TPM PIN", (154, 151, 179, 255), "pin")
label("that didn't unlock it, try again", (240, 145, 155, 255), "wrong")

bw, bh = int(380 * X), int(50 * X)
box = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
ImageDraw.Draw(box).rounded_rectangle((0, 0, bw - 1, bh - 1), int(6 * X), fill=(21, 20, 31, 235), outline=(54, 51, 73, 255), width=max(1, int(X)))
box.save(f"{out}/box.png", optimize=True)
r = int(5 * X)
dot = Image.new("RGBA", (2 * r + 2, 2 * r + 2), (0, 0, 0, 0))
ImageDraw.Draw(dot).ellipse((1, 1, 2 * r, 2 * r), fill=(196, 160, 251, 255))
dot.save(f"{out}/dot.png", optimize=True)
caret = Image.new("RGBA", (max(2, int(2 * X)), int(18 * X)), (196, 160, 251, 160))
caret.save(f"{out}/caret.png")
