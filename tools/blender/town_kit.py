"""Town kit: the repeated pieces of the canal town, modelled properly (Blender 5.x, headless).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/town_kit.py
Writes assets/models/TownKit.glb and assets/previews/TownKit*.png (git-ignored).

Scale: 1 Blender unit = 1 stud. Every object is named <Piece>_<Group> (Palm_Fronds, HouseA_Walls...). Studio groups them by the prefix
into templates and colours each group by name (tools/studio/BuildTownKit.luau). Fronts face -Y. Each piece stands on z = 0 at its own x offset.
Objects get box-projected UVs (1 UV unit = 8 studs) so Roblox materials (Plaster, ClayRoofTiles...) tile on the meshes.
"""

import math
import os
import random
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

c.PALETTE.update({
    "sand": "EFE2C4", "white": "FBF7EC", "glass": "3E6A8A", "stone": "D9CDB4", "wood": "6B4A2E", "bark": "8B6A45",
    "frond": "4F8F3A", "coconut": "6B4A2E", "leaf": "3F7F3A", "pink": "E0458C", "warmglow": "FFE9B0", "water": "3CB6C8",
    "gold": "E3B23C", "red": "C8453C", "brick": "B0644A", "salmon": "F0A08C",
})
c.reset_scene()
random.seed(7)
GROUPS = {}


def add(piece, group, obj):
    GROUPS.setdefault((piece, group), []).append(obj)
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


def arch_profile(w, h, segs=12):
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0), (r, h - r)]
    for i in range(1, segs):
        a = math.pi * i / segs
        pts.append((r * math.cos(a), h - r + r * math.sin(a)))
    pts.append((-r, h - r))
    return pts


def rect_profile(w, h):
    return [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h), (-w / 2, h)]


def prism(name, pts, a0, a1, place):
    """Extrude a 2D profile (u, v) from a0 to a1; place(u, a, v) -> world (x, y, z)."""
    n = len(pts)
    verts = [place(u, a, v) for a in (a0, a1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    return mesh_from(name, verts, faces)


def cut(wall, cutters):
    ob = c.join(cutters, "cutters") if len(cutters) > 1 else cutters[0]
    mod = wall.modifiers.new("cut", "BOOLEAN")
    mod.object = ob
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = wall
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(ob, do_unlink=True)


def front_opening(x, yface, zb, pts, depth):
    """Cutter through a -Y facing wall at y=yface (starts 0.5 outside)."""
    return prism("cut", pts, yface - 0.5, yface + depth, lambda u, a, v: (x + u, a, zb + v))


def side_opening(xface, y, zb, pts, depth, sign):
    """Cutter through an X facing wall (sign=+1: face at +X, cut goes toward -X)."""
    return prism("cut", pts, xface + 0.5 * sign, xface - depth * sign, lambda u, a, v: (a, y + u, zb + v))


def hip_roof(name, x0, x1, y0, y1, z, h, inset):
    v = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z),
         (x0 + inset, y0 + inset, z + h), (x1 - inset, y0 + inset, z + h), (x1 - inset, y1 - inset, z + h), (x0 + inset, y1 - inset, z + h)]
    f = [(0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
    return mesh_from(name, v, f)


def blob(name, r, loc, strength=0.25, subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        n = v.co.normalized()
        k = 1 + strength * (math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7) + 0.5 * math.sin(v.co.z * 4.3))
        v.co = n * r * k
    bm.to_mesh(o.data)
    bm.free()
    return o


def uv_box(obj, size=8.0):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.loops.layers.uv.verify()
    mw = obj.matrix_world
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = mw @ loop.vert.co
            if ax == 0:
                uv = (co.y, co.z)
            elif ax == 1:
                uv = (co.x, co.z)
            else:
                uv = (co.x, co.y)
            loop[layer].uv = (uv[0] / size, uv[1] / size)
    bm.to_mesh(me)
    bm.free()


# ======================= PALM (x = 0) =======================
def palm(ox):
    P = "Palm"
    pts = [(ox, 0, 0), (ox + 0.5, 0, 5.0), (ox + 1.5, 0, 10.0), (ox + 2.3, 0, 14.4)]
    add(P, "Trunk", c.tube("trunk", pts, [1.25, 1.0, 0.85, 0.7], bevel=0.5, resolution=16))
    # bark rings: follow the trunk curve
    for i in range(1, 12):
        t = i / 12
        x = ox + 2.3 * (t ** 1.6)
        z = 14.4 * t
        r = 0.5 * (1.25 - 0.55 * t) + 0.04
        add(P, "Trunk", c.torus("ring", r, 0.07, (x, 0, z), (0, math.radians(-12 * t), 0), 12, 4))
    crown = (ox + 2.3, 0.0, 14.5)
    add(P, "Trunk", c.sphere("boss", 0.55, (crown[0], 0, crown[2] - 0.1), segments=10, rings=6))
    # fronds: arched, drooping, slightly folded blades with leaflet zigzag
    for k in range(11):
        th = k / 11 * 2 * math.pi + random.uniform(-0.12, 0.12)
        L = random.uniform(6.2, 7.6)
        pitch = random.uniform(0.35, 0.75)
        droop = random.uniform(0.9, 1.3)
        d = (math.cos(th), math.sin(th))
        side = (-d[1], d[0])
        N = 10
        verts, faces = [], []
        for i in range(N + 1):
            s = i / N
            hx = L * s
            px = crown[0] + d[0] * hx
            py = crown[1] + d[1] * hx
            pz = crown[2] + math.sin(pitch) * L * s - droop * L * 0.55 * s * s
            w = 1.05 * (math.sin(math.pi * min(1.0, s * 1.15)) ** 0.6) + 0.04
            w *= 1.18 if i % 2 else 0.85  # leaflet zigzag
            fold = 0.22 * w
            verts += [(px + side[0] * w, py + side[1] * w, pz - fold), (px, py, pz), (px - side[0] * w, py - side[1] * w, pz - fold)]
        for i in range(N):
            a = i * 3
            faces += [(a, a + 1, a + 4, a + 3), (a + 1, a + 2, a + 5, a + 4)]
        add(P, "Fronds", mesh_from("frond", verts, faces))
    for k in range(5):
        a = k / 5 * 2 * math.pi
        add(P, "Coconuts", c.sphere("coco", 0.42, (crown[0] + 0.55 * math.cos(a), 0.55 * math.sin(a), crown[2] - 0.75), segments=10, rings=7))


# ======================= LAMP (x = 12) =======================
def lamp(ox):
    P = "Lamp"
    prof = [(0.01, 0), (0.95, 0), (0.95, 0.45), (0.75, 0.65), (0.7, 1.3), (0.5, 1.5), (0.42, 1.9), (0.3, 2.1), (0.22, 2.4),
            (0.2, 5.0), (0.3, 5.15), (0.3, 5.35), (0.19, 5.5), (0.17, 9.3), (0.3, 9.45), (0.3, 9.7), (0.01, 9.75)]
    o = c.lathe("pole", prof, steps=16)
    o.location.x = ox
    add(P, "Metal", o)
    for s in (-1, 1):
        add(P, "Metal", c.tube("arm", [(ox, 0, 9.0), (ox + 0.9 * s, 0, 9.6), (ox + 1.8 * s, 0, 9.75)], [1, 1, 1], bevel=0.09, resolution=10))
        add(P, "Metal", c.tube("scroll", [(ox + 0.25 * s, 0, 8.2), (ox + 0.9 * s, 0, 8.7), (ox + 1.2 * s, 0, 9.4), (ox + 0.9 * s, 0, 9.55)], [1, 1, 1, 1], bevel=0.05, resolution=10))
        lx = ox + 1.8 * s
        base = c.lathe("lbase", [(0.01, 9.7), (0.32, 9.7), (0.5, 9.85), (0.42, 9.95), (0.01, 9.95)], steps=6)
        base.location.x = lx - 0
        base.location.x = 0
        for v in base.data.vertices:
            v.co.x += lx
        add(P, "Metal", base)
        g = c.lathe("glass", [(0.01, 9.95), (0.38, 9.95), (0.48, 10.9), (0.01, 10.9)], steps=6)
        for v in g.data.vertices:
            v.co.x += lx
        add(P, "Glass", g)
        roof = c.lathe("lroof", [(0.01, 10.85), (0.62, 10.85), (0.62, 10.95), (0.25, 11.35), (0.08, 11.6), (0.01, 11.6)], steps=6)
        for v in roof.data.vertices:
            v.co.x += lx
        add(P, "Metal", roof)
        add(P, "Metal", c.sphere("fin", 0.12, (lx, 0, 11.7), segments=8, rings=5))
        for k in range(6):  # cage bars
            a = k / 6 * 2 * math.pi + math.pi / 6
            add(P, "Metal", c.box("bar", (0.05, 0.05, 0.95), (lx + 0.44 * math.cos(a), 0.44 * math.sin(a), 10.42)))
    add(P, "Metal", c.sphere("top", 0.22, (ox, 0, 9.95), segments=8, rings=6))


# ======================= BENCH (x = 22) =======================
def bench(ox):
    P = "Bench"
    for i in range(5):
        add(P, "Wood", c.box("slat", (5.0, 0.36, 0.14), (ox, -0.75 + i * 0.38, 1.55)))
    for i in range(3):
        b = c.box("back", (5.0, 0.12, 0.34), (ox, 1.05 + i * 0.05, 2.0 + i * 0.42))
        b.rotation_euler = (math.radians(-12), 0, 0)
        add(P, "Wood", b)
    for s in (-2.2, 2.2):
        add(P, "Iron", c.tube("leg", [(ox + s, -0.9, 0.0), (ox + s, -0.8, 0.8), (ox + s, -0.95, 1.45), (ox + s, -0.6, 2.2), (ox + s, -1.05, 2.25)], [1] * 5, bevel=0.09))
        add(P, "Iron", c.tube("back", [(ox + s, 0.9, 0.0), (ox + s, 0.85, 1.4), (ox + s, 1.15, 2.7), (ox + s, 1.3, 3.1)], [1] * 4, bevel=0.09))
        add(P, "Iron", c.box("seatbar", (0.16, 2.0, 0.14), (ox + s, 0.0, 1.43)))


# ======================= SHRUB (x = 32) =======================
def shrub(ox):
    P = "Shrub"
    leaves = [blob("b", 1.2, (ox, 0, 1.1)), blob("b", 0.95, (ox + 0.9, 0.3, 0.9)), blob("b", 0.9, (ox - 0.8, -0.3, 0.85)), blob("b", 0.8, (ox + 0.1, 0.7, 1.6))]
    for o in leaves:
        add(P, "Leaves", o)
    for k in range(18):
        a = random.uniform(0, 2 * math.pi)
        e = random.uniform(0.15, 1.2)
        r = 1.25
        add(P, "Flowers", c.sphere("fl", 0.17, (ox + r * math.cos(a) * math.cos(e), r * math.sin(a) * math.cos(e), 1.1 + r * math.sin(e)), segments=6, rings=4))


# ======================= FOUNTAIN (x = 60) =======================
def fountain(ox):
    P = "Fountain"

    def L(name, prof, steps=40, group="Stone"):
        o = c.lathe(name, prof, steps=steps)
        for v in o.data.vertices:
            v.co.x += ox
        add(P, group, o)
        return o

    L("pool", [(0.01, 0), (12.2, 0), (12.8, 0.25), (12.8, 1.5), (13.2, 1.7), (13.2, 2.2), (12.95, 2.35), (11.7, 2.35), (11.5, 2.2), (11.5, 0.5), (0.01, 0.5)], 48)
    L("water", [(0.01, 1.9), (11.55, 1.9)], 48, "Water")
    L("pedestal", [(0.01, 0.5), (3.3, 0.5), (3.3, 1.0), (2.6, 1.3), (2.0, 1.9), (1.5, 2.8), (1.3, 3.8), (1.6, 4.3), (2.2, 4.6), (2.0, 4.9), (0.01, 4.9)], 32)
    L("bowl1", [(0.01, 4.8), (1.9, 4.8), (4.2, 5.2), (5.9, 5.8), (6.5, 6.3), (6.6, 6.7), (6.2, 6.8), (5.6, 6.35), (0.01, 6.1)], 40)
    L("bowl1water", [(0.01, 6.45), (5.75, 6.45)], 40, "Water")
    L("stem", [(0.01, 6.1), (1.2, 6.1), (0.95, 6.8), (0.8, 7.8), (1.2, 8.3), (0.85, 8.9), (0.75, 9.6), (1.0, 9.9), (0.01, 9.9)], 24)
    L("bowl2", [(0.01, 9.8), (1.1, 9.8), (2.6, 10.3), (3.3, 10.8), (3.35, 11.1), (3.0, 11.15), (0.01, 10.6)], 32)
    L("bowl2water", [(0.01, 10.95), (2.95, 10.95)], 32, "Water")
    L("finial_base", [(0.01, 10.6), (0.6, 10.6), (0.45, 11.6), (0.7, 12.0), (0.01, 12.2)], 16)
    L("finial", [(0.01, 12.1), (0.45, 12.3), (0.55, 12.8), (0.35, 13.4), (0.12, 13.8), (0.01, 14.0)], 16, "Gold")
    L("fall1", [(6.45, 6.6), (6.75, 5.2), (7.2, 3.6), (7.8, 2.0)], 40, "Falls")
    L("fall2", [(3.25, 11.0), (3.5, 9.6), (3.9, 8.2), (4.5, 6.6)], 32, "Falls")
    for k in range(8):  # carved lion-head spouts on the pedestal: little gold discs
        a = k / 8 * 2 * math.pi
        add(P, "Gold", cyl("spout", 0.28, 0.2, (ox + 2.05 * math.cos(a), 2.05 * math.sin(a), 3.4), 12, (math.pi / 2, 0, a + math.pi / 2)))


# ======================= HOUSE A: 3-storey townhouse (x = 100) =======================
def houseA(ox):
    P = "HouseA"
    W, D = 22.0, 16.0
    y0 = -D / 2
    # rusticated stone ground floor + plaster upper floors
    stone = c.box("stone", (W + 0.4, D + 0.4, 6.4), (ox, 0, 3.2))
    walls = c.box("walls", (W, D, 13.2), (ox, 0, 6.4 + 6.6))
    gcuts = [front_opening(ox + x, y0 - 0.2, 0.4, arch_profile(4.0, 5.4), 1.2) for x in (-7.0, 0.0, 7.0)]
    gcuts += [side_opening(ox + W / 2 + 0.2, y, 0.8, arch_profile(3.0, 4.6), 1.0, 1) for y in (-3.5, 3.5)]
    gcuts += [side_opening(ox - W / 2 - 0.2, y, 0.8, arch_profile(3.0, 4.6), 1.0, -1) for y in (-3.5, 3.5)]
    cut(stone, gcuts)
    ucuts = []
    for x in (-7.0, 0.0, 7.0):
        ucuts.append(front_opening(ox + x, y0, 7.0, arch_profile(2.8, 4.9), 1.0))
        ucuts.append(front_opening(ox + x, y0, 13.6, rect_profile(2.6, 3.7), 1.0))
    for s, xf in ((1, ox + W / 2), (-1, ox - W / 2)):
        for y in (-3.5, 3.5):
            ucuts.append(side_opening(xf, y, 7.4, rect_profile(2.4, 3.8), 0.9, s))
            ucuts.append(side_opening(xf, y, 13.8, rect_profile(2.4, 3.4), 0.9, s))
    cut(walls, ucuts)
    add(P, "Stone", stone)
    add(P, "Walls", walls)
    for k in range(4):  # rustication grooves (thin dark lines) on the stone floor
        add(P, "Trim", c.box("groove", (W + 0.5, D + 0.5, 0.08), (ox, 0, 1.2 + k * 1.3)))
    # ground floor: glass + door + keystones
    for x in (-7.0, 7.0):
        add(P, "Glass", prism("g", arch_profile(3.5, 5.0), y0 + 0.75, y0 + 0.85, lambda u, a, v, x=x: (ox + x + u, a, 0.6 + v)))
        add(P, "Wood", c.box("mull", (0.18, 0.2, 4.8), (ox + x, y0 + 0.7, 3.0)))
        add(P, "Wood", c.box("tran", (3.5, 0.2, 0.18), (ox + x, y0 + 0.7, 3.9)))
    add(P, "Wood", prism("door", rect_profile(3.4, 3.9), y0 + 0.75, y0 + 0.95, lambda u, a, v: (ox + u, a, 0.4 + v)))
    add(P, "Glass", prism("fan", arch_profile(3.4, 5.2), y0 + 0.78, y0 + 0.86, lambda u, a, v: (ox + u, a, 0.4 + v)))
    for x in (-7.0, 0.0, 7.0):
        add(P, "Trim", c.box("key", (0.7, 0.5, 0.9), (ox + x, y0 - 0.35, 5.95)))
    # bands and cornice
    add(P, "Trim", c.box("band1", (W + 0.9, D + 0.9, 0.55), (ox, 0, 6.55)))
    add(P, "Trim", c.box("band2", (W + 0.7, D + 0.7, 0.4), (ox, 0, 13.1)))
    add(P, "Trim", c.box("corn1", (W + 0.8, D + 0.8, 0.5), (ox, 0, 19.35)))
    add(P, "Trim", c.box("corn2", (W + 1.6, D + 1.6, 0.6), (ox, 0, 19.9)))
    for i in range(23):  # brackets under the cornice
        add(P, "Trim", c.box("brk", (0.35, 0.55, 0.5), (ox - W / 2 + 0.5 + i * (W - 1) / 22, y0 - 0.35, 18.9)))
    # upper windows: surrounds, hoods, glass, shutters, flower boxes
    for x in (-7.0, 0.0, 7.0):
        add(P, "Glass", prism("g", arch_profile(2.4, 4.6), y0 + 0.6, y0 + 0.7, lambda u, a, v, x=x: (ox + x + u, a, 7.1 + v)))
        add(P, "Wood", c.box("mull", (0.14, 0.15, 4.5), (ox + x, y0 + 0.55, 9.3)))
        add(P, "Trim", prism("surround", arch_profile(3.5, 5.5), y0 - 0.15, y0 + 0.05, lambda u, a, v, x=x: (ox + x + u, a, 6.8 + v)))
        add(P, "Glass", c.box("g2", (2.2, 0.1, 3.5), (ox + x, y0 + 0.6, 15.45)))
        add(P, "Wood", c.box("mull2", (2.2, 0.14, 0.14), (ox + x, y0 + 0.55, 15.9)))
        add(P, "Trim", c.box("hood", (3.6, 0.6, 0.35), (ox + x, y0 - 0.25, 17.65)))
        add(P, "Trim", c.box("sill", (3.4, 0.7, 0.25), (ox + x, y0 - 0.3, 13.5)))
        for s in (-1, 1):
            sh = c.box("shutter", (1.25, 0.12, 3.7), (ox + x + s * 1.95, y0 - 0.25, 15.45))
            add(P, "Shutters", sh)
            for k in range(6):
                add(P, "Shutters", c.box("louver", (1.1, 0.16, 0.08), (ox + x + s * 1.95, y0 - 0.32, 13.9 + k * 0.6)))
        add(P, "Wood", c.box("box", (2.8, 0.7, 0.55), (ox + x, y0 - 0.55, 13.95)))
        add(P, "Leaves", blob("lv", 0.55, (ox + x, y0 - 0.55, 14.4), 0.3, 1))
        add(P, "Leaves", blob("lv", 0.45, (ox + x - 0.9, y0 - 0.55, 14.35), 0.3, 1))
        add(P, "Leaves", blob("lv", 0.45, (ox + x + 0.9, y0 - 0.55, 14.35), 0.3, 1))
        for k in range(5):
            add(P, "Flowers", c.sphere("f", 0.16, (ox + x - 1.1 + k * 0.55, y0 - 0.85, 14.65 + 0.1 * (k % 2)), segments=6, rings=4))
    # balcony with wrought-iron railing on floor 2
    add(P, "Trim", c.box("balc", (17.0, 2.0, 0.45), (ox, y0 - 1.0, 6.95)))
    for x in (-7.5, -2.5, 2.5, 7.5):
        b = c.box("bracket", (0.5, 1.6, 0.9), (ox + x, y0 - 0.75, 6.35))
        add(P, "Trim", b)
    add(P, "Iron", c.box("rail", (17.0, 0.12, 0.12), (ox, y0 - 1.9, 8.25)))
    add(P, "Iron", c.box("rail", (17.0, 0.1, 0.1), (ox, y0 - 1.9, 7.35)))
    for s in (-1, 1):
        add(P, "Iron", c.box("rails", (0.12, 1.9, 0.12), (ox + s * 8.45, y0 - 1.0, 8.25)))
    for i in range(43):
        add(P, "Iron", c.box("bar", (0.06, 0.06, 1.1), (ox - 8.4 + i * 0.4, y0 - 1.9, 7.75)))
    add(P, "Leaves", blob("vine", 0.7, (ox - 8.3, y0 - 1.6, 8.6), 0.35, 1))
    add(P, "Flowers", blob("bougain", 0.65, (ox - 8.6, y0 - 1.5, 8.2), 0.4, 1))
    add(P, "Flowers", blob("bougain", 0.55, (ox - 8.9, y0 - 1.2, 7.4), 0.4, 1))
    # roof
    roof = hip_roof("roof", ox - W / 2 - 1.3, ox + W / 2 + 1.3, -D / 2 - 1.3, D / 2 + 1.3, 20.2, 5.2, 6.5)
    add(P, "Roof", roof)
    add(P, "Trim", c.box("fascia", (W + 2.7, D + 2.7, 0.3), (ox, 0, 20.25)))
    add(P, "Brick", c.box("chimney", (1.6, 1.6, 4.0), (ox + 5.5, 2.5, 24.0)))
    add(P, "Trim", c.box("chimcap", (2.0, 2.0, 0.35), (ox + 5.5, 2.5, 26.1)))
    # side glass
    for s, xf in ((1, ox + W / 2), (-1, ox - W / 2)):
        for y in (-3.5, 3.5):
            add(P, "Glass", c.box("sg", (0.1, 2.2, 3.6), (xf - s * 0.7, y, 9.3)))
            add(P, "Glass", c.box("sg", (0.1, 2.2, 3.2), (xf - s * 0.7, y, 15.5)))
            add(P, "Glass", prism("sg", arch_profile(2.6, 4.2), xf - s * 0.8, xf - s * 0.7, lambda u, a, v, y=y: (a, y + u, 0.9 + v)))


# ======================= HOUSE B: 2-storey shophouse with awning (x = 140) =======================
def houseB(ox):
    P = "HouseB"
    W, D, H = 20.0, 16.0, 13.0
    y0 = -D / 2
    walls = c.box("walls", (W, D, H), (ox, 0, H / 2))
    cuts = [front_opening(ox, y0, 0.4, rect_profile(15.0, 5.2), 1.4)]
    for x in (-6.0, 0.0, 6.0):
        cuts.append(front_opening(ox + x, y0, 7.6, arch_profile(2.6, 4.2), 1.0))
    for s, xf in ((1, ox + W / 2), (-1, ox - W / 2)):
        for y in (-3.5, 3.5):
            cuts.append(side_opening(xf, y, 1.2, rect_profile(2.6, 3.6), 0.9, s))
            cuts.append(side_opening(xf, y, 7.8, rect_profile(2.4, 3.4), 0.9, s))
    cut(walls, cuts)
    add(P, "Walls", walls)
    add(P, "Stone", c.box("plinth", (W + 0.4, D + 0.4, 0.8), (ox, 0, 0.4)))
    # shopfront: glass grid, door, sign board
    add(P, "Glass", c.box("shopglass", (14.8, 0.12, 4.9), (ox, y0 + 1.25, 2.85)))
    for i in range(7):
        add(P, "Wood", c.box("mull", (0.22, 0.2, 5.0), (ox - 7.3 + i * (14.6 / 6), y0 + 1.15, 2.9)))
    add(P, "Wood", c.box("tran", (15.0, 0.2, 0.22), (ox, y0 + 1.15, 4.4)))
    add(P, "Wood", c.box("door", (2.6, 0.25, 3.9), (ox, y0 + 1.2, 2.35)))
    add(P, "Wood", c.box("signboard", (12.0, 0.35, 1.3), (ox, y0 - 0.2, 6.4)))
    add(P, "Trim", c.box("signframe", (12.5, 0.3, 1.7), (ox, y0 - 0.1, 6.4)))
    # scalloped two-colour awning
    n = 10
    for i in range(n):
        x = ox - 7.5 + (i + 0.5) * 15.0 / n
        a = c.box("aw", (15.0 / n - 0.02, 3.0, 0.12), (x, y0 - 1.35, 5.55))
        a.rotation_euler = (math.radians(24), 0, 0)
        add(P, "Awning1" if i % 2 == 0 else "Awning2", a)
        sc = cyl("scallop", 15.0 / n / 2, 0.1, (x, y0 - 2.73, 4.95), 12, (math.pi / 2, 0, 0))
        add(P, "Awning1" if i % 2 == 0 else "Awning2", sc)
    add(P, "Iron", c.box("awbar", (15.2, 0.1, 0.1), (ox, y0 - 2.75, 4.95)))
    # upper floor windows with shutters, Juliet balconies and flowers
    for x in (-6.0, 0.0, 6.0):
        add(P, "Glass", prism("g", arch_profile(2.2, 3.9), y0 + 0.6, y0 + 0.7, lambda u, a, v, x=x: (ox + x + u, a, 7.7 + v)))
        add(P, "Trim", prism("surround", arch_profile(3.3, 4.8), y0 - 0.15, y0 + 0.05, lambda u, a, v, x=x: (ox + x + u, a, 7.3 + v)))
        add(P, "Trim", c.box("sill", (3.4, 0.7, 0.25), (ox + x, y0 - 0.3, 7.45)))
        for s in (-1, 1):
            add(P, "Shutters", c.box("shutter", (1.15, 0.12, 3.6), (ox + x + s * 1.85, y0 - 0.25, 9.5)))
            for k in range(6):
                add(P, "Shutters", c.box("louver", (1.0, 0.16, 0.08), (ox + x + s * 1.85, y0 - 0.32, 8.0 + k * 0.58)))
        add(P, "Iron", c.box("jrail", (2.8, 0.1, 0.1), (ox + x, y0 - 0.75, 8.9)))
        for k in range(8):
            add(P, "Iron", c.box("jbar", (0.05, 0.05, 1.3), (ox + x - 1.35 + k * 0.385, y0 - 0.75, 8.25)))
        add(P, "Leaves", blob("lv", 0.5, (ox + x - 0.6, y0 - 0.55, 7.9), 0.3, 1))
        add(P, "Leaves", blob("lv", 0.5, (ox + x + 0.6, y0 - 0.55, 7.9), 0.3, 1))
        for k in range(4):
            add(P, "Flowers", c.sphere("f", 0.17, (ox + x - 0.9 + k * 0.6, y0 - 0.85, 8.25), segments=6, rings=4))
    add(P, "Trim", c.box("band", (W + 0.7, D + 0.7, 0.45), (ox, 0, 7.0)))
    add(P, "Trim", c.box("corn", (W + 1.2, D + 1.2, 0.55), (ox, 0, H + 0.1)))
    # front gable roof (ridge front-to-back) with a round window in the gable
    rh = 5.5
    v = [(ox - W / 2 - 1, -D / 2 - 1.2, H + 0.4), (ox + W / 2 + 1, -D / 2 - 1.2, H + 0.4), (ox, -D / 2 - 1.2, H + 0.4 + rh + 0.4),
         (ox - W / 2 - 1, D / 2 + 1.2, H + 0.4), (ox + W / 2 + 1, D / 2 + 1.2, H + 0.4), (ox, D / 2 + 1.2, H + 0.4 + rh + 0.4)]
    for s in (-1, 1):
        a, b = (0, 2) if s < 0 else (2, 1)
        # left slope uses verts 0,2,5,3 ; right slope 2,1,4,5 (thin slabs)
    roofL = mesh_from("roofL", [v[0], v[2], v[5], v[3], (v[0][0], v[0][1], v[0][2] - 0.4), (v[2][0], v[2][1], v[2][2] - 0.4), (v[5][0], v[5][1], v[5][2] - 0.4), (v[3][0], v[3][1], v[3][2] - 0.4)],
                      [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
    roofR = mesh_from("roofR", [v[2], v[1], v[4], v[5], (v[2][0], v[2][1], v[2][2] - 0.4), (v[1][0], v[1][1], v[1][2] - 0.4), (v[4][0], v[4][1], v[4][2] - 0.4), (v[5][0], v[5][1], v[5][2] - 0.4)],
                      [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
    add(P, "Roof", roofL)
    add(P, "Roof", roofR)
    for yy in (-D / 2, D / 2 - 0.4):
        gab = mesh_from("gable", [(ox - W / 2, yy, H + 0.4), (ox + W / 2, yy, H + 0.4), (ox, yy, H + 0.4 + rh),
                                  (ox - W / 2, yy + 0.4, H + 0.4), (ox + W / 2, yy + 0.4, H + 0.4), (ox, yy + 0.4, H + 0.4 + rh)],
                        [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)])
        add(P, "Walls", gab)
    add(P, "Trim", cyl("oculus_ring", 1.05, 0.3, (ox, -D / 2 - 0.15, H + 2.6), 20, (math.pi / 2, 0, 0)))
    add(P, "Glass", cyl("oculus", 0.8, 0.32, (ox, -D / 2 - 0.17, H + 2.6), 20, (math.pi / 2, 0, 0)))
    add(P, "Brick", c.box("chimney", (1.5, 1.5, 3.5), (ox - 5.0, 3.0, H + 4.5)))


palm(0)
lamp(12)
bench(22)
shrub(32)
fountain(60)
houseA(100)
houseB(140)

SPEC = {
    "Trunk": ("bark", 0.0, True), "Fronds": ("frond", 0.0, True), "Coconuts": ("coconut", 0.0, True),
    "Metal": ("black", 0.0, True), "Glass": ("glass", 0.0, False), "Wood": ("wood", 0.0, False), "Iron": ("black", 0.0, False),
    "Leaves": ("leaf", 0.0, True), "Flowers": ("pink", 0.0, True), "Stone": ("stone", 0.06, False), "Water": ("water", 0.0, True),
    "Falls": ("water", 0.0, True), "Gold": ("gold", 0.0, True), "Walls": ("salmon", 0.0, False), "Trim": ("white", 0.0, False),
    "Shutters": ("teal", 0.0, False), "Roof": ("terracotta", 0.0, False), "Brick": ("brick", 0.0, False),
    "Awning1": ("red", 0.0, False), "Awning2": ("white", 0.0, False),
}
UV_GROUPS = {"Walls", "Stone", "Roof", "Brick", "Trim", "Wood"}
final = []
for (piece, group), objs in GROUPS.items():
    obj = c.join(objs, f"{piece}_{group}") if len(objs) > 1 else objs[0]
    col, bev, smooth = SPEC[group]
    if piece == "Lamp" and group == "Glass":
        col = "warmglow"
    c.finish(obj, f"{piece}_{group}", col, bevel=bev, smooth=smooth)
    if group in UV_GROUPS:
        uv_box(obj, 8.0 if group != "Roof" else 6.0)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
for piece in sorted({p for p, _ in GROUPS}):
    objs = [o for o in final if o.name.startswith(piece + "_")]
    print("KIT", piece, "triangles", c.triangle_count(objs))
c.export_glb(os.path.join(c.OUT_MODELS, "TownKit.glb"), final)
def shot(path, tx, tz, dist, h):
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    if scene.world is None:
        scene.world = bpy.data.worlds.new("W")
    scene.world.color = (0.82, 0.86, 0.9)
    cam = bpy.data.objects.get("ShotCam")
    if cam is None:
        cam = bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam"))
        bpy.context.collection.objects.link(cam)
    cam.location = (tx + dist * 0.5, -dist, h)
    cam.rotation_euler = (mathutils.Vector((tx, 0, tz)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


shot(os.path.join(c.OUT_PREVIEWS, "TownKit_props.png"), 22, 5, 38, 12)
shot(os.path.join(c.OUT_PREVIEWS, "TownKit_fountain.png"), 60, 5, 30, 14)
shot(os.path.join(c.OUT_PREVIEWS, "TownKit_houseA.png"), 100, 11, 40, 14)
shot(os.path.join(c.OUT_PREVIEWS, "TownKit_houseB.png"), 140, 8, 34, 10)
print("done")
