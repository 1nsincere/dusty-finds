"""Universal Shop Shell v2: a Filipino shophouse (Bahay na bato / Escolta feel), plain light-grey and relief-only so ANY palette looks good
(Blender 5.x, headless).  v1 (the barn-like gable box) is kept as shop_universal_v1_barn.py.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/shop_universal.py
Writes assets/models/ShopU_Base.glb, ShopU_BackRoom.glb, ShopU_Decor.glb and preview renders assets/previews/ShopU_*.png.
DF_SKIP_RENDER=1 exports without renders.

Look: rusticated ground floor, upper storey that overhangs on corbels, a balcony over a columned porch, real windows (frame, sash, glass,
lintel, sill, louvred shutters), a low HIP roof with a dormer and a cupola. No barn gable.

Three INDEPENDENT modules:
  ShopU_Base     the standard 40 x 40 shop (same plot size and coordinates as shop.py). Roof = front hip + two side slopes; the rear hip is
                 a removable cap (Shop_BackCap, Shop_BackCapTrim, Shop_BackCapRoof).
  ShopU_BackRoom the extension, 24 deep: same side walls, 8-stud window rhythm, belt, cornice and roof slopes. Hide the cap, add this module.
  ShopU_Decor    stock exterior decor (plants, bench, crates, lanterns, blade sign, A-board), fixed colours.

Coordinates: plot base units, 1 stud = 1 unit, Z up; the door/front is +Y; the base back wall is y = -20 (open, gameplay).
Tint slots (plain light grey, tinted in Studio): Walls (Wall), Trim, Accent. Fixed neutrals: Glass, Roof, Decor*. Floor = the existing slab.
Up* groups and Roof are hidden when the player walks in (RoofController).
"""

import math
import os
import sys

import bmesh
import bpy
import mathutils

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

c.reset_scene()

F0 = 0.5            # plot floor top
H1 = 12.5           # ground floor wall top / upper floor level
H2 = 22.0           # upper storey top
OUT = 20.2          # outer face of the ground side walls
T = 1.2             # wall thickness
UP = 0.8            # how far the upper storey overhangs the ground floor
UO = OUT + UP       # upper storey outer face (sides)
BACK = -20.0        # base back wall plane (ground)
FRONT = 20.2
EXT_DEPTH = 24.0
E = 22.4            # roof half-width at the eaves
RISE = 9.5
PEAK = H2 + RISE
ROOF_T = 0.9
YF = FRONT + UP + 1.4          # front eave line
YRB = BACK - UP - 1.4          # base rear eave line
Y0 = BACK - EXT_DEPTH          # extension back wall plane (ground)
YRE = Y0 - UP - 1.4            # extension rear eave line
YR0 = YF - E                   # front ridge end (= 0.2)

BASE, EXT, DEC = {}, {}, {}


def _add(store, group, verts, faces):
    store.setdefault(group, []).append((verts, faces))


def bx(store, group, x0, x1, y0, y1, z0, z1):
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    if z1 < z0:
        z0, z1 = z1, z0
    if x1 - x0 < 1e-4 or y1 - y0 < 1e-4 or z1 - z0 < 1e-4:
        return
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    _add(store, group, v, f)


def slab_poly(store, group, pts, thick):
    """pts: 3D points of a flat (planar) polygon = the TOP face; solid extends `thick` straight down."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if area < 0:
        pts = list(reversed(pts))
    v = [tuple(p) for p in pts] + [(p[0], p[1], p[2] - thick) for p in pts]
    f = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, n + i, n + j, j))
    _add(store, group, v, f)


def prism_yz(store, group, pts, x0, x1):
    """Polygon in (y, z) extruded along X."""
    n = len(pts)
    v = [(x0, p[0], p[1]) for p in pts] + [(x1, p[0], p[1]) for p in pts]
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    _add(store, group, v, f)


def prism_xz(store, group, pts, y0, y1):
    """Polygon in (x, z) extruded along Y."""
    n = len(pts)
    v = [(p[0], y0, p[1]) for p in pts] + [(p[0], y1, p[1]) for p in pts]
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    _add(store, group, v, f)


def cyl(store, group, cx, cy, z0, z1, r, n=10):
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z1) for i in range(n)]
    slab_poly(store, group, pts, z1 - z0)


def ico(store, group, cx, cy, cz, r, sub=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    v = [(vv.co.x + cx, vv.co.y + cy, vv.co.z + cz) for vv in bm.verts]
    f = [tuple(vv.index for vv in ff.verts) for ff in bm.faces]
    bm.free()
    _add(store, group, v, f)


def fr(f0, f1, out, d0, d1):
    """face range: from d0 to d1 proud of the OUTER face (out = +1: outer face is f1, out = -1: outer face is f0)."""
    return (f1 + d0, f1 + d1) if out > 0 else (f0 - d1, f0 - d0)


def mk(store, axis):
    """Box helper: a = coordinate along the wall, f = across the wall."""
    def b(group, a0, a1, f0, f1, z0, z1):
        if axis == "x":
            bx(store, group, f0, f1, a0, a1, z0, z1)
        else:
            bx(store, group, a0, a1, f0, f1, z0, z1)
    return b


# ---------------------------------------------------------------- walls with real openings
def wall(store, group, axis, f0, f1, a0, a1, z0, z1, openings=(), out=1, courses=0.0):
    """Solid wall with rectangular openings; optional horizontal masonry courses (reveals) on the outer face."""
    b = mk(store, axis)
    rects, cur = [], a0
    for (oa0, oa1, zb, zt) in sorted(openings):
        rects += [(cur, oa0, z0, z1), (oa0, oa1, z0, zb), (oa0, oa1, zt, z1)]
        cur = oa1
    rects.append((cur, a1, z0, z1))
    o0, o1 = fr(f0, f1, out, 0.0, 0.1)
    for (r0, r1, zf, zt) in rects:
        b(group, r0, r1, f0, f1, zf, zt)
        if courses > 0 and r1 - r0 > 0.3:
            z = zf + courses
            while z < zt - 0.25:
                b(group, r0, r1, o0, o1, z - 0.07, z + 0.07)
                z += courses


def window(store, tg, gg, sg, axis, f0, f1, a0, a1, zb, zt, out, cols=None, sill=True, cap=True, shutter=0.0, sx=None):
    """A real window in an opening: frame inside the reveal, sash bars, recessed glass, architrave, lintel cap, sill, optional louvred shutters."""
    b = mk(store, axis)
    mid = (f0 + f1) / 2
    fw = 0.35
    e0, e1 = fr(f0, f1, out, -(f1 - f0), 0.2)        # frame bars: the full wall depth plus 0.2 outside
    if out < 0:
        e0, e1 = f0 - 0.2, f1
    else:
        e0, e1 = f0, f1 + 0.2
    # frame ring inside the opening
    b(tg, a0, a0 + fw, e0, e1, zb, zt)
    b(tg, a1 - fw, a1, e0, e1, zb, zt)
    b(tg, a0 + fw, a1 - fw, e0, e1, zb, zb + fw)
    b(tg, a0 + fw, a1 - fw, e0, e1, zt - fw, zt)
    # glass, recessed
    b(gg, a0 + fw, a1 - fw, mid - 0.06, mid + 0.06, zb + fw, zt - fw)
    # sash bars
    ncols = cols if cols is not None else max(1, int(round((a1 - a0) / 2.4)))
    for i in range(1, ncols):
        a = a0 + (a1 - a0) * i / ncols
        b(tg, a - 0.11, a + 0.11, mid - 0.17, mid + 0.17, zb + fw, zt - fw)
    zr = zb + (zt - zb) * 0.7
    b(tg, a0 + fw, a1 - fw, mid - 0.17, mid + 0.17, zr - 0.1, zr + 0.1)
    # architrave around the opening (proud)
    p0, p1 = fr(f0, f1, out, 0.0, 0.5)
    b(tg, a0 - 0.55, a0, p0, p1, zb - 0.1, zt + 0.55)
    b(tg, a1, a1 + 0.55, p0, p1, zb - 0.1, zt + 0.55)
    b(tg, a0 - 0.55, a1 + 0.55, p0, p1, zt, zt + 0.55)
    if cap:
        c0, c1 = fr(f0, f1, out, 0.0, 0.9)
        b(tg, a0 - 0.95, a1 + 0.95, c0, c1, zt + 0.55, zt + 0.95)
        d0, d1 = fr(f0, f1, out, 0.0, 1.2)
        b(tg, a0 - 1.15, a1 + 1.15, d0, d1, zt + 0.95, zt + 1.2)
    if sill:
        s0, s1 = fr(f0, f1, out, 0.0, 1.0)
        b(tg, a0 - 0.9, a1 + 0.9, s0, s1, zb - 0.6, zb - 0.2)
        t0, t1 = fr(f0, f1, out, 0.0, 0.5)
        b(tg, a0 - 0.5, a0 - 0.2, t0, t1, zb - 1.3, zb - 0.6)
        b(tg, a1 + 0.2, a1 + 0.5, t0, t1, zb - 1.3, zb - 0.6)
    if shutter > 0 and sg:
        h0, h1 = fr(f0, f1, out, 0.05, 0.3)
        for (sa0, sa1) in ((a0 - 0.55 - shutter, a0 - 0.55), (a1 + 0.55, a1 + 0.55 + shutter)):
            b(sg, sa0, sa0 + 0.14, h0, h1, zb - 0.1, zt + 0.5)
            b(sg, sa1 - 0.14, sa1, h0, h1, zb - 0.1, zt + 0.5)
            z = zb
            while z < zt + 0.3:
                b(sg, sa0 + 0.14, sa1 - 0.14, h0 + 0.03, h1 - 0.05, z, z + 0.3)
                z += 0.62


# ---------------------------------------------------------------- shared building pieces
WIN_YS = (12.0, 4.0, -4.0, -12.0, -28.0, -36.0)     # one 8-stud rhythm: the first four belong to the base, the last two to the extension
POST_YS = (8.0, 0.0, -8.0, -16.0, -24.0, -32.0, -40.0)


def side_walls(store, ground, upper):
    """Both side walls. ground = (y_lo, y_hi), upper = (y_lo, y_hi). Same window rhythm in every module."""
    for sx in (-1, 1):
        out = sx
        # ground
        g_lo, g_hi = ground
        lo, hi = ((OUT - T, OUT) if sx > 0 else (-OUT, -OUT + T))
        ops = [(wy - 1.8, wy + 1.8, 5.4, 10.2) for wy in WIN_YS if g_lo + 1.2 < wy - 1.8 and wy + 1.8 < g_hi - 1.2]
        wall(store, "Walls", "x", lo, hi, g_lo, g_hi, F0, H1, ops, out=out, courses=2.0)
        for (a0, a1, zb, zt) in ops:
            window(store, "Trim", "Glass", None, "x", lo, hi, a0, a1, zb, zt, out, cols=2)
        # upper (overhangs by UP)
        u_lo, u_hi = upper
        lo, hi = ((UO - T, UO) if sx > 0 else (-UO, -UO + T))
        ops = [(wy - 1.8, wy + 1.8, 15.4, 20.2) for wy in WIN_YS if u_lo + 1.2 < wy - 1.8 and wy + 1.8 < u_hi - 1.2]
        wall(store, "UpWalls", "x", lo, hi, u_lo, u_hi, H1, H2, ops, out=out)
        for (a0, a1, zb, zt) in ops:
            window(store, "UpTrim", "UpGlass", "UpAccent", "x", lo, hi, a0, a1, zb, zt, out, cols=2, shutter=1.0)
            # ventanilla balusters under the window
            o0, o1 = fr(lo, hi, out, 0.0, 0.3)
            b = mk(store, "x")
            b("UpTrim", a0 - 0.5, a1 + 0.5, o0, o1, 13.9, 14.2)
            n = 7
            for i in range(n):
                a = a0 - 0.2 + (a1 - a0 + 0.4) * i / (n - 1)
                b("UpTrim", a - 0.1, a + 0.1, o0, o1, 12.9, 13.9)
            b("UpTrim", a0 - 0.5, a1 + 0.5, o0, o1, 12.7, 12.95)
        # posts between the windows
        for py in POST_YS:
            if u_lo + 0.6 < py < u_hi - 0.6:
                p0, p1 = fr(lo, hi, out, 0.0, 0.35)
                mk(store, "x")("UpTrim", py - 0.35, py + 0.35, p0, p1, H1, H2 - 0.7)


def bands(store, y_hi, y_lo, front, back, tgroup_ground="Trim", tgroup_up="UpTrim", tgroup_back="BackCapTrim"):
    """Plinth at the foot, the ledge under the overhang, brackets, and the cornice under the roof."""
    # plinth
    for sx in (-1, 1):
        x0, x1 = (OUT, OUT + 0.35) if sx > 0 else (-OUT - 0.35, -OUT)
        bx(store, tgroup_ground, x0, x1, y_lo, y_hi, F0, F0 + 1.2)
    # ledge under the overhang (sides)
    for sx in (-1, 1):
        x0, x1 = (OUT, UO + 0.15) if sx > 0 else (-UO - 0.15, -OUT)
        bx(store, tgroup_ground, x0, x1, y_lo, y_hi, H1 - 0.7, H1)
        # brackets under the ledge every 4 studs
        yy = math.ceil((y_lo + 1.0) / 4.0) * 4.0
        while yy < y_hi - 1.0:
            xa, xb = (OUT, UO) if sx > 0 else (-UO, -OUT)
            bx(store, tgroup_ground, xa, xb, yy - 0.3, yy + 0.3, H1 - 1.8, H1 - 0.7)
            yy += 4.0
    # cornice (sides)
    for sx in (-1, 1):
        x0, x1 = (UO, UO + 1.2) if sx > 0 else (-UO - 1.2, -UO)
        bx(store, tgroup_up, x0, x1, y_lo, y_hi, H2 - 0.8, H2)
    if back:
        grp_t = tgroup_back
        bx(store, grp_t, -UO - 1.2, UO + 1.2, y_lo - UP - 1.2, y_lo - UP, H2 - 0.8, H2)
        bx(store, grp_t, -UO - 0.15, UO + 0.15, y_lo - UP - 0.15, y_lo, H1 - 0.7, H1)
    if front:
        bx(store, tgroup_up, -UO - 1.2, UO + 1.2, y_hi + UP, y_hi + UP + 1.2, H2 - 0.8, H2)


def pilaster(store, x, y, face, group="Trim"):
    """Stepped Art Deco pilaster at a ground-floor corner."""
    for (w, pr, h0, h1) in ((2.8, 0.4, F0, H1 - 0.7), (2.0, 0.8, F0 + 0.6, H1 - 1.2), (1.2, 1.1, F0 + 1.2, H1 - 1.7)):
        if face > 0:
            bx(store, group, x - w / 2, x + w / 2, y, y + pr, h0, h1)
        else:
            bx(store, group, x - w / 2, x + w / 2, y - pr, y, h0, h1)


def rz(d):
    """roof surface height at horizontal distance d from the eave line"""
    return H2 + d * RISE / E


# ================================================================ BASE MODULE
side_walls(BASE, (BACK, 19.0), (BACK - UP, 19.8))

# front wall, ground: door + two display windows (rusticated)
D0, D1 = -4.0, 4.0
wall(BASE, "Walls", "y", 19.0, FRONT, -OUT, OUT, F0, H1, [(D0, D1, F0, 9.6), (-16.0, -7.0, 3.2, 9.6), (7.0, 16.0, 3.2, 9.6)], out=1, courses=2.0)
for (a0, a1) in ((-16.0, -7.0), (7.0, 16.0)):
    window(BASE, "Trim", "Glass", None, "y", 19.0, FRONT, a0, a1, 3.2, 9.6, 1, cols=4, sill=True, cap=False)
    # Accent awning on two brackets
    bx(BASE, "Accent", a0 - 0.7, a1 + 0.7, FRONT + 0.2, FRONT + 2.4, 10.2, 10.55)
    bx(BASE, "Accent", a0 - 0.7, a1 + 0.7, FRONT + 2.3, FRONT + 2.5, 9.75, 10.55)
    for a in (a0 + 0.3, a1 - 0.3):
        bx(BASE, "Trim", a - 0.14, a + 0.14, FRONT + 0.2, FRONT + 2.3, 9.9, 10.2)
# door surround (Accent) and the sign frame under the balcony
bx(BASE, "Accent", D0 - 0.7, D0, FRONT, FRONT + 0.55, F0, 10.2)
bx(BASE, "Accent", D1, D1 + 0.7, FRONT, FRONT + 0.55, F0, 10.2)
bx(BASE, "Accent", D0 - 0.7, D1 + 0.7, FRONT, FRONT + 0.55, 9.6, 10.2)
SG = (-6.0, 6.0, 10.5, 11.7)
bx(BASE, "Accent", SG[0], SG[1], FRONT, FRONT + 0.5, SG[2], SG[2] + 0.3)
bx(BASE, "Accent", SG[0], SG[1], FRONT, FRONT + 0.5, SG[3] - 0.3, SG[3])
bx(BASE, "Accent", SG[0], SG[0] + 0.3, FRONT, FRONT + 0.5, SG[2], SG[3])
bx(BASE, "Accent", SG[1] - 0.3, SG[1], FRONT, FRONT + 0.5, SG[2], SG[3])

# front wall, upper storey (overhangs by UP): two windows and a tall balcony door
UF0, UF1 = 19.8, FRONT + UP
wall(BASE, "UpWalls", "y", UF0, UF1, -UO, UO, H1, H2, [(-14.0, -8.0, 15.4, 20.2), (8.0, 14.0, 15.4, 20.2), (-3.0, 3.0, 12.9, 20.2)], out=1)
for (a0, a1) in ((-14.0, -8.0), (8.0, 14.0)):
    window(BASE, "UpTrim", "UpGlass", "UpAccent", "y", UF0, UF1, a0, a1, 15.4, 20.2, 1, cols=2, shutter=1.1)
    # ventanilla balusters
    o0, o1 = fr(UF0, UF1, 1, 0.0, 0.3)
    bx(BASE, "UpTrim", a0 - 0.5, a1 + 0.5, o0, o1, 13.9, 14.2)
    bx(BASE, "UpTrim", a0 - 0.5, a1 + 0.5, o0, o1, 12.7, 12.95)
    for i in range(9):
        a = a0 - 0.2 + (a1 - a0 + 0.4) * i / 8
        bx(BASE, "UpTrim", a - 0.1, a + 0.1, o0, o1, 12.9, 13.9)
window(BASE, "UpTrim", "UpGlass", None, "y", UF0, UF1, -3.0, 3.0, 12.9, 20.2, 1, cols=2, sill=False)
# corner posts and the ledge/cornice
for sx in (-1, 1):
    bx(BASE, "UpTrim", sx * UO - 0.5 if sx > 0 else sx * UO - 0.3, sx * UO + 0.3 if sx > 0 else sx * UO + 0.5, UF0, UF1 + 0.3, H1, H2 - 0.7)
bands(BASE, 19.8, BACK - UP, True, False)
bx(BASE, "Trim", -UO - 0.15, UO + 0.15, FRONT, UF1 + 0.15, H1 - 0.7, H1)   # ledge across the front
yy = -16.0
for xx in (-18.0, -14.0, -10.0, 10.0, 14.0, 18.0):
    bx(BASE, "Trim", xx - 0.3, xx + 0.3, FRONT, UF1, H1 - 1.8, H1 - 0.7)
# ground corner pilasters + plinth beside the door
for x in (-OUT + 1.0, OUT - 1.0):
    pilaster(BASE, x, FRONT, 1)
bx(BASE, "Trim", -OUT - 0.35, D0 - 0.7, FRONT, FRONT + 0.35, F0, F0 + 1.2)
bx(BASE, "Trim", D1 + 0.7, OUT + 0.35, FRONT, FRONT + 0.35, F0, F0 + 1.2)

# porch columns + balcony over the door
BX, BY = 8.6, FRONT + 3.4
bx(BASE, "Trim", -BX, BX, FRONT, BY, 11.9, 12.7)                                 # balcony slab
for sx in (-1, 1):
    cx = sx * 7.6
    cyy = FRONT + 3.0
    bx(BASE, "Trim", cx - 0.8, cx + 0.8, cyy - 0.8, cyy + 0.8, F0, F0 + 0.5)    # base
    bx(BASE, "Trim", cx - 0.55, cx + 0.55, cyy - 0.55, cyy + 0.55, F0 + 0.5, 11.2)
    bx(BASE, "Trim", cx - 0.8, cx + 0.8, cyy - 0.8, cyy + 0.8, 11.2, 11.9)      # capital
# balustrade
xx = -BX + 0.3
while xx <= BX - 0.2:
    bx(BASE, "Trim", xx - 0.14, xx + 0.14, BY - 0.35, BY - 0.07, 12.7, 13.7)
    xx += 1.08
for sx in (-1, 1):
    yy = FRONT + UP + 0.4
    while yy < BY - 0.3:
        bx(BASE, "Trim", sx * (BX - 0.3) - 0.14, sx * (BX - 0.3) + 0.14, yy - 0.14, yy + 0.14, 12.7, 13.7)
        yy += 1.0
bx(BASE, "Trim", -BX, BX, BY - 0.45, BY, 13.7, 14.05)
for sx in (-1, 1):
    bx(BASE, "Trim", sx * BX - (0.45 if sx > 0 else 0.0), sx * BX + (0.0 if sx > 0 else 0.45), FRONT + UP, BY, 13.7, 14.05)

# ---- roof: front hip + two side slopes (rear hip is the removable BackCapRoof)
slab_poly(BASE, "Roof", [(-E, YF, H2), (E, YF, H2), (0.0, YR0, PEAK)], ROOF_T)
slab_poly(BASE, "Roof", [(-E, YF, H2), (0.0, YR0, PEAK), (-E, YRB, H2)], ROOF_T)
slab_poly(BASE, "Roof", [(E, YF, H2), (0.0, YR0, PEAK), (E, YRB, H2)], ROOF_T)
slab_poly(BASE, "BackCapRoof", [(-E, YRB, H2), (E, YRB, H2), (0.0, YR0, PEAK)], ROOF_T)

# ---- dormer on the front hip
DY0, DY1 = YF - 3.6, YF - 9.0         # front face / back
DW = 2.7
ZD0, ZD1 = H2, 27.4
wall(BASE, "UpWalls", "y", DY0 - 0.6, DY0, -DW, DW, ZD0, ZD1, [(-1.5, 1.5, 24.3, 26.8)], out=1)
window(BASE, "UpTrim", "UpGlass", None, "y", DY0 - 0.6, DY0, -1.5, 1.5, 24.3, 26.8, 1, cols=2, cap=False)
bx(BASE, "UpWalls", -DW, -DW + 0.6, DY1, DY0, ZD0, ZD1)
bx(BASE, "UpWalls", DW - 0.6, DW, DY1, DY0, ZD0, ZD1)
bx(BASE, "UpWalls", -DW, DW, DY1, DY1 + 0.6, ZD0, ZD1)
prism_xz(BASE, "UpWalls", [(-DW, ZD1), (DW, ZD1), (0.0, ZD1 + 1.5)], DY0 - 0.6, DY0)
slab_poly(BASE, "Roof", [(-DW - 0.6, DY0 + 0.5, ZD1), (0.0, DY0 + 0.5, ZD1 + 1.9), (0.0, DY1, ZD1 + 1.9), (-DW - 0.6, DY1, ZD1)], 0.5)
slab_poly(BASE, "Roof", [(DW + 0.6, DY0 + 0.5, ZD1), (0.0, DY0 + 0.5, ZD1 + 1.9), (0.0, DY1, ZD1 + 1.9), (DW + 0.6, DY1, ZD1)], 0.5)
bx(BASE, "UpTrim", -DW - 0.7, DW + 0.7, DY0 - 0.6, DY0 + 0.35, ZD1 - 0.35, ZD1)

# ---- cupola at the apex
CY = YR0
CW = 1.9
CZ0, CZ1 = PEAK - 1.3, PEAK + 2.1
bx(BASE, "UpWalls", -CW, CW, CY - CW, CY + CW, CZ0, CZ1)
bx(BASE, "UpTrim", -CW - 0.25, CW + 0.25, CY - CW - 0.25, CY + CW + 0.25, CZ1 - 0.35, CZ1 + 0.15)
bx(BASE, "UpTrim", -CW - 0.25, CW + 0.25, CY - CW - 0.25, CY + CW + 0.25, PEAK + 0.2, PEAK + 0.55)
for (axis, sgn) in (("y", 1), ("y", -1), ("x", 1), ("x", -1)):
    zb, zt = PEAK + 0.55, CZ1 - 0.35
    if axis == "y":
        yf = CY + sgn * CW
        f0_, f1_ = (yf - 0.05, yf + 0.25) if sgn > 0 else (yf - 0.25, yf + 0.05)
        bx(BASE, "UpGlass", -1.1, 1.1, f0_ + 0.1, f1_ - 0.1, zb, zt)
        bx(BASE, "UpTrim", -1.35, -1.1, f0_, f1_, zb - 0.1, zt + 0.1)
        bx(BASE, "UpTrim", 1.1, 1.35, f0_, f1_, zb - 0.1, zt + 0.1)
        bx(BASE, "UpTrim", -1.35, 1.35, f0_, f1_, zb - 0.2, zb)
        bx(BASE, "UpTrim", -1.35, 1.35, f0_, f1_, zt, zt + 0.15)
        bx(BASE, "UpTrim", -0.07, 0.07, f0_, f1_, zb, zt)
    else:
        xf = sgn * CW
        f0_, f1_ = (xf - 0.05, xf + 0.25) if sgn > 0 else (xf - 0.25, xf + 0.05)
        bx(BASE, "UpGlass", f0_ + 0.1, f1_ - 0.1, CY - 1.1, CY + 1.1, zb, zt)
        bx(BASE, "UpTrim", f0_, f1_, CY - 1.35, CY - 1.1, zb - 0.1, zt + 0.1)
        bx(BASE, "UpTrim", f0_, f1_, CY + 1.1, CY + 1.35, zb - 0.1, zt + 0.1)
        bx(BASE, "UpTrim", f0_, f1_, CY - 1.35, CY + 1.35, zb - 0.2, zb)
        bx(BASE, "UpTrim", f0_, f1_, CY - 1.35, CY + 1.35, zt, zt + 0.15)
        bx(BASE, "UpTrim", f0_, f1_, CY - 0.07, CY + 0.07, zb, zt)
CR = CW + 0.9
ZT = CZ1 + 1.7
for pts in ([(-CR, CY - CR, CZ1 + 0.15), (CR, CY - CR, CZ1 + 0.15), (0.0, CY, ZT)],
            [(CR, CY - CR, CZ1 + 0.15), (CR, CY + CR, CZ1 + 0.15), (0.0, CY, ZT)],
            [(CR, CY + CR, CZ1 + 0.15), (-CR, CY + CR, CZ1 + 0.15), (0.0, CY, ZT)],
            [(-CR, CY + CR, CZ1 + 0.15), (-CR, CY - CR, CZ1 + 0.15), (0.0, CY, ZT)]):
    slab_poly(BASE, "Roof", pts, 0.3)
bx(BASE, "UpTrim", -0.12, 0.12, CY - 0.12, CY + 0.12, ZT - 0.1, ZT + 1.0)

# ---- BackCap: upper back wall + trim + rear hip (hidden once the Back Room exists)
UB0, UB1 = BACK - UP, BACK + 0.4
wall(BASE, "BackCap", "y", UB0, UB1, -UO, UO, H1, H2, [], out=-1)
bx(BASE, "BackCapTrim", -UO - 0.15, UO + 0.15, UB0 - 0.15, UB1, H1 - 0.7, H1)
bx(BASE, "BackCapTrim", -UO - 1.2, UO + 1.2, UB0 - 1.2, UB0, H2 - 0.8, H2)
for sx in (-1, 1):
    bx(BASE, "BackCapTrim", sx * UO - 0.5 if sx > 0 else sx * UO - 0.3, sx * UO + 0.3 if sx > 0 else sx * UO + 0.5, UB0 - 0.3, UB1, H1, H2 - 0.7)

# ================================================================ EXTENSION MODULE (Back Room)
side_walls(EXT, (Y0, BACK), (Y0 - UP, BACK - UP))
wall(EXT, "Walls", "y", Y0, Y0 + T, -OUT, OUT, F0, H1, [(-6.0, 6.0, 4.0, 9.6)], out=-1, courses=2.0)
window(EXT, "Trim", "Glass", None, "y", Y0, Y0 + T, -6.0, 6.0, 4.0, 9.6, -1, cols=4)
UE0, UE1 = Y0 - UP, Y0 - UP + T
wall(EXT, "UpWalls", "y", UE0, UE1, -UO, UO, H1, H2, [(-9.0, -3.0, 15.4, 20.2), (3.0, 9.0, 15.4, 20.2)], out=-1)
for (a0, a1) in ((-9.0, -3.0), (3.0, 9.0)):
    window(EXT, "UpTrim", "UpGlass", "UpAccent", "y", UE0, UE1, a0, a1, 15.4, 20.2, -1, cols=2, shutter=1.1)
for x in (-OUT + 1.0, OUT - 1.0):
    pilaster(EXT, x, Y0, -1)
bands(EXT, BACK - UP, Y0 - UP, False, True, tgroup_back="Trim")
for sx in (-1, 1):
    bx(EXT, "UpTrim", sx * UO - 0.5 if sx > 0 else sx * UO - 0.3, sx * UO + 0.3 if sx > 0 else sx * UO + 0.5, UE0 - 0.3, UE1, H1, H2 - 0.7)
YRE_RIDGE = YRE + E
slab_poly(EXT, "Roof", [(-E, YRB, H2), (0.0, YR0, PEAK), (0.0, YRE_RIDGE, PEAK), (-E, YRE, H2)], ROOF_T)
slab_poly(EXT, "Roof", [(E, YRB, H2), (0.0, YR0, PEAK), (0.0, YRE_RIDGE, PEAK), (E, YRE, H2)], ROOF_T)
slab_poly(EXT, "Roof", [(-E, YRE, H2), (E, YRE, H2), (0.0, YRE_RIDGE, PEAK)], ROOF_T)
bx(EXT, "Roof", -0.45, 0.45, YRE_RIDGE, YR0, PEAK - 0.25, PEAK + 0.35)

# ================================================================ DECOR MODULE (fixed colours)
# blade sign on the right corner pilaster
SX_ = OUT - 1.0
bx(DEC, "DecorBrass", SX_ - 0.1, SX_ + 0.1, FRONT + 1.1, FRONT + 2.9, 9.2, 9.45)         # arm
bx(DEC, "DecorBrass", SX_ - 0.1, SX_ + 0.1, FRONT + 1.1, FRONT + 1.3, 9.0, 9.45)
bx(DEC, "DecorBrass", SX_ - 0.05, SX_ + 0.05, FRONT + 2.2, FRONT + 2.25, 8.2, 9.2)
bx(DEC, "DecorBrass", SX_ - 0.05, SX_ + 0.05, FRONT + 2.85, FRONT + 2.9, 8.2, 9.2)
bx(DEC, "Accent", SX_ - 0.12, SX_ + 0.12, FRONT + 2.1, FRONT + 3.0, 6.6, 8.4)
bx(DEC, "DecorCloth", SX_ - 0.16, SX_ + 0.16, FRONT + 2.25, FRONT + 2.85, 6.95, 8.05)
# planters (terracotta pot + leaves) beside the windows
for x in (-15.4, -8.6, 8.6, 15.4):
    cyl(DEC, "DecorPot", x, FRONT + 1.3, F0, F0 + 1.3, 0.8, 10)
    cyl(DEC, "DecorPot", x, FRONT + 1.3, F0 + 1.3, F0 + 1.5, 0.95, 10)
    ico(DEC, "DecorLeaf", x, FRONT + 1.3, F0 + 2.4, 1.1)
    ico(DEC, "DecorLeaf", x + 0.5, FRONT + 1.0, F0 + 3.0, 0.75)
    ico(DEC, "DecorLeaf", x - 0.45, FRONT + 1.6, F0 + 2.9, 0.7)
# bench under the left window
bx(DEC, "DecorWood", -14.0, -10.0, FRONT + 0.8, FRONT + 2.0, F0 + 1.5, F0 + 1.75)
for x in (-13.6, -10.4):
    bx(DEC, "DecorWood", x - 0.15, x + 0.15, FRONT + 0.9, FRONT + 1.9, F0, F0 + 1.5)
bx(DEC, "DecorWood", -14.0, -10.0, FRONT + 0.8, FRONT + 0.95, F0 + 1.75, F0 + 3.0)
# crates and a sack under the right window
bx(DEC, "DecorWood", 10.0, 11.8, FRONT + 0.7, FRONT + 2.3, F0, F0 + 1.6)
bx(DEC, "DecorWood", 10.2, 11.6, FRONT + 0.9, FRONT + 2.1, F0 + 1.6, F0 + 2.8)
bx(DEC, "DecorWood", 12.0, 13.5, FRONT + 0.8, FRONT + 2.1, F0, F0 + 1.1)
ico(DEC, "DecorCloth", 12.9, FRONT + 1.0, F0 + 1.7, 0.75)
# lanterns under the balcony
for sx in (-1, 1):
    lx = sx * 5.0
    ly = FRONT + 2.0
    bx(DEC, "DecorBrass", lx - 0.03, lx + 0.03, ly - 0.03, ly + 0.03, 11.0, 11.9)
    bx(DEC, "DecorBrass", lx - 0.45, lx + 0.45, ly - 0.45, ly + 0.45, 10.75, 10.95)
    bx(DEC, "DecorLamp", lx - 0.33, lx + 0.33, ly - 0.33, ly + 0.33, 9.85, 10.75)
    bx(DEC, "DecorBrass", lx - 0.4, lx + 0.4, ly - 0.4, ly + 0.4, 9.65, 9.85)
    for (dx, dy) in ((-0.38, -0.38), (0.38, -0.38), (-0.38, 0.38), (0.38, 0.38)):
        bx(DEC, "DecorBrass", lx + dx - 0.04, lx + dx + 0.04, ly + dy - 0.04, ly + dy + 0.04, 9.85, 10.75)
# "open" A-board
AX = 5.8
prism_yz(DEC, "DecorSlate", [(FRONT + 2.2, F0), (FRONT + 2.4, F0), (FRONT + 1.6, F0 + 3.0), (FRONT + 1.4, F0 + 3.0)], AX - 0.9, AX + 0.9)
prism_yz(DEC, "DecorWood", [(FRONT + 0.6, F0), (FRONT + 0.8, F0), (FRONT + 1.6, F0 + 3.0), (FRONT + 1.4, F0 + 3.0)], AX - 0.9, AX + 0.9)
bx(DEC, "DecorWood", AX - 1.0, AX + 1.0, FRONT + 1.35, FRONT + 1.65, F0 + 3.0, F0 + 3.15)

# ================================================================ build meshes, materials
SLOT = {"Walls": "Wall", "UpWalls": "Wall", "BackCap": "Wall", "Trim": "Trim", "UpTrim": "Trim", "BackCapTrim": "Trim",
        "Accent": "Accent", "UpAccent": "Accent", "Glass": "Glass", "UpGlass": "Glass", "Roof": "Roof", "BackCapRoof": "Roof",
        "DecorWood": "DecorWood", "DecorPot": "DecorPot", "DecorLeaf": "DecorLeaf", "DecorBrass": "DecorBrass",
        "DecorLamp": "DecorLamp", "DecorSlate": "DecorSlate", "DecorCloth": "DecorCloth"}
MESHES = {"base": [], "ext": [], "dec": []}
PREFIX = {"base": "Shop", "ext": "BackRoom", "dec": "Decor"}


def build(store, key):
    for group, parts in store.items():
        verts, faces = [], []
        for (v, f) in parts:
            o = len(verts)
            verts.extend(v)
            faces.extend([tuple(i + o for i in face) for face in f])
        me = bpy.data.meshes.new(f"{PREFIX[key]}_{group}_mesh")
        me.from_pydata(verts, [], faces)
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(f"{PREFIX[key]}_{group}", me)
        bpy.context.collection.objects.link(ob)
        MESHES[key].append(ob)


build(BASE, "base")
build(EXT, "ext")
build(DEC, "dec")

ALBEDO = 0.84
MATS = {}


def lin(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def srgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4))


def make_mat(slot):
    m = bpy.data.materials.new("U_" + slot)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.8 if slot != "Glass" else 0.12
    MATS[slot] = m
    return m


def set_slot(slot, hexs, tinted):
    r, g, b = srgb(hexs)
    k = lin(ALBEDO) if tinted else 1.0
    node = MATS[slot].node_tree.nodes["Principled BSDF"]
    node.inputs["Base Color"].default_value = (lin(r) * k, lin(g) * k, lin(b) * k, 1)


FIXED = {"Glass": "B9D2DE", "Roof": "6B5B50", "DecorWood": "6B4A2E", "DecorPot": "C0603E", "DecorLeaf": "4F8A4B", "DecorBrass": "B58A3C",
         "DecorLamp": "FFD98A", "DecorSlate": "2E3A38", "DecorCloth": "D8C7A0"}
for slot in ("Wall", "Trim", "Accent", *FIXED.keys()):
    make_mat(slot)
for slot, hexs in FIXED.items():
    set_slot(slot, hexs, False)
lamp = MATS["DecorLamp"].node_tree.nodes["Principled BSDF"]
lamp.inputs["Emission Color"].default_value = (1.0, 0.75, 0.35, 1)
lamp.inputs["Emission Strength"].default_value = 2.5

for key in MESHES:
    for ob in MESHES[key]:
        grp = ob.name.split("_", 1)[1]
        ob.data.materials.append(MATS[SLOT[grp]])
        for poly in ob.data.polygons:
            poly.use_smooth = False

print("SHOPU2 triangles base", c.triangle_count(MESHES["base"]), "ext", c.triangle_count(MESHES["ext"]), "decor", c.triangle_count(MESHES["dec"]))
print([(o.name, c.triangle_count([o])) for o in MESHES["base"] + MESHES["ext"] + MESHES["dec"]])

# ---- textured export (2026-11-26 texture pass): the base and the Back Room carry NEUTRAL light textures with relief (Studio imports them as a
# SurfaceAppearance, so a paint is a tint over the texture): plaster on walls, wood grain on trim / accents / shutters, shingles on the roof.
# Glass and the decor stay plain. The preview renders further down use the plain materials again.
import textures as tx  # noqa: E402

TEXTURE_FOR = {"Walls": "plaster", "UpWalls": "plaster", "BackCap": "plaster", "Trim": "woodgrain", "UpTrim": "woodgrain", "BackCapTrim": "woodgrain",
               "Accent": "woodgrain", "UpAccent": "woodgrain", "Roof": "shingle", "BackCapRoof": "shingle"}


def uv_box(obj, size=8.0):
    """Box projection: 1 UV unit = 8 studs (the scale every building script uses)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        for loop in f.loops:
            co = loop.vert.co
            uv = (co.y, co.z) if ax == 0 else ((co.x, co.z) if ax == 1 else (co.x, co.y))
            loop[layer].uv = (uv[0] / size, uv[1] / size)
    bm.to_mesh(obj.data)
    bm.free()


plain = {}
for key in ("base", "ext"):
    for ob in MESHES[key]:
        grp = ob.name.split("_", 1)[1]
        kind = TEXTURE_FOR.get(grp)
        if kind:
            plain[ob] = list(ob.data.materials)
            uv_box(ob)
            tx.apply(ob, kind, name=f"U_tex_{grp}")
os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_Base.glb"), MESHES["base"])
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_BackRoom.glb"), MESHES["ext"])
for ob, mats in plain.items():
    ob.data.materials.clear()
    for m in mats:
        ob.data.materials.append(m)
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_Decor.glb"), MESHES["dec"])
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no renders)")
    raise SystemExit

# ================================================================ preview renders
PRESETS = {
    "CapizCream": {"Wall": "EAE3D5", "Floor": "8C6648", "Trim": "593E2B", "Accent": "C98A4B"},
    "MayonAsh": {"Wall": "363940", "Floor": "5E544C", "Trim": "DFD8CC", "Accent": "C86D51"},
    "UbeHalaya": {"Wall": "CFC3DC", "Floor": "B89B7E", "Trim": "F5F1EB", "Accent": "7E5A8C"},
    "SantanSunset": {"Wall": "C95B4B", "Floor": "6E5644", "Trim": "F4EDE2", "Accent": "2F5D62"},
    "ParolPasko": {"Wall": "F1E8D8", "Floor": "6B4A36", "Trim": "8F2D2B", "Accent": "D9A441"},
}
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1200, 800
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
bgn = world.node_tree.nodes["Background"]
bgn.inputs["Color"].default_value = (0.62, 0.72, 0.82, 1)
bgn.inputs["Strength"].default_value = 0.9
scene.world = world
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 3.6
sd.color = (1.0, 0.92, 0.8)
sd.angle = math.radians(4)
so = bpy.data.objects.new("Sun", sd)
bpy.context.collection.objects.link(so)
so.rotation_euler = (math.radians(54), 0, math.radians(215))

gm = bpy.data.materials.new("ground_mat")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.19, 0.2, 0.2, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
fl = bpy.data.materials.new("floor_mat")
fl.use_nodes = True
park = bpy.data.materials.new("park_mat")
park.use_nodes = True
park.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.12, 0.22, 0.1, 1)


def slab(name, x0, x1, y0, y1, z0, z1, mat):
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


slab("street", -140, 140, -140, 140, -0.4, 0.0, park)
slab("road", -140, 140, 30, 48, -0.38, 0.02, gm)
floor_base = slab("floor_base", -OUT, OUT, BACK, FRONT, 0.0, F0, fl)
floor_ext = slab("floor_ext", -OUT, OUT, Y0, BACK, 0.0, F0, fl)

cam = bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam"))
bpy.context.collection.objects.link(cam)
scene.camera = cam


def shoot(name, loc, target, lens=30):
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(c.OUT_PREVIEWS, name)
    bpy.ops.render.render(write_still=True)


def show(ext_on, cap_on):
    for ob in MESHES["ext"]:
        ob.hide_render = not ext_on
    floor_ext.hide_render = not ext_on
    for ob in MESHES["base"]:
        if ob.name.startswith("Shop_BackCap"):
            ob.hide_render = not cap_on


def palette(pal):
    set_slot("Wall", pal["Wall"], True)
    set_slot("Trim", pal["Trim"], True)
    set_slot("Accent", pal["Accent"], True)
    r, g, b = srgb(pal["Floor"])
    fl.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (lin(r), lin(g), lin(b), 1)


for name, pal in PRESETS.items():
    palette(pal)
    show(True, False)
    shoot(f"ShopU_{name}_extended.png", (82, 96, 46), (0, -8, 13), 32)
    shoot(f"ShopU_{name}_front.png", (-14, 70, 14), (0, 20, 12), 30)
    if name == "CapizCream":
        show(False, True)
        shoot(f"ShopU_{name}_base.png", (64, 78, 40), (0, 4, 13), 32)
        shoot(f"ShopU_{name}_street.png", (26, 52, 4.5), (0, 20, 12), 24)
        shoot(f"ShopU_{name}_back.png", (-62, -70, 38), (0, -4, 12), 32)
print("done")
