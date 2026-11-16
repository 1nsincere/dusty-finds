"""The Brass Baron Kettle (item id CopperKettle), HIGH QUALITY pilot: smooth lathed body, tapered Bezier spout, arched handle,
domed lid, brass bands and rivets. Target: well under 8,000 triangles.
Run: "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/kettle_hq.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from common import *  # noqa: E402,F401,F403

reset_scene()

# body: base ring, flared belly, soft shoulder, neck with a rolled lip (radius, height)
body = lathe(
    "Body",
    [(0.0, 0.0), (0.50, 0.0), (0.56, 0.03), (0.74, 0.20), (0.84, 0.42), (0.82, 0.64), (0.68, 0.84), (0.50, 0.97), (0.40, 1.03), (0.40, 1.10), (0.34, 1.10), (0.34, 1.0), (0.0, 1.0)],
    steps=44,
)
finish(body, "Body", "terracotta", subsurf=1)
metal_material(body, "terracotta", 0.9, 0.32)

lid = lathe("Lid", [(0.0, 1.16), (0.12, 1.15), (0.30, 1.10), (0.42, 1.04), (0.43, 1.0), (0.36, 1.0), (0.0, 1.0)], steps=36)
lid.location = (0, 0, 0.1)
finish(lid, "Lid", "mustard", subsurf=1)
metal_material(lid, "mustard", 0.9, 0.28)

knob = sphere("Knob", 0.085, location=(0, 0, 1.33), scale=(1, 1, 1.2), segments=16, rings=10)
finish(knob, "Knob", "black", subsurf=0)

# brass bands around the belly and the base
band1 = torus("BandMid", 0.835, 0.03, location=(0, 0, 0.45), major_seg=48, minor_seg=8)
finish(band1, "BandMid", "mustard", subsurf=0)
metal_material(band1, "mustard", 0.9, 0.3)
band2 = torus("BandBase", 0.57, 0.028, location=(0, 0, 0.04), major_seg=40, minor_seg=8)
finish(band2, "BandBase", "mustard", subsurf=0)
metal_material(band2, "mustard", 0.9, 0.3)

# spout: tapered curved tube leaving the belly on the +X side
spout = tube(
    "Spout",
    [(0.62, 0, 0.30), (0.95, 0, 0.42), (1.18, 0, 0.72), (1.34, 0, 1.00)],
    [1.35, 1.0, 0.75, 0.55],
    bevel=0.12,
    resolution=16,
)
finish(spout, "Spout", "terracotta", subsurf=0)
metal_material(spout, "terracotta", 0.9, 0.32)

# arched handle over the lid with two dark grips
handle = tube("Handle", [(-0.62, 0, 0.78), (-0.78, 0, 1.18), (-0.38, 0, 1.62), (0.0, 0, 1.70), (0.38, 0, 1.62), (0.78, 0, 1.18), (0.62, 0, 0.78)], [1, 1, 1, 1, 1, 1, 1], bevel=0.055, resolution=14)
finish(handle, "Handle", "black", subsurf=0)

# rivets where the handle meets the body
rivets = [sphere(f"r{i}", 0.05, location=(x, 0, 0.78), segments=10, rings=6) for i, x in enumerate((-0.64, 0.64))]
rivet = join(rivets, "Rivet")
finish(rivet, "Rivet", "mustard", subsurf=0)

parts = [body, lid, knob, band1, band2, spout, handle, rivet]
print("TRIANGLES", triangle_count(parts))
os.makedirs(OUT_PREVIEWS, exist_ok=True)
preview_cycles(os.path.join(OUT_PREVIEWS, "Kettle_HQ.png"), distance=5.0, height=2.0, look_z=0.75, samples=40)
export_glb(os.path.join(OUT_MODELS, "Kettle_HQ.glb"), parts)
print("DONE Kettle HQ")
