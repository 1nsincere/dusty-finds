"""Shared helpers for the Dusty Finds item models (Blender 5.x, run headless).

Run an item script like this (nothing opens, no window):
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/teacup.py

Rules (docs/Item_Model_Contract_DRAFT.md + docs/Environment_Art.md):
- 1 Blender unit = 1 stud. The finished item fits about 1.8 studs wide (the Rubber Duck is about 1.65).
- Z is up in Blender; the glTF exporter converts to Roblox's Y-up.
- Every colour group is its OWN object (Body, Rim, Handle...). Roblox gets one MeshPart per object and the Studio wrapper
  (tools/studio) sets Color and Material by object name from the palette below, so no textures are needed.
- Smooth, softly bevelled shapes, low triangle count (target under 1,500 per item, hard limit 20,000).
"""

import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_MODELS = os.path.join(ROOT, "assets", "models")
OUT_PREVIEWS = os.path.join(ROOT, "assets", "previews")

# The game palette (docs/Environment_Art.md). Roblox colours are set in Studio by name; these are for the preview render.
PALETTE = {
    "cream": "F4F0E8",
    "oak": "D8B98A",
    "black": "22252B",
    "grey": "9AA0A6",
    "teal": "1F7A7A",
    "terracotta": "D2694A",
    "mustard": "E3B23C",
    "plum": "6E4A7E",
    "sage": "7FA37C",
    "navy": "2E4A7D",
    "warm": "FFE9B0",
}


def hex_to_rgba(hexstr: str):
    r, g, b = (int(hexstr[i : i + 2], 16) / 255.0 for i in (0, 2, 4))

    def lin(c):  # sRGB -> linear for Blender
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b), 1.0)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str, color_name: str):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = hex_to_rgba(PALETTE[color_name])
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = hex_to_rgba(PALETTE[color_name])
        bsdf.inputs["Roughness"].default_value = 0.6
    return mat


def finish(obj, name: str, color_name: str, bevel: float = 0.0, subsurf: int = 0, smooth: bool = True):
    """Name, colour, bevel, smooth-shade and apply modifiers so the exported mesh is plain geometry."""
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.data.materials.clear()
    obj.data.materials.append(material(name + "_mat", color_name))
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    if subsurf > 0:
        mod = obj.modifiers.new("Subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


def lathe(name: str, profile, steps: int = 32, closed_axis: bool = True):
    """Solid of revolution around Z. profile = [(radius, height), ...] from the bottom centre outward and up."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=steps)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return obj


def torus(name: str, major: float, minor: float, location=(0, 0, 0), rotation=(0, 0, 0), major_seg=24, minor_seg=8):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor, major_segments=major_seg, minor_segments=minor_seg, location=location, rotation=rotation
    )
    obj = bpy.context.active_object
    obj.name = name
    return obj


def sphere(name: str, radius: float, location=(0, 0, 0), scale=(1, 1, 1), segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=segments, ring_count=rings)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    obj.name = name
    return obj


def box(name: str, size, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    obj.name = name
    return obj


def join(objs, name: str):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.select_set(False)
    return obj


def triangle_count(objs) -> int:
    total = 0
    for o in objs:
        me = o.data
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
    return total


def preview(path: str, objs, distance: float = 4.0, height: float = 1.8, look_z: float = 0.45):
    """Workbench render (works without a GPU): flat shaded in the item colours, from the front-above."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.color = (0.82, 0.86, 0.9)
    scene.world = world
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (distance * 0.55, -distance, height)
    import mathutils

    direction = mathutils.Vector((0, 0, look_z)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def export_glb(path: str, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
