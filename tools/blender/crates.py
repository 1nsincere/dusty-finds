"""Dusty Finds: the six supply crates (Blender 5.x, headless). Built from Sean's design sheet assets/crate-designs/Crate Designs.jfif.

Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/crates.py
Env:
  DF_CRATES       comma list of crate ids to build (default: all six)
  DF_PREVIEW_DIR  where preview PNGs go (default assets/previews/crates)
  DF_EXPORT=1     also export assets/models/Crates.glb (one empty per crate, its meshes under it)
  DF_KEEP=path    save the built scene as a .blend (to open and tweak by hand)

Rules (same as tools/blender/skins.py): 1 Blender unit = 1 stud, origin = bottom centre, front faces -Y, Z up.
One object per colour per crate, named <CrateId>_<Part> (Studio colours MeshParts by that name; Glow -> Neon).
Sizes climb with the price (Sean's sheet): Free 1.9 wide .. Estate 3.0 wide; nothing wider than 3.0 (boxes at the door
sit 3.2 studs apart, DiscoveryController BOX_SPACING). The body box height is written to the template's Body part in Studio.
Crate ids = the boxModel names in Config/Crates.luau.
"""

import math
import os
import random
import sys

import bmesh
import bpy
import mathutils

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

FONTS_DIR = "C:/Windows/Fonts"
FONT_FILES = {
    "marker": "comicbd.ttf",  # hand-written marker (Yard Sale)
    "stencil": "STENCIL.TTF",  # stencilled paint (Starter)
    "stamp": "impact.ttf",  # rubber stamp (Free)
    "painted": "segoeprb.ttf",  # hand-painted sign (Flea Market)
    "serif": "georgiab.ttf",  # old-fashioned serif (Antique tag, Estate plate)
}
_fonts = {}

# Body box sizes (W, D, H) per crate: Studio's invisible Body part uses these (placement at the door reads Body.Size.Y)
BODY = {
    "CrateFree": (1.9, 1.7, 1.45),
    "CrateStarter": (2.4, 1.9, 1.35),
    "CrateYardSale": (2.3, 2.0, 1.9),
    "CrateFlea": (2.6, 2.3, 2.1),
    "CrateAntique": (2.6, 2.4, 2.3),
    "CrateEstate": (3.0, 2.1, 1.55),
}


def font(kind: str):
    if kind not in _fonts:
        path = os.path.join(FONTS_DIR, FONT_FILES[kind])
        _fonts[kind] = bpy.data.fonts.load(path) if os.path.exists(path) else None
    return _fonts[kind]


def hexmat(name: str, hexstr: str, emission: float = 0.0, metallic: float = 0.0, roughness: float = 0.65):
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


def _select_only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def _apply_mods(o):
    _select_only(o)
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _bevel(o, width: float, segments: int = 2):
    if width <= 0:
        return
    mod = o.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    _apply_mods(o)


def face_point(u: float, v: float, tilt: float, center):
    """A point on a front (-Y) face: u along X, v along Z, rotated by `tilt` (radians, about Y) around `center`."""
    cx, cy, cz = center
    x = u * math.cos(tilt) + v * math.sin(tilt)
    z = -u * math.sin(tilt) + v * math.cos(tilt)
    return (cx + x, cy, cz + z)


class Crate:
    """Collects shapes per colour part and joins each part into one object named <id>_<Part>."""

    def __init__(self, crate_id: str):
        self.id = crate_id
        self.groups = {}
        self.mats = {}
        self.n = 0

    def mat(self, part: str, hexstr: str, **kw):
        self.mats[part] = (hexstr, kw)

    def _name(self, part):
        self.n += 1
        return f"{self.id}_{part}_{self.n}"

    def add(self, part: str, obj):
        self.groups.setdefault(part, []).append(obj)
        return obj

    def box(self, part, size, center, rot=(0.0, 0.0, 0.0), bevel: float = 0.0, segments: int = 2):
        o = c.box(self._name(part), size, (0, 0, 0))
        _bevel(o, bevel, segments)
        o.rotation_euler = rot
        o.location = center
        return self.add(part, o)

    def cyl(self, part, radius, depth, center, rot=(0.0, 0.0, 0.0), verts: int = 16, bevel: float = 0.0, scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=(0, 0, 0))
        o = bpy.context.active_object
        o.name = self._name(part)
        o.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        _bevel(o, bevel, 1)
        o.rotation_euler = rot
        o.location = center
        return self.add(part, o)

    def ball(self, part, radius, center, scale=(1, 1, 1), rot=(0.0, 0.0, 0.0), segments: int = 12, rings: int = 8):
        o = c.sphere(self._name(part), radius, (0, 0, 0), scale, segments, rings)
        bpy.ops.object.shade_smooth()
        o.rotation_euler = rot
        o.location = center
        return self.add(part, o)

    def ring(self, part, major, minor, center, rot=(0.0, 0.0, 0.0), scale=(1, 1, 1), major_seg: int = 20, minor_seg: int = 6):
        o = c.torus(self._name(part), major, minor, (0, 0, 0), (0, 0, 0), major_seg, minor_seg)
        o.scale = scale
        _select_only(o)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bpy.ops.object.shade_smooth()
        o.rotation_euler = rot
        o.location = center
        return self.add(part, o)

    def lathe(self, part, profile, center, steps: int = 20, rot=(0.0, 0.0, 0.0)):
        o = c.lathe(self._name(part), profile, steps)
        _select_only(o)
        bpy.ops.object.shade_smooth()
        o.rotation_euler = rot
        o.location = center
        return self.add(part, o)

    def text(self, part, body, kind, size, center, tilt: float = 0.0, extrude: float = 0.014, side: float = 0.0, line: float = 0.85):
        """Raised lettering on a face. Default = the front (-Y) face; side = extra turn about Z (pi/2 = the +X face)."""
        cu = bpy.data.curves.new(self._name(part), "FONT")
        cu.body = body
        f = font(kind)
        if f:
            cu.font = f
        cu.size = size
        cu.extrude = extrude
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.space_line = line
        cu.resolution_u = 2
        o = bpy.data.objects.new(cu.name, cu)
        bpy.context.collection.objects.link(o)
        _select_only(o)
        bpy.ops.object.convert(target="MESH")
        o = bpy.context.active_object
        o.rotation_euler = (math.pi / 2, tilt, side)
        o.location = center
        return self.add(part, o)

    def frame(self, part, w, h, thick, depth, center, tilt: float = 0.0):
        """A rectangle outline on a front face (stamp border, buckle)."""
        for u, v, sw, sh in ((0, h / 2, w, thick), (0, -h / 2, w, thick), (-w / 2, 0, thick, h), (w / 2, 0, thick, h)):
            self.box(part, (sw, depth, sh), face_point(u, v, tilt, center), rot=(0, tilt, 0))

    def stripe_line(self, part_a, part_b, p0, p1, thick: float = 0.035, seg: float = 0.09):
        """Red-and-white twine: a straight line of short alternating blocks from p0 to p1."""
        a, b = mathutils.Vector(p0), mathutils.Vector(p1)
        d = b - a
        n = max(1, int(d.length / seg))
        q = d.to_track_quat("Z", "Y").to_euler()
        for i in range(n):
            m = a + d * ((i + 0.5) / n)
            self.box(part_a if i % 2 == 0 else part_b, (thick, thick, d.length / n), tuple(m), rot=tuple(q))

    def stick(self, part, p0, p1, thick):
        a, b = mathutils.Vector(p0), mathutils.Vector(p1)
        d = b - a
        q = d.to_track_quat("Z", "Y").to_euler()
        return self.box(part, (thick, thick, d.length), tuple((a + b) / 2), rot=tuple(q))

    def build(self):
        out = []
        for part, objs in self.groups.items():
            obj = c.join(objs, f"{self.id}_{part}") if len(objs) > 1 else objs[0]
            _select_only(obj)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            obj.name = f"{self.id}_{part}"
            obj.data.name = obj.name + "_mesh"
            hexstr, kw = self.mats[part]
            obj.data.materials.clear()
            obj.data.materials.append(hexmat(f"{self.id}_{part}_mat", hexstr, **kw))
            out.append(obj)
        bpy.ops.object.select_all(action="DESELECT")
        return out


def half_dome(name: str, length: float, radius: float, zscale: float, segs: int = 16):
    """A half cylinder along X (a steamer-trunk lid): flat at z = 0, arched up to radius * zscale, capped at both ends."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    ends = []
    for x in (-length / 2, length / 2):
        ring = []
        for i in range(segs + 1):
            a = math.pi * i / segs
            ring.append(bm.verts.new((x, radius * math.cos(a), radius * math.sin(a) * zscale)))
        ends.append(ring)
    for i in range(segs):
        bm.faces.new((ends[0][i], ends[1][i], ends[1][i + 1], ends[0][i + 1]))
    bm.faces.new(ends[0])
    bm.faces.new(list(reversed(ends[1])))
    bm.faces.new((ends[0][0], ends[0][segs], ends[1][segs], ends[1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return obj


# ===== 1. FREE DELIVERY BOX: small, plain, well-travelled cardboard parcel =====

def crate_free():
    s = Crate("CrateFree")
    s.mat("Body", "B98A5A", roughness=0.9)
    s.mat("Tape", "E8D9B0", roughness=0.5)
    s.mat("Label", "FFFFFF", roughness=0.7)
    s.mat("Ink", "4A3B30", roughness=0.8)
    s.mat("Stamp", "1FC2A5", roughness=0.7)
    W, D, H = BODY["CrateFree"]
    fy = -D / 2
    s.box("Body", (W, D, H), (0, 0, H / 2), bevel=0.09)
    # packing tape: a cross on top that runs down the front and both sides
    s.box("Tape", (W + 0.02, 0.36, 0.02), (0, 0.05, H + 0.005))
    for sx in (-1, 1):
        s.box("Tape", (0.02, 0.36, 0.5), (sx * (W / 2 + 0.006), 0.05, H - 0.25))
    s.box("Tape", (0.34, D + 0.02, 0.02), (0.18, 0, H + 0.012))
    s.box("Tape", (0.34, 0.02, 0.45), (0.18, fy - 0.006, H - 0.225))
    # shipping label with a tiny truck and two address lines
    lx, lz = -0.52, H - 0.33
    s.box("Label", (0.56, 0.02, 0.34), (lx, fy - 0.012, lz), bevel=0.01, segments=1)
    s.box("Ink", (0.15, 0.012, 0.09), (lx - 0.12, fy - 0.024, lz + 0.03))
    s.box("Ink", (0.07, 0.012, 0.07), (lx - 0.01, fy - 0.024, lz + 0.02))
    for wx in (-0.17, -0.04):
        s.cyl("Ink", 0.025, 0.012, (lx + wx, fy - 0.024, lz - 0.04), rot=(math.pi / 2, 0, 0), verts=8)
    for i, w in enumerate((0.16, 0.12)):
        s.box("Ink", (w, 0.012, 0.025), (lx + 0.14, fy - 0.024, lz + 0.05 - i * 0.07))
    # the teal FREE stamp, a little crooked, with its border
    tilt = -0.16  # leans up to the right, like a hand-pressed stamp
    sc = (-0.05, fy - 0.014, 0.55)
    s.text("Stamp", "FREE", "stamp", 0.42, sc, tilt=tilt, extrude=0.008)
    s.frame("Stamp", 1.12, 0.54, 0.05, 0.016, sc, tilt=tilt)
    # a little delivery truck with speed lines, bottom right
    tx, tz = 0.62, 0.24
    s.box("Stamp", (0.26, 0.016, 0.15), (tx, fy - 0.014, tz + 0.02))
    s.box("Stamp", (0.11, 0.016, 0.11), (tx + 0.19, fy - 0.014, tz))
    for wx in (-0.07, 0.17):
        s.cyl("Stamp", 0.04, 0.016, (tx + wx, fy - 0.014, tz - 0.08), rot=(math.pi / 2, 0, 0), verts=10)
    for i in range(3):
        s.box("Stamp", (0.12 - i * 0.02, 0.016, 0.022), (tx - 0.25 - i * 0.02, fy - 0.014, tz + 0.06 - i * 0.05))
    return s.build()


# ===== 2. STARTER CRATE: open pine slat crate, rope handles, mint STARTER plank, duck + teacup in newspaper =====

def crate_starter():
    s = Crate("CrateStarter")
    s.mat("Body", "D9B47A", roughness=0.8)
    s.mat("Post", "C49A5E", roughness=0.8)
    s.mat("Rope", "C9A26B", roughness=0.9)
    s.mat("Mint", "7FD8B5", roughness=0.7)
    s.mat("Paint", "F4F0E8", roughness=0.7)
    s.mat("Paper", "EDE6D6", roughness=0.9)
    s.mat("Ink", "8A8478", roughness=0.9)
    s.mat("Duck", "FFD43B", roughness=0.45)
    s.mat("Beak", "F28C28", roughness=0.5)
    s.mat("Cup", "FFFFFF", roughness=0.3)
    s.mat("Eye", "2B1A12", roughness=0.4)
    W, D, H = BODY["CrateStarter"]
    s.box("Body", (W - 0.1, D - 0.1, 0.1), (0, 0, 0.05))
    for sx in (-1, 1):
        for sy in (-1, 1):
            s.box("Post", (0.18, 0.18, H), (sx * (W / 2 - 0.09), sy * (D / 2 - 0.09), H / 2), bevel=0.03)
    rows = (0.22, 0.67, 1.12)
    for z in rows:
        for sy in (-1, 1):
            if sy == -1 and z == 0.67:
                continue  # the mint STARTER plank goes here
            s.box("Body", (W - 0.3, 0.08, 0.36), (0, sy * (D / 2 - 0.06), z), bevel=0.02)
        for sx in (-1, 1):
            s.box("Body", (0.08, D - 0.3, 0.36), (sx * (W / 2 - 0.06), 0, z), bevel=0.02)
    s.box("Mint", (W - 0.26, 0.11, 0.38), (0, -(D / 2 - 0.03), 0.67), bevel=0.02)
    s.text("Paint", "STARTER", "stencil", 0.27, (0, -D / 2 - 0.03, 0.66), extrude=0.01)
    # rope loop handles on both short sides
    for sx in (-1, 1):
        s.ring("Rope", 0.2, 0.045, (sx * (W / 2 + 0.05), 0, 0.92), rot=(0, math.pi / 2, 0), scale=(1, 1.25, 1))
    # crumpled newspaper filling the top, two sheets standing up at the back with print lines
    rnd = random.Random(7)
    for i in range(6):
        x = -W / 2 + 0.35 + (W - 0.7) * (i % 3) / 2 + rnd.uniform(-0.1, 0.1)
        y = -D / 2 + 0.4 + (D - 0.8) * (i // 3) / 2 + rnd.uniform(-0.08, 0.08)
        s.ball("Paper", 0.26, (x, y, H - 0.05), scale=(1.1, 0.9, 0.6), rot=(rnd.uniform(0, 1), rnd.uniform(0, 1), rnd.uniform(0, 3)), segments=7, rings=5)
    for x, tilt in ((-0.75, 0.35), (0.85, -0.3)):
        sheet_c = (x, D / 2 - 0.35, H + 0.28)
        s.box("Paper", (0.55, 0.02, 0.6), sheet_c, rot=(0.25, tilt, 0))
        for k in range(3):
            p = face_point(0, 0.15 - k * 0.12, tilt, (x, D / 2 - 0.37 - 0.04, H + 0.28))
            s.box("Ink", (0.38, 0.012, 0.035), p, rot=(0.25, tilt, 0))
    # rubber duck (left of centre) and a white teacup on a saucer (right)
    dx, dy, dz = -0.25, -0.1, H + 0.12
    s.ball("Duck", 0.32, (dx, dy, dz), scale=(1.15, 0.95, 0.8))
    s.ball("Duck", 0.2, (dx + 0.12, dy - 0.12, dz + 0.36))
    s.ball("Duck", 0.12, (dx - 0.32, dy + 0.02, dz + 0.12), scale=(1, 0.7, 0.8))
    s.ball("Beak", 0.09, (dx + 0.14, dy - 0.32, dz + 0.32), scale=(1.1, 0.8, 0.5))
    for ex in (0.04, 0.22):
        s.ball("Eye", 0.03, (dx + ex, dy - 0.28, dz + 0.42), segments=6, rings=4)
    cx, cy = 0.6, -0.05
    s.lathe("Cup", [(0.0, 0.0), (0.34, 0.0), (0.36, 0.04), (0.0, 0.04)], (cx, cy, H + 0.02))
    s.lathe("Cup", [(0.0, 0.0), (0.13, 0.0), (0.2, 0.08), (0.23, 0.24), (0.2, 0.24), (0.17, 0.1), (0.0, 0.06)], (cx, cy, H + 0.06))
    s.ring("Cup", 0.07, 0.022, (cx + 0.25, cy, H + 0.2), rot=(math.pi / 2, 0, 0))
    # paper tag with a smiley hanging off the front-right post
    tag_c, tilt = (W / 2 - 0.12, -D / 2 - 0.08, 0.62), 0.15
    s.box("Paper", (0.26, 0.02, 0.34), tag_c, rot=(0, tilt, 0), bevel=0.02, segments=1)
    s.stick("Rope", (W / 2 - 0.12, -D / 2 - 0.08, 0.8), (W / 2 - 0.09, -D / 2 - 0.1, 1.05), 0.02)
    for u in (-0.05, 0.05):
        s.box("Eye", (0.03, 0.012, 0.03), face_point(u, 0.04, tilt, (tag_c[0], tag_c[1] - 0.014, tag_c[2])), rot=(0, tilt, 0))
    for u, v in ((-0.06, -0.05), (0.0, -0.08), (0.06, -0.05)):
        s.box("Eye", (0.05, 0.012, 0.022), face_point(u, v, tilt, (tag_c[0], tag_c[1] - 0.014, tag_c[2])), rot=(0, tilt - u * 6, 0))
    return s.build()


# ===== 3. YARD SALE CRATE: cardboard box, marker YARD SALE!, striped twine + bow, pink 50c tag, racket + comic + blanket =====

def crate_yard_sale():
    s = Crate("CrateYardSale")
    s.mat("Body", "C89B6A", roughness=0.9)
    s.mat("Seam", "9C7650", roughness=0.9)
    s.mat("Marker", "2B1A12", roughness=0.6)
    s.mat("TwineRed", "E8553E", roughness=0.7)
    s.mat("TwineWhite", "FFFFFF", roughness=0.7)
    s.mat("Tag", "FF6B8E", roughness=0.6)
    s.mat("Tape", "E8D9B0", roughness=0.5)
    s.mat("Ring", "8A5A3C", roughness=0.8)
    s.mat("Racket", "B07A4A", roughness=0.6)
    s.mat("Strings", "F4F0E8", roughness=0.6)
    s.mat("Comic", "3A8FD8", roughness=0.6)
    s.mat("ComicBand", "F2C14E", roughness=0.6)
    s.mat("Plaid", "8C7A68", roughness=0.95)
    s.mat("PlaidLine", "A0453A", roughness=0.95)
    W, D, H = BODY["CrateYardSale"]
    fy = -D / 2
    s.box("Body", (W, D, H), (0, 0, H / 2), bevel=0.07)
    s.box("Seam", (W - 0.1, 0.025, 0.012), (0, 0, H + 0.002))
    # twine: across the top both ways, down the front; a bow on the front edge
    tx = -0.68  # left of the writing, like the sheet
    s.stripe_line("TwineRed", "TwineWhite", (tx, fy - 0.02, H + 0.02), (tx, D / 2 + 0.02, H + 0.02))
    s.stripe_line("TwineRed", "TwineWhite", (tx, fy - 0.02, H + 0.02), (tx, fy - 0.02, 0.02))
    s.stripe_line("TwineRed", "TwineWhite", (-W / 2 - 0.02, 0.15, H + 0.02), (W / 2 + 0.02, 0.15, H + 0.02))
    s.stripe_line("TwineRed", "TwineWhite", (W / 2 + 0.02, 0.15, H + 0.02), (W / 2 + 0.02, 0.15, H - 0.7))
    s.stripe_line("TwineRed", "TwineWhite", (-W / 2 - 0.02, 0.15, H + 0.02), (-W / 2 - 0.02, 0.15, H - 0.7))
    bow = (tx, fy - 0.05, H - 0.02)
    for side in (-1, 1):
        s.ring("TwineRed", 0.13, 0.03, (bow[0] + side * 0.14, bow[1], bow[2] + 0.06), rot=(math.pi / 2, side * 0.5, 0), scale=(1.2, 0.8, 1))
        s.stick("TwineWhite", bow, (bow[0] + side * 0.2, bow[1] - 0.02, bow[2] - 0.3), 0.03)
    s.ball("TwineRed", 0.055, bow, segments=8, rings=6)
    # pink price tag "50c" hanging off the twine at the front-right corner
    tag_c, tilt = (W / 2 - 0.25, fy - 0.03, H - 0.42), -0.45
    s.stripe_line("TwineRed", "TwineWhite", (tx + 0.05, fy - 0.03, H - 0.03), face_point(-0.2, 0.06, tilt, tag_c), thick=0.02, seg=0.07)
    s.box("Tag", (0.46, 0.025, 0.26), tag_c, rot=(0, tilt, 0), bevel=0.03, segments=1)
    s.text("Marker", "50\u00a2", "marker", 0.16, face_point(0.03, 0, tilt, (tag_c[0], tag_c[1] - 0.02, tag_c[2])), tilt=tilt, extrude=0.008)
    # marker writing on the front
    s.text("Marker", "YARD\nSALE!", "marker", 0.4, (0.12, fy - 0.006, 0.78), tilt=0.12, extrude=0.008, line=0.82)
    # masking tape patches on the corners and a coffee ring
    for x, z, r in ((-W / 2 + 0.2, H - 0.25, 0.6), (-W / 2 + 0.15, 0.25, -0.5), (W / 2 - 0.12, 0.35, 0.7)):
        s.box("Tape", (0.34, 0.016, 0.12), (x, fy - 0.004, z), rot=(0, r, 0))
    s.ring("Ring", 0.17, 0.014, (0.72, fy - 0.006, 0.28), rot=(math.pi / 2, 0, 0), major_seg=24, minor_seg=4)
    # tennis racket leaning at the back left (frame + strings + handle), built flat then tilted
    rc = mathutils.Vector((-0.55, 0.35, H + 0.75))
    lean = mathutils.Euler((0.25, -0.35, 0.15)).to_matrix()

    def at(u, v):  # a point in the racket's own plane (u across, v up)
        return tuple(rc + lean @ mathutils.Vector((u, 0, v)))

    rot = lean.to_euler()
    s.ring("Racket", 0.36, 0.045, tuple(rc), rot=(rot.x + math.pi / 2, rot.y, rot.z), scale=(1, 1.3, 1), major_seg=24, minor_seg=6)
    for k in range(-3, 4):
        u = k * 0.09
        h = 0.44 * math.sqrt(max(0.0, 1 - (u / 0.36) ** 2))
        s.box("Strings", (0.015, 0.015, 2 * h), at(u, 0), rot=tuple(rot))
    for k in range(-4, 5):
        v = k * 0.09
        w = 0.34 * math.sqrt(max(0.0, 1 - (v / 0.46) ** 2))
        s.box("Strings", (2 * w, 0.015, 0.015), at(0, v), rot=tuple(rot))
    s.box("Racket", (0.09, 0.09, 0.55), at(0, -0.72), rot=tuple(rot), bevel=0.02)
    # rolled comic and a folded plaid blanket
    s.cyl("Comic", 0.15, 0.75, (0.05, 0.45, H + 0.4), rot=(-0.25, 0.25, 0), verts=12)
    s.cyl("ComicBand", 0.155, 0.12, (0.08, 0.5, H + 0.6), rot=(-0.25, 0.25, 0), verts=12)
    bx, by, bz = 0.58, 0.25, H + 0.22
    s.box("Plaid", (0.85, 0.7, 0.42), (bx, by, bz), rot=(0, 0, 0.12), bevel=0.12)
    for k in (-0.25, 0.0, 0.25):
        s.box("PlaidLine", (0.04, 0.72, 0.44), (bx + k, by + k * 0.12, bz), rot=(0, 0, 0.12))
    for k in (-0.1, 0.1):
        s.box("PlaidLine", (0.87, 0.04, 0.44), (bx - k * 0.12, by + k, bz), rot=(0, 0, 0.12))
    return s.build()


# ===== 4. FLEA MARKET CRATE: chipped teal plank crate, striped awning, crooked painted sign, stickers, record + phone =====

def crate_flea():
    s = Crate("CrateFlea")
    s.mat("Body", "3E8F8A", roughness=0.8)
    s.mat("Wood", "8A5A3C", roughness=0.85)
    s.mat("AwningRed", "E8553E", roughness=0.8)
    s.mat("AwningCream", "F4E9D2", roughness=0.8)
    s.mat("Rope", "C9A26B", roughness=0.9)
    s.mat("Sign", "F2C14E", roughness=0.7)
    s.mat("SignInk", "5A3A28", roughness=0.7)
    s.mat("Nail", "6B6B6B", roughness=0.4, metallic=0.6)
    s.mat("StickerPink", "FF6B8E", roughness=0.5)
    s.mat("StickerBlue", "6FB7E8", roughness=0.5)
    s.mat("StickerPurple", "9B6FD8", roughness=0.5)
    s.mat("Vinyl", "22252B", roughness=0.3)
    s.mat("VinylLabel", "E8553E", roughness=0.5)
    s.mat("Phone", "F2B33C", roughness=0.4)
    s.mat("Dial", "F4F0E8", roughness=0.4)
    s.mat("Metal", "9AA0A6", roughness=0.3, metallic=0.7)
    W, D, H = BODY["CrateFlea"]
    fy = -D / 2
    s.box("Wood", (W - 0.1, D - 0.1, H - 0.1), (0, 0, H / 2))  # inner box so no gaps show through
    for sx in (-1, 1):
        for sy in (-1, 1):
            s.box("Wood", (0.2, 0.2, H), (sx * (W / 2 - 0.1), sy * (D / 2 - 0.1), H / 2), bevel=0.03)
    rnd = random.Random(11)
    rows = [0.27 + i * 0.52 for i in range(4)]
    for z in rows:
        for sy in (-1, 1):
            s.box("Body", (W - 0.36, 0.09, 0.48), (0, sy * (D / 2 - 0.05), z), bevel=0.025)
        for sx in (-1, 1):
            s.box("Body", (0.09, D - 0.36, 0.48), (sx * (W / 2 - 0.05), 0, z), bevel=0.025)
        # chipped paint: bare wood showing at a few plank edges
        for _ in range(2):
            x = rnd.uniform(-W / 2 + 0.4, W / 2 - 0.4)
            s.box("Wood", (rnd.uniform(0.12, 0.25), 0.02, 0.06), (x, fy - 0.006, z + rnd.choice((-0.2, 0.2))))
    # diagonal braces on the left side and the back
    ang = math.atan2(H - 0.3, D - 0.4)
    s.box("Body", (0.1, math.hypot(D - 0.4, H - 0.3), 0.26), (-W / 2 - 0.03, 0, H / 2), rot=(ang, 0, 0), bevel=0.02)
    # the awning: red / cream stripes sloping from the back of the top over the front edge, then hanging down the front
    # as a valance with a scalloped hem (like a market stall). Slope: a box's local Y turned up by `tilt` about X.
    n = 7
    sw = (W + 0.2) / n
    hem_y = fy - 0.12
    back, front = mathutils.Vector((0, 0.3, H + 0.38)), mathutils.Vector((0, hem_y, H + 0.06))
    d = back - front
    tilt = math.atan2(d.z, d.y)
    mid = (back + front) / 2
    drop = 0.42
    for i in range(n):
        x = -(W + 0.2) / 2 + sw * (i + 0.5)
        part = "AwningRed" if i % 2 == 0 else "AwningCream"
        s.box(part, (sw, d.length + 0.04, 0.05), (x, mid.y, mid.z), rot=(tilt, 0, 0))
        s.box(part, (sw, 0.05, drop), (x, hem_y, front.z - drop / 2 + 0.02))
        s.cyl(part, sw / 2, 0.05, (x, hem_y, front.z - drop + 0.02), rot=(math.pi / 2, 0, 0), verts=14)
    for sx in (-1, 1):
        s.ring("Rope", 0.07, 0.022, (sx * (W / 2 + 0.02), fy + 0.05, H - 0.02), rot=(0, math.pi / 2, 0))
    # the sign, nailed on a bit crooked
    sc, stilt = (0.05, fy - 0.1, 0.95), 0.08
    s.box("Sign", (1.4, 0.07, 0.66), sc, rot=(0, stilt, 0), bevel=0.035)
    s.text("SignInk", "FLEA\nMARKET", "painted", 0.24, (sc[0], sc[1] - 0.04, sc[2]), tilt=stilt, extrude=0.01, line=0.78)
    for u, v in ((-0.6, 0.25), (0.6, 0.25), (-0.6, -0.25), (0.6, -0.25)):
        s.cyl("Nail", 0.03, 0.03, face_point(u, v, stilt, (sc[0], sc[1] - 0.04, sc[2])), rot=(math.pi / 2, 0, 0), verts=8)
    # stickers from other market towns
    s.box("StickerPink", (0.26, 0.02, 0.26), (1.0, fy - 0.08, 1.4), rot=(0, -0.25, 0), bevel=0.02, segments=1)
    s.box("StickerBlue", (0.3, 0.02, 0.22), (0.95, fy - 0.08, 0.35), rot=(0, 0.3, 0), bevel=0.02, segments=1)
    s.cyl("StickerPurple", 0.15, 0.02, (-0.88, fy - 0.08, 0.32), rot=(math.pi / 2, 0, 0), verts=14)
    # a vinyl record and a yellow rotary phone poking out from under the awning
    rec = (-0.55, 0.2, H + 0.78)
    s.cyl("Vinyl", 0.55, 0.04, rec, rot=(math.pi / 2 - 0.35, 0, 0.25), verts=28)
    s.cyl("VinylLabel", 0.18, 0.05, rec, rot=(math.pi / 2 - 0.35, 0, 0.25), verts=16)
    px, py, pz = 0.5, 0.35, H + 0.48
    s.box("Phone", (0.72, 0.56, 0.36), (px, py, pz), rot=(-0.15, 0, -0.15), bevel=0.12)
    s.cyl("Phone", 0.07, 0.62, (px, py + 0.02, pz + 0.3), rot=(0, math.pi / 2, -0.15), verts=10)
    for ex in (-0.3, 0.3):
        s.ball("Phone", 0.12, (px + ex * math.cos(0.15), py + 0.02 + ex * math.sin(-0.15), pz + 0.28), scale=(0.8, 1, 0.7))
    s.cyl("Dial", 0.17, 0.04, (px - 0.02, py - 0.3, pz + 0.04), rot=(math.pi / 2 - 0.15, 0, -0.15), verts=16)
    s.stick("Metal", (px + 0.25, py + 0.2, pz + 0.1), (px + 0.45, py + 0.35, pz + 1.05), 0.03)
    s.ball("Metal", 0.04, (px + 0.45, py + 0.35, pz + 1.05), segments=8, rings=6)
    return s.build()


# ===== 5. ANTIQUE DEALER CRATE: walnut planks, brass corner caps + rivets, padlock, wax seal, straw, cream tag =====

def crate_antique():
    s = Crate("CrateAntique")
    s.mat("Body", "5A3A28", roughness=0.75)
    s.mat("Groove", "3E2618", roughness=0.9)
    s.mat("Brass", "E3B23C", roughness=0.35, metallic=0.9)
    s.mat("Straw", "E8C872", roughness=0.9)
    s.mat("Wax", "8E2A2A", roughness=0.4)
    s.mat("WaxDark", "6E1E1E", roughness=0.4)
    s.mat("Tag", "F4E9D2", roughness=0.8)
    s.mat("TagInk", "5A3A28", roughness=0.8)
    s.mat("String", "9A8A70", roughness=0.9)
    W, D, H = BODY["CrateAntique"]
    fy = -D / 2
    lid_z = H - 0.22
    s.box("Body", (W, D, lid_z - 0.04), (0, 0, (lid_z - 0.04) / 2), bevel=0.05)
    s.box("Body", (W + 0.06, D + 0.06, 0.3), (0, 0, H - 0.15), bevel=0.05)  # the lid
    # plank grooves on every side and across the lid
    for z in [0.38 * k for k in range(1, 5)]:
        if z < lid_z - 0.1:
            s.box("Groove", (W - 0.3, 0.02, 0.03), (0, fy - 0.004, z))
            s.box("Groove", (W - 0.3, 0.02, 0.03), (0, D / 2 + 0.004, z))
            for sx in (-1, 1):
                s.box("Groove", (0.02, D - 0.3, 0.03), (sx * (W / 2 + 0.004), 0, z))
    for y in (-0.6, 0.0, 0.6):
        s.box("Groove", (W - 0.3, 0.03, 0.02), (0, y, H + 0.004))
    # brass corner caps with rivets on all eight corners
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.17, H - 0.17):
                s.box("Brass", (0.4, 0.4, 0.38), (sx * (W / 2 - 0.17), sy * (D / 2 - 0.17), z), bevel=0.04)
                if sy == -1:
                    for v in (-0.08, 0.08):
                        s.ball("Brass", 0.035, (sx * (W / 2 - 0.2), fy - 0.06, z + v), segments=8, rings=5)
    # straw sticking out of the lid seam all round
    rnd = random.Random(3)
    sz = lid_z - 0.02
    for i in range(54):
        side = i % 3
        if side == 0:
            x, y = rnd.uniform(-W / 2 + 0.45, W / 2 - 0.45), fy
            out = mathutils.Vector((rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.0), -0.35, rnd.uniform(0.15, 0.6))).normalized()  # tufts fan out sideways along the front
        else:
            x, y = (-1 if side == 1 else 1) * W / 2, rnd.uniform(-D / 2 + 0.45, D / 2 - 0.45)
            out = mathutils.Vector(((-1 if side == 1 else 1), rnd.uniform(-0.3, 0.3), rnd.uniform(0.0, 0.8))).normalized()
        p0 = mathutils.Vector((x, y, sz))
        s.stick("Straw", tuple(p0 - out * 0.1), tuple(p0 + out * rnd.uniform(0.25, 0.5)), 0.028)
    # burgundy wax seal with a magnifying glass, on the lid front
    seal = (0.2, fy - 0.05, H - 0.3)
    s.cyl("Wax", 0.22, 0.07, seal, rot=(math.pi / 2, 0, 0), verts=16, bevel=0.02)
    for k in range(7):
        a = k * 2 * math.pi / 7
        s.ball("Wax", 0.045, (seal[0] + 0.22 * math.cos(a), seal[1] + 0.005, seal[2] + 0.22 * math.sin(a)), scale=(1, 0.5, 1), segments=8, rings=5)
    s.ring("WaxDark", 0.07, 0.016, (seal[0] - 0.02, seal[1] - 0.04, seal[2] + 0.03), rot=(math.pi / 2, 0, 0), major_seg=16, minor_seg=4)
    s.box("WaxDark", (0.03, 0.02, 0.1), (seal[0] + 0.05, seal[1] - 0.04, seal[2] - 0.06), rot=(0, -0.8, 0))
    # cream tag on a string: ANTIQUES / HANDLE WITH CARE
    tag_c, tilt = (0.45, fy - 0.08, 0.95), -0.32
    s.stick("String", (seal[0], seal[1] - 0.02, seal[2] - 0.2), face_point(-0.42, 0.12, tilt, tag_c), 0.018)
    s.box("Tag", (0.95, 0.025, 0.46), tag_c, rot=(0, tilt, 0), bevel=0.04, segments=1)
    s.ring("String", 0.035, 0.01, face_point(-0.38, 0.1, tilt, (tag_c[0], tag_c[1] - 0.02, tag_c[2])), rot=(math.pi / 2, 0, 0), major_seg=10, minor_seg=4)
    s.text("TagInk", "ANTIQUES", "serif", 0.16, face_point(0.04, 0.06, tilt, (tag_c[0], tag_c[1] - 0.02, tag_c[2])), tilt=tilt, extrude=0.006)
    s.text("TagInk", "HANDLE WITH CARE", "serif", 0.065, face_point(0.04, -0.1, tilt, (tag_c[0], tag_c[1] - 0.02, tag_c[2])), tilt=tilt, extrude=0.005)
    # a brass padlock hanging on the front left
    lk = (-0.82, fy - 0.09, 1.2)
    s.box("Brass", (0.28, 0.1, 0.26), lk, bevel=0.05)
    s.ring("Brass", 0.09, 0.026, (lk[0], lk[1], lk[2] + 0.16), rot=(math.pi / 2, 0, 0), major_seg=16, minor_seg=6)
    s.box("Groove", (0.035, 0.02, 0.08), (lk[0], lk[1] - 0.055, lk[2] - 0.02))
    return s.build()


# ===== 6. ESTATE SALE CRATE: emerald steamer trunk, gold trim + filigree, straps, crest, nameplate, glowing seam =====

def crate_estate():
    s = Crate("CrateEstate")
    s.mat("Body", "1F6B4F", roughness=0.55)
    s.mat("Gold", "F2C14E", roughness=0.3, metallic=0.9)
    s.mat("GoldDark", "C99A2E", roughness=0.35, metallic=0.9)
    s.mat("Strap", "4A2E1E", roughness=0.6)
    s.mat("Ink", "2B1A12", roughness=0.6)
    s.mat("Glow", "FFF2CC", emission=4.0)
    W, D, H1 = BODY["CrateEstate"]
    R, ZS, GAP = D / 2, 0.72, 0.07
    fy = -D / 2
    s.box("Body", (W, D, H1), (0, 0, H1 / 2), bevel=0.06)
    lid = half_dome(f"{s.id}_lid", W, R, ZS, segs=18)
    lid.location = (0, 0, H1 + GAP)
    s.add("Body", lid)
    top = H1 + GAP + R * ZS

    def dome_point(x, a, out=0.0):  # a = angle from the front edge (0) over the top (pi/2) to the back (pi)
        return (x, -(R + out) * math.cos(a), H1 + GAP + (R + out) * math.sin(a) * ZS)

    # glowing seam between body and lid, with a few sparkles in front of it
    s.box("Glow", (W - 0.1, D - 0.02, GAP + 0.02), (0, 0, H1 + GAP / 2))
    for x, z, k in ((-1.1, H1 + 0.25, 0.09), (0.9, H1 + 0.55, 0.07), (1.35, H1 - 0.1, 0.06), (-0.4, top + 0.25, 0.07)):
        p = (x, fy - 0.25, z)
        s.box("Glow", (k * 2, 0.02, k * 0.35), p, rot=(0, 0.785, 0))
        s.box("Glow", (k * 2, 0.02, k * 0.35), p, rot=(0, -0.785, 0))
    # gold bands: round the bottom, round the top of the body, up the corners, along the lid's front/back edge
    s.box("Gold", (W + 0.05, D + 0.05, 0.13), (0, 0, 0.065), bevel=0.02)
    s.box("Gold", (W + 0.05, D + 0.05, 0.12), (0, 0, H1 - 0.06), bevel=0.02)
    s.box("Gold", (W + 0.05, 0.1, 0.1), (0, fy + 0.02, H1 + GAP + 0.05), bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            s.box("Gold", (0.14, 0.14, H1), (sx * (W / 2 - 0.05), sy * (D / 2 - 0.05), H1 / 2), bevel=0.02)
        # gold arc along each end of the lid
        segs = 14
        for i in range(segs):
            a0, a1 = math.pi * i / segs, math.pi * (i + 1) / segs
            p0, p1 = dome_point(sx * (W / 2 - 0.06), a0, 0.02), dome_point(sx * (W / 2 - 0.06), a1, 0.02)
            s.stick("Gold", p0, p1, 0.12)
        # gold side handle on each end
        for (u, v, sw, sh) in ((0, 0.14, 0.55, 0.06), (0, -0.14, 0.55, 0.06), (-0.27, 0, 0.06, 0.34), (0.27, 0, 0.06, 0.34)):
            s.box("Gold", (0.06, sw, sh), (sx * (W / 2 + 0.05), u, H1 * 0.62 + v))
    # leather straps over the lid and down the front, each with a gold buckle
    for x in (-0.85, 0.85):
        segs = 12
        for i in range(segs):
            a0, a1 = math.pi * i / segs, math.pi * (i + 1) / segs
            p0, p1 = mathutils.Vector(dome_point(x, a0, 0.02)), mathutils.Vector(dome_point(x, a1, 0.02))
            d = p1 - p0
            q = d.to_track_quat("Z", "X").to_euler()
            s.box("Strap", (0.3, 0.035, d.length + 0.01), tuple((p0 + p1) / 2), rot=tuple(q))
        s.box("Strap", (0.3, 0.035, H1 - 0.35), (x, fy - 0.02, 0.3 + (H1 - 0.35) / 2))
        s.frame("Gold", 0.36, 0.26, 0.05, 0.05, (x, fy - 0.05, H1 * 0.6))
        s.box("Gold", (0.04, 0.05, 0.22), (x - 0.04, fy - 0.06, H1 * 0.6))
    # round gold crest with a little mansion, on the lid front. The lid surface there leans back by `beta` from upright:
    # a front-facing box turns by (-beta, 0, 0); a disc (cylinder axis Z) by (pi/2 - beta, 0, 0).
    a = math.radians(55)
    beta = math.atan2(math.sin(a) / ZS, math.cos(a))
    normal = mathutils.Vector((0, -math.cos(beta), math.sin(beta)))
    up = mathutils.Vector((0, math.sin(beta), math.cos(beta)))
    cpos = mathutils.Vector(dome_point(0, a, 0.0)) + normal * 0.03
    s.cyl("Gold", 0.34, 0.06, tuple(cpos), rot=(math.pi / 2 - beta, 0, 0), verts=24, bevel=0.015)
    c0 = cpos + normal * 0.04
    for (u, v, w, h) in ((0, -0.05, 0.36, 0.13), (0, 0.06, 0.4, 0.06), (0, 0.13, 0.12, 0.08), (-0.12, -0.05, 0.03, 0.13), (0.12, -0.05, 0.03, 0.13)):
        p = c0 + mathutils.Vector((u, 0, 0)) + up * v
        s.box("GoldDark", (w, 0.03, h), tuple(p), rot=(-beta, 0, 0))
    # gold nameplate on the front: ESTATE SALE
    s.box("Gold", (1.15, 0.05, 0.27), (0, fy - 0.03, 0.62), bevel=0.03)
    s.text("Ink", "ESTATE SALE", "serif", 0.13, (0, fy - 0.06, 0.615), extrude=0.008)
    # little gold filigree curls on the front corners
    for sx in (-1, 1):
        for z in (0.28, H1 - 0.28):
            s.ring("Gold", 0.07, 0.016, (sx * (W / 2 - 0.28), fy - 0.01, z), rot=(math.pi / 2, 0, 0), major_seg=12, minor_seg=4)
            s.ring("Gold", 0.045, 0.014, (sx * (W / 2 - 0.4), fy - 0.01, z + (0.08 if z < 1 else -0.08)), rot=(math.pi / 2, 0, 0), major_seg=10, minor_seg=4)
    return s.build()


BUILDERS = {
    "CrateFree": crate_free,
    "CrateStarter": crate_starter,
    "CrateYardSale": crate_yard_sale,
    "CrateFlea": crate_flea,
    "CrateAntique": crate_antique,
    "CrateEstate": crate_estate,
}


# ===== preview + export =====

def setup_render(width: int, height: int):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.86, 0.84, 0.8, 1)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o, do_unlink=True)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.93, 0.82)
    sun.rotation_euler = (math.radians(48), 0, math.radians(35))
    bpy.context.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 1.0
    fill.rotation_euler = (math.radians(60), 0, math.radians(-120))
    bpy.context.collection.objects.link(fill)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    return scene, cam


def aim(cam, location, target, lens=50):
    cam.location = location
    cam.rotation_euler = (mathutils.Vector(target) - mathutils.Vector(location)).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


def main():
    c.reset_scene()
    wanted = os.environ.get("DF_CRATES")
    ids = [i.strip() for i in wanted.split(",")] if wanted else list(BUILDERS)
    preview_dir = os.environ.get("DF_PREVIEW_DIR") or os.path.join(c.OUT_PREVIEWS, "crates")
    os.makedirs(preview_dir, exist_ok=True)
    built = {}
    for cid in ids:
        objs = BUILDERS[cid]()
        built[cid] = objs
        tris = c.triangle_count(objs)
        lo = [min((o.matrix_world @ v.co)[k] for o in objs for v in o.data.vertices) for k in range(3)]
        hi = [max((o.matrix_world @ v.co)[k] for o in objs for v in o.data.vertices) for k in range(3)]
        print(f"CRATE {cid}: {len(objs)} parts, {tris} triangles, x {lo[0]:.2f}..{hi[0]:.2f}  y {lo[1]:.2f}..{hi[1]:.2f}  z {lo[2]:.2f}..{hi[2]:.2f}")

    # one render per crate (3/4 front view), then the whole lineup side by side
    scene, cam = setup_render(900, 800)
    for cid, objs in built.items():
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = o not in objs
        w, _, h = BODY[cid]
        dist = 2.6 + w * 1.25
        aim(cam, (dist * 0.62, -dist, 1.2 + dist * 0.5), (0, 0, h * 0.62), lens=50)
        scene.render.filepath = os.path.join(preview_dir, cid + ".png")
        bpy.ops.render.render(write_still=True)

    x = 0.0
    offsets = {}
    for cid, objs in built.items():
        w = BODY[cid][0]
        x += w / 2
        offsets[cid] = x
        for o in objs:
            o.location.x += x
            o.hide_render = False
        x += w / 2 + 0.7
    scene.render.resolution_x, scene.render.resolution_y = 2000, 760
    mid = x / 2
    aim(cam, (mid + 1.5, -24.0, 7.5), (mid, 0, 1.3), lens=38)
    scene.render.filepath = os.path.join(preview_dir, "lineup.png")
    bpy.ops.render.render(write_still=True)

    if os.environ.get("DF_EXPORT"):
        # one empty per crate (becomes a Model in Studio) with its colour parts under it, each crate back at the origin
        allobjs = []
        for cid, objs in built.items():
            empty = bpy.data.objects.new(cid, None)
            bpy.context.collection.objects.link(empty)
            empty.location = (offsets[cid], 0, 0)
            for o in objs:
                o.parent = empty
                o.matrix_parent_inverse = empty.matrix_world.inverted()
            allobjs += [empty] + objs
        out = os.path.join(c.OUT_MODELS, "Crates.glb")
        os.makedirs(c.OUT_MODELS, exist_ok=True)
        c.export_glb(out, allobjs)
        print("EXPORTED", out)
    keep = os.environ.get("DF_KEEP")
    if keep:
        bpy.ops.wm.save_as_mainfile(filepath=keep)
        print("SAVED", keep)
    print("done")


main()
