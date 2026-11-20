"""Dusty Finds HUD icons: clean white 3D glyphs (gold for coin/star) rendered on a transparent background, for the
dark angular HUD skin. Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/ui_icons.py
Writes assets/ui/icons/<name>.png (256 x 256 RGBA).
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import vehicle_common as V  # noqa: E402

OUT = os.path.join(V.ROOT, "assets", "ui", "icons")
os.makedirs(OUT, exist_ok=True)

WHITE = (0.96, 0.96, 0.95, 1)
GOLD = (1.0, 0.76, 0.22, 1)
DIM = (0.70, 0.72, 0.76, 1)


def mat(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    return m


def prism(name, pts2d, depth, loc=(0, 0, 0), rot=(0, 0, 0), material=None):
    """Extrude a 2D outline (in the X/Z plane, facing the camera on -Y) by `depth`."""
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in pts2d]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in pts2d]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o.location = loc
    o.rotation_euler = rot
    if material:
        me.materials.append(material)
    return o


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = False
    sc.display.shading.cavity_type = "BOTH"
    sc.display.shading.show_shadows = False
    sc.display.shading.show_object_outline = False
    sc.render.film_transparent = True
    sc.render.resolution_x = 256
    sc.render.resolution_y = 256
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.5
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.9, -6, 0.75)  # slightly from the side and above: a little depth on the glyphs
    direction = -cam.location.__class__((0.9, -6, 0.75))
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam


def render(name):
    path = os.path.join(OUT, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # clear the icon's objects, keep the camera
    for o in list(bpy.context.scene.objects):
        if o.type != "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    print("[icons] wrote", path)


V.reset()
setup_scene()
W = mat("White", WHITE)
G = mat("Gold", GOLD)
D = mat("Dim", DIM)

# bag (backpack)
V.box("Body", (1.3, 0.7, 1.55), (0, 0, -0.1), W, bevel=0.25, segments=4)
V.box("Pocket", (0.95, 0.25, 0.6), (0, -0.42, -0.4), D, bevel=0.12, segments=3)
V.tube("Handle", [(-0.3, 0, 0.65), (-0.25, 0, 0.95), (0.25, 0, 0.95), (0.3, 0, 0.65)], 0.07, W)
V.box("Flap", (1.2, 0.3, 0.12), (0, -0.33, 0.25), D, bevel=0.05)
render("bag")

# upgrades: hammer + wrench crossed
def turn(pts, deg):
    a = math.radians(deg)
    return [(x * math.cos(a) - z * math.sin(a), x * math.sin(a) + z * math.cos(a)) for x, z in pts]


hammer = [(-0.08, -0.95), (0.08, -0.95), (0.08, 0.5), (0.5, 0.5), (0.5, 0.82), (-0.5, 0.82), (-0.5, 0.5), (-0.08, 0.5)]
wrench = [(-0.09, -0.95), (0.09, -0.95), (0.09, 0.45), (0.32, 0.45), (0.32, 0.95), (0.12, 0.95), (0.12, 0.68),
          (-0.12, 0.68), (-0.12, 0.95), (-0.32, 0.95), (-0.32, 0.45), (-0.09, 0.45)]
prism("Wrench", turn(wrench, -40), 0.2, (0, 0.12, 0), (0, 0, 0), D)
prism("Hammer", turn(hammer, 40), 0.25, (0, -0.1, 0), (0, 0, 0), W)
render("upgrades")

# collection: closed book with a bookmark
V.box("Cover", (1.2, 0.35, 1.6), (0, 0, 0), W, bevel=0.06)
V.box("Pages", (1.1, 0.3, 1.5), (0.06, -0.03, 0), D)
V.box("Spine", (0.18, 0.4, 1.62), (-0.55, 0, 0), W, bevel=0.05)
prism("Bookmark", [(-0.1, 0.0), (0.1, 0.0), (0.1, -0.55), (0.0, -0.42), (-0.1, -0.55)], 0.05, (0.3, -0.2, -0.78), (0, 0, 0), G)
render("collection")

# supply: crate with an X brace
V.box("Crate", (1.5, 1.2, 1.4), (0, 0, 0), D, bevel=0.06)
for z in (-0.6, 0.6):
    V.box("Plank", (1.56, 1.26, 0.18), (0, 0, z), W, bevel=0.03)
for x in (-0.68, 0.68):
    V.box("Post", (0.18, 1.26, 1.44), (x, 0, 0), W, bevel=0.03)
for s in (-1, 1):
    b = V.box("Brace", (1.6, 0.08, 0.16), (0, -0.62, 0), W)
    b.rotation_euler = (0, math.radians(40 * s), 0)
render("supply")

# my shop: house
V.box("Walls", (1.3, 1.0, 0.95), (0, 0, -0.35), W, bevel=0.04)
prism("Roof", [(-0.85, 0.12), (0.85, 0.12), (0.0, 0.85)], 1.1, (0, 0, 0), (0, 0, 0), G)
V.box("Door", (0.32, 0.05, 0.55), (0.25, -0.52, -0.55), D)
V.box("Window", (0.3, 0.05, 0.25), (-0.3, -0.52, -0.25), D)
render("myshop")

# visit: two people
for x, s, m_ in ((-0.38, 0.9, D), (0.32, 1.0, W)):
    V.sphere("Head", 0.28 * s, (x, 0, 0.45 * s), mat=m_, seg=20, rings=12)
    prism("Shoulders", [(x - 0.45 * s, -0.75), (x + 0.45 * s, -0.75), (x + 0.42 * s, -0.1), (x + 0.2 * s, 0.05), (x - 0.2 * s, 0.05), (x - 0.42 * s, -0.1)], 0.4, (0, x * 0.3, 0), (0, 0, 0), m_)
render("visit")

# settings: gear
teeth = []
for i in range(16):
    r = 0.95 if i % 2 == 0 else 0.72
    for k in (-0.11, 0.11):
        a = math.radians(i * 22.5) + k
        teeth.append((math.cos(a) * r, math.sin(a) * r))
prism("Gear", teeth, 0.35, (0, 0, 0), (0, 0, 0), W)
V.cylinder("Hole", 0.3, 0.45, (0, -0.02, 0), "Y", D, verts=24)
render("settings")

# travel: map pin
pin = [(0.0, -1.0)]
for a in range(-40, 225, 15):
    r = math.radians(a)
    pin.append((math.cos(r) * 0.6, 0.25 + math.sin(r) * 0.6))
prism("Pin", pin, 0.35, (0, 0, 0), (0, 0, 0), W)
V.cylinder("PinHole", 0.22, 0.45, (0, -0.02, 0.25), "Y", G, verts=24)
render("travel")

# sprint: lightning bolt
prism("Bolt", [(0.15, 1.0), (-0.55, -0.1), (-0.05, -0.1), (-0.25, -1.0), (0.55, 0.2), (0.05, 0.2)], 0.3, (0, 0, 0), (0, 0, 0), G)
render("sprint")

# coin
V.cylinder("Coin", 0.85, 0.22, (0, 0, 0), "Y", G, verts=40)
V.cylinder("CoinRim", 0.7, 0.26, (0, 0, 0), "Y", mat("GoldDark", (0.86, 0.6, 0.12, 1)), verts=40)
prism("Dollar", [(-0.08, -0.5), (0.08, -0.5), (0.08, 0.5), (-0.08, 0.5)], 0.32, (0, 0, 0), (0, 0, 0), G)
render("coin")

# star
star = []
for i in range(10):
    r = 0.95 if i % 2 == 0 else 0.42
    a = math.radians(90 + i * 36)
    star.append((math.cos(a) * r, math.sin(a) * r))
prism("Star", star, 0.3, (0, 0, -0.05), (0, 0, 0), G)
render("star")

# bell (notifications)
bell = [(-0.75, -0.5), (0.75, -0.5), (0.55, -0.3), (0.45, 0.35), (0.25, 0.65), (0.0, 0.72), (-0.25, 0.65), (-0.45, 0.35), (-0.55, -0.3)]
prism("Bell", bell, 0.5, (0, 0, 0.05), (0, 0, 0), W)
V.sphere("Clapper", 0.16, (0, -0.1, -0.68), mat=G, seg=16, rings=10)
render("bell")
print("[icons] done:", OUT)
