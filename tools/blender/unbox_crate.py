"""Dusty Finds mystery crate for the unboxing show: a weathered wooden shipping crate (planks with gaps, grain, bevels,
iron straps and rivets, a stencilled "?", a paper tag) lit like a real object, with hot light leaking out of every gap.
Rendered with Cycles in several states, then bloomed in numpy (threshold -> multi-radius gaussian -> additive) so the light
really looks like it is trying to burst out. Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/unbox_crate.py
Writes assets/vfx/crate_closed_0..3.png (light building up), crate_open.png (lid off, light pouring out), crate_lid.png
(the lid alone, cropped; its placement is printed), all 800 x 800 RGBA with the crate in the same place in every frame.
"""

import math
import os
import random
import tempfile

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "vfx")
os.makedirs(OUT, exist_ok=True)
RES = 800
random.seed(11)

W, D, H = 1.0, 0.7, 0.6  # crate width (x), depth (y), height (z), metres
T = 0.024  # plank thickness
GAP = 0.012  # gap between planks (the light comes out here)

# ---------- scene reset ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 56
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 6
scene.render.resolution_x = scene.render.resolution_y = RES
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0.0

world = bpy.data.worlds.new("w")
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.10, 0.075, 0.06, 1)
bg.inputs["Strength"].default_value = 0.45
scene.world = world

EMIT_NODES = []  # every emission node, so a state can set the glow strength


# ---------- materials ----------
def wood_mat(seed, tint):
    m = bpy.data.materials.new(f"wood{seed}")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = (random.random() * 9, random.random() * 9, random.random() * 9)
    mp.inputs["Scale"].default_value = (0.55, 16, 16)  # long streaks along the plank
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 3.4
    n1.inputs["Detail"].default_value = 11
    n1.inputs["Roughness"].default_value = 0.62
    n2 = nt.nodes.new("ShaderNodeTexNoise")  # big weathering blotches
    n2.inputs["Scale"].default_value = 2.2
    n2.inputs["Detail"].default_value = 4
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.28
    ramp.color_ramp.elements[0].color = (0.085 * tint, 0.042 * tint, 0.02 * tint, 1)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (0.36 * tint, 0.20 * tint, 0.095 * tint, 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["Factor"].default_value = 0.35
    mix.inputs["B"].default_value = (0.20, 0.17, 0.14, 1)  # grey weathering
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.01
    L = nt.links
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    L.new(mp.outputs["Vector"], n1.inputs["Vector"])
    L.new(tc.outputs["Object"], n2.inputs["Vector"])
    L.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    L.new(ramp.outputs["Color"], mix.inputs["A"])
    L.new(n2.outputs["Fac"], mix.inputs["Factor"])
    L.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    L.new(n1.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.62
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def flat_mat(name, rgb, rough=0.6, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def glow_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.80, 0.40, 1)
    em.inputs["Strength"].default_value = 0.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    EMIT_NODES.append(em)
    return m


STEEL = flat_mat("steel", (0.20, 0.205, 0.22), 0.42, 1.0)
RIVET = flat_mat("rivet", (0.30, 0.30, 0.31), 0.35, 1.0)
INK = flat_mat("ink", (0.30, 0.045, 0.03), 0.85)
PAPER = flat_mat("paper", (0.74, 0.64, 0.44), 0.9)
GLOW = glow_mat("glow")
DARK_IN = flat_mat("inside", (0.05, 0.035, 0.025), 0.9)


# ---------- geometry helpers ----------
def box(name, size, loc, rot=(0, 0, 0), mat=None, bevel=0.005, seed=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        bm = o.modifiers.new("bevel", "BEVEL")
        bm.width = bevel
        bm.segments = 2
        bm.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat or wood_mat(seed, random.uniform(0.82, 1.15)))
    return o


def cyl(name, r, h, loc, rot, mat):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=14, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    return o


body_parts, lid_parts, glow_parts = [], [], []
n_pl = 4
ph = (H - GAP * (n_pl - 1)) / n_pl  # plank height

# front and back walls: planks along x
for side, y in (("front", -D / 2), ("back", D / 2)):
    for i in range(n_pl):
        z = ph / 2 + i * (ph + GAP)
        jitter = random.uniform(-0.004, 0.004)
        p = box(f"{side}{i}", (W - 0.04 + random.uniform(-0.006, 0.006), T, ph), (jitter, y, z), seed=i + (0 if side == "front" else 20))
        body_parts.append(p)
        if i < n_pl - 1:  # the light strip that fills the gap above this plank
            g = box(f"{side}gap{i}", (W - 0.06, T * 0.5, GAP * 0.9), (0, y + (0.002 if side == "front" else -0.002), z + ph / 2 + GAP / 2), mat=GLOW, bevel=0)
            glow_parts.append(g)
            body_parts.append(g)
# side walls: planks along y
for side, x in (("left", -W / 2 + T / 2), ("right", W / 2 - T / 2)):
    for i in range(n_pl):
        z = ph / 2 + i * (ph + GAP)
        p = box(f"{side}{i}", (T, D - 2 * T, ph), (x, 0, z), seed=40 + i + (0 if side == "left" else 10))
        body_parts.append(p)
# floor (interior bottom)
floor = box("floor", (W - 2 * T, D - 2 * T, 0.02), (0, 0, 0.012), mat=DARK_IN, bevel=0)
body_parts.append(floor)
# corner posts
for sx in (-1, 1):
    for sy in (-1, 1):
        body_parts.append(box("post", (0.055, 0.055, H + 0.01), (sx * (W / 2 - 0.0275), sy * (D / 2 - 0.0275), H / 2), seed=70 + sx + sy))
# iron straps (top and bottom bands on front and back, with rivets)
for y in (-D / 2 - 0.005, D / 2 + 0.005):
    for z in (0.07, H - 0.07):
        body_parts.append(box("band", (W + 0.012, 0.012, 0.05), (0, y, z), mat=STEEL, bevel=0.003))
        for xr in (-0.42, -0.28, -0.14, 0.14, 0.28, 0.42):
            body_parts.append(cyl("rivet", 0.011, 0.01, (xr, y + (-0.005 if y < 0 else 0.005), z), (math.pi / 2, 0, 0), RIVET))
# vertical straps on the front
for x in (-0.27, 0.27):
    body_parts.append(box("strap", (0.05, 0.012, H - 0.02), (x, -D / 2 - 0.007, H / 2), mat=STEEL, bevel=0.003))
    for zr in (0.2, 0.3, 0.4):
        body_parts.append(cyl("rivet", 0.011, 0.01, (x, -D / 2 - 0.0135, zr), (math.pi / 2, 0, 0), RIVET))
# stencilled "?" and a paper tag
bpy.ops.object.text_add(location=(0, -D / 2 - 0.0125, 0.255), rotation=(math.pi / 2, 0, 0))
q = bpy.context.active_object
q.data.body = "?"
q.data.size = 0.34
q.data.extrude = 0.002
q.data.align_x = "CENTER"
q.data.align_y = "CENTER"
q.data.materials.append(INK)
body_parts.append(q)
tag = box("tag", (0.2, 0.004, 0.12), (0.30, -D / 2 - 0.016, 0.44), rot=(0, math.radians(2.5), math.radians(-4)), mat=PAPER, bevel=0.001)
body_parts.append(tag)

# lid: planks across, cleats, a small gap under it for light
LID_Z = H + 0.03
for i in range(5):
    lw = (D + 0.05 - GAP * 4) / 5
    y = -D / 2 - 0.025 + lw / 2 + i * (lw + GAP)
    lid_parts.append(box(f"lid{i}", (W + 0.05, lw, 0.03), (0, y, LID_Z), seed=90 + i))
    if i < 4:
        g = box(f"lidgap{i}", (W + 0.03, GAP * 0.9, 0.02), (0, y + lw / 2 + GAP / 2, LID_Z), mat=GLOW, bevel=0)
        glow_parts.append(g)
        lid_parts.append(g)
for x in (-0.34, 0.34):
    lid_parts.append(box("cleat", (0.07, D - 0.05, 0.026), (x, 0, LID_Z - 0.026), seed=95))
for y in (-D / 2 - 0.01, D / 2 + 0.01):
    lid_parts.append(box("lidband", (W + 0.06, 0.012, 0.034), (0, y, LID_Z + 0.002), mat=STEEL, bevel=0.003))
# the crack of light between lid and body
crack = box("crack", (W - 0.03, D + 0.02, 0.008), (0, 0, H + 0.008), mat=GLOW, bevel=0)
glow_parts.append(crack)
body_parts.append(crack)
# the pool of light inside (only seen when open)
pool = box("pool", (W - 0.14, D - 0.14, 0.004), (0, 0, 0.03), mat=GLOW, bevel=0)
glow_parts.append(pool)
body_parts.append(pool)

# ---------- lights + camera ----------
def area(name, loc, energy, size, rgb):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = energy
    ld.size = size
    ld.color = rgb
    o = bpy.data.objects.new(name, ld)
    bpy.context.collection.objects.link(o)
    o.location = loc
    c = o.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"


target = bpy.data.objects.new("target", None)
bpy.context.collection.objects.link(target)
target.location = (0, 0, 0.34)
area("key", (-1.6, -2.4, 2.4), 250, 1.6, (1.0, 0.86, 0.68))
area("fill", (2.6, -1.8, 1.0), 70, 2.2, (0.7, 0.82, 1.0))
area("rim", (0.4, 2.6, 2.0), 300, 1.2, (1.0, 0.78, 0.55))

cam_d = bpy.data.cameras.new("cam")
cam_d.lens = 85
cam = bpy.data.objects.new("cam", cam_d)
bpy.context.collection.objects.link(cam)
elev = math.radians(17)
dist = 3.55
cam.location = (0, -dist * math.cos(elev), 0.34 + dist * math.sin(elev))
c = cam.constraints.new("TRACK_TO")
c.target = target
c.track_axis = "TRACK_NEGATIVE_Z"
c.up_axis = "UP_Y"
scene.camera = cam


# ---------- render + bloom ----------
def blur(a, sigma):
    h, w = a.shape[:2]
    fx = np.fft.fftfreq(w)[None, :]
    fy = np.fft.fftfreq(h)[:, None]
    g = np.exp(-2 * np.pi ** 2 * sigma ** 2 * (fx ** 2 + fy ** 2))
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g))
    return np.dstack([np.real(np.fft.ifft2(np.fft.fft2(a[..., k]) * g)) for k in range(a.shape[2])])


def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def render(state_name, show_body=True, show_lid=True, glow=0.0, pool=0.0, gain=1.0, crop=False):
    for o in body_parts:
        o.hide_render = not show_body
    for o in lid_parts:
        o.hide_render = not show_lid
    for o in glow_parts:
        if o.name.startswith("pool"):
            o.hide_render = not (show_body and pool > 0)
        elif o.name.startswith("crack"):
            o.hide_render = not (show_body and show_lid and glow > 0)
        elif o.name.startswith("lidgap"):
            o.hide_render = not (show_lid and glow > 0)
        else:
            o.hide_render = not (show_body and glow > 0)
    for em in EMIT_NODES:
        em.inputs["Strength"].default_value = max(glow, pool)
    tmp = os.path.join(tempfile.gettempdir(), f"df_{state_name}.png")
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    img.colorspace_settings.name = "Non-Color"
    px = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
    bpy.data.images.remove(img)
    rgb, a = px[..., :3], px[..., 3]
    P = rgb * a[..., None]  # premultiplied
    lum = (P[..., 0] * 0.299 + P[..., 1] * 0.587 + P[..., 2] * 0.114)
    bright = P * smooth(0.55, 0.95, lum)[..., None]
    # multi-radius bloom: tight halo, soft bloom, wide atmosphere
    bloom = blur(bright, 5) * 0.8 + blur(bright, 16) * 0.5 + blur(bright, 46) * 0.35
    tint = np.array([1.0, 0.84, 0.55], dtype=np.float32)
    # the bloom is light in the AIR: strong outside the crate, only a faint veil over the wood (or it washes the crate white)
    B = bloom * tint * gain * (0.12 + 0.88 * (1 - a))[..., None]
    Pn = P + B
    bl = (B[..., 0] * 0.299 + B[..., 1] * 0.587 + B[..., 2] * 0.114)
    an = np.clip(a + (1 - a) * np.clip(bl * 1.5, 0, 1), 0, 1)
    rgb_n = np.clip(Pn / np.maximum(an[..., None], 1e-4), 0, 1)
    rgb_n = np.where(an[..., None] < 1e-4, 0, rgb_n)
    res = np.dstack([rgb_n, an]).astype(np.float32)
    box_ = None
    if crop:
        ys, xs = np.where(a > 0.02)
        pad = 6
        y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad, RES - 1)
        x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad, RES - 1)
        res = res[y0:y1 + 1, x0:x1 + 1]
        # bottom-up -> report as fractions from the TOP-left (UI space)
        box_ = (x0 / RES, (RES - 1 - y1) / RES, (x1 - x0 + 1) / RES, (y1 - y0 + 1) / RES)
    h, w = res.shape[:2]
    out = bpy.data.images.new(state_name, w, h, alpha=True)
    out.colorspace_settings.name = "Non-Color"
    out.alpha_mode = "STRAIGHT"
    out.pixels.foreach_set(res.ravel())
    out.filepath_raw = os.path.join(OUT, state_name + ".png")
    out.file_format = "PNG"
    out.save()
    print("wrote", out.filepath_raw, (w, h), "bbox(x,y,w,h from top-left):", box_)


render("crate_closed_0", glow=0.0, gain=0.0)
render("crate_closed_1", glow=5.0, gain=0.8)
render("crate_closed_2", glow=12.0, gain=1.0)
render("crate_closed_3", glow=30.0, gain=1.3)
render("crate_open", show_lid=False, glow=24.0, pool=22.0, gain=1.4)
render("crate_lid", show_body=False, glow=0.0, gain=0.0, crop=True)
print("done")
