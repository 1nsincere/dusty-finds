"""Cozy Living decor v2 (Blender 5.x, headless): soft, hand-made-looking pieces, each with a twist. Replaces the blocky v1 (decor_cozy.py).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/decor_cozy_v2.py
Writes assets/models/Decor_Cozy.glb (a row of the 8 pieces) and previews assets/previews/Decor_Cozy_Room_*.png (a living-room corner in two shop colour schemes).

1 unit = 1 stud, Z up, +Y = the front of each piece, base at z = 0. Every colour group is its own object named  <Piece>_<Part>.
SHOP-FIT SLOTS (the twist that makes every piece match every player's shop): parts ending in  _Accent  take the shop's ACCENT paint colour and
parts ending in  _Trim  take its TRIM paint colour (Studio / PaintService recolours them; see docs/STATUS). Everything else is a natural fixed
material (rattan, leaves, cat, glass, books) that looks good in any palette. Parts ending in  _Glow  are meant to light up (Neon + a light).

The eight pieces and their twists:
  PeacockLoveseat  a fan-ribbed rattan "peacock" back (Philippine classic), plump cushions in the shop's accent colour
  PeacockChair     the same chair, with a sleeping cat curled on the cushion (a tiny "zzz" can be added in game)
  BanigRug         a woven banig mat in a diamond pattern; its main colour is the shop's accent
  TinikTable       a low narra table on two CROSSED BAMBOO POLES: a nod to the tinikling dance
  CapizLamp        a floor lamp whose shade is made of staggered capiz shell tiles (glows warm)
  TeaTable         a turned narra side table with a small kettle and two cups (steam can be added in game)
  Bookcase         an arched-crown bookcase with a leaning ladder, a globe and a jar of fireflies (the jar glows)
  Monstera         a tall fiddle-leaf plant in a hand-woven basket (the piece id stays "Monstera")
"""

import math
import os
import sys

import bmesh
import bpy
import mathutils
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

# ---------------------------------------------------------------- palettes (preview only; the game recolours the _Accent / _Trim slots)
NATURAL = {
    "Cane": "D8B878", "CaneDark": "B8925A", "Leaf": "3F7F4A", "LeafDark": "2C5E38", "Basket": "C9A66B", "Cat": "D98A3D", "CatCream": "F1DEC0", "CatDark": "9C5A1E",
    "Cushion": "EFE6D2", "Glass": "CFE6EA", "Soil": "4A3626", "Terracotta": "C2693F", "Kettle": "B9BEC4", "Cup": "F4F0E8", "Bamboo": "C8B25E",
    "BambooNode": "8F7C34", "Capiz": "FFF1CE", "Glow": "FFD98A", "BookA": "2F5D6B", "BookB": "B84A33", "BookC": "E3B23C", "BookD": "6E4A7E",
    "Globe": "3F7DA8", "Brass": "C9A24A", "Pole": "5A3B26",
}
SCHEMES = {
    "Capiz Cream": {"Accent": "C8573A", "Trim": "7A4A2E"},   # the default shop: warm terracotta accent, narra trim
    "Canal Teal": {"Accent": "2F8F8F", "Trim": "D8C9A8"},    # a teal / pale wood shop
}

G = {}


def reset():
    c.reset_scene()
    G.clear()


def _flush(group, bm, M):
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    v = [tuple(x.co) for x in bm.verts]
    f = [tuple(vv.index for vv in ff.verts) for ff in bm.faces]
    bm.free()
    G.setdefault(group, []).append((v, f))


def rbox(group, M, cx, cy, cz, sx, sy, sz, r=0.1, rot=(0, 0, 0)):
    """A rounded box (soft edges) centred at (cx, cy, cz) with size (sx, sy, sz)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    if r > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(r, min(sx, sy, sz) * 0.45), segments=3, affect="EDGES")
    R = mathutils.Euler(rot).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((cx, cy, cz)) @ R, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _flush(group, bm, M)


def cyl(group, M, cx, cy, z0, z1, r, n=14, r_top=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=n, radius1=r, radius2=(r if r_top is None else r_top), depth=z1 - z0)
    bmesh.ops.translate(bm, vec=(cx, cy, (z0 + z1) / 2), verts=bm.verts)
    _flush(group, bm, M)


def ell(group, M, cx, cy, cz, rx, ry, rz, sub=2, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    bmesh.ops.scale(bm, vec=(rx, ry, rz), verts=bm.verts)
    R = mathutils.Euler(rot).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((cx, cy, cz)) @ R, verts=bm.verts)
    _flush(group, bm, M)


def rod(group, M, p0, p1, r, n=6, r1=None):
    """A round rod from p0 to p1 (optionally tapering to radius r1)."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    if d.length < 1e-6:
        return
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=n, radius1=r, radius2=(r if r1 is None else r1), depth=d.length)
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ q, verts=bm.verts)
    _flush(group, bm, M)


def tile(group, M, cx, cy, cz, sx, sy):
    """A flat top face only (for the woven rug: cheap, the rug is a thin sheet)."""
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in ((cx - sx / 2, cy - sy / 2, cz), (cx + sx / 2, cy - sy / 2, cz), (cx + sx / 2, cy + sy / 2, cz), (cx - sx / 2, cy + sy / 2, cz))]
    bm.faces.new(v)
    _flush(group, bm, M)


def lathe_group(group, M, profile, steps=18):
    """Solid of revolution around Z, profile = [(radius, height), ...] from bottom centre outward and up."""
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=steps)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _flush(group, bm, M)


# ---------------------------------------------------------------- shared: the peacock chair back (a fan of rattan ribs and woven rings)
def peacock_back(prefix, M, half_w, base_y, base_z, rx, rz, ribs, tilt=0.0):
    """Ribs fan out from the seat back (a line from -half_w to +half_w) up to an ellipse; two woven rings join them."""
    cx_, cz_ = 0.0, base_z + rz * 0.42
    pts = []
    for i in range(ribs):
        t = i / (ribs - 1)
        ang = math.pi * (0.03 + 0.94 * t)                       # 0 = right, pi = left: the upper half of the ellipse
        x = rx * math.cos(ang)
        z = cz_ + rz * math.sin(ang) * 0.95
        y = base_y - 0.25 - 0.55 * math.sin(ang) * tilt - 0.2 * (1 - math.sin(ang))
        bx_ = -half_w + 2 * half_w * (1 - t)
        rod(prefix + "_Cane", M, (bx_, base_y, base_z), (x, y, z), 0.075, 6)
        pts.append((x, y, z, ang))
    for scale, rr in ((1.0, 0.1), (0.62, 0.07)):                # woven rings: rods between rib points along the arc
        ring = []
        for k in range(ribs * 2):
            ang = math.pi * (0.03 + 0.94 * k / (ribs * 2 - 1))
            ring.append((rx * scale * math.cos(ang), base_y - 0.25 - 0.1 - 0.5 * math.sin(ang) * tilt - 0.2 * (1 - math.sin(ang)) * scale,
                         base_z + (cz_ - base_z) + rz * scale * math.sin(ang) * 0.95 - (1 - scale) * rz * 0.18))
        for a, b in zip(ring[:-1], ring[1:]):
            rod(prefix + "_CaneDark", M, a, b, rr, 6)
    # the outer frame: a thicker hoop on the rim
    for a, b in zip(pts[:-1], pts[1:]):
        rod(prefix + "_CaneDark", M, a[:3], b[:3], 0.13, 6)


# ---------------------------------------------------------------- 1. peacock loveseat
def peacock_loveseat(M):
    p = "PeacockLoveseat"
    for sx in (-2.55, 2.55):                                                      # turned tapered legs
        for sy in (-1.1, 1.1):
            cyl(p + "_Trim", M, sx, sy, 0.0, 1.0, 0.16, 10, r_top=0.1)
    rbox(p + "_Trim", M, 0, 0, 1.15, 5.7, 2.9, 0.3, 0.12)                           # seat frame
    rbox(p + "_Cane", M, 0, 0, 0.98, 5.35, 2.55, 0.1, 0.05)                           # woven underside
    rbox(p + "_Accent", M, 0, 0.1, 1.55, 5.3, 2.5, 0.75, 0.32)                       # plump seat cushion
    rbox(p + "_Accent", M, -1.35, -1.05, 2.5, 2.45, 0.7, 1.35, 0.3, rot=(-0.12, 0, 0))     # two back cushions
    rbox(p + "_Accent", M, 1.35, -1.05, 2.5, 2.45, 0.7, 1.35, 0.3, rot=(-0.12, 0, 0))
    ell(p + "_Cushion", M, -2.3, 0.45, 2.3, 0.62, 0.3, 0.62, 2, rot=(0.35, 0.0, 0.5))   # two soft throw pillows
    ell(p + "_Cushion", M, 2.25, 0.55, 2.25, 0.58, 0.3, 0.58, 2, rot=(0.3, 0.0, -0.45))
    for sx in (-2.95, 2.95):                                                         # rolled arms
        rbox(p + "_Trim", M, sx, 0.0, 1.9, 0.5, 2.8, 1.25, 0.2)
    peacock_back(p, M, 2.6, -1.25, 1.8, 3.15, 3.5, 21, tilt=0.6)


# ---------------------------------------------------------------- 2. peacock chair with a sleeping cat
def peacock_chair(M):
    p = "PeacockChair"
    for sx in (-1.2, 1.2):
        for sy in (-0.9, 0.9):
            cyl(p + "_Trim", M, sx, sy, 0.0, 1.0, 0.15, 10, r_top=0.1)
    rbox(p + "_Trim", M, 0, 0, 1.15, 3.1, 2.5, 0.3, 0.12)
    rbox(p + "_Cane", M, 0, 0, 0.98, 2.8, 2.2, 0.1, 0.05)
    rbox(p + "_Accent", M, 0, 0.05, 1.55, 2.9, 2.2, 0.75, 0.32)
    peacock_back(p, M, 1.3, -1.05, 1.8, 2.55, 3.1, 17, tilt=0.5)
    # the sleeping cat: curled body, head tucked in, two ears, a curled tail
    ell("PeacockChair_Cat", M, 0.0, 0.15, 2.05, 0.9, 0.7, 0.42, 2)
    ell("PeacockChair_Cat", M, 0.55, 0.55, 2.15, 0.4, 0.36, 0.34, 2)
    for ex in (0.38, 0.74):
        bm_pts = None
        rod("PeacockChair_Cat", M, (ex, 0.6, 2.4), (ex + (0.04 if ex > 0.5 else -0.04), 0.62, 2.62), 0.09, 4, r1=0.01)
    ell("PeacockChair_CatCream", M, 0.0, 0.62, 2.0, 0.55, 0.22, 0.26, 2)             # cream belly / paws
    ell("PeacockChair_CatCream", M, 0.62, 0.78, 2.12, 0.2, 0.1, 0.14, 1)             # muzzle
    pts = [(-0.7, 0.2, 2.1), (-1.0, 0.55, 2.0), (-0.75, 0.95, 1.95), (-0.25, 1.05, 2.0)]
    for a, b in zip(pts[:-1], pts[1:]):
        rod("PeacockChair_Cat", M, a, b, 0.12, 6, r1=0.1)
    # the dark stripes on the back
    for sx in (-0.3, 0.1, 0.5):
        ell("PeacockChair_CatDark", M, sx, 0.1, 2.42, 0.1, 0.5, 0.04, 1)


# ---------------------------------------------------------------- 3. banig rug (woven diamond pattern)
def banig_rug(M):
    p = "BanigRug"
    L, Wd = 8.4, 5.0
    rbox(p + "_Cane", M, 0, 0, 0.05, L, Wd, 0.1, 0.03)                                  # the mat itself
    for k in range(-5, 6):                                                              # woven look: fine stripes across the whole mat
        if k % 2 == 0:
            rbox(p + "_CaneDark", M, k * 0.72, 0, 0.105, 0.26, Wd - 0.5, 0.025, 0.0)
    for k, (fx, fy, col) in enumerate(((1.0, 1.0, "_Trim"), (0.86, 0.84, "_Cane"), (0.74, 0.7, "_Accent"))):   # a border frame in three bands
        t = 0.2
        for sx in (-1, 1):
            rbox(p + col, M, sx * (L / 2 * fx - t / 2), 0, 0.12 + k * 0.012, t, Wd * fy - 2 * t, 0.03, 0.0)   # between the long sides, so corners do not overlap
        for sy in (-1, 1):
            rbox(p + col, M, 0, sy * (Wd / 2 * fy - t / 2), 0.12 + k * 0.012, L * fx, t, 0.03, 0.0)
    # three nested diamonds in the middle (a classic banig lozenge)
    for k, (size, col) in enumerate(((1.9, "_Trim"), (1.55, "_Accent"), (1.15, "_Cane"), (0.7, "_Accent"), (0.3, "_Trim"))):
        rbox(p + col, M, 0, 0, 0.13 + k * 0.014, size * 1.35, size * 1.35, 0.03, 0.0, rot=(0, 0, math.pi / 4))
    for side in (-1, 1):                                                                # fringe tassels on the short ends
        for k in range(20):
            yy = -Wd / 2 + (k + 0.5) * (Wd / 20)
            rod(p + "_Cane", M, (side * (L / 2), yy, 0.05), (side * (L / 2 + 0.3), yy, 0.03), 0.03, 4)


# ---------------------------------------------------------------- 4. tinikling low table on crossed bamboo poles
def tinik_table(M):
    p = "TinikTable"
    for sign in (-1, 1):                                                              # two crossed bamboo poles under the top
        a = (-2.1 * sign, -1.1, 0.12)
        b = (2.1 * sign, 1.1, 0.12)
        rod(p + "_Bamboo", M, (a[0], a[1], 0.18), (b[0], b[1], 0.18), 0.17, 8)
        for k in range(1, 6):                                                          # bamboo nodes
            t = k / 6
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 0.18)
            ell(p + "_BambooNode", M, q[0], q[1], q[2], 0.2, 0.2, 0.2, 1)
    for sign in (-1, 1):                                                              # raised on small bamboo posts
        for sx in (-1.3, 1.3):
            cyl(p + "_Bamboo", M, sx * sign * 0.7, sx * 0.45 * sign, 0.18, 1.0, 0.16, 8)
    cyl(p + "_Trim", M, 0, 0, 1.0, 1.22, 2.2, 28)                                     # the narra top
    cyl(p + "_Trim", M, 0, 0, 1.22, 1.3, 2.05, 28)
    cyl(p + "_Accent", M, 0, 0, 1.3, 1.34, 1.2, 28)                                    # an inlaid accent medallion
    # a little tray with two cups
    for (qx, qy) in ((0.55, 0.2), (-0.5, -0.3)):
        lathe_group(p + "_Cup", M, [(0.0, 1.34 + 0.0), (0.2, 1.34), (0.27, 1.62), (0.23, 1.62), (0.0, 1.4)], 12) if False else None
        cyl(p + "_Cup", M, qx, qy, 1.34, 1.62, 0.2, 12, r_top=0.27)


# ---------------------------------------------------------------- 5. capiz floor lamp (staggered shell tiles)
def capiz_lamp(M):
    p = "CapizLamp"
    cyl(p + "_Trim", M, 0, 0, 0.0, 0.25, 0.85, 20)
    lathe_group(p + "_Trim", M, [(0.0, 0.25), (0.38, 0.3), (0.2, 0.7), (0.12, 1.4), (0.12, 4.0), (0.2, 4.3), (0.05, 4.4)], 14)   # a turned pole
    cyl(p + "_Brass", M, 0, 0, 4.2, 4.36, 0.3, 14)
    rings, per = 6, 12
    R0, R1 = 1.05, 0.85
    for k in range(rings):                                                              # capiz tile rings, each ring offset by half a tile
        z = 4.6 + k * 0.42
        rad = R0 + (R1 - R0) * k / (rings - 1)
        for i in range(per):
            a = 2 * math.pi * (i + (0.5 if k % 2 else 0.0)) / per
            x, y = rad * math.cos(a), rad * math.sin(a)
            rbox(p + "_Capiz", M, x, y, z, 0.62, 0.05, 0.38, 0.0, rot=(0, 0, a + math.pi / 2))
    for z0 in (4.45, 6.95):                                                              # top and bottom hoops
        cyl(p + "_Brass", M, 0, 0, z0, z0 + 0.12, R0 + 0.06 if z0 < 5 else R1 + 0.06, 20)
    for i in range(6):                                                                  # ribs
        a = 2 * math.pi * i / 6
        rod(p + "_Brass", M, ((R0 + 0.02) * math.cos(a), (R0 + 0.02) * math.sin(a), 4.5), ((R1 + 0.02) * math.cos(a), (R1 + 0.02) * math.sin(a), 7.05), 0.04, 5)
    ell(p + "_Glow", M, 0, 0, 5.8, 0.5, 0.5, 0.7, 2)                                    # the warm bulb inside


# ---------------------------------------------------------------- 6. tea table with kettle and cups
def tea_table(M):
    p = "TeaTable"
    lathe_group(p + "_Trim", M, [(0.0, 0.0), (0.95, 0.0), (0.95, 0.18), (0.45, 0.4), (0.3, 0.9), (0.42, 1.25), (0.28, 1.7), (0.34, 2.05), (0.0, 2.05)], 20)
    cyl(p + "_Trim", M, 0, 0, 2.05, 2.28, 1.35, 28)
    cyl(p + "_Trim", M, 0, 0, 2.28, 2.35, 1.2, 28)
    cyl(p + "_Accent", M, 0, 0, 2.35, 2.38, 0.75, 24)                                   # a woven accent mat under the tea set
    lathe_group(p + "_Kettle", M, [(0.0, 2.38), (0.34, 2.38), (0.4, 2.62), (0.3, 2.95), (0.16, 3.08), (0.12, 3.14), (0.0, 3.16)], 16)   # kettle body
    rod(p + "_Kettle", M, (0.34, 0.0, 2.62), (0.68, 0.0, 2.88), 0.05, 6)                  # spout
    rod(p + "_Kettle", M, (-0.34, 0.0, 2.8), (-0.55, 0.0, 2.62), 0.04, 5)                # handle
    rod(p + "_Kettle", M, (-0.55, 0.0, 2.62), (-0.36, 0.0, 2.45), 0.04, 5)
    cyl(p + "_Cup", M, -0.6, 0.55, 2.38, 2.62, 0.17, 12, r_top=0.23)
    cyl(p + "_Cup", M, -0.15, 0.62, 2.38, 2.62, 0.17, 12, r_top=0.23)


# ---------------------------------------------------------------- 7. bookcase with arched crown, ladder, globe and firefly jar
def bookcase(M):
    p = "Bookcase"
    W, D, H = 4.0, 1.3, 6.6
    rbox(p + "_Trim", M, -W / 2 + 0.1, 0, H / 2, 0.2, D, H, 0.05)
    rbox(p + "_Trim", M, W / 2 - 0.1, 0, H / 2, 0.2, D, H, 0.05)
    rbox(p + "_Trim", M, 0, -D / 2 + 0.05, H / 2, W, 0.1, H, 0.03)
    for z in (0.0, 1.6, 3.2, 4.8):
        rbox(p + "_Trim", M, 0, 0, z + 0.1, W, D, 0.2, 0.05)
    # the arched crown: a half-round of narra slabs
    n = 15
    for i in range(n):
        a = math.pi * (i + 0.5) / n
        rbox(p + "_Trim", M, -(W / 2 - 0.1) * math.cos(a), 0, H - 0.1 + 0.55 * math.sin(a), 0.62, D, 0.24, 0.05, rot=(0, -math.atan2(0.55 * math.cos(a), (W / 2 - 0.1) * math.sin(a)), 0))
    rbox(p + "_Trim", M, 0, 0, H + 0.62, 0.7, D, 0.3, 0.1)
    # books on the shelves (varied heights and a lean)
    books = ("BookA", "BookB", "BookC", "BookD")
    for r, z0 in enumerate((0.2, 1.8, 3.4)):
        x = -W / 2 + 0.35
        k = 0
        while x < W / 2 - 0.6:
            w = 0.22 + 0.06 * ((k * 3 + r) % 3)
            h = 1.0 + 0.22 * ((k * 5 + r * 2) % 4)
            lean = 0.18 if (k + r) % 7 == 0 else 0.0
            rbox(p + "_" + books[(k + r) % 4], M, x + w / 2, 0.05, z0 + h / 2, w, 0.8, h, 0.03, rot=(0, lean, 0))
            x += w + 0.02 + (0.25 if lean else 0.0)
            k += 1
    # top-right shelf (z 4.8): a globe on a stand and the firefly jar
    z0 = 5.0
    cyl(p + "_Brass", M, -1.0, 0.0, z0, z0 + 0.12, 0.45, 16)
    rod(p + "_Brass", M, (-1.0, 0.0, z0 + 0.1), (-1.0, 0.0, z0 + 0.55), 0.06, 6)
    ell(p + "_Globe", M, -1.0, 0.0, z0 + 0.95, 0.45, 0.45, 0.45, 2)
    rod(p + "_Brass", M, (-1.45, 0.0, z0 + 0.7), (-0.55, 0.0, z0 + 1.2), 0.04, 5)
    cyl(p + "_Glass", M, 1.0, 0.0, z0, z0 + 0.95, 0.42, 14)                               # the firefly jar
    cyl(p + "_Brass", M, 1.0, 0.0, z0 + 0.95, z0 + 1.08, 0.38, 14)
    for fx, fy, fz in ((0.9, 0.1, z0 + 0.4), (1.15, -0.1, z0 + 0.6), (0.95, -0.12, z0 + 0.78), (1.12, 0.12, z0 + 0.3)):
        ell(p + "_Glow", M, fx, fy, fz, 0.09, 0.09, 0.09, 1)
    # a ladder leaning on the right side
    for sx in (-0.32, 0.32):
        rod(p + "_Trim", M, (W / 2 + 0.55 + sx * 0.4, 0.2, 0.0), (W / 2 - 0.1 + sx * 0.5, 0.45, 5.4), 0.07, 6)
    for k in range(7):
        t = (k + 0.7) / 7.6
        z = 5.4 * t
        xx = W / 2 + 0.55 - (0.65 * t)
        rod(p + "_Trim", M, (xx - 0.34 * (1 - 0.25 * t), 0.2 + 0.25 * t, z), (xx + 0.34 * (1 - 0.25 * t), 0.2 + 0.25 * t, z), 0.05, 5)


# ---------------------------------------------------------------- 8. monstera in a woven basket
def leaf(group, M, base, tip, width):
    """A big oval leaf from `base` to `tip` (a thin ellipsoid) with a pale midrib."""
    a, b = Vector(base), Vector(tip)
    d = b - a
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    bmesh.ops.scale(bm, vec=(width, 0.06, d.length / 2), verts=bm.verts)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ q, verts=bm.verts)
    _flush(group, bm, M)
    rod(group + "Dark", M, base, tip, 0.03, 4)


def monstera(M):
    p = "Monstera"
    rings = 9
    for k in range(rings):                                                              # the basket: rings of cane, woven look from alternating radii
        z = 0.15 + k * 0.2
        rad = 1.0 + 0.12 * math.sin(k / (rings - 1) * math.pi)
        cyl(p + "_Basket", M, 0, 0, z, z + 0.17, rad + (0.04 if k % 2 else 0.0), 18)
    cyl(p + "_Soil", M, 0, 0, 1.85, 1.95, 0.95, 16)
    for sx in (-1, 1):                                                                  # two cane handles on the basket
        rod(p + "_Basket", M, (sx * 1.1, 0.0, 1.55), (sx * 1.2, 0.0, 1.0), 0.06, 5)
    rod(p + "_LeafDark", M, (0, 0, 1.9), (0.1, 0.05, 5.6), 0.11, 6, r1=0.06)             # the trunk
    # leaves spiral up the trunk, big and oval, each tilted out and up (fiddle-leaf style)
    n = 11
    for i in range(n):
        t = i / (n - 1)
        z = 2.3 + 3.2 * t
        ang = i * 2.4
        reach = 1.7 - 0.9 * t
        base = (0.08 * t, 0.04 * t, z)
        tip = (reach * math.cos(ang), reach * math.sin(ang), z + 0.9 - 0.2 * t)
        leaf(p + "_Leaf" if i % 3 else p + "_LeafDark", M, base, tip, 0.62 - 0.12 * t)
    leaf(p + "_Leaf", M, (0.1, 0.05, 5.5), (0.2, 0.1, 6.7), 0.55)                       # the crown


PIECES = (
    ("PeacockLoveseat", peacock_loveseat), ("PeacockChair", peacock_chair), ("BanigRug", banig_rug), ("TinikTable", tinik_table),
    ("CapizLamp", capiz_lamp), ("TeaTable", tea_table), ("Bookcase", bookcase), ("Monstera", monstera),
)


# ---------------------------------------------------------------- meshes
def part_color(group, scheme):
    part = group.split("_", 1)[1]
    if part == "Accent":
        return SCHEMES[scheme]["Accent"]
    if part == "Trim":
        return SCHEMES[scheme]["Trim"]
    return NATURAL.get(part, "CCCCCC")


def make_objects(scheme, name_prefix=""):
    objs = []
    for group, parts in G.items():
        verts, faces = [], []
        for (v, f) in parts:
            o = len(verts)
            verts.extend(v)
            faces.extend([tuple(i + o for i in face) for face in f])
        me = bpy.data.meshes.new(name_prefix + group + "_mesh")
        me.from_pydata(verts, [], faces)
        me.update()
        ob = bpy.data.objects.new(name_prefix + group, me)
        bpy.context.collection.objects.link(ob)
        key = "dx_" + group.lower()
        c.PALETTE[key] = part_color(group, scheme)
        mat = c.material(name_prefix + group + "_mat", key)
        if group.endswith("_Glow") or group.endswith("_Capiz"):
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Emission Color"].default_value = c.hex_to_rgba(NATURAL["Glow"])
            bsdf.inputs["Emission Strength"].default_value = 2.2 if group.endswith("_Glow") else 0.5
        ob.data.materials.append(mat)
        objs.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth()
    return objs


# ---------------------------------------------------------------- 1) export: the eight pieces in a row
reset()
SP = 10.5
for i, (name, fn) in enumerate(PIECES):
    fn(Matrix.Translation((i * SP, 0, 0)))
objs = make_objects("Capiz Cream")
print("COZY2 triangles", c.triangle_count(objs))
per = {}
for o in objs:
    per[o.name.split("_")[0]] = per.get(o.name.split("_")[0], 0) + c.triangle_count([o])
print("per piece:", per)
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "Decor_Cozy.glb"), objs)
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no render)")
    raise SystemExit


# ---------------------------------------------------------------- 2) previews: a living-room corner in two shop colour schemes
def room(scheme, wall_hex, floor_hex, out_name):
    reset()
    Mz = lambda x, y, rz=0.0: Matrix.Translation((x, y, 0)) @ Matrix.Rotation(rz, 4, "Z")
    banig_rug(Mz(0.0, 3.2))
    peacock_loveseat(Mz(-0.6, -2.3))
    peacock_chair(Mz(6.4, 2.6, -0.9))
    tinik_table(Mz(0.0, 3.0))
    capiz_lamp(Mz(-5.8, -3.0))
    tea_table(Mz(-5.2, 3.4))
    bookcase(Mz(8.2, -3.6))
    monstera(Mz(-9.0, -2.4))
    objs = make_objects(scheme)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.82, 0.7, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    # the shop: a back wall with a window glow, a left wall, a wooden floor
    def slab(name, size, loc, hexcol, rough=0.8):
        ob = c.box(name, size, loc)
        m = bpy.data.materials.new(name + "m")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = c.hex_to_rgba(hexcol)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = rough
        ob.data.materials.append(m)
        return ob
    slab("floor", (34, 24, 0.3), (0, 2, -0.15), floor_hex, 0.6)
    for k in range(9):                                                              # plank lines
        slab("plank%d" % k, (34, 0.05, 0.02), (0, -9 + k * 2.6, 0.01), "5A3B26", 0.7)
    slab("wall", (34, 0.5, 14), (0, -7.0, 7.0), wall_hex)
    slab("sidewall", (0.5, 24, 14), (-14.5, 2, 7.0), wall_hex)
    slab("baseboard", (34, 0.6, 0.7), (0, -6.6, 0.35), "7A4A2E", 0.5)
    for k, hx in enumerate((-3, 4, 11)):                                            # three tall windows with warm light
        win = slab("win%d" % k, (3.0, 0.08, 7.0), (hx, -6.7, 6.5), "FFE9B0", 0.3)
        wm = win.data.materials[0].node_tree.nodes["Principled BSDF"]
        wm.inputs["Emission Color"].default_value = c.hex_to_rgba("FFE9B0")
        wm.inputs["Emission Strength"].default_value = 6.0
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 1.6
    so = bpy.data.objects.new("Sun", sd)
    bpy.context.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0, math.radians(25))
    ld = bpy.data.lights.new("Fill", "AREA")
    ld.energy = 900
    ld.size = 10
    lo = bpy.data.objects.new("Fill", ld)
    bpy.context.collection.objects.link(lo)
    lo.location = (0, 14, 14)
    lo.rotation_euler = (mathutils.Vector((0, 0, 2)) - lo.location).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.collection.objects.link(cam)
    cam.data.lens = 34
    cam.location = (3.0, 21.0, 10.5)
    cam.rotation_euler = (mathutils.Vector((-0.5, 0.0, 3.2)) - mathutils.Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(c.OUT_PREVIEWS, out_name)
    bpy.ops.render.render(write_still=True)


room("Capiz Cream", "EFE3C9", "B88B5A", "Decor_Cozy_Room_Cream.png")
room("Canal Teal", "BFD8D6", "C8A878", "Decor_Cozy_Room_Teal.png")
print("done")
