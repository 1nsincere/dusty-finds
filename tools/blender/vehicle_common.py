"""Shared pipeline for the Dusty Finds vehicles (jeepney, tricycle). Blender 5.x, run headless:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P tools/blender/jeepney.py

What it does, in order (each vehicle script calls these):
  1. build the model from simple parts, each part with a procedural material (stainless, paint, chrome, rubber...)
  2. join the parts into a few export objects (Body, Chrome, Wheels, Signs): one Roblox MeshPart each
  3. smart-UV each export object and BAKE its materials into 1024x1024 colour / normal / roughness / metalness maps
     (for a SurfaceAppearance in Studio)
  4. render a separate sharp sign-text atlas (our own text only) that the Signs object is UV-mapped onto
  5. export assets/<vehicle>/<vehicle>.fbx (+ textures/) and render 3 previews to assets/<vehicle>/previews/

Axes: 1 Blender unit = 1 stud. Blender Z is up, the vehicle's FRONT points to Blender -Y, its right side to +X.
The FBX is written with axis_up = Y and axis_forward = -Z, so in Roblox: up = +Y, front = -Z (a Model's default LookVector).
Wheels touch Blender Z = 0, so they touch Y = 0 in Roblox.
"""

import math
import os

import bmesh
import bpy
import mathutils

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hexstr):
    return tuple(lin(int(hexstr[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


# ---------------------------------------------------------------- geometry helpers
def _active():
    return bpy.context.active_object


def box(name, size, loc, mat=None, bevel=0.0, segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = _active()
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = segments
        m.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=m.name)
    if mat:
        o.data.materials.append(mat)
    return o


def cylinder(name, radius, depth, loc, axis="X", mat=None, verts=20):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = _active()
    o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    if mat:
        o.data.materials.append(mat)
    return o


def sphere(name, radius, loc, scale=(1, 1, 1), mat=None, seg=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=seg, ring_count=rings)
    o = _active()
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        o.data.materials.append(mat)
    return o


def arch(name, radius, thickness, width, loc, mat=None, segs=14, start=0.0, end=math.pi):
    """A curved fender / canopy strip: a thick half-ring around the X axis (wheel arch), open at the bottom."""
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    rings = []
    for i in range(segs + 1):
        a = start + (end - start) * i / segs
        ring = []
        for r in (radius, radius + thickness):
            for x in (-width / 2, width / 2):
                ring.append(bm.verts.new((x, math.cos(a) * r, math.sin(a) * r)))
        rings.append(ring)
    for i in range(segs):
        a, b = rings[i], rings[i + 1]
        # ring order: (inner,-x) (inner,+x) (outer,-x) (outer,+x)
        bm.faces.new((a[2], a[3], b[3], b[2]))  # outer
        bm.faces.new((a[1], a[0], b[0], b[1]))  # inner
        bm.faces.new((a[0], a[2], b[2], b[0]))  # -x side
        bm.faces.new((a[3], a[1], b[1], b[3]))  # +x side
    bm.faces.new((rings[0][0], rings[0][1], rings[0][3], rings[0][2]))
    bm.faces.new((rings[-1][2], rings[-1][3], rings[-1][1], rings[-1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o.location = loc
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    o.select_set(False)
    if mat:
        me.materials.append(mat)
    return o


def tube(name, points, radius, mat=None, res=8):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    cu.use_fill_caps = True
    cu.resolution_u = 4
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        sp.points[i].co = (p[0], p[1], p[2], 1)
    o = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = _active()
    o.select_set(False)
    if mat:
        o.data.materials.clear()
        o.data.materials.append(mat)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = _active()
    o.name = name
    o.data.name = name + "_mesh"
    # smooth the curved parts (fenders, roof shoulders, wheels), keep box edges crisp
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    except Exception:
        bpy.ops.object.shade_flat()
    o.select_set(False)
    return o


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


# ---------------------------------------------------------------- procedural materials
def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    return m, nt, bsdf


def paint(name, color, rough=0.45, metal=0.0):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def stainless(name, ribs=True, scale=6.0):
    """Polished/brushed stainless steel; ribs = embossed horizontal panel ribbing (bump only)."""
    m, nt, b = _mat(name)
    b.inputs["Metallic"].default_value = 1.0
    # base colour: bright steel that gets a little grimier toward the bottom (road dust), with faint blotches
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 1.2
    mr.inputs["From Max"].default_value = 5.5
    grime = nt.nodes.new("ShaderNodeTexNoise")
    grime.inputs["Scale"].default_value = 3.0
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = rgb("8C9096")
    ramp.color_ramp.elements[1].color = rgb("D3D7DB")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], mix.inputs[0])
    nt.links.new(grime.outputs["Fac"], mix.inputs[1])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    add.inputs[1].default_value = 0.35
    nt.links.new(mix.outputs["Value"], add.inputs[0])
    nt.links.new(add.outputs["Value"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    # brushed look: stretched noise drives roughness 0.18..0.34
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (40.0, 1.0, 1.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 8.0
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].color = (0.18, 0.18, 0.18, 1)
    cr.color_ramp.elements[1].color = (0.34, 0.34, 0.34, 1)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Roughness"])
    if ribs:
        wv = nt.nodes.new("ShaderNodeTexWave")
        wv.wave_type = "BANDS"
        wv.bands_direction = "Z"
        wv.inputs["Scale"].default_value = scale
        wv.inputs["Distortion"].default_value = 0.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.35
        nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
        nt.links.new(wv.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def chrome(name):
    return paint(name, rgb("E8ECEF"), rough=0.08, metal=1.0)


def rubber(name):
    m, nt, b = _mat(name)
    b.inputs["Base Color"].default_value = rgb("1E1F22")
    b.inputs["Roughness"].default_value = 0.85
    # tread grooves around the tyre (bump)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = "RINGS"
    wv.inputs["Scale"].default_value = 3.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    nt.links.new(wv.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def striped_paint(name, base, stripe, scale=1.2, direction="Z"):
    """Bright paint with bold stripes (tricycle sidecar art)."""
    m, nt, b = _mat(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.wave_type = "BANDS"
    wv.bands_direction = direction
    wv.inputs["Scale"].default_value = scale
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.interpolation = "CONSTANT"
    cr.color_ramp.elements[0].position = 0.0
    cr.color_ramp.elements[0].color = base
    cr.color_ramp.elements[1].position = 0.72
    cr.color_ramp.elements[1].color = stripe
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    nt.links.new(wv.outputs["Fac"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.35
    return m


# ---------------------------------------------------------------- UV + bake
def smart_uv(o):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")
    o.select_set(False)


def _new_image(name, size, data):
    img = bpy.data.images.new(name, size, size, alpha=False, is_data=data)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def _set_targets(o, img):
    for slot in o.material_slots:
        nt = slot.material.node_tree
        node = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
        node.name = "BakeTarget"
        node.image = img
        nt.nodes.active = node


def _select_only(o):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def bake_maps(o, out_dir, prefix, size=1024, color_only=False):
    """Bake the object's materials into colour / normal / roughness / metalness PNGs. Returns {kind: path}."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    os.makedirs(out_dir, exist_ok=True)
    _select_only(o)
    paths = {}
    kinds = [("color", False)] if color_only else [("color", False), ("normal", True), ("roughness", True), ("metalness", True)]
    for kind, data in kinds:
        img = _new_image(f"{prefix}_{kind}", size, data)
        _set_targets(o, img)
        if kind == "normal":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=8, use_clear=True)
        elif kind == "roughness":
            bpy.ops.object.bake(type="ROUGHNESS", margin=8, use_clear=True)
        else:
            # colour and metalness: route the BSDF input straight into an Emission shader and bake EMIT.
            # (Cycles' diffuse-colour pass is black on metals, so it cannot be used for the stainless body.)
            input_name = "Base Color" if kind == "color" else "Metallic"
            saved = []
            for slot in o.material_slots:
                nt = slot.material.node_tree
                bsdf = nt.nodes.get("Principled BSDF")
                out = nt.nodes.get("Material Output")
                em = nt.nodes.new("ShaderNodeEmission")
                em.name = "BakeEmit"
                inp = bsdf.inputs[input_name]
                if inp.is_linked:
                    nt.links.new(inp.links[0].from_socket, em.inputs["Color"])
                else:
                    v = inp.default_value
                    em.inputs["Color"].default_value = tuple(v) if kind == "color" else (v, v, v, 1)
                old = out.inputs["Surface"].links[0].from_socket
                nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
                saved.append((nt, old, out, em))
            bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
            for nt, old, out, em in saved:
                nt.links.new(old, out.inputs["Surface"])
                nt.nodes.remove(em)
        path = os.path.join(out_dir, f"{prefix}_{kind}.png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        paths[kind] = path
    o.select_set(False)
    return paths


def baked_material(name, maps):
    """A single material using the baked maps (what the preview shows and the FBX references)."""
    m, nt, b = _mat(name)

    def tex(path, data):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=True)
        if data:
            n.image.colorspace_settings.name = "Non-Color"
        return n

    c = tex(maps["color"], False)
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    if "normal" in maps:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex(maps["normal"], True).outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        nt.links.new(tex(maps["roughness"], True).outputs["Color"], b.inputs["Roughness"])
        nt.links.new(tex(maps["metalness"], True).outputs["Color"], b.inputs["Metallic"])
    return m


def swap_material(o, mat):
    o.data.materials.clear()
    o.data.materials.append(mat)


# ---------------------------------------------------------------- sign-text atlas (sharp, separate texture)
ATLAS_W, ATLAS_H, ROWS = 2048, 1024, 8  # 8 rows of 2048x128 px (16:1 each)


def sign_atlas(path, rows):
    """rows = [(row_index, width_fraction, text, bg_hex, fg_hex), ...]. Renders a flat atlas PNG with Workbench.
    Each entry fills the left part of its row: width_fraction of 2048 px x 128 px. Returns {row_index: uv_rect}."""
    # rendered in the current (empty) scene, then everything it made is deleted again; call it before building
    scene = bpy.context.scene
    before = set(bpy.data.objects)
    W, H = ATLAS_W / 64, ATLAS_H / 64  # 1 unit = 64 px -> 32 x 16 units, each row 2 units tall
    rh = H / ROWS
    coll = scene.collection
    uv = {}

    def flat(hexstr):
        m = bpy.data.materials.new("sign_" + hexstr)
        m.diffuse_color = rgb(hexstr)
        return m

    bg_all = bpy.data.meshes.new("atlas_bg")
    bgo = bpy.data.objects.new("atlas_bg", bg_all)
    coll.objects.link(bgo)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    bm.to_mesh(bg_all)
    bm.free()
    bgo.scale = (W, H, 1)
    bgo.location = (W / 2, H / 2, -0.1)
    bg_all.materials.append(flat("777777"))
    for entry in rows:
        # (row, width_fraction, text, bg, fg[, nrows[, x0_fraction]]): multi-line boards span several rows
        row, frac, text, bg, fg = entry[:5]
        nrows = entry[5] if len(entry) > 5 else 1
        x0 = (entry[6] if len(entry) > 6 else 0.0) * W
        w = W * frac
        y0 = H - (row + nrows) * rh
        rh_e = rh * nrows
        me = bpy.data.meshes.new(f"bg{row}")
        ob = bpy.data.objects.new(f"bg{row}", me)
        coll.objects.link(ob)
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
        bm.to_mesh(me)
        bm.free()
        ob.scale = (w, rh_e, 1)
        ob.location = (x0 + w / 2, y0 + rh_e / 2, 0)
        me.materials.append(flat(bg))
        cu = bpy.data.curves.new(f"txt{row}", "FONT")
        cu.body = text
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.size = 1.0
        cu.offset_y = 0
        to = bpy.data.objects.new(f"txt{row}", cu)
        coll.objects.link(to)
        cu.materials.append(flat(fg))
        # bold look: a thin outline offset in the text colour
        cu.offset = 0.035
        bpy.context.view_layer.update()
        # fit the text inside the board with a margin
        dims = to.dimensions if to.dimensions.x > 0 else mathutils.Vector((len(text) * 0.6, 0.8, 0))
        s = min((w * 0.9) / max(dims.x, 0.01), (rh_e * 0.8) / max(dims.y, 0.01))
        to.scale = (s, s, 1)
        to.location = (x0 + w / 2, y0 + rh_e / 2, 0.05)
        key = row if x0 == 0 else (row, round(x0 / W, 3))
        uv[key] = (x0 / W, y0 / H, x0 / W + frac, (y0 + rh_e) / H)
    cam = bpy.data.objects.new("atlas_cam", bpy.data.cameras.new("atlas_cam"))
    coll.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = W
    cam.location = (W / 2, H / 2, 10)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = ATLAS_W
    scene.render.resolution_y = ATLAS_H
    scene.render.film_transparent = False
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    for o in list(set(bpy.data.objects) - before):
        bpy.data.objects.remove(o, do_unlink=True)
    return uv


def sign_quad(name, center, width, height, facing, uv_rect, push=0.03):
    """A flat sign board facing +X/-X/+Y/-Y, UV-mapped to uv_rect = (u0, v0, u1, v1) of the atlas.
    The u range is trimmed to the board's own aspect so text is never stretched."""
    u0, v0, u1, v1 = uv_rect
    cx, cy, cz = center
    hw, hh = width / 2, height / 2
    if facing in ("+X", "-X"):
        s = 1 if facing == "+X" else -1
        x = cx + s * push
        # viewer looking at the face sees +Y on their left for +X facing... order corners so text reads left-to-right
        pts = [(x, cy + s * hw, cz - hh), (x, cy - s * hw, cz - hh), (x, cy - s * hw, cz + hh), (x, cy + s * hw, cz + hh)]
    else:
        s = 1 if facing == "+Y" else -1
        y = cy + s * push
        pts = [(cx - s * hw, y, cz - hh), (cx + s * hw, y, cz - hh), (cx + s * hw, y, cz + hh), (cx - s * hw, y, cz + hh)]
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    uvl = bm.loops.layers.uv.new("UVMap")
    for loop, uvc in zip(f.loops, [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]):  # u runs right-to-left over these corners so text reads correctly
        loop[uvl].uv = uvc
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    return o


def sign_material(name, atlas_path):
    m, nt, b = _mat(name)
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(atlas_path, check_existing=True)
    n.interpolation = "Closest"
    nt.links.new(n.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.5
    return m


# ---------------------------------------------------------------- export + previews
def export_fbx(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        mesh_smooth_type="FACE",
        path_mode="RELATIVE",
        embed_textures=False,
    )


def previews(out_dir, name, size_hint, look_z, views):
    """Cycles CPU renders from the given views: [(file_suffix, (x, y, z) camera position)]."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.84, 0.92, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    fl = bpy.data.meshes.new("floor")
    fo = bpy.data.objects.new("floor", fl)
    scene.collection.objects.link(fo)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size_hint * 3)
    bm.to_mesh(fl)
    bm.free()
    fm = paint("floormat", (0.55, 0.52, 0.48, 1), rough=0.9)
    fl.materials.append(fm)
    for loc, energy, sz in [((size_hint, -size_hint * 1.4, size_hint * 1.6), 3000, size_hint), ((-size_hint * 1.4, size_hint * 0.4, size_hint), 1200, size_hint)]:
        ld = bpy.data.lights.new("L", "AREA")
        ld.energy = energy
        ld.size = sz
        lo = bpy.data.objects.new("L", ld)
        scene.collection.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (mathutils.Vector((0, 0, look_z)) - lo.location).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.data.lens = 40
    scene.camera = cam
    out = []
    for suffix, pos in views:
        cam.location = pos
        cam.rotation_euler = (mathutils.Vector((0, 0, look_z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(out_dir, f"{name}_{suffix}.png")
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        out.append(p)
    return out
