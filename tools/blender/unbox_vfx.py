"""Dusty Finds unboxing VFX sprites: white, tintable light effects with real optical falloff (glow with a long halo,
anamorphic streak flare with lens ghosts, 4+8-point star glints, noise-modulated god rays, a shockwave ring, soft
domain-warped dust puffs, bokeh discs, confetti shards, embers). Everything is white-on-alpha so Roblox can tint it per
rarity with ImageColor3. Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/unbox_vfx.py
Writes assets/vfx/<name>.png (RGBA). Uses Blender's bundled numpy; every shape is analytic (no jaggies at any size).
"""

import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "vfx")
os.makedirs(OUT, exist_ok=True)


# ---------- helpers ----------
def grid(n):
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, -c)  # y up
    return x, y


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise(X, Y, scale, seed):
    """Smooth value noise at coordinates X, Y in [0, 1]."""
    rng = np.random.default_rng(seed)
    g = rng.random((scale + 2, scale + 2))
    x, y = np.clip(X, 0, 0.9999) * scale, np.clip(Y, 0, 0.9999) * scale
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(X, Y, base, octaves, seed):
    total, amp, norm = 0.0, 0.5, 0.0
    for o in range(octaves):
        total = total + amp * vnoise(X, Y, base * (2 ** o), seed + o * 17)
        norm += amp
        amp *= 0.5
    return total / norm


def save(name, rgb, alpha):
    n = alpha.shape[0]
    a = np.clip(alpha, 0, 1)
    if np.isscalar(rgb) or np.ndim(rgb) == 0:
        rgb = np.ones((n, n, 3)) * rgb
    px = np.dstack([np.clip(rgb, 0, 1), a])
    px = np.flipud(px).astype(np.float32)
    img = bpy.data.images.new(name, n, n, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    print("wrote", img.filepath_raw)


def window(r, edge=0.98):
    return 1 - smooth(edge * 0.55, edge, r)


# ---------- sprites ----------
def glow(n=512):
    """Soft light with a hot core, a mid bloom and a long faint halo (inverse-square-ish tail)."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.07) ** 2)
    bloom = np.exp(-(r / 0.22) ** 2) * 0.75
    halo = 1.0 / (1.0 + (r / 0.18) ** 2.4) * 0.5
    a = (core + bloom + halo) * window(r)
    rgb = np.dstack([np.ones_like(r), 1 - 0.05 * (1 - core), 1 - 0.14 * (1 - core)])
    save("glow", rgb, a)


def flare(n=512):
    """Hero flash: glow + long anamorphic streak + a thin vertical streak + faint hexagonal lens ghosts."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.06) ** 2)
    bloom = np.exp(-(r / 0.2) ** 2) * 0.6
    streak = np.exp(-np.abs(y) * 55) * (1 - np.abs(x)) ** 2.2 * 0.85
    vstreak = np.exp(-np.abs(x) * 70) * (1 - np.abs(y)) ** 3 * 0.35
    ghost = 0
    for k, (d, s, w) in enumerate([(0.42, 0.11, 0.18), (0.66, 0.07, 0.12), (-0.5, 0.14, 0.1)]):
        gx, gy = x - d * 0.0 - d, y - d * 0.0
        rr = np.sqrt(gx * gx + gy * gy)
        ghost = ghost + np.exp(-((rr - s) / 0.018) ** 2) * w + np.exp(-(rr / s) ** 2) * w * 0.35
    a = (core + bloom + streak + vstreak + ghost) * (1 - smooth(0.7, 1.0, np.maximum(np.abs(x), np.abs(y))))
    rgb = np.dstack([np.ones_like(r), 1 - 0.06 * smooth(0.05, 0.6, r), 1 - 0.2 * smooth(0.02, 0.5, r)])
    save("flare", rgb, a)


def star(n=256):
    """4-point glint with thin tapered spikes, a smaller 45-degree pair, and a hot centre."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    h = np.exp(-np.abs(y) * 38) * (1 - np.abs(x)) ** 2.6
    v = np.exp(-np.abs(x) * 38) * (1 - np.abs(y)) ** 2.6
    u, w = (x + y) * 0.7071, (x - y) * 0.7071
    d1 = np.exp(-np.abs(w) * 60) * (1 - np.abs(u)) ** 3 * 0.35
    d2 = np.exp(-np.abs(u) * 60) * (1 - np.abs(w)) ** 3 * 0.35
    core = np.exp(-(r / 0.09) ** 2) + 0.35 * np.exp(-(r / 0.25) ** 2)
    a = (h + v + d1 + d2 + core) * window(r, 1.0) * (1 - smooth(0.82, 1.0, np.maximum(np.abs(x), np.abs(y))))
    save("star", 1.0, a)


def rays(n=1024):
    """God rays: many spokes of different width and brightness, noise-modulated so they look like light through dust."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    rng = np.random.default_rng(7)
    spokes = np.zeros_like(r)
    for i in range(34):
        phi = rng.random() * 2 * np.pi
        width = 0.025 + rng.random() * 0.09
        amp = 0.25 + rng.random() * 0.75
        d = np.angle(np.exp(1j * (th - phi)))
        spokes = np.maximum(spokes, amp * np.exp(-(d / width) ** 2))
    X, Y = (x + 1) / 2, (y + 1) / 2
    dust = 0.65 + 0.7 * fbm(X, Y, 6, 3, 3)
    fall = (1 - smooth(0.05, 1.0, r)) ** 1.35 * smooth(0.0, 0.1, r)
    a = spokes * dust * fall * 0.95
    save("rays", 1.0, a)


def ring(n=512):
    """Shockwave: bright thin crest, soft trailing wake inside, faint outer halo, slight angular wobble."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    wob = 0.012 * np.sin(th * 7 + 1.3) + 0.008 * np.sin(th * 13)
    rr = r + wob
    crest = np.exp(-((rr - 0.7) / 0.022) ** 2)
    wake = np.where(rr < 0.7, np.exp(-((0.7 - rr) / 0.16) ** 2), 0) * 0.45
    halo = np.exp(-((rr - 0.7) / 0.1) ** 2) * 0.3
    a = (crest + wake + halo) * window(r, 1.0)
    save("ring", 1.0, a)


def puff(n=512):
    """Soft dust puff: domain-warped fbm, faked top-light shading, feathered edge."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    X, Y = (x + 1) / 2, (y + 1) / 2
    wx = fbm(X, Y, 4, 3, 11) - 0.5
    wy = fbm(X, Y, 4, 3, 23) - 0.5
    d = fbm(X + wx * 0.45, Y + wy * 0.45, 5, 5, 31)
    body = smooth(0.18, 0.7, d) * (1 - smooth(0.35, 0.92, r + (d - 0.5) * 0.35))
    gy = np.gradient(d, axis=0)  # fake light from the top
    shade = np.clip(0.82 + gy * 55, 0.55, 1.0)
    rgb = np.dstack([shade, shade * 0.985, shade * 0.95])
    save("puff", rgb, body * 0.92)


def bokeh(n=256):
    """Camera-lens bokeh disc: bright rim, soft interior, tiny onion-ring noise."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y)
    edge = np.exp(-((r - 0.82) / 0.05) ** 2) * 0.8
    inner = smooth(0.0, 0.82, 1 - r) * 0.28
    ring2 = 0.05 * np.sin(r * 38) ** 2 * (r < 0.8)
    a = (edge + inner + ring2) * (1 - smooth(0.84, 0.97, r))
    save("bokeh", 1.0, a)


def shard(n=128):
    """Confetti flake: rounded slip folded along a diagonal (two tones), tinted by Roblox per colour."""
    x, y = grid(n)
    ax, ay = np.abs(x) / 0.42, np.abs(y) / 0.86
    sd = (ax ** 6 + ay ** 6) ** (1 / 6) - 1  # superellipse distance
    body = 1 - smooth(-0.04, 0.04, sd)
    fold = smooth(-0.04, 0.04, x * 0.6 + y * 0.8)
    tone = 0.74 + 0.26 * fold + 0.1 * np.exp(-((x * 0.6 + y * 0.8) / 0.03) ** 2)
    rgb = np.dstack([tone, tone, tone])
    save("shard", rgb, body)


def ember(n=128):
    """Teardrop spark: hot head, thin trailing tail (point it up; Roblox rotates it)."""
    x, y = grid(n)
    head = np.exp(-((x / 0.12) ** 2 + ((y + 0.35) / 0.12) ** 2))
    tail = np.exp(-(x / 0.045) ** 2) * smooth(-0.5, 0.85, y) * (1 - smooth(0.6, 0.98, y)) * 0.8
    a = (head + tail) * (1 - smooth(0.85, 1.0, np.maximum(np.abs(x), np.abs(y))))
    save("ember", 1.0, a)


def vignette(n=512):
    """Screen-corner darkening for the final flash (alpha only, tinted black in game)."""
    x, y = grid(n)
    r = np.sqrt(x * x + y * y) / 1.414
    save("vignette", 1.0, smooth(0.25, 1.0, r) ** 1.4)


for fn in (glow, flare, star, rays, ring, puff, bokeh, shard, ember, vignette):
    fn()
print("done:", OUT)
