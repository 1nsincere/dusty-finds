"""Dusty Finds Depot: the town's jeepney/delivery station, walk-in (Blender 5.x, headless). Visual landmark (no gameplay parts).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/depot.py
Writes assets/models/Depot.glb and assets/previews/Depot_*.png (git-ignored).

Real studs. Front faces -Y, stands on z = 0, centred on the origin. About 66 x 46 (with the back platform canopy), clock top ~27.
Yellow arcaded station (reference image), central clock pavilion with a "DEPOT" sign, tiled roofs, an open arcade loggia,
and a walk-in waiting hall: tiled floor, ticket booth, benches, departures board, pendant lamps, potted palms.
Groups Depot_<Group>; Studio colours/tints by name. Walls are hollow; the hall door is a 6 x 9 walk-through arch.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"yellow": "F2C75C", "white": "FBF7EC", "glass": "3E6A8A", "stone": "CFC5B0", "wood": "6B4A2E",
                  "leaf": "3F7F3A", "pink": "E0458C", "teal": "1F7A7A", "floor": "E8D9BC", "gold": "E3B23C"})
c.reset_scene()
G = {}
T = 1.0
Z0 = 1.0          # podium top = floor level


def add(g, o):
    G.setdefault(g, []).append(o)
    return o


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


def blob(r, loc, s=0.28):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        n = v.co.normalized()
        k = 1 + s * (math.sin(v.co.x * 3.1 + loc[0]) * math.cos(v.co.y * 2.7 + loc[1]) + 0.5 * math.sin(v.co.z * 4.3))
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
        for lp in f.loops:
            co = lp.vert.co
            uv = (co.y, co.z) if ax == 0 else ((co.x, co.z) if ax == 1 else (co.x, co.y))
            lp[layer].uv = (uv[0] / size, uv[1] / size)
    bm.to_mesh(obj.data)
    bm.free()


def tile_roof_x(x0, x1, y0, y1, zb, rise, group="Roof"):
    """Gable roof with ridge along X; slopes face -Y / +Y; barrel tiles running down-slope."""
    ym = (y0 + y1) / 2
    run = (y1 - y0) / 2
    L = math.hypot(run, rise)
    for s in (-1, 1):
        ey, dz = ym + s * run, rise / L
        dy = -s * run / L
        ny, nz = s * rise / L, run / L

        def P(a, v, xx, ey=ey, dy=dy, dz=dz, ny=ny, nz=nz):
            return (xx, ey + dy * a + ny * v, zb + dz * a + nz * v)
        add(group, mesh_from("slab", [P(0, -0.3, x0), P(L, -0.3, x0), P(L, -0.3, x1), P(0, -0.3, x1), P(0, 0, x0), P(L, 0, x0), P(L, 0, x1), P(0, 0, x1)],
                             [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]))
        semi = [(0.4 * math.cos(math.pi * k / 6), 0.4 * math.sin(math.pi * k / 6)) for k in range(7)]
        xx = x0 + 0.45
        while xx < x1 - 0.3:
            add(group, prism(semi, -0.3, L, lambda u, a, v, xx=xx, P=P: P(a, v, xx + u)))
            xx += 0.85
    add(group, cyl("ridge", 0.5, x1 - x0 + 0.3, ((x0 + x1) / 2, ym, zb + rise + 0.12), 10, (0, math.pi / 2, 0)))
    for xs in (x0 + 0.6, x1 - 0.6):
        add("Walls", prism([(y0 + 0.9, 0), (y1 - 0.9, 0), (ym, rise - 0.5)], xs - 0.3, xs + 0.3, lambda u, a, v: (a, u, zb + v)))


# ---------------- podium ----------------
add("Stone", c.box("podium", (68, 48, Z0), (0, 2, Z0 / 2)))
for i in range(3):
    add("Stone", c.box("step", (22 - i * 1.2, 1.4, Z0 - i * 0.33), (0, -22.7 - (2 - i) * 1.4, (Z0 - i * 0.33) / 2)))

# ---------------- main hall (hollow) + wings ----------------
HW, HD, HH = 40.0, 24.0, 14.0     # hall: x +-20, y -12..12
WX0, WX1, WH = 20.0, 31.0, 10.0   # wings
outer = join([c.box("o", (HW, HD, HH), (0, 0, Z0 + HH / 2)),
              c.box("o", (WX1 - WX0 + 0.01, HD - 4, WH), (-(WX0 + WX1) / 2, 0, Z0 + WH / 2)),
              c.box("o", (WX1 - WX0 + 0.01, HD - 4, WH), ((WX0 + WX1) / 2, 0, Z0 + WH / 2))], "outer")
mod = outer.modifiers.new("u", "BOOLEAN")
mod.operation = "UNION"
mod.solver = "EXACT"
mod.use_self = True
dummy = c.box("d", (0.01, 0.01, 0.01), (0, 0, -50))
mod.object = dummy
bpy.context.view_layer.objects.active = outer
bpy.ops.object.modifier_apply(modifier="u")
bpy.data.objects.remove(dummy, do_unlink=True)
bm = bmesh.new()
bm.from_mesh(outer.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -40], context="VERTS")
bm.to_mesh(outer.data)
bm.free()
inner = c.box("i", (HW - 2 * T, HD - 2 * T, HH - T + 0.5), (0, 0, Z0 - 0.5 + (HH - T + 0.5) / 2))
boolean(outer, inner)
cuts = [fy(0, Z0, arch(6.0, 9.0), -12.6, -12 + T + 0.6)]                       # main door
for x in (-14.0, -9.0, 9.0, 14.0):
    cuts.append(fy(x, Z0 + 2.0, arch(3.2, 7.0), -12.6, -12 + T + 0.6))
for x in (-12.0, -4.0, 4.0, 12.0):
    cuts.append(fy(x, Z0 + 2.0, arch(3.2, 7.0), 12 - T - 0.6, 12.6))               # back windows
for s in (-1, 1):
    for x in (WX0 + 3.0, WX1 - 3.0):
        cuts.append(fy(s * x, Z0 + 1.8, arch(2.8, 5.6), -10.6, -10 + T + 0.6))
    cuts.append(fx(0, Z0 + 1.8, arch(3.0, 5.8), s * (WX1 + 0.6), s * (WX1 - T - 0.6)))
    for y in (-6.0, 6.0):
        cuts.append(fx(y, Z0 + 9.0, arch(2.4, 3.6), s * (HW / 2 + 0.6), s * (HW / 2 - T - 0.6)))  # clerestory above the wings
boolean(outer, join(cuts, "c"))
add("Walls", outer)
# glass in the window openings (set in the wall middle)
for x in (-14.0, -9.0, 9.0, 14.0):
    add("Glass", fy(x, Z0 + 2.05, arch(3.1, 6.9), -12 + T / 2 - 0.04, -12 + T / 2 + 0.04))
for x in (-12.0, -4.0, 4.0, 12.0):
    add("Glass", fy(x, Z0 + 2.05, arch(3.1, 6.9), 12 - T / 2 - 0.04, 12 - T / 2 + 0.04))
for s in (-1, 1):
    for x in (WX0 + 3.0, WX1 - 3.0):
        add("Glass", fy(s * x, Z0 + 1.85, arch(2.7, 5.5), -10 + T / 2 - 0.04, -10 + T / 2 + 0.04))
        add("Shutters", c.box("sh", (1.4, 0.15, 5.2), (s * x - 2.1, -10.2, Z0 + 4.4)))
        add("Shutters", c.box("sh", (1.4, 0.15, 5.2), (s * x + 2.1, -10.2, Z0 + 4.4)))
# bands, cornices, quoins
for (w, d, h, y) in ((HW, HD, HH, 0), (WX1 - WX0, HD - 4, WH, 0)):
    pass
add("Trim", c.box("corn_h", (HW + 1.6, HD + 1.6, 0.8), (0, 0, Z0 + HH + 0.4)))
add("Trim", c.box("band_h", (HW + 0.6, HD + 0.6, 0.5), (0, 0, Z0 + 10.2)))
for s in (-1, 1):
    add("Trim", c.box("corn_w", (WX1 - WX0 + 1.2, HD - 2.8, 0.7), (s * (WX0 + WX1) / 2, 0, Z0 + WH + 0.35)))
    for xq in (s * HW / 2, s * WX1):
        for k in range(5):
            add("Stone", c.box("quoin", (1.6 if k % 2 else 1.1, 1.0, 1.3), (xq, -12.1 if abs(xq) < 21 else -10.1, Z0 + 1.0 + k * 2.6)))
# ---------------- front arcade loggia (7 arches) ----------------
AY0, AY1 = -18.0, -12.0
arc_wall = c.box("arcade", (34, 1.2, 9.5), (0, AY0 + 0.6, Z0 + 4.75))
acuts = [fy(x, Z0 - 0.1, arch(3.6, 7.2), AY0 - 0.6, AY0 + 1.8) for x in (-14.4, -9.6, -4.8, 0.0, 4.8, 9.6, 14.4)]
boolean(arc_wall, join(acuts, "c"))
add("Walls", arc_wall)
for x in (-16.8, -12.0, -7.2, -2.4, 2.4, 7.2, 12.0, 16.8):
    add("Trim", c.box("pier_base", (1.4, 1.5, 0.8), (x, AY0 + 0.6, Z0 + 0.4)))
    add("Trim", c.box("pier_cap", (1.5, 1.6, 0.4), (x, AY0 + 0.6, Z0 + 5.6)))
for x in (-14.4, -9.6, -4.8, 0.0, 4.8, 9.6, 14.4):
    add("Trim", c.box("key", (0.6, 1.4, 0.9), (x, AY0 + 0.6, Z0 + 7.6)))
add("Trim", c.box("arcade_corn", (35, 2.0, 0.6), (0, AY0 + 0.6, Z0 + 9.8)))
add("Floor", c.box("loggia_floor", (34, 6, 0.1), (0, (AY0 + AY1) / 2, Z0 + 0.05)))
# shed roof over the loggia
L = math.hypot(6.6, 2.4)
sr = c.box("shed", (35.6, L, 0.35), (0, (AY0 + AY1) / 2 - 0.3, Z0 + 11.2))
sr.rotation_euler = (math.atan2(2.4, 6.6), 0, 0)
add("Roof", sr)
semi = [(0.38 * math.cos(math.pi * k / 6), 0.38 * math.sin(math.pi * k / 6)) for k in range(7)]
for i in range(41):
    xx = -17.4 + i * 0.85
    ys, zs = AY0 - 0.6, Z0 + 10.0
    ye, ze = AY1 + 0.2, Z0 + 12.4
    add("Roof", prism(semi, 0, 1, lambda u, a, v, xx=xx: (xx + u, ys + (ye - ys) * a + 0.0 * v, zs + (ze - zs) * a + v + 0.15)))
# ---------------- central clock pavilion ----------------
pav = c.box("pav", (16, 4, 22), (0, -12.4, Z0 + 11))
pcut = join([fy(0, Z0 + 12.5, arch(5.0, 6.0), -14.8, -9.8), fy(0, Z0, arch(6.0, 9.0), -15.0, -9.8)], "pc")  # window + walk-through to the door
boolean(pav, pcut)
add("Walls", pav)
add("Glass", fy(0, Z0 + 12.55, arch(4.9, 5.9), -12.4 - 0.04, -12.4 + 0.04))
add("Trim", c.box("pav_corn", (17.2, 5.2, 0.7), (0, -12.4, Z0 + 22.3)))
add("Trim", prism([(-8.6, 0), (8.6, 0), (0, 4.6)], -14.8, -10.0, lambda u, a, v: (u, a, Z0 + 22.6 + v)))
add("Gold", cyl("clock_ring", 2.3, 0.4, (0, -14.95, Z0 + 24.6), 32, (math.pi / 2, 0, 0)))
add("Trim", cyl("clock_face", 1.95, 0.42, (0, -15.0, Z0 + 24.6), 32, (math.pi / 2, 0, 0)))
for k in range(12):
    a = k / 12 * 2 * math.pi
    add("Iron", c.box("tick", (0.12, 0.1, 0.35), (1.6 * math.sin(a), -15.25, Z0 + 24.6 + 1.6 * math.cos(a))))
h1 = c.box("hand_h", (0.18, 0.1, 1.1), (0.3, -15.3, Z0 + 25.0))
h1.rotation_euler = (0, math.radians(-35), 0)
add("Iron", h1)
h2 = c.box("hand_m", (0.12, 0.1, 1.6), (-0.35, -15.32, Z0 + 25.25))
h2.rotation_euler = (0, math.radians(25), 0)
add("Iron", h2)
add("Gold", cyl("finial", 0.2, 2.2, (0, -12.4, Z0 + 28.2), 8))
add("Gold", c.sphere("ball", 0.45, (0, -12.4, Z0 + 29.4), segments=10, rings=6))
add("Gold", c.box("signband", (12, 0.3, 1.5), (0, -14.65, Z0 + 10.8)))
bpy.ops.object.text_add(location=(0, -14.85, Z0 + 10.35), rotation=(math.pi / 2, 0, 0))
txt = bpy.context.active_object
txt.data.body = "DEPOT"
txt.data.size = 1.25
txt.data.extrude = 0.06
txt.data.align_x = "CENTER"
txt.data.space_character = 1.3
bpy.ops.object.convert(target="MESH")
add("Letters", bpy.context.active_object)
# ---------------- roofs ----------------
tile_roof_x(-HW / 2 - 1.0, HW / 2 + 1.0, -13.2, 13.2, Z0 + HH + 0.8, 6.0)
for s in (-1, 1):
    tile_roof_x(s * WX0 if s > 0 else -WX1 - 0.8, s * WX1 + 0.8 if s > 0 else -WX0, -11.0, 11.0, Z0 + WH + 0.7, 4.2)
# ---------------- back platform canopy (jeepney stand) ----------------
for x in range(-24, 25, 8):
    add("Iron", cyl("post", 0.25, 8.0, (x, 19.0, Z0 + 4.0), 10))
    add("Iron", c.box("bracket", (0.2, 4.0, 0.2), (x, 17.2, Z0 + 7.6)))
add("Roof", c.box("canopy", (52, 7.5, 0.3), (0, 17.5, Z0 + 8.2)))
add("Trim", c.box("canopy_edge", (52.4, 0.3, 0.6), (0, 21.3, Z0 + 8.0)))
add("Floor", c.box("platform", (54, 9, 0.12), (0, 17.5, Z0 + 0.06)))
add("Gold", c.box("platform_line", (52, 0.4, 0.13), (0, 21.6, Z0 + 0.07)))
# ---------------- waiting hall interior ----------------
add("Floor", c.box("hall_floor", (HW - 2 * T, HD - 2 * T, 0.1), (0, 0, Z0 + 0.05)))
add("Wood", c.box("booth", (10, 3.2, 3.6), (0, 8.5, Z0 + 1.8)))
add("Glass", c.box("booth_glass", (9.6, 0.15, 2.6), (0, 6.85, Z0 + 4.9)))
add("Trim", c.box("booth_top", (10.6, 3.8, 0.5), (0, 8.5, Z0 + 6.4)))
add("Iron", c.box("board", (8, 0.3, 3.0), (0, 10.9, Z0 + 10.0)))
add("Gold", c.box("board_frame", (8.6, 0.25, 3.6), (0, 10.95, Z0 + 10.0)))
for k in range(4):
    add("Lamp", c.box("board_line", (6.8, 0.32, 0.25), (0, 10.75, Z0 + 11.0 - k * 0.65)))
for s in (-1, 1):
    for y in (-5.0, 0.0):
        add("Wood", c.box("bench", (8, 1.6, 0.35), (s * 11.0, y, Z0 + 1.5)))
        add("Wood", c.box("bench_back", (8, 0.3, 1.4), (s * 11.0, y + 0.85, Z0 + 2.3)))
        add("Iron", c.box("bench_leg", (0.3, 1.4, 1.3), (s * 11.0 - 3.5, y, Z0 + 0.65)))
        add("Iron", c.box("bench_leg", (0.3, 1.4, 1.3), (s * 11.0 + 3.5, y, Z0 + 0.65)))
    add("Stone", c.lathe("pot", [(0.01, 0), (0.9, 0), (1.1, 1.2), (0.01, 1.2)], steps=12))
    G["Stone"][-1].location = (s * 16.5, 8.5, Z0)
    add("Leaves", blob(1.3, (s * 16.5, 8.5, Z0 + 2.8)))
for x in (-12.0, 0.0, 12.0):
    add("Iron", cyl("cord", 0.05, 4.0, (x, -2.0, Z0 + HH - T - 2.0), 6))
    add("Lamp", c.sphere("pendant", 0.6, (x, -2.0, Z0 + HH - T - 4.2), segments=12, rings=8))
# ---------------- planters by the steps ----------------
for s in (-1, 1):
    add("Stone", c.box("planter", (3.0, 3.0, 1.4), (s * 13.5, -22.0, Z0 + 0.7)))
    add("Leaves", blob(1.1, (s * 13.5, -22.0, Z0 + 2.2)))
    for j in range(4):
        add("Flowers", blob(0.3, (s * 13.5 + 0.8 * math.cos(j * 1.6), -22.6 + 0.6 * math.sin(j * 1.6), Z0 + 2.6 + 0.25 * j)))

SPEC = {"Walls": ("yellow", "plaster"), "Trim": ("white", "limestone"), "Stone": ("stone", "stone"), "Roof": ("terracotta", "clay"),
        "Glass": ("glass", None), "Shutters": ("teal", None), "Gold": ("gold", None), "Iron": ("black", None), "Letters": ("black", None),
        "Floor": ("floor", "marble"), "Wood": ("wood", "wood"), "Lamp": ("warm", None), "Leaves": ("leaf", None), "Flowers": ("pink", None)}
final = []
for name, objs in G.items():
    obj = join(objs, "Depot_" + name)
    col, tex = SPEC[name]
    c.finish(obj, "Depot_" + name, col, smooth=name in ("Gold", "Lamp", "Leaves", "Flowers"))
    if tex:
        uv_box(obj, 8.0)
        tx.apply(obj, tex, "Depot_" + name + "_mat", (0.98, 0.82, 0.45) if name == "Walls" else None)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
print("DEPOT triangles", c.triangle_count(final), [(o.name, c.triangle_count([o])) for o in final])
c.export_glb(os.path.join(c.OUT_MODELS, "Depot.glb"), final)


def render(path, cam, target, lens=35, samples=40, lights=False):
    import mathutils
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1100, 780
    sc.view_settings.view_transform = "AgX"
    if not bpy.data.objects.get("Sun"):
        w = bpy.data.worlds.new("Sky")
        w.use_nodes = True
        sky = w.node_tree.nodes.new("ShaderNodeTexSky")
        w.node_tree.links.new(sky.outputs["Color"], w.node_tree.nodes["Background"].inputs["Color"])
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
        sc.world = w
        sd = bpy.data.lights.new("Sun", "SUN")
        sd.energy = 4.2
        sd.color = (1.0, 0.86, 0.7)
        so = bpy.data.objects.new("Sun", sd)
        bpy.context.collection.objects.link(so)
        so.rotation_euler = (math.radians(55), 0, math.radians(200))
        gd = bpy.data.meshes.new("g")
        go = bpy.data.objects.new("g", gd)
        bpy.context.collection.objects.link(go)
        b2 = bmesh.new()
        bmesh.ops.create_grid(b2, x_segments=1, y_segments=1, size=120)
        b2.to_mesh(gd)
        b2.free()
    if lights:
        for x in (-12.0, 0.0, 12.0):
            ld = bpy.data.lights.new("p", "POINT")
            ld.energy = 2500
            ld.color = (1, 0.85, 0.65)
            lo = bpy.data.objects.new("p", ld)
            bpy.context.collection.objects.link(lo)
            lo.location = (x, -2, Z0 + 8.5)
        for o in final:
            if o.name == "Depot_Roof":
                o.hide_render = True
    cm = bpy.data.objects.get("Cam") or bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    if not cm.users_collection:
        bpy.context.collection.objects.link(cm)
    cm.data.lens = lens
    cm.location = cam
    cm.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(cam)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cm
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


render(os.path.join(c.OUT_PREVIEWS, "Depot_front.png"), (42, -78, 26), (0, 0, 10))
render(os.path.join(c.OUT_PREVIEWS, "Depot_inside.png"), (-14, -9, 6), (6, 9, 6), 20, 48, lights=True)
print("done")
