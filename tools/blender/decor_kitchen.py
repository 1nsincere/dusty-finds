"""Kitchen Nook decor set (Blender 5.x, headless): 8 hand-made-looking pieces, each with a twist. Second set after Cozy Living.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/decor_kitchen.py
Writes assets/models/Decor_Kitchen.glb (a row of the 8 pieces) and previews assets/previews/Decor_Kitchen_Room_*.png (a kitchen corner in two shop colour schemes).
Conventions (see decor_kit.py): 1 unit = 1 stud, Z up, +Y = front, base at z = 0; parts ending _Accent / _Trim take the shop's paint, _Glow lights up.

The eight pieces and their twists:
  DiningSet   a narra table with a banig runner and two woven stools, one pulled out as if someone just stood up
  PotRack     a standing rack hung with pots, a kawali (wok), ladles, a string of garlic and dried chillies
  ClayStove   a kalan clay stove with a palayok pot, firewood, and glowing embers you can see through the front
  Aparador    a louvered cabinet with a capiz-tile transom and a plate rack on top
  JarShelf    a three-tier shelf of glass jars: candies and preserves, one firefly lantern jar that glows
  FruitStand  a tripod stand with a woven basket of mangoes, kalamansi and a hand of bananas
  BangaJar    a clay water jar on a wooden ring stand with a coconut-shell dipper (tabo)
  BakeryCart  a little pandesal cart with a striped awning in the shop's accent colour, bread baskets and a bell
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import decor_kit as k  # noqa: E402

rbox, cyl, ell, rod, lathe_group = k.rbox, k.cyl, k.ell, k.rod, k.lathe_group

NATURAL = {
    "Cane": "D8B878", "CaneDark": "B8925A", "Basket": "C9A66B", "Plate": "F4F0E8", "PlateBlue": "3F6FA8", "Glass": "CFE6EA",
    "Pot": "9EA6AE", "PotDark": "3C3C42", "Clay": "B8623D", "ClayDark": "8E4A2E", "Ember": "FF8A3D", "Glow": "FFD98A", "Ash": "3A3430",
    "Mango": "F2B63A", "MangoRed": "E0593B", "Kalamansi": "7FB347", "Banana": "F0D45A", "BananaTip": "6B4A2E",
    "CandyA": "E0524D", "CandyB": "F2B63A", "CandyC": "5BC0EB", "CandyD": "7FD27F", "Jam": "7A2E4A", "Lid": "C9A24A", "Brass": "C9A24A",
    "Garlic": "F4EFE4", "Chili": "D6402F", "Twine": "A88A5A", "Capiz": "FFF1CE", "Coconut": "5A3B26", "Bread": "D9A25A", "BreadDark": "B0773A",
    "Cloth": "EFE6D2", "Rice": "F6F1E3", "Chalk": "2E3B36", "ChalkText": "F4F0E8", "Metal": "7B828A",
}
SCHEMES = {
    "Capiz Cream": {"Accent": "C8573A", "Trim": "7A4A2E"},
    "Pandan Green": {"Accent": "5F8F4A", "Trim": "D8C9A8"},
}


# ---------------------------------------------------------------- 1. dining set: narra table, banig runner, two woven stools
def stool(p, M, x, y, rot=0.0):
    cyl(p + "_Cane", M, x, y, 1.45, 1.7, 0.85, 18)                                  # woven seat
    cyl(p + "_CaneDark", M, x, y, 1.38, 1.46, 0.9, 18)                              # rim
    for i in range(3):                                                              # splayed legs
        a = rot + math.radians(90 + i * 120)
        rod(p + "_Trim", M, (x + 0.55 * math.cos(a), y + 0.55 * math.sin(a), 1.4), (x + 0.8 * math.cos(a), y + 0.8 * math.sin(a), 0.0), 0.1, 6)
    for z in (0.5, 0.95):                                                           # woven ring braces
        cyl(p + "_CaneDark", M, x, y, z, z + 0.07, 0.62 + 0.18 * (1.0 - z), 14)


def dining_set(M):
    p = "DiningSet"
    rbox(p + "_Trim", M, 0, 0, 2.5, 5.6, 3.3, 0.3, 0.12)                              # the narra top
    rbox(p + "_Trim", M, 0, 0, 2.2, 5.0, 2.7, 0.25, 0.05)                             # apron
    for sx in (-2.3, 2.3):                                                           # four tapered legs with little feet
        for sy in (-1.2, 1.2):
            rod(p + "_Trim", M, (sx, sy, 0.0), (sx, sy, 2.25), 0.2, 10, r1=0.14)
            cyl(p + "_Trim", M, sx, sy, 0.0, 0.18, 0.26, 10)
    rbox(p + "_Accent", M, 0, 0, 2.67, 4.4, 0.95, 0.04, 0.0)                          # banig runner down the middle
    for sx in (-0.9, 0.9):                                                          # a few woven stripes on the runner
        rbox(p + "_Cane", M, sx, 0, 2.7, 0.18, 0.95, 0.02, 0.0)
    for sx, sy in ((-1.7, 0.85), (1.7, 0.85), (-1.7, -0.85), (1.7, -0.85)):          # four plates with a blue rim
        cyl(p + "_PlateBlue", M, sx, sy, 2.65, 2.7, 0.52, 18)
        cyl(p + "_Plate", M, sx, sy, 2.7, 2.74, 0.42, 18)
    ell(p + "_Plate", M, 0.0, 0.0, 2.95, 0.55, 0.55, 0.32, 2)                          # a bowl of rice in the middle
    ell(p + "_Rice", M, 0.0, 0.0, 3.12, 0.46, 0.46, 0.2, 2)
    stool(p, M, -1.4, -2.7)                                                          # tucked in
    stool(p, M, 1.6, 2.75, 0.5)                                                      # pulled out, turned a little


# ---------------------------------------------------------------- 2. pot rack with pots, a kawali, ladles, garlic and chillies
def pot_rack(M):
    p = "PotRack"
    for sx in (-2.4, 2.4):                                                           # two posts with a foot each
        rbox(p + "_Trim", M, sx, 0, 3.4, 0.32, 0.32, 6.8, 0.06)
        rbox(p + "_Trim", M, sx, 0, 0.12, 0.9, 1.7, 0.24, 0.08)
    rbox(p + "_Trim", M, 0, 0, 6.5, 5.4, 0.3, 0.3, 0.08)                              # top bar
    rbox(p + "_Trim", M, 0, 0, 3.0, 4.8, 0.2, 0.2, 0.05)                              # lower rail
    rbox(p + "_Trim", M, 0, 0, 0.9, 4.8, 0.9, 0.12, 0.05)                             # low shelf
    pots = ((-1.8, 1.0, 1.4), (-0.4, 0.8, 1.15), (1.0, 0.65, 0.9))
    for (x, r, h) in pots:                                                            # three pots hanging from the top bar
        rod(p + "_Brass", M, (x, 0, 6.5), (x, 0, 6.5 - 0.5), 0.04, 5)
        cyl(p + "_Pot", M, x, 0.55, 6.0 - h, 6.0, r * 0.72, 16)
        cyl(p + "_PotDark", M, x, 0.55, 6.0 - h * 0.15, 6.02, r * 0.74, 16)
        rod(p + "_PotDark", M, (x + r * 0.7, 0.55, 5.85), (x + r * 1.1, 0.55, 5.8), 0.07, 5)
    # a kawali (wok) hung by its handle, seen from the side
    rod(p + "_Brass", M, (1.9, 0, 6.5), (1.9, 0, 6.0), 0.04, 5)
    ell(p + "_PotDark", M, 1.9, 0.45, 5.0, 0.8, 0.12, 0.8, 2)
    ell(p + "_Metal", M, 1.9, 0.5, 5.0, 0.62, 0.05, 0.62, 2)
    # ladles on the lower rail
    for x in (-1.9, -1.45, -1.0):
        rod(p + "_Trim", M, (x, 0.2, 3.0), (x, 0.3, 1.5), 0.05, 5)
        ell(p + "_Coconut", M, x, 0.3, 1.35, 0.2, 0.2, 0.2, 1)
    # a string of garlic and a bunch of dried chillies
    rod(p + "_Twine", M, (-2.2, 0.2, 6.4), (-2.2, 0.2, 4.6), 0.03, 4)
    for i in range(6):
        ell(p + "_Garlic", M, -2.2 + (0.12 if i % 2 else -0.12), 0.2, 6.2 - i * 0.28, 0.2, 0.2, 0.22, 1)
    rod(p + "_Twine", M, (2.2, 0.2, 6.4), (2.2, 0.2, 5.0), 0.03, 4)
    for i in range(7):
        ell(p + "_Chili", M, 2.2 + 0.08 * math.sin(i * 2.0), 0.2 + 0.08 * math.cos(i * 2.0), 6.2 - i * 0.18, 0.07, 0.07, 0.22, 1)
    # low shelf: stacked plates and a rice pot
    for i in range(4):
        cyl(p + "_Plate", M, -1.3, 0.0, 0.96 + i * 0.07, 1.02 + i * 0.07, 0.62, 16)
    cyl(p + "_Clay", M, 1.2, 0.0, 0.96, 1.7, 0.6, 14, r_top=0.5)


# ---------------------------------------------------------------- 3. kalan clay stove with a palayok, firewood and glowing embers
def clay_stove(M):
    p = "ClayStove"
    lathe_group(p + "_Clay", M, [(0.0, 0.0), (1.2, 0.0), (1.28, 0.2), (1.05, 1.2), (0.95, 2.0), (1.15, 2.3), (0.0, 2.3)], 20)      # the stove body
    cyl(p + "_ClayDark", M, 0, 0, 2.3, 2.42, 1.2, 20)                                                                                 # rim
    for i in range(3):                                                                                                                # three pot supports
        a = math.radians(90 + i * 120)
        rbox(p + "_ClayDark", M, 0.7 * math.cos(a), 0.7 * math.sin(a), 2.55, 0.28, 0.28, 0.35, 0.06)
    lathe_group(p + "_Clay", M, [(0.0, 2.7), (0.55, 2.75), (0.9, 3.2), (0.95, 3.7), (0.75, 4.2), (0.62, 4.35), (0.0, 4.35)], 18)  # the palayok
    cyl(p + "_ClayDark", M, 0, 0, 4.3, 4.45, 0.72, 18)
    ell(p + "_ClayDark", M, 0.0, 0.0, 4.5, 0.32, 0.32, 0.12, 1)                                                                       # knob
    # the fire door at the front with embers glowing inside
    ell(p + "_Ash", M, 0.0, 1.05, 0.95, 0.62, 0.15, 0.55, 2)
    ell(p + "_Glow", M, 0.0, 1.0, 0.8, 0.42, 0.12, 0.3, 2)
    ell(p + "_Glow", M, -0.25, 1.0, 0.55, 0.16, 0.1, 0.12, 1)
    ell(p + "_Glow", M, 0.28, 1.0, 0.6, 0.14, 0.1, 0.1, 1)
    # a stack of firewood beside it
    for i, (dx, dz) in enumerate(((2.0, 0.18), (2.0, 0.56), (2.0, 0.94), (2.0, 1.32), (2.45, 0.18), (2.45, 0.56))):
        rod(p + "_Trim", M, (dx, -0.7, dz), (dx, 0.7, dz), 0.17, 8)
    rbox(p + "_Trim", M, 2.2, 0.0, 0.08, 1.2, 1.7, 0.16, 0.04)


# ---------------------------------------------------------------- 4. aparador cabinet with louvered doors and a plate rack
def aparador(M):
    p = "Aparador"
    W, D, H = 4.6, 1.7, 5.4
    for sx in (-W / 2 + 0.18, W / 2 - 0.18):
        cyl(p + "_Trim", M, sx, -0.6, 0.0, 0.7, 0.16, 10, r_top=0.1)
        cyl(p + "_Trim", M, sx, 0.6, 0.0, 0.7, 0.16, 10, r_top=0.1)
    rbox(p + "_Trim", M, 0, 0, 0.7 + (H - 0.7) / 2, W, D, H - 0.7, 0.1)                # the body
    for sx in (-W / 4 - 0.02, W / 4 + 0.02):                                           # two doors, each a frame with louver slats
        rbox(p + "_Accent", M, sx, D / 2 + 0.02, 2.7, W / 2 - 0.3, 0.1, 3.7, 0.06)
        for i in range(10):
            z = 1.1 + i * 0.32
            rbox(p + "_Cane", M, sx, D / 2 + 0.1, z, W / 2 - 0.6, 0.12, 0.12, 0.02, rot=(-0.35, 0, 0))
        rbox(p + "_Brass", M, sx + (0.3 if sx < 0 else -0.3), D / 2 + 0.14, 2.7, 0.1, 0.1, 0.5, 0.03)
    for i in range(7):                                                                  # the capiz-tile transom above the doors
        x = -W / 2 + 0.5 + i * (W - 1.0) / 6
        rbox(p + "_Capiz", M, x, D / 2 + 0.03, 4.9, 0.5, 0.05, 0.5, 0.0, rot=(0, 0, math.pi / 4))
    rbox(p + "_Trim", M, 0, 0, H + 0.12, W + 0.3, D + 0.25, 0.24, 0.08)                # top slab
    # a plate rack on top: a few plates standing up
    rbox(p + "_Trim", M, 0, -0.1, H + 0.3, 3.2, 0.9, 0.12, 0.04)
    for i in range(6):
        x = -1.3 + i * 0.52
        cyl(p + "_Plate", M, x, 0.05, H + 0.38, H + 0.43, 0.0, 4)
        ell(p + "_Plate", M, x, 0.0, H + 1.0, 0.42, 0.07, 0.42, 2)
        ell(p + "_PlateBlue", M, x, 0.05, H + 1.0, 0.3, 0.04, 0.3, 2)
    rbox(p + "_Trim", M, 0, 0.35, H + 0.4, 3.2, 0.08, 0.25, 0.02)                      # the rail that holds them


# ---------------------------------------------------------------- 5. jar shelf with candy, preserves and a firefly lantern jar
def jar_shelf(M):
    p = "JarShelf"
    W, D, H = 4.4, 1.2, 6.4
    for sx in (-W / 2 + 0.12, W / 2 - 0.12):
        rbox(p + "_Trim", M, sx, 0, H / 2, 0.24, D, H, 0.05)
    rbox(p + "_Trim", M, 0, -D / 2 + 0.05, H / 2, W, 0.1, H, 0.03)
    for z in (0.0, 2.1, 4.2, 6.2):
        rbox(p + "_Trim", M, 0, 0, z + 0.1, W, D, 0.2, 0.05)
    rbox(p + "_Accent", M, 0, D / 2, H + 0.1, W + 0.2, 0.25, 0.35, 0.08)               # a painted valance on top
    candy = ("CandyA", "CandyB", "CandyC", "CandyD", "Jam")
    for tier, z0 in enumerate((0.2, 2.3, 4.4)):
        for j in range(4):
            x = -1.5 + j * 1.0
            h = 1.15 + 0.1 * ((j + tier) % 2)
            cyl(p + "_Glass", M, x, 0.05, z0, z0 + h, 0.38, 14)
            ell(p + "_" + candy[(j + tier) % 5], M, x, 0.05, z0 + h * 0.4, 0.3, 0.3, h * 0.36, 1)
            cyl(p + "_Lid", M, x, 0.05, z0 + h, z0 + h + 0.12, 0.34, 14)
    # the top tier's far-right jar is a lantern full of fireflies
    cyl(p + "_Glass", M, 1.5, 0.05, 4.4, 5.65, 0.42, 14)
    for (fx, fz) in ((1.4, 4.8), (1.65, 5.1), (1.5, 4.6), (1.35, 5.3)):
        ell(p + "_Glow", M, fx, 0.05, fz, 0.09, 0.09, 0.09, 1)
    # a little hand-written price tag on a string hanging from the second shelf
    rbox(p + "_Plate", M, -1.0, D / 2 + 0.05, 2.0, 0.6, 0.03, 0.3, 0.01)


# ---------------------------------------------------------------- 6. fruit stand: tripod, woven basket, mangoes, kalamansi, bananas
def fruit_stand(M):
    p = "FruitStand"
    for i in range(3):                                                                  # a tripod of three splayed legs with a ring
        a = math.radians(90 + i * 120)
        rod(p + "_Trim", M, (0.4 * math.cos(a), 0.4 * math.sin(a), 2.6), (1.25 * math.cos(a), 1.25 * math.sin(a), 0.0), 0.11, 7)
    cyl(p + "_Trim", M, 0, 0, 2.5, 2.62, 0.55, 16)
    rings = 6
    for r in range(rings):                                                              # the woven basket
        z = 2.62 + r * 0.2
        rad = 0.95 + 0.2 * math.sin(r / (rings - 1) * math.pi * 0.9)
        cyl(p + "_Basket", M, 0, 0, z, z + 0.17, rad + (0.04 if r % 2 else 0.0), 18)
    cyl(p + "_Cloth", M, 0, 0, 3.7, 3.78, 1.05, 18)                                     # a cloth lining
    for (x, y, z) in ((-0.4, 0.2, 3.95), (0.4, -0.1, 3.95), (0.0, 0.45, 3.95), (-0.15, -0.4, 4.05), (0.15, 0.1, 4.22)):
        ell(p + "_Mango", M, x, y, z, 0.36, 0.3, 0.3, 2)
        ell(p + "_MangoRed", M, x + 0.1, y + 0.05, z + 0.08, 0.2, 0.12, 0.16, 1)
    for (x, y, z) in ((0.7, 0.4, 3.95), (-0.7, -0.1, 3.95), (0.55, -0.5, 3.95), (-0.55, 0.5, 4.0), (0.05, -0.75, 3.95), (0.8, -0.1, 4.05)):
        ell(p + "_Kalamansi", M, x, y, z, 0.17, 0.17, 0.17, 1)
    # a hand of bananas hanging over the front rim
    for i in range(5):
        a = (i - 2) * 0.15
        pts = [(0.6 + 0.18 * i, 0.85, 4.1 - 0.1 * i), (0.7 + 0.18 * i, 1.2, 3.65 - 0.1 * i), (0.85 + 0.18 * i, 1.35, 3.1 - 0.1 * i)]
        for a_, b_ in zip(pts[:-1], pts[1:]):
            rod(p + "_Banana", M, a_, b_, 0.13, 6, r1=0.1)
        ell(p + "_BananaTip", M, pts[-1][0], pts[-1][1], pts[-1][2] - 0.04, 0.07, 0.07, 0.07, 1)


# ---------------------------------------------------------------- 7. banga water jar with a wooden ring stand and a coconut dipper
def banga_jar(M):
    p = "BangaJar"
    for i in range(3):
        a = math.radians(90 + i * 120)
        rod(p + "_Trim", M, (0.5 * math.cos(a), 0.5 * math.sin(a), 1.4), (0.95 * math.cos(a), 0.95 * math.sin(a), 0.0), 0.1, 7)
    cyl(p + "_Trim", M, 0, 0, 1.4, 1.58, 1.05, 18)
    lathe_group(p + "_Clay", M, [(0.0, 1.6), (0.7, 1.62), (1.2, 2.3), (1.32, 3.1), (1.1, 3.9), (0.65, 4.3), (0.55, 4.7), (0.7, 4.85), (0.0, 4.85)], 20)   # the jar
    lathe_group(p + "_ClayDark", M, [(0.5, 4.8), (0.72, 4.82), (0.72, 4.92), (0.5, 4.9)], 20)                                                       # its lip
    ell(p + "_Cloth", M, 0, 0, 4.92, 0.62, 0.62, 0.07, 1)                                                                                            # a cloth cover
    cyl(p + "_ClayDark", M, 0, 0, 3.0, 3.1, 1.34, 20)
    cyl(p + "_Accent", M, 0, 0, 3.1, 3.5, 1.3, 20)                                                                                                   # a painted band in the shop's accent
    cyl(p + "_ClayDark", M, 0, 0, 3.5, 3.6, 1.24, 20)
    # the tabo (coconut dipper) resting on the cover
    ell(p + "_Coconut", M, 0.05, 0.1, 5.05, 0.34, 0.34, 0.2, 2)
    rod(p + "_Trim", M, (0.3, 0.1, 5.1), (0.95, 0.1, 5.5), 0.06, 5)


# ---------------------------------------------------------------- 8. pandesal cart with a striped awning
def wheel(p, M, x, r=1.15):
    n = 16
    pts = [(x, r * math.cos(2 * math.pi * i / n), r + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    for a, b in zip(pts, pts[1:] + pts[:1]):
        rod(p + "_Trim", M, a, b, 0.11, 6)
    for i in range(8):
        a = 2 * math.pi * i / 8
        rod(p + "_Trim", M, (x, 0.0, r), (x, r * 0.95 * math.cos(a), r + r * 0.95 * math.sin(a)), 0.05, 5)
    ell(p + "_Brass", M, x, 0.0, r, 0.13, 0.22, 0.22, 1)


def bakery_cart(M):
    p = "BakeryCart"
    wheel(p, M, -1.95)
    wheel(p, M, 1.95)
    rod(p + "_Trim", M, (-2.0, 0.0, 1.15), (2.0, 0.0, 1.15), 0.1, 6)                    # axle
    rbox(p + "_Trim", M, 0, 0.1, 2.1, 4.0, 2.4, 0.3, 0.1)                              # the deck
    rbox(p + "_Trim", M, 0, -1.0, 2.95, 4.0, 0.15, 1.3, 0.04)                          # a back rail
    for sx in (-1.95, 1.95):
        rbox(p + "_Trim", M, sx, 0.1, 2.75, 0.14, 2.4, 0.7, 0.03)                       # side boards
    rod(p + "_Trim", M, (-1.4, 1.2, 2.1), (-1.9, 3.4, 1.4), 0.1, 6)                    # pull handles at the front
    rod(p + "_Trim", M, (1.4, 1.2, 2.1), (1.9, 3.4, 1.4), 0.1, 6)
    rod(p + "_Trim", M, (-1.9, 3.4, 1.4), (1.9, 3.4, 1.4), 0.09, 6)
    # two bread baskets with pandesal and a glass-covered tray
    for bx_ in (-1.0, 1.0):
        cyl(p + "_Basket", M, bx_, 0.1, 2.25, 2.7, 0.8, 16, r_top=0.95)
        for (dx, dy) in ((-0.3, -0.2), (0.3, -0.1), (0.0, 0.3), (-0.2, 0.3), (0.35, 0.3), (0.0, -0.4)):
            ell(p + ("_BreadDark" if (dx > 0) else "_Bread"), M, bx_ + dx, 0.1 + dy, 2.75, 0.3, 0.26, 0.2, 1)
    # the awning: two poles, striped canvas in the shop's accent colour and cream
    for sx in (-1.9, 1.9):
        rod(p + "_Trim", M, (sx, -0.9, 2.2), (sx, -0.9, 6.0), 0.09, 6)
    for i in range(10):
        x = -2.3 + i * 0.46
        rbox(p + ("_Accent" if i % 2 == 0 else "_Cloth"), M, x + 0.23, 0.0, 6.0 + 0.0, 0.46, 3.0, 0.1, 0.02, rot=(-0.22, 0, 0))
    for i in range(10):                                                                 # the scalloped fringe
        x = -2.3 + i * 0.46
        ell(p + ("_Accent" if i % 2 == 0 else "_Cloth"), M, x + 0.23, 1.45, 5.62, 0.23, 0.05, 0.22, 1)
    # a chalk sign and a little bell
    rbox(p + "_Chalk", M, 0, -0.95, 4.2, 2.2, 0.1, 1.0, 0.04)
    rbox(p + "_ChalkText", M, 0, -0.88, 4.2, 1.5, 0.02, 0.18, 0.0)
    rod(p + "_Brass", M, (1.2, 1.4, 5.65), (1.2, 1.4, 5.2), 0.025, 4)
    ell(p + "_Brass", M, 1.2, 1.4, 5.1, 0.17, 0.17, 0.2, 1)


PIECES = (
    ("DiningSet", dining_set), ("PotRack", pot_rack), ("ClayStove", clay_stove), ("Aparador", aparador),
    ("JarShelf", jar_shelf), ("FruitStand", fruit_stand), ("BangaJar", banga_jar), ("BakeryCart", bakery_cart),
)

# ---------------------------------------------------------------- 1) export: the eight pieces in a row
k.reset()
SP = 11.0
for i, (name, fn) in enumerate(PIECES):
    fn(Matrix.Translation((i * SP, 0, 0)))
objs = k.make_objects("Capiz Cream", NATURAL, SCHEMES)
per = {}
for o in objs:
    key = o.name.split("_")[0]
    per[key] = per.get(key, 0) + c.triangle_count([o])
print("KITCHEN triangles", c.triangle_count(objs), per)
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "Decor_Kitchen.glb"), objs)
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no render)")
    raise SystemExit


# ---------------------------------------------------------------- 2) previews: a kitchen corner in two shop colour schemes
def room(scheme, wall_hex, floor_hex, out_name):
    k.reset()
    Mz = lambda x, y, rz=0.0: Matrix.Translation((x, y, 0)) @ Matrix.Rotation(rz, 4, "Z")
    aparador(Mz(-9.5, -4.8))
    jar_shelf(Mz(-4.2, -5.4))
    pot_rack(Mz(1.5, -5.0))
    clay_stove(Mz(7.5, -4.4, 0.2))
    dining_set(Mz(-3.0, 1.8))
    fruit_stand(Mz(4.0, 3.2, -0.4))
    banga_jar(Mz(-10.5, 3.0))
    bakery_cart(Mz(9.8, 4.2, -0.5))
    k.make_objects(scheme, NATURAL, SCHEMES)
    k.render_room(os.path.join(c.OUT_PREVIEWS, out_name), wall_hex, floor_hex, (0.5, 27.0, 11.5), (0.0, 0.0, 2.4))


room("Capiz Cream", "EFE3C9", "B88B5A", "Decor_Kitchen_Room_Cream.png")
room("Pandan Green", "DCE8D0", "C8A878", "Decor_Kitchen_Room_Green.png")
print("done")
