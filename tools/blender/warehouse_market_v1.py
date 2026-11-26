"""Dusty Finds Warehouse Market, vintage placeholder (Blender 5.x, headless). Replaces Dwayne's modern Warehouse look.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/warehouse_market.py
Writes assets/models/WarehouseMarket.glb and assets/previews/WarehouseMarket_*.png (git-ignored).

This is the PLAN as blocky placeholder geometry (docs/10 + the Figma "Warehouse Market" preview), not final art:
  GROUND   double-height entrance hall (runner rug, grand staircase on the east wall, chandeliers, directory board)
           + three stalls under the deck: Supply Crates (west), Shelves & Pedestals (centre), Skins Booth (east)
  UPSTAIRS wooden deck over the back two thirds: Cozy Living, Kitchen Nook, Gallery & Study rooms + the Paint Bar
  SHELL    red-brick walls on a dark plinth, cream gable, slate gable roof, timber trusses, striped awnings, lanterns
Studs, 1 unit = 1 stud, z up, floor top z = 0, facade faces -Y, centred on x = 0, y = 0 (footprint 86 x 82, ridge 33.6).
Every object is "<Zone>_<Colour>" (Shell_Brick, Hall_Oak, Stalls_Timber, Upper_Plaster ...), one MeshPart each, with the
colour baked in the material, so Studio can also re-tint by the colour suffix. No textures (placeholder look).
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

COL = {  # vintage: brick, cream plaster, oak, brass, bottle green, slate
    "Brick": "A0573D", "BrickDark": "74392B", "Plaster": "EBDBB6", "Timber": "5B3A24", "Oak": "B58A57",
    "OakDark": "8A6238", "Slate": "4A5056", "Brass": "C9A24A", "Green": "3F6046", "Cream": "F3E7CB",
    "Maroon": "7B2D33", "Glass": "A9C4BA", "Stone": "B8AD99", "Iron": "2C2C2E", "Mustard": "D6A33E",
    "Teal": "3F7070", "Plum": "6E4A7E", "Terracotta": "C86A4A", "Leaf": "5F8A4E", "Paper": "F1E8D0",
    "Letters": "2A1D14", "Glow": "FFD98A", "Canvas": "6C8E8C", "Fridge": "CFE0D4", "Navy": "34476E",
}
c.PALETTE.update(COL)

G = {}  # "Zone_Colour" -> bmesh


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
    """Prism along Y from a polygon in the XZ plane (gable ends)."""
    bm = bm_for(key)
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((a[i], a[j], b[j], b[i]))


TEXTS = []


def TXT(body, loc, size, facing="-y", extrude=0.12, color_off=0.0):
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
    TEXTS.append(bpy.context.active_object)


# ------------------------------------------------------------------ constants
XO, XI = 43.0, 41.4      # outer / inner half width
YF, YB = -41.0, 41.0     # front / back outer faces
WH = 26.0                # wall height (eaves)
APEX = 33.6
DECK = 14.0              # deck top
DECK_Y0 = -8.0
TH = math.atan2(APEX - WH, XO)  # roof pitch angle


def window(zone, cx, cy, cz, w, h, facing):
    """Framed window on a wall: timber frame, pale glass, cross mullions, stone sill. facing x+ x- y+ y-."""
    if facing in ("x+", "x-"):
        s = 1 if facing == "x+" else -1
        x = cx
        B(zone + "_Timber", (0.4, w + 1.2, h + 1.2), (x, cy, cz))
        B(zone + "_Glass", (0.3, w, h), (x + s * 0.2, cy, cz))
        B(zone + "_Timber", (0.4, 0.4, h + 0.2), (x + s * 0.4, cy, cz))
        B(zone + "_Timber", (0.4, w + 0.2, 0.4), (x + s * 0.4, cy, cz))
        B(zone + "_Stone", (0.9, w + 2.0, 0.5), (x + s * 0.1, cy, cz - h / 2 - 0.6))
    else:
        s = 1 if facing == "y+" else -1
        y = cy
        B(zone + "_Timber", (w + 1.2, 0.4, h + 1.2), (cx, y, cz))
        B(zone + "_Glass", (w, 0.3, h), (cx, y + s * 0.2, cz))
        B(zone + "_Timber", (0.4, 0.4, h + 0.2), (cx, y + s * 0.4, cz))
        B(zone + "_Timber", (w + 0.2, 0.4, 0.4), (cx, y + s * 0.4, cz))
        B(zone + "_Stone", (w + 2.0, 0.9, 0.5), (cx, y + s * 0.1, cz - h / 2 - 0.6))


def lantern(zone, x, y, z):
    """Glowing lantern (brass cap, glow body, iron base)."""
    B(zone + "_Iron", (0.9, 0.9, 0.3), (x, y, z - 0.9))
    B(zone + "_Glow", (0.7, 0.7, 1.2), (x, y, z))
    B(zone + "_Brass", (1.0, 1.0, 0.3), (x, y, z + 0.75))


# ============================================================ SHELL
B("Shell_Stone", (XO * 2 + 1.0, 83.6, 1.6), (0, 0, -0.8))                       # foundation, a little proud of the walls
for s in (-1, 1):
    B("Shell_Brick", (1.6, 82.0, WH), (s * (XO - 0.8), 0, WH / 2))                # side walls
    B("Shell_BrickDark", (1.9, 82.4, 3.0), (s * (XO - 0.85), 0, 1.5))            # dark plinth band
    B("Shell_Timber", (2.4, 83.0, 0.9), (s * (XO - 0.8), 0, WH + 0.45))         # eaves plate
    B("Shell_Stone", (2.0, 82.4, 0.4), (s * (XO - 0.8), 0, 11.8))               # stone string course between floors
    for y in (-32, -16, 0, 16, 32):                                                # ground + upper windows
        for z in (8.0, 20.0):
            window("Shell", s * (XO + 0.05), y, z, 6.0, 7.0 if z < 10 else 6.0, "x+" if s > 0 else "x-")
B("Shell_Brick", (XO * 2, 1.6, WH), (0, YB - 0.8, WH / 2))                       # back wall
B("Shell_BrickDark", (XO * 2, 1.9, 3.0), (0, YB - 0.85, 1.5))
B("Shell_Timber", (XO * 2 + 0.4, 2.4, 0.9), (0, YB - 0.8, WH + 0.45))
for x in (-20, 20):
    window("Shell", x, YB + 0.05, 20.0, 6.0, 6.0, "y+")
B("Shell_Timber", (11.0, 0.8, 13.6), (0, YB + 0.4, 6.8))                         # rear service door frame
B("Shell_Green", (9.4, 0.5, 12.6), (0, YB + 0.75, 6.4))
for z in (3, 6.4, 9.8):
    B("Shell_Iron", (9.4, 0.3, 0.4), (0, YB + 1.05, z))
B("Shell_Brass", (0.6, 0.6, 0.6), (3.4, YB + 1.1, 6.4))
for s in (-1, 1):                                                                  # corner posts
    for t in (-1, 1):
        B("Shell_Timber", (1.2, 1.2, WH), (s * (XO + 0.1), t * (YB + 0.1), WH / 2))

# front wall (door in the middle, two shop windows, brick piers)
FY = YF + 0.8
for x, w in ((-41.0, 4.0), (-9.0, 4.0), (9.0, 4.0), (41.0, 4.0)):
    B("Shell_Brick", (w, 1.6, 15.0), (x, FY, 7.5))
for s in (-1, 1):
    B("Shell_BrickDark", (28.0, 1.8, 4.0), (s * 25.0, FY, 2.0))                  # plinth under the shop windows
    B("Shell_Glass", (28.0, 0.3, 10.6), (s * 25.0, YF + 0.1, 9.7))
    for k in range(7):
        B("Shell_Timber", (0.4, 0.5, 10.8), (s * 25.0 - 14 + k * 28 / 6, YF - 0.05, 9.7))
    B("Shell_Timber", (28.0, 0.5, 0.4), (s * 25.0, YF - 0.05, 11.0))
    B("Shell_Timber", (28.4, 0.8, 0.6), (s * 25.0, YF - 0.1, 4.2))
    # striped awning over each window
    for k in range(12):
        g = "Shell_Green" if k % 2 == 0 else "Shell_Cream"
        B(g, (28 / 12, 5.2, 0.3), (s * 25.0 - 14 + 28 / 24 + k * 28 / 12, YF - 2.4, 16.1), rot=(0.34, 0, 0))
        B(g, (28 / 12, 0.3, 1.2), (s * 25.0 - 14 + 28 / 24 + k * 28 / 12, YF - 4.7, 14.7))
B("Shell_Brick", (XO * 2, 1.6, 11.0), (0, FY, 20.5))                             # band over doors and windows
B("Shell_Stone", (XO * 2 + 0.6, 2.0, 0.6), (0, FY - 0.1, 15.3))                  # string course
for s in (-1, 1):
    B("Shell_Timber", (1.2, 2.0, 15.0), (s * 7.6, FY - 0.1, 7.5))                 # door posts
    B("Shell_Green", (0.5, 6.6, 13.4), (s * 6.9, YF + 4.3, 6.7))                 # double doors swung open inwards
    B("Shell_Brass", (0.3, 0.5, 0.5), (s * 6.55, YF + 6.8, 6.4))
B("Shell_Timber", (16.4, 2.0, 1.4), (0, FY - 0.1, 14.5))                          # door lintel
B("Shell_Timber", (4.0, 2.0, 0.8), (0, FY - 0.1, 15.5))                           # stepped arch crown
B("Shell_Stone", (18.0, 3.0, 0.3), (0, YF - 1.6, -0.15))                          # threshold slab
# sign board
B("Shell_Plaster", (36.0, 0.6, 5.6), (0, YF - 0.3, 20.7))
B("Shell_Brass", (36.6, 0.5, 0.4), (0, YF - 0.35, 23.7))
B("Shell_Brass", (36.6, 0.5, 0.4), (0, YF - 0.35, 17.7))
TXT("DUSTY FINDS MARKET", (0, YF - 0.9, 20.7), 2.3, "-y", 0.18)
# gable + round window
PRISM("Shell_Plaster", [(-XO, WH + 0.9), (XO, WH + 0.9), (0, APEX + 0.3)], YF, YF + 1.6)
PRISM("Shell_Plaster", [(-XO, WH + 0.9), (XO, WH + 0.9), (0, APEX + 0.3)], YB - 1.6, YB)
C("Shell_Timber", 2.5, 0.4, (0, YF - 0.1, 30.0), rot=(math.pi / 2, 0, 0), seg=20)
C("Shell_Glass", 2.0, 0.5, (0, YF - 0.15, 30.0), rot=(math.pi / 2, 0, 0), seg=20)
B("Shell_Timber", (0.3, 0.5, 4.2), (0, YF - 0.2, 30.0))
B("Shell_Timber", (4.2, 0.5, 0.3), (0, YF - 0.2, 30.0))
# street lanterns beside the door
for s in (-1, 1):
    B("Shell_Iron", (0.4, 0.4, 9.0), (s * 12.5, YF - 1.0, 4.5))
    B("Shell_Iron", (1.6, 0.3, 0.3), (s * 12.5, YF - 1.0, 8.6))
    lantern("Shell", s * 12.5, YF - 1.0, 9.8)
# roof: two slate slopes, ridge cap, skylights
RL = math.hypot(XO + 1.5, APEX - WH)
for s in (-1, 1):
    B("Shell_Slate", (RL, 84.0, 0.8), (s * 22.3, 0, 29.95), rot=(0, s * TH, 0))
    for y in (-20, 20):
        B("Shell_Glass", (10.0, 16.0, 0.4), (s * 22.0, y, 30.6 + math.tan(TH) * 0), rot=(0, s * TH, 0))
B("Shell_Timber", (2.4, 84.4, 0.9), (0, 0, APEX + 0.1))
# interior trusses (tie beam, king post, rafters, struts)
for y in (-32, -16, 0, 16, 32):
    B("Shell_Timber", (XI * 2, 1.0, 1.0), (0, y, 25.4))
    B("Shell_Timber", (0.9, 0.9, 7.4), (0, y, 29.2))
    for s in (-1, 1):
        B("Shell_Timber", (math.hypot(XI, APEX - 26.3), 0.7, 0.7), (s * XI / 2, y, 29.5), rot=(0, s * TH, 0))
        B("Shell_Timber", (10.3, 0.7, 0.7), (s * 5.0, y, 27.0), rot=(0, s * 0.245, 0))
B("Shell_Timber", (0.8, 82.0, 0.8), (0, 0, 32.2))                                 # ridge beam inside

# ============================================================ HALL (ground)
B("Hall_Oak", (XI * 2, 78.8, 0.4), (0, 0, -0.2))
for i in range(-6, 7):
    B("Hall_OakDark", (0.14, 78.8, 0.04), (i * 6.4, 0, 0.02))
B("Hall_Maroon", (8.0, 32.0, 0.1), (0, -23.4, 0.05))                              # entrance runner
for s in (-1, 1):
    B("Hall_Brass", (0.3, 32.0, 0.12), (s * 4.1, -23.4, 0.06))
B("Hall_Cream", (9.0, 0.5, 0.12), (0, -7.6, 0.06))
# deck over the back two thirds
B("Upper_Oak", (XI * 2, 47.4, 1.0), (0, DECK_Y0 + 23.7, DECK - 0.5))
B("Upper_OakDark", (XI * 2, 0.4, 1.2), (0, DECK_Y0 - 0.2, DECK - 0.6))
for y in (-7.6, 0.0, 8.0, 16.0, 24.0, 32.0, 38.6):
    B("Hall_Timber", (XI * 2, 0.8, 1.2), (0, y, DECK - 1.6))
for x in (-15.0, 15.0):
    for y in (-7.2, 16.0, 38.6):
        B("Hall_Stone", (2.0, 2.0, 0.6), (x, y, 0.3))
        B("Hall_Timber", (1.4, 1.4, 12.4), (x, y, 6.8))
        B("Hall_Brass", (1.8, 1.8, 0.4), (x, y, 12.8))
# deck balustrade (broken where the staircase lands)
for z, h in ((DECK + 3.4, 0.6), (DECK + 0.5, 0.5)):
    B("Hall_Timber", (74.0, 0.6, h), (-4.0, DECK_Y0 + 0.4, z))
for i in range(34):
    B("Hall_Timber", (0.3, 0.3, 3.0), (-40.6 + i * 2.2, DECK_Y0 + 0.4, DECK + 1.9))
for x in (-41.0, -20.0, 0.0, 20.0, 32.4):
    B("Hall_Timber", (0.9, 0.9, 4.2), (x, DECK_Y0 + 0.4, DECK + 2.1))
    B("Hall_Brass", (1.1, 1.1, 0.3), (x, DECK_Y0 + 0.4, DECK + 4.3))
# grand staircase on the east wall (solid oak treads, 20 x 0.7 rise)
for i in range(20):
    top = 0.7 * (i + 1)
    B("Hall_OakDark", (8.0, 1.5, top), (37.4, -38.0 + 1.5 * i + 0.75, top / 2))
    B("Hall_Oak", (8.0, 0.3, 0.12), (37.4, -38.0 + 1.5 * i + 0.15, top + 0.04))
rl = math.hypot(30.0, 14.0)
B("Hall_Timber", (0.5, rl, 0.6), (32.6, -23.0, 7.0 + 3.4), rot=(math.atan2(14, 30), 0, 0))
B("Hall_Timber", (0.5, rl, 0.5), (32.6, -23.0, 7.0 + 0.8), rot=(math.atan2(14, 30), 0, 0))
for i in range(0, 20, 2):
    zt = 0.7 * (i + 1)
    B("Hall_Timber", (0.3, 0.3, 3.1), (32.6, -38.0 + 1.5 * i + 0.75, zt + 1.5))
for y in (-38.0, -8.4):
    z = 0.0 if y < -20 else 14.0
    B("Hall_Timber", (1.0, 1.0, 5.0), (32.6, y, z + 2.5))
    B("Hall_Brass", (1.3, 1.3, 0.35), (32.6, y, z + 5.1))
# chandeliers
for (x, y, z, r) in ((0, -34, 20.0, 3.6), (0, -22, 19.0, 4.6), (0, -10, 20.0, 3.6)):
    C("Hall_Iron", 0.12, 25.4 - z, (x, y, (25.4 + z) / 2), seg=6)
    for k in range(12):
        a = k * math.tau / 12
        B("Hall_Brass", (1.3 * r / 3.6, 0.35, 0.35), (x + math.cos(a) * r, y + math.sin(a) * r, z), rot=(0, 0, a + math.pi / 2))
        S("Hall_Glow", 0.5, (x + math.cos(a) * r, y + math.sin(a) * r, z + 0.8), seg=8, rings=5)
    S("Hall_Glow", 1.0, (x, y, z - 0.4), seg=8, rings=5)
    C("Hall_Brass", 0.3, 1.0, (x, y, z + 0.4), seg=8)
# directory board on the west wall + benches, barrels, crates, plants
B("Hall_Timber", (0.5, 16.0, 11.0), (-41.1, -26.0, 8.6))
B("Hall_Paper", (0.3, 14.8, 9.8), (-40.8, -26.0, 8.6))
B("Hall_Brass", (0.4, 14.8, 0.4), (-40.75, -26.0, 13.7))
TXT("DIRECTORY", (-40.5, -26.0, 12.2), 1.1, "+x", 0.1)
TXT("GROUND   Supply - Shelves - Skins", (-40.5, -26.0, 9.6), 0.62, "+x", 0.08)
TXT("UP  Living - Kitchen - Gallery", (-40.5, -26.0, 8.0), 0.62, "+x", 0.08)
TXT("UP  Paint Bar", (-40.5, -26.0, 6.4), 0.62, "+x", 0.08)
for y in (-30.0, -16.0):
    B("Hall_Oak", (2.4, 7.0, 0.5), (-37.5, y, 2.0))
    B("Hall_OakDark", (2.4, 0.5, 2.0), (-37.5, y - 3.0, 1.0))
    B("Hall_OakDark", (2.4, 0.5, 2.0), (-37.5, y + 3.0, 1.0))
    B("Hall_Oak", (0.5, 7.0, 2.0), (-38.8, y, 3.2))
for (x, y) in ((-20.0, -38.0), (-17.2, -37.4), (19.0, -38.0)):
    C("Hall_Oak", 1.1, 2.8, (x, y, 1.4), seg=10)
    C("Hall_Iron", 1.15, 0.25, (x, y, 0.8), seg=10)
    C("Hall_Iron", 1.15, 0.25, (x, y, 2.0), seg=10)
for (x, y, z, w) in ((-14.0, -37.0, 1.4, 2.8), (-14.0, -37.0, 4.2, 2.4), (23.0, -37.5, 1.4, 2.8)):
    B("Hall_Oak", (w, w, 2.8 if z < 3 else 2.4), (x, y, z))
    B("Hall_Iron", (w + 0.1, w + 0.1, 0.25), (x, y, z))
for (x, y) in ((-39.5, -38.5), (28.5, -38.0)):
    C("Hall_Terracotta", 1.3, 1.8, (x, y, 0.9), seg=10, r2=1.0)
    S("Hall_Leaf", 1.9, (x, y, 3.2), scale=(1, 1, 1.15), seg=8, rings=6)

# ============================================================ STALLS (ground, under the deck)
def sign_board(zone, cx, y, z, w, body, h=2.8, size=1.3, chain_to=DECK - 1.2):
    B(zone + "_Timber", (w, 0.6, h), (cx, y, z))
    B(zone + "_Paper", (w - 0.8, 0.3, h - 0.8), (cx, y - 0.25, z))
    B(zone + "_Brass", (w, 0.7, 0.25), (cx, y, z + h / 2))
    TXT(body, (cx, y - 0.5, z), size, "-y", 0.1)
    for s in (-1, 1):
        C(zone + "_Iron", 0.08, chain_to - (z + h / 2), (cx + s * (w / 2 - 0.5), y, (chain_to + z + h / 2) / 2), seg=6)


def stall_counter(cx, w, top="Stall_OakDark"):
    B("Stalls_Oak", (w, 3.0, 4.0), (cx, -3.0, 2.0))
    B("Stalls_OakDark", (w + 0.6, 3.6, 0.4), (cx, -3.0, 4.2))
    B("Stalls_Timber", (w, 0.4, 0.5), (cx, -4.6, 0.3))
    for k in range(int(w // 3)):
        B("Stalls_Timber", (0.25, 0.2, 3.2), (cx - w / 2 + 1.5 + k * 3.0, -4.52, 2.0))


def awning(cx, w, y=-4.0, z=11.0, n=8):
    for k in range(n):
        g = "Stalls_Green" if k % 2 == 0 else "Stalls_Cream"
        B(g, (w / n, 5.0, 0.3), (cx - w / 2 + w / n / 2 + k * w / n, y, z), rot=(0.25, 0, 0))
        B(g, (w / n, 0.3, 1.0), (cx - w / 2 + w / n / 2 + k * w / n, y - 2.4, z - 0.7))


def shelf_unit(cx, y, w, h, tiers, depth=1.6, key="Stalls_Oak", wall_axis="y"):
    B("Stalls_Timber", (w, depth, h), (cx, y, h / 2))
    for t in range(tiers):
        z = 1.2 + t * (h - 1.4) / max(1, tiers - 1)
        B(key, (w - 0.4, depth + 0.5, 0.3), (cx, y - 0.3, z))


# --- SUPPLY CRATES (west, cx -28.5)
stall_counter(-28.5, 14.0)
awning(-28.5, 15.0)
sign_board("Stalls", -28.5, -5.4, 9.2, 13.0, "SUPPLY CRATES")
B("Stalls_Stone", (24.0, 40.0, 0.12), (-28.5, 17.0, 0.06))
B("Stalls_Brass", (1.0, 0.8, 0.5), (-33.0, -3.0, 4.8))                          # service bell
C("Stalls_Brass", 0.45, 0.4, (-33.0, -3.0, 5.2), seg=10)
for k in range(4):                                                                 # crates on the counter
    B("Stalls_Oak", (2.0, 2.0, 1.6), (-24.0 + k * 2.2, -3.0, 5.2))
for (x, y, n) in ((-34.0, 6.0, 3), (-28.0, 6.0, 2), (-22.0, 6.0, 3)):
    B("Stalls_Timber", (5.6, 5.0, 0.5), (x, y, 0.25))
    for i in range(n):
        B("Stalls_Oak", (2.6, 2.6, 2.4), (x - 1.4 + (i % 2) * 2.8, y + (i // 2) * 2.7 - 1.0, 1.7))
        B("Stalls_Iron", (2.7, 2.7, 0.3), (x - 1.4 + (i % 2) * 2.8, y + (i // 2) * 2.7 - 1.0, 1.7))
for y in (18.0, 28.0):
    shelf_unit(-40.0, y, 1.6, 10.0, 4)
    for t in range(4):
        for k in range(2):
            B("Stalls_Oak", (1.4, 3.2, 1.8), (-39.6, y - 2.2 + k * 4.4, 1.2 + t * 2.87 + 1.1))
B("Stalls_Timber", (22.0, 1.2, 9.0), (-28.5, 37.6, 4.5))                          # back wall rack
for t in range(3):
    B("Stalls_Oak", (22.0, 1.8, 0.3), (-28.5, 36.8, 1.5 + t * 2.8))
    for k in range(5):
        B("Stalls_Mustard" if (k + t) % 2 else "Stalls_Terracotta", (2.8, 1.5, 1.8), (-36.4 + k * 4.2, 36.8, 2.5 + t * 2.8))
lantern("Stalls", -36.0, -4.0, 8.4)
lantern("Stalls", -21.0, -4.0, 8.4)

# --- SHELVES & PEDESTALS (centre)
stall_counter(0.0, 12.0)
awning(0.0, 13.0, n=8)
sign_board("Stalls", 0.0, -5.4, 9.2, 15.0, "SHELVES & PEDESTALS", size=1.15)
B("Stalls_Cream", (26.0, 40.0, 0.12), (0, 17.0, 0.06))
for x in (-9.0, -3.0, 3.0, 9.0):                                                   # pedestals
    B("Stalls_Stone", (3.2, 3.2, 3.6), (x, 6.0, 1.8))
    B("Stalls_Brass", (3.6, 3.6, 0.3), (x, 6.0, 3.75))
    S("Stalls_Glow" if x in (-3.0, 3.0) else "Stalls_Teal", 0.8, (x, 6.0, 4.9), seg=8, rings=5)
for x in (-8.0, 8.0):                                                              # freestanding shelves
    for y in (16.0, 26.0):
        B("Stalls_Timber", (0.4, 1.6, 7.0), (x - 3.4, y, 3.5))
        B("Stalls_Timber", (0.4, 1.6, 7.0), (x + 3.4, y, 3.5))
        for t in range(3):
            B("Stalls_Oak", (7.2, 1.8, 0.3), (x, y, 1.2 + t * 2.7))
            B("Stalls_Terracotta" if t % 2 == 0 else "Stalls_Teal", (1.4, 1.2, 1.3), (x - 2.0, y, 2.0 + t * 2.7))
            B("Stalls_Mustard", (1.0, 1.0, 1.3), (x + 0.5, y, 2.0 + t * 2.7))
            B("Stalls_Plum", (1.2, 1.2, 1.0), (x + 2.4, y, 1.9 + t * 2.7))
B("Stalls_Timber", (24.0, 1.2, 9.0), (0, 37.6, 4.5))
for t in range(3):
    B("Stalls_Oak", (24.0, 1.8, 0.3), (0, 36.8, 1.5 + t * 2.8))
lantern("Stalls", -10.0, -4.0, 8.4)
lantern("Stalls", 10.0, -4.0, 8.4)

# --- SKINS BOOTH (east, cx 28.5)
stall_counter(28.5, 14.0)
awning(28.5, 15.0)
sign_board("Stalls", 28.5, -5.4, 9.2, 12.0, "SKINS BOOTH")
B("Stalls_Terracotta", (24.0, 40.0, 0.12), (28.5, 17.0, 0.06))
B("Stalls_Timber", (22.0, 1.0, 9.6), (28.5, 37.7, 4.8))                           # swatch wall
swatch = ["Terracotta", "Mustard", "Teal", "Plum", "Leaf", "Navy", "Maroon", "Cream"]
for r in range(3):
    for k in range(8):
        B("Stalls_" + swatch[(k + r * 3) % 8], (2.2, 0.3, 2.2), (28.5 - 8.8 + k * 2.5, 37.0, 2.0 + r * 2.9))
for x in (21.0, 28.5, 36.0):                                                        # tool-skin display tables
    B("Stalls_Oak", (5.0, 3.0, 3.0), (x, 8.0, 1.5))
    B("Stalls_Maroon", (5.2, 3.2, 0.2), (x, 8.0, 3.1))
    B("Stalls_Iron", (0.3, 0.3, 1.7), (x - 1.2, 8.0, 4.0))
    B("Stalls_Brass", (1.5, 0.6, 0.7), (x - 1.2, 8.0, 5.0))
    B("Stalls_Iron", (0.3, 0.3, 1.7), (x + 1.2, 8.0, 4.0))
    B("Stalls_Teal", (1.2, 0.6, 0.6), (x + 1.2, 8.0, 5.0))
for y in (18.0, 28.0):
    for t in range(4):
        B("Stalls_Oak", (1.6, 6.0, 0.3), (40.2, y, 1.2 + t * 2.6))
    B("Stalls_Timber", (1.0, 6.0, 9.0), (40.9, y, 4.5))
    for k in range(4):
        B("Stalls_" + swatch[(k + int(y)) % 8], (0.9, 1.6, 1.2), (40.0, y - 1.8 + (k % 2) * 3.6, 2.0 + (k // 2) * 2.6))
lantern("Stalls", 20.0, -4.0, 8.4)
lantern("Stalls", 36.0, -4.0, 8.4)

# ============================================================ UPSTAIRS (deck z = 14)
def room_walls():
    for (x1, x2, name) in ((-XI, -14.0, "COZY LIVING"), (-14.0, 14.0, "KITCHEN NOOK"), (14.0, XI, "GALLERY & STUDY")):
        cx = (x1 + x2) / 2
        for xa, xb in ((x1, cx - 3.5), (cx + 3.5, x2)):
            B("Upper_Plaster", (xb - xa, 0.8, 10.0), ((xa + xb) / 2, 6.0, DECK + 5.0))
            B("Upper_Oak", (xb - xa, 1.0, 3.6), ((xa + xb) / 2, 5.9, DECK + 1.8))
            B("Upper_Timber", (xb - xa, 1.2, 0.5), ((xa + xb) / 2, 6.0, DECK + 10.2))
        B("Upper_Plaster", (7.0, 0.8, 3.0), (cx, 6.0, DECK + 8.5))               # lintel over the doorway
        B("Upper_Timber", (7.6, 1.2, 0.5), (cx, 6.0, DECK + 7.1))
        B("Upper_Oak", (10.0, 0.5, 2.0), (cx, 5.4, DECK + 8.7))
        B("Upper_Brass", (10.4, 0.6, 0.25), (cx, 5.4, DECK + 9.7))
        TXT(name, (cx, 5.05, DECK + 8.7), 0.95 if len(name) < 14 else 0.8, "-y", 0.08)
    for x in (-14.0, 14.0):
        B("Upper_Plaster", (0.8, 33.4, 10.0), (x, 22.7, DECK + 5.0))
        B("Upper_Oak", (1.0, 33.4, 3.6), (x, 22.7, DECK + 1.8))
        B("Upper_Timber", (1.2, 33.4, 0.5), (x, 22.7, DECK + 10.2))


room_walls()

# --- COZY LIVING (cx -27.7)
cx = -27.7
B("Upper_Maroon", (15.0, 11.0, 0.1), (cx, 22.0, DECK + 0.05))
B("Upper_Cream", (13.4, 9.4, 0.12), (cx, 22.0, DECK + 0.07))
B("Upper_Maroon", (12.6, 8.6, 0.14), (cx, 22.0, DECK + 0.08))
B("Upper_Mustard", (9.4, 3.6, 1.6), (cx, 17.0, DECK + 0.9))                      # sofa
B("Upper_Mustard", (9.4, 1.0, 3.4), (cx, 15.4, DECK + 2.3))
for s in (-1, 1):
    B("Upper_Mustard", (1.0, 3.6, 2.8), (cx + s * 4.2, 17.0, DECK + 1.5))
B("Upper_Oak", (5.0, 2.8, 1.5), (cx, 23.0, DECK + 0.75))                         # coffee table
B("Upper_Brass", (4.0, 1.8, 0.1), (cx, 23.0, DECK + 1.55))
for x in (cx - 8.5, cx + 8.5):                                                    # armchairs
    B("Upper_Teal", (3.2, 3.2, 1.4), (x, 27.0, DECK + 0.8))
    B("Upper_Teal", (3.2, 0.9, 3.0), (x, 28.7, DECK + 2.2))
B("Upper_Brick", (9.0, 2.0, 8.0), (cx, 38.4, DECK + 4.0))                         # fireplace on the back wall
B("Upper_Iron", (4.0, 0.6, 3.8), (cx, 37.3, DECK + 2.1))
S("Upper_Glow", 1.1, (cx, 37.0, DECK + 1.2), scale=(1.3, 0.7, 1.0), seg=8, rings=5)
B("Upper_Oak", (10.6, 2.8, 0.5), (cx, 38.0, DECK + 8.2))
B("Upper_Timber", (1.6, 9.0, 9.6), (-40.4, 30.0, DECK + 4.8))                     # bookshelf, west wall
colors = ["Maroon", "Teal", "Mustard", "Green", "Navy", "Terracotta", "Plum"]
for t in range(4):
    B("Upper_Oak", (1.8, 9.0, 0.25), (-40.3, 30.0, DECK + 0.4 + t * 2.4))
    for k in range(9):
        B("Upper_" + colors[(k + t) % 7], (1.0, 0.7, 1.7 + (k % 3) * 0.1), (-40.2, 26.2 + k * 0.95, DECK + 1.3 + t * 2.4))
C("Upper_Iron", 0.12, 7.2, (-36.0, 19.0, DECK + 3.6), seg=6)                       # floor lamp
C("Upper_Glow", 1.1, 1.8, (-36.0, 19.0, DECK + 7.6), seg=10, r2=0.8)
C("Upper_Terracotta", 1.2, 1.8, (cx + 11.0, 33.0, DECK + 0.9), seg=10, r2=0.9)  # plant
S("Upper_Leaf", 1.9, (cx + 11.0, 33.0, DECK + 3.4), scale=(1, 1, 1.2), seg=8, rings=6)
B("Upper_Brass", (0.3, 4.2, 3.4), (-13.4, 30.0, DECK + 6.0))                       # picture frame
B("Upper_Canvas", (0.3, 3.4, 2.6), (-13.3, 30.0, DECK + 6.0))

# --- KITCHEN NOOK (cx 0)
B("Upper_Oak", (22.0, 2.4, 3.6), (0.0, 38.0, DECK + 1.8))
B("Upper_Stone", (22.4, 2.8, 0.35), (0.0, 38.0, DECK + 3.8))
B("Upper_Iron", (3.6, 2.6, 3.7), (-6.0, 38.0, DECK + 1.9))                       # stove with burners
for dx in (-0.8, 0.8):
    C("Upper_Brass", 0.5, 0.2, (-6.0 + dx, 38.0, DECK + 3.95), seg=10)
B("Upper_Iron", (3.0, 2.0, 0.5), (4.5, 38.0, DECK + 4.1))                         # sink basin
C("Upper_Brass", 0.12, 1.4, (4.5, 38.9, DECK + 5.0), seg=6)
B("Upper_Fridge", (3.6, 3.2, 7.8), (9.2, 38.0, DECK + 3.9))                       # vintage fridge
B("Upper_Brass", (0.3, 0.3, 2.4), (7.2, 36.3, DECK + 4.8))
for z in (7.4, 9.6):
    B("Upper_Oak", (18.0, 1.1, 0.3), (-1.0, 39.0, DECK + z))
    for k in range(7):
        C("Upper_" + ["Leaf", "Mustard", "Terracotta", "Glass"][k % 4], 0.55, 1.1, (-8.5 + k * 2.4, 39.0, DECK + z + 0.7), seg=8)
B("Upper_Cream", (10.0, 10.0, 0.1), (0.0, 24.0, DECK + 0.05))                    # checker rug
for i in range(5):
    for j in range(5):
        if (i + j) % 2 == 0:
            B("Upper_Brick", (2.0, 2.0, 0.12), (-4.0 + i * 2.0, 20.0 + j * 2.0, DECK + 0.09))
C("Upper_Oak", 3.2, 0.4, (0.0, 24.0, DECK + 3.2), seg=16)                          # round table
C("Upper_OakDark", 0.5, 3.2, (0.0, 24.0, DECK + 1.6), seg=8)
for a in (0, 1, 2, 3):
    C("Upper_Terracotta", 0.9, 2.0, (math.cos(a * math.pi / 2) * 4.8, 24.0 + math.sin(a * math.pi / 2) * 4.8, DECK + 1.0), seg=10)
C("Upper_Iron", 0.08, 6.0, (0.0, 24.0, DECK + 15.0 - 3.0 * 0), seg=6)             # pendant lamp chain
C("Upper_Glow", 1.6, 1.3, (0.0, 24.0, DECK + 7.8), seg=10, r2=0.7)

# --- GALLERY & STUDY (cx 27.7)
cx = 27.7
for y in (12.0, 20.0, 28.0, 35.0):                                                  # framed pictures on the east wall
    B("Upper_Brass", (0.3, 4.6, 3.8), (XI - 0.1, y, DECK + 6.3))
    B("Upper_" + ["Canvas", "Maroon", "Mustard", "Teal"][int(y) % 4], (0.3, 3.8, 3.0), (XI - 0.25, y, DECK + 6.3))
for x in (20.0, 27.7, 35.0):                                                         # frames on the back wall
    B("Upper_Brass", (4.6, 0.3, 3.8), (x, 41.0 - 1.6, DECK + 6.8))
    B("Upper_" + ["Plum", "Leaf", "Terracotta"][int(x) % 3], (3.8, 0.3, 3.0), (x, 41.0 - 1.75, DECK + 6.8))
for x in (21.0, 27.7, 34.4):                                                         # display pedestals
    B("Upper_Stone", (2.8, 2.8, 3.2), (x, 15.0, DECK + 1.6))
    B("Upper_Brass", (3.2, 3.2, 0.3), (x, 15.0, DECK + 3.35))
    S("Upper_" + ["Glow", "Terracotta", "Teal"][int(x) % 3], 0.9, (x, 15.0, DECK + 4.6), seg=8, rings=5)
B("Upper_Maroon", (11.0, 6.0, 0.1), (27.7, 15.0, DECK + 0.05))
B("Upper_Oak", (7.0, 3.2, 0.5), (22.0, 36.0, DECK + 3.0))                          # study desk
for s in (-1, 1):
    B("Upper_OakDark", (0.5, 2.8, 3.0), (22.0 + s * 3.0, 36.0, DECK + 1.5))
B("Upper_Teal", (2.4, 2.4, 0.5), (22.0, 32.6, DECK + 2.1))                         # chair
B("Upper_Teal", (2.4, 0.5, 2.6), (22.0, 31.6, DECK + 3.4))
C("Upper_OakDark", 0.2, 2.1, (22.0, 32.6, DECK + 1.0), seg=6)
B("Upper_Maroon", (1.6, 1.2, 0.5), (24.6, 36.0, DECK + 3.4))                       # books on the desk
B("Upper_Navy", (1.6, 1.2, 0.5), (24.6, 36.0, DECK + 3.9))
C("Upper_Brass", 0.4, 0.2, (19.8, 36.0, DECK + 3.35), seg=8)                        # desk lamp
C("Upper_Glow", 0.9, 1.0, (19.8, 36.0, DECK + 5.0), seg=8, r2=0.5)
C("Upper_Iron", 0.1, 1.4, (19.8, 36.0, DECK + 4.0), seg=6)
S("Upper_Terracotta", 1.2, (38.0, 36.0, DECK + 3.6), seg=10, rings=7)                # globe
C("Upper_Brass", 0.15, 2.0, (38.0, 36.0, DECK + 1.5), seg=6)
B("Upper_Brass", (2.0, 2.0, 0.3), (38.0, 36.0, DECK + 0.4))

# --- PAINT BAR (front strip, west)
B("Upper_Oak", (18.0, 2.4, 3.6), (-28.0, -1.0, DECK + 1.8))
B("Upper_OakDark", (18.6, 3.0, 0.4), (-28.0, -1.0, DECK + 3.8))
for x in (-32.0, -28.0, -24.0, -20.0):
    C("Upper_Terracotta", 0.9, 2.0, (x, -4.0, DECK + 1.0), seg=10)
    C("Upper_Oak", 1.1, 0.3, (x, -4.0, DECK + 2.1), seg=10)
for t, z in enumerate((3.2, 5.8, 8.4)):
    B("Upper_OakDark", (22.0, 1.4, 0.3), (-28.0, 5.0, DECK + z))
    for k in range(9):
        C("Upper_" + ["Terracotta", "Mustard", "Teal", "Plum", "Leaf", "Navy", "Maroon", "Cream", "Brass"][(k + t * 2) % 9],
          0.6, 1.3, (-37.6 + k * 2.4, 5.0, DECK + z + 0.8), seg=8)
for k in range(4):                                                                   # palette + brush on the bar
    B("Upper_" + ["Terracotta", "Teal", "Mustard", "Plum"][k], (0.9, 0.9, 0.3), (-34.0 + k * 1.2, -1.0, DECK + 4.15))
B("Upper_Timber", (11.0, 0.6, 2.4), (-28.0, 0.0, DECK + 10.0))                        # hanging sign
B("Upper_Paper", (10.2, 0.3, 1.8), (-28.0, -0.3, DECK + 10.0))
TXT("PAINT BAR", (-28.0, -0.6, DECK + 10.0), 1.0, "-y", 0.08)
for s in (-1, 1):
    C("Upper_Iron", 0.08, 1.3, (-28.0 + s * 4.5, 0.0, DECK + 11.9), seg=6)

# ============================================================ BUILD OBJECTS
def hexcol(name):
    return COL[name]


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
    mat.diffuse_color = c.hex_to_rgba(hexcol(colname))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = c.hex_to_rgba(hexcol(colname))
    bsdf.inputs["Roughness"].default_value = 0.85
    if colname == "Glow":
        bsdf.inputs["Emission Color"].default_value = c.hex_to_rgba(hexcol(colname))
        bsdf.inputs["Emission Strength"].default_value = 2.0
    if colname in ("Brass",):
        bsdf.inputs["Metallic"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.45
    o.data.materials.append(mat)
    objs.append(o)

if TEXTS:
    for t in TEXTS:
        t.data.materials.clear()
    letters = c.join(TEXTS, "Signs_Letters")
    mat = bpy.data.materials.new("Signs_Letters_mat")
    mat.diffuse_color = c.hex_to_rgba(COL["Letters"])
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = c.hex_to_rgba(COL["Letters"])
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    letters.data.materials.append(mat)
    objs.append(letters)

tris = 0
for o in objs:
    o.data.calc_loop_triangles()
    n = len(o.data.loop_triangles)
    tris += n
    print(f"{o.name:22s} {n:6d} tris")
print("TOTAL", tris, "tris,", len(objs), "objects")

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "WarehouseMarket.glb"), objs)

# ============================================================ PREVIEWS (flat workbench renders)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_shadows = True
sc.display.shading.shadow_intensity = 0.35
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


shot("WarehouseMarket_front.png", (70, -150, 55), (0, 0, 14), 40)
shot("WarehouseMarket_cutaway.png", (0, -125, 110), (0, 5, 8), 38, hide=("Shell_Slate", "Shell_Glass", "Shell_Brick", "Shell_Timber", "Shell_Plaster", "Shell_Green", "Shell_Cream", "Shell_BrickDark"))
shot("WarehouseMarket_hall.png", (-8, -38, 8), (14, 10, 10), 22, hide=("Shell_Slate", "Shell_Plaster"))
print("done")
