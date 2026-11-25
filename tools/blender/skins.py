"""Dusty Finds: shelf, pedestal and cashier skins (Blender 5.x, headless). Built from Sean's design sheets (assets/skin-designs).

Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/skins.py
Env:
  DF_SKINS        comma list of skin ids to build (default: all)
  DF_PREVIEW_DIR  where preview PNGs go (default assets/previews/skins)
  DF_EXPORT=1     also export assets/models/Skins.glb (the selected skins)
  DF_KEEP=path    save the built scene as a .blend (to open and tweak by hand)

Rules (docs/10, Studio contract): 1 Blender unit = 1 stud. Origin = bottom centre, front faces -Y, Z up.
  Shelf    11.2 (X) x 4.2 (Y) x 4.2 (Z)      Pedestal 2.8 x 2.8 x 4.2
  Cashier  8.04 x 2.51, counter top at 3.13, register to 4.2 (scaled in game to each shop's counter)
  The top is flat at exactly Z = 4.2 (items sit there); nothing sticks out more than 0.15 past the footprint.
One object per material per skin, named <SkinId>_<Part>: Body / Dark / Brass / Trim / Glow ... (Glow -> Neon in Roblox).
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

TOP = 4.2


# ===== helpers =====

def hexmat(name: str, hexstr: str, emission: float = 0.0, metallic: float = 0.0, roughness: float = 0.6):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    rgba = c.hex_to_rgba(hexstr)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission > 0:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission
    return mat


class Skin:
    """Collects boxes per material and joins each group into one object."""

    def __init__(self, skin_id: str):
        self.id = skin_id
        self.groups = {}  # part -> [objects]
        self.mats = {}

    def mat(self, part: str, hexstr: str, **kw):
        self.mats[part] = (hexstr, kw)

    def box(self, part: str, size, center, rot_z: float = 0.0, rot_y: float = 0.0, rot_x: float = 0.0):
        o = c.box(f"{self.id}_{part}", size, center)
        if rot_x or rot_y or rot_z:
            o.rotation_euler = (rot_x, rot_y, rot_z)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        self.groups.setdefault(part, []).append(o)
        return o

    def add(self, part: str, obj):
        self.groups.setdefault(part, []).append(obj)
        return obj

    def build(self):
        out = []
        for part, objs in self.groups.items():
            obj = c.join(objs, f"{self.id}_{part}") if len(objs) > 1 else objs[0]
            obj.name = f"{self.id}_{part}"
            obj.data.name = obj.name + "_mesh"
            hexstr, kw = self.mats[part]
            obj.data.materials.clear()
            obj.data.materials.append(hexmat(f"{self.id}_{part}_mat", hexstr, **kw))
            out.append(obj)
        return out


def rune_band(s: Skin, part: str, x0: float, x1: float, y: float, z: float, height: float = 0.26, face: str = "front"):
    """A row of small glyph blocks along a face (front: -Y side at y; side: x fixed = y argument, running along Y)."""
    n = max(3, int((x1 - x0) / 0.34))
    step = (x1 - x0) / n
    for i in range(n):
        t = x0 + step * (i + 0.5)
        h = height * (0.7 + 0.3 * ((i * 7) % 3) / 2)
        w = step * 0.45
        if face == "front":
            s.box(part, (w, 0.04, h), (t, y, z))
            if i % 2 == 0:  # a small crossbar so it reads as a glyph, not a dash
                s.box(part, (step * 0.55, 0.04, 0.05), (t, y, z + h * 0.15))
        else:
            s.box(part, (0.04, w, h), (y, t, z))
            if i % 2 == 0:
                s.box(part, (0.04, step * 0.55, 0.05), (y, t, z + h * 0.15))


# ===== RUNIC ANTIQUE (Relic) =====

SLATE, SHADOW, BRASS, RUNE = "4A4552", "312D3A", "E3B23C", "8E6CEF"


def shelf_runic():
    s = Skin("ShelfRunic")
    s.mat("Body", SLATE, roughness=0.85)
    s.mat("Dark", SHADOW, roughness=0.9)
    s.mat("Brass", BRASS, metallic=0.9, roughness=0.35)
    s.mat("Glow", RUNE, emission=3.0)
    L, D = 11.2, 4.2
    # plinth, body, slab
    s.box("Dark", (L, D, 0.45), (0, 0, 0.225))
    s.box("Brass", (L - 0.2, D - 0.2, 0.08), (0, 0, 0.49))
    s.box("Body", (L - 0.4, D - 0.4, 3.07), (0, 0, 0.53 + 3.07 / 2))
    s.box("Brass", (L - 0.2, D - 0.2, 0.08), (0, 0, 3.64))
    s.box("Body", (L, D, 0.51), (0, 0, 3.68 + 0.51 / 2))
    # top: three flush shadow-stone squares where the items stand (top stays exactly 4.2)
    for x in (-3.5, 0.0, 3.5):
        s.box("Dark", (2.6, 2.6, 0.01), (x, 0, TOP - 0.005))
    # long faces: three framed panels with aged-brass pilasters between them (Sean's spec, 2026-11-24);
    # the front (-Y) corner pillars carry a column of small inlaid crystal dots (glow)
    fy, by = -(D - 0.4) / 2, (D - 0.4) / 2
    for side, y in (("front", fy), ("back", by)):
        sign = -1 if side == "front" else 1
        for x in (-3.55, 0.0, 3.55):
            s.box("Dark", (2.9, 0.06, 2.3), (x, y + sign * 0.03, 1.95))
            s.box("Body", (2.5, 0.08, 1.9), (x, y + sign * 0.05, 1.95))
        for x in (-5.3, -1.775, 1.775, 5.3):
            s.box("Brass", (0.5, 0.1, 3.0), (x, y + sign * 0.05, 2.1))
            if side == "front" and abs(x) > 5:
                for i in range(7):
                    s.box("Glow", (0.16, 0.05, 0.16), (x, y - 0.11, 0.9 + i * 0.4))
        if side == "front":
            for x in (-3.55, 0.0, 3.55):
                rune_band(s, "Glow", x - 1.25, x + 1.25, y - 0.09, 3.32)
    # short faces: one framed panel each, with a rune band
    for sign in (-1, 1):
        x = sign * (L - 0.4) / 2
        s.box("Dark", (0.06, 2.9, 2.3), (x + sign * 0.03, 0, 1.95))
        s.box("Body", (0.08, 2.5, 1.9), (x + sign * 0.05, 0, 1.95))
        rune_band(s, "Glow", -1.25, 1.25, x + sign * 0.09, 3.32, face="side")
    return s.build()


def pedestal_runic():
    s = Skin("PedestalRunic")
    s.mat("Body", SLATE, roughness=0.85)
    s.mat("Dark", SHADOW, roughness=0.9)
    s.mat("Brass", BRASS, metallic=0.9, roughness=0.35)
    s.mat("Glow", RUNE, emission=3.0)
    W = 2.8
    # stepped bottom cap (two steps) and stepped top cap (Sean's spec, 2026-11-24)
    s.box("Dark", (W, W, 0.35), (0, 0, 0.175))
    s.box("Dark", (2.55, 2.55, 0.25), (0, 0, 0.35 + 0.125))
    s.box("Body", (2.3, 2.3, 2.85), (0, 0, 0.6 + 2.85 / 2))
    s.box("Body", (2.55, 2.55, 0.2), (0, 0, 3.45 + 0.1))
    s.box("Body", (W, W, 0.55), (0, 0, 3.65 + 0.55 / 2))
    s.box("Dark", (2.3, 2.3, 0.01), (0, 0, TOP - 0.005))
    # subtle aged-brass inlays down the four column corners
    for cx in (-1.15, 1.15):
        for cy in (-1.15, 1.15):
            s.box("Brass", (0.09, 0.09, 2.85), (cx, cy, 0.6 + 2.85 / 2))
    # every face: two pilasters, a dark channel between them with a stacked rune, a brass chevron under the cap
    for k in range(4):
        ang = k * math.pi / 2
        ca, sa = math.cos(ang), math.sin(ang)

        def at(u, v, z):  # u along the face, v outward from the face (face normal = -Y rotated by ang)
            return (u * ca + v * sa, u * sa - v * ca, z)

        rot = ang
        for u in (-0.9, 0.9):
            s.box("Body", (0.45, 0.12, 2.85), at(u, 1.15 + 0.06, 0.6 + 2.85 / 2), rot_z=rot)
        s.box("Dark", (1.1, 0.04, 2.7), at(0, 1.15 + 0.02, 2.0), rot_z=rot)
        # the rune: a vertical stroke with two short arms, an arch and an angle (simplified glyphs from the sheet)
        s.box("Glow", (0.1, 0.05, 0.9), at(-0.12, 1.2, 2.75), rot_z=rot)
        s.box("Glow", (0.34, 0.05, 0.09), at(0.05, 1.2, 3.1), rot_z=rot)
        s.box("Glow", (0.28, 0.05, 0.09), at(0.02, 1.2, 2.85), rot_z=rot)
        s.box("Glow", (0.1, 0.05, 0.6), at(-0.15, 1.2, 1.95), rot_z=rot)
        s.box("Glow", (0.1, 0.05, 0.6), at(0.15, 1.2, 1.95), rot_z=rot)
        s.box("Glow", (0.4, 0.05, 0.09), at(0.0, 1.2, 2.22), rot_z=rot)
        s.box("Glow", (0.1, 0.05, 0.45), at(-0.06, 1.2, 1.25), rot_z=rot + 0.0, rot_y=0.0)
        s.box("Glow", (0.32, 0.05, 0.09), at(0.06, 1.2, 1.05), rot_z=rot)
        # recessed rune border round the top rim (on the top cap)
        u0, u1 = -1.2, 1.2
        n = 7
        for i in range(n):
            u = u0 + (u1 - u0) * (i + 0.5) / n
            s.box("Glow", (0.14, 0.04, 0.24 if i % 2 == 0 else 0.18), at(u, 1.42, 3.92), rot_z=rot)
    return s.build()


# ===== CELESTIAL ASCENSION (Mythic) =====

MARBLE, TEAL, GOLD, WARM = "F2ECE1", "1F7A7A", "E3B23C", "FFF2CC"


def wing(s: Skin, face: str, plane: float, u_root: float, z_root: float, toward: int, lengths, angles, widths,
         thick: float = 0.08, ridge: bool = True, z_step: float = 0.12):
    """A low-poly wing relief: feather blades fanning up from a root, lying flat on a face.
    face: "front" (-Y), "back" (+Y), "left" (-X), "right" (+X); plane = the face's distance from the centre;
    u = position along the face (X for front/back, Y for left/right); toward = -1/+1, the way the feathers fan."""
    normal = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    for i, (length, ang, width) in enumerate(zip(lengths, angles, widths)):
        a = math.radians(ang)
        du, dz = toward * math.cos(a), math.sin(a)
        zr = z_root + i * z_step
        cu, cz = u_root + du * length / 2, zr + dz * length / 2
        # the ridge runs along the blade's outer edge (perpendicular in the face plane, on the side away from the
        # next feather: up for rising fans, down for folded wings)
        pu, pz = -dz * toward, abs(du)
        if dz < 0:
            pu, pz = -pu, -pz
        ru, rz = cu + pu * width / 2, cz + pz * width / 2
        for part, off, t, w, u0, z0 in (("Brass", thick / 2, thick, width, cu, cz),
                                         ("Glow", thick + 0.025, 0.05, 0.06, ru, rz)):
            if part == "Glow" and not ridge:
                continue
            n = plane + off
            if face in ("front", "back"):
                center = (u0, normal[1] * n, z0)
                s.box(part, (length, t, w), center, rot_y=-math.atan2(dz, du))
            else:
                center = (normal[0] * n, u0, z0)
                s.box(part, (t, length, w), center, rot_x=math.atan2(dz, du))


def shelf_celestial():
    s = Skin("ShelfCelestial")
    s.mat("Marble", MARBLE, roughness=0.25)
    s.mat("Teal", TEAL, roughness=0.5)
    s.mat("Brass", GOLD, metallic=0.9, roughness=0.3)
    s.mat("Glow", WARM, emission=3.0)
    L, D = 11.2, 4.2
    # teal plinth with a brass strip, teal body, marble panels front and back, brass neck ring (glow), marble top
    s.box("Teal", (L, D, 0.45), (0, 0, 0.225))
    s.box("Brass", (L - 0.2, D - 0.2, 0.07), (0, 0, 0.485))
    s.box("Teal", (L - 0.4, D - 0.4, 3.08), (0, 0, 0.52 + 3.08 / 2))
    s.box("Glow", (L - 0.25, D - 0.25, 0.1), (0, 0, 3.65))
    s.box("Marble", (L, D, 0.49), (0, 0, 3.7 + 0.49 / 2))  # 4.19: the flush inlays make the top exactly 4.2
    for x in (-3.5, 0.0, 3.5):  # flush teal squares where the items stand
        s.box("Teal", (2.4, 2.4, 0.01), (x, 0, TOP - 0.005))
    for sign in (-1, 1):
        y = sign * (D - 0.4) / 2
        s.box("Marble", (L - 1.6, 0.06, 2.6), (0, y + sign * 0.03, 2.05))
        s.box("Teal", (0.9, 0.08, 0.45), (0, y + sign * 0.05, 3.15), rot_y=math.radians(45) if False else 0.0)
        for z in (0.78, 3.33):  # gold frame lines round the marble panel
            s.box("Brass", (L - 1.5, 0.08, 0.06), (0, y + sign * 0.05, z))
    # golden corner pilasters; folded wings at the top of each front corner and on both ends (sheet: wings sweep
    # down and inward from the top corners, broad overlapping feathers)
    for sx in (-1, 1):
        for sy in (-1, 1):
            s.box("Brass", (0.32, 0.32, 3.1), (sx * (L - 0.5) / 2, sy * (D - 0.5) / 2, 2.05))
        wing(s, "front", (D - 0.4) / 2, sx * 5.1, 3.35, -sx, (2.5, 2.4, 2.15, 1.8, 1.4), (-8, -24, -40, -56, -72),
             (0.42, 0.42, 0.4, 0.36, 0.32), z_step=-0.08)
    for face in ("left", "right"):
        wing(s, face, (L - 0.4) / 2, -1.7, 3.35, 1, (2.2, 2.05, 1.85, 1.55, 1.2), (-8, -24, -40, -56, -72),
             (0.38, 0.38, 0.36, 0.32, 0.28), z_step=-0.08)
    return s.build()


def pedestal_celestial():
    s = Skin("PedestalCelestial")
    s.mat("Marble", MARBLE, roughness=0.25)
    s.mat("Teal", TEAL, roughness=0.5)
    s.mat("Brass", GOLD, metallic=0.9, roughness=0.3)
    s.mat("Glow", WARM, emission=3.0)
    W = 2.8
    s.box("Brass", (W, W, 0.22), (0, 0, 0.11))
    s.box("Marble", (2.6, 2.6, 0.33), (0, 0, 0.22 + 0.165))
    s.box("Teal", (2.2, 2.2, 2.95), (0, 0, 0.55 + 2.95 / 2))
    for cx in (-0.86, 0.86):  # marble corner pilasters round the teal core (a hair proud of it: no flicker)
        for cy in (-0.86, 0.86):
            s.box("Marble", (0.52, 0.52, 2.95), (cx, cy, 0.55 + 2.95 / 2))
    s.box("Glow", (2.42, 2.42, 0.11), (0, 0, 3.555))  # thin brass neck ring under the top slab (glows)
    s.box("Marble", (W, W, 0.58), (0, 0, 3.61 + 0.58 / 2))  # 4.19: the flush gold frame makes the top exactly 4.2
    # gold inlay frame on the top (flush), marble in the middle
    for k in range(4):
        ang = k * math.pi / 2
        x, y = 1.15 * math.cos(ang), 1.15 * math.sin(ang)
        s.box("Brass", (0.08 if k % 2 == 0 else 2.38, 2.38 if k % 2 == 0 else 0.08, 0.01), (x, y, TOP - 0.005))
    s.box("Marble", (2.3, 2.3, 0.01), (0, 0, TOP - 0.005))
    # gold arch lines on each face round the teal panel, and a wing on both edges of every face (hugging the corners)
    for face in ("front", "back", "left", "right"):
        n = 1.1
        for u in (-0.58, 0.58):
            if face in ("front", "back"):
                y = (-1 if face == "front" else 1) * (n + 0.02)
                s.box("Brass", (0.06, 0.04, 2.7), (u, y, 2.0))
            else:
                x = (-1 if face == "left" else 1) * (n + 0.02)
                s.box("Brass", (0.04, 0.06, 2.7), (x, u, 2.0))
        for u_root, toward in ((1.02, -1), (-1.02, 1)):
            wing(s, face, n + 0.02, u_root, 3.3, toward, (1.25, 1.2, 1.1, 0.95, 0.8), (-12, -30, -48, -64, -80),
                 (0.3, 0.3, 0.28, 0.26, 0.24), z_step=-0.07)
    return s.build()


# ===== COSMIC HARMONY (Mythic) =====

C_TEAL, C_CORAL, C_DEEP, C_GOLD, C_CRYSTAL, C_STAR, C_ALABASTER = "1F7A7A", "D2694A", "123F45", "E3B23C", "8CE8E8", "FFF2CC", "F7F1E3"


def cosmic_mats(s: Skin):
    # galaxy remake (Sean, 2026-11-24): deep space body, nebula clouds the game colour-shifts (pink/violet/cyan)
    s.mat("Space", "141838", roughness=0.25)  # deep navy
    s.mat("Violet", "35205F", roughness=0.25)  # deep purple
    s.mat("Void", "07081A", roughness=0.4)  # near black
    s.mat("Nebula", "B0479F", roughness=0.2)  # pink cloud (shifts in game)
    s.mat("NebulaCore", "F08CD8", emission=1.5)  # bright cloud heart (neon, shifts in game)
    s.mat("Brass", C_GOLD, metallic=0.9, roughness=0.3)
    s.mat("Glow", C_CRYSTAL, emission=3.0)  # crystal wings (cyan neon)
    s.mat("Star", C_STAR, emission=3.0)  # star lines, star dots, item-spot borders (starlight neon)


def crystal(s: Skin, part: str, center, length: float, width: float, lean_dir, lean_deg: float, spin_deg: float = 45.0):
    """A faceted crystal shard (4-sided bipyramid), standing up and leaning lean_deg toward lean_dir (x, y)."""
    import mathutils

    o = c.sphere(f"{s.id}_{part}", 1.0, center, scale=(width / 2, width / 2, length / 2), segments=4, rings=2)
    lx, ly = lean_dir
    axis = mathutils.Vector((-ly, lx, 0.0))
    rot = mathutils.Matrix.Rotation(math.radians(spin_deg), 4, "Z")
    if axis.length > 1e-6:
        rot = mathutils.Matrix.Rotation(math.radians(lean_deg), 4, axis.normalized()) @ rot
    o.rotation_euler = rot.to_euler()
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    s.add(part, o)
    return o


def tri_panel(s: Skin, part_of, face: str, plane: float, u0: float, u1: float, z0: float, z1: float, nu: int, nz: int,
              seed: int):
    """A faceted low-poly panel: a jittered triangle grid lying on a face; part_of(un, zn, k) picks each triangle's
    material group. Each group becomes one flat mesh object, facing out of the face."""
    import random

    rng = random.Random(seed)
    normal = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    n = plane + 0.02
    du, dz = (u1 - u0) / nu, (z1 - z0) / nz
    grid = {}
    for i in range(nu + 1):
        for j in range(nz + 1):
            ju = rng.uniform(-0.32, 0.32) * du if 0 < i < nu else 0.0
            jz = rng.uniform(-0.32, 0.32) * dz if 0 < j < nz else 0.0
            grid[(i, j)] = (u0 + i * du + ju, z0 + j * dz + jz)

    def world(uz):
        u, z = uz
        if face in ("front", "back"):
            return (u, normal[1] * n, z)
        return (normal[0] * n, u, z)

    outward = (normal[0], normal[1], 0.0)
    groups = {}
    k = 0
    for i in range(nu):
        for j in range(nz):
            a, b, cc, d = grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]
            tris = ((a, b, cc), (a, cc, d)) if (i + j) % 2 == 0 else ((a, b, d), (b, cc, d))
            for t in tris:
                cu = sum(p[0] for p in t) / 3
                cz = sum(p[1] for p in t) / 3
                part = part_of((cu - u0) / (u1 - u0), (cz - z0) / (z1 - z0), k)
                k += 1
                p1, p2, p3 = (world(p) for p in t)
                # face the triangle out of the panel
                e1 = (p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2])
                e2 = (p3[0] - p1[0], p3[1] - p1[1], p3[2] - p1[2])
                cross = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
                if cross[0] * outward[0] + cross[1] * outward[1] < 0:
                    p2, p3 = p3, p2
                groups.setdefault(part, []).append((p1, p2, p3))
    for part, tris in groups.items():
        verts, faces = [], []
        for t in tris:
            base = len(verts)
            verts.extend(t)
            faces.append((base, base + 1, base + 2))
        me = bpy.data.meshes.new(f"{s.id}_{part}_panel")
        me.from_pydata(verts, [], faces)
        me.update()
        ob = bpy.data.objects.new(f"{s.id}_{part}", me)
        bpy.context.collection.objects.link(ob)
        s.add(part, ob)


def nebula_part(seed: float):
    """Deep space with a nebula cloud swirling through it, a bright heart, dark voids and purple dust."""

    def pick(un, zn, k):
        swirl = math.sin(3.1 * un + 2.3 * zn + seed) + 0.6 * math.sin(5.3 * zn - 2.2 * un + seed * 1.7)
        if swirl > 1.05:
            return "NebulaCore"
        if swirl > 0.45:
            return "Nebula"
        if swirl < -0.95:
            return "Void"
        return "Violet" if k % 4 == 0 else "Space"

    return pick


def nebula(s: Skin, face: str, plane: float, u0: float, u1: float, z0: float, z1: float, cols: int, rows: int, seed: int):
    """A nebula panel: faceted triangles in deep teal / teal / coral / light coral, a few starlight dots, gold frame."""
    tri_panel(s, nebula_part(seed * 1.3), face, plane, u0, u1, z0, z1, cols, rows, seed)
    normal = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    nn = plane + 0.06
    # gold filigree frame with little corner brackets
    w = 0.08
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2
    lu, lz = u1 - u0, z1 - z0
    pieces = [((um, z0 - w / 2), (lu + 2 * w, w)), ((um, z1 + w / 2), (lu + 2 * w, w)),
              ((u0 - w / 2, zm), (w, lz)), ((u1 + w / 2, zm), (w, lz))]
    for cu, cz in ((u0 + 0.22, z0 + 0.22), (u1 - 0.22, z0 + 0.22), (u0 + 0.22, z1 - 0.22), (u1 - 0.22, z1 - 0.22)):
        pieces.append(((cu, cz), (0.26, 0.06)))
        pieces.append(((cu, cz), (0.06, 0.26)))
    for (cu, cz), (su, sz) in pieces:
        if face in ("front", "back"):
            s.box("Brass", (su, 0.05, sz), (cu, normal[1] * nn, cz))
        else:
            s.box("Brass", (0.05, su, sz), (normal[0] * nn, cu, cz))
    # a scatter of starlight dots
    import random

    rng = random.Random(seed * 101)
    for _ in range(max(6, int(lu * lz * 3.2))):
        cu, cz = rng.uniform(u0 + 0.15, u1 - 0.15), rng.uniform(z0 + 0.15, z1 - 0.15)
        sz = rng.choice((0.05, 0.06, 0.09))
        if face in ("front", "back"):
            s.box("Star", (sz, 0.03, sz), (cu, normal[1] * (plane + 0.04), cz), rot_y=math.radians(45))
        else:
            s.box("Star", (0.03, sz, sz), (normal[0] * (plane + 0.04), cu, cz), rot_x=math.radians(45))


def star_line(s: Skin, face: str, plane: float, u0: float, u1: float, z: float):
    """A gold-rimmed starlight filigree line along a face."""
    normal = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    length = u1 - u0
    um = (u0 + u1) / 2
    for part, n, size_n, h in (("Brass", plane + 0.04, 0.06, 0.16), ("Star", plane + 0.08, 0.04, 0.06)):
        if face in ("front", "back"):
            s.box(part, (length, size_n, h), (um, normal[1] * n, z))
        else:
            s.box(part, (size_n, length, h), (normal[0] * n, um, z))


def top_spot(s: Skin, x: float, y: float, size: float = 2.8):
    """A 2.8 x 2.8 item spot on the top: starlight border (glow) round a coral-and-teal inlay, all flush at 4.2."""
    b = 0.1
    half = size / 2 - b / 2
    for dx, dy, sx, sy in ((0, -half, size, b), (0, half, size, b), (-half, 0, b, size - 2 * b), (half, 0, b, size - 2 * b)):
        s.box("Star", (sx, sy, 0.01), (x + dx, y + dy, TOP - 0.005))
    s.box("Space", (size - 2 * b, size - 2 * b, 0.01), (x, y, TOP - 0.005))


def shelf_cosmic():
    s = Skin("ShelfCosmic")
    cosmic_mats(s)
    L, D = 11.2, 4.2
    s.box("Violet", (L, D, 0.42), (0, 0, 0.21))  # purple plinth
    s.box("Brass", (L - 0.2, D - 0.2, 0.08), (0, 0, 0.46))
    s.box("Void", (L - 1.0, D - 0.4, 3.1), (0, 0, 0.5 + 3.1 / 2))
    s.box("Brass", (L - 0.2, D - 0.2, 0.09), (0, 0, 3.645))
    s.box("Space", (L, D, 0.5), (0, 0, 3.69 + 0.5 / 2))  # 4.19; the flush spots make the top exactly 4.2
    for x in (-3.5, 0.0, 3.5):
        top_spot(s, x, 0.0)
    fy = (D - 0.4) / 2
    # front: three nebula panels between teal crystal pillars, star filigree lines above and below
    for i, x in enumerate((-3.55, 0.0, 3.55)):
        nebula(s, "front", fy, x - 1.4, x + 1.4, 0.8, 3.25, 7, 6, seed=i + 1)
    for x in (-1.775, 1.775):  # the outer corners are the crystal wings
        s.box("Space", (0.42, 0.1, 3.0), (x, -(fy + 0.05), 2.05))
    star_line(s, "front", fy, -5.05, 5.05, 3.42)
    star_line(s, "front", fy, -5.05, 5.05, 0.62)
    # ends: one nebula panel each with filigree lines
    for face in ("left", "right"):
        nebula(s, face, (L - 1.0) / 2, -1.45, 1.45, 0.8, 3.25, 6, 6, seed=7 if face == "left" else 9)
        star_line(s, face, (L - 1.0) / 2, -1.5, 1.5, 3.42)
        star_line(s, face, (L - 1.0) / 2, -1.5, 1.5, 0.62)
    # back (against the wall): plain teal panel with one filigree line
    s.box("Space", (L - 1.2, 0.06, 2.6), (0, fy + 0.03, 2.05))
    star_line(s, "back", fy, -5.05, 5.05, 3.42)
    # faceted crystal wings on all four vertical corners (cyan glow), leaning outward, inside the 0.15 rim
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (L / 2 - 0.42), sy * (D / 2 - 0.36)  # body cut back at the ends: the wings stand clear
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 2.3), 3.0, 0.6, d, 4)
            crystal(s, "Glow", (cx, cy - sy * 0.42, 1.75), 1.9, 0.42, (sx * 0.3, -sy * 0.95), 12)
            crystal(s, "Glow", (cx - sx * 0.45, cy, 1.85), 1.7, 0.4, (-sx * 0.95, sy * 0.3), 12)
            crystal(s, "Glow", (cx - sx * 0.25, cy - sy * 0.25, 3.05), 0.9, 0.3, (-sx * 0.7, -sy * 0.7), 18)
    return s.build()


def pedestal_cosmic():
    s = Skin("PedestalCosmic")
    cosmic_mats(s)
    W = 2.8
    s.box("Violet", (W, W, 0.42), (0, 0, 0.21))
    s.box("Brass", (2.6, 2.6, 0.1), (0, 0, 0.47))
    s.box("Void", (2.3, 2.3, 2.9), (0, 0, 0.52 + 2.9 / 2))
    s.box("Brass", (2.55, 2.55, 0.1), (0, 0, 3.47))
    s.box("Space", (W, W, 0.67), (0, 0, 3.52 + 0.67 / 2))  # 4.19
    s.box("Nebula", (2.82, 2.82, 0.16), (0, 0, 3.62))  # a nebula band (colour-shifts in game) through the top slab
    top_spot(s, 0.0, 0.0, 2.8)
    for k, face in enumerate(("front", "back", "left", "right")):
        nebula(s, face, 1.15, -0.82, 0.82, 0.8, 3.25, 4, 6, seed=k + 3)
        star_line(s, face, 1.15, -1.0, 1.0, 3.38)
        star_line(s, face, 1.15, -1.0, 1.0, 0.66)
        # recessed nebula core facets (glow): a small diamond of starlight at the heart of each panel
        n = 1.15 + 0.07
        nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
        for dz, du, sz in ((2.1, 0, 0.26), (1.8, -0.2, 0.16), (2.35, 0.22, 0.14)):
            if face in ("front", "back"):
                s.box("Star", (sz, 0.04, sz), (du, ny * n, dz), rot_y=math.radians(45))
            else:
                s.box("Star", (0.04, sz, sz), (nx * n, du, dz), rot_x=math.radians(45))
    # faceted crystal wings along all four vertical edges (cyan glow), flush with the corners
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 1.16, sy * 1.16
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 2.2), 2.4, 0.46, d, 4)
            crystal(s, "Glow", (cx, cy - sy * 0.3, 1.5), 1.3, 0.3, (sx * 0.3, -sy * 0.95), 12)
            crystal(s, "Glow", (cx - sx * 0.3, cy, 1.6), 1.2, 0.28, (-sx * 0.95, sy * 0.3), 12)
            crystal(s, "Glow", (cx, cy, 3.15), 0.8, 0.26, d, 14)
    return s.build()


# ===== CASHIER COUNTERS (Plots.PlotN.ShopProps.CashCounter) =====
# Sized to the classic counter in Plot1 (Body 8.04 x 2.51 x 3.13, register on top to 4.2); the game scales the model to
# each shop's counter (Plots 2-6 are 1.34x bigger). Front (-Y) = the customer side, back (+Y) = the owner side (open
# shelves). The register sits left of centre as the customer sees it (-X) with its keys and drawer toward the owner.

CW, CD, CH = 8.04, 2.51, 3.13


def cyl(s: Skin, part: str, radius: float, height: float, center, verts: int = 12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=center)
    o = bpy.context.active_object
    o.name = f"{s.id}_{part}"
    s.add(part, o)
    return o


def counter_shell(s: Skin, top_part: str, core_part: str, frame_part: str, trim_part: str,
                  plinth_part: str = "", upright_part: str = "", shelf_part: str = "", back_part: str = ""):
    """The shape every cashier skin shares: plinth, solid customer half, open owner half with 3 bays and 2 shelves,
    a top slab overhanging 0.1, end walls. Returns the customer face's y (front of the core) and the bays' centre y.
    plinth / upright / shelf / back parts default to frame_part."""
    plinth_part = plinth_part or frame_part
    upright_part = upright_part or frame_part
    shelf_part = shelf_part or frame_part
    back_part = back_part or frame_part
    y_f = -CD / 2 + 0.1
    s.box(plinth_part, (CW, CD, 0.3), (0, 0, 0.15))  # plinth
    s.box(trim_part, (CW - 0.1, 0.05, 0.08), (0, -CD / 2 - 0.0, 0.33))  # trim line on the plinth (front)
    s.box(core_part, (CW - 0.4, 1.3, 2.55), (0, y_f + 0.65, 0.3 + 2.55 / 2))  # solid customer half
    for sx in (-1, 1):  # end walls, full depth
        s.box(core_part, (0.2, CD - 0.2, 2.55), (sx * (CW / 2 - 0.2), 0, 0.3 + 2.55 / 2))
    y_back0, y_back1 = y_f + 1.3, CD / 2 - 0.1
    yb = (y_back0 + y_back1) / 2
    db = y_back1 - y_back0
    for x in (-1.34, 1.34):  # uprights between the 3 owner bays
        s.box(upright_part, (0.22, db, 2.55), (x, yb, 0.3 + 2.55 / 2))
    s.box(shelf_part, (CW - 0.6, db, 0.1), (0, yb, 0.35))  # bottom shelf
    s.box(shelf_part, (CW - 0.6, db, 0.1), (0, yb, 1.55))  # middle shelf
    s.box(back_part, (CW - 0.6, 0.04, 2.5), (0, y_back0 + 0.02, 1.6))  # back of the bays
    s.box(trim_part, (CW - 0.1, CD - 0.1, 0.08), (0, 0, 2.81))  # band right under the top
    s.box(top_part, (CW + 0.2, CD + 0.2, 0.28), (0, 0, CH - 0.14))  # top slab, flat at CH
    return y_f, yb


def cashier_runic():
    s = Skin("CashierRunic")
    s.mat("Body", SLATE, roughness=0.85)
    s.mat("Dark", SHADOW, roughness=0.9)
    s.mat("Brass", BRASS, metallic=0.9, roughness=0.35)
    s.mat("Glow", RUNE, emission=3.0)
    s.mat("Paper", "C8A878", roughness=0.9)
    s.mat("Wood", "5A4636", roughness=0.85)
    s.mat("Iron", "3A3D42", metallic=0.7, roughness=0.5)
    s.mat("Bronze", "8C6A2F", metallic=0.9, roughness=0.4)
    s.mat("Glass", "D8E8EE", roughness=0.05)
    s.mat("Receipt", "F4F0E8", roughness=0.6)
    y_f, yb = counter_shell(s, "Body", "Body", "Dark", "Brass")

    # customer face: 3 framed slate panels with a carved rune frieze above each, glowing pilasters between them
    for x in (-2.48, 0.0, 2.48):
        s.box("Dark", (2.1, 0.06, 1.7), (x, y_f - 0.03, 1.35))
        s.box("Body", (1.8, 0.08, 1.4), (x, y_f - 0.05, 1.35))
        s.box("Dark", (2.1, 0.05, 0.34), (x, y_f - 0.025, 2.45))
        rune_band(s, "Glow", x - 0.95, x + 0.95, y_f - 0.07, 2.45, height=0.2)
    for x in (-3.72, -1.24, 1.24, 3.72):
        s.box("Dark", (0.3, 0.1, 2.4), (x, y_f - 0.05, 1.55))
        s.box("Glow", (0.1, 0.05, 1.9), (x, y_f - 0.12, 1.5))
    # end faces: framed panel + rune band
    for sx in (-1, 1):
        xf = sx * (CW / 2 - 0.1)
        s.box("Dark", (0.06, 1.9, 1.7), (xf + sx * 0.03, 0, 1.35))
        s.box("Body", (0.08, 1.6, 1.4), (xf + sx * 0.05, 0, 1.35))
        rune_band(s, "Glow", -0.85, 0.85, xf + sx * 0.08, 2.45, height=0.2, face="side")

    # owner bays: rune-stamped parchment bags + stacks on the middle shelf, iron-bound relic boxes below
    for x in (-3.0, -2.35):
        s.box("Paper", (0.5, 0.4, 0.75), (x, yb, 1.6 + 0.375))
        s.box("Glow", (0.18, 0.03, 0.18), (x, yb + 0.21, 1.95))
    for x in (-0.45, 0.35):
        for k in range(5):
            s.box("Paper", (0.6, 0.5, 0.07), (x + (k % 2) * 0.04, yb, 1.64 + k * 0.08))
    for x in (-3.15, -2.15, -0.25, 2.05, 3.05):
        s.box("Wood", (0.8, 0.7, 0.55), (x, yb, 0.4 + 0.275))
        for dx in (-0.25, 0.25):
            s.box("Iron", (0.08, 0.74, 0.58), (x + dx, yb, 0.4 + 0.29))
    # cash drawer under the top in the owner's right bay (purple bills)
    s.box("Dark", (1.7, 0.9, 0.28), (2.65, yb, 2.6))
    for i in range(4):
        s.box("Glow" if i < 3 else "Iron", (0.32, 0.6, 0.03), (2.1 + i * 0.37, yb, 2.75))

    # --- on the top (z = CH) ---
    rx, top = -2.3, CH
    s.box("Dark", (1.9, 1.45, 0.3), (rx, 0.15, top + 0.15))  # register base
    s.box("Brass", (1.96, 1.5, 0.06), (rx, 0.15, top + 0.31))
    s.box("Body", (1.8, 1.1, 0.42), (rx, 0.0, top + 0.55))  # carved slate body
    rune_band(s, "Glow", rx - 0.75, rx + 0.75, -0.56, top + 0.55, height=0.2)  # rune keys face the customer
    s.box("Dark", (1.3, 0.55, 0.06), (rx, 0.6, top + 0.79))  # key deck toward the owner
    for r in range(2):
        for k in range(4):
            s.box("Receipt", (0.22, 0.16, 0.05), (rx - 0.45 + k * 0.3, 0.48 + r * 0.24, top + 0.84))
    s.box("Brass", (0.1, 0.1, 0.3), (rx, -0.35, top + 0.91))  # display pole
    s.box("Dark", (0.8, 0.14, 0.3), (rx, -0.38, top + 0.92))
    s.box("Glow", (0.64, 0.03, 0.18), (rx, -0.46, top + 0.92))  # price display (customer side)
    s.box("Dark", (1.7, 0.3, 0.24), (rx, 1.05, top + 0.13))  # register drawer toward the owner
    s.box("Brass", (0.25, 0.04, 0.06), (rx, 1.21, top + 0.13))
    cyl(s, "Receipt", 0.14, 0.3, (rx + 1.15, 0.45, top + 0.15), verts=10)
    # stone change tray, dark bronze bell, rune-etched glass tip jar
    s.box("Dark", (1.0, 0.6, 0.08), (0.3, 0.1, top + 0.04))
    s.box("Body", (0.84, 0.44, 0.04), (0.3, 0.1, top + 0.08))
    cyl(s, "Dark", 0.24, 0.06, (1.7, 0.1, top + 0.03), verts=14)
    s.add("Bronze", c.sphere(f"{s.id}_Bronze", 0.22, (1.7, 0.1, top + 0.08), scale=(1, 1, 0.8), segments=12, rings=6))
    s.box("Bronze", (0.06, 0.06, 0.1), (1.7, 0.1, top + 0.3))
    cyl(s, "Glass", 0.3, 0.62, (3.15, -0.4, top + 0.31), verts=14)
    s.box("Glow", (0.3, 0.04, 0.2), (3.15, -0.4, top + 0.25))  # the glowing bill inside
    return s.build()


def register_set(s: Skin, P: dict):
    """The cash register and the counter-top props, shared by the newer counters. P maps a role to a part name:
    base, trim, body, deck, keys, pole, frame, screen, drawer, roll, tray, inset, bellbase, bell, jar, bill, collar."""
    rx, top = -2.3, CH
    s.box(P["base"], (1.9, 1.45, 0.3), (rx, 0.15, top + 0.15))
    s.box(P["trim"], (1.96, 1.5, 0.06), (rx, 0.15, top + 0.31))
    s.box(P["body"], (1.8, 1.1, 0.42), (rx, 0.0, top + 0.55))
    s.box(P["deck"], (1.3, 0.55, 0.06), (rx, 0.6, top + 0.79))
    for r in range(2):
        for k in range(4):
            s.box(P["keys"], (0.22, 0.16, 0.05), (rx - 0.45 + k * 0.3, 0.48 + r * 0.24, top + 0.84))
    s.box(P["pole"], (0.1, 0.1, 0.3), (rx, -0.35, top + 0.91))
    s.box(P["frame"], (0.8, 0.14, 0.3), (rx, -0.38, top + 0.92))
    s.box(P["screen"], (0.64, 0.03, 0.18), (rx, -0.46, top + 0.92))  # price display, facing the customer
    s.box(P["drawer"], (1.7, 0.3, 0.24), (rx, 1.05, top + 0.13))
    s.box(P["trim"], (0.25, 0.04, 0.06), (rx, 1.21, top + 0.13))
    cyl(s, "Receipt", 0.14, 0.3, (rx + 1.15, 0.45, top + 0.15), verts=10)
    s.box(P["tray"], (1.0, 0.6, 0.08), (0.3, 0.1, top + 0.04))
    s.box(P["inset"], (0.84, 0.44, 0.04), (0.3, 0.1, top + 0.08))
    cyl(s, P["bellbase"], 0.24, 0.06, (1.7, 0.1, top + 0.03), verts=14)
    s.add(P["bell"], c.sphere(f"{s.id}_{P['bell']}", 0.22, (1.7, 0.1, top + 0.08), scale=(1, 1, 0.8), segments=12, rings=6))
    s.box(P["bell"], (0.06, 0.06, 0.1), (1.7, 0.1, top + 0.3))
    cyl(s, "Glass", 0.3, 0.62, (3.15, -0.4, top + 0.31), verts=14)
    cyl(s, P["collar"], 0.32, 0.08, (3.15, -0.4, top + 0.58), verts=14)
    s.box(P["bill"], (0.3, 0.04, 0.2), (3.15, -0.4, top + 0.25))


def cashier_classic():
    """A plain counter the game repaints for the colour skins (Common .. Legendary): parts Body (panels), Frame
    (core, frames, plinth, shelves), Top (slab) and Trim (stripe + bands) take the skin's colours in SkinModelController;
    the register and props keep their own colours. Default colours = the classic counter (oak, cream, teal)."""
    s = Skin("CashierClassic")
    s.mat("Body", "EFE6D2", roughness=0.6)
    s.mat("Frame", "7A5233", roughness=0.7)
    s.mat("Top", "B07A48", roughness=0.6)
    s.mat("Trim", "1F7A7A", roughness=0.5)
    s.mat("Dark", "23252A", roughness=0.5)
    s.mat("Grey", "9AA0A6", metallic=0.5, roughness=0.4)
    s.mat("Screen", "2B3D2B", roughness=0.2)
    s.mat("Paper", "C8A878", roughness=0.9)
    s.mat("Bill", "6BAF6B", roughness=0.8)
    s.mat("Bell", "C9A227", metallic=0.9, roughness=0.3)
    s.mat("Glass", "D8E8EE", roughness=0.05)
    s.mat("Receipt", "F4F0E8", roughness=0.6)
    y_f, yb = counter_shell(s, "Top", "Frame", "Frame", "Trim")
    for x in (-3.06, -1.53, 0.0, 1.53, 3.06):  # 5 framed panels like the classic counter
        s.box("Frame", (1.4, 0.05, 2.1), (x, y_f - 0.025, 1.5))
        s.box("Body", (1.2, 0.08, 1.9), (x, y_f - 0.04, 1.5))
    s.box("Trim", (CW - 0.3, 0.08, 0.2), (0, y_f - 0.04, 2.72))  # stripe under the top
    for sx in (-1, 1):
        xf = sx * (CW / 2 - 0.1)
        s.box("Body", (0.08, 1.7, 1.9), (xf + sx * 0.04, 0, 1.5))
    for x in (-3.0, -2.35):
        s.box("Paper", (0.5, 0.4, 0.75), (x, yb, 1.6 + 0.375))
    for x in (-0.45, 0.35):
        for k in range(5):
            s.box("Paper", (0.6, 0.5, 0.07), (x + (k % 2) * 0.04, yb, 1.64 + k * 0.08))
    for x in (-3.15, -2.15, 2.05, 3.05):
        s.box("Paper", (0.8, 0.7, 0.55), (x, yb, 0.4 + 0.275))
    s.box("Dark", (1.7, 0.9, 0.28), (2.65, yb, 2.6))
    for i in range(4):
        s.box("Bill" if i < 3 else "Grey", (0.32, 0.6, 0.03), (2.1 + i * 0.37, yb, 2.75))
    register_set(s, {"base": "Dark", "trim": "Grey", "body": "Dark", "deck": "Grey", "keys": "Receipt", "pole": "Grey",
                     "frame": "Dark", "screen": "Screen", "drawer": "Dark", "tray": "Trim", "inset": "Dark",
                     "bellbase": "Dark", "bell": "Bell", "bill": "Bill", "collar": "Grey"})
    return s.build()


def cashier_celestial():
    s = Skin("CashierCelestial")
    s.mat("Marble", MARBLE, roughness=0.25)
    s.mat("Teal", TEAL, roughness=0.5)
    s.mat("Brass", GOLD, metallic=0.9, roughness=0.3)
    s.mat("Glow", WARM, emission=3.0)
    s.mat("Paper", "D8C49A", roughness=0.85)
    s.mat("Dark", "2E2E33", roughness=0.5)
    s.mat("Bill", "6BAF6B", roughness=0.8)
    s.mat("Glass", "D8E8EE", roughness=0.05)
    s.mat("Receipt", "F4F0E8", roughness=0.6)
    y_f, yb = counter_shell(s, "Marble", "Teal", "Teal", "Brass", plinth_part="Brass", upright_part="Brass",
                            shelf_part="Marble", back_part="Marble")
    # customer face: 5 cream marble panels in gold frames on teal, a warm glowing strip under the top lip
    for x in (-3.06, -1.53, 0.0, 1.53, 3.06):
        s.box("Brass", (1.36, 0.05, 2.1), (x, y_f - 0.025, 1.55))
        s.box("Marble", (1.16, 0.08, 1.9), (x, y_f - 0.04, 1.55))
    s.box("Glow", (CW - 0.3, 0.05, 0.07), (0, y_f - 0.03, 2.73))
    # sculpted wing reliefs fanning in from the outer top corners (brass feathers with glowing ridges)
    for sx in (-1, 1):
        wing(s, "front", -y_f + 0.08, sx * 3.66, 2.5, -sx, (1.25, 1.2, 1.1, 0.95, 0.75), (-8, -24, -40, -56, -72),
             (0.26, 0.26, 0.24, 0.22, 0.2), thick=0.06, z_step=-0.06)
    # ends: marble panel in a gold frame
    for sx in (-1, 1):
        xf = sx * (CW / 2 - 0.1)
        s.box("Brass", (0.05, 1.8, 2.1), (xf + sx * 0.025, 0, 1.55))
        s.box("Marble", (0.08, 1.6, 1.9), (xf + sx * 0.04, 0, 1.55))
    # gold edge round the marble top (inside the 0.15 rim)
    for sy in (-1, 1):
        s.box("Brass", (CW + 0.24, 0.03, 0.07), (0, sy * (CD / 2 + 0.115), CH - 0.12))
    for sx in (-1, 1):
        s.box("Brass", (0.03, CD + 0.24, 0.07), (sx * (CW / 2 + 0.115), 0, CH - 0.12))
    # owner bays: cream-gold bags, a paper stack, gilded stock boxes, the drawer with green bills
    for x in (-3.0, -2.35):
        s.box("Paper", (0.5, 0.4, 0.75), (x, yb, 1.6 + 0.375))
    for k in range(5):
        s.box("Paper", (0.6, 0.5, 0.07), (-0.1 + (k % 2) * 0.04, yb, 1.64 + k * 0.08))
    for x in (-3.15, -2.15, -0.25, 2.05, 3.05):
        s.box("Brass", (0.8, 0.7, 0.55), (x, yb, 0.4 + 0.275))
        s.box("Marble", (0.3, 0.04, 0.15), (x, yb + 0.36, 0.85))
    s.box("Dark", (1.7, 0.9, 0.28), (2.65, yb, 2.6))
    for i in range(4):
        s.box("Bill" if i < 3 else "Brass", (0.32, 0.6, 0.03), (2.1 + i * 0.37, yb, 2.75))
    # white marble + gold register, gold keys, gold pole display with a warm glowing screen; teal tray; winged bell
    register_set(s, {"base": "Brass", "trim": "Brass", "body": "Marble", "deck": "Marble", "keys": "Brass",
                     "pole": "Brass", "frame": "Brass", "screen": "Glow", "drawer": "Marble", "tray": "Teal",
                     "inset": "Teal", "bellbase": "Marble", "bell": "Brass", "bill": "Bill", "collar": "Brass"})
    for sx in (-1, 1):  # the bell's little wings
        s.box("Brass", (0.3, 0.04, 0.12), (1.7 + sx * 0.3, 0.1, CH + 0.2), rot_y=sx * math.radians(25))
    return s.build()


def cashier_cosmic():
    s = Skin("CashierCosmic")
    cosmic_mats(s)
    s.mat("Bill", "6BAF6B", roughness=0.8)
    s.mat("Glass", "C9D8F0", roughness=0.05)
    s.mat("Receipt", "F4F0E8", roughness=0.6)
    # deep indigo frame, a magenta plinth (Nebula: colour-shifts in game), dark space top
    y_f, yb = counter_shell(s, "Space", "Void", "Space", "Brass", plinth_part="Nebula", back_part="Void")
    # customer face: three faceted nebula panels in gold filigree frames, starlight lines above and below
    for i, x in enumerate((-2.48, 0.0, 2.48)):
        nebula(s, "front", -y_f, x - 1.08, x + 1.08, 0.6, 2.5, 6, 5, seed=i + 11)
    for x in (-1.24, 1.24):
        s.box("Space", (0.3, 0.1, 2.3), (x, y_f - 0.05, 1.55))
    star_line(s, "front", -y_f, -3.7, 3.7, 2.7)
    star_line(s, "front", -y_f, -3.7, 3.7, 0.42)
    # ends: a nebula panel each
    for face in ("left", "right"):
        nebula(s, face, CW / 2 - 0.1, -0.8, 0.8, 0.6, 2.5, 4, 5, seed=21 if face == "left" else 23)
    # faceted ice-cyan crystal wings on the four outer corners (glow), inside the 0.15 rim
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (CW / 2 - 0.2), sy * (CD / 2 - 0.2)
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 1.55), 2.3, 0.4, d, 3)
            crystal(s, "Glow", (cx, cy - sy * 0.3, 1.1), 1.3, 0.28, (sx * 0.3, -sy * 0.95), 10)
            crystal(s, "Glow", (cx - sx * 0.3, cy, 1.2), 1.2, 0.26, (-sx * 0.95, sy * 0.3), 10)
    # starlight zone lines flush on the top (the slab is CH; inlays at CH keep it flat)
    for x0, x1 in ((-0.95, 1.2), (1.4, 3.9)):
        xm, w = (x0 + x1) / 2, x1 - x0
        for dy in (-0.95, 0.95):
            s.box("Star", (w, 0.05, 0.01), (xm, dy, CH - 0.005))
        for xx in (x0, x1):
            s.box("Star", (0.05, 1.95, 0.01), (xx, 0, CH - 0.005))
    # owner bays: star-patterned bags, crystal-clasped boxes, the drawer with green bills
    for x in (-3.0, -2.35):
        s.box("Violet", (0.5, 0.4, 0.75), (x, yb, 1.6 + 0.375))
        for dz in (0.2, 0.45):
            s.box("Brass", (0.08, 0.03, 0.08), (x - 0.1 + dz * 0.3, yb + 0.21, 1.6 + dz + 0.1), rot_y=math.radians(45))
    for k in range(5):
        s.box("Receipt", (0.6, 0.5, 0.07), (-0.1 + (k % 2) * 0.04, yb, 1.64 + k * 0.08))
    for x in (-3.15, -2.15, -0.25):
        s.box("Violet", (0.8, 0.7, 0.55), (x, yb, 0.4 + 0.275))
        s.box("Brass", (0.82, 0.72, 0.06), (x, yb, 0.62))
        crystal(s, "Glow", (x, yb + 0.37, 0.7), 0.24, 0.12, (0, 0), 0)
    s.box("Void", (1.7, 0.9, 0.28), (2.65, yb, 2.6))
    for i in range(4):
        s.box("Bill" if i < 3 else "Brass", (0.32, 0.6, 0.03), (2.1 + i * 0.37, yb, 2.75))
    # obsidian register with gold trim, glowing star keys, starlight screen, crystal fins; crystal tray; crystal bell
    register_set(s, {"base": "Void", "trim": "Brass", "body": "Void", "deck": "Space", "keys": "Star", "pole": "Brass",
                     "frame": "Void", "screen": "Star", "drawer": "Void", "tray": "Glow", "inset": "Space",
                     "bellbase": "Void", "bell": "Brass", "bill": "NebulaCore", "collar": "Brass"})
    for sx in (-1, 1):
        crystal(s, "Glow", (-2.3 + sx * 0.98, 0.0, CH + 0.5), 0.8, 0.22, (sx, 0), 15)
    crystal(s, "Glow", (1.7, 0.1, CH + 0.42), 0.22, 0.12, (0, 0), 0)  # crystal on the bell
    return s.build()


# ===== SAKURA STARLIGHT (Mythic; Sean's sheets "Sakura Starlight (1-3)") =====
# Blush marble, faceted rose-pink / berry-plum crystal panels with glowing diamond facets, gold filigree, rose-quartz
# crystal wings on the corners (glow). Each model also carries a hidden "Gem" (a cut pink diamond) that the game
# clones into the floating diamonds (look.gems in Config.Skins).

S_BLUSH, S_PINK, S_PLUM, S_GLOW, S_SOFT = "F8E8EE", "F49AC2", "5D3554", "FFD1E6", "F8C8DC"


def sakura_mats(s: Skin):
    s.mat("Marble", S_BLUSH, roughness=0.25)
    s.mat("Pink", S_PINK, roughness=0.2)
    s.mat("Soft", S_SOFT, roughness=0.2)
    s.mat("Plum", S_PLUM, roughness=0.35)
    s.mat("Brass", GOLD, metallic=0.9, roughness=0.3)
    s.mat("Glow", S_GLOW, emission=3.0)
    s.mat("Gem", "FF7EB9", emission=3.0)
    s.mat("Diamond", "FF5FAE", emission=3.0)  # glowing pink cut diamonds (Neon in game)
    s.mat("Ice", "FFE6F2", roughness=0.05)  # clear pale diamonds (Glass in game)


def gem(s: Skin, size: float, center):
    """A cut diamond (8 facets): pointed pavilion below, flat table on top. Hidden in the model; the game clones it."""
    r = size / 2
    o = c.lathe(f"{s.id}_Gem", [(0.0, -1.1 * r), (r, 0.0), (0.62 * r, 0.55 * r), (0.0, 0.55 * r)], steps=8)
    o.location = center
    s.add("Gem", o)


def cut_gem(s: Skin, part: str, size: float, center, facing: str = "up", tall: float = 1.0):
    """A cut diamond whose table (flat top) faces `facing` (up / down / front / back / left / right); tall stretches it
    along the vertical. On a face, its pointed back sinks into the body and only the crown stands out (0.55 x radius)."""
    r = size / 2
    o = c.lathe(f"{s.id}_{part}", [(0.0, -1.1 * r), (r, 0.0), (0.62 * r, 0.55 * r), (0.0, 0.55 * r)], steps=8)
    o.scale = (1, 1, tall) if facing in ("up", "down") else ((tall, 1, 1) if facing in ("left", "right") else (1, tall, 1))
    o.rotation_euler = {"up": (0, 0, math.radians(22.5)), "down": (math.pi, 0, 0), "front": (math.pi / 2, 0, 0),
                        "back": (-math.pi / 2, 0, 0), "left": (0, -math.pi / 2, 0), "right": (0, math.pi / 2, 0)}[facing]
    o.location = center
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    s.add(part, o)
    return o


def quad(s: Skin, part: str, pts, outward):
    """One flat 4-sided face (a diamond tile) facing `outward`."""
    p1, p2, p3 = pts[0], pts[1], pts[2]
    e1 = [p2[k] - p1[k] for k in range(3)]
    e2 = [p3[k] - p1[k] for k in range(3)]
    n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
    if n[0] * outward[0] + n[1] * outward[1] + n[2] * outward[2] < 0:
        pts = list(reversed(pts))
    me = bpy.data.meshes.new(f"{s.id}_{part}_quad")
    me.from_pydata([tuple(p) for p in pts], [], [(0, 1, 2, 3)])
    me.update()
    ob = bpy.data.objects.new(f"{s.id}_{part}", me)
    bpy.context.collection.objects.link(ob)
    s.add(part, ob)


def harlequin(s: Skin, face: str, plane: float, u0: float, u1: float, z0: float, z1: float, cols: int, rows: int,
              tiles=("Pink", "Soft"), medallion: float = 0.0, tall: float = 1.3):
    """A harlequin diamond panel: pink / blush diamond tiles on berry-plum, glowing studs where the tiles meet, a gold
    frame, and (medallion > 0) a big cut diamond on a gold diamond plate in the middle."""
    nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    lu, lz = u1 - u0, z1 - z0
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2

    def at(u, z, off):
        n = plane + off
        return (u, ny * n, z) if face in ("front", "back") else (nx * n, u, z)

    def flat(part, su, sz, u, z, off, rot=0.0):
        if face in ("front", "back"):
            s.box(part, (su, 0.04, sz), at(u, z, off), rot_y=rot)
        else:
            s.box(part, (0.04, su, sz), at(u, z, off), rot_x=rot)

    flat("Plum", lu, lz, um, zm, 0.02)
    w, h = lu / cols, lz / rows
    for i in range(cols):
        for j in range(rows):
            cu, cz = u0 + (i + 0.5) * w, z0 + (j + 0.5) * h
            k = 0.92
            pts = [at(cu - w / 2 * k, cz, 0.045), at(cu, cz + h / 2 * k, 0.045), at(cu + w / 2 * k, cz, 0.045),
                   at(cu, cz - h / 2 * k, 0.045)]
            quad(s, tiles[(i + j) % len(tiles)], pts, (nx, ny, 0))
    for i in range(1, cols):
        for j in range(rows):
            flat("Glow", 0.09, 0.09, u0 + i * w, z0 + (j + 0.5) * h, 0.05, math.radians(45))
    wf = 0.08
    for (u, z), (su, sz) in (((um, z0 - wf / 2), (lu + 2 * wf, wf)), ((um, z1 + wf / 2), (lu + 2 * wf, wf)),
                             ((u0 - wf / 2, zm), (wf, lz)), ((u1 + wf / 2, zm), (wf, lz))):
        flat("Brass", su, sz, u, z, 0.06)
    if medallion > 0:
        plate = medallion * 1.15
        flat("Brass", plate, plate * tall, um, zm, 0.07, math.radians(45))
        cut_gem(s, "Diamond", medallion, at(um, zm, 0.06), face, tall=tall)


def diamond_stack(s: Skin, x: float, y: float, sizes_z, parts=("Diamond", "Ice")):
    """A column of upright cut diamonds on a vertical corner (points down), alternating glowing pink and clear."""
    for k, (size, z) in enumerate(sizes_z):
        cut_gem(s, parts[k % len(parts)], size, (x, y, z), "up", tall=1.35)


def stud_row(s: Skin, face: str, plane: float, u0: float, u1: float, z: float, step: float = 0.6, size: float = 0.12):
    """Glowing diamond studs along a band."""
    nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    n = int((u1 - u0) / step)
    for i in range(n + 1):
        u = u0 + i * (u1 - u0) / max(1, n)
        if face in ("front", "back"):
            s.box("Glow", (size, 0.03, size), (u, ny * (plane + 0.02), z), rot_y=math.radians(45))
        else:
            s.box("Glow", (0.03, size, size), (nx * (plane + 0.02), u, z), rot_x=math.radians(45))


def sakura_part(seed: float, light: bool = False):
    """Rose-quartz facets: mostly pink, berry-plum shadows, blush highlights."""

    def pick(un, zn, k):
        v = math.sin(4.1 * un + 2.7 * zn + seed) + 0.5 * math.sin(6.3 * zn - 3.1 * un + seed * 1.9)
        if v > 0.9:
            return "Soft"
        if v < (-0.9 if light else -0.55):
            return "Plum"
        return "Pink"

    return pick


def sakura_panel(s: Skin, face: str, plane: float, u0: float, u1: float, z0: float, z1: float, cols: int, rows: int,
                 seed: int, light: bool = False, crosses: bool = False):
    """A faceted rose-quartz panel in a gold frame with glowing starlight diamond facets (and gold cross-stars)."""
    tri_panel(s, sakura_part(seed * 1.7, light), face, plane, u0, u1, z0, z1, cols, rows, seed)
    normal = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    w = 0.08
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2
    lu, lz = u1 - u0, z1 - z0
    pieces = [((um, z0 - w / 2), (lu + 2 * w, w)), ((um, z1 + w / 2), (lu + 2 * w, w)),
              ((u0 - w / 2, zm), (w, lz)), ((u1 + w / 2, zm), (w, lz))]
    if crosses:
        for cu, cz in ((u0 + 0.22, z0 + 0.22), (u1 - 0.22, z0 + 0.22), (u0 + 0.22, z1 - 0.22), (u1 - 0.22, z1 - 0.22)):
            pieces.append(((cu, cz), (0.24, 0.06)))
            pieces.append(((cu, cz), (0.06, 0.24)))
    nn = plane + 0.06
    for (cu, cz), (su, sz) in pieces:
        if face in ("front", "back"):
            s.box("Brass", (su, 0.05, sz), (cu, normal[1] * nn, cz))
        else:
            s.box("Brass", (0.05, su, sz), (normal[0] * nn, cu, cz))
    import random

    rng = random.Random(seed * 37)
    for _ in range(max(5, int(lu * lz * 2.2))):
        cu, cz = rng.uniform(u0 + 0.15, u1 - 0.15), rng.uniform(z0 + 0.15, z1 - 0.15)
        sz = rng.choice((0.07, 0.09, 0.13))
        if face in ("front", "back"):
            s.box("Glow", (sz, 0.03, sz), (cu, normal[1] * (plane + 0.04), cz), rot_y=math.radians(45))
        else:
            s.box("Glow", (0.03, sz, sz), (normal[0] * (plane + 0.04), cu, cz), rot_x=math.radians(45))


def sakura_spot(s: Skin, x: float, y: float, size: float):
    """An item spot on the top: glowing border round a soft-pink inlay with small diamond inlays on the corners."""
    b = 0.1
    half = size / 2 - b / 2
    for dx, dy, sx, sy in ((0, -half, size, b), (0, half, size, b), (-half, 0, b, size - 2 * b), (half, 0, b, size - 2 * b)):
        s.box("Glow", (sx, sy, 0.01), (x + dx, y + dy, TOP - 0.005))
    s.box("Soft", (size - 2 * b, size - 2 * b, 0.01), (x, y, TOP - 0.006))
    for cx in (-1, 1):
        for cy in (-1, 1):
            s.box("Diamond", (0.26, 0.26, 0.01), (x + cx * (half - 0.36), y + cy * (half - 0.36), TOP - 0.005),
                  rot_z=math.radians(45))


def filigree_gem(s: Skin, face: str, plane: float, u: float, z: float, flip: int = 1, size: float = 0.22):
    """The sheet's gold filigree ornament, as a jewellery setting: a small pink cut diamond on a gold diamond plate with
    short gold arms either side, slightly swept (flip = which way they sweep)."""
    nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    n = plane + 0.05
    plate = size * 1.9
    if face in ("front", "back"):
        s.box("Brass", (plate, 0.03, plate), (u, ny * n, z), rot_y=math.radians(45))
    else:
        s.box("Brass", (0.03, plate, plate), (nx * n, u, z), rot_x=math.radians(45))
    for du in (-1, 1):
        a = math.radians(12 * du * flip)
        cu = u + du * (plate * 0.5 + 0.18)
        if face in ("front", "back"):
            s.box("Brass", (0.36, 0.03, 0.05), (cu, ny * n, z), rot_y=-a)
            s.box("Glow", (0.07, 0.03, 0.07), (u + du * (plate * 0.5 + 0.4), ny * (n + 0.005), z - flip * du * 0.0),
                  rot_y=math.radians(45))
        else:
            s.box("Brass", (0.03, 0.36, 0.05), (nx * n, cu, z), rot_x=a)
            s.box("Glow", (0.03, 0.07, 0.07), (nx * (n + 0.005), u + du * (plate * 0.5 + 0.4), z),
                  rot_x=math.radians(45))
    center = (u, ny * (plane + 0.05), z) if face in ("front", "back") else (nx * (plane + 0.05), u, z)
    cut_gem(s, "Diamond", size, center, face, tall=1.3)


def starlight_gems(s: Skin, face: str, plane: float, u0: float, u1: float, z0: float, z1: float, count: int, seed: int):
    """A few small cut diamonds set into a faceted panel (the sheet's starlight diamond facets), pink and clear."""
    import random

    rng = random.Random(seed * 53)
    for k in range(count):
        u = rng.uniform(u0 + 0.3, u1 - 0.3)
        z = rng.uniform(z0 + 0.3, z1 - 0.3)
        size = rng.choice((0.18, 0.22, 0.28))
        nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
        center = (u, ny * (plane + 0.04), z) if face in ("front", "back") else (nx * (plane + 0.04), u, z)
        cut_gem(s, "Diamond" if k % 3 else "Ice", size, center, face, tall=1.2)


def gem_cluster(s: Skin, face: str, plane: float, u: float, z: float, big: float, tall: float, side: float = 0.0,
                side_gap: float = 0.0, setting: float = 0.18, setting_gap: float = 1.1):
    """The pedestal's centrepiece, for any face: a tall faceted rose-quartz gem with a gold diamond setting above and
    below it, and (side > 0) a smaller tall gem either side, like a jewellery cluster."""
    nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]

    def at(uu, zz):
        n = plane + 0.05
        return (uu, ny * n, zz) if face in ("front", "back") else (nx * n, uu, zz)

    cut_gem(s, "Diamond", big, at(u, z), face, tall=tall)
    if side > 0:
        for du in (-1, 1):
            cut_gem(s, "Ice", side, at(u + du * side_gap, z), face, tall=tall * 0.8)
    filigree_gem(s, face, plane, u, z + setting_gap, flip=1, size=setting)
    filigree_gem(s, face, plane, u, z - setting_gap, flip=-1, size=setting)


def spire(s: Skin, x: float, y: float, base_z: float, height: float, width: float):
    """A crystal spire ("antenna") rising from a top corner: a gold collar, a tall thin rose-quartz crystal (glow), a
    smaller one leaning outward beside it, and a glowing pink cut diamond on the tip. Stands on the corner, clear of
    the item spots; the footprint rule still holds (it is inside the corner)."""
    s.box("Brass", (width * 1.6, width * 1.6, 0.12), (x, y, base_z + 0.06))
    crystal(s, "Glow", (x, y, base_z + height / 2), height, width, (0, 0), 0)
    out = (1 if x > 0 else -1, 1 if y > 0 else -1)
    crystal(s, "Glow", (x - out[0] * 0.08, y - out[1] * 0.08, base_z + height * 0.3), height * 0.5, width * 0.7,
            (out[0] * 0.7, out[1] * 0.7), 14)
    s.box("Brass", (width * 0.9, width * 0.9, 0.06), (x, y, base_z + height * 0.78))  # a gold ring up the spire
    cut_gem(s, "Diamond", width * 1.3, (x, y, base_z + height + width * 0.5), "down", tall=1.4)


def jewel_pillar(s: Skin, face: str, plane: float, u: float, z0: float, z1: float, part: str, width: float, count: int):
    """A pillar between panels: a gold strip down its middle set with small pink cut diamonds."""
    nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
    zm, h = (z0 + z1) / 2, z1 - z0
    s.box(part, (width, 0.1, h), (u, ny * (plane + 0.05), zm))
    s.box("Brass", (0.08, 0.03, h - 0.2), (u, ny * (plane + 0.11), zm))
    for k in range(count):
        zz = z0 + (k + 0.5) * h / count
        cut_gem(s, "Diamond", 0.17, (u, ny * (plane + 0.11), zz), face, tall=1.3)


def shelf_sakura():
    s = Skin("ShelfSakura")
    sakura_mats(s)
    L, D = 11.2, 4.2
    s.box("Marble", (L, D, 0.42), (0, 0, 0.21))
    s.box("Brass", (L - 0.2, D - 0.2, 0.08), (0, 0, 0.46))
    s.box("Plum", (L - 1.0, D - 0.4, 3.1), (0, 0, 0.5 + 3.1 / 2))
    s.box("Brass", (L - 0.2, D - 0.2, 0.09), (0, 0, 3.645))
    s.box("Marble", (L, D, 0.5), (0, 0, 3.69 + 0.5 / 2))  # 4.19; the flush spots make the top exactly 4.2
    for x in (-3.5, 0.0, 3.5):
        sakura_spot(s, x, 0.0, 2.8)
    fy = (D - 0.4) / 2
    # front: three faceted rose-quartz panels, each with the pedestal's gem cluster in the middle (Sean loved it)
    for i, x in enumerate((-3.55, 0.0, 3.55)):
        sakura_panel(s, "front", fy, x - 1.4, x + 1.4, 0.8, 3.25, 7, 6, seed=i + 31)
        gem_cluster(s, "front", fy, x, 2.02, 0.66, 2.5, side=0.4, side_gap=0.78, setting_gap=1.05)
    for x in (-1.775, 1.775):  # blush marble pillars set with a gold strip and small diamonds
        jewel_pillar(s, "front", fy, x, 0.55, 3.55, "Marble", 0.42, 4)
    stud_row(s, "front", (D - 0.2) / 2, -5.3, 5.3, 3.645, step=0.5, size=0.1)  # diamond studs on the top band
    stud_row(s, "front", (D - 0.2) / 2, -5.3, 5.3, 0.46, step=0.5, size=0.1)  # and on the plinth band
    for face in ("left", "right"):  # ends: marble panel in a gold frame with a single tall gem + settings
        x = (L - 1.0) / 2
        sx = -1 if face == "left" else 1
        s.box("Brass", (0.05, 3.0, 2.55), (sx * (x + 0.025), 0, 2.03))
        s.box("Marble", (0.08, 2.8, 2.35), (sx * (x + 0.04), 0, 2.03))
        gem_cluster(s, face, x + 0.04, 0.0, 2.02, 0.56, 2.4, setting=0.16, setting_gap=0.95)
    s.box("Plum", (L - 1.2, 0.06, 2.6), (0, fy + 0.03, 2.05))  # back (against the wall)
    for sx in (-1, 1):  # rose-quartz crystal wings on the four vertical corners (glow)
        for sy in (-1, 1):
            cx, cy = sx * (L / 2 - 0.42), sy * (D / 2 - 0.36)
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 2.3), 3.0, 0.6, d, 4)
            crystal(s, "Glow", (cx, cy - sy * 0.42, 1.75), 1.9, 0.42, (sx * 0.3, -sy * 0.95), 12)
            crystal(s, "Glow", (cx - sx * 0.45, cy, 1.85), 1.7, 0.4, (-sx * 0.95, sy * 0.3), 12)
    for sx in (-1, 1):  # crystal spires ("antennae") on the four top corners, clear of the item spots
        for sy in (-1, 1):
            spire(s, sx * (L / 2 - 0.3), sy * (D / 2 - 0.3), TOP, 1.3, 0.26)
    gem(s, 1.0, (0, 0, 2.0))  # hidden inside the body
    return s.build()


def pedestal_sakura():
    s = Skin("PedestalSakura")
    sakura_mats(s)
    W = 2.8
    s.box("Marble", (W, W, 0.42), (0, 0, 0.21))
    s.box("Brass", (2.6, 2.6, 0.1), (0, 0, 0.47))
    s.box("Plum", (2.3, 2.3, 2.9), (0, 0, 0.52 + 2.9 / 2))
    s.box("Brass", (2.55, 2.55, 0.1), (0, 0, 3.47))
    s.box("Marble", (W, W, 0.67), (0, 0, 3.52 + 0.67 / 2))  # 4.19
    sakura_spot(s, 0.0, 0.0, 2.8)
    for k, face in enumerate(("front", "back", "left", "right")):
        sakura_panel(s, face, 1.15, -0.62, 0.62, 0.75, 3.3, 3, 6, seed=k + 41)
        # the sheet's tall faceted rose-quartz gem in the middle of each side, gold filigree diamonds above and below
        nx, ny = {"front": (0, -1), "back": (0, 1), "left": (-1, 0), "right": (1, 0)}[face]
        n = 1.15 + 0.05
        center = (0, ny * n, 2.02) if face in ("front", "back") else (nx * n, 0, 2.02)
        cut_gem(s, "Diamond", 0.62, center, face, tall=2.7)
        filigree_gem(s, face, 1.15, 0.0, 3.12, flip=1, size=0.18)
        filigree_gem(s, face, 1.15, 0.0, 0.92, flip=-1, size=0.18)
    for sx in (-1, 1):  # rose-quartz crystal wings hugging the four vertical edges (glow)
        for sy in (-1, 1):
            cx, cy = sx * 1.16, sy * 1.16
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 2.2), 2.4, 0.46, d, 4)
            crystal(s, "Glow", (cx, cy - sy * 0.3, 1.5), 1.3, 0.3, (sx * 0.3, -sy * 0.95), 12)
            crystal(s, "Glow", (cx - sx * 0.3, cy, 1.6), 1.2, 0.28, (-sx * 0.95, sy * 0.3), 12)
    for sx in (-1, 1):  # crystal spires ("antennae") on the four top corners, clear of the item in the middle
        for sy in (-1, 1):
            spire(s, sx * 1.22, sy * 1.22, TOP, 0.9, 0.2)
    gem(s, 0.6, (0, 0, 2.0))
    return s.build()


def cashier_sakura():
    s = Skin("CashierSakura")
    sakura_mats(s)
    s.mat("RoseGold", "B76E79", metallic=0.85, roughness=0.3)
    s.mat("Cream", "F4E6D6", roughness=0.5)
    s.mat("Bill", "6BAF6B", roughness=0.8)
    s.mat("Glass", "F6C6DA", roughness=0.05)
    s.mat("Receipt", "F4F0E8", roughness=0.6)
    s.mat("Dark", "3A2236", roughness=0.6)
    y_f, yb = counter_shell(s, "Marble", "Plum", "Plum", "Brass", plinth_part="Dark", shelf_part="RoseGold")
    # front: faceted pink + blush panels with cross-stars, each with the pedestal's gem cluster in the middle
    for i, x in enumerate((-2.48, 0.0, 2.48)):
        sakura_panel(s, "front", -y_f, x - 1.08, x + 1.08, 0.6, 2.5, 6, 5, seed=i + 51, light=True, crosses=True)
        gem_cluster(s, "front", -y_f, x, 1.55, 0.5, 2.4, side=0.32, side_gap=0.58, setting=0.14, setting_gap=0.78)
    for x in (-1.24, 1.24):  # plum pillars set with a gold strip and small diamonds
        jewel_pillar(s, "front", -y_f, x, 0.4, 2.7, "Plum", 0.3, 3)
    stud_row(s, "front", CD / 2 - 0.03, -3.8, 3.8, 0.33, step=0.45, size=0.1)  # diamond studs on the plinth line
    for face in ("left", "right"):
        sakura_panel(s, face, CW / 2 - 0.1, -0.8, 0.8, 0.6, 2.5, 4, 5, seed=61 if face == "left" else 63, light=True)
        gem_cluster(s, face, CW / 2 - 0.1, 0.0, 1.55, 0.42, 2.3, setting=0.13, setting_gap=0.76)
    # glowing thin rim borders round the top (inside the 0.15 rim)
    for sy in (-1, 1):
        s.box("Glow", (CW + 0.24, 0.03, 0.06), (0, sy * (CD / 2 + 0.115), CH - 0.12))
    for sx in (-1, 1):
        s.box("Glow", (0.03, CD + 0.24, 0.06), (sx * (CW / 2 + 0.115), 0, CH - 0.12))
    for sx in (-1, 1):  # rose-quartz crystal wing shards on the outer corners
        for sy in (-1, 1):
            cx, cy = sx * (CW / 2 - 0.2), sy * (CD / 2 - 0.2)
            d = (sx * 0.7071, sy * 0.7071)
            crystal(s, "Glow", (cx, cy, 1.55), 2.3, 0.4, d, 3)
            crystal(s, "Glow", (cx, cy - sy * 0.3, 1.1), 1.3, 0.28, (sx * 0.3, -sy * 0.95), 10)
            crystal(s, "Glow", (cx - sx * 0.3, cy, 1.2), 1.2, 0.26, (-sx * 0.95, sy * 0.3), 10)
    # owner bays: pink-gold gift bags, a paper stack, crystal-clasped boxes, drawer with green bills
    for x, part in ((-3.0, "Pink"), (-2.35, "RoseGold")):
        s.box(part, (0.5, 0.4, 0.75), (x, yb, 1.6 + 0.375))
    for k in range(5):
        s.box("Receipt", (0.6, 0.5, 0.07), (-0.1 + (k % 2) * 0.04, yb, 1.64 + k * 0.08))
    for x in (-3.15, -2.15, -0.25):
        s.box("Plum", (0.8, 0.7, 0.55), (x, yb, 0.4 + 0.275))
        s.box("RoseGold", (0.82, 0.72, 0.06), (x, yb, 0.62))
        cut_gem(s, "Diamond", 0.2, (x, yb + 0.36, 0.62), "back")
    s.box("RoseGold", (1.7, 0.9, 0.28), (2.65, yb, 2.6))
    for i in range(4):
        s.box("Bill" if i < 3 else "Brass", (0.32, 0.6, 0.03), (2.1 + i * 0.37, yb, 2.75))
    # rose-gold + cream register with gold star keys and a glowing pink screen, crystal fins; pink crystal tray
    register_set(s, {"base": "RoseGold", "trim": "Brass", "body": "Cream", "deck": "RoseGold", "keys": "Brass",
                     "pole": "RoseGold", "frame": "RoseGold", "screen": "Glow", "drawer": "RoseGold", "tray": "Pink",
                     "inset": "Soft", "bellbase": "Cream", "bell": "RoseGold", "bill": "Bill", "collar": "RoseGold"})
    for sx in (-1, 1):
        crystal(s, "Glow", (-2.3 + sx * 0.98, 0.0, CH + 0.5), 0.8, 0.22, (sx, 0), 15)
    cut_gem(s, "Diamond", 0.3, (-2.3, -0.55, CH + 0.55), "front")  # a diamond set in the register face
    for dx, part in ((-0.2, "Diamond"), (0.05, "Ice"), (0.3, "Diamond")):  # diamonds in the change tray
        cut_gem(s, part, 0.18, (0.3 + dx, 0.1 + dx * 0.3, CH + 0.16), "up")
    cut_gem(s, "Diamond", 0.16, (1.7, 0.1, CH + 0.45), "up")  # on the bell
    for k, (dx, dy, dz) in enumerate(((0, 0, 0.12), (0.1, 0.08, 0.2), (-0.1, -0.05, 0.22), (0.02, -0.1, 0.32))):
        cut_gem(s, "Diamond" if k % 2 == 0 else "Ice", 0.16, (3.15 + dx, -0.4 + dy, CH + dz), "up")  # tip jar
    for sx in (-1, 1):  # crystal spires ("antennae") on the four top corners
        for sy in (-1, 1):
            spire(s, sx * (CW / 2 - 0.2), sy * (CD / 2 - 0.2), CH, 1.1, 0.22)
    gem(s, 0.8, (0, -0.5, 1.5))
    return s.build()


BUILDERS = {
    "ShelfSakura": shelf_sakura,
    "PedestalSakura": pedestal_sakura,
    "CashierSakura": cashier_sakura,
    "CashierRunic": cashier_runic,
    "CashierClassic": cashier_classic,
    "CashierCelestial": cashier_celestial,
    "CashierCosmic": cashier_cosmic,
    "ShelfRunic": shelf_runic,
    "PedestalRunic": pedestal_runic,
    "ShelfCelestial": shelf_celestial,
    "PedestalCelestial": pedestal_celestial,
    "ShelfCosmic": shelf_cosmic,
    "PedestalCosmic": pedestal_cosmic,
}


# ===== preview + export =====

def render_preview(path: str, objs, kind: str):
    import mathutils

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 760
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.93, 0.89, 0.8, 1)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o, do_unlink=True)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.collection.objects.link(cam)
    size = 11.2 if kind == "Shelf" else 2.8
    dist = {"Shelf": 12.5, "Cashier": 10.5}.get(kind, 7.5)
    cam.location = (dist * 0.6, -dist, 2.1 + dist * 0.45)
    target = mathutils.Vector((0, 0, 2.0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 55 if kind == "Pedestal" else 50
    scene.camera = cam
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in objs
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    _ = size


def main():
    c.reset_scene()
    wanted = os.environ.get("DF_SKINS")
    ids = [i.strip() for i in wanted.split(",")] if wanted else list(BUILDERS)
    preview_dir = os.environ.get("DF_PREVIEW_DIR") or os.path.join(c.OUT_PREVIEWS, "skins")
    os.makedirs(preview_dir, exist_ok=True)
    built = {}
    for i, sid in enumerate(ids):
        objs = BUILDERS[sid]()
        # spread skins out so a kept .blend shows them side by side (export re-centres nothing: each skin is its own group)
        built[sid] = objs
        tris = c.triangle_count(objs)
        lo = [min((o.matrix_world @ v.co)[k] for o in objs for v in o.data.vertices) for k in range(3)]
        hi = [max((o.matrix_world @ v.co)[k] for o in objs for v in o.data.vertices) for k in range(3)]
        print(f"SKIN {sid}: {len(objs)} objects, {tris} triangles, size x {hi[0]-lo[0]:.2f} y {hi[1]-lo[1]:.2f} z {lo[2]:.2f}..{hi[2]:.3f}")
    for sid, objs in built.items():
        kind = "Shelf" if sid.startswith("Shelf") else ("Cashier" if sid.startswith("Cashier") else "Pedestal")
        render_preview(os.path.join(preview_dir, sid + ".png"), objs, kind)
    if os.environ.get("DF_EXPORT"):
        allobjs = [o for objs in built.values() for o in objs]
        c.export_glb(os.path.join(c.OUT_MODELS, "Skins.glb"), allobjs)
        print("EXPORTED", os.path.join(c.OUT_MODELS, "Skins.glb"))
    keep = os.environ.get("DF_KEEP")
    if keep:
        # lay the skins out side by side for hand editing
        x = 0.0
        for sid, objs in built.items():
            for o in objs:
                o.location.x += x
            x += 14.0 if not sid.startswith("Pedestal") else 5.0
        bpy.ops.wm.save_as_mainfile(filepath=keep)
        print("SAVED", keep)
    print("done")


main()
