"""Pasko (Filipino Christmas) decor for the universal shop (Blender 5.x, headless).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/shop_pasko.py
Writes assets/models/ShopU_Pasko.glb and a preview assets/previews/ShopU_Pasko.png (set DF_SKIP_RENDER=1 to skip the render).

Same coordinates as shop_universal.py (plot base units, plot centre = origin, +Y = the shop front, Z up). Groups (one mesh each, Studio colours them by name):
  PaskoParol / PaskoParolCore / PaskoParolTail / PaskoCord   the big glowing capiz-style star lantern hanging over the balcony door
  PaskoWire / PaskoBulbWarm / PaskoBulbRed / PaskoBulbGreen    three swags of string lights along the front eave
  PaskoWreath / PaskoWreathBow                                 a wreath on the wall beside the door
  PaskoBelenWood / PaskoBelenThatch / PaskoBelenFigure / PaskoBelenStar   a small belen (nativity) scene in front of the right planters
Free for everyone in December: the lights. Pasko Pack owners: the parol, wreath and belen (SeasonService decides).
"""

import math
import os
import sys

import bmesh
import bpy
import mathutils

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

c.reset_scene()
G = {}


def _add(group, verts, faces):
    G.setdefault(group, []).append((verts, faces))


def bx(group, x0, x1, y0, y1, z0, z1):
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    if z1 < z0:
        z0, z1 = z1, z0
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    _add(group, v, f)


def ico(group, cx, cy, cz, r, sub=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    v = [(vv.co.x + cx, vv.co.y + cy, vv.co.z + cz) for vv in bm.verts]
    f = [tuple(vv.index for vv in ff.verts) for ff in bm.faces]
    bm.free()
    _add(group, v, f)


def cone(group, cx, cy, z0, z1, r, n=8):
    """closed cone / frustum point at the top"""
    v = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z0) for i in range(n)] + [(cx, cy, z1)]
    f = [tuple(reversed(range(n)))] + [(i, (i + 1) % n, n) for i in range(n)]
    _add(group, v, f)


def star_lantern(group, cx, cy, cz, r_out, r_in, depth):
    """A 5-point star lantern: a ring of 10 points in the XZ plane (one tip straight up) with an apex front and back."""
    ring = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = r_out if i % 2 == 0 else r_in
        ring.append((cx + r * math.cos(a), cy, cz + r * math.sin(a)))
    v = ring + [(cx, cy + depth, cz), (cx, cy - depth, cz)]
    f = []
    for i in range(10):
        j = (i + 1) % 10
        f.append((i, j, 10))        # front faces
        f.append((j, i, 11))        # back faces
    _add(group, v, f)


# ---------------------------------------------------------------- the parol (star lantern) over the balcony door
PX, PY, PZ = 0.0, 23.6, 17.2
star_lantern("PaskoParol", PX, PY, PZ, 2.7, 1.15, 1.0)
star_lantern("PaskoParolCore", PX, PY, PZ, 1.5, 0.62, 1.25)
for (dx, ln) in ((-0.9, 2.6), (0.0, 3.4), (0.9, 2.6)):      # tassel tails under the star
    cone("PaskoParolTail", PX + dx, PY, PZ - 2.5 - ln, PZ - 2.2, 0.16)
bx("PaskoCord", PX - 0.06, PX + 0.06, 22.55, 23.65, 21.9, 22.05)             # arm from the eave
bx("PaskoCord", PX - 0.06, PX + 0.06, PY - 0.06, PY + 0.06, PZ + 2.55, 22.05)   # cord down to the star tip

# ---------------------------------------------------------------- string lights along the front eave
WIRE_Y, WIRE_Z = 22.75, 21.7
POINTS = (-21.5, -7.2, 7.2, 21.5)
bulb_i = 0
for a, b in zip(POINTS[:-1], POINTS[1:]):
    n = 24
    prev = None
    for i in range(n + 1):
        t = i / n
        x = a + (b - a) * t
        z = WIRE_Z - 1.7 * 4 * t * (1 - t)       # a sag of 1.7 at the middle
        if prev is not None:
            # thin wire segment (a flat quad strip is enough at this size)
            bx("PaskoWire", min(prev[0], x), max(prev[0], x) + 0.02, WIRE_Y - 0.04, WIRE_Y + 0.04, min(prev[1], z) - 0.03, max(prev[1], z) + 0.03)
        prev = (x, z)
        if i % 3 == 1:
            group = ("PaskoBulbWarm", "PaskoBulbRed", "PaskoBulbGreen")[bulb_i % 3]
            ico(group, x, WIRE_Y, z - 0.35, 0.26)
            bulb_i += 1

# ---------------------------------------------------------------- wreath beside the door (on the wall, left pier)
WX, WY, WZ = -5.85, 20.55, 6.4
for i in range(16):
    a = 2 * math.pi * i / 16
    ico("PaskoWreath", WX + 1.0 * math.cos(a), WY, WZ + 1.0 * math.sin(a), 0.3)
for i in range(5):
    a = math.radians(30 + i * 72)
    ico("PaskoWreathBow", WX + 1.0 * math.cos(a) * 0.98, WY + 0.25, WZ + 1.0 * math.sin(a) * 0.98, 0.12)      # tiny berries
bx("PaskoWreathBow", WX - 0.55, WX + 0.55, WY + 0.2, WY + 0.5, WZ - 1.55, WZ - 1.25)                          # the bow: two tails and a knot
bx("PaskoWreathBow", WX - 0.7, WX - 0.1, WY + 0.2, WY + 0.5, WZ - 1.9, WZ - 1.35)
bx("PaskoWreathBow", WX + 0.1, WX + 0.7, WY + 0.2, WY + 0.5, WZ - 1.9, WZ - 1.35)

# ---------------------------------------------------------------- belen (nativity) in front of the right planters
BX, BY, B0 = 17.0, 23.8, 0.5
bx("PaskoBelenWood", BX - 1.6, BX + 1.6, BY - 1.2, BY + 1.2, B0, B0 + 0.25)                    # base
for (dx, dy) in ((-1.4, -1.0), (1.4, -1.0), (-1.4, 1.0), (1.4, 1.0)):
    bx("PaskoBelenWood", BX + dx - 0.1, BX + dx + 0.1, BY + dy - 0.1, BY + dy + 0.1, B0 + 0.25, B0 + 2.5)    # posts
bx("PaskoBelenWood", BX - 1.2, BX + 1.2, BY - 0.9, BY - 0.6, B0 + 0.25, B0 + 0.55)            # manger
# thatched roof: two sloped slabs (a pyramid-like roof as a pitched prism)
roof = [(BX - 1.9, B0 + 2.5), (BX + 1.9, B0 + 2.5), (BX, B0 + 3.9)]
v = [(p[0], BY - 1.4, p[1]) for p in roof] + [(p[0], BY + 1.4, p[1]) for p in roof]
f = [(2, 1, 0), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
_add("PaskoBelenThatch", v, f)
cone("PaskoBelenFigure", BX - 0.8, BY + 0.2, B0 + 0.25, B0 + 1.6, 0.38)                       # Joseph
ico("PaskoBelenFigure", BX - 0.8, BY + 0.2, B0 + 1.85, 0.22)
cone("PaskoBelenFigure", BX + 0.5, BY + 0.2, B0 + 0.25, B0 + 1.5, 0.36)                       # Mary
ico("PaskoBelenFigure", BX + 0.5, BY + 0.2, B0 + 1.72, 0.21)
ico("PaskoBelenFigure", BX - 0.1, BY - 0.75, B0 + 0.7, 0.2)                                    # the baby in the manger
star_lantern("PaskoBelenStar", BX, BY + 1.35, B0 + 3.4, 0.7, 0.3, 0.2)                         # little star on the front of the roof

# ---------------------------------------------------------------- meshes, materials, export
COLOURS = {"PaskoParol": "E8B64A", "PaskoParolCore": "C03A2E", "PaskoParolTail": "E8B64A", "PaskoCord": "6B4A2E", "PaskoWire": "2A2A2A",
           "PaskoBulbWarm": "FFD98A", "PaskoBulbRed": "FF5A4A", "PaskoBulbGreen": "7FD27F", "PaskoWreath": "3F7F3A", "PaskoWreathBow": "B02A2A",
           "PaskoBelenWood": "6B4A2E", "PaskoBelenThatch": "C9A85C", "PaskoBelenFigure": "E8D8B8", "PaskoBelenStar": "FFD04A"}
c.PALETTE.update({k.lower(): v for k, v in COLOURS.items()})
objs = []
for group, parts in G.items():
    verts, faces = [], []
    for (v, f) in parts:
        o = len(verts)
        verts.extend(v)
        faces.extend([tuple(i + o for i in face) for face in f])
    me = bpy.data.meshes.new("Pasko_" + group + "_mesh")
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Pasko_" + group, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(c.material("Pasko_" + group + "_mat", group.lower()))
    objs.append(ob)

print("PASKO triangles", c.triangle_count(objs), [(o.name, c.triangle_count([o])) for o in objs])
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_Pasko.glb"), objs)
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no render)")
    raise SystemExit

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1100, 760
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.1, 0.12, 0.2, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
scene.world = world
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 2.2
so = bpy.data.objects.new("Sun", sd)
bpy.context.collection.objects.link(so)
so.rotation_euler = (math.radians(60), 0, math.radians(200))
# a stand-in facade so the decor reads against a wall
wall = c.box("wall", (46, 1.2, 22), (0, 20.8 + 0.6 - 0.6, 11))
wm = bpy.data.materials.new("wm")
wm.use_nodes = True
wm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.74, 0.62, 1)
wall.data.materials.append(wm)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cam)
cam.data.lens = 30
cam.location = (6, 52, 14)
cam.rotation_euler = (mathutils.Vector((0, 22, 13)) - mathutils.Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.filepath = os.path.join(c.OUT_PREVIEWS, "ShopU_Pasko.png")
bpy.ops.render.render(write_still=True)
print("done")
