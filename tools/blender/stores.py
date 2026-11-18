"""Dusty Finds town stores: Kainan ni Bida (fast food) and Sulit Mart (grocery), walk-in (Blender 5.x, headless).
Fictional brands only (no real logos, names or mascots). Scenery: no gameplay parts.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/stores.py
Writes assets/models/Stores.glb and assets/previews/Stores_*.png (git-ignored).

Real studs. Each store faces -Y, stands on z = 0 (floor top), centred on x = 0 (Kainan) and x = 70 (Sulit), so Studio
splits them by prefix Kainan_<Group> / Sulit_<Group>.
  Kainan ni Bida  40 wide x 34 deep, glass shop front with an 8-wide open doorway, dining hall (tables, stools, counter,
                  lit menu boards), closed upper floor with windows, flat roof with parapet, pylon sign.
  Sulit Mart      50 wide x 40 deep x 14, glass front with a 10-wide open doorway and canopy, 4 grocery aisles, 3 checkouts,
                  cart corral, big fascia sign.
Walls are simple boxes (no booleans) so the doorways are always clean openings.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"cream": "F6EEDC", "stone": "CFC5B0", "glass": "4A7088", "iron": "2E3236", "wood": "8A5A34",
                  "red": "C8262B", "yellow": "F2B632", "green": "2E8B57", "white": "F7F7F2", "floor": "E9E1D2",
                  "warm": "FFE2B0", "leaf": "3F7F3A", "blue": "2F6DB5", "orange": "E9822E", "purple": "7B4C9A",
                  "plaster": "F3EEE4", "teal": "1F7A7A", "tin": "9AA3A8", "brown": "6E4A2E", "bread": "D9A066"})
c.reset_scene()
G = {}
CUR = ["Kainan"]
OX = [0.0]


def add(g, o):
    o.location.x += OX[0]
    G.setdefault((CUR[0], g), []).append(o)
    return o


def box(g, size, loc, rot=None):
    o = c.box("b", size, loc)
    if rot:
        o.rotation_euler = rot
    return add(g, o)


def cyl(g, r, h, loc, verts=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    return add(g, bpy.context.active_object)


def text(g, body, loc, size, rot=(math.pi / 2, 0, 0), extrude=0.08, spacing=1.1):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.active_object
    t.data.body = body
    t.data.size = size
    t.data.extrude = extrude
    t.data.align_x = "CENTER"
    t.data.space_character = spacing
    bpy.ops.object.convert(target="MESH")
    return add(g, bpy.context.active_object)


def blob(r, loc, s=0.25):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    o = bpy.context.active_object
    for v in o.data.vertices:
        n = v.co.normalized()
        v.co = n * r * (1 + s * math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]))
    return o


def shell(W, D, H, wall_g, T=1.0, door_w=8.0, door_h=8.0, front_g="Frame", glass_to=None):
    """Hollow box: back/side walls, roof slab, and a front of piers + glass + an open doorway in the middle."""
    FY = -D / 2
    box(wall_g, (W, T, H), (0, D / 2 - T / 2, H / 2))                       # back
    for s in (-1, 1):
        box(wall_g, (T, D, H), (s * (W / 2 - T / 2), 0, H / 2))           # sides
    box(wall_g, (W, D, T), (0, 0, H + T / 2))                              # roof slab (ceiling)
    glass_to = glass_to or H - 2.5
    # front: corner piers, kickplate, glass panels, mullions, transom band above the glass
    for s in (-1, 1):
        box(front_g, (1.6, T + 0.4, H), (s * (W / 2 - 0.8), FY + T / 2, H / 2))
        span0, span1 = door_w / 2, W / 2 - 1.6
        box(front_g, (span1 - span0, T, 0.8), (s * (span0 + span1) / 2, FY + T / 2, 0.4))
        box("Glass", (span1 - span0, 0.15, glass_to - 0.8), (s * (span0 + span1) / 2, FY + T / 2, 0.8 + (glass_to - 0.8) / 2))
        n = max(1, int((span1 - span0) / 4))
        for k in range(n + 1):
            x = s * (span0 + k * (span1 - span0) / n)
            box(front_g, (0.35, T + 0.1, glass_to), (x, FY + T / 2, glass_to / 2))
    box(front_g, (W, T, H - glass_to), (0, FY + T / 2, glass_to + (H - glass_to) / 2))   # band above the glass and door
    box(front_g, (door_w + 0.8, T + 0.3, 0.4), (0, FY + T / 2, door_h + 0.2))            # door head
    box("Floor", (W - 2 * T, D - 2 * T, 0.1), (0, 0, 0.05))
    box("Stone", (W + 1.2, 3.0, 0.3), (0, FY - 1.4, -0.15 + 0.15))                     # front pavement apron
    return FY


# ===================== KAINAN NI BIDA =====================
CUR[0], OX[0] = "Kainan", 0.0
W, D, H1, H2 = 40.0, 34.0, 10.0, 18.0
FY = shell(W, D, H1, "Walls", door_w=8.0, door_h=8.0, front_g="Red")
# upper floor (closed, windows) sitting on the ground-floor roof slab
box("Walls", (W, D, H2 - H1 - 1.0), (0, 0, H1 + 1.0 + (H2 - H1 - 1.0) / 2))
for x in (-14.0, -7.0, 0.0, 7.0, 14.0):
    box("Glass", (4.2, 0.15, 3.6), (x, FY - 0.05, H1 + 3.0 + 1.8))
    box("Cream", (4.9, 0.4, 0.4), (x, FY - 0.15, H1 + 2.8))
    box("Cream", (4.9, 0.4, 0.4), (x, FY - 0.15, H1 + 6.8))
for s in (-1, 1):
    for y in (-8.0, 0.0, 8.0):
        box("Glass", (0.15, 4.0, 3.4), (s * (W / 2 + 0.05), y, H1 + 4.6))
box("Cream", (W + 1.2, D + 1.2, 0.8), (0, 0, H2 + 0.1))                  # cornice
for s in (-1, 1):                                                       # parapet
    box("Walls", (W, 0.8, 2.0), (0, s * (D / 2 - 0.4), H2 + 1.5))
    box("Walls", (0.8, D, 2.0), (s * (W / 2 - 0.4), 0, H2 + 1.5))
# big red fascia with the name, yellow trim lines
box("Red", (W + 0.6, 1.2, 3.0), (0, FY - 0.4, H1 - 0.8))
box("Yellow", (W + 0.8, 1.3, 0.35), (0, FY - 0.45, H1 + 0.75))
box("Yellow", (W + 0.8, 1.3, 0.35), (0, FY - 0.45, H1 - 2.35))
text("Letters", "KAINAN NI BIDA", (0, FY - 1.1, H1 - 1.55), 1.9)
# emblem: yellow disc with a red spoon and fork (generic, no mascot)
cyl("Yellow", 1.9, 0.5, (W / 2 - 4.0, FY - 1.2, H1 + 4.8), 24, (math.pi / 2, 0, 0))
box("Red", (0.35, 0.3, 2.6), (W / 2 - 4.6, FY - 1.5, H1 + 4.6))
box("Red", (0.35, 0.3, 2.6), (W / 2 - 3.4, FY - 1.5, H1 + 4.6))
add("Red", c.sphere("spoon", 0.55, (W / 2 - 4.6, FY - 1.5, H1 + 6.0), segments=10, rings=6))
for k in range(3):
    box("Red", (0.12, 0.3, 0.8), (W / 2 - 3.75 + k * 0.17, FY - 1.5, H1 + 6.2))
# awning strips over the side glass
for s in (-1, 1):
    for k in range(6):
        g = "Red" if k % 2 == 0 else "Cream"
        box(g, (2.55, 3.0, 0.2), (s * (5.6 + k * 2.5), FY - 1.4, H1 - 2.9), rot=(math.radians(-16), 0, 0))
# pylon sign on the right
cyl("Iron", 0.5, 22.0, (W / 2 + 3.0, FY - 3.0, 11.0), 10)
box("Red", (7.0, 1.2, 4.2), (W / 2 + 3.0, FY - 3.0, 23.0))
box("Yellow", (7.4, 1.3, 0.35), (W / 2 + 3.0, FY - 3.0, 25.2))
text("Letters", "BIDA", (W / 2 + 3.0, FY - 3.7, 22.3), 1.7)
# interior: counter with lit menu boards, tables and stools
box("Red", (22.0, 2.4, 3.4), (0, D / 2 - 8.0, 1.7))
box("Cream", (22.6, 2.8, 0.3), (0, D / 2 - 8.0, 3.55))
box("Iron", (24.0, 0.5, 5.0), (0, D / 2 - 1.3, 6.5))
for k in range(4):
    box("Lamp", (5.0, 0.3, 3.4), (-8.25 + k * 5.5, D / 2 - 1.6, 6.5))
box("Iron", (14.0, 3.0, 4.0), (0, D / 2 - 3.0, 2.0))                    # kitchen line behind the counter
for (tx_, ty_) in ((-12.0, -9.0), (-4.0, -9.0), (4.0, -9.0), (12.0, -9.0), (-12.0, -1.0), (-4.0, -1.0), (4.0, -1.0), (12.0, -1.0)):
    cyl("Cream", 1.5, 0.25, (tx_, ty_, 2.8), 16)
    cyl("Iron", 0.2, 2.7, (tx_, ty_, 1.4), 8)
    for (ox, oy) in ((2.4, 0), (-2.4, 0), (0, 2.4), (0, -2.4)):
        cyl("Red", 0.6, 0.3, (tx_ + ox, ty_ + oy, 1.8), 10)
        cyl("Iron", 0.12, 1.7, (tx_ + ox, ty_ + oy, 0.85), 6)
for x in (-12.0, 0.0, 12.0):
    box("Lamp", (4.0, 2.0, 0.2), (x, -4.0, H1 - 0.15))
# planters at the entrance
for s in (-1, 1):
    box("Red", (2.0, 2.0, 1.4), (s * 6.0, FY - 2.0, 0.7))
    add("Leaves", blob(1.1, (s * 6.0, FY - 2.0, 2.2)))

# ===================== SULIT MART =====================
CUR[0], OX[0] = "Sulit", 70.0
W, D, H = 50.0, 40.0, 14.0
FY = shell(W, D, H, "Walls", door_w=10.0, door_h=9.0, front_g="Green", glass_to=10.0)
box("Green", (W + 0.6, 1.4, 4.0), (0, FY - 0.5, H - 1.8))
box("White", (W + 0.8, 1.5, 0.4), (0, FY - 0.55, H + 0.35))
box("White", (W + 0.8, 1.5, 0.4), (0, FY - 0.55, H - 3.95))
text("Letters", "SULIT MART", (0, FY - 1.3, H - 3.0), 2.6, spacing=1.15)
cyl("Yellow", 1.6, 0.5, (-W / 2 + 4.0, FY - 1.3, H - 1.8), 20, (math.pi / 2, 0, 0))   # price-tag style emblem
text("Green", "%", (-W / 2 + 4.0, FY - 1.7, H - 2.6), 1.8)
box("Cream", (W + 1.4, D + 1.4, 0.8), (0, 0, H + 1.4))
for s in (-1, 1):
    box("Walls", (W, 0.8, 1.8), (0, s * (D / 2 - 0.4), H + 2.6))
    box("Walls", (0.8, D, 1.8), (s * (W / 2 - 0.4), 0, H + 2.6))
# entrance canopy on two posts
box("Green", (16.0, 6.0, 0.5), (0, FY - 3.0, 9.6))
box("White", (16.4, 0.3, 0.8), (0, FY - 6.0, 9.4))
for s in (-1, 1):
    cyl("Iron", 0.3, 9.4, (s * 7.4, FY - 5.6, 4.7), 10)
# cart corral and carts outside on the left
box("Iron", (0.2, 7.0, 1.2), (-14.0, FY - 4.0, 1.0))
box("Iron", (0.2, 7.0, 1.2), (-17.0, FY - 4.0, 1.0))
for k in range(4):
    box("Iron", (2.2, 1.4, 1.4), (-15.5, FY - 1.6 - k * 1.6, 1.3))
    box("Green", (2.0, 0.2, 1.0), (-15.5, FY - 2.25 - k * 1.6, 1.4))
# interior: 4 double-sided aisles with product rows in 5 colours, checkouts by the door, ceiling light panels
COLS = ["Red", "Blue", "Yellow", "Orange", "Purple"]
for i, x in enumerate((-16.0, -6.0, 6.0, 16.0)):
    box("White", (3.0, 22.0, 6.0), (x, 6.0, 3.0))
    box("Green", (3.2, 22.2, 0.6), (x, 6.0, 6.3))
    for lvl, z in enumerate((1.2, 2.9, 4.6)):
        for j in range(5):
            g = COLS[(i + lvl + j) % 5]
            for sd in (-1, 1):
                box(g, (0.8, 4.0, 1.2), (x + sd * 1.8, -2.4 + j * 4.2, z + 0.6))
    box("Green", (4.0, 0.3, 1.4), (x, -5.4, 8.0))                     # aisle number boards
    cyl("Iron", 0.05, 4.0, (x, -5.4, 10.6), 6)
# fresh produce tables along the back wall
for k in range(4):
    box("Wood", (8.0, 3.0, 2.6), (-16.5 + k * 11.0, D / 2 - 3.0, 1.3))
    for j in range(5):
        add(COLS[(k + j) % 5] if j % 2 else "Leaves", blob(0.6, (-19.5 + k * 11.0 + j * 1.5, D / 2 - 3.0, 3.0)))
# checkouts
for x in (-18.0, -12.0, 12.0, 18.0):
    box("White", (2.0, 6.0, 3.0), (x, -12.0, 1.5))
    box("Iron", (2.2, 2.0, 0.3), (x, -14.0, 3.15))
    box("Green", (0.2, 0.2, 2.5), (x, -9.5, 4.2))
    box("Lamp", (0.8, 0.2, 0.8), (x, -9.5, 5.8))
for x in (-16.0, -6.0, 6.0, 16.0):
    for y in (-8.0, 4.0, 14.0):
        box("Lamp", (3.0, 6.0, 0.2), (x, y, H - 0.15))

# ===================== SARI-SARI STORE =====================
# corner store in a two-storey house: barred store window with a serving hatch, hanging snack strips, tin awning, bench
CUR[0], OX[0] = "SariSari", 140.0
W, D, H1, H2 = 24.0, 18.0, 9.0, 17.0
FY = shell(W, D, H1, "Walls", door_w=4.0, door_h=7.5, front_g="Wood", glass_to=6.5)
box("Walls", (W, D, H2 - H1 - 1.0), (0, 0, H1 + 1.0 + (H2 - H1 - 1.0) / 2))
box("Wood", (W + 1.4, D + 1.4, 0.5), (0, 0, H1 + 0.6))                 # wooden floor band (overhang line)
for x in (-7.0, 0.0, 7.0):
    box("Glass", (3.6, 0.15, 4.0), (x, FY - 0.05, H1 + 2.6 + 2.0))
    for k in range(1, 4):
        box("Wood", (0.12, 0.2, 4.0), (x - 1.8 + k * 0.9, FY - 0.12, H1 + 4.6))
    for s in (-1, 1):
        box("Teal", (1.7, 0.15, 4.0), (x + s * 2.7, FY - 0.12, H1 + 4.6))
for s in (-1, 1):                                                       # iron grille over both store windows
    for k in range(14):
        box("Iron", (0.1, 0.1, 5.6), (s * (2.6 + k * 0.6), FY - 0.35, 3.6))
    box("Iron", (8.6, 0.12, 0.12), (s * 6.5, FY - 0.35, 6.4))
    box("Iron", (8.6, 0.12, 0.12), (s * 6.5, FY - 0.35, 0.9))
    box("Wood", (3.0, 1.2, 0.2), (s * 6.5, FY - 0.8, 3.4))              # serving hatch ledge
for k in range(10):                                                     # hanging snack strips
    g = ("Red", "Yellow", "Orange", "Blue", "Purple")[k % 5]
    for j in range(3):
        box(g, (0.7, 0.12, 0.9), (-9.0 + k * 2.0, FY - 1.3, 6.3 - j * 1.0))
box("Iron", (W - 2.0, 0.1, 0.1), (0, FY - 1.3, 6.9))
box("Tin", (W + 1.0, 3.2, 0.2), (0, FY - 1.6, 7.6), rot=(math.radians(-14), 0, 0))   # corrugated tin awning
for k in range(13):
    box("Tin", (0.2, 3.2, 0.15), (-W / 2 + k * 2.0, FY - 1.6, 7.75), rot=(math.radians(-14), 0, 0))
box("Wood", (10.0, 0.4, 1.8), (0, FY - 0.3, H1 - 0.4))                 # painted sign board
box("Yellow", (10.4, 0.3, 2.1), (0, FY - 0.2, H1 - 0.4))
text("Letters", "SARI-SARI STORE", (0, FY - 0.6, H1 - 0.85), 0.95)
box("Wood", (6.0, 1.4, 0.35), (8.0, FY - 3.6, 1.6))                    # bench and a red cooler outside
for x in (5.6, 10.4):
    box("Wood", (0.35, 1.2, 1.5), (x, FY - 3.6, 0.75))
box("Red", (2.4, 1.6, 2.0), (-8.5, FY - 3.0, 1.0))
box("Cream", (2.5, 1.7, 0.3), (-8.5, FY - 3.0, 2.15))
hip = [(-W / 2 - 1.2, -D / 2 - 1.2, H2), (W / 2 + 1.2, -D / 2 - 1.2, H2), (W / 2 + 1.2, D / 2 + 1.2, H2), (-W / 2 - 1.2, D / 2 + 1.2, H2),
       (-3.0, 0, H2 + 6.0), (3.0, 0, H2 + 6.0)]
roof = bpy.data.meshes.new("r")
roof.from_pydata(hip, [], [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)])
ro = bpy.data.objects.new("r", roof)
bpy.context.collection.objects.link(ro)
add("Roof", ro)
# inside: shelves of goods behind a wooden counter
box("Wood", (16.0, 2.0, 3.2), (0, -2.0, 1.6))
for s in (-1, 1):
    box("Wood", (8.0, 1.6, 7.0), (s * 6.0, D / 2 - 1.8, 3.5))
    for lvl in range(3):
        for j in range(6):
            box(("Red", "Yellow", "Blue", "Orange", "Purple", "Green")[(j + lvl) % 6], (0.9, 0.8, 1.1), (s * 6.0 - 3.0 + j * 1.2, D / 2 - 2.8, 1.4 + lvl * 2.2))

# ===================== PANADERIA (bakery) =====================
CUR[0], OX[0] = "Bakery", 200.0
W, D, H = 28.0, 22.0, 13.0
FY = shell(W, D, H, "Walls", door_w=6.0, door_h=8.5, front_g="Brown", glass_to=8.0)
box("Brown", (W + 0.6, 1.2, 3.2), (0, FY - 0.4, H - 1.5))
box("Cream", (W + 0.8, 1.3, 0.35), (0, FY - 0.45, H + 0.2))
text("Letters", "PANADERIA", (0, FY - 1.1, H - 2.3), 1.9, spacing=1.2)
for s in (-1, 1):                                                       # scalloped brown/cream awnings
    for k in range(5):
        g = "Brown" if k % 2 == 0 else "Cream"
        box(g, (2.0, 3.0, 0.2), (s * (4.5 + k * 2.0), FY - 1.4, 8.8), rot=(math.radians(-18), 0, 0))
        cyl(g, 1.0, 0.1, (s * (4.5 + k * 2.0), FY - 2.8, 8.25), 12, (math.pi / 2, 0, 0))
    for k in range(3):                                                  # bread trays in the window
        box("Wood", (8.0, 1.6, 0.2), (s * 8.5, FY + 1.6, 1.6 + k * 1.8))
        for j in range(6):
            add("Bread", blob(0.45, (s * 8.5 - 3.0 + j * 1.2, FY + 1.6, 1.95 + k * 1.8), 0.15))
box("Cream", (W + 1.2, D + 1.2, 0.8), (0, 0, H + 0.6))
for s in (-1, 1):
    box("Walls", (W, 0.8, 2.0), (0, s * (D / 2 - 0.4), H + 2.0))
    box("Walls", (0.8, D, 2.0), (s * (W / 2 - 0.4), 0, H + 2.0))
box("Stone", (3.0, 3.0, 6.0), (W / 2 - 3.0, D / 2 - 3.0, H + 3.0))      # oven chimney
# inside: glass counter of breads, back shelves of baskets, brick oven
box("Wood", (16.0, 2.4, 3.0), (0, 1.0, 1.5))
box("Glass", (16.0, 2.2, 1.2), (0, 1.0, 3.6))
for j in range(10):
    add("Bread", blob(0.5, (-7.0 + j * 1.55, 1.0, 3.4), 0.15))
for lvl in range(3):
    box("Wood", (18.0, 1.6, 0.25), (0, D / 2 - 2.0, 2.0 + lvl * 2.2))
    for j in range(8):
        add("Bread", blob(0.55, (-7.5 + j * 2.1, D / 2 - 2.0, 2.6 + lvl * 2.2), 0.15))
box("Red", (6.0, 3.0, 5.0), (-W / 2 + 4.5, D / 2 - 2.5, 2.5))
cyl("Iron", 1.2, 0.3, (-W / 2 + 4.5, D / 2 - 4.05, 2.2), 16, (math.pi / 2, 0, 0))

# ===================== finish =====================
SPEC = {"Walls": ("plaster", "plaster"), "Red": ("red", None), "Yellow": ("yellow", None), "Cream": ("cream", "limestone"),
        "Green": ("green", None), "White": ("white", None), "Glass": ("glass", None), "Iron": ("iron", None),
        "Letters": ("white", None), "Floor": ("floor", "marble"), "Stone": ("stone", "stone"), "Lamp": ("warm", None),
        "Leaves": ("leaf", None), "Blue": ("blue", None), "Orange": ("orange", None), "Purple": ("purple", None),
        "Frame": ("iron", None), "Wood": ("wood", "wood"), "Teal": ("teal", None), "Tin": ("tin", None),
        "Roof": ("terracotta", "clay"), "Brown": ("brown", None), "Bread": ("bread", None)}
final = []
for (store, name), objs in G.items():
    obj = c.join(objs, f"{store}_{name}") if len(objs) > 1 else objs[0]
    obj.name = f"{store}_{name}"
    col, tex = SPEC[name]
    c.finish(obj, obj.name, col, smooth=name in ("Leaves",))
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
        tint = {("Kainan", "Walls"): (0.98, 0.9, 0.78), ("Sulit", "Walls"): (0.97, 0.97, 0.94), ("SariSari", "Walls"): (0.62, 0.86, 0.78),
                ("Bakery", "Walls"): (0.99, 0.88, 0.7)}.get((store, name))
        tx.apply(obj, tex, f"{store}_{name}_mat", tint)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
per = {}
for o in final:
    k = o.name.split("_")[0]
    per[k] = per.get(k, 0) + c.triangle_count([o])
print("STORES triangles", c.triangle_count(final), per)
c.export_glb(os.path.join(c.OUT_MODELS, "Stores.glb"), final)

# ---------------- previews ----------------
import mathutils  # noqa: E402

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 40
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1300, 700
sc.view_settings.view_transform = "AgX"
w = bpy.data.worlds.new("Sky")
w.use_nodes = True
sky = w.node_tree.nodes.new("ShaderNodeTexSky")
w.node_tree.links.new(sky.outputs["Color"], w.node_tree.nodes["Background"].inputs["Color"])
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
sc.world = w
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 4.0
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
sc.camera = cm


def shot(path, loc, target, lens, hide_roofs=False, lights=None):
    cm.data.lens = lens
    cm.location = loc
    cm.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    for o in final:
        o.hide_render = hide_roofs and o.name.endswith("_Walls")
    for p in lights or []:
        ld = bpy.data.lights.new("p", "POINT")
        ld.energy = 900
        ld.color = (1, 0.88, 0.7)
        lo = bpy.data.objects.new("p", ld)
        bpy.context.collection.objects.link(lo)
        lo.location = p
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


shot(os.path.join(c.OUT_PREVIEWS, "Stores_front.png"), (35, -95, 30), (35, 0, 8), 26)
shot(os.path.join(c.OUT_PREVIEWS, "Stores_corner.png"), (170, -75, 24), (170, 0, 6), 28)
shot(os.path.join(c.OUT_PREVIEWS, "Stores_inside_kainan.png"), (-15, -14, 7), (8, 10, 3), 18, lights=[(-8, -4, 7), (8, -4, 7)])
shot(os.path.join(c.OUT_PREVIEWS, "Stores_inside_sulit.png"), (52, -17, 8), (75, 12, 3), 18, lights=[(60, 0, 11), (80, 0, 11), (70, 12, 11)])
print("done")
