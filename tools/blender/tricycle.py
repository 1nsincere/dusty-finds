"""Dusty Finds tricycle: a classic Filipino tricycle, about 10 long x 5 wide x 7 tall, following the reference photo:
a tall enclosed sidecar cab (domed roof with ornate chrome trim, an upper front panel with the route/number board between
painted art panels, open windshield, round headlights over a chrome bumper-grille, a big coloured front mudflap with a
chrome emblem, chrome fender over the sidecar wheel) bolted to the motorcycle's RIGHT side, plus a curved canopy over
the rider with a striped visor windshield, chrome spoked wheels, a bright tank and chrome side plate.
Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/tricycle.py
Writes assets/tricycle/tricycle.fbx (one shared mesh) + textures/ (shared normal/roughness/metal maps, one Body colour
map and one sign atlas per tricycle DF-01..DF-04) + previews/.
Front = Blender -Y (Roblox -Z), up = Blender Z (Roblox Y), wheels touch Z 0. Facing -Y, the vehicle's right is -X, so the
sidecar sits at -X and the motorcycle at +X. Our own text only.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import vehicle_common as V  # noqa: E402

OUT = os.path.join(V.ROOT, "assets", "tricycle")
TEX = os.path.join(OUT, "textures")
PRE = os.path.join(OUT, "previews")

# the 4 tricycles: number, route, body colour, accent colour (mudflap, stripes, canopy edge)
FLEET = [
    ("DF-01", "WEST", "C8202A", "F6C51A"),      # red / yellow
    ("DF-02", "WEST", "1E4FB0", "F2F2F0"),      # blue / white
    ("DF-03", "PANTALAN", "1F8A3C", "F6C51A"),  # green / yellow
    ("DF-04", "PANTALAN", "F07A1A", "1A1A1A"),  # orange / black
]

V.reset()
os.makedirs(TEX, exist_ok=True)

# ---- one sign atlas per tricycle -------------------------------------------------------------------------------
YEL, BLK = "FFD21F", "111111"
atlases = []
uv = None
for num, route, base, accent in FLEET:
    p = os.path.join(TEX, f"tricycle_signs_{num.replace('-', '')}.png")
    uv = V.sign_atlas(p, [
        (0, 0.20, f"{route}\n{num}", YEL, BLK, 2, 0.0),
        (2, 0.18, num, "F4F4F0", BLK),
        (3, 0.13, "Sakay na!", "D62828", "FFFFFF"),
    ])
    atlases.append(p)

# ---- materials -------------------------------------------------------------------------------------------------
base0, acc0 = V.rgb(FLEET[0][2]), V.rgb(FLEET[0][3])
body_paint = V.paint("BodyPaint", base0, rough=0.3)
accent_paint = V.paint("AccentPaint", acc0, rough=0.35)
stripe_paint = V.striped_paint("StripePaint", acc0, base0, scale=2.2, direction="X")


def art(name):
    """Painted flame / swirl art for the side panels beside the sign (colourful noise bands)."""
    m, nt, b = V._mat(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.5
    nz.inputs["Detail"].default_value = 4.0
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.interpolation = "CONSTANT"
    els = cr.color_ramp.elements
    els[0].position, els[0].color = 0.0, V.rgb("1F8A3C")
    els[1].position, els[1].color = 0.45, V.rgb("F07A1A")
    e = els.new(0.58)
    e.color = V.rgb("D62828")
    e2 = els.new(0.7)
    e2.color = V.rgb("FFD21F")
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.3
    return m


art_m = art("Art")
chrome = V.chrome("Chrome")
tyre = V.rubber("Tyre")
black = V.paint("Black", V.rgb("202226"), rough=0.6)
seat_m = V.paint("Seat", V.rgb("2A2522"), rough=0.75)
engine = V.paint("Engine", V.rgb("5A5E64"), rough=0.4, metal=0.7)
lens = V.paint("Lens", V.rgb("FFF2CC"), rough=0.08)
amber = V.paint("Amber", V.rgb("F2A33A"), rough=0.2)
visor = V.paint("Visor", V.rgb("C9DCE6"), rough=0.1)
tail = V.paint("Tail", V.rgb("D42A20"), rough=0.3)

body, chromeparts, wheels = [], [], []
B, C, Wl = body.append, chromeparts.append, wheels.append
SX0, SX1 = -2.5, 0.0  # sidecar X range (vehicle's right side)
SY0, SY1 = -3.4, 2.8  # sidecar Y range
SC = (SX0 + SX1) / 2
SW = SX1 - SX0
MX = 1.45  # motorcycle centre line
# cab roof raised 1.3 (2026-11-20) so tall avatars sitting in the sidecar (hips ~2.8) clear it
BASE_TOP, CAB_TOP = 2.35, 6.6


def spoked_wheel(x, y, r, w):
    Wl(V.cylinder("Tyre", r, w, (x, y, r), "X", tyre, verts=22))
    C(V.cylinder("Rim", r * 0.72, w + 0.02, (x, y, r), "X", chrome, verts=20))
    Wl(V.cylinder("RimInner", r * 0.64, w + 0.03, (x, y, r), "X", black, verts=20))
    C(V.cylinder("HubC", r * 0.16, w + 0.12, (x, y, r), "X", chrome, verts=10))
    for k in range(8):  # spokes
        a = k * math.pi / 8
        C(V.box("Spoke", (0.03, r * 1.28, 0.03), (x, y, r), chrome))
        sp = chromeparts[-1]
        sp.rotation_euler = (a, 0, 0)
        import bpy
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = sp
        sp.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        sp.select_set(False)


# ---- sidecar cab ---------------------------------------------------------------------------------------------------
B(V.box("SideBase", (SW, SY1 - SY0, BASE_TOP - 0.8), (SC, (SY0 + SY1) / 2, (BASE_TOP + 0.8) / 2), body_paint, bevel=0.2))
B(V.box("Nose", (SW - 0.1, 0.7, 1.7), (SC, SY0 - 0.3, 1.8), body_paint, bevel=0.3, segments=3))
for z in (1.25, BASE_TOP):
    for x in (SX0 - 0.03, SX1 + 0.03):
        C(V.box("SideTrim", (0.06, SY1 - SY0, 0.1), (x, (SY0 + SY1) / 2, z), chrome))
# front: headlights, chrome bumper-grille, big mudflap with chrome emblem
for x in (SX0 + 0.45, SX1 - 0.45):
    C(V.cylinder("HeadRing", 0.27, 0.2, (x, SY0 - 0.68, 2.1), "Y", chrome, verts=16))
    B(V.cylinder("HeadLens", 0.21, 0.22, (x, SY0 - 0.7, 2.1), "Y", amber, verts=16))
C(V.tube("BumperTop", [(SX0 + 0.05, SY0 - 0.85, 2.55), (SX1 - 0.05, SY0 - 0.85, 2.55)], 0.06, chrome))
C(V.tube("BumperLow", [(SX0 + 0.05, SY0 - 0.85, 1.45), (SX1 - 0.05, SY0 - 0.85, 1.45)], 0.06, chrome))
for i in range(6):
    x = SX0 + 0.25 + i * (SW - 0.5) / 5
    C(V.tube("GrilleBar", [(x, SY0 - 0.85, 1.45), (x, SY0 - 0.85, 2.55)], 0.04, chrome))
B(V.box("Mudflap", (SW - 0.4, 0.08, 1.1), (SC, SY0 - 0.75, 0.6), accent_paint, bevel=0.04))
C(V.cylinder("Emblem", 0.35, 0.1, (SC, SY0 - 0.8, 0.65), "Y", chrome, verts=16))
# cab pillars, side walls, rear wall
for (x, y) in ((SX0 + 0.1, SY0 + 0.1), (SX1 - 0.1, SY0 + 0.1), (SX0 + 0.1, SY1 - 0.1), (SX1 - 0.1, SY1 - 0.1), (SX0 + 0.1, 0.4)):
    B(V.box("Pillar", (0.2, 0.2, CAB_TOP - BASE_TOP), (x, y, (BASE_TOP + CAB_TOP) / 2), body_paint))
B(V.box("RearWall", (SW, 0.2, CAB_TOP - BASE_TOP), (SC, SY1 - 0.1, (BASE_TOP + CAB_TOP) / 2), body_paint))
B(V.box("InnerWallLow", (0.15, SY1 - SY0, 1.0), (SX1 - 0.08, (SY0 + SY1) / 2, BASE_TOP + 0.5), body_paint))
B(V.box("InnerRail", (0.15, SY1 - SY0, 0.3), (SX1 - 0.08, (SY0 + SY1) / 2, CAB_TOP - 0.15), body_paint))
B(V.box("OuterRearWall", (0.15, SY1 - 0.4, 1.0), (SX0 + 0.08, (0.4 + SY1) / 2, BASE_TOP + 0.5), body_paint))
B(V.box("OuterRail", (0.15, SY1 - SY0, 0.3), (SX0 + 0.08, (SY0 + SY1) / 2, CAB_TOP - 0.15), body_paint))
# upper front panel: sign board in the middle, painted art panels either side
B(V.box("FrontPanel", (SW, 0.2, 1.15), (SC, SY0 + 0.1, CAB_TOP - 0.55), body_paint))
for x in (SX0 + 0.33, SX1 - 0.33):
    B(V.box("ArtPanel", (0.5, 0.06, 0.95), (x, SY0 - 0.02, CAB_TOP - 0.55), art_m, bevel=0.03))
C(V.box("PanelTrim", (SW + 0.1, 0.08, 0.08), (SC, SY0, CAB_TOP - 1.15), chrome))
# domed roof with ornate chrome rim and a front crown badge
B(V.box("Roof", (SW + 0.3, SY1 - SY0 + 0.4, 0.3), (SC, (SY0 + SY1) / 2, CAB_TOP + 0.15), body_paint, bevel=0.12))
B(V.box("RoofDome", (SW - 0.2, SY1 - SY0 - 0.4, 0.35), (SC, (SY0 + SY1) / 2, CAB_TOP + 0.45), body_paint, bevel=0.16, segments=3))
for (a, b) in (((SX0 - 0.15, SY0 - 0.2), (SX1 + 0.15, SY0 - 0.2)), ((SX0 - 0.15, SY1 + 0.2), (SX1 + 0.15, SY1 + 0.2)),
               ((SX0 - 0.15, SY0 - 0.2), (SX0 - 0.15, SY1 + 0.2)), ((SX1 + 0.15, SY0 - 0.2), (SX1 + 0.15, SY1 + 0.2))):
    C(V.tube("RoofRim", [(a[0], a[1], CAB_TOP + 0.02), (b[0], b[1], CAB_TOP + 0.02)], 0.06, chrome))
C(V.box("Crown", (SW - 0.4, 0.1, 0.55), (SC, SY0 - 0.15, CAB_TOP + 0.62), chrome, bevel=0.04))
B(V.box("CrownBadge", (0.55, 0.06, 0.4), (SC, SY0 - 0.22, CAB_TOP + 0.62), art_m))
# sidecar wheel at the front corner, chrome fender, side step
spoked_wheel(SX0 + 0.2, SY0 + 0.9, 0.75, 0.3)
C(V.arch("SideFender", 0.85, 0.07, 0.45, (SX0 + 0.2, SY0 + 0.9, 0.75), chrome, segs=12, start=0.15, end=math.pi * 0.95))
C(V.box("SplashPlate", (0.06, 1.6, 0.6), (SX0 - 0.05, SY0 + 2.1, 1.1), chrome))
C(V.box("Step", (0.6, 1.0, 0.12), (SX0 - 0.3, -0.6, 0.95), chrome))
B(V.box("SideSeat", (SW - 0.5, 2.2, 0.3), (SC, 1.3, BASE_TOP + 0.05), seat_m, bevel=0.08))

# ---- motorcycle ----------------------------------------------------------------------------------------------------
spoked_wheel(MX, -3.85, 0.85, 0.34)
spoked_wheel(MX, 3.0, 0.85, 0.34)
C(V.arch("FrontFender", 0.95, 0.06, 0.4, (MX, -3.85, 0.85), chrome, segs=10, start=0.4, end=math.pi * 0.9))
B(V.arch("RearFender", 0.95, 0.06, 0.4, (MX, 3.0, 0.85), black, segs=10, start=0.1, end=math.pi * 0.75))
C(V.tube("ForkL", [(MX - 0.17, -3.85, 0.85), (MX - 0.17, -3.3, 3.0)], 0.06, chrome))
C(V.tube("ForkR", [(MX + 0.17, -3.85, 0.85), (MX + 0.17, -3.3, 3.0)], 0.06, chrome))
C(V.tube("Handlebar", [(MX - 0.8, -3.05, 3.5), (MX - 0.3, -3.2, 3.3), (MX + 0.3, -3.2, 3.3), (MX + 0.8, -3.05, 3.5)], 0.05, chrome))
C(V.cylinder("HeadRing", 0.36, 0.28, (MX, -3.55, 3.05), "Y", chrome, verts=18))
B(V.cylinder("Headlight", 0.3, 0.3, (MX, -3.6, 3.05), "Y", lens, verts=18))
for dx in (-0.55, 0.55):
    B(V.sphere("Indicator", 0.12, (MX + dx, -3.4, 3.15), mat=amber, seg=10, rings=6))
B(V.box("Frame", (0.25, 4.4, 0.22), (MX, -0.6, 2.35), black))
B(V.box("Engine", (0.7, 1.4, 0.9), (MX, -0.7, 1.35), engine, bevel=0.1))
C(V.box("SidePlate", (0.06, 1.5, 0.9), (MX + 0.45, -0.8, 1.45), chrome, bevel=0.03))
B(V.box("Tank", (0.8, 1.5, 0.62), (MX, -1.95, 2.85), stripe_paint, bevel=0.25, segments=3))
B(V.box("Seat", (0.72, 2.6, 0.3), (MX, 0.6, 2.75), seat_m, bevel=0.12))
B(V.box("TailLight", (0.4, 0.12, 0.2), (MX, 3.5, 2.4), tail))
C(V.tube("Exhaust", [(MX + 0.35, -0.7, 1.1), (MX + 0.45, 1.6, 1.0), (MX + 0.45, 3.8, 1.25)], 0.12, chrome))
# visor windshield with a striped art panel, in front of the rider
B(V.box("Visor", (1.5, 0.06, 1.25), (MX, -3.35, 4.15), visor, bevel=0.05))
B(V.box("VisorArt", (0.35, 0.07, 1.2), (MX - 0.55, -3.37, 4.12), stripe_paint))
C(V.tube("VisorFrame", [(MX - 0.75, -3.35, 3.5), (MX - 0.75, -3.35, 4.8), (MX + 0.75, -3.35, 4.8), (MX + 0.75, -3.35, 3.5)], 0.04, chrome))
# rider canopy joined to the sidecar roof, with chrome edge and posts
RX0, RX1, RY0, RY1, RZ = SX1 - 0.2, MX + 1.0, -2.6, 1.6, CAB_TOP + 0.85
B(V.box("RiderRoof", (RX1 - RX0, RY1 - RY0, 0.22), ((RX0 + RX1) / 2, (RY0 + RY1) / 2, RZ), body_paint, bevel=0.1))
B(V.box("RiderRoofLip", (RX1 - RX0, 0.3, 0.5), ((RX0 + RX1) / 2, RY0, RZ - 0.15), accent_paint, bevel=0.1))
C(V.tube("RiderRoofEdge", [(RX0, RY0 - 0.16, RZ - 0.4), (RX1, RY0 - 0.16, RZ - 0.4), (RX1, RY1, RZ - 0.1)], 0.05, chrome))
C(V.tube("RiderPostF", [(MX + 0.8, -2.4, 2.4), (MX + 0.8, -2.4, RZ - 0.1)], 0.06, chrome))
C(V.tube("RiderPostR", [(MX + 0.8, 1.4, 2.6), (MX + 0.8, 1.4, RZ - 0.1)], 0.06, chrome))
B(V.box("RoofJoin", (0.5, RY1 - RY0, 0.6), (SX1, (RY0 + RY1) / 2, CAB_TOP + 0.55), body_paint))

# ---- signs -------------------------------------------------------------------------------------------------------
signs = [
    V.sign_quad("FrontBoard", (SC, SY0, CAB_TOP - 0.55), 1.15, 0.9, "-Y", uv[0], push=0.06),
    V.sign_quad("NumberSide", (SX0, -0.9, 1.75), 1.0, 0.5, "-X", uv[2], push=0.05),
    V.sign_quad("NumberBack", (SC, SY1, 1.75), 1.0, 0.5, "+Y", uv[2], push=0.05),
    V.sign_quad("Sticker", (SC, SY1, CAB_TOP - 0.9), 0.8, 0.4, "+Y", uv[3], push=0.05),
]

body_o = V.join(body, "Body")
chrome_o = V.join(chromeparts, "Chrome")
wheels_o = V.join(wheels, "Wheels")
signs_o = V.join(signs, "Signs")
print("[tricycle] triangles:", {o.name: V.tris(o) for o in (body_o, chrome_o, wheels_o, signs_o)})

# ---- bake: shared maps from DF-01, then one Body colour map per colourway ------------------------------------------
maps = {}
for o in (body_o, chrome_o, wheels_o):
    V.smart_uv(o)
    maps[o.name] = V.bake_maps(o, TEX, "tricycle_" + o.name.lower())


def set_colours(base_hex, acc_hex):
    base, acc = V.rgb(base_hex), V.rgb(acc_hex)
    body_paint.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = base
    accent_paint.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = acc
    ramp = [n for n in stripe_paint.node_tree.nodes if n.type == "VALTORGB"][0]
    ramp.color_ramp.elements[0].color = acc
    ramp.color_ramp.elements[1].color = base


for num, route, base, acc in FLEET:
    set_colours(base, acc)
    V.bake_maps(body_o, TEX, f"tricycle_body_{num.replace('-', '')}", color_only=True)

maps["Body"]["color"] = os.path.join(TEX, "tricycle_body_DF01_color.png")
for o in (body_o, chrome_o, wheels_o):
    V.swap_material(o, V.baked_material(o.name + "_baked", maps[o.name]))
V.swap_material(signs_o, V.sign_material("Signs_mat", atlases[0]))

V.export_fbx(os.path.join(OUT, "tricycle.fbx"), [body_o, chrome_o, wheels_o, signs_o])
V.previews(PRE, "tricycle", 6, 2.8, [
    ("front34", (-8, -12, 5)),
    ("side", (-15, 0.2, 3.5)),
    ("rear", (9, 12, 5.5)),
])
print("[tricycle] done:", OUT)
