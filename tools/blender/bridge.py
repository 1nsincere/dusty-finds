"""Canal bridge: a stone segmental-arch footbridge with stairs, balustrades and lanterns (Blender 5.x, headless). Visual only.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/bridge.py
Writes assets/models/Bridge.glb and assets/previews/Bridge_*.png (git-ignored).

Fits the canal blockout (docs/Environment_Art.md): canal walls 15.2 apart, walks at +4, deck top at +8.5.
Origin = centre of the span at WALK level (world +4). Span along X, width along Y (9), Z up.
Deck top z 4.5; 6 steps of 0.75 each side (run 1.0) from the deck edge (x +-7.6) down to the walk; arch crown z 3.2
(world +7.2 = 6.6 studs over the water at +0.6). Studio keeps the blockout parts as the invisible walking surface,
so this mesh never collides; for the 19.2-wide south canal Studio stretches it along X.
Groups: Bridge_Stone (textured stone), Bridge_Trim (limestone), Bridge_Iron, Bridge_Lamp, Bridge_Leaves, Bridge_Flowers.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"stone": "D9CDB4", "white": "F4EEDF", "leaf": "3F7F3A", "pink": "E0458C"})
c.reset_scene()
G = {}
HALF = 7.6        # deck half-span (canal walls)
W = 4.5           # half width
TOP = 4.5         # deck top
CROWN = 3.2       # arch crown (intrados)
RISE = 4.2        # arch rise above the springing line
R = (HALF ** 2 + RISE ** 2) / (2 * RISE)
CZ = CROWN - R    # arch circle centre


def add(g, o):
    G.setdefault(g, []).append(o)
    return o


def cyl(name, r, h, loc, verts=32, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def mesh_from(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def prism_xz(name, pts, y0, y1):
    """Extrude a profile in (x, z) along Y."""
    n = len(pts)
    verts = [(x, y, z) for y in (y0, y1) for (x, z) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return mesh_from(name, verts, faces)


def boolean(t, o):
    m = t.modifiers.new("b", "BOOLEAN")
    m.object = o
    m.operation = "DIFFERENCE"
    m.solver = "EXACT"
    bpy.context.view_layer.objects.active = t
    bpy.ops.object.modifier_apply(modifier="b")
    bpy.data.objects.remove(o, do_unlink=True)


def blob(r, loc, s=0.28):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        nrm = v.co.normalized()
        k = 1 + s * (math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]) + 0.5 * math.sin(v.co.z * 4.3))
        v.co = nrm * r * k
    bm.to_mesh(o.data)
    bm.free()
    return o


def uv_box(obj, size=8.0):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        for lp in f.loops:
            co = lp.vert.co
            uv = (co.y, co.z) if ax == 0 else ((co.x, co.z) if ax == 1 else (co.x, co.y))
            lp[layer].uv = (uv[0] / size, uv[1] / size)
    bm.to_mesh(obj.data)
    bm.free()


def arc(radius, a0, a1, n=18):
    return [(radius * math.cos(a0 + (a1 - a0) * i / n), CZ + radius * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


aspring = math.asin((0 - CZ) / R) if False else math.atan2(CROWN - RISE - CZ, HALF)  # springing angle (right side)
a_r, a_l = aspring, math.pi - aspring

# ---- body: deck mass with the arch cut out, abutments down into the canal walls ----
body = c.box("body", (2 * HALF + 0.2, 2 * W, TOP + 3.6), (0, 0, (TOP - 3.6) / 2))
cutter = cyl("cut", R, 2 * W + 2, (0, 0, CZ), 64, (math.pi / 2, 0, 0))
boolean(body, cutter)
add("Stone", body)
# ---- stairs: 6 steps each side, from the deck edge down to the walk ----
for s in (-1, 1):
    for k in range(6):
        t = TOP - 0.75 * (k + 1)
        add("Stone", c.box("step", (1.0, 2 * W, t + 0.4), (s * (HALF + k + 0.5), 0, (t - 0.4) / 2)))
        add("Trim", c.box("nosing", (0.18, 2 * W - 0.4, 0.12), (s * (HALF + k + 0.05), 0, t + 0.75 + 0.02)))
# ---- arch ring (voussoirs) on both faces, keystone, string course under the parapet ----
for yf in (-W - 0.15, W + 0.15):
    inner = arc(R, a_r, a_l)
    outer = list(reversed(arc(R + 1.0, a_r - 0.02, a_l + 0.02)))
    add("Trim", prism_xz("ring", inner + outer, yf - 0.15, yf + 0.15))
    for i in range(1, 12):  # voussoir joints: thin grooves read as separate stones
        a = a_r + (a_l - a_r) * i / 12
        x, z = (R + 0.5) * math.cos(a), CZ + (R + 0.5) * math.sin(a)
        j = c.box("joint", (0.06, 0.34, 1.1), (x, yf, z))
        j.rotation_euler = (0, -(a - math.pi / 2), 0)
        add("Stone", j)
    add("Trim", c.box("key", (1.1, 0.5, 1.5), (0, yf, CROWN + 0.55)))
    add("Trim", c.box("string", (2 * HALF + 0.8, 0.45, 0.4), (0, yf, TOP - 0.25)))
# ---- balustrade on the deck: plinth rail, vase balusters, top rail; solid sloped parapets on the stairs ----
for ys in (-1, 1):
    y = ys * (W - 0.35)
    add("Trim", c.box("plinth", (2 * HALF, 0.75, 0.35), (0, y, TOP + 0.17)))
    add("Trim", c.box("toprail", (2 * HALF + 0.4, 0.95, 0.3), (0, y, TOP + 1.65)))
    n = 15
    for i in range(n):
        x = -HALF + 0.5 + i * (2 * HALF - 1.0) / (n - 1)
        b = c.lathe("bal", [(0.01, 0), (0.22, 0), (0.17, 0.2), (0.27, 0.55), (0.13, 0.95), (0.2, 1.1), (0.01, 1.1)], steps=8)
        for v in b.data.vertices:
            v.co.x += x
            v.co.y += y
            v.co.z += TOP + 0.35
        add("Trim", b)
    for s in (-1, 1):  # sloped stair parapets with coping
        L = math.hypot(6.0, 4.5)
        ang = math.atan2(4.5, 6.0)
        p = c.box("sp", (L, 0.7, 1.2), (s * (HALF + 3.0), y, 2.25 + 0.6))
        p.rotation_euler = (0, s * ang, 0)
        add("Stone", p)
        cp = c.box("spc", (L + 0.2, 0.95, 0.25), (s * (HALF + 3.0), y, 2.25 + 1.3))
        cp.rotation_euler = (0, s * ang, 0)
        add("Trim", cp)
        # newel posts: deck corners and stair feet, lanterns on the feet
        add("Trim", c.box("newel_top", (0.9, 0.95, 2.1), (s * HALF, y, TOP + 1.0)))
        add("Trim", c.box("newel", (1.1, 1.1, 2.4), (s * (HALF + 6.3), y, 1.2)))
        add("Trim", c.box("newel_cap", (1.4, 1.4, 0.3), (s * (HALF + 6.3), y, 2.55)))
        add("Iron", cyl("lamp_post", 0.12, 2.4, (s * (HALF + 6.3), y, 3.9), 8))
        add("Iron", c.lathe("lamp_hat", [(0.01, 5.6), (0.55, 5.6), (0.15, 6.0), (0.01, 6.1)], steps=6))
        G["Iron"][-1].location = (s * (HALF + 6.3), y, 0)
        add("Lamp", cyl("lamp", 0.38, 0.9, (s * (HALF + 6.3), y, 5.15), 6))
# ---- flower boxes on the deck parapets (bougainvillea spilling over) ----
for ys in (-1, 1):
    for x in (-3.0, 3.0):
        add("Trim", c.box("fbox", (2.4, 0.8, 0.5), (x, ys * (W + 0.25), TOP + 1.3)))
        for j in range(3):
            add("Leaves", blob(0.42, (x - 0.8 + j * 0.8, ys * (W + 0.35), TOP + 1.7)))
            add("Flowers", blob(0.22, (x - 0.9 + j * 0.8, ys * (W + 0.6), TOP + 1.85)))
            add("Flowers", blob(0.2, (x - 0.5 + j * 0.8, ys * (W + 0.7), TOP + 1.3)))

SPEC = {"Stone": ("stone", "stone"), "Trim": ("white", "limestone"), "Iron": ("black", None), "Lamp": ("warm", None), "Leaves": ("leaf", None), "Flowers": ("pink", None)}
final = []
for name, objs in G.items():
    obj = c.join(objs, "Bridge_" + name) if len(objs) > 1 else objs[0]
    col, tex = SPEC[name]
    c.finish(obj, "Bridge_" + name, col, smooth=name in ("Lamp", "Leaves", "Flowers"))
    if tex:
        uv_box(obj, 8.0)
        tx.apply(obj, tex, "Bridge_" + name + "_mat")
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
print("BRIDGE triangles", c.triangle_count(final), [(o.name, c.triangle_count([o])) for o in final])
c.export_glb(os.path.join(c.OUT_MODELS, "Bridge.glb"), final)


def render(path, cam, target, lens=35, samples=40):
    import mathutils
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1100, 780
    sc.view_settings.view_transform = "AgX"
    if not bpy.data.objects.get("Sun"):
        w = bpy.data.worlds.new("Sky")
        w.use_nodes = True
        sky = w.node_tree.nodes.new("ShaderNodeTexSky")
        w.node_tree.links.new(sky.outputs["Color"], w.node_tree.nodes["Background"].inputs["Color"])
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
        sc.world = w
        sd = bpy.data.lights.new("Sun", "SUN")
        sd.energy = 4.2
        sd.color = (1.0, 0.86, 0.7)
        so = bpy.data.objects.new("Sun", sd)
        bpy.context.collection.objects.link(so)
        so.rotation_euler = (math.radians(55), 0, math.radians(30))
        # canal context (not exported): water, walls, walks
        def blk(name, size, loc, rgba):
            o = c.box(name, size, loc)
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = rgba
            o.data.materials.append(m)
        blk("water", (30, 60, 0.1), (0, 0, -3.4), (0.1, 0.55, 0.65, 1))
        for s in (-1, 1):
            blk("wall", (1.6, 60, 3.6), (s * 6.8, 0, -1.8), (0.85, 0.8, 0.7, 1))
            blk("walk", (9, 60, 0.3), (s * 12.1, 0, -0.15), (0.8, 0.72, 0.6, 1))
    cm = bpy.data.objects.get("Cam") or bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    if not cm.users_collection:
        bpy.context.collection.objects.link(cm)
    cm.data.lens = lens
    cm.location = cam
    cm.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(cam)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cm
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


render(os.path.join(c.OUT_PREVIEWS, "Bridge_side.png"), (6, -30, 4), (0, 0, 1.5))
render(os.path.join(c.OUT_PREVIEWS, "Bridge_walk.png"), (-20, -11, 4.5), (0, 0, 3))
print("done")
