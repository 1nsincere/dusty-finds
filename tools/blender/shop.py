"""Curio Emporium: the player shop shell (Blender 5.x, headless). One design for all six plots; Studio recolours the accent per shop.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/shop.py
Writes assets/models/Shop.glb and assets/previews/Shop_*.png (git-ignored).

Built in the plot's own BASE coordinates (the 40 x 40 plot before the 1.4x scale; Studio scales it with the plot).
Mapping: plot local (x, height, z) -> Blender (x, -z, height). The plot front (park side, door) is plot z = -20 = Blender y = +20.
Kept OUT of the mesh on purpose (gameplay parts stay as they are): the ground-floor back wall (PlotService opens it for the
Back Room / Showroom), the counter, shelves, slots, bench, exhibits, decor, sign, spawn and customer path.
Groups: Shop_<Group> for the ground floor (always visible) and Shop_Up<Group> / Shop_Roof for the upper storey and roof,
which Studio puts into Facade.Upper / Facade.Roof so RoofController hides them when you walk in.
Layout around the existing parts: gallery shelving (left), checkout nook (right front), restoration workshop (right back),
collector's vault (back, around the exhibits), window displays either side of the door.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"sand": "EFE2C4", "white": "FBF7EC", "glass": "3E6A8A", "stone": "CFC5B0", "wood": "6B4A2E", "leaf": "3F7F3A",
                  "pink": "E0458C", "gold": "E3B23C", "accent": "1F7A7A", "stripe": "FBF7EC", "velvet": "8E1F2F", "jar": "7FB7A5"})
c.reset_scene()
STYLE = os.environ.get("DF_SHOP_STYLE", "A").upper()   # A Curio Emporium, B Bahay na bato, C Escolta Art Deco
SUFFIX = "" if STYLE == "A" else "_" + STYLE
G = {}
F0 = 0.5          # plot floor top
H1 = 12.5         # ground floor wall top (the existing collision walls stop here)
H2 = 22.0         # upper storey top
T = 1.2           # wall thickness (outer faces at +-20.2)
OUT = 20.2


def add(group, obj):
    G.setdefault(group, []).append(obj)
    return obj


def B(px, py, pz):
    """plot local -> Blender"""
    return (px, -pz, py)


def box(group, center, size, name="b"):
    """center/size in plot local (x, height, z)."""
    return add(group, c.box(name, (size[0], size[2], size[1]), B(*center)))


def cyl(name, r, h, loc, verts=16, rot=(0, 0, 0)):
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


def arch(w, h, segs=12):
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0), (r, h - r)]
    pts += [(r * math.cos(math.pi * i / segs), h - r + r * math.sin(math.pi * i / segs)) for i in range(1, segs)]
    return pts + [(-r, h - r)]


def rect(w, h):
    return [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h), (-w / 2, h)]


def prism(pts, a0, a1, place):
    n = len(pts)
    verts = [place(u, a, v) for a in (a0, a1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return mesh_from("p", verts, faces)


def front(px, py, pts, z0, z1):
    """Prism through the front/back walls: profile in (x, height), extruded along plot z from z0 to z1."""
    return prism(pts, z0, z1, lambda u, a, v: B(px + u, py + v, a))


def side(pz, py, pts, x0, x1):
    """Prism through the side walls: profile in (z, height), extruded along plot x."""
    return prism(pts, x0, x1, lambda u, a, v: B(a, py + v, pz + u))


def boolean(target, other, op="DIFFERENCE"):
    mod = target.modifiers.new("b", "BOOLEAN")
    mod.object = other
    mod.operation = op
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="b")
    bpy.data.objects.remove(other, do_unlink=True)


def join(objs, name):
    return c.join(objs, name) if len(objs) > 1 else objs[0]


def blob(r, loc, strength=0.28, subdiv=2):
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


# ===================== GROUND FLOOR SHELL (front + both sides; NO back wall) =====================
wl = c.box("w", (T, 2 * OUT, H1 - F0), B(-OUT + T / 2, F0 + (H1 - F0) / 2, 0))
wr = c.box("w", (T, 2 * OUT, H1 - F0), B(OUT - T / 2, F0 + (H1 - F0) / 2, 0))
wf = c.box("w", (2 * OUT, T, H1 - F0), B(0, F0 + (H1 - F0) / 2, -OUT + T / 2))
cuts = [front(0, F0 - 0.3, arch(8.0, 10.0), -OUT - 0.6, -OUT + T + 0.6)]           # walk-in doorway (matches the 8-stud gap)
for x in (-11.0, 11.0):
    cuts.append(front(x, F0 + 1.4, arch(7.4, 8.4), -OUT - 0.6, -OUT + T + 0.6))   # display windows
boolean(wf, join(cuts, "c"))
lcuts = [side(z, F0 + 8.6, arch(3.0, 3.2), -OUT - 0.6, -OUT + T + 0.6) for z in (-7.5, 1.5, 10.5)]   # gallery clerestory
rcuts = [side(z, F0 + 3.0, arch(3.6, 6.5), OUT - T - 0.6, OUT + 0.6) for z in (-13.0, 2.0)]          # checkout + workshop light
boolean(wl, join(lcuts, "c"))
boolean(wr, join(rcuts, "c"))
for w in (wl, wr, wf):
    add("Walls", w)
# stone plinth, quoins, band at the ground floor top, keystones
box("Stone", (0, F0 + 0.6, -OUT - 0.25), (2 * OUT + 0.6, 1.2, 0.5))
for s in (-1, 1):
    box("Stone", (s * (OUT + 0.25), F0 + 0.6, 0), (0.5, 1.2, 2 * OUT + 0.6))
    for k in range(6):
        h = F0 + 1.0 + k * 3.6
        box("Stone", (s * (OUT - 0.4), h, -OUT - 0.1), (1.8 if k % 2 else 1.2, 1.5, 1.0))
        box("Stone", (s * (OUT + 0.1), h, -OUT + 0.6), (1.0, 1.5, 1.8 if k % 2 == 0 else 1.2))
box("Trim", (0, H1 + 0.1, -OUT - 0.3), (2 * OUT + 1.0, 0.7, 0.8))
for s in (-1, 1):
    box("Trim", (s * (OUT + 0.3), H1 + 0.1, 0), (0.8, 0.7, 2 * OUT + 1.0))
# doorway: moulded surround with keystone, transom glass, brass threshold
sur = front(0, F0 - 0.3, [(u * 4.8 / 4.0, v * 10.8 / 10.0) for (u, v) in arch(8.0, 10.0)], -OUT - 0.35, -OUT + 0.05)
boolean(sur, front(0, F0 - 0.31, arch(8.0, 10.01), -OUT - 0.8, -OUT + 0.6))
add("Trim", sur)
box("Trim", (0, F0 + 10.6, -OUT - 0.35), (1.0, 1.3, 0.7))
box("Gold", (0, F0 + 0.03, -OUT + T / 2), (8.0, 0.06, T + 0.4))
# display windows: glass, mullions, surround, sill, flower box and a scalloped accent awning each
for x in (-11.0, 11.0):
    add("Glass", front(x, F0 + 1.45, arch(7.3, 8.3), -OUT + T / 2 - 0.05, -OUT + T / 2 + 0.05))
    for dx in (-1.8, 1.8):
        box("Wood", (x + dx, F0 + 4.6, -OUT + T / 2), (0.18, 6.4, 0.22))
    box("Wood", (x, F0 + 5.6, -OUT + T / 2), (7.3, 0.18, 0.22))
    s2 = front(x, F0 + 1.1, [(u * 4.15 / 3.7, v * 9.0 / 8.4) for (u, v) in arch(7.4, 8.4)], -OUT - 0.32, -OUT + 0.05)
    boolean(s2, front(x, F0 + 1.39, arch(7.4, 8.41), -OUT - 0.8, -OUT + 0.6))
    add("Trim", s2)
    box("Trim", (x, F0 + 1.2, -OUT - 0.4), (8.6, 0.35, 0.9))
    box("Wood", (x, F0 + 0.65, -OUT - 0.75), (7.6, 0.8, 0.8))
    for k in range(5):
        add("Leaves", blob(0.55, B(x - 3.0 + k * 1.5, F0 + 1.25, -OUT - 0.8)))
        add("Flowers", c.sphere("f", 0.2, B(x - 3.2 + k * 1.5, F0 + 1.65, -OUT - 1.05), segments=6, rings=4))
        add("Flowers", c.sphere("f", 0.18, B(x - 2.6 + k * 1.5, F0 + 1.55, -OUT - 1.1), segments=6, rings=4))
    n = 8
    for i in range(n):
        ax = x - 4.2 + (i + 0.5) * 8.4 / n
        a = c.box("aw", (8.4 / n - 0.02, 2.8, 0.1), B(ax, F0 + 9.75, -OUT - 1.25))
        a.rotation_euler = (math.radians(-26), 0, 0)
        add("Accent" if i % 2 == 0 else "Stripe", a)
        add("Accent" if i % 2 == 0 else "Stripe", cyl("sc", 8.4 / n / 2, 0.08, B(ax, F0 + 9.15, -OUT - 2.5), 12, (math.pi / 2, 0, 0)))
    box("Iron", (x, F0 + 9.15, -OUT - 2.5), (8.6, 0.1, 0.1))
    for s in (-1, 1):
        box("Iron", (x + s * 4.2, F0 + 9.5, -OUT - 1.4), (0.08, 0.08, 2.4))
# fascia frame around the existing Sign part (plot (0, 11, -20.3)), lanterns either side of the door
box("Wood", (0, F0 + 10.55, -OUT - 0.12), (12.0, 2.6, 0.25))
box("Gold", (0, F0 + 10.55, -OUT - 0.2), (12.6, 3.1, 0.12))
for s in (-1, 1):
    box("Iron", (s * 5.4, F0 + 7.6, -OUT - 0.5), (0.12, 0.12, 1.0))
    add("Iron", c.lathe("lantern_top", [(0.01, 9.1), (0.45, 9.1), (0.12, 9.5), (0.01, 9.6)], 6))
    G["Iron"][-1].location = B(s * 5.4, F0 - 0.9, -OUT - 1.0)
    add("Lamp", cyl("lan", 0.32, 0.9, B(s * 5.4, F0 + 7.75, -OUT - 1.0), 6))
# outdoor planters with bougainvillea climbing the front-right corner
for s in (-1, 1):
    add("Stone", c.lathe("pot", [(0.01, 0), (0.8, 0), (1.0, 0.9), (1.1, 1.2), (0.01, 1.2)], 12))
    G["Stone"][-1].location = B(s * 6.2, F0 - 0.5, -OUT - 1.6)
    add("Leaves", blob(0.9, B(s * 6.2, F0 + 1.3, -OUT - 1.6)))
    add("Flowers", blob(0.35, B(s * 6.2 + 0.4, F0 + 1.8, -OUT - 2.0), 0.25))
for k in range(10):
    zc = F0 + 1.0 + k * 1.95
    for j in range(2):
        add("Leaves" if zc < H1 else "UpLeaves", blob(0.55, B(OUT + 0.4 - 0.5 * j, zc + 0.5 * j, -OUT - 0.4 - 0.3 * j)))
    for j in range(3):
        add("Flowers" if zc < H1 else "UpFlowers", blob(0.27, B(OUT + 0.5 - 0.4 * j, zc + 0.4 + 0.3 * j, -OUT - 0.75 - 0.2 * j), 0.25))

# ===================== INTERIOR SECTIONS =====================
box("Floor", (0, F0 + 0.03, 0), (2 * (OUT - T), 0.06, 2 * (OUT - T) + 1.0))
for x in range(-18, 19, 6):   # ceiling beams (seen from above when the roof hides)
    box("Wood", (x, H1 - 0.35, 0), (0.6, 0.7, 2 * (OUT - T)))
# 1. gallery wall (left): arched wooden shelving surround around the 4 shelves, spotlights, brass price rail
for z in (-16.5, -7.5, 1.5, 10.5, 19.0):
    box("Wood", (-18.0, F0 + 4.5, z), (2.4, 9.0, 0.9))
box("Wood", (-18.0, F0 + 9.3, 1.25), (2.6, 0.7, 36.5))
box("Wood", (-18.9, F0 + 4.5, 1.25), (0.3, 9.0, 36.0))
for z in (-12.0, -3.0, 6.0, 15.0):
    ar = side(z, F0 + 5.2, [(u * 4.4 / 4.0, v) for (u, v) in arch(8.0, 3.6)], -18.85, -18.6)
    add("Trim", ar)
    add("Lamp", cyl("spot", 0.3, 0.4, B(-17.0, F0 + 8.7, z), 10))
    box("Gold", (-17.0, F0 + 9.0, z), (0.2, 0.3, 0.2))
box("Gold", (-15.9, F0 + 3.9, 1.25), (0.12, 0.12, 35.0))
# 2. checkout nook (right front): back shelving with jars, a clock, chalkboard frame around the SupplyBoard
# The jar shelf and clock are their own Nook* groups (Sean, 2026-11-24): the Showroom stairs run along this wall, so
# PlotService hides Shop_Nook* / Shop_Jars in shops that own the Showroom. Kept out of Shop_Wood / Shop_Trim / Shop_Gold.
box("NookWood", (18.6, F0 + 4.0, -7.5), (1.6, 8.0, 10.0))
for k, hgt in enumerate((2.2, 4.4, 6.6)):
    box("NookTrim", (17.7, F0 + hgt, -7.5), (0.5, 0.15, 9.6))
    for j in range(7):
        add("Jars", cyl("jar", 0.32, 0.8 + 0.15 * (j % 3), B(17.6, F0 + hgt + 0.5, -11.5 + j * 1.3), 10))
add("NookGold", cyl("clock", 0.9, 0.15, B(17.8, F0 + 9.6, -7.5), 20, (0, math.pi / 2, 0)))
add("NookTrim", cyl("clockface", 0.75, 0.17, B(17.75, F0 + 9.6, -7.5), 20, (0, math.pi / 2, 0)))
box("Wood", (14.0, F0 + 5.0, -18.7), (5.4, 4.4, 0.25))     # frame behind the SupplyBoard (plot (14, 5.5, -18.8))
box("Gold", (14.0, F0 + 7.5, -18.7), (5.6, 0.25, 0.3))
# 3. restoration workshop (right back): raised platform, glass half wall, tool pegboard, work lamp
box("Wood", (13.5, F0 + 0.12, 14.2), (12.0, 0.24, 10.0))
box("Wood", (7.6, F0 + 1.2, 14.2), (0.3, 2.2, 10.0))
add("Glass", c.box("g", (0.1, 10.0, 2.6), B(7.6, F0 + 3.6, 14.2)))
box("Wood", (7.6, F0 + 4.95, 14.2), (0.35, 0.25, 10.2))
for z in (9.3, 14.2, 19.0):
    box("Wood", (7.6, F0 + 2.5, z), (0.3, 5.0, 0.3))
box("Wood", (18.9, F0 + 6.5, 14.0), (0.25, 5.0, 8.0))
for i in range(6):   # tool silhouettes on the pegboard
    box("Iron", (18.65, F0 + 5.0 + (i % 2) * 2.2, 10.8 + i * 1.3), (0.15, 1.6, 0.25))
    box("Iron", (18.65, F0 + 5.8 + (i % 2) * 2.2, 10.8 + i * 1.3), (0.15, 0.3, 0.7))
add("Iron", c.tube("lamparm", [B(17.5, F0 + 4.2, 16.5), B(16.5, F0 + 7.5, 16.0), B(14.0, F0 + 7.8, 15.0)], [1, 1, 1], bevel=0.1))
add("Lamp", c.sphere("worklamp", 0.45, B(13.8, F0 + 7.4, 14.9), segments=10, rings=6))
# 4. collector's vault (back): free-standing arches over the exhibit row, gold rope posts with velvet rope, plaques
# The vault is its own Vault* groups (+ the existing Velvet) (Sean, 2026-11-24): the Showroom moves every exhibit
# pedestal upstairs, so PlotService hides Shop_Vault* / Shop_Velvet in shops that own the Showroom.
for x in (-12.5, -7.5, -2.5, 2.5, 7.0):
    box("VaultTrim", (x, F0 + 3.5, 17.6), (0.8, 7.0, 0.8))
for x in (-10.0, -5.0, 0.0, 5.0):
    add("VaultTrim", front(x, F0 + 6.0, [(u * 5.0 / 4.2, v) for (u, v) in arch(4.2, 2.6)], 17.3, 17.9))
    add("VaultLamp", cyl("vspot", 0.25, 0.3, B(x, F0 + 7.6, 16.2), 10))
    box("VaultGold", (x, F0 + 0.9, 14.4), (0.9, 0.5, 0.12))
for x in (-12.5, -6.5, -0.5, 5.5):
    add("VaultGold", c.lathe("post", [(0.01, 0), (0.45, 0), (0.12, 0.2), (0.1, 2.4), (0.25, 2.6), (0.01, 2.8)], 10))
    G["VaultGold"][-1].location = B(x, F0, 12.8)
for x0, x1 in ((-12.5, -6.5), (-6.5, -0.5), (-0.5, 5.5)):
    add("Velvet", c.tube("rope", [B(x0, F0 + 2.4, 12.8), B((x0 + x1) / 2, F0 + 1.7, 12.8), B(x1, F0 + 2.4, 12.8)], [1, 1, 1], bevel=0.11))
# window display plinths behind the front windows
for x in (-12.5, 12.5):
    add("Trim", c.lathe("plinth", [(0.01, 0), (1.3, 0), (1.3, 0.3), (1.0, 0.45), (1.0, 1.6), (1.3, 1.8), (0.01, 1.8)], 16))
    G["Trim"][-1].location = B(x, F0, -17.6)
    add("Gold", c.lathe("vase", [(0.01, 0), (0.35, 0), (0.55, 0.5), (0.3, 1.0), (0.4, 1.2), (0.01, 1.2)], 12))
    G["Gold"][-1].location = B(x, F0 + 1.8, -17.6)

# ===================== UPPER STOREY (hidden while inside) =====================
uw = c.box("uw", (2 * OUT, 2 * OUT, H2 - H1), B(0, H1 + (H2 - H1) / 2, 0))
ui = c.box("ui", (2 * (OUT - T), 2 * (OUT - T), H2 - H1 + 2.0), B(0, H1 + (H2 - H1) / 2 - 0.4, 0))
boolean(uw, ui)
ucuts = []
for x in (-12.0, 0.0, 12.0):
    ucuts.append(front(x, H1 + 1.6, arch(3.2, 5.6) if x else rect(3.2, 5.6), -OUT - 0.6, -OUT + T + 0.6))
    ucuts.append(front(x, H1 + 1.6, rect(3.0, 5.0), OUT - T - 0.6, OUT + 0.6))
for z in (-8.0, 8.0):
    ucuts.append(side(z, H1 + 1.8, rect(3.0, 5.0), -OUT - 0.6, -OUT + T + 0.6))
    ucuts.append(side(z, H1 + 1.8, rect(3.0, 5.0), OUT - T - 0.6, OUT + 0.6))
boolean(uw, join(ucuts, "c"))
add("UpWalls", uw)
box("UpTrim", (0, H1 + 0.15, 0), (2 * OUT - 0.2, 0.3, 2 * OUT - 0.2))      # upper floor slab (the ground floor ceiling)
for x in (-12.0, 0.0, 12.0):
    add("UpGlass", front(x, H1 + 1.65, arch(3.1, 5.5) if x else rect(3.1, 5.5), -OUT + T / 2 - 0.04, -OUT + T / 2 + 0.04))
    add("UpGlass", front(x, H1 + 1.65, rect(2.9, 4.9), OUT - T / 2 - 0.04, OUT - T / 2 + 0.04))
    box("UpTrim", (x, H1 + 1.45, -OUT - 0.35), (4.4, 0.3, 0.8))
    box("UpTrim", (x, H1 + 7.6, -OUT - 0.25), (4.2, 0.35, 0.6))
    if STYLE == "A":
        for s in (-1, 1):
            box("UpAccent", (x + s * 2.3, H1 + 4.4, -OUT - 0.25), (1.3, 5.4, 0.15))
            for k in range(7):
                box("UpAccent", (x + s * 2.3, H1 + 2.0 + k * 0.75, -OUT - 0.33), (1.15, 0.09, 0.16))
    elif STYLE == "B":   # sliding capiz panels: wooden grid over the glass, ventanilla panel below
        for k in range(1, 4):
            box("UpWood", (x - 1.55 + k * 0.78, H1 + 4.4, -OUT - 0.1), (0.12, 5.5, 0.14))
        for k in range(1, 4):
            box("UpWood", (x, H1 + 1.65 + k * 1.38, -OUT - 0.1), (3.1, 0.12, 0.14))
        box("UpAccent", (x, H1 + 0.9, -OUT - 0.2), (3.4, 0.9, 0.15))
    else:                # Art Deco: tall fins either side of every window
        for s in (-1, 1):
            box("UpTrim", (x + s * 2.4, H1 + 4.6, -OUT - 0.35), (0.5, 8.6, 0.7))
for z in (-8.0, 8.0):
    for sx in (-1, 1):
        add("UpGlass", side(z, H1 + 1.85, rect(2.9, 4.9), sx * (OUT - T / 2) - 0.04, sx * (OUT - T / 2) + 0.04))
        box("UpTrim", (sx * (OUT + 0.3), H1 + 1.65, z), (0.8, 0.3, 4.0))
# balcony on the middle window: slab, brackets, wrought-iron rail, flower boxes on the side windows (style A only)
BALC = STYLE == "A"
if BALC: box("UpTrim", (0, H1 + 1.3, -OUT - 1.2), (7.0, 0.4, 2.4))
for s in (-1, 1) if BALC else ():
    box("UpTrim", (s * 2.8, H1 + 0.7, -OUT - 0.8), (0.5, 0.9, 1.5))
if BALC:
    box("UpIron", (0, H1 + 3.1, -OUT - 2.35), (7.0, 0.12, 0.12))
    box("UpIron", (0, H1 + 1.7, -OUT - 2.35), (7.0, 0.1, 0.1))
for s in (-1, 1) if BALC else ():
    box("UpIron", (s * 3.45, H1 + 3.1, -OUT - 1.2), (0.12, 0.12, 2.3))
for i in range(18 if BALC else 0):
    box("UpIron", (-3.4 + i * 0.4, H1 + 2.4, -OUT - 2.35), (0.06, 1.4, 0.06))
for x in ((-12.0, 12.0) if STYLE != "C" else ()):
    box("UpWood", (x, H1 + 1.25, -OUT - 0.7), (3.4, 0.6, 0.8))
    for k in range(4):
        add("UpLeaves", blob(0.45, B(x - 1.2 + k * 0.8, H1 + 1.7, -OUT - 0.75)))
        add("UpFlowers", c.sphere("f", 0.18, B(x - 1.3 + k * 0.85, H1 + 2.05, -OUT - 1.0), segments=6, rings=4))
# cornice + hanging blade sign bracket
box("UpTrim", (0, H2 - 0.3, 0), (2 * OUT + 0.8, 0.6, 2 * OUT + 0.8))
box("UpTrim", (0, H2 + 0.25, 0), (2 * OUT + 1.6, 0.5, 2 * OUT + 1.6))
for i in range(40):
    box("UpTrim", (-OUT + 0.5 + i * (2 * OUT - 1) / 39, H2 - 0.85, -OUT - 0.3), (0.35, 0.5, 0.5))
box("UpIron", (-OUT - 1.3, H1 + 5.0, -OUT - 0.2), (2.8, 0.15, 0.15))
add("UpAccent", c.box("blade", (0.25, 2.6, 3.4), B(-OUT - 2.2, H1 + 3.1, -OUT - 0.2)))
add("UpGold", c.box("bladeframe", (0.18, 2.9, 3.7), B(-OUT - 2.2, H1 + 3.1, -OUT - 0.2)))

# ===================== ROOF (hidden while inside) =====================
RB = H2 + 0.5
if STYLE == "A":
    RB = H2 + 0.5
    RISE = 7.0
    y0, y1 = -OUT - 1.4, OUT + 1.4      # Blender y range (front at +y)
    x0, x1 = -OUT - 1.4, OUT + 1.4
    run = (y1 - y0) / 2
    th = math.atan2(RISE, run)
    L = math.hypot(run, RISE)
    for s in (-1, 1):   # slopes face front (+y, s=1) and back (-y, s=-1); ridge along x
        ey = s * run
        dyy, dz = -s * run / L, RISE / L
        ny, nz = s * math.sin(th), math.cos(th)

        def P(a, v, xx, ey=ey, dyy=dyy, dz=dz, ny=ny, nz=nz):
            return (xx, ey + dyy * a + ny * v, RB + dz * a + nz * v)
        add("Roof", mesh_from("slab", [P(0, -0.35, x0), P(L, -0.35, x0), P(L, -0.35, x1), P(0, -0.35, x1), P(0, 0, x0), P(L, 0, x0), P(L, 0, x1), P(0, 0, x1)],
                              [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]))
        semi = [(0.42 * math.cos(math.pi * k / 6), 0.42 * math.sin(math.pi * k / 6)) for k in range(7)]
        xx = x0 + 0.45
        while xx < x1 - 0.3:
            add("Roof", prism(semi, -0.3, L, lambda u, a, v, xx=xx, P=P: P(a, v, xx + u)))
            xx += 0.9
    add("Roof", cyl("ridge", 0.55, x1 - x0 + 0.3, (0, 0, RB + RISE + 0.15), 10, (0, math.pi / 2, 0)))
    for sx in (-1, 1):   # gable end walls
        add("UpWalls", prism([(-OUT, 0), (OUT, 0), (0, RISE - 0.6)], sx * OUT - 0.6, sx * OUT, lambda u, a, v: (a, u, RB - 0.2 + v)))
        add("UpTrim", cyl("oculus", 1.1, 0.4, (sx * (OUT + 0.05), 0, RB + 2.6), 20, (0, math.pi / 2, 0)))
    # chimney and a glazed skylight lantern
    box("UpStone", (12.0, RB + RISE * 0.55, 8.0), (2.2, 5.5, 2.2))
    box("UpTrim", (12.0, RB + RISE * 0.55 + 2.9, 8.0), (2.7, 0.4, 2.7))
    box("UpTrim", (-6.0, RB + RISE - 0.6, 0), (6.0, 1.2, 4.0))
    add("UpGlass", c.box("sky", (5.4, 3.4, 1.4), B(-6.0, RB + RISE + 0.6, 0)))
    box("UpTrim", (-6.0, RB + RISE + 1.5, 0), (6.4, 0.4, 4.4))

elif STYLE == "B":
    # tall hip roof with a wide overhang (bahay na bato), ridge along x, tiles from the clay texture
    o = 2.4
    RISE = 9.0
    X0, X1, Y0, Y1 = -OUT - o, OUT + o, -OUT - o, OUT + o
    hh = (Y1 - Y0) / 2 - 6.0
    v = [(X0, Y0, RB), (X1, Y0, RB), (X1, Y1, RB), (X0, Y1, RB), (-hh, 0, RB + RISE), (hh, 0, RB + RISE)]
    f = [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)]
    add("Roof", mesh_from("hip", v, f))
    add("UpTrim", c.box("eave", (X1 - X0 + 0.2, Y1 - Y0 + 0.2, 0.5), (0, 0, RB - 0.2)))
    for k in range(9):  # carved eave brackets along the front
        add("UpWood", c.box("bracket", (0.5, 1.8, 0.9), (-OUT + 2.0 + k * (2 * OUT - 4.0) / 8, OUT + 1.0, RB - 0.8)))
    add("Roof", cyl("ridge", 0.55, 2 * hh + 0.4, (0, 0, RB + RISE + 0.1), 10, (0, math.pi / 2, 0)))
    box("UpStone", (12.0, RB + 6.5, 8.0), (2.2, 6.0, 2.2))
else:
    # Art Deco: flat roof behind a parapet, stepped centre tower over the door with a sunburst and the year plaque
    box("UpTrim", (0, H2 + 0.2, 0), (2 * OUT + 0.4, 0.5, 2 * OUT + 0.4))
    for s in (-1, 1):
        box("UpWalls", (0, H2 + 1.6, s * (OUT - 0.4)), (2 * OUT, 2.4, 0.8))
        box("UpWalls", (s * (OUT - 0.4), H2 + 1.6, 0), (0.8, 2.4, 2 * OUT))
    for (w, hgt, dz) in ((16.0, 4.0, 0.0), (10.0, 7.0, 0.3), (5.0, 9.5, 0.6)):
        box("UpWalls", (0, H2 + hgt / 2, -OUT + 0.6 - dz), (w, hgt, 1.2))
        box("UpTrim", (0, H2 + hgt + 0.2, -OUT + 0.6 - dz), (w + 0.6, 0.4, 1.6))
    for k in range(7):   # sunburst rays
        a = math.pi * (k + 0.5) / 7
        r = c.box("ray", (0.3, 0.15, 2.6), B(1.3 * math.cos(a), H2 + 5.0 + 1.3 * math.sin(a), -OUT - 1.35))
        r.rotation_euler = (0, -(a - math.pi / 2), 0)
        add("UpGold", r)
    add("UpGold", cyl("sun", 0.9, 0.2, B(0, H2 + 5.0, -OUT - 1.4), 16, (math.pi / 2, 0, 0)))
    for x in (-OUT + 1.0, -6.5, 6.5, OUT - 1.0):   # vertical fins rising through the parapet
        box("UpTrim", (x, H1 + (H2 + 3.5 - H1) / 2, -OUT - 0.4), (0.9, H2 + 3.5 - H1, 0.9))
    for k in range(3):   # horizontal speed lines
        box("UpAccent", (0, H1 + 0.6 + k * 0.45, -OUT - 0.3), (2 * OUT + 0.2, 0.15, 0.25))
    box("UpIron", (12.0, H2 + 2.6, 10.0), (3.0, 2.8, 3.0))   # rooftop water tank

# ===================== FINISH =====================
SPEC = {"Walls": "sand", "Stone": "stone", "Trim": "white", "Gold": "gold", "Glass": "glass", "Wood": "wood", "Leaves": "leaf", "Flowers": "pink",
        "Accent": "accent", "Stripe": "stripe", "Iron": "black", "Lamp": "warm", "Floor": "wood", "Jars": "jar", "Velvet": "velvet",
        "UpWalls": "sand", "UpTrim": "white", "UpGlass": "glass", "UpAccent": "accent", "UpIron": "black", "UpWood": "wood", "UpLeaves": "leaf",
        "UpFlowers": "pink", "UpGold": "gold", "UpStone": "stone", "Roof": "terracotta",
        "NookWood": "wood", "NookTrim": "white", "NookGold": "gold", "VaultTrim": "white", "VaultLamp": "warm", "VaultGold": "gold"}
TEX = {"Walls": "plaster", "UpWalls": "plaster", "Stone": "stone", "UpStone": "stone", "Trim": "limestone", "UpTrim": "limestone",
       "Wood": "wood", "UpWood": "wood", "Floor": "wood", "Roof": "clay", "NookWood": "wood", "NookTrim": "limestone",
       "VaultTrim": "limestone"}
SMOOTH = {"Leaves", "Flowers", "UpLeaves", "UpFlowers", "Gold", "UpGold", "Lamp", "Velvet", "Jars", "NookGold", "VaultLamp", "VaultGold"}
if STYLE == "B":
    SPEC.update({"Walls": "stone", "UpWalls": "wood"})
    TEX.update({"Walls": "stone", "UpWalls": "wood"})
elif STYLE == "C":
    SPEC.update({"Walls": "white", "UpWalls": "white"})
final = []
for name, objs in G.items():
    obj = join(objs, "Shop_" + name)
    c.finish(obj, "Shop_" + name, SPEC[name], smooth=name in SMOOTH)
    if name in TEX:
        uv_box(obj, 8.0 if name != "Floor" else 4.0)
        tint = {"A": (0.97, 0.9, 0.78), "B": None, "C": (0.98, 0.95, 0.88)}[STYLE] if name in ("Walls", "UpWalls") else None
        tx.apply(obj, TEX[name], "Shop_" + name + "_mat", tint)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
print("SHOP triangles", c.triangle_count(final), [(o.name, c.triangle_count([o])) for o in final])
c.export_glb(os.path.join(c.OUT_MODELS, "Shop" + SUFFIX + ".glb"), final)
if os.environ.get("DF_SKIP_RENDER"):  # export only (no Cycles previews): DF_SKIP_RENDER=1
    print("done (no renders)")
    raise SystemExit


def render(path, cam_loc, target, lens=35, samples=40, hide_upper=False, res=(1200, 860)):
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.view_settings.view_transform = "AgX"
    if not bpy.data.objects.get("Sun"):
        world = bpy.data.worlds.new("Sky")
        world.use_nodes = True
        sky = world.node_tree.nodes.new("ShaderNodeTexSky")
        world.node_tree.links.new(sky.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
        scene.world = world
        sd = bpy.data.lights.new("Sun", "SUN")
        sd.energy = 4.2
        sd.color = (1.0, 0.86, 0.7)
        sd.angle = math.radians(3)
        so = bpy.data.objects.new("Sun", sd)
        bpy.context.collection.objects.link(so)
        so.rotation_euler = (math.radians(55), 0, math.radians(200))
        gd = bpy.data.meshes.new("ground")
        go = bpy.data.objects.new("ground", gd)
        bpy.context.collection.objects.link(go)
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=90)
        bm.to_mesh(gd)
        bm.free()
        gm = bpy.data.materials.new("gm")
        gm.use_nodes = True
        gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.47, 0.36, 1)
        gd.materials.append(gm)
        # stand-ins for the gameplay parts so the interior preview reads (not exported)
        for (cx, cz, sx, sy, sz) in ((-17.5, -12, 3, 3, 8), (-17.5, -3, 3, 3, 8), (-17.5, 6, 3, 3, 8), (-17.5, 15, 3, 3, 8), (10, -6, 8, 4, 3), (12, 14, 6, 3.5, 3)):
            o = c.box("standin", (sx, sz, sy), B(cx, F0 + sy / 2, cz))
            m = bpy.data.materials.new("si")
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.45, 0.3, 0.18, 1)
            o.data.materials.append(m)
        for x in (-10, -5, 0, 5):
            o = c.box("standin", (2, 2, 3), B(x, F0 + 1.5, 16))
        bw = c.box("standin_backwall", (40, 1, 12), B(0, F0 + 6, 19.5))
    for o in final:
        if o.name.startswith("Shop_Up") or o.name == "Shop_Roof":
            o.hide_render = hide_upper
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


render(os.path.join(c.OUT_PREVIEWS, "Shop" + SUFFIX + "_front.png"), (34, 70, 20), (0, 0, 11))
if STYLE != "A":
    print("done")
    raise SystemExit
render(os.path.join(c.OUT_PREVIEWS, "Shop_inside.png"), (0, 34, 46), (0, -2, 0), 28, 40, hide_upper=True)
render(os.path.join(c.OUT_PREVIEWS, "Shop_door.png"), (-9, 40, 7), (0, 20, 6), 32, 32, res=(1000, 760))
print("done")
