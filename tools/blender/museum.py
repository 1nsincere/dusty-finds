"""Museum of Restored Things v2: hero landmark you can WALK INTO (Blender 5.x, headless).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/museum.py
Writes assets/models/Museum.glb and assets/previews/Museum_*.png (git-ignored).

Scale: real studs (1 unit = 1 stud). Front faces -Y. Stands on z = 0. Footprint about 82 x 58 (podium), dome top about 62.
Hollow shell: one connected exhibit hall (two wings + a tall central hall under the dome), a 7 x 11 walk-through entrance,
real window openings with glass, tiled floor, plinths and display cases inside. Roblox: give Museum_Walls
CollisionFidelity = PreciseConvexDecomposition so the doorway is walkable (tools/studio/PlaceMuseum.luau).
One object per colour group named Museum_<Group>; Studio colours them by name.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

c.PALETTE.update({"sand": "EFE2C4", "white": "FBF7EC", "verdigris": "5E9E88", "glass": "3E6A8A", "stone": "CFC5B0",
                  "wood": "6B4A2E", "leaf": "3F7F3A", "pink": "E0458C", "floor": "E8D9BC", "gold": "E3B23C"})
c.reset_scene()

Z0 = 1.8           # podium top = interior floor level
T = 1.2            # wall thickness
WING_H, MID_H = 20.0, 27.0
G = {}


def add(group, obj):
    G.setdefault(group, []).append(obj)
    return obj


def cyl(name, r, h, loc, verts=24, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def mesh_from(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def arch(w, h, segs=14):
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0), (r, h - r)]
    pts += [(r * math.cos(math.pi * i / segs), h - r + r * math.sin(math.pi * i / segs)) for i in range(1, segs)]
    return pts + [(-r, h - r)]


def prism(name, pts, a0, a1, place):
    n = len(pts)
    verts = [place(u, a, v) for a in (a0, a1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return mesh_from(name, verts, faces)


def lathe(name, prof, steps=24, ox=0.0, oy=0.0):
    o = c.lathe(name, prof, steps=steps)
    for v in o.data.vertices:
        v.co.x += ox
        v.co.y += oy
    return o


def boolean(target, other, op):
    mod = target.modifiers.new("b", "BOOLEAN")
    mod.object = other
    mod.operation = op
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="b")
    bpy.data.objects.remove(other, do_unlink=True)


def join(objs, name):
    return c.join(objs, name) if len(objs) > 1 else objs[0]


def fy(x, zb, pts, y0, y1):
    """Prism through a Y-facing wall (profile in X/Z, extruded y0..y1)."""
    return prism("p", pts, y0, y1, lambda u, a, v: (x + u, a, zb + v))


def fx(y, zb, pts, x0, x1):
    """Prism through an X-facing wall (profile in Y/Z, extruded x0..x1)."""
    return prism("p", pts, min(x0, x1), max(x0, x1), lambda u, a, v: (a, y + u, zb + v))


def blob(name, r, loc, strength=0.3, subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        n = v.co.normalized()
        k = 1 + strength * (math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]) + 0.5 * math.sin(v.co.z * 4.3))
        v.co = n * r * k
    bm.to_mesh(o.data)
    bm.free()
    o.name = name
    return o


def uv_box(obj, size=8.0):
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


# ================= SHELL (hollow, one connected hall) =================
outer = join([c.box("o", (19, 40, WING_H), (-26.5, 0, Z0 + WING_H / 2)),
              c.box("o", (34, 40, MID_H), (0, 0, Z0 + MID_H / 2)),
              c.box("o", (19, 40, WING_H), (26.5, 0, Z0 + WING_H / 2))], "outer")
ih_w, ih_m = WING_H - T + 0.5, MID_H - T + 0.5
inner = join([c.box("i", (36 - T - 15.8 + 0.01, 40 - 2 * T, ih_w), (-(36 - T + 15.8) / 2, 0, Z0 - 0.5 + ih_w / 2)),
              c.box("i", (34 - 2 * T, 40 - 2 * T, ih_m), (0, 0, Z0 - 0.5 + ih_m / 2)),
              c.box("i", (36 - T - 15.8 + 0.01, 40 - 2 * T, ih_w), ((36 - T + 15.8) / 2, 0, Z0 - 0.5 + ih_w / 2))], "inner")
def union_all(obj):
    """Merge the overlapping boxes of a joined object into one clean volume (the exact boolean needs that)."""
    mod = obj.modifiers.new("u", "BOOLEAN")
    mod.operation = "UNION"
    mod.solver = "EXACT"
    mod.use_self = True
    dummy = c.box("dummy", (0.01, 0.01, 0.01), (0, 0, -50))
    mod.object = dummy
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="u")
    bpy.data.objects.remove(dummy, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    far = [v for v in bm.verts if v.co.z < -40]
    bmesh.ops.delete(bm, geom=far, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()


union_all(outer)
union_all(inner)
boolean(outer, inner, "DIFFERENCE")
shell = outer

Y_F, Y_B = -20.0, 20.0
TF = (Y_F - 0.6, Y_F + T + 0.6)
TB = (Y_B - T - 0.6, Y_B + 0.6)
cuts = [fy(0, Z0, arch(7.0, 11.0), *TF)]  # walk-through entrance
for x in (-10.0, 10.0):
    cuts += [fy(x, Z0 + 3.0, arch(4.2, 10.0), *TF), fy(x, Z0 + 16.0, arch(3.4, 5.6), *TF)]
cuts.append(fy(0, Z0 + 16.5, arch(4.6, 7.0), *TF))
WX = {-1: [-31.5, -26.5, -21.5], 1: [21.5, 26.5, 31.5]}
for s in (-1, 1):
    for x in WX[s]:
        cuts += [fy(x, Z0 + 2.4, arch(4.0, 8.6), *TF), fy(x, Z0 + 12.6, arch(3.2, 5.4), *TF), fy(x, Z0 + 2.4, arch(4.0, 8.6), *TB)]
    xf = 36.0 * s
    for y in (-10.0, 0.0, 10.0):
        cuts += [fx(y, Z0 + 2.4, arch(3.8, 8.4), xf + 0.6 * s, xf - (T + 0.6) * s), fx(y, Z0 + 12.6, arch(3.0, 5.2), xf + 0.6 * s, xf - (T + 0.6) * s)]
        xc = 17.0 * s  # clerestory windows above the wing roofs
        cuts.append(fx(y, Z0 + WING_H + 1.4, arch(3.0, 4.0), xc + 0.6 * s, xc - (T + 0.6) * s))
for x in (-8.0, 0.0, 8.0):
    cuts.append(fy(x, Z0 + 4.0, arch(3.6, 9.0), *TB))
boolean(shell, join(cuts, "cuts"), "DIFFERENCE")
add("Walls", shell)


def window_dress(x, zb, w, h, y_face, flowers=False):
    """Glass in the wall middle, mullion, transom, moulded surround, sill, keystone; optional flower box."""
    yg = y_face + T / 2
    add("Glass", fy(x, zb + 0.05, arch(w - 0.1, h - 0.1), yg - 0.04, yg + 0.04))
    add("Wood", c.box("mull", (0.18, 0.2, h - w / 2), (x, yg, zb + (h - w / 2) / 2)))
    add("Wood", c.box("transom", (w, 0.2, 0.16), (x, yg, zb + (h - w / 2) * 0.62)))
    big = [(u * (w / 2 + 0.4) / (w / 2), v * (h + 0.4) / h) for (u, v) in arch(w, h)]
    surround = fy(x, zb - 0.2, big, y_face - 0.28, y_face + 0.05)
    boolean(surround, fy(x, zb - 0.01, arch(w, h + 0.01), y_face - 0.7, y_face + 0.6), "DIFFERENCE")
    add("Trim", surround)
    add("Trim", c.box("sill", (w + 1.1, 0.8, 0.32), (x, y_face - 0.32, zb - 0.16)))
    add("Trim", c.box("key", (0.75, 0.6, 1.0), (x, y_face - 0.32, zb + h + 0.25)))
    if flowers:
        add("Wood", c.box("fbox", (w + 0.4, 0.8, 0.6), (x, y_face - 0.6, zb + 0.15)))
        for dx in (-w / 3, 0, w / 3):
            add("Leaves", blob("lv", 0.55, (x + dx, y_face - 0.65, zb + 0.6), 0.3, 2))
        for k in range(6):
            add("Flowers", c.sphere("f", 0.17, (x - w / 2 + 0.3 + k * (w - 0.6) / 5, y_face - 1.0, zb + 0.78 + 0.12 * (k % 2)), segments=6, rings=4))


for s in (-1, 1):
    for x in WX[s]:
        window_dress(x, Z0 + 2.4, 4.0, 8.6, Y_F, flowers=True)
        window_dress(x, Z0 + 12.6, 3.2, 5.4, Y_F)
for x in (-10.0, 10.0):
    window_dress(x, Z0 + 3.0, 4.2, 10.0, Y_F)
    window_dress(x, Z0 + 16.0, 3.4, 5.6, Y_F)
window_dress(0, Z0 + 16.5, 4.6, 7.0, Y_F)
for s in (-1, 1):
    xg = 36.0 * s - T / 2 * s
    for y in (-10.0, 0.0, 10.0):
        add("Glass", fx(y, Z0 + 2.45, arch(3.7, 8.3), xg - 0.04, xg + 0.04))
        add("Glass", fx(y, Z0 + 12.65, arch(2.9, 5.1), xg - 0.04, xg + 0.04))
        add("Trim", c.box("ssill", (0.8, 4.8, 0.3), (36.0 * s + 0.3 * s, y, Z0 + 2.25)))
        add("Trim", c.box("skey", (0.6, 0.75, 1.0), (36.0 * s + 0.3 * s, y, Z0 + 11.05)))
        xc = 17.0 * s - T / 2 * s
        add("Glass", fx(y, Z0 + WING_H + 1.45, arch(2.9, 3.9), xc - 0.04, xc + 0.04))
    for x in WX[s]:
        add("Glass", fy(x, Z0 + 2.45, arch(3.9, 8.5), Y_B - T / 2 - 0.04, Y_B - T / 2 + 0.04))
for x in (-8.0, 0.0, 8.0):
    add("Glass", fy(x, Z0 + 4.05, arch(3.5, 8.9), Y_B - T / 2 - 0.04, Y_B - T / 2 + 0.04))

# ================= BANDS, CORNICES, DENTILS, PILASTERS =================
def ring_band(group, x0, x1, y0, y1, zc, h, out, skip=()):
    """A moulding that wraps the OUTSIDE of the walls only (4 strips), so it never forms a slab across the hall."""
    w, d = x1 - x0, y1 - y0
    t = out + T * 0.5
    add(group, c.box("rb", (w + 2 * out, t, h), ((x0 + x1) / 2, y0 - out + t / 2, zc)))
    add(group, c.box("rb", (w + 2 * out, t, h), ((x0 + x1) / 2, y1 + out - t / 2, zc)))
    if "x0" not in skip:
        add(group, c.box("rb", (t, d + 2 * out, h), (x0 - out + t / 2, (y0 + y1) / 2, zc)))
    if "x1" not in skip:
        add(group, c.box("rb", (t, d + 2 * out, h), (x1 + out - t / 2, (y0 + y1) / 2, zc)))


for (x0, x1, h) in ((-36, -17, WING_H), (17, 36, WING_H), (-17, 17, MID_H)):
    w = x1 - x0
    xm = (x0 + x1) / 2
    sk = ("x1",) if x1 == -17 else (("x0",) if x0 == 17 else ("x0", "x1"))
    ring_band("Stone", x0, x1, -20, 20, Z0 + 0.65, 1.3, 0.3, sk)
    ring_band("Trim", x0, x1, -20, 20, Z0 + 11.4, 0.7, 0.45, sk)
    add("Trim", c.box("corn1", (w + 0.7, 40.7, 0.5), (xm, 0, Z0 + h - 0.4)))
    add("Trim", c.box("corn2", (w + 1.5, 41.5, 0.6), (xm, 0, Z0 + h + 0.15)))
    add("Trim", c.box("corn3", (w + 2.3, 42.3, 0.55), (xm, 0, Z0 + h + 0.7)))
    for i in range(int(w / 0.9)):
        add("Trim", c.box("dentil", (0.45, 0.5, 0.5), (x0 + 0.45 + i * 0.9, Y_F - 0.3, Z0 + h - 1.0)))
for x in (-36, -17, 17, 36):
    add("Trim", c.box("pilaster", (1.8, 1.0, WING_H - 1.2), (x, Y_F - 0.4, Z0 + (WING_H - 1.2) / 2 + 0.6)))
    add("Trim", c.box("pcap", (2.4, 1.4, 0.6), (x, Y_F - 0.45, Z0 + WING_H - 0.9)))

# ================= PORTICO =================
colx = [-15.0, -11.0, -7.0, 7.0, 11.0, 15.0]  # open 14-stud middle bay so nothing blocks the door
add("Trim", c.box("portico_floor", (37, 9.5, 0.3), (0, -24.75, Z0 + 0.15)))
for x in colx:
    add("Columns", lathe("col", [(0.01, Z0 + 1.4), (1.3, Z0 + 1.4), (1.25, Z0 + 10), (1.12, Z0 + 19.4), (0.01, Z0 + 19.4)], 20, x, -25.5))
    add("Trim", lathe("base", [(0.01, Z0 + 0.3), (1.95, Z0 + 0.3), (1.95, Z0 + 0.75), (1.6, Z0 + 0.95), (1.6, Z0 + 1.15), (1.35, Z0 + 1.4), (0.01, Z0 + 1.4)], 20, x, -25.5))
    add("Trim", lathe("cap", [(0.01, Z0 + 19.3), (1.2, Z0 + 19.3), (1.6, Z0 + 19.8), (2.0, Z0 + 20.2), (0.01, Z0 + 20.2)], 20, x, -25.5))
    add("Trim", c.box("abacus", (4.2, 4.2, 0.55), (x, -25.5, Z0 + 20.45)))
add("Trim", c.box("arch1", (37.5, 10.5, 1.0), (0, -24.4, Z0 + 21.2)))
add("Gold", c.box("signband", (24, 0.4, 1.4), (0, -29.7, Z0 + 22.4)))
add("Trim", c.box("arch2", (38.5, 11.2, 1.1), (0, -24.4, Z0 + 23.2)))
add("Trim", prism("pediment", [(-19.8, 0), (19.8, 0), (0, 7.2)], -30.1, -19.6, lambda u, a, v: (u, a, Z0 + 23.75 + v)))
add("Trim", prism("tympanum", [(-17.2, 0), (17.2, 0), (0, 6.0)], -30.2, -30.05, lambda u, a, v: (u, a, Z0 + 24.3 + v)))
add("Gold", cyl("emblem", 1.7, 0.4, (0, -30.35, Z0 + 26.6), 28, (math.pi / 2, 0, 0)))
add("Gold", c.torus("wreath", 2.1, 0.18, (0, -30.35, Z0 + 26.6), (math.pi / 2, 0, 0), 28, 6))
for i, x in enumerate((-13.0, -9.0, 9.0, 13.0)):
    add("BannerPlum" if i in (0, 3) else "BannerTeal", c.box("ban", (2.2, 0.15, 12.5), (x, -24.9, Z0 + 12.0)))
    add("Gold", c.box("banrod", (2.6, 0.2, 0.2), (x, -24.9, Z0 + 18.3)))
    add("BannerGold", c.box("banstripe", (2.2, 0.2, 0.5), (x, -24.95, Z0 + 6.6)))
add("Stone", c.box("podium", (82, 58, Z0), (0, 0, Z0 / 2)))
for i in range(4):  # grand steps down from the podium front (y = -29) to the ground
    add("Stone", c.box("step", (32 - i * 0.8, 1.6, Z0 - i * 0.45), (0, -29.0 - 0.8 - (3 - i) * 1.6, (Z0 - i * 0.45) / 2)))
for s in (-1, 1):  # stair cheeks with urn planters; bougainvillea climbs the outer columns from them
    add("Stone", c.box("cheek", (1.6, 7.0, 2.6), (s * 16.8, -32.4, 1.3)))
    add("Urns", lathe("urn", [(0.01, 2.6), (0.7, 2.6), (0.8, 3.3), (1.25, 4.1), (0.75, 5.0), (0.55, 5.4), (0.95, 5.65), (0.01, 5.65)], 16, s * 16.8, -32.4))
    add("Leaves", blob("lv", 0.95, (s * 16.8, -32.4, 6.0), 0.3, 2))
    add("Flowers", blob("bg", 0.6, (s * 16.8 + 0.4 * s, -32.8, 6.5), 0.3, 2))
    for k in range(9):  # bougainvillea climbing the outer column from the urn: dense leaf clusters + pink bract clusters
        zc = Z0 + 1.0 + k * 2.1
        for j in range(3):
            a = j * 2.1 + k * 0.9
            add("Leaves", blob("vine", 0.5 - k * 0.02, (s * 16.5 + 0.45 * math.cos(a), -26.5 + 0.35 * math.sin(a), zc + 0.4 * j), 0.28, 2))
        for j in range(4):
            a = j * 1.6 + k * 1.3
            add("Flowers", blob("bg", 0.26, (s * 16.6 + 0.6 * math.cos(a), -27.0 + 0.3 * math.sin(a), zc + 0.5 + 0.35 * j), 0.25, 2))


# ================= TILED WING ROOFS (real barrel tiles) =================
def tile_roof(x0, x1, y0, y1, zb, rise):
    xm = (x0 + x1) / 2
    run = (x1 - x0) / 2
    th = math.atan2(rise, run)
    L = math.hypot(run, rise)
    for s in (-1, 1):  # s=-1: the low-x slope, s=+1: the high-x slope; both rise to the ridge at xm
        # explicit geometry (no Euler rotations): eave point -> ridge point, outward normal
        ex, ez = xm + s * run, zb
        dx, dz = (xm - ex) / L, rise / L          # unit vector up the slope
        nx_, nz_ = s * math.sin(th), math.cos(th)
        def P(a, v, yy):
            return (ex + dx * a + nx_ * v, yy, ez + dz * a + nz_ * v)
        slab = mesh_from("slab", [P(0, -0.35, y0), P(L, -0.35, y0), P(L, -0.35, y1), P(0, -0.35, y1),
                                  P(0, 0, y0), P(L, 0, y0), P(L, 0, y1), P(0, 0, y1)],
                         [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
        add("Roof", slab)
        semi = [(0.42 * math.cos(math.pi * k / 6), 0.42 * math.sin(math.pi * k / 6)) for k in range(7)]
        y = y0 + 0.45
        while y < y1 - 0.3:
            add("Roof", prism("tile", semi, -0.3, L, lambda u, a, v, y=y: P(a, v, y + u)))
            y += 0.9
    add("Roof", cyl("ridge", 0.55, y1 - y0 + 0.2, (xm, (y0 + y1) / 2, zb + rise + 0.15), 10, (math.pi / 2, 0, 0)))
    add("Walls", prism("gable", [(x0 + 1.2, 0), (x1 - 1.2, 0), (xm, rise - 0.7)], y0 + 0.6, y1 - 0.6, lambda u, a, v: (u, a, zb + v)))
    add("Trim", prism("gtrim", [(x0 - 0.2, 0), (x1 + 0.2, 0), (xm, rise + 0.35)], y0 - 0.35, y0 + 0.05, lambda u, a, v: (u, a, zb - 0.1 + v)))


for (x0, x1) in ((-37.2, -17.3), (17.3, 37.2)):
    tile_roof(x0, x1, -21.0, 21.0, Z0 + WING_H + 1.0, 5.6)

# ================= CENTRAL ROOF BALUSTRADE + DOME =================
add("Trim", c.box("mid_roof", (33.6, 39.6, 0.4), (0, 0, Z0 + MID_H + 1.2)))
for side_y in (-21.0, 21.0):
    add("Trim", c.box("bal_base", (34.5, 0.9, 0.4), (0, side_y, Z0 + MID_H + 1.2)))
    add("Trim", c.box("bal_top", (34.5, 1.0, 0.4), (0, side_y, Z0 + MID_H + 3.2)))
    for i in range(36):
        add("Trim", lathe("baluster", [(0.01, Z0 + MID_H + 1.4), (0.3, Z0 + MID_H + 1.4), (0.22, Z0 + MID_H + 1.7), (0.36, Z0 + MID_H + 2.3), (0.18, Z0 + MID_H + 2.8), (0.28, Z0 + MID_H + 3.0), (0.01, Z0 + MID_H + 3.0)], 6, -16.6 + i * 0.95, side_y))
DZ = Z0 + MID_H + 1.4
DR = 11.0
add("Trim", cyl("drum_base", DR + 1.9, 1.4, (0, 0, DZ + 0.7), 44))
drum = cyl("drum", DR + 0.6, 7.4, (0, 0, DZ + 1.4 + 3.7), 44)
dcuts = []
for i in range(12):
    a = i / 12 * 2 * math.pi + math.pi / 12
    for kind in ("cut", "glass"):
        if kind == "cut":
            ob = fy(0, DZ + 2.5, arch(2.0, 4.6), -(DR + 2.0), -(DR - 1.5))
        else:
            ob = fy(0, DZ + 2.55, arch(1.9, 4.5), -(DR + 0.15), -(DR + 0.05))
        ob.rotation_euler = (0, 0, a + math.pi / 2)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.transform_apply(rotation=True)
        ob.select_set(False)
        if kind == "cut":
            dcuts.append(ob)
        else:
            add("Glass", ob)
boolean(drum, join(dcuts, "dc"), "DIFFERENCE")
add("Walls", drum)
for i in range(12):
    a = i / 12 * 2 * math.pi
    p = c.box("drumpil", (1.2, 0.9, 7.2), ((DR + 0.95) * math.cos(a), (DR + 0.95) * math.sin(a), DZ + 5.0))
    p.rotation_euler = (0, 0, a + math.pi / 2)
    add("Trim", p)
add("Trim", cyl("drum_corn", DR + 1.5, 0.8, (0, 0, DZ + 9.2), 44))
add("Trim", cyl("drum_corn2", DR + 2.0, 0.5, (0, 0, DZ + 9.75), 44))
prof = [(0.01, DZ + 9.9), (DR + 0.4, DZ + 9.9)] + [((DR + 0.4) * math.cos(math.radians(t)), DZ + 9.9 + (DR + 1.2) * math.sin(math.radians(t))) for t in range(6, 91, 6)]
add("Dome", c.lathe("dome", prof, steps=48))
for i in range(16):  # gold ribs following the dome curve
    a = i / 16 * 2 * math.pi
    pts = [((DR + 0.45) * math.cos(math.radians(t)) * math.cos(a), (DR + 0.45) * math.cos(math.radians(t)) * math.sin(a), DZ + 9.9 + (DR + 1.25) * math.sin(math.radians(t))) for t in (4, 30, 55, 78)]
    add("Gold", c.tube("rib", pts, [1, 1, 1, 0.7], bevel=0.13, resolution=10))
add("Trim", lathe("lantern_base", [(0.01, DZ + 21.6), (3.0, DZ + 21.6), (3.0, DZ + 22.2), (0.01, DZ + 22.2)], 20))
for i in range(8):
    a = i / 8 * 2 * math.pi
    add("Trim", cyl("lcol", 0.22, 3.0, (2.4 * math.cos(a), 2.4 * math.sin(a), DZ + 23.7), 8))
add("Glass", cyl("lglass", 2.1, 3.0, (0, 0, DZ + 23.7), 16))
add("Trim", cyl("lcap", 2.9, 0.4, (0, 0, DZ + 25.4), 20))
add("Dome", c.lathe("ldome", [(0.01, DZ + 25.6), (2.7, DZ + 25.6)] + [(2.7 * math.cos(math.radians(t)), DZ + 25.6 + 2.8 * math.sin(math.radians(t))) for t in range(12, 91, 13)], steps=20))
add("Gold", cyl("spire", 0.17, 4.0, (0, 0, DZ + 30.2), 8))
add("Gold", c.sphere("finial", 0.6, (0, 0, DZ + 32.5), segments=12, rings=8))

# ================= INTERIOR (walk-in exhibit hall) =================
add("Floor", c.box("floor", (70.4, 37.4, 0.3), (0, 0, Z0 + 0.15)))
for i in range(-8, 9):
    add("Stone", c.box("inlay", (0.25, 37.3, 0.32), (i * 4.0, 0, Z0 + 0.16)))
add("Stone", cyl("rotunda", 8.0, 0.34, (0, 2.0, Z0 + 0.17), 40))
add("Gold", c.torus("rotring", 8.0, 0.12, (0, 2.0, Z0 + 0.34), (0, 0, 0), 40, 4))
add("Stone", cyl("centre_plinth", 2.2, 3.2, (0, 2.0, Z0 + 1.9), 24))
add("Trim", cyl("centre_top", 2.6, 0.35, (0, 2.0, Z0 + 3.65), 24))
add("Glass", c.box("centre_case", (3.0, 3.0, 2.6), (0, 2.0, Z0 + 5.15)))
add("Gold", c.sphere("relic", 0.9, (0, 2.0, Z0 + 4.85), segments=16, rings=10))
for s in (-1, 1):
    for x in (21.5, 26.5, 31.5):
        for py in (-9.0, 9.0):
            add("Stone", c.box("plinth", (2.2, 2.2, 3.2), (s * x, py, Z0 + 1.9)))
            add("Trim", c.box("plinthtop", (2.6, 2.6, 0.3), (s * x, py, Z0 + 3.65)))
            add("Glass", c.box("case", (2.0, 2.0, 1.8), (s * x, py, Z0 + 4.7)))
            add("Gold", c.sphere("exhibit", 0.45, (s * x, py, Z0 + 4.3), segments=10, rings=6))
    for y in (-12.0, 12.0):
        add("Columns", lathe("icol", [(0.01, Z0 + 0.3), (1.0, Z0 + 0.3), (0.9, Z0 + 12), (0.8, Z0 + MID_H - 1.6), (0.01, Z0 + MID_H - 1.6)], 16, s * 13.0, y))
    add("Wood", c.box("wainscot", (0.3, 37.0, 3.2), (s * (36 - T - 0.15), 0, Z0 + 1.9)))
    add("Wood", c.box("bench", (1.4, 6.0, 0.4), (s * 26.5, 0, Z0 + 1.6)))
add("Wood", c.box("wainscot_b", (70.0, 0.3, 3.2), (0, 20 - T - 0.15, Z0 + 1.9)))
add("BannerTeal", c.box("rug", (6.0, 26.0, 0.06), (0, -6.0, Z0 + 0.33)))
# coffered ceiling, chandeliers (Studio adds lights to Museum_Lamp), paintings, sign letters
for gx in range(-34, 35, 4):
    add("Trim", c.box("beam", (0.5, 37.6, 0.6), (gx, 0, (Z0 + WING_H - T - 0.3) if abs(gx) > 16 else (Z0 + MID_H - T - 0.3))))
for gy in range(-16, 17, 4):
    for (xa, xb, zz) in ((-34.8, -15.8, Z0 + WING_H - T - 0.3), (15.8, 34.8, Z0 + WING_H - T - 0.3), (-15.8, 15.8, Z0 + MID_H - T - 0.3)):
        add("Trim", c.box("beam", (xb - xa, 0.5, 0.6), ((xa + xb) / 2, gy, zz)))
for (lx, lz) in ((-26.5, Z0 + 14.5), (26.5, Z0 + 14.5), (0.0, Z0 + 19.0)):
    add("Gold", cyl("chain", 0.06, (Z0 + (WING_H if lx else MID_H) - T) - lz - 1.0, (lx, 0, (lz + 1.0 + Z0 + (WING_H if lx else MID_H) - T) / 2), 6))
    add("Gold", c.torus("ring", 1.6, 0.12, (lx, 0, lz), (0, 0, 0), 24, 6))
    add("Gold", c.torus("ring2", 0.9, 0.1, (lx, 0, lz + 0.7), (0, 0, 0), 20, 6))
    for k in range(8):
        a = k / 8 * 2 * math.pi
        add("Lamp", c.sphere("bulb", 0.22, (lx + 1.6 * math.cos(a), 1.6 * math.sin(a), lz + 0.3), segments=8, rings=5))
for i, x in enumerate((-31.5, -21.5, 21.5, 31.5)):
    add("Gold", c.box("frame", (4.4, 0.25, 3.4), (x, 20 - T - 0.2, Z0 + 12.5)))
    add(("BannerTeal", "BannerPlum", "BannerPlum", "BannerTeal")[i], c.box("canvas", (3.8, 0.3, 2.8), (x, 20 - T - 0.25, Z0 + 12.5)))
bpy.ops.object.text_add(location=(0, -29.95, Z0 + 22.0), rotation=(math.pi / 2, 0, 0))
txt = bpy.context.active_object
txt.data.body = "MUSEUM"
txt.data.size = 1.2
txt.data.extrude = 0.06
txt.data.align_x = "CENTER"
txt.data.space_character = 1.25
bpy.ops.object.convert(target="MESH")
add("Letters", bpy.context.active_object)

# ================= FINISH =================
SPEC = {"Walls": ("sand", 0.1), "Trim": ("white", 0.0), "Columns": ("white", 0.0), "Roof": ("terracotta", 0.0), "Dome": ("verdigris", 0.0),
        "Gold": ("gold", 0.0), "Glass": ("glass", 0.0), "Wood": ("wood", 0.0), "Stone": ("stone", 0.0), "BannerPlum": ("plum", 0.0),
        "BannerTeal": ("teal", 0.0), "BannerGold": ("gold", 0.0), "Urns": ("white", 0.0), "Leaves": ("leaf", 0.0), "Flowers": ("pink", 0.0),
        "Floor": ("floor", 0.0), "Lamp": ("warm", 0.0), "Letters": ("black", 0.0)}
SMOOTH = {"Columns", "Dome", "Gold", "Urns", "Leaves", "Flowers", "Lamp"}
import textures as tx  # noqa: E402
TEX = {"Walls": "plaster", "Stone": "stone", "Trim": "limestone", "Columns": "limestone", "Roof": "clay", "Wood": "wood", "Floor": "marble", "Urns": "limestone"}
final = []
for name, objs in G.items():
    obj = join(objs, "Museum_" + name)
    col, bev = SPEC[name]
    c.finish(obj, "Museum_" + name, col, bevel=bev, smooth=name in SMOOTH)
    if name in TEX:
        uv_box(obj, 8.0)
        tx.apply(obj, TEX[name], "Museum_" + name + "_mat", (0.95, 0.86, 0.70) if name == "Walls" else None)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
print("MUSEUM triangles", c.triangle_count(final), [(o.name, c.triangle_count([o])) for o in final])
c.export_glb(os.path.join(c.OUT_MODELS, "Museum.glb"), final)


def shot(path, cam_loc, target, lens=35):
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_shadows = True
    sh.shadow_intensity = 0.55
    scene.display.light_direction = (0.45, -0.55, 0.7)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 860
    if scene.world is None:
        scene.world = bpy.data.worlds.new("W")
    scene.world.color = (0.86, 0.9, 0.95)
    cam = bpy.data.objects.get("ShotCam")
    if cam is None:
        cam = bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam"))
        bpy.context.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = cam_loc
    cam.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_cycles(path, cam_loc, target, lens=35, samples=40, res=(1200, 860)):
    """Golden-hour render (warm sun + sky) so the textures and depth read like the game will."""
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    sky = world.node_tree.nodes.new("ShaderNodeTexSky")
    bg = world.node_tree.nodes["Background"]
    world.node_tree.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35
    scene.world = world
    if not bpy.data.objects.get("Sun"):
        sd = bpy.data.lights.new("Sun", "SUN")
        sd.energy = 4.2
        sd.color = (1.0, 0.86, 0.7)
        sd.angle = math.radians(3)
        so = bpy.data.objects.new("Sun", sd)
        bpy.context.collection.objects.link(so)
        so.rotation_euler = (math.radians(58), 0, math.radians(35))
        gd = bpy.data.meshes.new("ground")
        go = bpy.data.objects.new("ground", gd)
        bpy.context.collection.objects.link(go)
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=160)
        bm.to_mesh(gd)
        bm.free()
        gm = bpy.data.materials.new("groundmat")
        gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.47, 0.36, 1)
        gd.materials.append(gm)
    cam = bpy.data.objects.get("ShotCam")
    if cam is None:
        cam = bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam"))
        bpy.context.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = cam_loc
    cam.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# preview only: tint the plaster like Studio will (SurfaceAppearance.Color), without changing the exported texture
render_cycles(os.path.join(c.OUT_PREVIEWS, "Museum_front.png"), (62, -100, 30), (0, 0, 20))
render_cycles(os.path.join(c.OUT_PREVIEWS, "Museum_bay.png"), (-12, -44, 9), (-26, -20, 9), 40, 32, (1000, 760))
for (lx, lz) in ((-26.5, Z0 + 14.0), (26.5, Z0 + 14.0), (0.0, Z0 + 18.5)):  # preview only: the chandeliers lit, like the Studio PointLights
    ld = bpy.data.lights.new("chand", "POINT")
    ld.energy = 9000
    ld.color = (1.0, 0.82, 0.6)
    ld.shadow_soft_size = 1.5
    lo = bpy.data.objects.new("chand", ld)
    bpy.context.collection.objects.link(lo)
    lo.location = (lx, 0, lz)
render_cycles(os.path.join(c.OUT_PREVIEWS, "Museum_inside.png"), (-6, -16, 6.5), (4, 8, 10), 18, 64, (1000, 760))
print("done")
