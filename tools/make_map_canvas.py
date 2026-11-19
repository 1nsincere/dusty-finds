"""Writes assets/template/4_Map_Canvas_660x700.svg: a blank, true-scale canvas of the current Baseplate for planning a layout.

Run with any Python 3 (e.g. Blender's):  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/make_map_canvas.py
Same orientation as the Phase 2 blueprint: North = +Z (top), East = -X (right). Labels are real Roblox X / Z coordinates.
The stamp sheet on the right shows every building / gameplay footprint at the same scale (sizes measured in Studio, place v188).
"""

import os

S = 3.0                      # pixels per stud
X0, X1 = -330.0, 330.0       # Baseplate 660 x 700, centred on (0, -50)
Z0, Z1 = -400.0, 300.0
M = 100                      # margin for the axis labels
W_MAP, H_MAP = (X1 - X0) * S, (Z1 - Z0) * S
PANEL = 760
W, H = M * 2 + W_MAP + PANEL, M * 2 + H_MAP + 40


def px(x):                   # East = -X is to the right
    return M + (X1 - x) * S


def pz(z):                   # North = +Z is at the top
    return M + (Z1 - z) * S


o = []
a = o.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" viewBox="0 0 {W:.0f} {H:.0f}" '
  'font-family="Segoe UI, Arial, sans-serif">')
a(f'<rect width="{W:.0f}" height="{H:.0f}" fill="#2b2d33"/>')
a(f'<rect x="{M}" y="{M}" width="{W_MAP:.0f}" height="{H_MAP:.0f}" fill="#fbf7ef"/>')

# grid: thin every 20 studs, strong every 100, labelled with real coordinates
x = -320.0                   # grid lines on multiples of 20 (the Baseplate edge is at 330)
while x <= X1 + 0.1:
    strong = abs(x % 100) < 0.1
    a(f'<line x1="{px(x):.1f}" y1="{M}" x2="{px(x):.1f}" y2="{M + H_MAP:.0f}" stroke="{"#a9a393" if strong else "#e6e0d2"}" stroke-width="{2 if strong else 1}"/>')
    if strong:
        a(f'<text x="{px(x):.1f}" y="{M - 14}" fill="#e9e4d8" font-size="20" text-anchor="middle">X {x:.0f}</text>')
    x += 20
z = Z0
while z <= Z1 + 0.1:
    strong = abs(z % 100) < 0.1
    a(f'<line x1="{M}" y1="{pz(z):.1f}" x2="{M + W_MAP:.0f}" y2="{pz(z):.1f}" stroke="{"#a9a393" if strong else "#e6e0d2"}" stroke-width="{2 if strong else 1}"/>')
    if strong:
        a(f'<text x="{M - 8}" y="{pz(z) + 7:.1f}" fill="#e9e4d8" font-size="20" text-anchor="end">Z {z:.0f}</text>')
    z += 20
a(f'<rect x="{M}" y="{M}" width="{W_MAP:.0f}" height="{H_MAP:.0f}" fill="none" stroke="#1d1e22" stroke-width="6"/>')
# origin cross
a(f'<path d="M{px(0) - 12:.1f} {pz(0):.1f}h24M{px(0):.1f} {pz(0) - 12:.1f}v24" stroke="#c0392b" stroke-width="3"/>')
a(f'<text x="{px(0) + 10:.1f}" y="{pz(0) - 10:.1f}" fill="#c0392b" font-size="18">0,0</text>')
# compass
cx, cy = M + W_MAP - 70, M + 80
a(f'<path d="M{cx} {cy - 45}l16 40h-32z" fill="#1d1e22"/><text x="{cx}" y="{cy + 26}" font-size="30" font-weight="700" text-anchor="middle" fill="#1d1e22">N (+Z)</text>')
a(f'<text x="{cx}" y="{cy + 56}" font-size="18" text-anchor="middle" fill="#5d5a52">East = -X (right)</text>')
# footer
a(f'<text x="{M}" y="{M + H_MAP + 34:.0f}" fill="#e9e4d8" font-size="22" font-weight="700">MAP CANVAS  -  Baseplate 660 x 700 studs (X -330..330, Z -400..300)  -  '
  f'{S:.0f} px = 1 stud  -  grid every 20 studs (strong every 100)  -  ground top is Y 0.4</text>')

# ---------- stamp sheet (same scale) ----------
SX = M + W_MAP + 50
a(f'<text x="{SX}" y="{M + 10}" fill="#ffffff" font-size="30" font-weight="700">STAMPS (same scale)</text>')
a(f'<text x="{SX}" y="{M + 40}" fill="#cfc9bb" font-size="17">top-down footprints, front marked with a red edge</text>')

STAMPS = [
    # name, width (along the front), depth, colour, note
    ("Shop plot x6 (+ Back Room)", 56, 90, "#e8c79a", "56 x 56 shop + 34 deep Back Room behind; door on the front; code needs Plots.Plot1-6"),
    ("Museum", 82, 65, "#efe2c4", "Collection pedestal in front (code needs it)"),
    ("Depot (jeep stop)", 68, 52, "#f2c75c", "back canopy = jeepney platform"),
    ("Domed Hall", 50, 61, "#efe0b8", ""),
    ("Sulit Mart", 51, 48, "#f7f7f2", ""),
    ("Kainan ni Bida", 47, 38, "#c8262b", ""),
    ("Warehouse", 45, 56, "#b8573c", "Supply counter inside the door (code needs it)"),
    ("Gate", 71, 13, "#e8d6a8", "walk-through arch across a street"),
    ("Bakery", 29, 26, "#d9a066", ""),
    ("Sari-sari", 26, 24, "#9edbc6", ""),
    ("House (x23 now)", 25, 22, "#f3d6d6", "5 designs, any colour"),
    ("Clock Tower", 17, 17, "#c76a47", ""),
]
yy = M + 80
col_x = [SX, SX + 360]
col_y = [yy, yy]
for i, (name, w, d, colr, note) in enumerate(STAMPS):
    c = 0 if col_y[0] <= col_y[1] else 1
    x0, y0 = col_x[c], col_y[c]
    a(f'<text x="{x0}" y="{y0 + 18}" fill="#ffffff" font-size="19" font-weight="700">{name}</text>')
    a(f'<text x="{x0}" y="{y0 + 40}" fill="#cfc9bb" font-size="16">{w} x {d} studs</text>')
    by = y0 + 52
    if name.startswith("Shop"):
        room = 34 * S  # Back Room behind the shop (drawn on top = behind, since the front edge is at the bottom)
        a(f'<rect x="{x0}" y="{by}" width="{w * S}" height="{room}" fill="#d9cfb8" stroke="#1d1e22" stroke-width="2" stroke-dasharray="6 4"/>')
        a(f'<text x="{x0 + w * S / 2}" y="{by + room / 2 + 6}" font-size="15" text-anchor="middle" fill="#5d5a52">Back Room</text>')
        a(f'<rect x="{x0}" y="{by + room}" width="{w * S}" height="{56 * S}" fill="{colr}" stroke="#1d1e22" stroke-width="2"/>')
        a(f'<text x="{x0 + w * S / 2}" y="{by + room + 28 * S + 6}" font-size="15" text-anchor="middle" fill="#5d5a52">shop</text>')
        a(f'<line x1="{x0}" y1="{by + room + 56 * S}" x2="{x0 + w * S}" y2="{by + room + 56 * S}" stroke="#c0392b" stroke-width="5"/>')
        h_used = 52 + 90 * S
    else:
        a(f'<rect x="{x0}" y="{by}" width="{w * S}" height="{d * S}" fill="{colr}" stroke="#1d1e22" stroke-width="2"/>')
        a(f'<line x1="{x0}" y1="{by + d * S}" x2="{x0 + w * S}" y2="{by + d * S}" stroke="#c0392b" stroke-width="5"/>')
        h_used = 52 + d * S
    if note:
        a(f'<text x="{x0}" y="{y0 + h_used + 22}" fill="#cfc9bb" font-size="14">{note[:46]}</text>')
        if len(note) > 46:
            a(f'<text x="{x0}" y="{y0 + h_used + 40}" fill="#cfc9bb" font-size="14">{note[46:92]}</text>')
            h_used += 18
        h_used += 22
    col_y[c] = y0 + h_used + 34

# rules the code depends on
ry = max(col_y) + 10
rules = [
    "MUST KEEP (code looks for these names):",
    "- 6 shop plots Plots.Plot1-6, 34 studs free behind each",
    "- Warehouse supply counter + its prompt",
    "- Museum Collection pedestal + its prompt",
    "- one SpawnLocation",
    "Everything else is free to move (I update the code).",
    "Walk up/down: steps 0.38 tall x 0.8 deep;",
    "  stairs/ramps 16 wide feel good.",
]
for i, t in enumerate(rules):
    a(f'<text x="{SX}" y="{ry + i * 26}" fill="{"#ffd36b" if i == 0 else "#e9e4d8"}" font-size="{19 if i == 0 else 17}" '
      f'font-weight="{700 if i == 0 else 400}">{t}</text>')
a('</svg>')

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "..", "assets", "template", "4_Map_Canvas_660x700.svg")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(o))
print("wrote", os.path.normpath(out), f"{W:.0f}x{H:.0f}")
