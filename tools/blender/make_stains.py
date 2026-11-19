"""Dirt and rust stain decals for the Wipe and Scrape minigames (replace the placeholder SpawnLocation ring).
Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/make_stains.py
Writes assets/textures/dirt_spot.png and rust_spot.png (512x512 RGBA, soft irregular edge, transparent outside).
Uses only numpy (bundled with Blender) and Blender's image API, no scene.
"""

import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(7)


def value_noise(size, cells, seed):
    """Smooth value noise in 0..1 (bilinear on a random grid)."""
    r = np.random.default_rng(seed)
    grid = r.random((cells + 1, cells + 1))
    x = np.linspace(0, cells, size, endpoint=False)
    xi = x.astype(int)
    xf = x - xi
    xf = xf * xf * (3 - 2 * xf)  # smoothstep
    a = grid[np.ix_(xi, xi)]
    b = grid[np.ix_(xi, xi + 1)]
    c = grid[np.ix_(xi + 1, xi)]
    d = grid[np.ix_(xi + 1, xi + 1)]
    fx = xf[None, :]
    fy = xf[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, seed, octaves=5, base=4):
    total, amp, norm = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        total += value_noise(size, base * 2 ** o, seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


yy, xx = np.mgrid[0:N, 0:N]
dist = np.sqrt((xx - N / 2) ** 2 + (yy - N / 2) ** 2) / (N / 2)  # 0 centre .. 1 edge


def blob(seed, edge=0.78, rough=0.45):
    """Irregular stain mask: a circle whose edge is pushed in and out by noise, with a soft rim."""
    n = fbm(N, seed)
    radius = edge + (n - 0.5) * rough
    m = np.clip((radius - dist) / 0.12, 0, 1)
    return m, n


def save(name, rgb, alpha):
    img = bpy.data.images.new(name, N, N, alpha=True)
    px = np.dstack([rgb, alpha]).astype(np.float32)
    img.pixels.foreach_set(np.flipud(px).ravel())  # Blender stores rows bottom-up
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    print("[stains] wrote", img.filepath_raw)


# ---- dirt: brown-grey grime, speckled, denser in the middle ----------------------------------------
m, n = blob(11)
speck = fbm(N, 40, octaves=4, base=24)
dark = np.array([0.20, 0.15, 0.10])
light = np.array([0.42, 0.35, 0.25])
t = np.clip(n * 1.3 - 0.15 + (speck - 0.5) * 0.6, 0, 1)[..., None]
rgb = dark * (1 - t) + light * t
alpha = m * np.clip(0.55 + (speck - 0.5) * 0.9 + (1 - dist) * 0.35, 0, 1) * 0.95
save("dirt_spot", rgb, alpha)

# ---- rust: orange-brown crust, darker pits, flaky edge ---------------------------------------------
m, n = blob(23, edge=0.8, rough=0.55)
pits = fbm(N, 77, octaves=4, base=18)
flake = (fbm(N, 91, octaves=3, base=32) > 0.42).astype(float)
c1 = np.array([0.55, 0.24, 0.07])  # orange rust
c2 = np.array([0.30, 0.12, 0.05])  # dark brown
c3 = np.array([0.72, 0.38, 0.12])  # bright flecks
t = np.clip((pits - 0.35) * 2.2, 0, 1)[..., None]
rgb = c1 * (1 - t) + c2 * t
fleck = (fbm(N, 55, octaves=2, base=40) > 0.66)[..., None]
rgb = np.where(fleck, c3, rgb)
alpha = m * np.clip(0.75 + flake * 0.25, 0, 1)
save("rust_spot", rgb, alpha)
