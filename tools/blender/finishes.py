"""Premium finish textures (Robux Premium tab, docs/12): NEUTRAL light textures with relief, saved as PNG so they can be uploaded as Image
assets. A premium paint is a tint over one of these (Config.Finishes holds the uploaded asset ids). Blender 5.x, headless.

Run:  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/finishes.py
Writes assets/textures/finishes/<key>_color.png and <key>_normal.png (512 x 512, seamless; 1 tile = 8 studs on the shell).
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402
import textures as tx  # noqa: E402

c.reset_scene()
OUT = os.path.join(c.ROOT, "assets", "textures", "finishes")
os.makedirs(OUT, exist_ok=True)
for key in ("pearl", "velvet", "brass", "goldleaf", "marblewall"):
    color, normal = tx.make(key)
    for img, suffix in ((color, "color"), (normal, "normal")):
        img.filepath_raw = os.path.join(OUT, f"{key}_{suffix}.png")
        img.file_format = "PNG"
        img.save()
    print("wrote", key)
print("done")

# ---- a small model that CARRIES the finishes: the upload pipeline (Open Cloud Model upload from assets/models) turns the embedded images
# into image assets, and Studio's SurfaceAppearance on each mesh then gives us their ids for Config.Finishes. Five flat quads, one per finish.
import bmesh  # noqa: E402

objs = []
for i, key in enumerate(("pearl", "velvet", "brass", "goldleaf", "marblewall")):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            loop[layer].uv = (loop.vert.co.x + 0.5, loop.vert.co.y + 0.5)
    me = bpy.data.meshes.new(f"Finish_{key}_mesh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"Finish_{key}", me)
    ob.location = (i * 2.5, 0, 0)
    bpy.context.collection.objects.link(ob)
    tx.apply(ob, key, name=f"Finish_{key}_mat")
    objs.append(ob)
os.makedirs(c.OUT_MODELS, exist_ok=True)
c.export_glb(os.path.join(c.OUT_MODELS, "ShopU_Finishes.glb"), objs)
print("exported ShopU_Finishes.glb")
