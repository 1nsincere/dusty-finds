"""Shared building blocks for the decor sets (Blender 5.x, headless): soft rounded shapes, rods, lathes, the colour-slot convention and a
room preview. Used by decor_kitchen.py (and later sets). decor_cozy_v2.py has its own copy of these helpers (kept as it was).

SHOP-FIT SLOTS: parts named <Piece>_Accent take the shop's ACCENT paint, <Piece>_Trim its TRIM paint (the game recolours them); every
other part keeps a natural fixed material. <Piece>_Glow parts are meant to light up. 1 unit = 1 stud, Z up, +Y = the front of a piece.
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




def part_color(group, scheme, natural, schemes):
    part = group.split("_", 1)[1]
    if part in ("Accent", "Trim"):
        return schemes[scheme][part]
    return natural.get(part, "CCCCCC")


def make_objects(scheme, natural, schemes):
    objs = []
    for group, parts in G.items():
        verts, faces = [], []
        for (v, f) in parts:
            o = len(verts)
            verts.extend(v)
            faces.extend([tuple(i + o for i in face) for face in f])
        me = bpy.data.meshes.new(group + "_mesh")
        me.from_pydata(verts, [], faces)
        me.update()
        ob = bpy.data.objects.new(group, me)
        bpy.context.collection.objects.link(ob)
        key = "dx_" + group.lower()
        c.PALETTE[key] = part_color(group, scheme, natural, schemes)
        mat = c.material(group + "_mat", key)
        if group.endswith("_Glass"):
            mat.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value = 0.35 # see-through jars in the preview (Studio: Glass material)
        if group.endswith("_Glow"):
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Emission Color"].default_value = c.hex_to_rgba(natural.get("Glow", "FFD98A"))
            bsdf.inputs["Emission Strength"].default_value = 2.2
        ob.data.materials.append(mat)
        objs.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth()
    return objs


def render_room(out_path, wall_hex, floor_hex, cam_loc, cam_look, width=1600, height=900, samples=40):
    """A shop-like room (floor planks, back wall with windows, a side wall) lit warmly, then one render from cam_loc looking at cam_look."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.82, 0.7, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world

    def slab(name, size, loc, hexcol, rough=0.8):
        ob = c.box(name, size, loc)
        m = bpy.data.materials.new(name + "m")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = c.hex_to_rgba(hexcol)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = rough
        ob.data.materials.append(m)
        return ob

    slab("floor", (34, 24, 0.3), (0, 2, -0.15), floor_hex, 0.6)
    for k in range(9):
        slab("plank%d" % k, (34, 0.05, 0.02), (0, -9 + k * 2.6, 0.01), "5A3B26", 0.7)
    slab("wall", (34, 0.5, 14), (0, -7.0, 7.0), wall_hex)
    slab("sidewall", (0.5, 24, 14), (-14.5, 2, 7.0), wall_hex)
    slab("baseboard", (34, 0.6, 0.7), (0, -6.6, 0.35), "7A4A2E", 0.5)
    for k, hx in enumerate((-3, 4, 11)):
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
    cam.location = cam_loc
    cam.rotation_euler = (mathutils.Vector(cam_look) - mathutils.Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
