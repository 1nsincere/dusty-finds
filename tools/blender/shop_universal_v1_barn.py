"""Universal Shop Shell: a calm, neutral, relief-only shop that looks good in ANY palette (Blender 5.x, headless).

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/shop_universal.py
Writes assets/models/ShopU_Base.glb, assets/models/ShopU_BackRoom.glb and preview renders assets/previews/ShopU_*.png.
Set DF_SKIP_RENDER=1 to export without the renders.

Two INDEPENDENT modules (docs: universal shop redesign):
  ShopU_Base     the standard shop, 40 x 40 plot base (same size and coordinates as shop.py): front facade with door and windows,
                 both side walls, upper storey, gable roof. Works alone (the Back Room is not bought yet).
  ShopU_BackRoom the extension: 40 wide x 24 deep, continues the same side walls, window rhythm, belt course and roof from the base back wall.
  The base ends in a removable "BackCap" (rear gable wall + roof end). Studio hides Shop_BackCap* once the Back Room is owned,
  and the extension slots in behind. One building from both sides.

Coordinates: plot base units, 1 stud = 1 unit; Blender Z up; the shop front (door) is +Y, the back wall (open, gameplay) is y = -20.
Colour slots (plain light-grey surfaces, tinted by Studio): Walls, Trim, Accent. Fixed neutrals: Glass, Roof. Floor is the existing slab.
Group names: <Prefix>_<Group>; Up* groups are hidden when the player walks in (RoofController); Roof / BackCapRoof too.
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
H1 = 12.5           # ground floor wall top
H2 = 22.0           # upper storey top
PEAK = 29.0         # roof ridge height (top surface)
OUT = 20.2          # outer face of the side walls (inner face = OUT - T)
T = 1.2
BACK = -20.0        # back wall plane of the base
EXT_DEPTH = 24.0
FRONT = 20.2
EAVE = 21.6         # roof reaches this far sideways
ROOF_T = 0.9        # roof slab thickness (vertical)

# ---------------------------------------------------------------- mesh builders (one mesh per colour group)
BASE, EXT = {}, {}      # group -> [(verts, faces)]


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


def prism_x(store, group, pts, y0, y1):
    """Convex polygon in (x, z) extruded along Y from y0 to y1."""
    n = len(pts)
    v = [(p[0], y0, p[1]) for p in pts] + [(p[0], y1, p[1]) for p in pts]
    f = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    _add(store, group, v, f)


def roof_panel(store, group, xa, za, xb, zb, y0, y1, thick=ROOF_T):
    """A sloped slab: top edge from (xa, za) to (xb, zb), thick below it."""
    prism_x(store, group, [(xa, za - thick), (xb, zb - thick), (xb, zb), (xa, za)], y0, y1)


# ---------------------------------------------------------------- walls with openings
def wall(store, group, axis, f0, f1, a0, a1, z0, z1, openings=(), battens=0.0, proud=0.28, inner=0.12, pitch=2.5):
    """axis 'x': thin in X (side wall at fixed range f0..f1, runs along Y a0..a1). axis 'y': thin in Y (runs along X).
    openings: (a_from, a_to, z_bottom, z_top). battens>0 adds vertical board-and-batten ribs on both faces every `pitch`."""
    def box(af, at, zf, zt, ff=f0, ft=f1):
        if axis == "x":
            bx(store, group, ff, ft, af, at, zf, zt)
        else:
            bx(store, group, af, at, ff, ft, zf, zt)

    cuts = sorted(openings)
    cur = a0
    for (oa0, oa1, zb, zt) in cuts:
        box(cur, oa0, z0, z1)
        box(oa0, oa1, z0, zb)
        box(oa0, oa1, zt, z1)
        cur = oa1
    box(cur, a1, z0, z1)
    if battens > 0:
        p = a0 + pitch / 2
        while p < a1 - 0.2:
            segs = [(z0, z1)]
            for (oa0, oa1, zb, zt) in cuts:
                if oa0 - 0.3 < p < oa1 + 0.3:
                    segs = [(z0, zb), (zt, z1)]
                    break
            for (sz0, sz1) in segs:
                if sz1 - sz0 > 0.3:
                    box(p - battens / 2, p + battens / 2, sz0, sz1, f1, f1 + proud)
                    box(p - battens / 2, p + battens / 2, sz0, sz1, f0 - inner, f0)
            p += pitch


def window(store, trim_group, glass_group, axis, f0, f1, a0, a1, zb, zt, outward):
    """Glass pane in the wall + a capiz-style grid (Trim) + a frame. outward = +1 / -1 (which side is outside)."""
    mid = (f0 + f1) / 2

    def b(af, at, zf, zt_, ff, ft):
        if axis == "x":
            bx(store, trim_group if ff is None else trim_group, ff, ft, af, at, zf, zt_)
        else:
            bx(store, trim_group, af, at, ff, ft, zf, zt_)

    # glass
    if axis == "x":
        bx(store, glass_group, mid - 0.08, mid + 0.08, a0, a1, zb, zt)
    else:
        bx(store, glass_group, a0, a1, mid - 0.08, mid + 0.08, zb, zt)
    face0, face1 = (f1, f1 + 0.4) if outward > 0 else (f0 - 0.4, f0)
    fw = 0.4
    # frame (proud on the outside)
    b(a0 - fw, a0, zb - fw, zt + fw, face0, face1)
    b(a1, a1 + fw, zb - fw, zt + fw, face0, face1)
    b(a0, a1, zb - fw, zb, face0, face1)
    b(a0, a1, zt, zt + fw, face0, face1)
    # sill (a little deeper)
    s0, s1 = (f1, f1 + 0.9) if outward > 0 else (f0 - 0.9, f0)
    b(a0 - fw - 0.2, a1 + fw + 0.2, zb - fw - 0.3, zb - fw, s0, s1)
    # grid
    gm0, gm1 = mid - 0.2, mid + 0.2
    cols = max(1, int(round((a1 - a0) / 1.6)))
    for i in range(1, cols):
        a = a0 + (a1 - a0) * i / cols
        b(a - 0.07, a + 0.07, zb, zt, gm0, gm1)
    rows = max(1, int(round((zt - zb) / 1.6)))
    for i in range(1, rows):
        z = zb + (zt - zb) * i / rows
        b(a0, a1, z - 0.07, z + 0.07, gm0, gm1)


# ---------------------------------------------------------------- shared building pieces
def side_runs(store, prefix_up, y_hi, y_lo, win_ys, ground=True, upper=True):
    """Both side walls between y_lo and y_hi, windows centred at win_ys (same 8-stud rhythm in the base and the extension)."""
    for sx in (-1, 1):
        f_in, f_out = (OUT - T, OUT) if sx > 0 else (-OUT, -OUT + T)
        f0, f1 = (f_in, f_out) if sx > 0 else (f_in, f_out)
        outward = 1 if sx > 0 else -1
        if sx < 0:
            f0, f1 = -OUT, -OUT + T
        for level, (z0, z1, wz0, wz1, wgrp, tgrp, grp) in enumerate((
            (F0, H1, 5.4, 10.2, "Glass", "Trim", "Walls"),
            (H1, H2, 15.4, 20.2, "UpGlass", "UpTrim", "UpWalls"),
        )):
            if level == 0 and not ground:
                continue
            if level == 1 and not upper:
                continue
            ops = []
            for wy in win_ys:
                if y_lo + 1.0 < wy - 2.2 and wy + 2.2 < y_hi - 1.0:
                    ops.append((wy - 2.0, wy + 2.0, wz0, wz1))
            if sx < 0:
                lo, hi = (-OUT, -OUT + T)
            else:
                lo, hi = (OUT - T, OUT)
            # thin in X: f0..f1 = lo..hi
            wall(store, grp, "x", lo, hi, y_lo, y_hi, z0, z1, ops, battens=0.3)
            for (a0, a1, zb, zt) in ops:
                window(store, tgrp, wgrp, "x", lo, hi, a0, a1, zb, zt, outward)


def belt_and_plinth(store, y_hi, y_lo, front_closed, back_closed):
    """Plinth at the foot, belt course between the floors, cornice under the roof. Trim slot. Runs around the module."""
    for (g, z0, z1, p) in (("Trim", F0, F0 + 1.2, 0.35), ("Trim", H1 - 0.5, H1 + 0.3, 0.45), ("UpTrim", H2 - 0.8, H2, 0.8)):
        for sx in (-1, 1):
            if sx > 0:
                bx(store, g, OUT, OUT + p, y_lo, y_hi, z0, z1)
            else:
                bx(store, g, -OUT - p, -OUT, y_lo, y_hi, z0, z1)
        if front_closed:
            bx(store, g, -OUT - p, OUT + p, y_hi, y_hi + p, z0, z1) if g != "Trim" or z0 > F0 else None
        if back_closed:
            bx(store, g, -OUT - p, OUT + p, y_lo - p, y_lo, z0, z1)


def pilaster(store, x, y, face):
    """Stepped Art Deco pilaster, centred at (x, y) on a wall facing `face` = +1 (front, +Y) or -1 (back, -Y). Trim slot."""
    for (w, pr, h0, h1) in ((2.8, 0.4, F0, H1 - 0.3), (2.0, 0.8, F0 + 0.6, H1 - 0.9), (1.2, 1.1, F0 + 1.2, H1 - 1.5)):
        if face > 0:
            bx(store, "Trim", x - w / 2, x + w / 2, y, y + pr, h0, h1)
        else:
            bx(store, "Trim", x - w / 2, x + w / 2, y - pr, y, h0, h1)


def roof_run(store, group, y0, y1, trimgroup="UpTrim"):
    """Gable roof along Y between y0 and y1 (y1 > y0)."""
    roof_panel(store, group, -EAVE, H2, 0.0, PEAK, y0, y1)
    roof_panel(store, group, EAVE, H2, 0.0, PEAK, y0, y1)
    bx(store, group, -0.7, 0.7, y0, y1, PEAK - 0.3, PEAK + 0.45)  # ridge cap


# ---------------------------------------------------------------- BASE module (front, sides, upper, roof, removable back cap)
WIN_YS = (12.0, 4.0, -4.0, -12.0, -28.0, -36.0)   # one 8-stud rhythm; the first four belong to the base, the last two to the extension

# side walls: base spans y -20 .. +20.2 (front wall closes the +Y end; front wall is 1.2 thick: y 19 .. 20.2)
side_runs(BASE, "Up", 19.0 + 0.0, BACK, WIN_YS)

# front wall, ground: door + two display windows
W = OUT
wall(BASE, "Walls", "y", 19.0, FRONT, -W, W, F0, H1,
     [(-4.0, 4.0, F0, 9.6), (-16.0, -7.0, 3.2, 9.6), (7.0, 16.0, 3.2, 9.6)], battens=0.3, pitch=2.6)
for (a0, a1) in ((-16.0, -7.0), (7.0, 16.0)):
    window(BASE, "Trim", "Glass", "y", 19.0, FRONT, a0, a1, 3.2, 9.6, 1)
    # Accent awning over each display window, on two Trim brackets
    bx(BASE, "Accent", a0 - 0.6, a1 + 0.6, FRONT + 0.2, FRONT + 2.6, 10.3, 10.65)
    bx(BASE, "Accent", a0 - 0.6, a1 + 0.6, FRONT + 2.5, FRONT + 2.7, 9.9, 10.65)
    for a in (a0 + 0.3, a1 - 0.3):
        bx(BASE, "Trim", a - 0.15, a + 0.15, FRONT + 0.2, FRONT + 2.4, 10.0, 10.3)
# door surround (Accent) and the signboard frame above it
bx(BASE, "Accent", -4.0 - 0.7, -4.0, FRONT, FRONT + 0.55, F0, 10.1)
bx(BASE, "Accent", 4.0, 4.0 + 0.7, FRONT, FRONT + 0.55, F0, 10.1)
bx(BASE, "Accent", -4.7, 4.7, FRONT, FRONT + 0.55, 9.6, 10.1)
SIGN = (-6.2, 6.2, 10.45, 12.1)
bx(BASE, "Accent", SIGN[0], SIGN[1], FRONT, FRONT + 0.5, SIGN[2], SIGN[2] + 0.35)
bx(BASE, "Accent", SIGN[0], SIGN[1], FRONT, FRONT + 0.5, SIGN[3] - 0.35, SIGN[3])
bx(BASE, "Accent", SIGN[0], SIGN[0] + 0.35, FRONT, FRONT + 0.5, SIGN[2], SIGN[3])
bx(BASE, "Accent", SIGN[1] - 0.35, SIGN[1], FRONT, FRONT + 0.5, SIGN[2], SIGN[3])
# front wall, upper storey: three tall windows
UPOPS = [(-14.0, -8.0, 15.4, 20.2), (-3.0, 3.0, 15.4, 20.2), (8.0, 14.0, 15.4, 20.2)]
wall(BASE, "UpWalls", "y", 19.0, FRONT, -W, W, H1, H2, UPOPS, battens=0.3, pitch=2.6)
for (a0, a1, zb, zt) in UPOPS:
    window(BASE, "UpTrim", "UpGlass", "y", 19.0, FRONT, a0, a1, zb, zt, 1)

# Art Deco pilasters: the four corners and either side of the door; trim bands around the module
for x in (-OUT + 1.0, OUT - 1.0, -6.0, 6.0):
    pilaster(BASE, x, FRONT, 1)
belt_and_plinth(BASE, FRONT, BACK, True, False)
# the plinth would block the door: cut it back (rebuild without the middle)
# (the door sill stays flush, so the plinth is only built beside the door below)
bx(BASE, "Trim", -OUT - 0.35, -4.7, FRONT, FRONT + 0.35, F0, F0 + 1.2)
bx(BASE, "Trim", 4.7, OUT + 0.35, FRONT, FRONT + 0.35, F0, F0 + 1.2)

# roof (front overhang) from y = BACK to the front; visible only from outside
roof_run(BASE, "Roof", BACK, FRONT + 1.6)
# front gable: the wall triangle under the roof, front face
prism_x(BASE, "UpWalls", [(-OUT, H2 - 0.2), (OUT, H2 - 0.2), (0.0, PEAK - ROOF_T - 0.05)], 19.0, FRONT)

# ---- BackCap: the removable rear of the base (hidden once the Back Room exists)
cap_wall = BASE.setdefault("_cap_wall", [])
prism_x(BASE, "BackCap", [(-OUT, H2 - 0.2), (OUT, H2 - 0.2), (0.0, PEAK - ROOF_T - 0.05)], BACK, BACK + T)
wall(BASE, "BackCap", "y", BACK, BACK + T, -OUT, OUT, H1, H2, [], battens=0.3, pitch=2.6)       # upper back wall
# the ground back wall is gameplay (opened by PlotService), so only the upper part and gable are in the cap
roof_panel(BASE, "BackCapRoof", -EAVE, H2, 0.0, PEAK, BACK - 1.6, BACK)
roof_panel(BASE, "BackCapRoof", EAVE, H2, 0.0, PEAK, BACK - 1.6, BACK)
bx(BASE, "BackCapRoof", -0.7, 0.7, BACK - 1.6, BACK, PEAK - 0.3, PEAK + 0.45)
BASE.pop("_cap_wall", None)

# ---------------------------------------------------------------- EXTENSION module (Back Room): y from BACK to BACK - EXT_DEPTH
Y1, Y0 = BACK, BACK - EXT_DEPTH
side_runs(EXT, "Up", Y1, Y0, WIN_YS)
wall(EXT, "Walls", "y", Y0, Y0 + T, -OUT, OUT, F0, H1, [(-6.0, 6.0, 4.0, 9.6)], battens=0.3, pitch=2.6)
window(EXT, "Trim", "Glass", "y", Y0, Y0 + T, -6.0, 6.0, 4.0, 9.6, -1)
wall(EXT, "UpWalls", "y", Y0, Y0 + T, -OUT, OUT, H1, H2, [(-9.0, -3.0, 15.4, 20.2), (3.0, 9.0, 15.4, 20.2)], battens=0.3, pitch=2.6)
for (a0, a1) in ((-9.0, -3.0), (3.0, 9.0)):
    window(EXT, "UpTrim", "UpGlass", "y", Y0, Y0 + T, a0, a1, 15.4, 20.2, -1)
for x in (-OUT + 1.0, OUT - 1.0):
    pilaster(EXT, x, Y0, -1)
belt_and_plinth(EXT, Y1, Y0, False, True)
roof_run(EXT, "Roof", Y0 - 1.6, Y1)
prism_x(EXT, "UpWalls", [(-OUT, H2 - 0.2), (OUT, H2 - 0.2), (0.0, PEAK - ROOF_T - 0.05)], Y0, Y0 + T)

# ---------------------------------------------------------------- build meshes
GROUPS_ROOF = {"Roof", "BackCapRoof"}
MESHES = {"base": [], "ext": []}


def build(store, prefix, key):
    for group, parts in store.items():
        verts, faces = [], []
        for (v, f) in parts:
            o = len(verts)
            verts.extend(v)
            faces.extend([tuple(i + o for i in face) for face in f])
        me = bpy.data.meshes.new(f"{prefix}_{group}_mesh")
        me.from_pydata(verts, [], faces)
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(f"{prefix}_{group}", me)
        bpy.context.collection.objects.link(ob)
        MESHES[key].append(ob)


build(BASE, "Shop", "base")
build(EXT, "BackRoom", "ext")

# ---------------------------------------------------------------- materials: plain light-grey surfaces, ONE grey for every tinted slot
SLOT = {"Walls": "Wall", "UpWalls": "Wall", "BackCap": "Wall", "Trim": "Trim", "UpTrim": "Trim", "Accent": "Accent",
        "Glass": "Glass", "UpGlass": "Glass", "Roof": "Roof", "BackCapRoof": "Roof"}
ALBEDO = 0.84     # light grey (a little under white so dark and bright tints both keep their shadows)
MATS = {}


def lin(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def make_mat(slot):
    m = bpy.data.materials.new("U_" + slot)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.8 if slot != "Glass" else 0.15
    MATS[slot] = m
    return m


for slot in ("Wall", "Trim", "Accent", "Glass", "Roof"):
    make_mat(slot)


def set_palette(p):
    """p: dict slot -> hex. Multiplies the colour over the light-grey albedo, like SurfaceAppearance.Color does in Studio."""
    for slot, hexs in p.items():
        r, g, b = (int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4))
        mat = MATS[slot]
        node = mat.node_tree.nodes["Principled BSDF"]
        k = lin(ALBEDO) if slot not in ("Glass", "Roof") else 1.0
        node.inputs["Base Color"].default_value = (lin(r) * k, lin(g) * k, lin(b) * k, 1)
        if slot == "Glass":
            node.inputs["Alpha"].default_value = 0.55


for key in MESHES:
    for ob in MESHES[key]:
        grp = ob.name.split("_", 1)[1]
        ob.data.materials.append(MATS[SLOT[grp]])
        for poly in ob.data.polygons:
            poly.use_smooth = False

tri_base = c.triangle_count(MESHES["base"])
tri_ext = c.triangle_count(MESHES["ext"])
print("SHOPU triangles base", tri_base, "extension", tri_ext, [(o.name, c.triangle_count([o])) for o in MESHES["base"] + MESHES["ext"]])

os.makedirs(c.OUT_MODELS, exist_ok=True)
os.makedirs(c.OUT_PREVIEWS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_Base.glb"), MESHES["base"])
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_BackRoom.glb"), MESHES["ext"])
if os.environ.get("DF_SKIP_RENDER"):
    print("done (no renders)")
    raise SystemExit

# ---------------------------------------------------------------- preview renders: 4 palettes on base + extension, plus base alone
PRESETS = {
    "CapizCream": {"Wall": "EAE3D5", "Floor": "8C6648", "Trim": "593E2B", "Accent": "C98A4B"},
    "MayonAsh": {"Wall": "363940", "Floor": "5E544C", "Trim": "DFD8CC", "Accent": "C86D51"},
    "UbeHalaya": {"Wall": "CFC3DC", "Floor": "B89B7E", "Trim": "F5F1EB", "Accent": "7E5A8C"},
    "SantanSunset": {"Wall": "C95B4B", "Floor": "6E5644", "Trim": "F4EDE2", "Accent": "2F5D62"},
}
FIXED = {"Glass": "A9C2CF", "Roof": "5A544E"}

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 28
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1100, 760
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
sky = world.node_tree.nodes.new("ShaderNodeTexSky")
world.node_tree.links.new(sky.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
scene.world = world
sd = bpy.data.lights.new("Sun", "SUN")
sd.energy = 4.0
sd.color = (1.0, 0.9, 0.78)
sd.angle = math.radians(4)
so = bpy.data.objects.new("Sun", sd)
bpy.context.collection.objects.link(so)
so.rotation_euler = (math.radians(52), 0, math.radians(215))

# ground: a street apron and the plot floor (the floor slab uses the Floor slot colour)
gm_mat = bpy.data.materials.new("ground_mat")
gm_mat.use_nodes = True
gm_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.40, 0.36, 1)
fl_mat = bpy.data.materials.new("floor_mat")
fl_mat.use_nodes = True


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


slab("street", -90, 90, -90, 90, -0.4, 0.0, gm_mat)
floor_base = slab("floor_base", -OUT, OUT, BACK, FRONT, 0.0, F0, fl_mat)
floor_ext = slab("floor_ext", -OUT, OUT, BACK - EXT_DEPTH, BACK, 0.0, F0, fl_mat)

cam = bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam"))
bpy.context.collection.objects.link(cam)
scene.camera = cam


def shoot(path, loc, target, lens=32):
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def show(ext_on, cap_on):
    for ob in MESHES["ext"]:
        ob.hide_render = not ext_on
    floor_ext.hide_render = not ext_on
    for ob in MESHES["base"]:
        if ob.name in ("Shop_BackCap", "Shop_BackCapRoof"):
            ob.hide_render = not cap_on


for name, pal in PRESETS.items():
    set_palette({k: v for k, v in pal.items() if k != "Floor"})
    set_palette(FIXED)
    r, g, b = (int(pal["Floor"][i:i + 2], 16) / 255 for i in (0, 2, 4))
    fl_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (lin(r), lin(g), lin(b), 1)
    show(True, False)
    shoot(os.path.join(c.OUT_PREVIEWS, f"ShopU_{name}_extended.png"), (62, 78, 42), (0, -8, 10))
    if name == "CapizCream":
        show(False, True)
        shoot(os.path.join(c.OUT_PREVIEWS, f"ShopU_{name}_base.png"), (56, 66, 40), (0, 0, 11))
        shoot(os.path.join(c.OUT_PREVIEWS, f"ShopU_{name}_back.png"), (-52, -60, 36), (0, 0, 11))
        show(True, False)
        shoot(os.path.join(c.OUT_PREVIEWS, f"ShopU_{name}_front.png"), (-8, 62, 14), (0, 20, 8), 30)
print("done")
