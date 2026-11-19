"""Dusty Finds jeepney: a classic stainless-steel Filipino "owner-type" jeepney, about 21 long x 8.5 wide (matches
the current jeep). Shape follows the reference photo: rounded roof with drip rails, one long run of open windows over a
chrome belt line, a painted panel low on the side, big flared rear fenders with chrome edging, rounded rear corners,
tall tail lights, an open rear entrance with a step and grab bar, a short hood with a chrome grille.
Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/jeepney.py
Writes assets/jeepney/jeepney.fbx, assets/jeepney/textures/*.png, assets/jeepney/previews/*.png
Front = Blender -Y (Roblox -Z), up = Blender Z (Roblox Y), wheels touch Z 0. Our own text only (no real routes/plates).
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import vehicle_common as V  # noqa: E402

OUT = os.path.join(V.ROOT, "assets", "jeepney")
TEX = os.path.join(OUT, "textures")
PRE = os.path.join(OUT, "previews")

V.reset()
os.makedirs(TEX, exist_ok=True)

# ---- sign atlas (sharp, separate texture; 2048 x 1024, 8 rows of 128 px) -----------------------------------------
atlas_path = os.path.join(TEX, "jeepney_signs.png")
YEL, BLK = "FFD21F", "111111"
uv = V.sign_atlas(atlas_path, [
    (0, 1.0, "PANTALAN – PALENGKE – PLAZA – MUSEO", YEL, BLK),
    (1, 0.62, "DUSTY FINDS TRANSIT", YEL, BLK),
    (2, 0.25, "DFT-2026", YEL, BLK),
    (3, 0.30, "DUSTY FINDS TRANSIT\nPANTALAN – PLAZA\nAraw-araw 6AM–10PM\nDFT-2026", YEL, BLK, 3, 0.0),
    (3, 0.30, "PLAZA – MUSEO\nPAMASAHE: 13\nSakay na!", YEL, BLK, 3, 0.35),
    (6, 0.13, "Sakay na!", "D62828", "FFFFFF"),
])

# ---- materials ----------------------------------------------------------------------------------------------
steel = V.stainless("Steel", ribs=True, scale=7.0)
steel_flat = V.stainless("SteelFlat", ribs=False)
panel = V.paint("Panel", V.rgb("6F86A0"), rough=0.65)  # grey-blue side panel (Jeepney2: deep red)
chrome = V.chrome("Chrome")
tyre = V.rubber("Tyre")
rim = V.paint("Rim", V.rgb("E6E8EA"), rough=0.35, metal=0.6)
black = V.paint("Black", V.rgb("23252A"), rough=0.7)
tail = V.paint("TailLight", V.rgb("D42A20"), rough=0.25)
amber = V.paint("Amber", V.rgb("F2A33A"), rough=0.25)
lens = V.paint("Lens", V.rgb("FFF2CC"), rough=0.08)
glass = V.paint("Glass", V.rgb("2B3540"), rough=0.05, metal=0.2)
pin_r, pin_b, pin_y = V.paint("PinR", V.rgb("D62828")), V.paint("PinB", V.rgb("2457C5")), V.paint("PinY", V.rgb("FFD21F"))
dash = V.paint("Dash", V.rgb("3A3D44"), rough=0.6)

body, chromeparts, wheels = [], [], []
B, C, Wl = body.append, chromeparts.append, wheels.append
Y0, Y1 = -6.2, 10.6  # passenger body from the windshield to the rear
# belt line, window top, header top (roof sits on the header). Cabin raised 1 stud (2026-11-20) so tall avatars'
# heads clear the roof: seated hips sit ~5.0 above the road, so the ceiling is now ~9.5.
BELT, WTOP, HDR = 5.35, 8.75, 9.55


def roof(name, y0, y1, half_w=4.5, top=9.55, eave=8.5, shoulder=0.95, mat=None):
    """Rounded jeepney roof: flat top, big rounded shoulders down to a drip rail, extruded along Y with rounded ends."""
    prof = []
    steps = 6
    for i in range(steps + 1):  # right shoulder, from the top edge down to the eave
        a = math.pi / 2 * i / steps
        prof.append((half_w - shoulder + math.sin(a) * shoulder, top - shoulder + math.cos(a) * shoulder))
    prof.append((half_w + 0.08, eave + 0.05))  # drip rail lip
    prof.append((half_w + 0.08, eave - 0.05))
    prof.append((half_w - 0.3, eave - 0.05))
    full = [(-x, z) for x, z in reversed(prof)] + prof
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for x, z in full] for y in (y0, y1)]
    n = len(full)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    m = o.modifiers.new("Bevel", "BEVEL")  # round the front and rear ends of the roof
    m.width = 0.45
    m.segments = 3
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(50)
    bpy.ops.object.modifier_apply(modifier=m.name)
    o.select_set(False)
    if mat:
        me.materials.append(mat)
    return o


# ---- floor, lower sides, rounded rear corners ------------------------------------------------------------------
B(V.box("Floor", (8.2, Y1 - Y0, 0.4), (0, (Y0 + Y1) / 2, 2.45), steel_flat))
for s in (-1, 1):
    # lower side: stainless with embossed ribbing, from behind the driver's opening to the rear corner
    B(V.box("LowerSide", (0.4, 14.0, BELT - 2.3), (s * 4.05, 3.4, (BELT + 2.3) / 2), steel, bevel=0.12))
    # driver's side area: lower panel only (open above it, like the photo)
    B(V.box("CabSide", (0.4, 2.6, 2.3), (s * 4.05, -4.9, 3.45), steel, bevel=0.12))
    # painted side panel (grey-blue), framed by chrome
    B(V.box("Panel", (0.06, 8.6, 2.3), (s * 4.27, 0.6, 3.75), panel))
    C(V.box("PanelTrimTop", (0.08, 8.8, 0.1), (s * 4.3, 0.6, 4.92), chrome))
    C(V.box("PanelTrimBot", (0.08, 8.8, 0.1), (s * 4.3, 0.6, 2.58), chrome))
    for yy in (-3.75, 4.95):
        C(V.box("PanelTrimEnd", (0.08, 0.1, 2.4), (s * 4.3, yy, 3.75), chrome))
    for z, m in ((5.05, pin_r), (5.14, pin_b), (5.23, pin_y)):
        B(V.box("Pin", (0.05, 14.0, 0.07), (s * 4.27, 3.4, z), m))
    # chrome belt line, running board, window top rail
    C(V.box("Belt", (0.12, Y1 - Y0 - 0.6, 0.16), (s * 4.3, (Y0 + Y1) / 2, BELT + 0.05), chrome))
    C(V.box("RunningBoard", (0.45, 9.8, 0.22), (s * 4.35, 0.6, 2.25), chrome))
    C(V.box("WindowRail", (0.08, 14.2, 0.1), (s * 4.25, 3.4, WTOP - 0.35), chrome))
    # window pillars (wide stainless pillars between the long open windows)
    for yy in (-6.0, -3.6, -0.6, 2.4, 5.4, 8.2):
        B(V.box("Pillar", (0.38, 0.55, WTOP - BELT), (s * 4.05, yy, (BELT + WTOP) / 2), steel_flat, bevel=0.06))
    # header above the windows
    B(V.box("Header", (0.38, Y1 - Y0, HDR - WTOP), (s * 4.05, (Y0 + Y1) / 2, (WTOP + HDR) / 2), steel_flat))
    # rounded rear corner post
    B(V.cylinder("RearCorner", 0.5, HDR - 2.3, (s * 3.75, Y1 - 0.25, (HDR + 2.3) / 2), "Z", steel_flat, verts=14))
    # tall tail lights in the rear corners + amber marker
    B(V.box("TailLight", (0.55, 0.16, 1.5), (s * 3.55, Y1 + 0.18, 6.9), tail, bevel=0.05))
    B(V.box("Marker", (0.4, 0.16, 0.4), (s * 3.55, Y1 + 0.18, 5.85), amber))
# rear: open entrance between X -1.2 and 2.6; step, bumper, grab bar
B(V.box("RearWallL", (2.6, 0.35, BELT - 2.3), (-2.5, Y1, (BELT + 2.3) / 2), steel, bevel=0.1))
B(V.box("RearWallR", (1.2, 0.35, BELT - 2.3), (3.2, Y1, (BELT + 2.3) / 2), steel, bevel=0.1))
B(V.box("RearHeader", (7.6, 0.35, HDR - WTOP + 0.6), (0, Y1, (WTOP - 0.6 + HDR) / 2), steel_flat))
for xx in (-3.0, 3.0):
    B(V.box("RearPillar", (0.5, 0.35, WTOP - BELT), (xx, Y1, (BELT + WTOP) / 2), steel_flat))
C(V.box("RearBumper", (8.2, 0.5, 0.45), (0, Y1 + 0.35, 2.15), chrome, bevel=0.1))
B(V.box("RearStep", (3.4, 1.0, 0.22), (0.7, Y1 + 0.75, 1.55), steel_flat))
C(V.tube("GrabBar", [(2.45, Y1 + 0.25, 2.6), (2.45, Y1 + 0.25, WTOP)], 0.08, chrome))
# roof
B(roof("Roof", Y0 - 0.45, Y1 + 0.35, top=HDR + 1.0, eave=HDR - 0.05, mat=steel_flat))
# ---- cab: windshield, dash, front wall --------------------------------------------------------------------------
B(V.box("CabFront", (8.0, 0.35, 1.9), (0, Y0, 3.55), steel))
B(V.box("Dash", (7.4, 0.9, 0.45), (0, Y0 + 0.35, 4.7), dash))
B(V.box("Windshield", (7.2, 0.08, WTOP - 5.15), (0, Y0 - 0.05, (5.05 + WTOP) / 2), glass))
C(V.box("WindFrameTop", (7.6, 0.2, 0.18), (0, Y0 - 0.1, WTOP - 0.05), chrome))
C(V.box("WindFrameBot", (7.6, 0.2, 0.18), (0, Y0 - 0.1, 5.0), chrome))
for s in (-1, 1):
    B(V.box("WindPost", (0.35, 0.4, WTOP - 4.4), (s * 3.85, Y0, (4.7 + WTOP) / 2), steel_flat))
# ---- hood, grille, headlights, bumper, horses ----------------------------------------------------------------
B(V.box("Hood", (6.4, 4.0, 1.5), (0, -8.2, 3.85), steel, bevel=0.35, segments=4))
B(V.box("GrilleBack", (5.0, 0.2, 1.6), (0, -10.15, 3.7), black))
z = 3.05
while z <= 4.4:
    C(V.box("GrilleBar", (5.0, 0.14, 0.08), (0, -10.3, z), chrome))
    z += 0.22
C(V.box("GrilleFrame", (5.4, 0.2, 0.2), (0, -10.3, 4.55), chrome, bevel=0.05))
for s in (-1, 1):
    C(V.cylinder("HeadRing", 0.6, 0.3, (s * 2.95, -10.15, 3.75), "Y", chrome, verts=20))
    B(V.cylinder("HeadLens", 0.48, 0.34, (s * 2.95, -10.2, 3.75), "Y", lens, verts=20))
    hx = s * 1.5
    C(V.box("HorseBody", (0.34, 0.85, 0.42), (hx, -9.55, 4.82), chrome, bevel=0.06))
    C(V.box("HorseNeck", (0.26, 0.3, 0.55), (hx, -9.95, 5.2), chrome, bevel=0.04))
    C(V.box("HorseHead", (0.26, 0.5, 0.26), (hx, -10.12, 5.52), chrome, bevel=0.04))
    for dy in (-0.28, 0.28):
        C(V.box("HorseLeg", (0.11, 0.11, 0.32), (hx, -9.55 + dy, 4.5), chrome))
C(V.box("Bumper", (8.4, 0.5, 0.55), (0, -10.65, 2.15), chrome, bevel=0.12))
# ---- fenders: front arches, big flared rear fenders with chrome edging -------------------------------------------
FX, RX, FY, RY = 3.55, 3.8, -7.9, 6.5
for s in (-1, 1):
    B(V.arch("FrontFender", 1.75, 0.3, 1.5, (s * FX, FY, 1.5), steel_flat, segs=14))
    C(V.arch("FrontFenderTrim", 2.05, 0.08, 1.55, (s * FX, FY, 1.5), chrome, segs=14))
    B(V.box("FenderSkirt", (1.4, 1.6, 0.9), (s * FX, FY + 2.3, 2.75), steel_flat, bevel=0.2))
    # rear fender: a flared bulge on the side with a chrome edge around the wheel opening
    B(V.arch("RearFender", 1.85, 0.55, 1.35, (s * (RX + 0.45), RY, 1.5), steel_flat, segs=16))
    B(V.sphere("RearFenderBulge", 1.0, (s * 4.25, RY, 3.35), scale=(0.42, 2.7, 1.25), mat=steel_flat, seg=20, rings=10))
    C(V.arch("RearFenderTrim", 2.42, 0.1, 1.42, (s * (RX + 0.45), RY, 1.5), chrome, segs=16))
# ---- wheels: chunky tyres, white rims with lug nuts --------------------------------------------------------------
for (fx, fy) in ((FX, FY), (RX, RY)):
    for s in (-1, 1):
        Wl(V.cylinder("Tyre", 1.5, 1.1, (s * fx, fy, 1.5), "X", tyre, verts=24))
        Wl(V.cylinder("Rim", 0.85, 1.14, (s * fx, fy, 1.5), "X", rim, verts=18))
        C(V.cylinder("HubCap", 0.32, 1.2, (s * fx, fy, 1.5), "X", chrome, verts=12))
        for k in range(6):
            a = k * math.pi / 3
            C(V.cylinder("Lug", 0.07, 1.22, (s * fx, fy + math.cos(a) * 0.55, 1.5 + math.sin(a) * 0.55), "X", chrome, verts=6))
for s in (-1, 1):
    B(V.box("MudFlapR", (1.3, 0.08, 1.15), (s * RX, RY + 2.0, 0.85), black))
    B(V.box("MudFlapF", (1.2, 0.08, 1.0), (s * FX, FY + 1.9, 0.95), black))
    C(V.tube("MirrorArm", [(s * 4.0, Y0 - 0.1, 6.9), (s * 4.75, Y0 - 0.4, 7.1)], 0.05, chrome))
    C(V.box("Mirror", (0.14, 0.5, 0.75), (s * 4.85, Y0 - 0.45, 7.15), chrome))

# ---- signs (separate object, sharp atlas texture) ----------------------------------------------------------------
signs = []
for s, face in ((1, "+X"), (-1, "-X")):
    # boards that sit in the window openings get a stainless backing so they are not see-through from inside
    B(V.box("BeltBoardBack", (0.06, 10.6, 0.65), (s * 4.2, 1.6, BELT + 0.45), steel_flat))
    B(V.box("RearBoardBack", (0.06, 2.05, 1.85), (s * 4.2, 9.4, 6.6), steel_flat))
    signs.append(V.sign_quad("RouteBelt", (s * 4.23, 1.6, BELT + 0.45), 10.4, 0.55, face, uv[0], push=0.02))
    signs.append(V.sign_quad("InfoBoard", (s * 4.3, 1.8, 3.75), 2.6, 1.95, face, uv[3], push=0.02))
    signs.append(V.sign_quad("RearBoard", (s * 4.23, 9.4, 6.6), 1.9, 1.7, face, uv[(3, 0.35)], push=0.02))
    signs.append(V.sign_quad("SidePlate", (s * 4.27, 9.85, 4.55), 1.15, 0.4, face, uv[2], push=0.04))
signs.append(V.sign_quad("SmallBoard", (0, Y0 - 0.2, HDR - 0.4), 6.0, 0.55, "-Y", uv[1], push=0.02))
signs.append(V.sign_quad("PlateFront", (0, -10.92, 2.15), 2.0, 0.5, "-Y", uv[2], push=0.01))
signs.append(V.sign_quad("PlateRear", (-2.5, Y1 + 0.2, 3.3), 2.0, 0.5, "+Y", uv[2], push=0.01))
signs.append(V.sign_quad("Sticker", (-2.5, Y1 + 0.2, 4.55), 1.1, 0.55, "+Y", uv[6], push=0.01))

body_o = V.join(body, "Body")
chrome_o = V.join(chromeparts, "Chrome")
wheels_o = V.join(wheels, "Wheels")
signs_o = V.join(signs, "Signs")
print("[jeepney] triangles:", {o.name: V.tris(o) for o in (body_o, chrome_o, wheels_o, signs_o)})

# ---- bake ---------------------------------------------------------------------------------------------------
maps = {}
for o in (body_o, chrome_o, wheels_o):
    V.smart_uv(o)
    maps[o.name] = V.bake_maps(o, TEX, "jeepney_" + o.name.lower())
# Jeepney2 variant: deep red side panel (colour map only; the other maps are shared)
panel.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = V.rgb("8E1B1B")
V.bake_maps(body_o, TEX, "jeepney_body_red", color_only=True)
for o in (body_o, chrome_o, wheels_o):
    V.swap_material(o, V.baked_material(o.name + "_baked", maps[o.name]))
V.swap_material(signs_o, V.sign_material("Signs_mat", atlas_path))

V.export_fbx(os.path.join(OUT, "jeepney.fbx"), [body_o, chrome_o, wheels_o, signs_o])
V.previews(PRE, "jeepney", 12, 4.2, [
    ("front34", (-17, -24, 8.5)),
    ("side", (30, 1.5, 5.5)),
    ("rear", (13, 24, 8)),
])
print("[jeepney] done:", OUT)
