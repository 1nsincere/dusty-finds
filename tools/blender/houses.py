"""Dusty Finds house kit: 5 Filipino-European town houses (Blender 5.x, headless). Scenery only, solid shells (not walk-in).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/houses.py
Writes assets/models/Houses.glb and assets/previews/Houses.png (git-ignored).

Real studs. Every house faces -Y, stands on z = 0, and is centred on x = SPACING * k (k = 0..4) so Studio can split them
by name prefix: HouseA_<Group> ... HouseE_<Group>. Walls are a light neutral plaster: tint each copy in Studio with
SurfaceAppearance.Color for pastel variety. Low detail on purpose (phones): flat glass, boxed shutters, no interiors.
  A Townhouse   22 x 18, 3 floors, iron balcony, hip roof
  B Bahay na bato  24 x 20, stone arcade ground floor, wooden upper floor with capiz windows, big hip roof
  C Shophouse   20 x 18, awning shop front, 2 floors over, flat roof with cornice and parapet
  D Narrow tower house  14 x 16, 4 floors, gable roof facing the street
  E Villa       26 x 22, 2 floors, columned porch with balcony on top, hip roof
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"plaster": "F3EEE4", "cream": "F4EAD2", "stone": "CFC5B0", "glass": "3E5F78", "iron": "2E3236",
                  "wood": "6B4A2E", "capiz": "EDE3C8", "teal": "1F7A7A", "leaf": "3F7F3A", "pink": "E0458C",
                  "awning": "C0392B"})
c.reset_scene()
SPACING = 40.0
G = {}          # (house, group) -> objects
CUR = ["A"]
OX = [0.0]


def add(g, o):
    o.location.x += OX[0]
    G.setdefault((CUR[0], g), []).append(o)
    return o


def start(letter, k):
    CUR[0] = letter
    OX[0] = SPACING * k


def box(g, size, loc, rot=None):
    o = c.box("b", size, loc)
    if rot:
        o.rotation_euler = rot
    return add(g, o)


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


def blob(r, loc, s=0.25):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    o = bpy.context.active_object
    for v in o.data.vertices:
        n = v.co.normalized()
        v.co = n * r * (1 + s * math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]))
    return o


def arch_prism(g, x, zb, w, h, y0, y1, segs=8):
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0), (r, h - r)] + [(r * math.cos(math.pi * i / segs), h - r + r * math.sin(math.pi * i / segs)) for i in range(1, segs)] + [(-r, h - r)]
    n = len(pts)
    verts = [(x + u, a, zb + v) for a in (y0, y1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)] + [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return add(g, mesh_from("arch", verts, faces))


def hip_roof(x0, x1, y0, y1, z, rise, over=1.2, g="Roof"):
    """Closed hip roof; ridge along the longer side."""
    x0, x1, y0, y1 = x0 - over, x1 + over, y0 - over, y1 + over
    w, d = x1 - x0, y1 - y0
    if w >= d:
        h = d / 2
        r0, r1 = (x0 + h, (y0 + y1) / 2, z + rise), (x1 - h, (y0 + y1) / 2, z + rise)
    else:
        h = w / 2
        r0, r1 = ((x0 + x1) / 2, y0 + h, z + rise), ((x0 + x1) / 2, y1 - h, z + rise)
    v = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), r0, r1]
    if w >= d:
        f = [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)]
    else:
        f = [(1, 2, 5, 4), (3, 0, 4, 5), (0, 1, 4), (2, 3, 5), (3, 2, 1, 0)]
    add(g, mesh_from("roof", v, f))
    add("Trim", c.box("eave", (w + 0.2, d + 0.2, 0.5), ((x0 + x1) / 2, (y0 + y1) / 2, z - 0.2)))


def gable_roof_y(x0, x1, y0, y1, z, rise, over=1.0, g="Roof"):
    """Gable with ridge along Y, so the triangle faces the street (-Y)."""
    x0, x1, y0, y1 = x0 - over, x1 + over, y0 - over, y1 + over
    xm = (x0 + x1) / 2
    v = [(x0, y0, z), (x1, y0, z), (xm, y0, z + rise), (x0, y1, z), (x1, y1, z), (xm, y1, z + rise)]
    f = [(0, 1, 2), (5, 4, 3), (0, 2, 5, 3), (2, 1, 4, 5), (0, 3, 4, 1)]
    add(g, mesh_from("groof", v, f))


def window(fy, x, z, w, h, shutters=True, capiz=False, box_flowers=False):
    """Window on the front plane y = fy (front faces -Y)."""
    box("Glass", (w, 0.1, h), (x, fy - 0.03, z + h / 2))
    box("Trim", (w + 0.7, 0.35, 0.35), (x, fy - 0.15, z + h + 0.15))      # lintel
    box("Trim", (w + 0.6, 0.45, 0.3), (x, fy - 0.2, z - 0.1))              # sill
    for s in (-1, 1):
        box("Trim", (0.25, 0.25, h), (x + s * (w / 2 + 0.12), fy - 0.12, z + h / 2))
    if capiz:  # sliding capiz panels: cream grid over the glass
        for k in range(1, 4):
            box("Wood", (0.12, 0.15, h), (x - w / 2 + k * w / 4, fy - 0.1, z + h / 2))
        for k in range(1, 3):
            box("Wood", (w, 0.15, 0.12), (x, fy - 0.1, z + k * h / 3))
    if shutters:
        for s in (-1, 1):
            box("Shutters", (w / 2, 0.15, h), (x + s * (w * 0.75 + 0.35), fy - 0.12, z + h / 2))
    if box_flowers:
        box("Wood", (w, 0.8, 0.6), (x, fy - 0.6, z - 0.2))
        for k in range(3):
            add("Flowers", blob(0.35, (x - w / 3 + k * w / 3, fy - 0.6, z + 0.35)))


def door(fy, x, w=3.0, h=6.0, z=0.0, arched=False):
    box("Wood", (w, 0.2, h), (x, fy - 0.05, z + h / 2))
    box("Trim", (w + 1.0, 0.35, 0.5), (x, fy - 0.15, z + h + 0.25))
    for s in (-1, 1):
        box("Trim", (0.4, 0.35, h), (x + s * (w / 2 + 0.2), fy - 0.15, z + h / 2))
    box("Stone", (w + 1.4, 1.2, 0.4), (x, fy - 0.6, 0.2))


def balcony(fy, x, w, z, depth=1.6):
    box("Trim", (w, depth, 0.35), (x, fy - depth / 2, z))
    box("Iron", (w, 0.12, 0.12), (x, fy - depth + 0.06, z + 2.4))
    for s in (-1, 1):
        box("Iron", (0.12, depth, 0.12), (x + s * w / 2, fy - depth / 2, z + 2.4))
    n = int(w / 0.8)
    for k in range(n + 1):
        box("Iron", (0.08, 0.08, 2.2), (x - w / 2 + k * w / n, fy - depth + 0.06, z + 1.25))
    for k in range(int(w / 3)):
        add("Flowers", blob(0.4, (x - w / 2 + 1.5 + k * 3, fy - depth + 0.3, z + 2.7)))


def body(w, d, h, g="Walls"):
    box(g, (w, d, h), (0, 0, h / 2))
    box("Stone", (w + 0.4, d + 0.4, 1.2), (0, 0, 0.6))         # base course


def bands(w, d, zs):
    for z in zs:
        box("Trim", (w + 0.5, d + 0.5, 0.4), (0, 0, z))


def quoins(w, d, h):
    for sx in (-1, 1):
        for k in range(int(h / 2.2)):
            box("Trim", (0.9 if k % 2 else 1.4, 0.9, 1.1), (sx * w / 2, -d / 2, 1.8 + k * 2.2))


# ============ A: townhouse ============
start("A", 0)
W, D, H = 22.0, 18.0, 21.0
FY = -D / 2
body(W, D, H)
bands(W, D, (7.0, 14.0))
quoins(W, D, H)
door(FY, 0)
for x in (-6.5, 6.5):
    window(FY, x, 1.8, 3.0, 4.2)
balcony(FY, 0, 16.0, 7.2)
for fl, z in ((1, 8.2), (2, 15.0)):
    for x in (-6.5, 0.0, 6.5):
        window(FY, x, z, 2.6, 4.4 if fl == 1 else 3.8, box_flowers=(fl == 2))
for s in (-1, 1):  # side windows
    for y in (-3.0, 4.0):
        for z in (8.2, 15.0):
            box("Glass", (0.1, 2.4, 3.8), (s * (W / 2 + 0.03), y, z + 1.9))
            box("Shutters", (0.15, 1.2, 3.8), (s * (W / 2 + 0.1), y - 1.9, z + 1.9))
            box("Shutters", (0.15, 1.2, 3.8), (s * (W / 2 + 0.1), y + 1.9, z + 1.9))
box("Trim", (W + 1.0, D + 1.0, 0.7), (0, 0, H - 0.3))
hip_roof(-W / 2, W / 2, -D / 2, D / 2, H, 6.5)
box("Stone", (1.6, 1.6, 3.5), (5.0, 3.0, H + 5.0))           # chimney

# ============ B: bahay na bato ============
start("B", 1)
W, D, H0, H1 = 24.0, 20.0, 8.0, 15.5
FY = -D / 2
box("Stone", (W, D, H0), (0, 0, H0 / 2))                       # stone ground floor
for x in (-8.0, 0.0, 8.0):                                     # arcade: dark arch recesses with a door in the middle one
    arch_prism("Shadow", x, 0.0, 5.0, 6.4, FY - 0.08, FY + 0.6)
    box("Trim", (5.8, 0.4, 0.5), (x, FY - 0.2, 6.6))
door(FY - 0.1, 0.0, 3.2, 5.8)
box("Wood", (W + 1.6, D + 1.6, H1 - H0), (0, 0, (H0 + H1) / 2))  # wooden upper floor, overhanging
box("Trim", (W + 2.0, D + 2.0, 0.5), (0, 0, H0 + 0.1))
for x in (-8.4, -2.8, 2.8, 8.4):
    window(FY - 0.8, x, H0 + 1.4, 4.4, 4.6, shutters=False, capiz=True)
for k in range(9):                                             # ventanillas (vent panels under the windows)
    box("Shutters", (1.6, 0.15, 0.9), (-10.0 + k * 2.5, FY - 0.9, H0 + 0.75))
for s in (-1, 1):
    for y in (-5.0, 0.0, 5.0):
        box("Capiz", (0.1, 3.6, 4.2), (s * (W / 2 + 0.83), y, H0 + 3.6))
hip_roof(-W / 2 - 0.8, W / 2 + 0.8, -D / 2 - 0.8, D / 2 + 0.8, H1, 8.0, over=1.6)

# ============ C: shophouse ============
start("C", 2)
W, D, H = 20.0, 18.0, 19.0
FY = -D / 2
body(W, D, H)
bands(W, D, (6.8,))
box("Shadow", (14.0, 0.3, 4.6), (0, FY + 0.05, 2.9))           # shop opening
box("Glass", (13.0, 0.1, 3.8), (-0.5, FY - 0.05, 3.1))
door(FY - 0.05, 5.4, 2.6, 5.2)
box("Trim", (15.0, 0.5, 1.4), (0, FY - 0.2, 6.0))              # fascia
box("Shutters", (13.0, 0.2, 1.0), (0, FY - 0.45, 6.0))         # sign board
for k in range(8):                                             # striped scalloped awning
    g = "Awning" if k % 2 == 0 else "Trim"
    a = box(g, (1.75, 3.2, 0.2), (-6.1 + k * 1.75, FY - 1.5, 5.0), rot=(math.radians(-18), 0, 0))
for fl, z in ((1, 8.0), (2, 13.2)):
    for x in (-6.0, 0.0, 6.0):
        window(FY, x, z, 2.6, 3.8, box_flowers=(fl == 1))
box("Trim", (W + 1.2, D + 1.2, 0.9), (0, 0, H + 0.2))           # cornice
box("Walls", (W, 0.8, 2.2), (0, FY + 0.4, H + 1.6))             # parapet
box("Walls", (W, 0.8, 2.2), (0, -FY - 0.4, H + 1.6))
for s in (-1, 1):
    box("Walls", (0.8, D, 2.2), (s * (W / 2 - 0.4), 0, H + 1.6))
box("Trim", (W + 0.4, D + 0.4, 0.4), (0, 0, H + 2.8))
box("Iron", (1.2, 1.2, 4.0), (5.0, 4.0, H + 2.0))              # water tank stand
add("Iron", c.lathe("tank", [(0.01, 0), (1.6, 0), (1.6, 2.6), (0.01, 2.9)], steps=12))
G[("C", "Iron")][-1].location = (5.0 + OX[0], 4.0, H + 4.0)

# ============ D: narrow tower house ============
start("D", 3)
W, D, H = 14.0, 16.0, 26.0
FY = -D / 2
body(W, D, H)
bands(W, D, (6.5, 12.5, 18.5))
quoins(W, D, H)
door(FY, -3.0, 2.8, 5.6)
window(FY, 3.5, 1.8, 2.6, 3.8)
for z in (7.6, 13.6, 19.6):
    for x in (-3.4, 3.4):
        window(FY, x, z, 2.4, 3.8, box_flowers=(z == 13.6))
balcony(FY, 0, 9.0, 13.2, depth=1.2)
gable_roof_y(-W / 2, W / 2, -D / 2, D / 2, H, 6.0)
box("Trim", (W + 1.0, D + 1.0, 0.6), (0, 0, H - 0.2))
box("Trim", (2.2, 0.4, 2.2), (0, FY - 1.2, H + 2.4))            # round-ish gable vent plate

# ============ E: villa ============
start("E", 4)
W, D, H = 26.0, 22.0, 15.0
FY = -D / 2
body(W, D, H)
bands(W, D, (7.4,))
quoins(W, D, H)
box("Trim", (10.0, 4.0, 0.5), (0, FY - 2.0, 7.2))               # porch roof = balcony floor
for x in (-4.2, 4.2):
    add("Trim", c.lathe("col", [(0.01, 0), (0.75, 0), (0.75, 0.5), (0.5, 0.7), (0.45, 6.2), (0.7, 6.5), (0.75, 7.0), (0.01, 7.0)], steps=12))
    G[("E", "Trim")][-1].location = (x + OX[0], FY - 3.4, 0.0)
box("Stone", (11.0, 4.6, 0.5), (0, FY - 2.2, 0.25))
door(FY, 0, 3.4, 6.2)
for x in (-9.0, 9.0):
    window(FY, x, 1.8, 3.0, 4.4)
    window(FY, x, 8.8, 3.0, 4.2, box_flowers=True)
for x in (-2.6, 2.6):
    window(FY, x, 8.8, 2.2, 4.6, shutters=False)
for k in range(13):                                             # balustrade on the porch roof
    box("Trim", (0.35, 0.35, 1.8), (-4.8 + k * 0.8, FY - 3.8, 8.35))
box("Trim", (10.0, 0.6, 0.35), (0, FY - 3.8, 9.4))
for s in (-1, 1):
    for y in (-5.0, 3.0):
        for z in (1.8, 8.8):
            box("Glass", (0.1, 2.6, 4.2), (s * (W / 2 + 0.03), y, z + 2.1))
            box("Shutters", (0.15, 1.3, 4.2), (s * (W / 2 + 0.1), y - 2.0, z + 2.1))
            box("Shutters", (0.15, 1.3, 4.2), (s * (W / 2 + 0.1), y + 2.0, z + 2.1))
box("Trim", (W + 1.0, D + 1.0, 0.7), (0, 0, H - 0.3))
hip_roof(-W / 2, W / 2, -D / 2, D / 2, H, 7.0)
for s in (-1, 1):  # potted shrubs by the porch
    box("Stone", (1.6, 1.6, 1.2), (s * 6.6, FY - 3.6, 0.6))
    add("Leaves", blob(1.1, (s * 6.6, FY - 3.6, 2.0)))

# ============ finish ============
SPEC = {"Walls": ("plaster", "plaster"), "Trim": ("cream", "limestone"), "Stone": ("stone", "stone"), "Roof": ("terracotta", "clay"),
        "Glass": ("glass", None), "Shutters": ("teal", None), "Wood": ("wood", "wood"), "Capiz": ("capiz", None),
        "Iron": ("iron", None), "Flowers": ("pink", None), "Leaves": ("leaf", None), "Shadow": ("iron", None), "Awning": ("awning", None)}
final = []
mats = {}
for (house, name), objs in G.items():
    obj = c.join(objs, f"House{house}_{name}") if len(objs) > 1 else objs[0]
    obj.name = f"House{house}_{name}"
    col, tex = SPEC[name]
    c.finish(obj, obj.name, col, smooth=name in ("Flowers", "Leaves"))
    if tex:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            ax = max(range(3), key=lambda i: abs(f.normal[i]))
            for lp in f.loops:
                co = lp.vert.co
                uv = (co.y, co.z) if ax == 0 else ((co.x, co.z) if ax == 1 else (co.x, co.y))
                lp[layer].uv = (uv[0] / 8.0, uv[1] / 8.0)
        bm.to_mesh(obj.data)
        bm.free()
        # one material per texture kind, shared by all houses (fewer textures to load on phones)
        if name not in mats:
            tx.apply(obj, tex, "Houses_" + name + "_mat", (0.97, 0.95, 0.9) if name == "Walls" else None)
            mats[name] = obj.data.materials[0]
        else:
            obj.data.materials.clear()
            obj.data.materials.append(mats[name])
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
per = {}
for o in final:
    per[o.name[:6]] = per.get(o.name[:6], 0) + c.triangle_count([o])
print("HOUSES triangles", c.triangle_count(final), per)
c.export_glb(os.path.join(c.OUT_MODELS, "Houses.glb"), final)

# ---------------- preview ----------------
import mathutils  # noqa: E402

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 40
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1400, 700
sc.view_settings.view_transform = "AgX"
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
so.rotation_euler = (math.radians(55), 0, math.radians(200))
gd = bpy.data.meshes.new("g")
go = bpy.data.objects.new("g", gd)
bpy.context.collection.objects.link(go)
b2 = bmesh.new()
bmesh.ops.create_grid(b2, x_segments=1, y_segments=1, size=300)
b2.to_mesh(gd)
b2.free()
cm = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cm)
cm.data.lens = 24
cm.location = (80, -150, 48)
cm.rotation_euler = (mathutils.Vector((80, 0, 10)) - mathutils.Vector(cm.location)).to_track_quat("-Z", "Y").to_euler()
sc.camera = cm
sc.render.filepath = os.path.join(c.OUT_PREVIEWS, "Houses.png")
bpy.ops.render.render(write_still=True)
print("done")
