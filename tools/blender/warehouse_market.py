"""Dusty Finds Warehouse Market v2: bigger, "modern vintage" loft market (Blender 5.x, headless).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/warehouse_market.py
Writes assets/models/WarehouseMarket.glb and assets/previews/WarehouseMarket_*.png (git-ignored). v1 is warehouse_market_v1.py.

Style: VINTAGE = red brick, oak, brass, striped awnings, chandeliers, gas lanterns, warm cream plaster.
       MODERN  = black steel-framed glazing, a glass-walled curtain front, steel trusses and I-beams, glass balustrade,
                 polished concrete floor, backlit sign, industrial pendant domes, long skylights.
Plan (placeholder geometry, not final art), 120 x 110 studs, eaves 32, ridge 41.6:
  GROUND   double-height entrance hall (runner rug, grand oak stair on the east wall, chandeliers, directory) +
           three big stalls under the mezzanine: Supply Crates (west), Shelves & Pedestals (centre), Skins Booth (east)
  UPSTAIRS oak mezzanine over the back: Cozy Living, Kitchen Nook, Gallery & Study (glazed partitions) + the Paint Bar
Studs, z up, floor top z = 0, facade faces -Y, centred on x = 0, y = 0. Objects are "<Zone>_<Colour>" (one MeshPart each).
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

c.reset_scene()

COL = {
    "Brick": "A0573D", "BrickDark": "74392B", "Plaster": "EBDBB6", "Timber": "5B3A24", "Oak": "B58A57",
    "OakDark": "8A6238", "Slate": "4A5056", "Brass": "C9A24A", "Green": "3F6046", "Cream": "F3E7CB",
    "Maroon": "7B2D33", "Glass": "A9C4BA", "Stone": "B8AD99", "Iron": "2C2C2E", "Mustard": "D6A33E",
    "Teal": "3F7070", "Plum": "6E4A7E", "Terracotta": "C86A4A", "Leaf": "5F8A4E", "Paper": "F1E8D0",
    "Letters": "2A1D14", "Glow": "FFD98A", "Canvas": "6C8E8C", "Fridge": "CFE0D4", "Navy": "34476E",
    "Concrete": "C9C4B8",
}
c.PALETTE.update(COL)
G = {}


def bm_for(key):
    if key not in G:
        G[key] = bmesh.new()
    return G[key]


def B(key, size, loc, rot=(0, 0, 0)):
    m = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((size[0], size[1], size[2], 1))
    bmesh.ops.create_cube(bm_for(key), size=1.0, matrix=m)


def C(key, r, h, loc, rot=(0, 0, 0), seg=12, r2=None):
    m = Matrix.Translation(Vector(loc)) @ Euler(rot).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm_for(key), cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h, matrix=m)


def S(key, r, loc, scale=(1, 1, 1), seg=10, rings=6):
    m = Matrix.Translation(Vector(loc)) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1))
    bmesh.ops.create_uvsphere(bm_for(key), u_segments=seg, v_segments=rings, radius=r, matrix=m)


def PRISM(key, pts, y0, y1):
    bm = bm_for(key)
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((a[i], a[j], b[j], b[i]))


TEXTS, GLOWTEXTS = [], []


def TXT(body, loc, size, facing="-y", extrude=0.12, glow=False):
    rot = {"-y": (math.pi / 2, 0, 0), "+x": (math.pi / 2, 0, math.pi / 2), "+y": (math.pi / 2, 0, math.pi)}[facing]
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.active_object
    t.data.body = body
    t.data.size = size
    t.data.extrude = extrude
    t.data.resolution_u = 2
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    (GLOWTEXTS if glow else TEXTS).append(bpy.context.active_object)


# ------------------------------------------------------------------ dimensions
XO, WT = 60.0, 1.8
XI = XO - WT            # inner half width 58.2
YF, YB = -55.0, 55.0    # outer front/back faces
YI = YB - WT            # inner back 53.2
WH = 32.0               # wall height
TOP = 41.6              # roof top line at the ridge
DECK = 17.0             # mezzanine top
DY0 = -10.0             # mezzanine front edge
TH = math.atan2(9.0, XO)  # roof pitch


# ------------------------------------------------------------------ wall helpers
def WB(key, facing, base, u, v, du, dn, dv, off=0.0):
    """Box on a wall: u along the wall, v = height, du/dn/dv = size along wall / through wall / vertical."""
    s = 1 if facing.endswith("+") else -1
    if facing[0] == "x":
        B(key, (dn, du, dv), (base + s * off, u, v))
    else:
        B(key, (du, dn, dv), (u, base + s * off, v))


def steelwin(zone, facing, base, u, v, w, h, cols=3, rows=2, sill=True):
    """Black steel-framed window (modern) with pale glass, a brick-vintage stone sill."""
    for du, dv, uu, vv in ((w + 0.8, 0.4, u, v + h / 2 + 0.2), (w + 0.8, 0.4, u, v - h / 2 - 0.2),
                           (0.4, h, u - w / 2 - 0.2, v), (0.4, h, u + w / 2 + 0.2, v)):
        WB(zone + "_Iron", facing, base, uu, vv, du, WT + 0.5, dv)
    WB(zone + "_Glass", facing, base, u, v, w, 0.3, h)
    for k in range(1, cols):
        WB(zone + "_Iron", facing, base, u - w / 2 + k * w / cols, v, 0.3, 0.6, h)
    for k in range(1, rows):
        WB(zone + "_Iron", facing, base, u, v - h / 2 + k * h / rows, w, 0.6, 0.3)
    if sill:
        WB(zone + "_Stone", facing, base, u, v - h / 2 - 0.7, w + 2.0, WT + 1.0, 0.5, off=0.0)


def pierwall(facing, base, u0, u1, bands, centers, ww, zone="Shell"):
    """Brick wall built from bands so the windows are real openings. bands = [(z0, z1, windowed, key)]."""
    for z0, z1, win, key in bands:
        if not win:
            WB(zone + "_" + key, facing, base, (u0 + u1) / 2, (z0 + z1) / 2, u1 - u0, WT, z1 - z0)
        else:
            e = u0
            for uc in centers:
                if uc - ww / 2 > e:
                    WB(zone + "_Brick", facing, base, (e + uc - ww / 2) / 2, (z0 + z1) / 2, uc - ww / 2 - e, WT, z1 - z0)
                e = uc + ww / 2
            if u1 > e:
                WB(zone + "_Brick", facing, base, (e + u1) / 2, (z0 + z1) / 2, u1 - e, WT, z1 - z0)
            for uc in centers:
                steelwin(zone, facing, base, uc, (z0 + z1) / 2, ww, z1 - z0, 3, 2)


def lantern(zone, x, y, z):
    B(zone + "_Iron", (0.9, 0.9, 0.3), (x, y, z - 0.9))
    B(zone + "_Glow", (0.7, 0.7, 1.2), (x, y, z))
    B(zone + "_Brass", (1.0, 1.0, 0.3), (x, y, z + 0.75))


def dome(zone, x, y, z, drop=4.0, r=2.4, top=None):
    """Industrial pendant: steel cord, steel dome shade, warm glowing bulb."""
    top = top if top is not None else z + drop
    C(zone + "_Iron", 0.06, top - z - 1.0, (x, y, (top + z + 1.0) / 2), seg=5)
    C(zone + "_Iron", r, 1.4, (x, y, z + 0.4), seg=12, r2=0.5)
    S(zone + "_Glow", 0.75, (x, y, z - 0.35), seg=8, rings=5)


# ============================================================ SHELL
B("Shell_Stone", (XO * 2 + 1.0, 112.0, 1.6), (0, 0, -1.2))   # top at -0.4 so it never shares a plane with the floor
SIDE_BANDS = [(0, 5, False, "BrickDark"), (5, 14, True, "Brick"), (14, 20, False, "Brick"), (20, 29, True, "Brick"), (29, WH, False, "Brick")]
WIN_U = [-45, -30, -15, 0, 15, 30, 45]
for s, fc in ((-1, "x-"), (1, "x+")):
    pierwall(fc, s * (XO - WT / 2), -YB, YB, SIDE_BANDS, WIN_U, 9.0)
    B("Shell_Iron", (WT + 0.6, 112.0, 0.5), (s * (XO - WT / 2), 0, 14.2))                 # steel string course
    B("Shell_Timber", (WT + 0.6, 112.4, 0.8), (s * (XO - WT / 2), 0, WH + 0.2))           # oak eaves plate
# back wall (service door in the middle)
BACK_U = [-50, -38, -26, 26, 38, 50]
pierwall("y+", YB - WT / 2, -XO, XO, SIDE_BANDS, BACK_U, 9.0)
B("Shell_Iron", (XO * 2 + 0.6, WT + 0.6, 0.5), (0, YB - WT / 2, 14.2))
B("Shell_Timber", (XO * 2 + 0.4, WT + 0.6, 0.8), (0, YB - WT / 2, WH + 0.2))
B("Shell_Iron", (14.0, 0.8, 15.0), (0, YB + 0.5, 7.5))                                      # roller/service door frame
B("Shell_Green", (12.4, 0.5, 13.6), (0, YB + 0.95, 7.0))
for z in (3.5, 7.0, 10.5, 14.0):
    B("Shell_Iron", (12.4, 0.3, 0.3), (0, YB + 1.3, z))
for sx in (-1, 1):
    for sy in (-1, 1):
        B("Shell_Timber", (1.4, 1.4, WH), (sx * (XO + 0.1), sy * (YB + 0.1), WH / 2))     # oak corner posts

# front: brick piers, big steel curtain wall, glazed doors
FY = YF + WT / 2
for x, w in ((-57.0, 6.0), (57.0, 6.0), (-11.0, 6.0), (11.0, 6.0)):
    B("Shell_Brick", (w, WT, 26.0), (x, FY, 13.0))
for s in (-1, 1):
    B("Shell_BrickDark", (40.0, WT + 0.2, 4.5), (s * 34.0, FY, 2.25))                       # plinth under the glass wall
    steelwin("Shell", "y-", FY, s * 34.0, 15.25, 40.0, 21.5, 8, 4, sill=False)
    B("Shell_Stone", (42.0, 1.4, 0.5), (s * 34.0, YF - 0.5, 4.7))                            # stone sill ledge
    for k in range(16):                                                                      # vintage striped awning
        g = "Shell_Green" if k % 2 == 0 else "Shell_Cream"
        xk = s * 34.0 - 20.0 + 1.25 + k * 2.5
        B(g, (2.5, 6.0, 0.3), (xk, YF - 3.0, 17.4), rot=(0.34, 0, 0))
        B(g, (2.5, 0.3, 1.4), (xk, YF - 5.7, 15.9))
B("Shell_Brick", (XO * 2, WT, 6.0), (0, FY, 29.0))                                           # sign band
B("Shell_Stone", (XO * 2 + 0.8, WT + 0.6, 0.6), (0, FY - 0.1, 26.2))
steelwin("Shell", "y-", FY, 0.0, 21.5, 16.0, 9.0, 4, 1, sill=False)                          # transom glass over the doors
B("Shell_Iron", (16.8, 2.0, 0.8), (0, FY - 0.1, 16.6))                                       # door header
for s in (-1, 1):
    B("Shell_Iron", (0.9, 2.0, 17.0), (s * 8.3, FY - 0.1, 8.5))                              # door posts
    B("Shell_Iron", (0.4, 7.4, 15.4), (s * 7.3, YF + 5.0, 7.7))                              # steel door leaves swung in
    B("Shell_Glass", (0.3, 6.6, 13.8), (s * 7.3, YF + 5.0, 7.7))
    B("Shell_Brass", (0.3, 0.3, 4.0), (s * 7.0, YF + 8.2, 7.0))
B("Shell_Stone", (24.0, 4.0, 0.3), (0, YF - 2.0, -0.1))                                     # threshold
# modern canopy over the door + vintage lanterns
B("Shell_Iron", (22.0, 8.0, 0.5), (0, YF - 4.0, 18.6))
B("Shell_Brass", (22.4, 0.4, 0.6), (0, YF - 8.1, 18.6))
B("Shell_Glow", (20.0, 0.6, 0.3), (0, YF - 7.6, 18.2))
for s in (-1, 1):
    B("Shell_Iron", (0.3, 0.3, 18.2), (s * 10.5, YF - 7.6, 9.1))
    B("Shell_Iron", (0.4, 0.4, 10.0), (s * 15.5, YF - 4.0, 5.0))
    B("Shell_Iron", (1.6, 0.3, 0.3), (s * 15.5, YF - 4.0, 9.6))
    lantern("Shell", s * 15.5, YF - 4.0, 10.8)
# sign: dark steel panel, backlit glowing letters, brass trim
B("Shell_Iron", (66.0, 0.6, 5.0), (0, YF - 0.4, 29.0))
B("Shell_Brass", (66.6, 0.5, 0.4), (0, YF - 0.45, 31.7))
B("Shell_Brass", (66.6, 0.5, 0.4), (0, YF - 0.45, 26.3))
TXT("DUSTY FINDS MARKET", (0, YF - 0.9, 29.0), 3.4, "-y", 0.3, glow=True)
# gable: plaster + vertical oak cladding, steel round window
PRISM("Shell_Plaster", [(-XO, WH + 0.5), (XO, WH + 0.5), (0, TOP - 1.2)], YF, YF + WT)
PRISM("Shell_Plaster", [(-XO, WH + 0.5), (XO, WH + 0.5), (0, TOP - 1.2)], YB - WT, YB)
x = -58.0
while x <= 58.0:
    ztop = TOP - 1.4 - (abs(x) / XO) * (TOP - 1.2 - WH - 0.5)
    h = ztop - (WH + 0.5)
    if h > 0.8 and abs(x) > 5.0:
        B("Shell_Oak", (1.4, 0.5, h), (x, YF - 0.2, WH + 0.5 + h / 2))
    x += 2.4
C("Shell_Iron", 4.2, 0.7, (0, YF - 0.6, 36.0), rot=(math.pi / 2, 0, 0), seg=24)
C("Shell_Glass", 3.6, 0.8, (0, YF - 0.65, 36.0), rot=(math.pi / 2, 0, 0), seg=24)
B("Shell_Iron", (0.4, 0.9, 7.6), (0, YF - 0.7, 36.0))
B("Shell_Iron", (7.6, 0.9, 0.4), (0, YF - 0.7, 36.0))
# roof: dark standing-seam slopes with real long skylights, cream ceiling panels, steel trusses
CT, SL0, SL1 = math.cos(TH), 22.0, 42.0
TEND = (XO + 2.0) / CT


def roof_piece(key, s, t0, t1, y0, y1, th, off):
    tm = (t0 + t1) / 2
    x = s * (tm * CT + math.sin(TH) * off)
    z = TOP - tm * math.sin(TH) + CT * off
    B(key, (t1 - t0, y1 - y0, th), (x, (y0 + y1) / 2, z), rot=(0, s * TH, 0))


for s in (-1, 1):
    for (t0, t1) in ((0.0, SL0), (SL1, TEND)):
        roof_piece("Shell_Slate", s, t0, t1, -YB - 2, YB + 2, 0.8, -0.4)
        roof_piece("Shell_Cream", s, t0, t1, -YI, YI, 0.3, -1.4)
    for (y0, y1) in ((-YB - 2, -42.0), (42.0, YB + 2)):
        roof_piece("Shell_Slate", s, SL0, SL1, y0, y1, 0.8, -0.4)
    for (y0, y1) in ((-YI, -42.0), (42.0, YI)):
        roof_piece("Shell_Cream", s, SL0, SL1, y0, y1, 0.3, -1.4)
    roof_piece("Shell_Glass", s, SL0, SL1, -42.0, 42.0, 0.3, -0.5)
    for k in range(9):
        roof_piece("Shell_Iron", s, SL0, SL1, -42.0 + k * 10.5 - 0.2, -42.0 + k * 10.5 + 0.2, 0.7, -0.4)
    for t in (SL0, SL1):
        roof_piece("Shell_Iron", s, t - 0.2, t + 0.2, -42.0, 42.0, 0.7, -0.4)
B("Shell_Iron", (2.8, 114.0, 1.0), (0, 0, TOP + 0.1))                                        # ridge cap
for y in (-48, -32, -16, 0, 16, 32, 48):                                                      # steel trusses
    B("Shell_Iron", (XI * 2, 0.9, 0.9), (0, y, 30.6))
    B("Shell_Iron", (0.8, 0.8, 8.4), (0, y, 34.8))
    for s in (-1, 1):
        B("Shell_Iron", (math.hypot(XI, 8.6), 0.7, 0.7), (s * XI / 2, y, 35.1), rot=(0, s * math.atan2(8.6, XI), 0))
        B("Shell_Iron", (21.5, 0.6, 0.6), (s * 10.0, y, 34.7), rot=(0, s * 0.38, 0))
        B("Shell_Brass", (1.2, 1.2, 0.4), (s * XI, y, 30.6))
for x in (-40.0, -20.0, 20.0, 40.0):
    B("Shell_Timber", (0.8, 112.0, 0.8), (x, 0, 38.9 - abs(x) / XI * 8.6))                   # oak purlins

# ============================================================ HALL (ground)
B("Hall_Concrete", (XI * 2, YI * 2, 0.4), (0, 0, -0.2))                                       # polished concrete floor
for i in range(-5, 6):
    B("Hall_Stone", (0.12, YI * 2, 0.08), (i * 10.0, 0, 0.04))
for j in range(-10, 11):
    B("Hall_Stone", (XI * 2, 0.12, 0.08), (0, j * 5.0, 0.04))
B("Hall_Maroon", (10.0, 45.0, 0.16), (0, -32.5, 0.08))                                        # entrance runner
for s in (-1, 1):
    B("Hall_Brass", (0.3, 45.0, 0.24), (s * 5.1, -32.5, 0.12))
B("Hall_Brass", (10.4, 0.3, 0.24), (0, -10.0, 0.12))
# mezzanine: oak planks on steel I-beams, light cream soffit
B("Upper_Oak", (XI * 2, YI - DY0, 1.0), (0, (YI + DY0) / 2, DECK - 0.5))
B("Hall_Cream", (XI * 2, YI - DY0, 0.3), (0, (YI + DY0) / 2, DECK - 1.1))
B("Hall_Iron", (XI * 2, 0.9, 1.7), (0, DY0 - 0.4, DECK - 1.2))
for y in (-9.0, 0.0, 9.0, 18.0, 27.0, 36.0, 45.0, 52.4):
    B("Hall_Iron", (XI * 2, 0.5, 1.2), (0, y, DECK - 1.6))
    B("Hall_Iron", (XI * 2, 1.6, 0.3), (0, y, DECK - 2.35))
for x in (-19.4, 19.4):
    for y in (-9.2, 21.0, 52.0):
        B("Hall_Stone", (2.6, 2.6, 0.7), (x, y, 0.35))
        C("Hall_Iron", 0.9, DECK - 2.5, (x, y, 0.7 + (DECK - 2.5) / 2), seg=14)
        C("Hall_Brass", 1.15, 0.5, (x, y, 1.2), seg=14)
        C("Hall_Brass", 1.15, 0.5, (x, y, DECK - 2.4), seg=14)
# glass balustrade (steel posts, brass rail), open where the stair lands
SX0 = XI - 10.0
nb = int((SX0 + XI) // 8)
for k in range(nb + 1):
    xk = -XI + k * (SX0 + XI) / nb
    B("Hall_Iron", (0.5, 0.5, 4.4), (xk, DY0 + 0.2, DECK + 2.2))
    if k < nb:
        B("Hall_Glass", ((SX0 + XI) / nb - 0.6, 0.25, 3.5), (xk + (SX0 + XI) / nb / 2, DY0 + 0.2, DECK + 2.2))
B("Hall_Brass", (SX0 + XI, 0.55, 0.5), ((SX0 - XI) / 2, DY0 + 0.2, DECK + 4.3))
B("Hall_Iron", (SX0 + XI, 0.6, 0.3), ((SX0 - XI) / 2, DY0 + 0.2, DECK + 0.4))
# grand oak staircase, east wall (24 treads)
NS, RISE, RUN = 24, DECK / 24, 1.5
SY0 = DY0 - NS * RUN
for i in range(NS):
    top = RISE * (i + 1)
    B("Hall_OakDark", (10.0, RUN, top), (XI - 5.0, SY0 + RUN * i + RUN / 2, top / 2))
    B("Hall_Oak", (10.0, RUN + 0.2, 0.16), (XI - 5.0, SY0 + RUN * i + RUN / 2 - 0.1, top + 0.02))
slope = math.atan2(DECK, NS * RUN)
rl = math.hypot(NS * RUN, DECK)
B("Hall_Brass", (0.5, rl, 0.5), (SX0 + 0.2, (SY0 + DY0) / 2, DECK / 2 + 3.4), rot=(slope, 0, 0))
B("Hall_Iron", (0.4, rl, 0.3), (SX0 + 0.2, (SY0 + DY0) / 2, DECK / 2 + 0.9), rot=(slope, 0, 0))
for i in range(0, NS, 2):
    B("Hall_Iron", (0.3, 0.3, 3.1), (SX0 + 0.2, SY0 + RUN * i + 0.75, RISE * (i + 1) + 1.6))
for y, z in ((SY0 + 0.4, 0.0), (DY0 - 0.4, DECK)):
    B("Hall_Iron", (0.9, 0.9, 5.2), (SX0 + 0.2, y, z + 2.6))
    B("Hall_Brass", (1.2, 1.2, 0.35), (SX0 + 0.2, y, z + 5.3))
# chandeliers (vintage) + pendant domes (modern)
for (x, y, z, r) in ((0, -46, 25.0, 4.4), (0, -31, 24.0, 5.6), (0, -16, 25.0, 4.4)):
    C("Hall_Iron", 0.12, 30.6 - z, (x, y, (30.6 + z) / 2), seg=6)
    for k in range(14):
        a = k * math.tau / 14
        B("Hall_Brass", (1.5 * r / 4.4, 0.35, 0.35), (x + math.cos(a) * r, y + math.sin(a) * r, z), rot=(0, 0, a + math.pi / 2))
        S("Hall_Glow", 0.55, (x + math.cos(a) * r, y + math.sin(a) * r, z + 0.85), seg=8, rings=5)
    S("Hall_Glow", 1.2, (x, y, z - 0.4), seg=8, rings=5)
    C("Hall_Brass", 0.35, 1.2, (x, y, z + 0.5), seg=8)
for y in (-48.0, -32.0, -16.0):
    for x in (-36.0, -20.0, 20.0, 36.0):
        dome("Hall", x, y, 23.0, top=30.6)
# directory board, benches, barrels, crates, plants
B("Hall_Iron", (0.6, 20.0, 13.0), (-XI + 0.4, -34.0, 9.5))
B("Hall_Paper", (0.3, 18.8, 11.8), (-XI + 0.7, -34.0, 9.5))
B("Hall_Brass", (0.4, 18.8, 0.4), (-XI + 0.75, -34.0, 15.5))
TXT("DIRECTORY", (-XI + 1.0, -34.0, 13.6), 1.5, "+x", 0.1)
TXT("GROUND   Supply - Shelves - Skins", (-XI + 1.0, -34.0, 10.4), 0.8, "+x", 0.08)
TXT("UP   Living - Kitchen - Gallery", (-XI + 1.0, -34.0, 8.6), 0.8, "+x", 0.08)
TXT("UP   Paint Bar", (-XI + 1.0, -34.0, 6.8), 0.8, "+x", 0.08)
for y in (-46.0, -22.0):
    B("Hall_Oak", (3.0, 9.0, 0.5), (-XI + 3.0, y, 2.2))
    for dy in (-3.8, 3.8):
        B("Hall_Iron", (2.6, 0.4, 2.2), (-XI + 3.0, y + dy, 1.1))
    B("Hall_Oak", (0.5, 9.0, 2.4), (-XI + 1.7, y, 3.6))
for (x, y) in ((-26.0, -50.0), (-22.5, -49.4), (26.0, -50.0), (22.0, -49.6)):
    C("Hall_Oak", 1.3, 3.2, (x, y, 1.6), seg=10)
    C("Hall_Iron", 1.35, 0.3, (x, y, 0.9), seg=10)
    C("Hall_Iron", 1.35, 0.3, (x, y, 2.3), seg=10)
for (x, y, z, w) in ((-18.0, -50.0, 1.7, 3.4), (-18.0, -50.0, 5.0, 2.8), (30.0, -50.0, 1.7, 3.4)):
    B("Hall_Oak", (w, w, 3.4 if z < 3 else 2.8), (x, y, z))
    B("Hall_Iron", (w + 0.1, w + 0.1, 0.3), (x, y, z))
for (x, y) in ((-56.0, -52.0), (39.0, -52.0), (56.0, -52.0)):
    C("Hall_Terracotta", 1.5, 2.2, (x, y, 1.1), seg=10, r2=1.2)
    S("Hall_Leaf", 2.3, (x, y, 3.9), scale=(1, 1, 1.15), seg=8, rings=6)


# ============================================================ STALLS (ground, under the mezzanine)
def sign_board(zone, cx, y, z, w, body, h=3.2, size=1.5):
    B(zone + "_Iron", (w, 0.6, h), (cx, y, z))
    B(zone + "_Paper", (w - 0.8, 0.3, h - 0.8), (cx, y - 0.25, z))
    B(zone + "_Brass", (w, 0.7, 0.3), (cx, y, z + h / 2))
    TXT(body, (cx, y - 0.5, z), size, "-y", 0.1)
    for s in (-1, 1):
        C(zone + "_Iron", 0.08, DECK - 2.4 - (z + h / 2), (cx + s * (w / 2 - 0.6), y, (DECK - 2.4 + z + h / 2) / 2), seg=6)


def counter(cx, w):
    B("Stalls_Oak", (w, 3.4, 4.2), (cx, -4.6, 2.1))
    B("Stalls_Concrete", (w + 0.6, 4.0, 0.5), (cx, -4.6, 4.45))
    B("Stalls_Iron", (w, 0.4, 0.5), (cx, -6.4, 0.3))
    for k in range(int(w // 3.4)):
        B("Stalls_Timber", (0.25, 0.2, 3.4), (cx - w / 2 + 1.7 + k * 3.4, -6.35, 2.1))


def awning(cx, w, n=12, z=12.2):
    for k in range(n):
        g = "Stalls_Green" if k % 2 == 0 else "Stalls_Cream"
        xk = cx - w / 2 + w / n / 2 + k * w / n
        B(g, (w / n, 5.4, 0.3), (xk, -6.0, z), rot=(0.25, 0, 0))
        B(g, (w / n, 0.3, 1.0), (xk, -8.6, z - 0.75))


def shelf(cx, y, w, h, tiers, depth=1.8, items=None, facing="y"):
    dx, dy = (w, depth) if facing == "y" else (depth, w)
    B("Stalls_Iron", (dx, dy, h), (cx, y, h / 2))
    for t in range(tiers):
        z = 1.2 + t * (h - 1.6) / max(1, tiers - 1)
        B("Stalls_Oak", (dx + (0.0 if facing == "y" else 0.5), dy + (0.5 if facing == "y" else 0.0), 0.3), (cx, y, z))
        if items:
            for k in range(int(w // 3.2)):
                col = items[(k + t) % len(items)]
                off = -w / 2 + 1.7 + k * 3.2
                B("Stalls_" + col, (1.6 if facing == "y" else 1.2, 1.2 if facing == "y" else 1.6, 1.4 + (k % 2) * 0.4),
                  (cx + (off if facing == "y" else 0), y + (off if facing == "x" else 0), z + 1.0))


# --- SUPPLY CRATES (west)
SC = -39.0
B("Stalls_Oak", (37.0, 62.0, 0.2), (SC, 22.0, 0.1))
counter(SC, 20.0)
awning(SC, 22.0)
sign_board("Stalls", SC, -7.0, 10.2, 18.0, "SUPPLY CRATES")
for k in range(5):
    B("Stalls_Oak", (2.4, 2.4, 2.0), (SC - 6.0 + k * 3.0, -4.6, 5.7))
    B("Stalls_Iron", (2.5, 2.5, 0.3), (SC - 6.0 + k * 3.0, -4.6, 5.7))
B("Stalls_Brass", (1.2, 1.0, 0.6), (SC + 8.5, -4.6, 5.0))
C("Stalls_Brass", 0.55, 0.5, (SC + 8.5, -4.6, 5.5), seg=10)
for (x, y) in ((SC - 11.0, 8.0), (SC, 8.0), (SC + 11.0, 8.0), (SC - 11.0, 22.0), (SC, 22.0), (SC + 11.0, 22.0)):
    B("Stalls_Timber", (7.0, 6.4, 0.5), (x, y, 0.25))
    for i in range(6):
        B("Stalls_Oak", (3.0, 3.0, 2.8), (x - 1.7 + (i % 2) * 3.4, y - 1.6 + (i // 2) * 3.2, 1.9))
        B("Stalls_Iron", (3.1, 3.1, 0.3), (x - 1.7 + (i % 2) * 3.4, y - 1.6 + (i // 2) * 3.2, 1.9))
    B("Stalls_Oak", (3.0, 3.0, 2.8), (x - 0.2, y, 4.7))
for y in (12.0, 24.0, 36.0):
    shelf(-XI + 1.6, y, 10.0, 11.0, 4, items=["Oak", "Terracotta", "Mustard"], facing="x")
shelf(SC, 51.5, 28.0, 11.0, 4, items=["Mustard", "Terracotta", "Oak", "Teal"])
for k in range(3):
    dome("Stalls", SC - 12.0 + k * 12.0, 4.0, 10.8, top=DECK - 2.4)
lantern("Stalls", SC - 14.0, -7.0, 9.2)
lantern("Stalls", SC + 14.0, -7.0, 9.2)

# --- SHELVES & PEDESTALS (centre)
FC = 0.0
B("Stalls_Cream", (34.0, 62.0, 0.2), (FC, 22.0, 0.1))
counter(FC, 18.0)
awning(FC, 20.0)
sign_board("Stalls", FC, -7.0, 10.2, 20.0, "SHELVES & PEDESTALS", size=1.3)
for r, y in enumerate((8.0, 18.0)):
    for k in range(5):
        x = -12.0 + k * 6.0
        B("Stalls_Stone", (3.6, 3.6, 3.8), (x, y, 1.9))
        B("Stalls_Brass", (4.0, 4.0, 0.3), (x, y, 3.95))
        S("Stalls_Glow" if (k + r) % 2 == 0 else "Stalls_" + ["Teal", "Terracotta", "Plum"][k % 3], 0.95, (x, y, 5.2), seg=8, rings=5)
for x in (-10.0, 10.0):
    for y in (30.0, 40.0):
        for sx in (-4.0, 4.0):
            B("Stalls_Iron", (0.4, 1.8, 8.0), (x + sx, y, 4.0))
        for t in range(3):
            B("Stalls_Oak", (8.4, 2.0, 0.3), (x, y, 1.2 + t * 3.0))
            for k in range(3):
                B("Stalls_" + ["Terracotta", "Teal", "Mustard", "Plum"][(k + t + int(y)) % 4], (1.8, 1.4, 1.6), (x - 2.6 + k * 2.6, y, 2.1 + t * 3.0))
shelf(FC, 51.5, 30.0, 11.0, 4, items=["Cream", "Teal", "Terracotta"])
for k in range(3):
    dome("Stalls", -10.0 + k * 10.0, 6.0, 10.8, top=DECK - 2.4)
lantern("Stalls", -12.0, -7.0, 9.2)
lantern("Stalls", 12.0, -7.0, 9.2)

# --- SKINS BOOTH (east)
SK = 39.0
B("Stalls_Terracotta", (37.0, 62.0, 0.2), (SK, 22.0, 0.1))
counter(SK, 20.0)
awning(SK, 22.0)
sign_board("Stalls", SK, -7.0, 10.2, 16.0, "SKINS BOOTH")
swatch = ["Terracotta", "Mustard", "Teal", "Plum", "Leaf", "Navy", "Maroon", "Cream"]
B("Stalls_Iron", (30.0, 1.0, 11.0), (SK, 52.4, 5.5))                                           # swatch wall
for r in range(4):
    for k in range(10):
        B("Stalls_" + swatch[(k + r * 3) % 8], (2.4, 0.3, 2.2), (SK - 13.5 + k * 3.0, 51.7, 2.0 + r * 2.6))
for x in (SK - 12.0, SK - 4.0, SK + 4.0, SK + 12.0):                                           # tool-skin tables
    B("Stalls_Oak", (6.0, 3.6, 3.2), (x, 10.0, 1.6))
    B("Stalls_Maroon", (6.2, 3.8, 0.2), (x, 10.0, 3.3))
    B("Stalls_Iron", (0.3, 0.3, 2.0), (x - 1.4, 10.0, 4.3))
    B("Stalls_Brass", (1.8, 0.7, 0.8), (x - 1.4, 10.0, 5.4))
    B("Stalls_Iron", (0.3, 0.3, 2.0), (x + 1.4, 10.0, 4.3))
    B("Stalls_" + swatch[int(x) % 8], (1.4, 0.7, 0.7), (x + 1.4, 10.0, 5.4))
for y in (24.0, 36.0):
    shelf(XI - 1.6, y, 10.0, 11.0, 4, items=swatch, facing="x")
for x in (SK - 12.0, SK, SK + 12.0):                                                            # paint-pot rack
    B("Stalls_Oak", (8.0, 2.0, 5.0), (x, 28.0, 2.5))
    for k in range(4):
        C("Stalls_" + swatch[(k + int(x)) % 8], 0.8, 1.4, (x - 2.7 + k * 1.8, 28.0, 5.7), seg=8)
for k in range(3):
    dome("Stalls", SK - 12.0 + k * 12.0, 4.0, 10.8, top=DECK - 2.4)
lantern("Stalls", SK - 14.0, -7.0, 9.2)
lantern("Stalls", SK + 14.0, -7.0, 9.2)


# ============================================================ UPSTAIRS
def pframe(zone, facing, base, u, v, w, h, color):
    WB(zone + "_Brass", facing, base, u, v, w, 0.3, h)
    WB(zone + "_" + color, facing, base, u, v, w - 0.8, 0.3, h - 0.8, off=0.1)


def sofa(cx, y, w=11.0):
    B("Upper_Mustard", (w, 4.0, 1.8), (cx, y, DECK + 1.0))
    B("Upper_Mustard", (w, 1.1, 3.8), (cx, y - 1.5, DECK + 2.5))
    for s in (-1, 1):
        B("Upper_Mustard", (1.1, 4.0, 3.2), (cx + s * (w / 2 - 0.55), y, DECK + 1.6))


def armchair(x, y, color="Teal"):
    B("Upper_" + color, (3.6, 3.6, 1.6), (x, y, DECK + 0.9))
    B("Upper_" + color, (3.6, 1.0, 3.4), (x, y + 1.3, DECK + 2.4))


def rug(cx, cy, w, d, c1="Maroon", c2="Cream"):
    B("Upper_" + c1, (w, d, 0.12), (cx, cy, DECK + 0.06))
    B("Upper_" + c2, (w - 1.4, d - 1.4, 0.24), (cx, cy, DECK + 0.12))
    B("Upper_" + c1, (w - 2.6, d - 2.6, 0.36), (cx, cy, DECK + 0.18))


def plant(x, y, big=1.0):
    C("Upper_Terracotta", 1.4 * big, 2.0 * big, (x, y, DECK + 1.0 * big), seg=10, r2=1.1 * big)
    S("Upper_Leaf", 2.2 * big, (x, y, DECK + 3.7 * big), scale=(1, 1, 1.2), seg=8, rings=6)


def floorlamp(x, y):
    C("Upper_Iron", 0.12, 8.0, (x, y, DECK + 4.0), seg=6)
    C("Upper_Glow", 1.3, 2.0, (x, y, DECK + 8.4), seg=10, r2=0.9)


def bookshelf_x(x, y, length, h=10.0):                       # against a west/east wall (runs along y)
    B("Upper_Timber", (1.8, length, h), (x, y, DECK + h / 2))
    colors = ["Maroon", "Teal", "Mustard", "Green", "Navy", "Terracotta", "Plum"]
    s = 1 if x < 0 else -1
    for t in range(4):
        B("Upper_Oak", (2.0, length, 0.25), (x + s * 0.1, y, DECK + 0.4 + t * 2.5))
        for k in range(int(length // 1.0) - 1):
            B("Upper_" + colors[(k + t) % 7], (1.0, 0.7, 1.7 + (k % 3) * 0.1), (x + s * 0.35, y - length / 2 + 1 + k * 1.0, DECK + 1.3 + t * 2.5))


# glazed partitions: oak wainscot + plaster + steel-framed glass band
PH = 13.0
def part_x(x, y0, y1):
    L = y1 - y0
    B("Upper_Oak", (1.0, L, 3.6), (x, (y0 + y1) / 2, DECK + 1.8))
    B("Upper_Plaster", (0.8, L, 3.4), (x, (y0 + y1) / 2, DECK + 5.3))
    B("Upper_Glass", (0.4, L, 4.4), (x, (y0 + y1) / 2, DECK + 9.4))
    B("Upper_Iron", (1.0, L, 0.4), (x, (y0 + y1) / 2, DECK + 7.2))
    B("Upper_Iron", (1.0, L, 0.4), (x, (y0 + y1) / 2, DECK + PH))
    for k in range(int(L // 6) + 1):
        B("Upper_Iron", (0.8, 0.4, 5.0), (x, y0 + k * L / max(1, int(L // 6)), DECK + 9.6))


def part_y(y, x0, x1):
    L = x1 - x0
    B("Upper_Oak", (L, 1.0, 3.6), ((x0 + x1) / 2, y, DECK + 1.8))
    B("Upper_Plaster", (L, 0.8, 3.4), ((x0 + x1) / 2, y, DECK + 5.3))
    B("Upper_Glass", (L, 0.4, 4.4), ((x0 + x1) / 2, y, DECK + 9.4))
    B("Upper_Iron", (L, 1.0, 0.4), ((x0 + x1) / 2, y, DECK + 7.2))
    B("Upper_Iron", (L, 1.0, 0.4), ((x0 + x1) / 2, y, DECK + PH))
    for k in range(int(L // 6) + 1):
        B("Upper_Iron", (0.4, 0.8, 5.0), (x0 + k * L / max(1, int(L // 6)), y, DECK + 9.6))


RY = 8.0                                                       # rooms start at y = 8
rooms = ((-XI, -19.4, "COZY LIVING"), (-19.4, 19.4, "KITCHEN NOOK"), (19.4, XI, "GALLERY & STUDY"))
for x1, x2, name in rooms:
    cx = (x1 + x2) / 2
    part_y(RY, x1, cx - 4.5)
    part_y(RY, cx + 4.5, x2)
    B("Upper_Plaster", (9.0, 0.8, 4.0), (cx, RY, DECK + 11.0))                                 # lintel over the doorway
    B("Upper_Iron", (9.6, 1.0, 0.4), (cx, RY, DECK + 9.0))
    B("Upper_Iron", (9.6, 1.0, 0.4), (cx, RY, DECK + PH))
    B("Upper_Iron", (9.0, 0.5, 2.2), (cx, RY - 0.7, DECK + 11.0))
    TXT(name, (cx, RY - 1.05, DECK + 11.0), 1.0 if len(name) < 14 else 0.85, "-y", 0.08, glow=True)
part_x(-19.4, RY, YI)
part_x(19.4, RY, YI)

# --- COZY LIVING (cx -38.8)
cx = -38.8
rug(cx, 26.0, 18.0, 13.0)
sofa(cx, 20.0)
armchair(cx - 10.0, 31.0)
armchair(cx + 10.0, 31.0, "Mustard")
B("Upper_Oak", (6.0, 3.2, 1.7), (cx, 27.0, DECK + 0.85))
B("Upper_Concrete", (5.0, 2.2, 0.15), (cx, 27.0, DECK + 1.8))
B("Upper_Brick", (11.0, 2.4, 10.0), (cx, YI - 1.2, DECK + 5.0))                                # fireplace
B("Upper_Iron", (5.0, 0.7, 4.8), (cx, YI - 2.5, DECK + 2.6))
S("Upper_Glow", 1.4, (cx, YI - 2.7, DECK + 1.6), scale=(1.4, 0.7, 1.0), seg=8, rings=5)
B("Upper_Oak", (12.6, 3.2, 0.6), (cx, YI - 1.6, DECK + 10.4))
bookshelf_x(-XI + 1.0, 36.0, 12.0)
floorlamp(cx - 14.0, 16.0)
plant(cx + 14.5, 14.0)
plant(cx - 14.5, YI - 3.0, 1.2)
pframe("Upper", "x+", -19.4, 40.0, DECK + 8.0, 5.0, 4.0, "Canvas")

# --- KITCHEN NOOK (cx 0)
B("Upper_Oak", (28.0, 3.0, 4.2), (0.0, YI - 1.6, DECK + 2.1))
B("Upper_Concrete", (28.6, 3.4, 0.45), (0.0, YI - 1.6, DECK + 4.4))
B("Upper_Iron", (4.0, 3.2, 4.3), (-8.0, YI - 1.6, DECK + 2.2))                                 # stove
for dx in (-1.0, 1.0):
    for dy in (-0.7, 0.7):
        C("Upper_Brass", 0.55, 0.2, (-8.0 + dx, YI - 1.6 + dy, DECK + 4.55), seg=10)
B("Upper_Iron", (3.6, 2.4, 0.5), (6.0, YI - 1.6, DECK + 4.7))
C("Upper_Brass", 0.14, 1.8, (6.0, YI - 0.4, DECK + 5.8), seg=6)
B("Upper_Fridge", (4.2, 3.6, 9.0), (14.0, YI - 1.9, DECK + 4.5))
B("Upper_Brass", (0.35, 0.35, 2.8), (11.8, YI - 3.8, DECK + 5.5))
for z in (8.8, 11.4):
    B("Upper_Oak", (22.0, 1.3, 0.35), (-3.0, YI - 0.8, DECK + z))
    for k in range(9):
        C("Upper_" + ["Leaf", "Mustard", "Terracotta", "Glass"][k % 4], 0.6, 1.2, (-12.0 + k * 2.4, YI - 0.8, DECK + z + 0.8), seg=8)
rug(0.0, 28.0, 13.0, 13.0, "Brick", "Cream")
C("Upper_Oak", 3.8, 0.45, (0.0, 28.0, DECK + 3.4), seg=18)
C("Upper_Iron", 0.55, 3.4, (0.0, 28.0, DECK + 1.7), seg=8)
for a in range(4):
    C("Upper_Terracotta", 1.0, 2.2, (math.cos(a * math.pi / 2 + 0.78) * 5.6, 28.0 + math.sin(a * math.pi / 2 + 0.78) * 5.6, DECK + 1.1), seg=10)
dome("Upper", 0.0, 28.0, DECK + 11.0, top=30.6)
dome("Upper", -9.0, 40.0, DECK + 11.0, top=30.6)
dome("Upper", 9.0, 40.0, DECK + 11.0, top=30.6)
plant(-16.0, 14.0)

# --- GALLERY & STUDY (cx 38.8)
cx = 38.8
for y in (14.0, 24.0, 34.0, 44.0):
    pframe("Upper", "x-", XI, y, DECK + 7.8, 5.4, 4.4, ["Canvas", "Maroon", "Mustard", "Teal"][int(y) % 4])
for x in (26.0, 38.8, 51.0):
    pframe("Upper", "y+", YI, x, DECK + 8.0, 5.6, 4.6, ["Plum", "Leaf", "Terracotta"][int(x) % 3])
rug(cx, 21.0, 24.0, 7.0, "Maroon", "Cream")
for x in (cx - 8.0, cx, cx + 8.0):
    B("Upper_Stone", (3.2, 3.2, 3.6), (x, 21.0, DECK + 1.8))
    B("Upper_Brass", (3.6, 3.6, 0.3), (x, 21.0, DECK + 3.75))
    S("Upper_" + ["Glow", "Terracotta", "Teal"][int(x) % 3], 1.0, (x, 21.0, DECK + 5.1), seg=8, rings=5)
B("Upper_Oak", (8.0, 3.6, 0.6), (cx - 8.0, 42.0, DECK + 3.4))                                  # study desk
for s in (-1, 1):
    B("Upper_Iron", (0.5, 3.2, 3.4), (cx - 8.0 + s * 3.5, 42.0, DECK + 1.7))
B("Upper_Teal", (2.8, 2.8, 0.6), (cx - 8.0, 38.4, DECK + 2.4))
B("Upper_Teal", (2.8, 0.6, 3.0), (cx - 8.0, 37.0, DECK + 3.9))
C("Upper_Iron", 0.2, 2.4, (cx - 8.0, 38.4, DECK + 1.2), seg=6)
B("Upper_Maroon", (1.8, 1.4, 0.6), (cx - 5.5, 42.0, DECK + 3.9))
B("Upper_Navy", (1.8, 1.4, 0.6), (cx - 5.5, 42.0, DECK + 4.5))
C("Upper_Iron", 0.5, 0.25, (cx - 10.5, 42.0, DECK + 3.85), seg=8)
C("Upper_Glow", 1.0, 1.1, (cx - 10.5, 42.0, DECK + 5.4), seg=8, r2=0.55)
S("Upper_Terracotta", 1.4, (cx + 12.5, 42.0, DECK + 4.4), seg=10, rings=7)                    # globe
C("Upper_Brass", 0.18, 2.4, (cx + 12.5, 42.0, DECK + 1.8), seg=6)
B("Upper_Brass", (2.4, 2.4, 0.35), (cx + 12.5, 42.0, DECK + 0.4))
bookshelf_x(XI - 1.0, 33.0, 10.0)
dome("Upper", cx, 21.0, DECK + 11.0, top=30.6)
plant(cx + 14.5, 12.0)

# --- PAINT BAR (front strip, west)
B("Upper_Oak", (22.0, 3.0, 4.0), (-36.0, -1.0, DECK + 2.0))
B("Upper_Concrete", (22.6, 3.6, 0.45), (-36.0, -1.0, DECK + 4.2))
for x in (-44.0, -40.0, -36.0, -32.0, -28.0):
    C("Upper_Iron", 0.2, 2.6, (x, -4.2, DECK + 1.3), seg=6)
    C("Upper_Terracotta", 1.0, 0.45, (x, -4.2, DECK + 2.7), seg=10)
for t, z in enumerate((3.4, 6.2, 9.0)):
    B("Upper_Iron", (26.0, 1.4, 0.3), (-36.0, 6.0, DECK + z))
    for k in range(11):
        C("Upper_" + ["Terracotta", "Mustard", "Teal", "Plum", "Leaf", "Navy", "Maroon", "Cream", "Brass"][(k + t * 2) % 9],
          0.65, 1.4, (-47.5 + k * 2.3, 5.8, DECK + z + 0.85), seg=8)
for k in range(5):
    B("Upper_" + ["Terracotta", "Teal", "Mustard", "Plum", "Leaf"][k], (1.0, 1.0, 0.3), (-44.0 + k * 1.4, -1.0, DECK + 4.6))
B("Upper_Iron", (13.0, 0.6, 2.8), (-36.0, 0.0, DECK + 12.0))
B("Upper_Paper", (12.2, 0.3, 2.0), (-36.0, -0.3, DECK + 12.0))
TXT("PAINT BAR", (-36.0, -0.6, DECK + 12.0), 1.2, "-y", 0.08)
for s in (-1, 1):
    C("Upper_Iron", 0.08, 2.2, (-36.0 + s * 5.5, 0.0, DECK + 14.2), seg=6)
for x in (-42.0, -30.0):
    dome("Upper", x, -1.0, DECK + 10.5, top=30.6)
for x in (22.0, 38.8, 50.0):
    pass

# ============================================================ BUILD OBJECTS
objs = []
for key, bm in G.items():
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    mesh = bpy.data.meshes.new(key + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(key, mesh)
    bpy.context.collection.objects.link(o)
    colname = key.split("_", 1)[1]
    mat = bpy.data.materials.new(key + "_mat")
    mat.diffuse_color = c.hex_to_rgba(COL[colname])
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = c.hex_to_rgba(COL[colname])
    bsdf.inputs["Roughness"].default_value = 0.85
    if colname == "Glow":
        bsdf.inputs["Emission Color"].default_value = c.hex_to_rgba(COL[colname])
        bsdf.inputs["Emission Strength"].default_value = 2.0
    if colname == "Brass":
        bsdf.inputs["Metallic"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.45
    if colname == "Iron":
        bsdf.inputs["Metallic"].default_value = 0.5
        bsdf.inputs["Roughness"].default_value = 0.55
    if colname == "Glass":
        bsdf.inputs["Alpha"].default_value = 0.35
        bsdf.inputs["Roughness"].default_value = 0.1
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    o.data.materials.append(mat)
    objs.append(o)


def text_group(lst, name, colname, glow):
    if not lst:
        return
    for t in lst:
        t.data.materials.clear()
    o = c.join(lst, name)
    mat = bpy.data.materials.new(name + "_mat")
    mat.diffuse_color = c.hex_to_rgba(COL[colname])
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = c.hex_to_rgba(COL[colname])
    b.inputs["Roughness"].default_value = 0.8
    if glow:
        b.inputs["Emission Color"].default_value = c.hex_to_rgba(COL[colname])
        b.inputs["Emission Strength"].default_value = 2.0
    o.data.materials.append(mat)
    objs.append(o)


text_group(TEXTS, "Signs_Letters", "Letters", False)
text_group(GLOWTEXTS, "Signs_Glow", "Glow", True)

tris = 0
worst = 0
for o in objs:
    o.data.calc_loop_triangles()
    n = len(o.data.loop_triangles)
    tris += n
    worst = max(worst, n)
    if n > 12000:
        print(f"BIG {o.name} {n}")
print("TOTAL", tris, "tris,", len(objs), "objects, biggest", worst)
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "WarehouseMarket.glb"), objs)

# ============================================================ PREVIEWS
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_shadows = True
sc.display.shading.shadow_intensity = 0.3
sc.render.resolution_x, sc.render.resolution_y = 1400, 800
w = bpy.data.worlds.new("W")
w.color = (0.86, 0.88, 0.9)
sc.world = w
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cam)
sc.camera = cam


def shot(name, loc, target, lens, hide=()):
    cam.data.lens = lens
    cam.data.clip_end = 1000
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    for o in objs:
        o.hide_render = any(o.name.startswith(h) for h in hide)
    sc.render.filepath = os.path.join(c.OUT_PREVIEWS, name)
    bpy.ops.render.render(write_still=True)


shot("WarehouseMarket_front.png", (95, -190, 70), (0, 0, 16), 40)
shot("WarehouseMarket_cutaway.png", (0, -165, 150), (0, 5, 8), 38,
     hide=("Shell_Slate", "Shell_Glass", "Shell_Brick", "Shell_Cream", "Shell_Plaster", "Shell_Oak", "Shell_Green", "Shell_Iron", "Shell_Timber", "Shell_BrickDark", "Shell_Stone", "Shell_Brass", "Signs_Glow"))
shot("WarehouseMarket_back.png", (-110, 160, 80), (0, 0, 14), 40)
print("done")
