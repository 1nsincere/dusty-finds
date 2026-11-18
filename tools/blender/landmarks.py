"""Dusty Finds landmarks: Domed Hall (walk-in), Clock Tower (walk-through base), Town Gate (Blender 5.x, headless).
Scenery only: no gameplay parts.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/landmarks.py
Writes assets/models/Landmarks.glb and assets/previews/Landmarks_*.png (git-ignored).

Real studs. Each piece faces -Y, stands on z = 0, centred on x = 0 (DomedHall), 90 (ClockTower), 170 (Gate); Studio splits
them by prefix DomedHall_<Group> / ClockTower_<Group> / Gate_<Group>.
  DomedHall   46 x 46 hall (walls 15) on a 1.2 podium, columned portico with pediment, drum + ribbed dome (top ~44),
              corner towers with small domes; inside: arcade of columns and a fountain. Door 8 x 11 walk-through.
  ClockTower  14 x 14, 40 to the roof, 4 clock faces, open belfry, tiled pyramid roof; arched passages through the base.
  Gate        62 wide: 18-wide main arch (16 tall) over the street, two 6-wide side arches, attic with "DUSTY FINDS",
              piers with lanterns and urns.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"cream": "F6EEDC", "ochre": "E8B85C", "stone": "CFC5B0", "glass": "3E6A8A", "iron": "2E3236",
                  "teal": "2F8F86", "gold": "E3B23C", "floor": "E8D9BC", "water": "4FB3C8", "leaf": "3F7F3A",
                  "pink": "E0458C", "brick": "B8573C", "warm": "FFD9A0", "plaster": "F3EEE4", "white": "FBF7EC"})
c.reset_scene()
G = {}
CUR = ["DomedHall"]
OX = [0.0]


def add(g, o):
    o.location.x += OX[0]
    G.setdefault((CUR[0], g), []).append(o)
    return o


def keep(o):
    """Object built directly in world coords (already offset): register without moving."""
    G.setdefault((CUR[0], o["g"]), []).append(o)
    return o


def box(g, size, loc, rot=None):
    o = c.box("b", size, loc)
    if rot:
        o.rotation_euler = rot
    return add(g, o)


def cyl(g, r, h, loc, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    return add(g, bpy.context.active_object)


def lathe(g, profile, loc, steps=24):
    o = c.lathe("l", profile, steps=steps)
    o.location = loc
    return add(g, o)


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


def prism(pts, a0, a1, place):
    n = len(pts)
    verts = [place(u, a, v) for a in (a0, a1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return mesh_from("p", verts, faces)


def fy(x, zb, pts, y0, y1):
    return prism(pts, y0, y1, lambda u, a, v: (x + u, a, zb + v))


def fx(y, zb, pts, x0, x1):
    return prism(pts, min(x0, x1), max(x0, x1), lambda u, a, v: (a, y + u, zb + v))


def boolean(t, o, op="DIFFERENCE"):
    m = t.modifiers.new("b", "BOOLEAN")
    m.object = o
    m.operation = op
    m.solver = "EXACT"
    bpy.context.view_layer.objects.active = t
    bpy.ops.object.modifier_apply(modifier="b")
    bpy.data.objects.remove(o, do_unlink=True)


def join(objs, name):
    return c.join(objs, name) if len(objs) > 1 else objs[0]


def blob(r, loc, s=0.25):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    o = bpy.context.active_object
    for v in o.data.vertices:
        n = v.co.normalized()
        v.co = n * r * (1 + s * math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]))
    return o


def text(g, body, loc, size, spacing=1.15):
    bpy.ops.object.text_add(location=loc, rotation=(math.pi / 2, 0, 0))
    t = bpy.context.active_object
    t.data.body = body
    t.data.size = size
    t.data.extrude = 0.08
    t.data.align_x = "CENTER"
    t.data.space_character = spacing
    bpy.ops.object.convert(target="MESH")
    return add(g, bpy.context.active_object)


def column(g, x, y, z, h, r=0.7):
    lathe(g, [(0.01, 0), (r * 1.3, 0), (r * 1.3, 0.5), (r, 0.8), (r * 0.9, h - 0.9), (r * 1.25, h - 0.4), (r * 1.35, h), (0.01, h)], (x, y, z), 12)


def pyramid(g, cx, cy, z, half, rise, over=0.8):
    h = half + over
    v = [(cx - h, cy - h, z), (cx + h, cy - h, z), (cx + h, cy + h, z), (cx - h, cy + h, z), (cx, cy, z + rise)]
    f = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)]
    return add(g, mesh_from("pyr", v, f))


def dome(g, cx, cy, z, r, steps=24, lift=0.0):
    prof = [(0.01, 0)] + [(r * math.cos(math.pi / 2 * k / 8), lift + r * math.sin(math.pi / 2 * k / 8)) for k in range(9)]
    return lathe(g, prof, (cx, cy, z), steps)


def hollow(W, D, H, z0, T, g):
    o = c.box("o", (W, D, H), (OX[0], 0, z0 + H / 2))
    i = c.box("i", (W - 2 * T, D - 2 * T, H + 1), (OX[0], 0, z0 + H / 2 + 0.3))
    boolean(o, i)
    return o


# ===================== DOMED HALL =====================
CUR[0], OX[0] = "DomedHall", 0.0
W = 46.0
H = 15.0
Z0 = 1.2
FY = -W / 2
box("Stone", (W + 4, W + 4, Z0), (0, 0, Z0 / 2))
for i in range(4):
    box("Stone", (22 - i * 0.8, 1.2, Z0 * (4 - i) / 4), (0, FY - 8.6 - i * 1.2 - 0.6, Z0 * (4 - i) / 8))
hall = hollow(W, W, H, Z0, 1.2, "Walls")
cuts = [fy(OX[0], Z0 - 0.1, arch(8.0, 11.0), FY - 0.6, FY + 1.8)]
for x in (-15.0, 15.0):
    cuts.append(fy(OX[0] + x, Z0 + 3.0, arch(4.0, 8.0), FY - 0.6, FY + 1.8))
for s in (-1, 1):
    for y in (-12.0, 0.0, 12.0):
        cuts.append(fx(y, Z0 + 3.0, [(u + 0, v) for (u, v) in arch(4.0, 8.0)], OX[0] + s * (W / 2 + 0.6), OX[0] + s * (W / 2 - 1.8)))
    cuts.append(fy(OX[0] + s * 10.0, Z0 + 3.0, arch(4.0, 8.0), W / 2 - 1.8, W / 2 + 0.6))
boolean(hall, join(cuts, "c"))
G.setdefault(("DomedHall", "Walls"), []).append(hall)
for x in (-15.0, 15.0):
    add("Glass", fy(x, Z0 + 3.05, arch(3.9, 7.9), FY + 0.55, FY + 0.65))
for s in (-1, 1):
    for y in (-12.0, 0.0, 12.0):
        add("Glass", fx(y, Z0 + 3.05, arch(3.9, 7.9), s * (W / 2 - 0.55), s * (W / 2 - 0.65)))
    add("Glass", fy(s * 10.0, Z0 + 3.05, arch(3.9, 7.9), W / 2 - 0.65, W / 2 - 0.55))
box("Walls", (W - 2.4, W - 2.4, 0.8), (0, 0, Z0 + H - 0.4))                     # ceiling slab
box("Trim", (W + 1.6, W + 1.6, 0.9), (0, 0, Z0 + H + 0.2))                      # cornice
box("Trim", (W + 0.6, W + 0.6, 0.5), (0, 0, Z0 + 11.8))
for s in (-1, 1):                                                                # balustrade on the roof edge
    for k in range(23):
        box("Trim", (0.4, 0.4, 1.6), (-21.0 + k * 1.9, s * (W / 2 - 0.3), Z0 + H + 1.4))
        box("Trim", (0.4, 0.4, 1.6), (s * (W / 2 - 0.3), -21.0 + k * 1.9, Z0 + H + 1.4))
    box("Trim", (W, 0.7, 0.4), (0, s * (W / 2 - 0.3), Z0 + H + 2.4))
    box("Trim", (0.7, W, 0.4), (s * (W / 2 - 0.3), 0, Z0 + H + 2.4))
# portico: 6 columns, entablature, pediment
for x in (-10.5, -7.0, -3.6, 3.6, 7.0, 10.5):  # 5.8-stud walk-through gap in the middle
    column("Trim", x, FY - 6.0, Z0, 12.0)
box("Trim", (23.0, 8.0, 1.6), (0, FY - 3.8, Z0 + 12.8))
box("Walls", (22.0, 7.4, 0.3), (0, FY - 3.8, Z0 + 11.9))
add("Trim", fy(0, Z0 + 13.6, [(-11.8, 0), (11.8, 0), (0, 4.6)], FY - 8.0, FY + 0.2))
add("Walls", fy(0, Z0 + 13.9, [(-10.2, 0), (10.2, 0), (0, 3.6)], FY - 8.1, FY - 7.9))
box("Gold", (14.0, 0.4, 1.2), (0, FY - 8.0, Z0 + 12.8))
text("Letters", "BULWAGAN", (0, FY - 8.25, Z0 + 12.35), 0.95)
box("Stone", (24.0, 8.4, 0.3), (0, FY - 4.0, Z0 + 0.15))
# drum + ribbed dome + lantern
cyl("Walls", 11.5, 6.5, (0, 0, Z0 + H + 3.25), 32)
for k in range(16):
    a = 2 * math.pi * k / 16
    box("Trim", (0.9, 0.9, 6.5), (11.6 * math.cos(a), 11.6 * math.sin(a), Z0 + H + 3.25))
    if k % 2 == 0:
        box("Glass", (0.3, 2.0, 3.6), (11.55 * math.cos(a + 0.2), 11.55 * math.sin(a + 0.2), Z0 + H + 3.4),
            rot=(0, 0, a + 0.2))
cyl("Trim", 12.4, 0.8, (0, 0, Z0 + H + 6.8), 32)
dome("Dome", 0, 0, Z0 + H + 7.2, 11.6, 32)
for k in range(12):
    a = 2 * math.pi * k / 12
    pts = []
    rib = []
    for j in range(9):
        t = math.pi / 2 * j / 8
        rib.append((11.75 * math.cos(t) * math.cos(a), 11.75 * math.cos(t) * math.sin(a), Z0 + H + 7.2 + 11.75 * math.sin(t)))
    for j in range(8):
        p0, p1 = rib[j], rib[j + 1]
        mid = [(p0[i] + p1[i]) / 2 for i in range(3)]
        L = math.dist(p0, p1)
        b = c.box("rib", (0.35, 0.35, L), mid)
        d = [p1[i] - p0[i] for i in range(3)]
        import mathutils
        b.rotation_euler = mathutils.Vector(d).to_track_quat("Z", "Y").to_euler()
        add("Gold", b)
cyl("Trim", 2.2, 3.4, (0, 0, Z0 + H + 7.2 + 11.6 + 1.5), 12)
for k in range(6):
    a = 2 * math.pi * k / 6
    box("Glass", (0.2, 1.4, 2.2), (2.25 * math.cos(a), 2.25 * math.sin(a), Z0 + H + 20.3), rot=(0, 0, a))
dome("Gold", 0, 0, Z0 + H + 22.1, 2.5, 16)
cyl("Gold", 0.18, 3.0, (0, 0, Z0 + H + 26.0), 8)
add("Gold", c.sphere("ball", 0.5, (0, 0, Z0 + H + 27.6), segments=10, rings=6))
# corner towers with small domes
for sx in (-1, 1):
    for sy in (-1, 1):
        cx, cy = sx * (W / 2 - 1.5), sy * (W / 2 - 1.5)
        box("Walls", (5.0, 5.0, 6.0), (cx, cy, Z0 + H + 3.0))
        box("Trim", (5.8, 5.8, 0.6), (cx, cy, Z0 + H + 6.2))
        for (dx, dy) in ((0, -2.55), (0, 2.55), (-2.55, 0), (2.55, 0)):
            box("Glass", (1.4 if dx == 0 else 0.15, 0.15 if dx == 0 else 1.4, 2.6), (cx + dx, cy + dy, Z0 + H + 3.4))
        dome("Dome", cx, cy, Z0 + H + 6.5, 2.8, 16)
        cyl("Gold", 0.12, 1.8, (cx, cy, Z0 + H + 10.0), 6)
# interior: ring of columns under the dome, fountain, benches, lamps
box("Floor", (W - 2.6, W - 2.6, 0.1), (0, 0, Z0 + 0.05))
for k in range(8):
    a = 2 * math.pi * k / 8 + math.pi / 8
    column("Trim", 10.0 * math.cos(a), 10.0 * math.sin(a), Z0, H - 0.8, 0.6)
lathe("Stone", [(0.01, 0), (5.0, 0), (5.0, 1.2), (4.5, 1.2), (4.5, 0.4), (0.01, 0.4)], (0, 0, Z0), 24)
cyl("Water", 4.5, 0.2, (0, 0, Z0 + 0.9), 24)
lathe("Stone", [(0.01, 0), (0.7, 0), (0.5, 2.6), (1.8, 2.8), (1.8, 3.1), (0.01, 3.1)], (0, 0, Z0 + 0.4), 16)
for s in (-1, 1):
    for y in (-12.0, 12.0):
        box("Wood", (6.0, 1.4, 0.35), (s * 17.0, y, Z0 + 1.5))
        box("Iron", (0.3, 1.2, 1.3), (s * 17.0 - 2.6, y, Z0 + 0.65))
        box("Iron", (0.3, 1.2, 1.3), (s * 17.0 + 2.6, y, Z0 + 0.65))
for (x, y) in ((-14, -14), (14, -14), (-14, 14), (14, 14)):
    cyl("Iron", 0.05, 3.0, (x, y, Z0 + H - 2.3), 6)
    add("Lamp", c.sphere("pend", 0.6, (x + OX[0] * 0, y, Z0 + H - 4.2), segments=12, rings=8))
for s in (-1, 1):  # planters by the portico
    box("Stone", (2.8, 2.8, 1.2), (s * 13.5, FY - 7.0, Z0 + 0.6))
    add("Leaves", blob(1.2, (s * 13.5, FY - 7.0, Z0 + 2.1)))

# ===================== CLOCK TOWER =====================
CUR[0], OX[0] = "ClockTower", 90.0
S, TH = 14.0, 32.0
base = hollow(S, S, 9.0, 0.0, 1.5, "Stone")
pc = []
for d in (-1, 1):
    pc.append(fy(OX[0], -0.1, arch(5.0, 7.5), d * (S / 2 + 0.6) - (0.0 if d < 0 else 0), d * (S / 2 - 2.2)))
    pc.append(fx(0, -0.1, arch(5.0, 7.5), OX[0] + d * (S / 2 + 0.6), OX[0] + d * (S / 2 - 2.2)))
boolean(base, join(pc, "pc"))
G.setdefault(("ClockTower", "Stone"), []).append(base)
box("Stone", (S, S, 0.6), (0, 0, 9.3))
box("Walls", (S - 1.0, S - 1.0, TH - 9.6), (0, 0, 9.6 + (TH - 9.6) / 2))
for z in (9.6, 18.0, 25.0):
    box("Trim", (S + 0.6, S + 0.6, 0.6), (0, 0, z))
for sx in (-1, 1):  # corner quoins
    for sy in (-1, 1):
        for k in range(10):
            box("Stone", (1.3 if k % 2 else 0.9, 1.3 if k % 2 else 0.9, 1.4), (sx * (S / 2 - 0.5), sy * (S / 2 - 0.5), 10.6 + k * 2.1))
for (dx, dy, rz) in ((0, -1, 0), (0, 1, math.pi), (-1, 0, -math.pi / 2), (1, 0, math.pi / 2)):
    px, py = dx * (S / 2 - 0.3), dy * (S / 2 - 0.3)
    # tall slit windows
    box("Glass", (1.2 if dy else 0.15, 0.15 if dy else 1.2, 4.0), (px + dx * 0.25, py + dy * 0.25, 13.0))
    # clock: gold ring, white face, ticks, hands
    cyl("Gold", 3.6, 0.4, (px + dx * 0.4, py + dy * 0.4, 21.5), 32, (math.pi / 2 if dy else 0, 0 if dy else math.pi / 2, 0))
    cyl("White", 3.1, 0.45, (px + dx * 0.5, py + dy * 0.5, 21.5), 32, (math.pi / 2 if dy else 0, 0 if dy else math.pi / 2, 0))
    for k in range(12):
        a = k / 12 * 2 * math.pi
        o = 2.6 * math.sin(a)
        box("Iron", (0.15 if dy else 0.1, 0.1 if dy else 0.15, 0.5), (px + dx * 0.75 + (o if dy else 0), py + dy * 0.75 + (0 if dy else o), 21.5 + 2.6 * math.cos(a)))
    box("Iron", (0.25 if dy else 0.1, 0.1 if dy else 0.25, 1.7), (px + dx * 0.8, py + dy * 0.8, 22.3), rot=(0, 0.6 if dy else 0, 0 if dy else 0) if dy else (0.6, 0, 0))
    box("Iron", (0.18 if dy else 0.1, 0.1 if dy else 0.18, 2.4), (px + dx * 0.82, py + dy * 0.82, 22.6), rot=(0, -0.4, 0) if dy else (-0.4, 0, 0))
# open belfry: 4 corner piers + bell
for sx in (-1, 1):
    for sy in (-1, 1):
        box("Walls", (2.6, 2.6, 6.0), (sx * (S / 2 - 1.3), sy * (S / 2 - 1.3), TH + 3.0))
box("Walls", (S, S, 0.6), (0, 0, TH + 0.3))
box("Trim", (S + 1.0, S + 1.0, 0.8), (0, 0, TH + 6.4))
for d in range(4):
    for (dx, dy) in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        pass
for (dx, dy) in ((0, -1), (0, 1), (-1, 0), (1, 0)):
    for k in range(5):
        o = -3.6 + k * 1.8
        box("Trim", (0.35, 0.35, 1.4), (dx * (S / 2 - 0.4) + (o if dy else 0), dy * (S / 2 - 0.4) + (0 if dy else o), TH + 1.3))
    box("Trim", (S - 5.2 if dy else 0.5, 0.5 if dy else S - 5.2, 0.35), (dx * (S / 2 - 0.4), dy * (S / 2 - 0.4), TH + 2.1))
lathe("Gold", [(0.01, 0), (1.8, 0), (1.5, 0.6), (1.1, 2.4), (0.4, 2.8), (0.01, 2.9)], (0, 0, TH + 2.4), 16)
cyl("Iron", 0.15, 2.0, (0, 0, TH + 5.4), 6)
pyramid("Roof", 0, 0, TH + 6.8, S / 2 + 0.5, 9.0)
cyl("Gold", 0.15, 4.0, (0, 0, TH + 17.5), 6)
add("Gold", c.sphere("ball", 0.55, (0, 0, TH + 16.2), segments=10, rings=6))

# ===================== TOWN GATE =====================
CUR[0], OX[0] = "Gate", 170.0
GW, GD, GH = 62.0, 6.0, 22.0
gate = c.box("gate", (GW, GD, GH), (OX[0], 0, GH / 2))
gc = [fy(OX[0], -0.1, arch(18.0, 16.0), -GD / 2 - 0.6, GD / 2 + 0.6)]
for s in (-1, 1):
    gc.append(fy(OX[0] + s * 19.0, -0.1, arch(6.0, 9.0), -GD / 2 - 0.6, GD / 2 + 0.6))
boolean(gate, join(gc, "gc"))
G.setdefault(("Gate", "Walls"), []).append(gate)
for yy in (-GD / 2, GD / 2):
    d = -1 if yy < 0 else 1
    ring = fy(0, -0.1, arch(20.4, 17.2), yy + d * 0.0 - 0.3, yy + 0.3)
    boolean(ring, fy(0, -0.5, arch(18.0, 16.0), yy - 1.0, yy + 1.0))
    add("Trim", ring)
    box("Trim", (1.6, 0.9, 2.0), (0, yy + d * 0.3, 16.6))                                # keystone
    for s in (-1, 1):
        for x in (s * 11.5, s * 26.5):
            box("Trim", (2.0, 0.8, 16.0), (x, yy + d * 0.25, 8.0))                       # pilasters
            box("Trim", (2.6, 1.0, 0.8), (x, yy + d * 0.3, 16.3))
    box("Trim", (GW + 1.4, 1.2, 1.0), (0, yy + d * 0.3, 16.9))                          # entablature
    box("Gold", (26.0, 0.4, 2.4), (0, yy + d * 0.45, 19.4))                              # name plaque
    tl = text("Letters", "DUSTY FINDS", (0, yy + d * 0.7, 18.55), 1.8)
    if d > 0:
        tl.rotation_euler = (math.pi / 2, 0, math.pi)
box("Trim", (GW + 1.6, GD + 1.6, 1.0), (0, 0, GH + 0.5))
for s in (-1, 1):  # attic urns and end piers with lanterns
    lathe("Trim", [(0.01, 0), (1.0, 0), (1.4, 1.2), (0.8, 2.2), (1.0, 2.6), (0.01, 2.6)], (s * 26.5, 0, GH + 1.0), 12)
    box("Stone", (4.0, GD + 2.0, 1.2), (s * (GW / 2 + 2.5), 0, 0.6))
    box("Walls", (3.2, GD + 1.0, 14.0), (s * (GW / 2 + 2.5), 0, 7.0))
    box("Trim", (3.8, GD + 1.6, 0.8), (s * (GW / 2 + 2.5), 0, 14.4))
    cyl("Iron", 0.2, 2.0, (s * (GW / 2 + 2.5), 0, 15.8), 8)
    box("Lamp", (1.4, 1.4, 1.8), (s * (GW / 2 + 2.5), 0, 17.6))
    pyramid("Iron", s * (GW / 2 + 2.5), 0, 18.5, 0.7, 1.0, over=0.2)
    for yy in (-GD / 2 - 2.0, GD / 2 + 2.0):                                          # planters
        box("Stone", (3.0, 3.0, 1.2), (s * 13.0, yy, 0.6))
        add("Leaves", blob(1.2, (s * 13.0, yy, 2.1)))
        for j in range(4):
            add("Flowers", blob(0.3, (s * 13.0 + 0.8 * math.cos(j * 1.6), yy + 0.6 * math.sin(j * 1.6), 2.6 + 0.2 * j)))

# ===================== finish =====================
SPEC = {"Walls": ("ochre", "plaster"), "Trim": ("cream", "limestone"), "Stone": ("stone", "stone"), "Glass": ("glass", None),
        "Gold": ("gold", None), "Dome": ("teal", None), "Roof": ("terracotta", "clay"), "Iron": ("iron", None),
        "Letters": ("iron", None), "Floor": ("floor", "marble"), "Water": ("water", None), "Wood": ("wood", "wood"),
        "Lamp": ("warm", None), "Leaves": ("leaf", None), "Flowers": ("pink", None), "White": ("white", None)}
TINT = {("DomedHall", "Walls"): (0.98, 0.9, 0.72), ("ClockTower", "Walls"): (0.78, 0.4, 0.28), ("Gate", "Walls"): (0.98, 0.86, 0.6)}
c.PALETTE.setdefault("wood", "6B4A2E")
final = []
for (piece, name), objs in G.items():
    obj = join(objs, f"{piece}_{name}")
    obj.name = f"{piece}_{name}"
    col, texk = SPEC[name]
    c.finish(obj, obj.name, col, smooth=name in ("Gold", "Lamp", "Leaves", "Flowers", "Dome", "Water"))
    if texk:
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
        tx.apply(obj, texk, f"{piece}_{name}_mat", TINT.get((piece, name)))
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
per = {}
for o in final:
    k = o.name.split("_")[0]
    per[k] = per.get(k, 0) + c.triangle_count([o])
print("LANDMARKS triangles", c.triangle_count(final), per)
c.export_glb(os.path.join(c.OUT_MODELS, "Landmarks.glb"), final)

import mathutils  # noqa: E402

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 40
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = 1400, 700
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
bmesh.ops.create_grid(b2, x_segments=1, y_segments=1, size=400)
b2.to_mesh(gd)
b2.free()
cm = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
bpy.context.collection.objects.link(cm)
sc.camera = cm


def shot(path, loc, target, lens):
    cm.data.lens = lens
    cm.location = loc
    cm.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


shot(os.path.join(c.OUT_PREVIEWS, "Landmarks_all.png"), (90, -190, 60), (90, 0, 15), 24)
shot(os.path.join(c.OUT_PREVIEWS, "Landmarks_hall.png"), (40, -75, 22), (0, 0, 16), 30)
print("done")
