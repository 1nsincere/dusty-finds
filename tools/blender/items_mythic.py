"""Dusty Finds Mythic + Secret items (4 models). Each part is its own mesh (named) so Studio can colour it and the
restoration converter can use the named repair part as Socket/LooseParts.
Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/items_mythic.py
Writes assets/items/<Id>.fbx (+ previews/<Id>.png). Front = Blender -Y (Roblox -Z), up = Z, 1 unit = 1 stud,
bottom at Z 0, footprint <= 2 x 2.
  Mythic: CrystalMusicBox (repair part "Crystal"), JadeDragonClock (repair part "Hand")
  Secret: SunIdol (repair part "Gem"), Astrolabe (repair part "Ring")
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import vehicle_common as V  # noqa: E402

OUT = os.path.join(V.ROOT, "assets", "items")
PRE = os.path.join(OUT, "previews")
os.makedirs(PRE, exist_ok=True)


def m(name, hexcol, metal=0.0, rough=0.5):
    return V.paint(name, V.rgb(hexcol), rough=rough, metal=metal)


def export(item_id, objs):
    path = os.path.join(OUT, item_id + ".fbx")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", object_types={"MESH"}, mesh_smooth_type="FACE")
    V.previews(PRE, item_id, 2.6, 1.0, [("front34", (-3.2, -4.2, 2.6))])
    print("[items] wrote", path, "parts:", [o.name for o in objs])


def named(o, name):
    o.name = name
    o.data.name = name + "_mesh"
    return o


# ---------------------------------------------------------------------------------------------------------- MYTHIC 1
V.reset()
wood = m("Rosewood", "5A2E1E", rough=0.4)
gold = m("Gold", "E2B33C", metal=1.0, rough=0.25)
crystal = m("Crystal", "9FE8FF", rough=0.05)
velvet = m("Velvet", "6A1E5A", rough=0.9)
parts = [
    named(V.box("Box", (1.9, 1.3, 0.9), (0, 0, 0.45), wood, bevel=0.08), "Box"),
    named(V.box("Trim", (2.0, 1.4, 0.12), (0, 0, 0.92), gold, bevel=0.03), "Trim"),
    named(V.box("Velvet", (1.6, 1.0, 0.04), (0, 0, 0.96), velvet), "Velvet"),
    named(V.box("Lid", (1.9, 0.12, 1.1), (0, 0.66, 1.45), wood, bevel=0.06), "Lid"),
    named(V.cylinder("Key", 0.12, 0.5, (1.05, 0, 0.5), "X", gold, verts=12), "Key"),
]
c = V.sphere("Crystal", 0.38, (0, 0, 1.35), mat=crystal, seg=6, rings=4)
c.scale = (0.8, 0.8, 1.25)
parts.append(named(c, "Crystal"))
parts.append(named(V.cylinder("Stand", 0.18, 0.3, (0, 0, 1.06), "Z", gold, verts=12), "Stand"))
export("CrystalMusicBox", parts)

# ---------------------------------------------------------------------------------------------------------- MYTHIC 2
V.reset()
jade = m("Jade", "2FA36B", rough=0.25)
dark = m("DarkJade", "1C6B45", rough=0.3)
gold = m("Gold", "E2B33C", metal=1.0, rough=0.25)
face = m("Face", "F3EBD5", rough=0.6)
parts = [
    named(V.box("Pedestal", (1.8, 1.0, 0.35), (0, 0, 0.175), dark, bevel=0.06), "Pedestal"),
    named(V.cylinder("Body", 0.75, 0.55, (0, 0, 1.2), "Y", jade, verts=32), "Body"),
    named(V.cylinder("Face", 0.6, 0.06, (0, -0.3, 1.2), "Y", face, verts=32), "Face"),
    named(V.cylinder("Bezel", 0.66, 0.08, (0, -0.31, 1.2), "Y", gold, verts=32), "Bezel"),
    named(V.box("Neck", (0.5, 0.5, 0.4), (0, 0, 0.55), jade, bevel=0.05), "Neck"),
]
# dragon coiling over the top
pts = [(-0.85, 0.05, 0.6), (-0.95, 0.05, 1.4), (-0.6, 0.05, 2.0), (0.0, 0.05, 2.15), (0.6, 0.05, 2.0), (0.9, 0.0, 1.55)]
parts.append(named(V.tube("Dragon", pts, 0.13, dark), "Dragon"))
parts.append(named(V.sphere("DragonHead", 0.2, (0.95, -0.05, 1.45), mat=gold, seg=12, rings=8), "DragonHead"))
hand = V.box("Hand", (0.06, 0.04, 0.5), (0, -0.36, 1.4), gold)
parts.append(named(hand, "Hand"))
parts.append(named(V.box("HandShort", (0.06, 0.04, 0.32), (0.11, -0.36, 1.3), gold), "HandShort"))
export("JadeDragonClock", parts)

# ---------------------------------------------------------------------------------------------------------- SECRET 1
V.reset()
gold = m("Gold", "F0C24A", metal=1.0, rough=0.2)
stone = m("Stone", "6B6458", rough=0.85)
ruby = m("Ruby", "E0204A", rough=0.05)
parts = [
    named(V.box("Plinth", (1.6, 1.4, 0.4), (0, 0, 0.2), stone, bevel=0.08), "Plinth"),
    named(V.box("Body", (0.9, 0.7, 1.0), (0, 0, 0.9), gold, bevel=0.15, segments=3), "Body"),
    named(V.sphere("Head", 0.42, (0, 0, 1.72), mat=gold, seg=20, rings=12), "Head"),
]
crown = []
for i in range(8):
    a = i * math.pi / 4
    crown.append(V.box("Ray", (0.1, 0.08, 0.32), (math.cos(a) * 0.55, 0.05, 1.72 + math.sin(a) * 0.55), gold))
    crown[-1].rotation_euler = (0, -a + math.pi / 2, 0)
parts.append(named(V.join(crown, "Rays"), "Rays"))
for x in (-0.15, 0.15):
    parts.append(named(V.sphere("Eye", 0.06, (x, -0.38, 1.78), mat=stone, seg=8, rings=6), "Eye" + ("L" if x < 0 else "R")))
parts.append(named(V.sphere("Gem", 0.17, (0, -0.37, 1.05), mat=ruby, seg=6, rings=4), "Gem"))
export("SunIdol", parts)

# ---------------------------------------------------------------------------------------------------------- SECRET 2
V.reset()
brass = m("Brass", "C9A227", metal=1.0, rough=0.3)
navy = m("Navy", "1B2A55", rough=0.5)
silver = m("Silver", "D8DCE2", metal=1.0, rough=0.2)
parts = [
    named(V.cylinder("Stand", 0.8, 0.25, (0, 0, 0.125), "Z", navy, verts=32), "Stand"),
    named(V.cylinder("Post", 0.08, 0.7, (0, 0, 0.6), "Z", brass, verts=12), "Post"),
    named(V.cylinder("Mater", 0.8, 0.1, (0, 0, 1.6), "Y", brass, verts=40), "Mater"),
    named(V.cylinder("Plate", 0.68, 0.06, (0, -0.06, 1.6), "Y", navy, verts=40), "Plate"),
]
rete = []
for k in range(4):
    b = V.box("Spoke", (1.3, 0.03, 0.05), (0, -0.1, 1.6), silver)
    b.rotation_euler = (0, k * math.pi / 4, 0)
    rete.append(b)
parts.append(named(V.join(rete, "Rete"), "Rete"))
ring = V.arch("Ring", 0.9, 0.06, 0.08, (0, 0, 1.6), silver, segs=24, start=0, end=math.pi * 2)
ring.rotation_euler = (0, 0, math.pi / 2)
parts.append(named(ring, "Ring"))
parts.append(named(V.sphere("Star", 0.09, (0, -0.12, 2.25), mat=silver, seg=8, rings=6), "Star"))
export("Astrolabe", parts)
print("[items] done")
