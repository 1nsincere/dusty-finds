"""Dusty Finds: turn Gemini item icons into clean, transparent 512 px PNGs for Roblox (Blender 5.x, headless).

Gemini often saves WebP files with a .png name AND paints a grey checkerboard where the transparency should be. This:
  1. loads each icon (Blender reads WebP),
  2. flood-fills the checkerboard from the image edges and makes it transparent (only neutral grey / black pixels that
     touch the border; the icons' brown ink outline stops the fill, so grey parts inside an item stay),
  3. shrinks to 512 x 512 and saves a real PNG named after the item's config id (Items.luau),
  4. trims every PNG in the output folder (also the ones exported from Figma) to the same framing (MARGIN).

Run:
  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/clean_icons.py
Env:
  DF_ICONS_IN   folder with the Gemini files (default assets/item-icons)
  DF_ICONS_OUT  where the clean PNGs go (default assets/models/item-icons)
"""

import os
import sys
from collections import deque

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import common as c  # noqa: E402

# Gemini file name (without extension) -> item id in Config/Items.luau
NAMES = {
    "aurora-crystal-music-box": "CrystalMusicBox",
    "boombox": "Boombox",
    "celetial-astrolabe": "Astrolabe",
    "celestial-astrolabe": "Astrolabe",
    "enamel-cup-mug": "EnamelMug",
    "golden-cartridge": "GoldenCartridge",
    "instant-camera": "InstantCamera",
    "jade-dragon-clock": "JadeDragonClock",
    "lava-lamp": "LavaLamp",
    "lunch-box": "LunchBox",
    "midnight-neon-jukebox": "Jukebox",
    "pixel-brick": "PixelBrick",
    "plush-bunny": "PlushBunny",
    "pocket-compass": "PocketCompass",
    "pocket-watch": "PocketWatch",
    "rotary-phone": "RotaryPhone",
    "slime-jar": "SlimeJar",
    "spinning-top": "SpinningTop",
    "starlight-orrery": "StarlightOrrery",
    "sticker-album": "StickerAlbum",
    "sunken-sun-idol": "SunIdol",
    "vinyls-record": "VinylRecord",
    "vinyl-record": "VinylRecord",
    # the 9 that first came from Figma, redrawn with Gemini so they match the set (2026-11-25)
    "rubber-duck": "RubberDuck",
    "floral-teacup": "Teacup",
    "teacup": "Teacup",
    "toy-race-car": "ToyCar",
    "toy-car": "ToyCar",
    "alarm-clock": "AlarmClock",
    "snow-globe": "SnowGlobe",
    "music-box": "MusicBox",
    "brass-baron-kettle": "CopperKettle",
    "kettle": "CopperKettle",
    "tin-robot": "TinRobot",
    "sir-clank": "TinRobot",
    "gramophone": "Gramophone",
    "unknown": "Unknown",
    "mystery": "Unknown",
    "mystery-item": "Unknown",
    "silver-tongue-gramaphone": "Gramophone",
    "silver-tongue-gramophone": "Gramophone",
}

SIZE = 512
# Gemini's painted checkerboard (measured on these files): 50 x 50 squares of ~20.5 px, dark grey ~0.15 and light grey
# ~0.66, starting dark in the top-left corner. Measured again per image from its top-left corner, so a different
# checker size still works.
TOLERANCE = 0.1  # how far (per channel) a pixel may be from the checker colour expected at its spot
NEUTRAL = 0.06  # checker pixels are pure grey: max - min of RGB below this
SEAM = 1.6  # px either side of a square edge where the two greys blend (any grey in between counts there)


def measure(px, h, w):
    """Square size + the two greys, from the top-left corner (Blender rows go bottom-up: row h - 1 is the top)."""
    row = px[h - 3, : min(w, 400), :3].mean(axis=1)
    th = (row.max() + row.min()) / 2
    runs, cur, n = [], row[0] > th, 0
    for v in row:
        if (v > th) == cur:
            n += 1
        else:
            runs.append(n)
            cur, n = v > th, 1
    inner = runs[1:-1] if len(runs) > 3 else runs
    square = float(np.mean(inner)) if inner else w / 50
    first_dark = not (row[0] > th)
    patch = px[h - int(square * 2) : h, : int(square * 2), :3].reshape(-1, 3)
    lum = patch.mean(axis=1)
    dark = patch[lum < th].mean(axis=0) if np.any(lum < th) else np.array([0.15, 0.15, 0.15])
    light = patch[lum >= th].mean(axis=0) if np.any(lum >= th) else np.array([0.66, 0.66, 0.66])
    return square, first_dark, dark, light


def clean(path_in: str, path_out: str) -> float:
    img = bpy.data.images.load(path_in)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[:, :, :3]
    square, first_dark, dark, light = measure(px, h, w)

    # the checker colour expected at every pixel (top-left square = dark when first_dark)
    ys, xs = np.mgrid[0:h, 0:w]
    top = (h - 1) - ys
    cx, cy = xs / square, top / square
    parity = (np.floor(cx).astype(int) + np.floor(cy).astype(int)) % 2
    expect_dark = (parity == 0) if first_dark else (parity == 1)
    expected = np.where(expect_dark[:, :, None], dark, light)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    neutral = spread < NEUTRAL
    exact = neutral & (np.abs(rgb - expected).max(axis=2) < TOLERANCE)
    # near a square edge the greys blend: any grey between the two shades is fine there
    near_seam = (np.minimum(cx - np.floor(cx), np.ceil(cx) - cx) * square < SEAM) | (np.minimum(cy - np.floor(cy), np.ceil(cy) - cy) * square < SEAM)
    lum = rgb.mean(axis=2)
    between = neutral & (lum > dark.mean() - TOLERANCE) & (lum < light.mean() + TOLERANCE)
    match = exact | (near_seam & between)

    def fill(starts, allowed):
        got = np.zeros((h, w), dtype=bool)
        q = deque()
        for y, x in starts:
            if allowed[y, x] and not got[y, x]:
                got[y, x] = True
                q.append((y, x))
        while q:
            y, x = q.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and allowed[ny, nx] and not got[ny, nx]:
                    got[ny, nx] = True
                    q.append((ny, nx))
        return got

    border = [(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)]
    bg = fill(border, match)

    # enclosed checker (a mug handle, a chain, orrery rings): a region of matching pixels that shows BOTH shades where
    # the checker would put them. An item's own silver or black parts only ever match one of the two shades.
    seen = bg.copy()
    exact_dark = exact & expect_dark
    exact_light = exact & ~expect_dark
    step = max(2, int(square // 4))
    for sy in range(0, h, step):
        for sx in range(0, w, step):
            if not match[sy, sx] or seen[sy, sx]:
                continue
            comp = fill([(sy, sx)], match & ~seen)
            seen |= comp
            size = int(comp.sum())
            if size < square * square * 0.8:
                continue
            nd = int((comp & exact_dark).sum())
            nl = int((comp & exact_light).sum())
            if nd > size * 0.2 and nl > size * 0.2:
                bg |= comp

    # leftovers: seam lines (squares are 20 or 21 px, so the grid drifts) and bands where Gemini warped the checker.
    # Any plain grey in the checker's range that touches the removed background goes too; the icons' brown ink outline
    # is not grey, so the fill stops at the item.
    loose = neutral & (lum > dark.mean() - TOLERANCE) & (lum < light.mean() + TOLERANCE)
    bg = fill([(int(y), int(x)) for y, x in zip(*np.nonzero(bg))], loose | bg)

    # soften the cut: a 1 px half-transparent rim where the item meets the removed background
    edge = np.zeros_like(bg)
    edge[1:, :] |= bg[:-1, :]
    edge[:-1, :] |= bg[1:, :]
    edge[:, 1:] |= bg[:, :-1]
    edge[:, :-1] |= bg[:, 1:]
    edge &= ~bg
    alpha = np.where(bg, 0.0, np.where(edge & neutral, 0.5, 1.0)).astype(np.float32)
    px[:, :, 3] = alpha
    px[bg, :3] = 0.17  # dark ink under the transparent part, so shrinking never leaves a light halo
    out = bpy.data.images.new(os.path.basename(path_out), w, h, alpha=True)
    out.pixels[:] = px.reshape(-1)
    out.scale(SIZE, SIZE)
    out.filepath_raw = path_out
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(img)
    bpy.data.images.remove(out)
    return float(bg.mean())


MARGIN = 0.05  # empty border kept around every icon after trimming (fraction of the side)


def fit(path: str):
    """Trims an icon to its visible pixels and centres it on a square with the same small margin as every other icon,
    so Gemini icons (lots of empty space) and the Figma ones (edge to edge) end up the same size in the game."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    # solid pixels only, and ignore rows / columns with just a few stray specks left from the background
    solid = px[:, :, 3] > 0.9
    need = max(3, int(min(w, h) * 0.01))
    rows = np.nonzero(solid.sum(axis=1) >= need)[0]
    cols = np.nonzero(solid.sum(axis=0) >= need)[0]
    if len(rows) == 0:
        bpy.data.images.remove(img)
        return
    crop = px[rows[0] : rows[-1] + 1, cols[0] : cols[-1] + 1]
    ch, cw = crop.shape[:2]
    side = int(max(ch, cw) / (1 - 2 * MARGIN))
    canvas = np.zeros((side, side, 4), dtype=np.float32)
    canvas[:, :, :3] = 0.17
    oy, ox = (side - ch) // 2, (side - cw) // 2
    canvas[oy : oy + ch, ox : ox + cw] = crop
    out = bpy.data.images.new(os.path.basename(path), side, side, alpha=True)
    out.pixels[:] = canvas.reshape(-1)
    out.scale(SIZE, SIZE)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(img)
    bpy.data.images.remove(out)


def main():
    src = os.environ.get("DF_ICONS_IN") or os.path.join(c.ROOT, "assets", "item-icons")
    dst = os.environ.get("DF_ICONS_OUT") or os.path.join(c.OUT_MODELS, "item-icons")
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        stem = os.path.splitext(name)[0].lower()
        item_id = NAMES.get(stem)
        if item_id is None:
            print(f"SKIP {name}: no item id for it (add it to NAMES)")
            continue
        removed = clean(os.path.join(src, name), os.path.join(dst, item_id + ".png"))
        print(f"ICON {item_id}: background removed {removed * 100:.0f}% of the image")
    # every icon in the output folder (the cleaned Gemini ones AND the ones exported from Figma) gets the same framing
    for name in sorted(os.listdir(dst)):
        if name.lower().endswith(".png"):
            fit(os.path.join(dst, name))
            print(f"FIT {name}")
    print("done")


main()
