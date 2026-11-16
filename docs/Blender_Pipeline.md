# Blender item pipeline (Dusty Finds)

Goal: smooth, professional-looking item models (26 items, `docs/02_Economy.md` §4b) made from code in Blender, imported into Studio, and wrapped for the restore minigames. Free tools only. Works with Claude Code or Codex CLI because everything is plain scripts in the repo.

## 0. Setup (once per PC)
- Install Blender (free, blender.org). We use 5.3: `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe`. Other 4.x/5.x versions probably work; the scripts were only tested on 5.3.
- `git pull` main. You need `tools/blender/` (helpers + examples) and `tools/studio/WrapImportedItem.luau`.

## 1. Make a model (Blender, headless)
Copy an example (`tools/blender/teacup.py` for lathed round things, `tools/blender/kettle_hq.py` for the high-quality style) to `tools/blender/<itemid>.py`, change the shape, run:
`"C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --python tools/blender/<itemid>.py`
It writes `assets/models/<Name>.glb` (the file for Studio) and `assets/previews/<Name>.png` (look at it before importing). Both folders are git-ignored; the scripts are the source of truth.

**Rules**
- 1 Blender unit = 1 stud. Item width about 1.6 to 2.2 studs (the Rubber Duck is 1.65). Z is up.
- **One Blender object per colour/material group**, named for what it is (`Body`, `Lid`, `Handle`, `Rim`...). Roblox makes one MeshPart per object; colours are set in Studio by that name. No textures needed.
- Smooth shading, bevels, tapers: use `lathe`, `tube` (tapered Bezier pipe), `torus`, `sphere`, `box`, `join`, `finish(..., bevel=, subsurf=)` from `tools/blender/common.py`.
- Triangle budget: aim 3,000 to 5,000 per item (shelves show many items on phones). Hard limit 20,000 per mesh. The script prints `TRIANGLES n`.
- Palette: `PALETTE` in `common.py`; see "Item colours" below.
- Recognisable silhouette first, details second. Test the preview at small size.

## 2. Import into Studio
Studio, Home tab, **Import 3D**, pick the `.glb`, Import (needs your Roblox login; Team Create shares the result). A Model named `Scene` appears in Workspace, one sub-model per Blender object.

## 3. Wrap it (colours, base, restore spots)
Open `tools/studio/WrapImportedItem.luau`, edit the `CONFIG` block (item id, rotation, colours by part name, polish parts, dirt/rust/socket positions), paste into **View > Command Bar** in Edit mode, Enter. It builds the final model at `ReplicatedStorage.Assets.Items.<ItemId>`. Then File > Save.

## 4. Test (always)
Play, give yourself the item (`game.ServerStorage.DevTools:Invoke("giveItem", player, "<ItemId>", "Dirty")` in the command bar, server side), stand at the bench, Inventory > the item > Restore. Check: item fully visible, dirt marks visible, you can rub them off, every step of the recipe works. Run `testAll` (docs/08).

## 5. Rules the model must keep (docs/Item_Model_Contract_DRAFT.md)
`Base` (PrimaryPart, a plate), `DirtSpots` (Wipe) / `RustSpots` (Scrape) with spot Parts 0.6 studs ON the outside surface, `PolishSurfaces` folder, `Sockets` + `LooseParts` with matching names (Replace/Reassemble, decoys for Replace), `TestPoint` (Test). Anchored, CanCollide false. At most 60 parts. Never rename config ids.

## 6. Item colours (suggestion, decide as a team)
The town palette (docs/Environment_Art.md) is muted on purpose so items pop. Items may use a richer set: copper `D2694A`, brass `B08D57` (a duller brass; the Golden variant uses bright gold `FFD43B`, so avoid bright yellow-gold as a main item colour), chrome `C9CED6`, dark steel `3A3F47`, walnut `9C6B43`, ceramic white `FAF7F2`, cream `F4F0E8`, royal blue `2E4A7D`, teal `1F7A7A`, coral `E9795F`, rose `D98A9A`, mint `8ED1B2`, sunny `F2C94C`, lilac `9B8CC4`, toy red `C0392B`. Rarity colours (UI borders) are in `src/Client/UiTheme.luau`; never recolour an item to a rarity colour.

## 7. Prompt for Codex CLI / Claude Code
See the section "Prompt" in the chat history or ask Ace; the short version: read this file and the two examples, then write `tools/blender/<itemid>.py` for the item in `src/Shared/Config/Items.luau`, run it, look at the preview, fix, and report triangles and the preview path.

**Orientation (learned on the kettle):** the bench camera sits on the -Z side of the item looking toward +Z; its right is -X. The glTF importer flips Blender X. So model the front toward Blender +Y... in practice: a handle or spout you build on Blender +X appears on the RIGHT of the screen with `ROTATE_Y_DEGREES = 0`, and spots belong on the -Z side. Check with a Play test before trusting.

**Do not rotate the Base plate.** The bench view uses the Base (PrimaryPart) orientation as the item's frame; only rotate the other parts (the wrapper does this with `ROTATE_Y_DEGREES`).
