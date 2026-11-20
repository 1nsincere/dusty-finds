"""Dusty Finds shop props: the restoration WORKBENCH and the cashier COUNTER, sized to the shop's existing parts so they
drop in on top of them (the old parts stay as invisible colliders / prompt holders).
Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/shop_props.py
Writes assets/workbench/workbench.fbx, assets/counter/counter.fbx (+ textures/, previews/).
Axes: Blender X = Roblox X, Blender -Y = Roblox -Z, Blender Z = up; 1 unit = 1 stud; origin = bottom centre.
  Workbench: 8.4 x 4.2 footprint, work surface at 4.9 (the item sits in the clear middle); the player stands on the -Y
  (Roblox -Z) side, so the pegboard wall of tools is on +Y.
  Counter: 14 x 4.2 footprint, top at 5.6; customers stand on -Y (Roblox -Z), the owner on +Y, so the register's keys
  and open cash drawer face +Y and its price display faces the customer.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import vehicle_common as V  # noqa: E402


def wood(name, light, dark, scale=2.2):
    """Planked wood: wave-texture grain between two browns (baked into the colour map)."""
    m, nt, b = V._mat(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale * 0.15, scale)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 3.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = V.rgb(dark)
    ramp.color_ramp.elements[1].color = V.rgb(light)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.65
    return m


def pegboard(name):
    """Hardboard with a grid of dark holes."""
    m, nt, b = V._mat(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (2.0, 2.0, 2.0)
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "F1"
    vor.inputs["Randomness"].default_value = 0.0
    vor.inputs["Scale"].default_value = 1.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = V.rgb("2A2420")
    ramp.color_ramp.elements[1].position = 0.12
    ramp.color_ramp.elements[1].color = V.rgb("B8885A")
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], vor.inputs["Vector"])
    nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.8
    return m


def finish(parts_by_group, name, preview_views, size_hint, look_z):
    out = os.path.join(V.ROOT, "assets", name)
    tex = os.path.join(out, "textures")
    pre = os.path.join(out, "previews")
    os.makedirs(tex, exist_ok=True)
    objs = []
    for group, parts in parts_by_group.items():
        if parts:
            objs.append(V.join(parts, group))
    print(f"[{name}] triangles:", {o.name: V.tris(o) for o in objs})
    for o in objs:
        if o.name == "Signs":
            continue
        V.smart_uv(o)
        maps = V.bake_maps(o, tex, f"{name}_{o.name.lower()}")
        V.swap_material(o, V.baked_material(o.name + "_baked", maps))
    V.export_fbx(os.path.join(out, f"{name}.fbx"), objs)
    V.previews(pre, name, size_hint, look_z, preview_views)
    print(f"[{name}] done:", out)


# =====================================================================================================================
# WORKBENCH
# =====================================================================================================================
V.reset()
oak = wood("Oak", "B07A48", "6E4526")
dark = wood("DarkWood", "7A5233", "4A3020", scale=3.0)
peg = pegboard("Pegboard")
steel = V.paint("Steel", V.rgb("8A9098"), rough=0.35, metal=0.9)
red = V.paint("ToolRed", V.rgb("C0392B"), rough=0.4)
blue = V.paint("ToolBlue", V.rgb("2F6FB3"), rough=0.4)
yellow = V.paint("ToolYellow", V.rgb("E8B33A"), rough=0.45)
black = V.paint("Black", V.rgb("23252A"), rough=0.6)
brass = V.paint("Brass", V.rgb("C9A227"), rough=0.3, metal=0.9)
cloth = V.paint("Cloth", V.rgb("D9CBB0"), rough=0.95)
lampshade = V.paint("Lamp", V.rgb("2E7D5B"), rough=0.4, metal=0.3)
bulb = V.paint("Bulb", V.rgb("FFF2CC"), rough=0.1)

W, D, TOP = 8.4, 4.2, 4.9
body, tools = [], []
B, T = body.append, tools.append
# top: thick planks with a worn front edge
B(V.box("Top", (W, D, 0.35), (0, 0, TOP - 0.175), oak, bevel=0.06))
for i in range(5):  # plank seams (slightly darker strips)
    B(V.box("Seam", (W - 0.1, 0.03, 0.02), (0, -D / 2 + (i + 1) * D / 6, TOP + 0.005), dark))
# legs and rails
for sx in (-1, 1):
    for sy in (-1, 1):
        B(V.box("Leg", (0.45, 0.45, TOP - 0.35), (sx * (W / 2 - 0.35), sy * (D / 2 - 0.35), (TOP - 0.35) / 2), dark, bevel=0.04))
B(V.box("RailFront", (W - 0.9, 0.18, 0.4), (0, -D / 2 + 0.35, TOP - 0.6), dark))
B(V.box("Shelf", (W - 0.6, D - 0.6, 0.18), (0, 0, 1.0), oak))
# drawer block on the right with 3 drawers + brass handles
for k in range(3):
    z = TOP - 0.85 - k * 1.0
    B(V.box("Drawer", (2.6, 0.12, 0.85), (W / 2 - 1.75, -D / 2 + 0.25, z), oak, bevel=0.03))
    T(V.box("Handle", (0.6, 0.08, 0.1), (W / 2 - 1.75, -D / 2 + 0.17, z), brass, bevel=0.02))
B(V.box("DrawerBox", (2.7, D - 0.5, 3.0), (W / 2 - 1.75, 0, TOP - 1.85), dark))
# toolbox on the lower shelf
T(V.box("Toolbox", (1.8, 1.0, 0.8), (-2.3, 0.4, 1.5), red, bevel=0.08))
T(V.box("ToolboxHandle", (1.0, 0.1, 0.1), (-2.3, 0.4, 2.0), black))
# vice on the left front corner
vx, vy = -W / 2 + 0.9, -D / 2 + 0.55
T(V.box("ViseBody", (0.9, 0.9, 0.5), (vx, vy, TOP + 0.25), blue, bevel=0.06))
T(V.box("ViseJaw", (1.0, 0.18, 0.55), (vx, vy - 0.55, TOP + 0.3), steel))
T(V.box("ViseJaw2", (1.0, 0.18, 0.55), (vx, vy + 0.1, TOP + 0.3), steel))
T(V.cylinder("ViseScrew", 0.07, 1.1, (vx, vy - 0.95, TOP + 0.25), "Y", steel, verts=10))
T(V.cylinder("ViseBar", 0.05, 1.0, (vx, vy - 1.45, TOP + 0.25), "X", steel, verts=8))
# pegboard wall on the back edge with hung tools
PB_Y = D / 2 + 0.05
B(V.box("PegboardFrame", (W, 0.18, 3.8), (0, PB_Y + 0.05, TOP + 1.9), dark))
B(V.box("Pegboard", (W - 0.4, 0.06, 3.4), (0, PB_Y - 0.06, TOP + 1.95), peg))
ty = PB_Y - 0.16


def hang(x, z, parts):
    for p in parts:
        p.location.x += x
        p.location.z += z
        T(p)


hang(-3.2, TOP + 2.6, [V.box("HammerHead", (0.7, 0.18, 0.22), (0, ty, 0.6), steel), V.box("HammerGrip", (0.14, 0.14, 1.3), (0, ty, -0.1), yellow)])
hang(-2.2, TOP + 2.5, [V.box("Screwdriver", (0.06, 0.06, 0.9), (0, ty, 0.2), steel), V.box("ScrewGrip", (0.18, 0.18, 0.6), (0, ty, 0.85), red, bevel=0.05)])
hang(-1.5, TOP + 2.5, [V.box("Screwdriver2", (0.06, 0.06, 0.8), (0, ty, 0.2), steel), V.box("ScrewGrip2", (0.18, 0.18, 0.55), (0, ty, 0.8), blue, bevel=0.05)])
hang(-0.6, TOP + 2.7, [V.box("BrushHead", (0.7, 0.2, 0.35), (0, ty, 0.0), dark), V.box("Bristles", (0.66, 0.16, 0.25), (0, ty, -0.3), cloth), V.box("BrushGrip", (0.12, 0.12, 0.9), (0, ty, 0.6), oak)])
hang(0.5, TOP + 2.6, [V.box("Scraper", (0.6, 0.04, 0.5), (0, ty, -0.2), steel), V.box("ScraperGrip", (0.16, 0.16, 0.9), (0, ty, 0.45), yellow)])
hang(1.5, TOP + 2.7, [V.box("Wrench", (0.14, 0.05, 1.4), (0, ty, 0.0), steel), V.box("WrenchHead", (0.45, 0.05, 0.3), (0, ty, 0.7), steel)])
hang(2.4, TOP + 2.4, [V.box("Rag", (0.9, 0.08, 1.1), (0, ty, 0.0), cloth, bevel=0.05)])
hang(-2.6, TOP + 1.0, [V.box("ShelfSmall", (2.4, 0.5, 0.1), (0, ty - 0.2, 0.0), oak)])
for i, mat in enumerate((red, blue, yellow)):  # paint/polish tins on the small shelf
    T(V.cylinder("Tin", 0.22, 0.45, (-3.4 + i * 0.6, ty - 0.25, TOP + 1.28), "Z", mat, verts=14))
# desk lamp on the right back corner, angled over the work area
lx, ly = W / 2 - 0.7, D / 2 - 0.6
T(V.cylinder("LampBase", 0.4, 0.12, (lx, ly, TOP + 0.06), "Z", lampshade, verts=16))
T(V.tube("LampArm", [(lx, ly, TOP + 0.1), (lx, ly - 0.2, TOP + 1.6), (lx - 1.2, ly - 0.7, TOP + 2.2)], 0.06, steel))
T(V.cylinder("LampShade", 0.4, 0.55, (lx - 1.35, ly - 0.8, TOP + 1.95), "Z", lampshade, verts=16))
T(V.sphere("LampBulb", 0.18, (lx - 1.35, ly - 0.8, TOP + 1.68), mat=bulb, seg=10, rings=6))
# mat in the middle where the item goes (keeps the ItemAnchor area clear and readable)
B(V.box("WorkMat", (2.6, 2.0, 0.03), (0, -0.1, TOP + 0.015), V.paint("Mat", V.rgb("2E5E4E"), rough=0.9)))

finish({"Body": body, "Tools": tools}, "workbench", [
    ("front34", (-9, -12, 9)),
    ("front", (0, -13, 8)),
    ("side", (13, -2, 7)),
], 8, 5.5)

# =====================================================================================================================
# COUNTER + CASH REGISTER
# =====================================================================================================================
V.reset()
oak = wood("Oak", "B07A48", "6E4526")
dark = wood("DarkWood", "7A5233", "4A3020", scale=3.0)
cream = V.paint("Cream", V.rgb("EFE6D2"), rough=0.6)
teal = V.paint("Teal", V.rgb("1F7A7A"), rough=0.5)
black = V.paint("Black", V.rgb("23252A"), rough=0.5)
grey = V.paint("Grey", V.rgb("9AA0A6"), rough=0.4, metal=0.5)
brass = V.paint("Brass", V.rgb("C9A227"), rough=0.3, metal=0.9)
bill = V.paint("Bill", V.rgb("6BAF6B"), rough=0.8)
coin = V.paint("Coin", V.rgb("C0C4C8"), rough=0.3, metal=0.9)
screen = V.paint("Screen", V.rgb("2B3D2B"), rough=0.2)
glass = V.paint("Jar", V.rgb("D8E8EE"), rough=0.05)
paper = V.paint("Paper", V.rgb("C8A878"), rough=0.9)

W, D, TOP = 14.0, 4.2, 5.6
body, reg = [], []
B, R = body.append, reg.append
B(V.box("Top", (W + 0.4, D + 0.3, 0.3), (0, 0, TOP - 0.15), oak, bevel=0.06))
# solid only on the customer half; the owner half (+Y) is open shelving under the top
B(V.box("Core", (W, 1.8, TOP - 0.6), (0, -D / 2 + 1.1, (TOP - 0.6) / 2 + 0.3), dark))
B(V.box("Kick", (W - 0.2, 1.6, 0.3), (0, -D / 2 + 1.1, 0.15), black))
for x in (-W / 2 + 0.2, -W / 6, W / 6, W / 2 - 0.2):  # uprights on the owner side
    B(V.box("Upright", (0.3, D - 1.9, TOP - 0.3), (x, D / 2 - (D - 1.9) / 2 - 0.1, (TOP - 0.3) / 2), dark))
for z in (0.3, 2.4):
    B(V.box("OwnerShelf", (W - 0.3, D - 1.9, 0.14), (0, D / 2 - (D - 1.9) / 2 - 0.1, z), oak))
# customer side (-Y): cream panels framed in wood with a teal stripe
for i in range(5):
    x = -W / 2 + 1.4 + i * 2.8
    B(V.box("Panel", (2.4, 0.08, TOP - 1.6), (x, -D / 2 + 0.1, (TOP - 1.6) / 2 + 0.6), cream, bevel=0.03))
B(V.box("Stripe", (W, 0.1, 0.25), (0, -D / 2 + 0.08, TOP - 0.55), teal))
# owner side (+Y): open shelves under the top
for k in range(5):  # paper bags stacked on the owner-side shelf
    B(V.box("Bag", (0.9, 0.6, 1.0), (-5 + k * 0.4, D / 2 - 0.9, 3.0), paper, bevel=0.03))
for k in range(3):  # boxes of stock on the lower shelf
    B(V.box("StockBox", (1.4, 1.2, 1.0), (1.5 + k * 1.7, D / 2 - 1.0, 0.87), paper, bevel=0.04))
# cash register (owner keys + drawer face +Y), slightly left of centre
rx = -2.5
R(V.box("RegBase", (2.4, 2.0, 0.7), (rx, 0.2, TOP + 0.35), black, bevel=0.08))
R(V.box("Drawer", (2.2, 0.9, 0.35), (rx, 1.45, TOP + 0.2), black, bevel=0.03))  # pulled open toward the owner
for j, x in enumerate((-0.75, -0.25, 0.25, 0.75)):
    R(V.box("BillSlot", (0.42, 0.7, 0.05), (rx + x, 1.45, TOP + 0.38), bill))
for j in range(4):
    R(V.cylinder("CoinCup", 0.13, 0.08, (rx - 0.75 + j * 0.5, 1.85, TOP + 0.4), "Z", coin, verts=10))
R(V.box("KeyBlock", (1.9, 1.0, 0.45), (rx, 0.55, TOP + 0.85), grey, bevel=0.05))
R(V.box("KeyBlock_tilt", (1.8, 0.9, 0.08), (rx, 0.6, TOP + 1.1), black))
for r_ in range(3):
    for c_ in range(4):
        R(V.box("Key", (0.3, 0.2, 0.08), (rx - 0.6 + c_ * 0.4, 0.3 + r_ * 0.27, TOP + 1.16), V.paint("Key", V.rgb("F4F0E8"), rough=0.5)))
R(V.box("Pole", (0.15, 0.15, 0.8), (rx, -0.4, TOP + 1.1), grey))
R(V.box("Display", (1.2, 0.18, 0.55), (rx, -0.45, TOP + 1.65), black, bevel=0.04))
R(V.box("DisplayGlass", (1.0, 0.04, 0.38), (rx, -0.56, TOP + 1.65), screen))
R(V.box("ReceiptRoll", (0.5, 0.5, 0.35), (rx + 1.0, 0.0, TOP + 0.9), V.paint("RollBody", V.rgb("F4F0E8"), rough=0.6)))
# bell, tip jar, bills tray on top
R(V.cylinder("BellBase", 0.3, 0.08, (rx + 3.0, -0.6, TOP + 0.04), "Z", black, verts=16))
R(V.sphere("Bell", 0.28, (rx + 3.0, -0.6, TOP + 0.22), mat=brass, seg=14, rings=7))
R(V.cylinder("TipJar", 0.35, 0.8, (rx + 4.4, -0.8, TOP + 0.4), "Z", glass, verts=16))
R(V.box("TipBill", (0.4, 0.25, 0.05), (rx + 4.4, -0.8, TOP + 0.3), bill))
R(V.box("ChangeTray", (1.2, 0.8, 0.12), (rx + 2.2, 0.9, TOP + 0.06), teal, bevel=0.04))

finish({"Body": body, "Register": reg}, "counter", [
    ("customer34", (-10, -14, 10)),
    ("owner34", (10, 14, 11)),
    ("register", (-2.5, 6, 9)),
], 10, 6)
