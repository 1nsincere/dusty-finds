"""Floral Teacup (item id Teacup): lathed cup + saucer, gold trim, little flowers. Pilot for the Blender pipeline.
Run: "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/teacup.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from common import *  # noqa: E402,F401,F403

reset_scene()

# --- cup body: (radius, height) from the bottom centre, up the outside, over the rim, down the inside ---
cup = lathe(
    "Body",
    [(0.0, 0.0), (0.26, 0.0), (0.30, 0.06), (0.50, 0.30), (0.60, 0.62), (0.63, 0.80), (0.58, 0.80), (0.54, 0.62), (0.44, 0.30), (0.26, 0.17), (0.0, 0.17)],
    steps=36,
)
cup.location = (0, 0, 0.09)
finish(cup, "Body", "cream", bevel=0.01, subsurf=1)

saucer = lathe("Saucer", [(0.0, 0.0), (0.34, 0.0), (0.88, 0.07), (0.92, 0.09), (0.86, 0.11), (0.40, 0.06), (0.0, 0.06)], steps=40)
finish(saucer, "Saucer", "cream", bevel=0.01, subsurf=1)

# gold rim on the cup and the saucer edge
rim = torus("Rim", 0.605, 0.028, location=(0, 0, 0.09 + 0.80), major_seg=36, minor_seg=8)
finish(rim, "Rim", "mustard", subsurf=0)
trim = torus("Trim", 0.89, 0.026, location=(0, 0, 0.10), major_seg=40, minor_seg=8)
finish(trim, "Trim", "mustard", subsurf=0)

# handle: a vertical ring on the right side
handle = torus("Handle", 0.19, 0.045, location=(0.66, 0, 0.52), rotation=(math.pi / 2, 0, 0), major_seg=20, minor_seg=8)
finish(handle, "Handle", "cream", subsurf=0)

# floral decoration: five flowers and leaves around the belly
flowers, leaves = [], []
for i in range(5):
    a = i * 2 * math.pi / 5 + 0.3
    r, z = 0.545, 0.44
    x, y = math.cos(a) * r, math.sin(a) * r
    flowers.append(sphere(f"f{i}", 0.07, location=(x, y, z), scale=(1.0, 1.0, 0.55), segments=10, rings=6))
    flowers[-1].rotation_euler = (0, 0, a)
    leaves.append(sphere(f"l{i}", 0.06, location=(math.cos(a + 0.35) * 0.55, math.sin(a + 0.35) * 0.55, 0.36), scale=(1.4, 0.7, 0.5), segments=8, rings=6))
flower = join(flowers, "Flower")
finish(flower, "Flower", "terracotta", subsurf=0)
leaf = join(leaves, "Leaf")
finish(leaf, "Leaf", "sage", subsurf=0)

parts = [cup, saucer, rim, trim, handle, flower, leaf]
print("TRIANGLES", triangle_count(parts))
preview(os.path.join(OUT_PREVIEWS, "Teacup.png"), parts, distance=3.6, height=1.7, look_z=0.45)
export_glb(os.path.join(OUT_MODELS, "Teacup.glb"), parts)
print("DONE Teacup")
