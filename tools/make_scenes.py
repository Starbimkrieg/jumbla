"""Procedurally paints the top-down battle backgrounds as 1024x512 TGA files.

    python3 tools/make_scenes.py

Writes Media/Scenes/<DUNGEON>.tga. WoW reads uncompressed 24-bit TGA with
power-of-two sizes; the 2:1 image stretches over the 2:1 battle field.
Any 1024x512 image (e.g. a Blender render or painting) can replace these:
    python3 tools/make_scenes.py --convert my_render.png RFC
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

W, H = 1024, 512
OUT = os.path.join(os.path.dirname(__file__), "..", "Media", "Scenes")
rng = np.random.default_rng(7)


def fractal(octaves=6, base=4, persistence=0.55, seed=None):
    """Fractal value noise in [0, 1]."""
    r = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gw, gh = base * 2 ** o * 2, base * 2 ** o
        grid = (r.random((gh + 1, gw + 1)) * 255).astype(np.uint8)
        layer = np.asarray(Image.fromarray(grid).resize((W, H), Image.BICUBIC), np.float32) / 255
        out += layer * amp
        total += amp
        amp *= persistence
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def voronoi_edges(n, seed, jitter_y=1.0):
    """Distance to the nearest Voronoi edge (F2 - F1), small = crack."""
    r = np.random.default_rng(seed)
    pts = np.stack([r.random(n) * W, r.random(n) * H * jitter_y], 1)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    f1 = np.full((H, W), 1e9, np.float32)
    f2 = np.full((H, W), 1e9, np.float32)
    for px, py in pts:
        d = np.hypot(xs - px, ys - py)
        f2 = np.where(d < f1, f1, np.minimum(f2, d))
        f1 = np.minimum(f1, d)
    return f2 - f1


def radial(cx, cy, rx, ry):
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    return np.clip(1 - d, 0, 1)


def mix(a, b, t):
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t


def color(rgb):
    return np.array(rgb, np.float32)[None, None, :] / 255


def vignette(img, strength=0.55):
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xs - W / 2) / (W / 2)) ** 2 + ((ys - H / 2) / (H / 2)) ** 2)
    v = 1 - strength * np.clip(d - 0.35, 0, 1) ** 1.5
    return img * v[..., None]


def blur(arr, radius):
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(data, "RGB").save(os.path.join(OUT, name + ".tga"), compression=None)
    Image.fromarray(data, "RGB").resize((512, 256)).save(os.path.join(OUT, name + "_preview.png"))
    print("wrote", name)


# --------------------------------------------------------------- Ragefire Chasm
def ragefire():
    rock = fractal(7, 3, seed=1)
    detail = fractal(5, 24, seed=2)
    base = mix(color((34, 24, 22)), color((78, 56, 46)), rock * 0.8 + detail * 0.2)
    # basalt plates separated by glowing cracks
    edges = voronoi_edges(70, 3)
    crack = np.clip(1 - edges / 5.0, 0, 1) ** 2 * (fractal(4, 6, seed=4) > 0.35)
    glow = blur(crack, 6) * 1.6
    # lava pools along the top and bottom walls
    wall = fractal(5, 5, seed=5)
    ys = np.mgrid[0:H, 0:W][0].astype(np.float32) / H
    edge_dist = np.minimum(ys, 1 - ys) + (wall - 0.5) * 0.12
    lava = np.clip((0.11 - edge_dist) / 0.05, 0, 1)
    lava_tex = fractal(5, 8, seed=6)
    lava_col = mix(color((255, 80, 10)), color((255, 210, 70)), lava_tex)
    img = base * (1 - glow[..., None] * 0.2)
    img = img + color((255, 90, 20)) * np.clip(glow, 0, 1)[..., None] * 0.35
    img = mix(img, color((230, 120, 40)), np.clip(crack, 0, 1) * 0.6)
    rim = np.clip(blur(lava, 14) * 1.4 - lava, 0, 1)
    img = img + color((255, 80, 20)) * rim[..., None] * 0.45
    img = mix(img, lava_col, lava)
    # scattered embers
    ember = (rng.random((H, W)) > 0.9993).astype(np.float32)
    img = img + color((255, 170, 60)) * blur(ember, 1.5)[..., None] * 3
    return vignette(img, 0.6)


# --------------------------------------------------------------- Deadmines
def deadmines():
    plank_h = 32
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    row = (ys // plank_h).astype(int)
    r = np.random.default_rng(11)
    offsets = r.random(H // plank_h + 1) * 300
    tints = 0.75 + r.random(H // plank_h + 1) * 0.35
    grain = fractal(4, 2, seed=12)
    streak = np.asarray(Image.fromarray((fractal(3, 40, seed=13) * 255).astype(np.uint8)).resize((W // 16, H)).resize((W, H)), np.float32) / 255
    wood = mix(color((70, 44, 24)), color((128, 86, 48)), np.clip(grain * 0.5 + streak * 0.5, 0, 1))
    wood = wood * tints[row][..., None]
    # plank seams and board ends
    seam = (ys % plank_h < 2).astype(np.float32)
    board_len = 220
    end = (((xs + offsets[row]) % board_len) < 2).astype(np.float32)
    img = wood * (1 - 0.65 * np.clip(seam + end, 0, 1))[..., None]
    nails = ((((xs + offsets[row]) % board_len) - 8) ** 2 + ((ys % plank_h) - plank_h / 2) ** 2 < 4).astype(np.float32)
    img = mix(img, color((150, 150, 150)), nails * 0.7)
    # mine-cart rails along the bottom
    for ry in (440, 470):
        rail = np.clip(1 - np.abs(ys - ry) / 3, 0, 1)
        img = mix(img, color((120, 120, 125)), rail * 0.9)
    ties = ((ys > 430) & (ys < 480) & ((xs % 60) < 14)).astype(np.float32)
    img = mix(img, color((45, 30, 18)), ties * 0.6)
    # crates in the corners
    for cx, cy, s in ((60, 60, 70), (140, 40, 50), (960, 70, 80), (900, 460, 60)):
        box = ((np.abs(xs - cx) < s / 2) & (np.abs(ys - cy) < s / 2)).astype(np.float32)
        frame = box * (((np.abs(xs - cx) > s / 2 - 6) | (np.abs(ys - cy) > s / 2 - 6) |
                        (np.abs((xs - cx) - (ys - cy)) < 4))).astype(np.float32)
        shadow = blur(box, 8)
        img = img * (1 - shadow[..., None] * 0.5)
        img = mix(img, color((150, 105, 60)), box)
        img = mix(img, color((85, 55, 30)), frame)
    # lantern light pools
    light = np.zeros((H, W), np.float32)
    for cx, cy in ((180, 256), (520, 120), (520, 400), (860, 256)):
        light += radial(cx, cy, 260, 200) ** 1.5
    img = img * (0.45 + 0.75 * np.clip(light, 0, 1))[..., None]
    img = img + color((255, 170, 70)) * (np.clip(light, 0, 1) ** 3)[..., None] * 0.12
    return vignette(img, 0.65)


# --------------------------------------------------------------- Wailing Caverns
def wailing():
    stone = fractal(7, 3, seed=21)
    detail = fractal(5, 20, seed=22)
    moss = fractal(6, 4, seed=23)
    img = mix(color((40, 46, 40)), color((84, 92, 78)), stone * 0.75 + detail * 0.25)
    moss_mask = np.clip((moss - 0.45) * 4, 0, 1)
    img = mix(img, mix(color((40, 80, 34)), color((90, 140, 60)), detail), moss_mask * 0.8)
    # water channels winding along the top and bottom
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    wob = (fractal(4, 3, seed=24) - 0.5) * 70
    for cy, half in ((40, 34), (472, 34)):
        d = np.abs(ys - cy - wob)
        water = np.clip((half - d) / 8, 0, 1)
        shore = np.clip((half + 10 - d) / 10, 0, 1) - water
        ripple = fractal(4, 16, seed=int(cy))
        wcol = mix(color((20, 70, 80)), color((60, 150, 150)), ripple ** 2)
        img = mix(img, color((120, 130, 90)), np.clip(shore, 0, 1) * 0.5)
        img = mix(img, wcol, water)
    # glowing fungus clusters
    glow = np.zeros((H, W), np.float32)
    r = np.random.default_rng(25)
    for _ in range(26):
        cx, cy = r.random() * W, r.random() * H
        if 120 < cx < 900 and 120 < cy < 390:
            continue  # keep the middle readable
        for _ in range(r.integers(3, 7)):
            ox, oy = cx + r.normal(0, 10), cy + r.normal(0, 10)
            glow += (np.hypot(xs - ox, ys - oy) < r.uniform(2, 5)).astype(np.float32)
    halo = blur(np.clip(glow, 0, 1), 10) * 2.5
    img = img + color((120, 255, 180)) * np.clip(halo, 0, 1)[..., None] * 0.35
    img = mix(img, color((190, 255, 220)), np.clip(glow, 0, 1))
    return vignette(img, 0.6)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--convert":
        src = Image.open(sys.argv[2]).convert("RGB").resize((W, H), Image.LANCZOS)
        save(np.asarray(src, np.float32) / 255, sys.argv[3])
        sys.exit()
    save(ragefire(), "RFC")
    save(deadmines(), "DM")
    save(wailing(), "WC")
