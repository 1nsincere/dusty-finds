"""
alarm_clock.py - Dusty Finds "AlarmClock" model -> alarm_clock.glb  (Owner: Dev 2 / art pipeline)

Self-contained bpy script. 1 Blender unit = 1 Roblox stud. Blender Z-up, bottom of feet on Z=0,
clock face points -Y (glTF exporter maps that to +Z in Roblox). Final box: 2.4 (X) x 1.3 (Y) x 2.2 (Z),
i.e. W x D x H = 2.4 x 1.3 x 2.2 studs.

Run (UI):       Scripting tab -> open this file -> Run Script
Run (headless): blender --background --python tools/blender/alarm_clock.py -- C:/out/alarm_clock.glb
Output path: the argument after "--", else next to this script.
"""
import bpy, bmesh, math, os, sys
from math import pi, sin, cos, radians
from mathutils import Matrix, Vector

TARGET = Vector((2.4, 1.3, 2.2))          # X (width), Y (depth), Z (height)
CX, CY, CZ = 0.0, 0.28, 1.0               # drum centre (before final normalise)
DRUM_R, DRUM_FRONT, DRUM_BACK = 0.82, -0.32, 0.88
BELL_ANGLE = radians(55)                  # bells sit this far from straight up
HEX = {"coral": "#D94B38", "cream": "#F6F1DF", "brass": "#C8A45D", "brown": "#3A261D"}

bpy.ops.wm.read_factory_settings(use_empty=True)  # must run before materials are created

# ---------------------------------------------------------------- helpers
def lin(c):  # sRGB 0..1 -> linear (glTF base colours are linear)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def make_mat(name, hexcol, metallic, rough):
    h = hexcol.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (lin(r), lin(g), lin(b), 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m

MAT = {
    "coral": make_mat("Coral", HEX["coral"], 0.0, 0.45),
    "cream": make_mat("Cream", HEX["cream"], 0.0, 0.6),
    "brass": make_mat("Brass", HEX["brass"], 1.0, 0.3),
    "brown": make_mat("DarkBrown", HEX["brown"], 0.0, 0.5),
}

def T(x, y, z): return Matrix.Translation((x, y, z))
def R(a, axis): return Matrix.Rotation(a, 4, axis)
def S(x, y, z): return Matrix.Diagonal((x, y, z, 1.0))

def to_object(name, bm, matkey, parent):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    me.materials.append(MAT[matkey])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob

def add_modifier_and_apply(ob, mod):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    old = ob.data; ob.data = me; me.name = ob.name
    for p in me.polygons: p.use_smooth = True
    if old.users == 0: bpy.data.meshes.remove(old)

def bevel(ob, width, segs=3):
    m = ob.modifiers.new("Bevel", "BEVEL"); m.width = width; m.segments = segs
    m.limit_method = "ANGLE"; m.angle_limit = radians(30)
    add_modifier_and_apply(ob, m)

def solidify(ob, t, offset=-1.0):
    m = ob.modifiers.new("Solid", "SOLIDIFY"); m.thickness = t; m.offset = offset
    add_modifier_and_apply(ob, m)

def cyl(bm, r1, r2, depth, mat, segs=32):
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r1, radius2=r2, depth=depth, matrix=mat, calc_uvs=True)

def sphere(bm, r, mat, u=24, v=12):
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r, matrix=mat)

def tube(bm, pts, radius, sides=12):
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n1 = Vector((0, 1, 0)); n2 = t.cross(n1).normalized()
        rings.append([bm.verts.new(p + radius * (cos(2 * pi * k / sides) * n1 + sin(2 * pi * k / sides) * n2))
                      for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])

# ---------------------------------------------------------------- scene
root =bpy.data.objects.new("AlarmClock", None)
bpy.context.scene.collection.objects.link(root)

# BodyDrum: chunky beveled barrel, axis along Y
bm = bmesh.new()
cyl(bm, DRUM_R, DRUM_R, DRUM_BACK - DRUM_FRONT, T(CX, (DRUM_FRONT + DRUM_BACK) / 2, CZ) @ R(pi / 2, "X"))
drum = to_object("BodyDrum", bm, "coral", root); bevel(drum, 0.09, 4)

# Bezel: raised torus rim around the dial
bpy.ops.mesh.primitive_torus_add(major_segments=48, minor_segments=14, major_radius=0.745,
                                 minor_radius=0.075, location=(CX, -0.345, CZ), rotation=(pi / 2, 0, 0))
bez = bpy.context.active_object; bez.name = "Bezel"; bez.data.name = "Bezel"
bez.data.materials.append(MAT["coral"]); bez.parent = root
for p in bez.data.polygons: p.use_smooth = True

# ClockFace: recessed cream disc with planar UVs (front view, X right / Z up) for the 1-12 texture
bm = bmesh.new()
FR = 0.68
cyl(bm, FR, FR, 0.03, T(CX, -0.335, CZ) @ R(pi / 2, "X"), segs=48)
uv = bm.loops.layers.uv.verify()
for f in bm.faces:
    for l in f.loops:
        l[uv].uv = (0.5 + (l.vert.co.x - CX) / (2 * FR), 0.5 + (l.vert.co.z - CZ) / (2 * FR))
face = to_object("ClockFace", bm, "cream", root)

# HourMarkers: 12 chunky ticks (bigger at 12/3/6/9)
bm = bmesh.new()
for i in range(12):
    a = radians(i * 30); big = i % 3 == 0
    pos = (CX + 0.585 * sin(a), -0.356, CZ + 0.585 * cos(a))
    bmesh.ops.create_cube(bm, size=1.0, matrix=T(*pos) @ R(a, "Y") @ S(0.05 if big else 0.032, 0.012, 0.11 if big else 0.075))
to_object("HourMarkers", bm, "brown", root)

# Hands: kite-shaped, solidified. Clock angle = clockwise from 12; 10:10 -> hour 305 deg, minute 60 deg
def hand(name, clock_deg, length, width, tail, y, thick):
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((0, 0, -tail), (width, 0, 0.18 * length), (0, 0, length), (-width, 0, 0.18 * length))]
    bm.faces.new(vs)
    ob = to_object(name, bm, "brown", root)
    ob.location = (CX, y, CZ); ob.rotation_euler = (0, radians(clock_deg), 0)
    solidify(ob, thick, 0.0)
    return ob
hand("HourHand", 305, 0.36, 0.07, 0.08, -0.368, 0.014)
hand("MinuteHand", 60, 0.52, 0.05, 0.10, -0.382, 0.014)
hand("SecondHand", 180, 0.54, 0.014, 0.12, -0.396, 0.01)
bm = bmesh.new(); cyl(bm, 0.055, 0.055, 0.03, T(CX, -0.405, CZ) @ R(pi / 2, "X"), segs=24)
bev = to_object("CenterCap", bm, "brown", root); bevel(bev, 0.008, 2)

# Bells (half-dome, hollow) on angled stems + CarryHandle finials
def bell(name, side):
    th = side * BELL_ANGLE
    d = Vector((sin(th), 0, cos(th)))
    c = Vector((CX, CY, CZ))
    bm = bmesh.new()
    sphere(bm, 0.40, Matrix.Identity(4), 28, 14)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    bmesh.ops.transform(bm, matrix=T(*(c + d * 1.05)) @ R(th, "Y"), verts=bm.verts)
    ob = to_object(name, bm, "brass", root); solidify(ob, 0.035, -1.0)
    bm = bmesh.new()                                   # stem: drum surface -> dome base
    cyl(bm, 0.045, 0.045, 0.34, T(*(c + d * 0.93)) @ R(th, "Y"), segs=16)
    stem = to_object(name + "Stem", bm, "brass", root)
    return ob
bell("LeftBell", -1); bell("RightBell", 1)

# CarryHandle: smooth arch from left finial to right finial
fx, fz = 1.45 * sin(BELL_ANGLE), CZ + 1.45 * cos(BELL_ANGLE)
pts = []
for i in range(33):
    x = -fx + 2 * fx * i / 32
    pts.append(Vector((x, CY, fz + 0.32 * (1 - (x / fx) ** 2))))
bm = bmesh.new(); tube(bm, pts, 0.04, 12)
for s in (-1, 1): sphere(bm, 0.07, T(s * fx, CY, fz), 16, 10)
to_object("CarryHandle", bm, "brass", root)

# SnoozePost: T-shaped post under the handle
bm = bmesh.new()
cyl(bm, 0.04, 0.04, 0.26, T(CX, CY, CZ + DRUM_R + 0.11), segs=16)
cyl(bm, 0.04, 0.04, 0.36, T(CX, CY, CZ + DRUM_R + 0.24) @ R(pi / 2, "Y"), segs=16)
sphere(bm, 0.05, T(CX - 0.18, CY, CZ + DRUM_R + 0.24), 12, 8); sphere(bm, 0.05, T(CX + 0.18, CY, CZ + DRUM_R + 0.24), 12, 8)
to_object("SnoozePost", bm, "brass", root)

# Feet: tapered pegs angled outward (wide end up, tucked under the drum)
for name, s in (("FootL", -1), ("FootR", 1)):
    bm = bmesh.new()
    cyl(bm, 0.11, 0.18, 0.5, T(CX + s * 0.55, CY, 0.22) @ R(-s * radians(25), "Y"), segs=20)
    f = to_object(name, bm, "brown", root); bevel(f, 0.04, 3)

# ---------------------------------------------------------------- normalise: centre X/Y, feet on Z=0, exact 2.4 x 1.3 x 2.2
meshes = [o for o in root.children if o.type == "MESH"]
for o in meshes:
    o.data.transform(o.matrix_world); o.matrix_world = Matrix.Identity(4)
mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
for o in meshes:
    for v in o.data.vertices:
        for i in range(3): mn[i] = min(mn[i], v.co[i]); mx[i] = max(mx[i], v.co[i])
size = mx - mn
k = Vector((TARGET[i] / size[i] for i in range(3)))
print("[alarm_clock] raw size %s, scale factors %s" % (tuple(round(x, 3) for x in size), tuple(round(x, 3) for x in k)))
for i, n in enumerate("XYZ"):
    if abs(k[i] - 1) > 0.08: print("[alarm_clock] WARNING: %s axis scaled by %.2f - consider retuning proportions" % (n, k[i]))
cen = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for o in meshes:
    o.data.transform(S(*k) @ T(-cen.x, -cen.y, -cen.z))
    o.data.update()

# ---------------------------------------------------------------- export
out = None
if "--" in sys.argv:
    rest = sys.argv[sys.argv.index("--") + 1:]
    out = rest[0] if rest else None
if not out:
    try: base = os.path.dirname(os.path.abspath(__file__))
    except NameError: base = os.path.expanduser("~")
    out = os.path.join(base, "alarm_clock.glb")
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                          export_yup=True, export_materials="EXPORT")
print("[alarm_clock] exported", out, "| dims W x D x H =", tuple(round(x, 3) for x in TARGET))
