"""Procedural, seamless PBR textures for the town (colour + normal), made with numpy inside Blender. No downloads, no licences.

Each texture covers 8 x 8 studs (the box-UV scale used by the building scripts: 1 UV unit = 8 studs).
Colour maps are kept light/neutral where Studio should tint them per building (plaster): SurfaceAppearance.Color multiplies.
apply(obj, kind) replaces the object's material with an image-textured Principled BSDF that the glTF exporter writes out;
Roblox's Import 3D turns it into a SurfaceAppearance.
"""

import bpy
import numpy as np

_cache = {}
rng = np.random.default_rng(11)


def fnoise(n, beta=2.0, lo=2.0):
    """Seamless fractal noise in [0, 1] (periodic because it is built in the frequency domain)."""
    w = rng.standard_normal((n, n))
    f = np.fft.fftfreq(n) * n
    r = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)
    r[0, 0] = 1
    amp = 1.0 / np.maximum(r, lo) ** (beta / 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    out -= out.min()
    return out / out.max()


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([(-dx / l) * 0.5 + 0.5, (-dy / l) * 0.5 + 0.5, (nz / l) * 0.5 + 0.5], -1)


def to_image(name, rgb, non_color=False):
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False, is_data=non_color)
    # colour space first: changing it later reloads the buffer and wipes the pixels (that made the normals black)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((n, n, 1))], -1).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = "PNG"
    img.pack()
    return img


def blocks(n, rows, cols, grout, offset=True, jitter=0.0):
    """Mask of block ids and grout for a running-bond pattern. Returns (grout_mask 0..1, block_value per pixel)."""
    y = np.arange(n)[:, None] / n * rows
    x = np.arange(n)[None, :] / n * cols
    row = np.floor(y).astype(int)
    xs = x + (row % 2) * 0.5 * offset
    col = np.floor(xs).astype(int) % cols
    fy, fx = y - np.floor(y), xs - np.floor(xs)
    g = np.minimum(np.minimum(fy, 1 - fy) * n / rows, np.minimum(fx, 1 - fx) * n / cols)
    mask = np.clip(g / (grout * n / 64), 0, 1)
    ids = (row * 97 + col * 31) % 997
    vals = np.random.default_rng(3).random(997)[ids]
    return mask, vals


def make(kind):
    if kind in _cache:
        return _cache[kind]
    if kind == "plaster":  # warm off-white stucco: soft mottling + fine grain (Studio tints it per building)
        n = 1024
        m = fnoise(n, 2.4, 3)
        g = fnoise(n, 0.9, 1)
        h = 0.65 * m + 0.35 * g
        base = 0.9 + 0.08 * (m - 0.5) + 0.04 * (g - 0.5)
        stain = np.clip((fnoise(n, 3.0, 2) - 0.62) * 2.2, 0, 1)
        col = np.stack([base - 0.05 * stain, base - 0.06 * stain, base - 0.08 * stain], -1)
        nor = normal_from_height(h, 2.2)
    elif kind == "stone":  # cream ashlar blocks with grout (4 courses per 8 studs)
        n = 1024
        mask, vals = blocks(n, 4, 2, 1.2)
        grain = fnoise(n, 1.2, 1)
        m = fnoise(n, 2.2, 3)
        tone = 0.84 + 0.08 * (vals[..., None] - 0.5) + 0.06 * (grain[..., None] - 0.5) + 0.04 * (m[..., None] - 0.5)
        col = tone * np.array([1.0, 0.95, 0.85]) * (0.62 + 0.38 * mask[..., None])
        h = mask * 0.8 + 0.2 * grain
        nor = normal_from_height(h, 5.0)
    elif kind == "limestone":  # smooth carved trim: very fine grain
        n = 512
        g = fnoise(n, 1.1, 1)
        m = fnoise(n, 2.4, 2)
        tone = 0.95 + 0.04 * (g - 0.5) + 0.03 * (m - 0.5)
        col = np.stack([tone, tone * 0.975, tone * 0.93], -1)
        nor = normal_from_height(0.6 * g + 0.4 * m, 1.2)
    elif kind == "clay":  # terracotta with per-tile variation and sun fading
        n = 512
        mask, vals = blocks(n, 9, 9, 0.6, offset=True)
        m = fnoise(n, 2.2, 2)
        g = fnoise(n, 1.0, 1)
        v = vals[..., None]
        col = np.array([0.80, 0.40, 0.25]) * (0.82 + 0.25 * (v - 0.5) + 0.12 * (m[..., None] - 0.5)) + 0.05 * (g[..., None] - 0.5)
        col = col * (0.8 + 0.2 * mask[..., None])
        nor = normal_from_height(mask * 0.5 + 0.5 * g, 2.0)
    elif kind == "wood":  # painted-oak planks with grain
        n = 512
        x = np.arange(n)[None, :] / n
        y = np.arange(n)[:, None] / n
        warp = fnoise(n, 2.0, 2)
        grain = 0.5 + 0.5 * np.sin((x * 60 + warp * 6) * np.pi)
        plank = np.clip(np.abs(((y * 8) % 1) - 0.5) * 2 * 30 - 28.5, 0, 1)
        tone = 0.75 + 0.18 * grain + 0.07 * (fnoise(n, 1.0, 1) - 0.5)
        col = np.stack([tone * 0.62, tone * 0.43, tone * 0.27], -1) * (1 - 0.35 * plank[..., None])
        nor = normal_from_height(grain * 0.4 + plank * 0.6, 2.5)
    elif kind == "marble":  # cream/sand marble floor tiles, 2 x 2 studs, with veins
        n = 1024
        mask, vals = blocks(n, 4, 4, 0.5, offset=False)
        y = np.arange(n)[:, None] / n
        x = np.arange(n)[None, :] / n
        cheq = ((np.floor(y * 4) + np.floor(x * 4)) % 2)
        veins = np.abs(np.sin((x * 3 + y * 2 + fnoise(n, 2.0, 2) * 2.5) * np.pi * 2)) ** 0.25
        tone = 0.9 - 0.12 * cheq - 0.1 * (1 - veins) * 0.6
        col = np.stack([tone, tone * 0.95, tone * 0.86], -1) * (0.7 + 0.3 * mask[..., None])
        nor = normal_from_height(mask, 3.0)
    else:
        raise ValueError(kind)
    out = (to_image(f"T_{kind}_color", col), to_image(f"T_{kind}_normal", nor, non_color=True))
    _cache[kind] = out
    return out


ROUGH = {"plaster": 0.9, "stone": 0.85, "limestone": 0.6, "clay": 0.8, "wood": 0.7, "marble": 0.35}


def apply(obj, kind, name=None, tint=None):
    """Give obj one textured material (its UVs must already be set, e.g. with uv_box)."""
    col, nor = make(kind)
    mat = bpy.data.materials.new(name or f"M_{kind}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    if tint:  # multiply by a constant colour: the glTF exporter writes it as baseColorFactor
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (tint[0], tint[1], tint[2], 1.0)
        nt.links.new(tc.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = ROUGH[kind]
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return mat
