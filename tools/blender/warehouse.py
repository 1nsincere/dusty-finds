"""Dusty Finds Supply Warehouse ("bodega"), walk-in (Blender 5.x, headless). Visual shell around the gameplay SupplyCounter.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/warehouse.py
Writes assets/models/Warehouse.glb and assets/previews/Warehouse_*.png (git-ignored).

Real studs. Front (entrance) faces -Y, origin = centre of the footprint at FLOOR level (z = 0); the street is 1.55 lower.
Footprint 42 x 50 (+ steps and canopy in front). Hall walls 13 tall, stepped gable front parapet to 22.5.
The game's SupplyDesk/SupplyCounter stays in Studio (not in this model): it stands 4 studs inside the front wall, 9 studs
left or right of the door, so that whole strip (|x| 4..15, y -24..-17) is kept clear. Groups Warehouse_<Group>.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.PALETTE.update({"brick": "B8573C", "cream": "F4EAD2", "stone": "CFC5B0", "glass": "3E5F78", "metal": "5E6E68",
                  "iron": "2E3236", "wood": "7A5233", "crate": "B88A55", "floor": "8A6A48", "warm": "FFD9A0",
                  "teal": "1F7A7A", "gold": "E3B23C", "leaf": "3F7F3A", "pink": "E0458C"})
c.reset_scene()
G = {}
T = 1.0
W, D, H = 42.0, 50.0, 13.0          # hall: x +-21, y -25..25, walls to z 13
Y0, Y1 = -D / 2, D / 2
STREET = -1.55


def add(g, o):
    G.setdefault(g, []).append(o)
    return o


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


def circle(r, segs=20):
    return [(r * math.cos(2 * math.pi * i / segs), r + r * math.sin(2 * math.pi * i / segs)) for i in range(segs)]


def prism(pts, a0, a1, place):
    n = len(pts)
    verts = [place(u, a, v) for a in (a0, a1) for (u, v) in pts]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    return mesh_from("p", verts, faces)


def fy(x, zb, pts, y0, y1):
    """Profile in the XZ plane (u along X, v up), extruded along Y."""
    return prism(pts, y0, y1, lambda u, a, v: (x + u, a, zb + v))


def fx(y, zb, pts, x0, x1):
    """Profile in the YZ plane (u along Y, v up), extruded along X."""
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


# ---------------- plinth and front steps ----------------
add("Stone", c.box("plinth", (W + 2, D + 2, -STREET), (0, 0, STREET / 2)))
for i in range(3):
    h = -STREET * (3 - i) / 3
    add("Stone", c.box("step", (16 + i * 1.0, 1.2, h), (0, Y0 - 1.6 - i * 1.2, STREET + h / 2)))  # tallest step against the plinth

# ---------------- hollow hall ----------------
outer = c.box("outer", (W, D, H), (0, 0, H / 2))
inner = c.box("inner", (W - 2 * T, D - 2 * T, H + 1), (0, 0, H / 2 + 0.2))
boolean(outer, inner)
cuts = [fy(0, -0.1, arch(10.0, 10.0), Y0 - 0.6, Y0 + T + 0.6)]                      # main entrance
for x in (-15.0, 15.0):
    cuts.append(fy(x, 2.5, arch(4.0, 7.5), Y0 - 0.6, Y0 + T + 0.6))                  # front windows
SIDE_Y = (-15.0, -5.0, 5.0, 15.0)
for s in (-1, 1):
    for y in SIDE_Y:
        cuts.append(fx(y, 4.0, arch(3.6, 7.5), s * (W / 2 + 0.6), s * (W / 2 - T - 0.6)))  # tall side windows
for x in (-10.0, 10.0):
    cuts.append(fy(x, -0.1, [(-4, 0), (4, 0), (4, 8), (-4, 8)], Y1 - T - 0.6, Y1 + 0.6))   # back loading doors
boolean(outer, join(cuts, "cuts"))
add("Walls", outer)

# front stepped gable parapet (covers the roof end) with an oculus
STEPS = [(-22, 0), (22, 0), (22, 2), (17, 2), (17, 4.5), (11, 4.5), (11, 7), (5, 7), (5, 9.5), (-5, 9.5), (-5, 7), (-11, 7),
         (-11, 4.5), (-17, 4.5), (-17, 2), (-22, 2)]
par = fy(0, H, STEPS, Y0 - 0.2, Y0 + 1.2)
boolean(par, fy(0, H + 3.4, circle(2.0), Y0 - 0.8, Y0 + 1.8))
add("Walls", par)
add("Glass", fy(0, H + 3.45, circle(1.95), Y0 + 0.45, Y0 + 0.55))
add("Trim", c.box("oculus_key", (0.9, 0.5, 1.0), (0, Y0 - 0.25, H + 7.6)))
for (x0, x1, z) in ((17, 22, 2), (11, 17, 4.5), (5, 11, 7), (-5, 5, 9.5)):
    for s in (1, -1) if x0 > 0 else (1,):
        cx = s * (x0 + x1) / 2 if x0 > 0 else 0
        add("Trim", c.box("par_cap", (x1 - x0 + 0.6, 1.8, 0.45), (cx, Y0 + 0.5, H + z + 0.22)))
# back gable (plain, closes the roof)
add("Walls", fy(0, H, [(-21, 0), (21, 0), (0, 7.0)], Y1 - T, Y1))

# ---------------- trim: plinth band, cornice, pilasters, sign band ----------------
add("Trim", c.box("base_band", (W + 0.5, D + 0.5, 0.9), (0, 0, 0.45)))
add("Trim", c.box("cornice", (W + 1.4, D + 1.4, 0.7), (0, 0, H - 0.1)))
for x in (-21.0, -8.5, 8.5, 21.0):
    add("Trim", c.box("pil_f", (1.4, 0.6, H), (x, Y0 - 0.25, H / 2)))
for s in (-1, 1):
    for y in (-25.0, -10.0, 0.0, 10.0, 25.0):
        add("Trim", c.box("pil_s", (0.6, 1.4, H), (s * (W / 2 + 0.25), y, H / 2)))
    for y in SIDE_Y:  # window sills and keystones
        add("Trim", c.box("sill", (0.6, 4.4, 0.35), (s * (W / 2 + 0.3), y, 3.9)))
        add("Trim", c.box("key", (0.7, 0.8, 1.0), (s * (W / 2 + 0.3), y, 11.3)))
        add("Glass", fx(y, 4.05, arch(3.5, 7.4), s * (W / 2 - T / 2 + 0.05), s * (W / 2 - T / 2 - 0.05)))
for x in (-15.0, 15.0):
    add("Glass", fy(x, 2.55, arch(3.9, 7.4), Y0 + T / 2 - 0.05, Y0 + T / 2 + 0.05))
    add("Trim", c.box("sill_f", (4.6, 0.6, 0.35), (x, Y0 - 0.3, 2.4)))
    add("Teal", c.box("shutter", (1.6, 0.15, 6.0), (x - 2.9, Y0 - 0.2, 5.6)))
    add("Teal", c.box("shutter", (1.6, 0.15, 6.0), (x + 2.9, Y0 - 0.2, 5.6)))
ring = fy(0, -0.1, arch(11.6, 10.8), Y0 - 0.5, Y0 + 0.2)
boolean(ring, fy(0, -0.5, arch(10.0, 10.0), Y0 - 1.0, Y0 + 0.7))
add("Trim", ring)
add("Trim", c.box("door_key", (1.2, 0.9, 1.4), (0, Y0 - 0.45, 10.4)))
add("Teal", c.box("signband", (16, 0.4, 1.7), (0, Y0 - 0.45, 12.0)))  # dark band so the cream letters read
bpy.ops.object.text_add(location=(0, Y0 - 0.7, 11.45), rotation=(math.pi / 2, 0, 0))
txt = bpy.context.active_object
txt.data.body = "WAREHOUSE"
txt.data.size = 1.2
txt.data.extrude = 0.06
txt.data.align_x = "CENTER"
txt.data.space_character = 1.15
bpy.ops.object.convert(target="MESH")
add("Letters", bpy.context.active_object)

# ---------------- entrance canopy and lamps ----------------
add("Metal", c.box("canopy", (13, 4.0, 0.25), (0, Y0 - 2.0, 10.5)))
add("Iron", c.box("canopy_edge", (13.2, 0.2, 0.5), (0, Y0 - 4.0, 10.4)))
for x in (-6.0, 6.0):  # brackets under the canopy, from the wall down to the outer edge
    rod = c.box("bracket", (0.15, 4.4, 0.15), (x, Y0 - 2.0, 9.4))
    rod.rotation_euler = (-math.atan2(2.0, 4.0), 0, 0)
    add("Iron", rod)
for x in (-7.3, 7.3):
    add("Iron", c.box("lamp_arm", (0.15, 1.0, 0.15), (x, Y0 - 0.6, 8.2)))
    add("Lamp", c.box("lamp", (0.7, 0.7, 1.0), (x, Y0 - 1.1, 7.7)))

# ---------------- corrugated metal roof (ridge along Y) ----------------
RISE, EAVE = 7.0, H + 0.2
run = W / 2 + 1.0
L = math.hypot(run, RISE)
ang = math.atan2(RISE, run)
for s in (-1, 1):
    # rotation about Y: +ang lowers the +X end, so the right slope (s=+1) uses +ang and the left one -ang
    slab = c.box("roof", (L, D + 1.0, 0.3), (s * run / 2, 0.6, EAVE + RISE / 2))
    slab.rotation_euler = (0, s * ang, 0)
    add("Metal", slab)
    nrib = 30
    for k in range(nrib + 1):
        t = L * k / nrib                     # distance up the slope from the eave
        px = s * (run - t * math.cos(ang))
        pz = EAVE + t * math.sin(ang) + 0.22
        rib = c.box("rib", (0.25, D + 1.0, 0.18), (px, 0.6, pz))
        rib.rotation_euler = (0, s * ang, 0)
        add("Metal", rib)
add("Iron", c.box("ridge_cap", (1.2, D + 1.2, 0.4), (0, 0.6, EAVE + RISE + 0.2)))
for y in (-12.0, 0.0, 12.0):  # roof vents
    add("Metal", cyl("vent", 0.9, 1.6, (0, y, EAVE + RISE + 0.9), 12))
    add("Iron", cyl("vent_cap", 1.3, 0.3, (0, y, EAVE + RISE + 1.8), 12))

# ---------------- back loading doors (visual roller doors) ----------------
for x in (-10.0, 10.0):
    add("Metal", c.box("roller", (8.0, 0.2, 8.0), (x, Y1 - T / 2, 4.0)))
    for k in range(10):
        add("Iron", c.box("roller_slat", (8.0, 0.25, 0.1), (x, Y1 - T / 2 + 0.05, 0.6 + k * 0.78)))
    add("Teal", c.box("door_hood", (9.0, 1.2, 0.6), (x, Y1 + 0.5, 8.4)))

# ---------------- interior ----------------
add("Floor", c.box("floor", (W - 2 * T, D - 2 * T, 0.1), (0, 0, 0.05)))
# steel trusses: tie beam, rafters, king post, struts
for y in (-16.0, -8.0, 0.0, 8.0, 16.0):
    add("Iron", c.box("tie", (W - 2 * T, 0.5, 0.5), (0, y, H - 0.4)))
    for s in (-1, 1):
        raf = c.box("rafter", (math.hypot(W / 2 - T, RISE - 0.6), 0.45, 0.45), (s * (W / 2 - T) / 2, y, H - 0.4 + (RISE - 0.6) / 2))
        raf.rotation_euler = (0, s * math.atan2(RISE - 0.6, W / 2 - T), 0)
        add("Iron", raf)
        st = c.box("strut", (0.3, 0.3, 4.0), (s * 7.0, y, H + 1.4))
        st.rotation_euler = (0, -s * 0.45, 0)
        add("Iron", st)
    add("Iron", c.box("king", (0.35, 0.35, RISE - 0.6), (0, y, H - 0.4 + (RISE - 0.6) / 2)))
# pendant lamps
for y in (-12.0, 4.0, 18.0):
    for x in (-8.0, 8.0):
        add("Iron", cyl("cord", 0.05, 3.5, (x, y, H - 2.2), 6))
        add("Metal", c.lathe("shade", [(0.01, 0.0), (1.1, 0.0), (0.35, 0.6), (0.01, 0.6)], steps=12))
        G["Metal"][-1].location = (x, y, H - 4.2)
        add("Lamp", c.sphere("bulb", 0.35, (x, y, H - 4.3), segments=10, rings=6))
# storage racks along both side walls (back two thirds)
for s in (-1, 1):
    rx = s * (W / 2 - T - 2.0)
    for y0 in (-8.0, 8.0):
        for dy in (-7.0, 7.0):
            for dx in (-1.6, 1.6):
                add("Iron", c.box("upright", (0.3, 0.3, 9.0), (rx + dx, y0 + dy, 4.5)))
        for z in (0.4, 3.2, 6.0, 8.8):
            add("Wood", c.box("shelf", (3.6, 14.4, 0.25), (rx, y0, z)))
        for k, z in enumerate((0.55, 3.35, 6.15)):
            for j in range(4):
                if (j + k + (1 if s > 0 else 0)) % 3 == 2:
                    continue
                sz = 2.0 + 0.4 * ((j + k) % 2)
                add("Crate", c.box("crate", (2.4, sz, sz * 0.8), (rx, y0 - 5.0 + j * 3.4, z + sz * 0.4)))
# pallets of crates in the middle (back half), leaving a wide aisle from the door
for (px, py) in ((-6.0, 12.0), (6.0, 12.0), (-6.0, 19.0), (6.0, 19.0)):
    add("Wood", c.box("pallet", (4.0, 4.0, 0.5), (px, py, 0.25)))
    for (ox, oy, oz) in ((-0.95, -0.95, 0), (0.95, -0.95, 0), (-0.95, 0.95, 0), (0.95, 0.95, 0), (0.0, 0.0, 1.8)):
        if oz and (px + py) % 2:
            continue
        add("Crate", c.box("crate", (1.8, 1.8, 1.8), (px + ox, py + oy, 0.5 + 0.9 + oz)))
# hanging sign over the counter strip so it reads as "the place you buy crates"
for s in (-1, 1):
    add("Iron", cyl("sign_rod", 0.05, 2.0, (s * 9.0 - 2.0, Y0 + 4.5, H - 2.0), 6))
    add("Iron", cyl("sign_rod", 0.05, 2.0, (s * 9.0 + 2.0, Y0 + 4.5, H - 2.0), 6))
    add("Teal", c.box("supply_sign", (5.2, 0.25, 1.6), (s * 9.0, Y0 + 4.5, H - 3.6)))
    add("Gold", c.box("supply_sign_line", (4.6, 0.3, 0.2), (s * 9.0, Y0 + 4.5, H - 3.2)))
# planters by the steps
for s in (-1, 1):
    add("Stone", c.box("planter", (2.6, 2.6, 1.2), (s * 10.5, Y0 - 3.0, STREET + 0.6)))
    add("Leaves", blob(1.0, (s * 10.5, Y0 - 3.0, STREET + 1.9)))
    for j in range(4):
        add("Flowers", blob(0.28, (s * 10.5 + 0.7 * math.cos(j * 1.6), Y0 - 3.5 + 0.5 * math.sin(j * 1.6), STREET + 2.3 + 0.2 * j)))

SPEC = {"Walls": ("brick", "plaster"), "Trim": ("cream", "limestone"), "Stone": ("stone", "stone"), "Metal": ("metal", None),
        "Iron": ("iron", None), "Glass": ("glass", None), "Teal": ("teal", None), "Letters": ("cream", None),
        "Floor": ("floor", "wood"), "Wood": ("wood", "wood"), "Crate": ("crate", "wood"), "Lamp": ("warm", None),
        "Gold": ("gold", None), "Leaves": ("leaf", None), "Flowers": ("pink", None)}
final = []
for name, objs in G.items():
    obj = join(objs, "Warehouse_" + name)
    col, tex = SPEC[name]
    c.finish(obj, "Warehouse_" + name, col, smooth=name in ("Lamp", "Leaves", "Flowers"))
    if tex:
        uv_box(obj, 8.0)
        tx.apply(obj, tex, "Warehouse_" + name + "_mat", (0.72, 0.33, 0.24) if name == "Walls" else None)
    final.append(obj)

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
print("WAREHOUSE triangles", c.triangle_count(final), [(o.name, c.triangle_count([o])) for o in final])
c.export_glb(os.path.join(c.OUT_MODELS, "Warehouse.glb"), final)


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
        go.location = (0, 0, STREET)
        b2 = bmesh.new()
        bmesh.ops.create_grid(b2, x_segments=1, y_segments=1, size=120)
        b2.to_mesh(gd)
        b2.free()
    if lights:
        for y in (-12.0, 4.0, 18.0):
            ld = bpy.data.lights.new("p", "POINT")
            ld.energy = 900
            ld.color = (1, 0.85, 0.65)
            lo = bpy.data.objects.new("p", ld)
            bpy.context.collection.objects.link(lo)
            lo.location = (0, y, H - 5.0)
        for o in final:
            if o.name == "Warehouse_Metal":
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


render(os.path.join(c.OUT_PREVIEWS, "Warehouse_front.png"), (38, -72, 20), (0, 0, 8))
render(os.path.join(c.OUT_PREVIEWS, "Warehouse_inside.png"), (0, -22, 7), (0, 10, 8), 18, 48, lights=True)
print("done")
