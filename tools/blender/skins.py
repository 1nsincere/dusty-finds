"""Dusty Finds: shelf and pedestal skins (Blender 5.x, headless). Built from Sean's design sheets (assets/skin-designs).

Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/skins.py
Env:
  DF_SKINS        comma list of skin ids to build (default: all)
  DF_PREVIEW_DIR  where preview PNGs go (default assets/previews/skins)
  DF_EXPORT=1     also export assets/models/Skins.glb (the selected skins)
  DF_KEEP=path    save the built scene as a .blend (to open and tweak by hand)

Rules (docs/10, Studio contract): 1 Blender unit = 1 stud. Origin = bottom centre, front faces -Y, Z up.
  Shelf    11.2 (X) x 4.2 (Y) x 4.2 (Z)      Pedestal 2.8 x 2.8 x 4.2
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


BUILDERS = {
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
    dist = 12.5 if kind == "Shelf" else 7.5
    cam.location = (dist * 0.6, -dist, 2.1 + dist * 0.45)
    target = mathutils.Vector((0, 0, 2.0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50 if kind == "Shelf" else 55
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
        kind = "Shelf" if sid.startswith("Shelf") else "Pedestal"
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
            x += 14.0 if sid.startswith("Shelf") else 5.0
        bpy.ops.wm.save_as_mainfile(filepath=keep)
        print("SAVED", keep)
    print("done")


main()
