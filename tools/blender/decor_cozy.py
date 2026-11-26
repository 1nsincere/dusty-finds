"""Cozy Living decor set for the shop (Blender 5.x, headless). First set of docs/decor plan: 8 pieces, placeholder-quality but finished-looking.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/decor_cozy.py
Writes assets/models/Decor_Cozy.glb and a preview assets/previews/Decor_Cozy.png (set DF_SKIP_RENDER=1 to skip the render).

1 unit = 1 stud, Z up, +Y = the front of each piece (it faces the shop). Each piece sits on its own origin along X (9 studs apart) with its
base at z = 0. Every colour group is its own object named  <Piece>_<Part>  (Studio colours them by name):
  Sofa      RattanSofa_Frame / _Cane / _Cushion / _Pillow        Armchair  RattanChair_Frame / _Cane / _Cushion
  Banig     BanigRug_A / _B / _Edge   (woven mat: alternating stripes)      RoundBanig  RoundBanig_A / _B / _Edge
  Lamp      CapizLamp_Pole / _Shade (glows)    SideTable  SideTable_Top / _Leg
  Bookshelf Bookcase_Wood / _BookA / _BookB / _BookC            Plant  BigPlant_Pot / _Leaf / _Soil
Filipino touches stay subtle: rattan cane, a woven banig mat, a capiz shell lamp, narra-coloured wood.
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


def bx(group, x0, x1, y0, y1, z0, z1, ox=0.0):
    x0, x1, ox_ = min(x0, x1) + ox, max(x0, x1) + ox, ox
    y0, y1 = min(y0, y1), max(y0, y1)
    z0, z1 = min(z0, z1), max(z0, z1)
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    _add(group, v, f)


def cyl(group, cx, cy, z0, z1, r, n=16, r_top=None):
    """closed cylinder / frustum"""
    rt = r if r_top is None else r_top
    v = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z0) for i in range(n)]
    v += [(cx + rt * math.cos(2 * math.pi * i / n), cy + rt * math.sin(2 * math.pi * i / n), z1) for i in range(n)]
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    _add(group, v, f)


def ico(group, cx, cy, cz, r, sub=1, sx=1.0, sy=1.0, sz=1.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    v = [(vv.co.x * sx + cx, vv.co.y * sy + cy, vv.co.z * sz + cz) for vv in bm.verts]
    f = [tuple(vv.index for vv in ff.verts) for ff in bm.faces]
    bm.free()
    _add(group, v, f)


SP = 9.0  # studs between pieces in the preview row

# ---------------------------------------------------------------- 1. rattan sofa (7 x 3 x 3.2), x = 0
X = 0.0
for sx in (-3.35, 3.35):                                                         # chunky arms
    bx("RattanSofa_Frame", sx - 0.32, sx + 0.32, -1.4, 1.4, 0.35, 2.3, X)
    bx("RattanSofa_Cane", sx - 0.34, sx + 0.34, -1.2, 1.2, 1.2, 2.05, X)          # cane panel on the arm
bx("RattanSofa_Frame", -3.35, 3.35, -1.4, -1.0, 0.35, 3.2, X)                       # back (behind = -Y), the sofa faces +Y; between the arms so no surfaces overlap
bx("RattanSofa_Cane", -3.0, 3.0, -1.0, -0.9, 1.5, 3.0, X)                          # cane back panel
bx("RattanSofa_Frame", -3.35, 3.35, -1.4, 1.4, 0.35, 0.9, X)                        # seat base
for sx in (-3.67, 3.67):
    bx("RattanSofa_Frame", sx - 0.1, sx + 0.1, -1.3, 1.3, 0.0, 0.35, X)            # feet
for k, sx in enumerate((-1.62, 0.0, 1.62)):                                       # three seat cushions
    bx("RattanSofa_Cushion", sx - 0.78, sx + 0.78, -0.85, 1.35, 0.9, 1.55, X)
for sx in (-2.6, 2.6):                                                             # scatter pillows
    bx("RattanSofa_Pillow", sx - 0.45, sx + 0.45, -0.75, -0.2, 1.55, 2.35, X)

# ---------------------------------------------------------------- 2. rattan armchair (3.2 x 3 x 3.2), x = 9
X = SP
for sx in (-1.45, 1.45):
    bx("RattanChair_Frame", sx - 0.28, sx + 0.28, -1.3, 1.3, 0.35, 2.1, X)
    bx("RattanChair_Cane", sx - 0.3, sx + 0.3, -1.0, 1.0, 1.1, 1.9, X)
bx("RattanChair_Frame", -1.45, 1.45, -1.3, -0.95, 0.35, 3.2, X)
bx("RattanChair_Cane", -1.2, 1.2, -0.95, -0.85, 1.4, 3.0, X)
bx("RattanChair_Frame", -1.45, 1.45, -1.3, 1.3, 0.35, 0.9, X)
bx("RattanChair_Cushion", -1.1, 1.1, -0.8, 1.2, 0.9, 1.5, X)
for sx in (-1.55, 1.55):
    bx("RattanChair_Frame", sx - 0.1, sx + 0.1, -1.2, 1.2, 0.0, 0.35, X)

# ---------------------------------------------------------------- 3. banig rug (8 x 5 x 0.12), x = 18: a woven mat of stripes
X = 2 * SP
STRIPES = 14
for i in range(STRIPES):
    x0 = -3.6 + i * (7.2 / STRIPES)
    bx("BanigRug_A" if i % 2 == 0 else "BanigRug_B", x0, x0 + 7.2 / STRIPES, -2.1, 2.1, 0.0, 0.1, X)
for sy in (-2.35, 2.2):
    bx("BanigRug_Edge", -4.0, 4.0, sy, sy + 0.15 + (0.0 if sy < 0 else 0.0), 0.0, 0.12, X)
for sx in (-4.0, 3.85):
    bx("BanigRug_Edge", sx, sx + 0.15, -2.35, 2.35, 0.0, 0.12, X)

# ---------------------------------------------------------------- 4. round banig rug (r 3 x 0.12), x = 27: concentric rings
X = 3 * SP
for k, (r0, name) in enumerate(((3.0, "RoundBanig_Edge"), (2.8, "RoundBanig_A"), (2.2, "RoundBanig_B"), (1.6, "RoundBanig_A"), (1.0, "RoundBanig_B"), (0.45, "RoundBanig_A"))):
    cyl(name, X, 0.0, 0.0, 0.06 + k * 0.02, r0, 28)   # each inner ring a little taller, so none is hidden under the next

# ---------------------------------------------------------------- 5. capiz floor lamp (1.6 x 1.6 x 6.4), x = 36
X = 4 * SP
cyl("CapizLamp_Pole", X, 0.0, 0.0, 0.3, 0.7, 14)
cyl("CapizLamp_Pole", X, 0.0, 0.3, 4.4, 0.12, 10)
cyl("CapizLamp_Pole", X, 0.0, 4.2, 4.5, 0.4, 12)
cyl("CapizLamp_Shade", X, 0.0, 4.4, 6.4, 0.95, 12, r_top=0.75)                    # the capiz shell shade glows (Studio: Neon / light)
for i in range(6):                                                                  # capiz window ribs
    a = 2 * math.pi * i / 6
    bx("CapizLamp_Pole", X + 0.82 * math.cos(a) - 0.035, X + 0.82 * math.cos(a) + 0.035, 0.82 * math.sin(a) - 0.035, 0.82 * math.sin(a) + 0.035, 4.4, 6.4)
cyl("CapizLamp_Pole", X, 0.0, 6.4, 6.55, 0.78, 12)

# ---------------------------------------------------------------- 6. side table (2 x 2 x 2.4), x = 45
X = 5 * SP
cyl("SideTable_Top", X, 0.0, 2.1, 2.4, 1.0, 18)
cyl("SideTable_Top", X, 0.0, 2.4, 2.45, 0.85, 18)
for i in range(3):
    a = math.radians(90 + i * 120)
    bx("SideTable_Leg", X + 0.62 * math.cos(a) - 0.12, X + 0.62 * math.cos(a) + 0.12, 0.62 * math.sin(a) - 0.12, 0.62 * math.sin(a) + 0.12, 0.0, 2.1)
cyl("SideTable_Leg", X, 0.0, 0.7, 0.8, 0.7, 12)

# ---------------------------------------------------------------- 7. bookcase (3.6 x 1.2 x 6.4), x = 54
X = 6 * SP
bx("Bookcase_Wood", -1.8, -1.6, -0.6, 0.6, 0.0, 6.4, X)
bx("Bookcase_Wood", 1.6, 1.8, -0.6, 0.6, 0.0, 6.4, X)
bx("Bookcase_Wood", -1.8, 1.8, -0.6, -0.5, 0.0, 6.4, X)                           # back panel
for z in (0.0, 1.6, 3.2, 4.8, 6.3):
    bx("Bookcase_Wood", -1.8, 1.8, -0.6, 0.6, z, z + 0.15, X)
rows = (0.15, 1.75, 3.35, 4.95)
book_colors = ("Bookcase_BookA", "Bookcase_BookB", "Bookcase_BookC")
for r, z0 in enumerate(rows):
    x = -1.5
    k = 0
    while x < 1.3:
        w = 0.18 + 0.05 * ((k * 3 + r) % 3)
        h = 1.05 + 0.2 * ((k * 5 + r * 2) % 3)
        bx(book_colors[(k + r) % 3], x, x + w, -0.4, 0.35, z0, z0 + h, X)
        x += w + 0.03
        k += 1
        if r == 2 and k == 8:                                                       # one gap: a little ornament on the shelf
            ico("Bookcase_BookA", X + 0.9, 0.0, z0 + 0.35, 0.3)
            x += 0.9

# ---------------------------------------------------------------- 8. big plant (2.6 x 2.6 x 6), x = 63
X = 7 * SP
cyl("BigPlant_Pot", X, 0.0, 0.0, 1.5, 0.95, 14, r_top=1.2)
cyl("BigPlant_Pot", X, 0.0, 1.5, 1.7, 1.28, 14)
cyl("BigPlant_Soil", X, 0.0, 1.5, 1.62, 1.05, 14)
for i, (dx, dy, dz, r) in enumerate((
    (0.0, 0.0, 3.4, 1.0), (0.8, 0.3, 2.6, 0.8), (-0.8, 0.2, 2.8, 0.8), (0.3, -0.8, 3.0, 0.8), (-0.3, 0.8, 3.1, 0.8),
    (0.5, 0.4, 4.3, 0.75), (-0.5, -0.3, 4.4, 0.75), (0.0, 0.1, 5.2, 0.6), (1.0, -0.4, 3.7, 0.55), (-1.0, 0.5, 3.8, 0.55),
)):
    ico("BigPlant_Leaf", X + dx, dy, dz, r, 1, 1.15, 1.0, 1.35)
cyl("BigPlant_Soil", X, 0.0, 1.6, 3.0, 0.1, 6)

# ---------------------------------------------------------------- meshes, materials, export
COLOURS = {
    "RattanSofa_Frame": "7A4A2E", "RattanSofa_Cane": "D9BC84", "RattanSofa_Cushion": "EADFC8", "RattanSofa_Pillow": "C9645C",
    "RattanChair_Frame": "7A4A2E", "RattanChair_Cane": "D9BC84", "RattanChair_Cushion": "EADFC8",
    "BanigRug_A": "C8502F", "BanigRug_B": "E9C46A", "BanigRug_Edge": "3A5A47",
    "RoundBanig_A": "C8502F", "RoundBanig_B": "E9C46A", "RoundBanig_Edge": "3A5A47",
    "CapizLamp_Pole": "5A3B26", "CapizLamp_Shade": "FFF1CE",
    "SideTable_Top": "8A5A3A", "SideTable_Leg": "5A3B26",
    "Bookcase_Wood": "7A4A2E", "Bookcase_BookA": "2F5D6B", "Bookcase_BookB": "C8502F", "Bookcase_BookC": "E9C46A",
    "BigPlant_Pot": "C2693F", "BigPlant_Leaf": "3E7D45", "BigPlant_Soil": "4A3626",
}
c.PALETTE.update({k.lower(): v for k, v in COLOURS.items()})
objs = []
for group, parts in G.items():
    verts, faces = [], []
    for (v, f) in parts:
        o = len(verts)
        verts.extend(v)
        faces.extend([tuple(i + o for i in face) for face in f])
    me = bpy.data.meshes.new(group + "_mesh")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(group, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(c.material(group + "_mat", group.lower()))
    objs.append(ob)

print("COZY triangles", c.triangle_count(objs))
per_piece = {}
for o in objs:
    per_piece[o.name.split("_")[0]] = per_piece.get(o.name.split("_")[0], 0) + c.triangle_count([o])
print("per piece:", per_piece)
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "Decor_Cozy.glb"), objs)
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no render)")
    raise SystemExit

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1700, 640
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.78, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
scene.world = world
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 3.0
so = bpy.data.objects.new("Sun", sd)
bpy.context.collection.objects.link(so)
so.rotation_euler = (math.radians(55), 0, math.radians(-30))
floor = c.box("floor", (90, 14, 0.2), (31.5, 0, -0.1))
fm = bpy.data.materials.new("fm")
fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.74, 0.62, 0.46, 1)
floor.data.materials.append(fm)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cam)
cam.data.lens = 34
scene.camera = cam
scene.render.resolution_x, scene.render.resolution_y = 1500, 760
# two shots: the sofa set (x 0-27) and the accent pieces (x 36-63)
for name, cx in (("Decor_Cozy_A", 13.5), ("Decor_Cozy_B", 49.5)):
    cam.location = (cx, 40, 11)
    cam.rotation_euler = (mathutils.Vector((cx, 0, 2.2)) - mathutils.Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(c.OUT_PREVIEWS, name + ".png")
    bpy.ops.render.render(write_still=True)
print("done")
