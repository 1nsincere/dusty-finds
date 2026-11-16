# Generates the map-planning template images for Dusty Finds (run with Windows PowerShell; no extra software needed).
#   powershell -ExecutionPolicy Bypass -File tools/template/make_map_template.ps1
# Output: assets/template/1_Map_Canvas.png, 2_Stamp_Sheet.png, 3_Brief.png  (all at 5 pixels = 1 stud, so boxes copy over 1:1)
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root "assets\template"
New-Item -ItemType Directory -Force $out | Out-Null
$PX = 5            # pixels per stud
$MAP = 480         # playable map is 480 x 480 studs (fits the 500 stud desk)

function Brush($hex) { $c = [System.Drawing.ColorTranslator]::FromHtml("#$hex"); return New-Object System.Drawing.SolidBrush($c) }
function PenOf($hex, $w, $dash) { $p = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#$hex"), $w); if ($dash) { $p.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash }; return $p }
function Font($size, $bold) { $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }; return New-Object System.Drawing.Font("Segoe UI", $size, $style) }
function Text($g, $s, $f, $hex, $x, $y) { $g.DrawString($s, $f, (Brush $hex), $x, $y) }
function NewCanvas($w, $h, $bg) { $b = New-Object System.Drawing.Bitmap($w, $h); $g = [System.Drawing.Graphics]::FromImage($b); $g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAliasGridFit"; $g.Clear([System.Drawing.ColorTranslator]::FromHtml("#$bg")); return @($b, $g) }

# ================= 1. MAP CANVAS =================
$size = $MAP * $PX
$b, $g = NewCanvas $size $size "FBF7EF"
# grid every 20 studs, strong line every 100
for ($s = 0; $s -le $MAP; $s += 20) {
    $strong = ($s % 100 -eq 0)
    $pen = if ($strong) { PenOf "B9B2A3" 3 $false } else { PenOf "E4DED0" 1 $false }
    $g.DrawLine($pen, $s * $PX, 0, $s * $PX, $size)
    $g.DrawLine($pen, 0, $s * $PX, $size, $s * $PX)
    if ($strong) { Text $g "$s" (Font 16 $true) "8A8272" ($s * $PX + 4) 4; Text $g "$s" (Font 16 $true) "8A8272" 4 ($s * $PX + 4) }
}
$g.DrawRectangle((PenOf "22252B" 8 $false), 4, 4, $size - 8, $size - 8)
# central park zone: radius 75 studs at the centre (240, 240)
$c = $MAP / 2 * $PX
$r = 75 * $PX
$g.FillEllipse((Brush "E3F2DC"), $c - $r, $c - $r, 2 * $r, 2 * $r)
$g.DrawEllipse((PenOf "6FA070" 6 $true), $c - $r, $c - $r, 2 * $r, 2 * $r)
Text $g "CENTRAL PARK" (Font 40 $true) "4F7F52" ($c - 190) ($c - 120)
Text $g "(concept: Wishing Fountain Plaza)" (Font 22 $false) "4F7F52" ($c - 200) ($c - 60)
Text $g "you decide: fountain, paths, play area, flower beds, trees..." (Font 18 $false) "6A8F6B" ($c - 280) ($c)
Text $g "150 studs wide" (Font 16 $false) "6A8F6B" ($c - 60) ($c + 60)
# ring road guide (suggested, radius 101 outside edge of the road ring)
$rr = 101 * $PX
$g.DrawEllipse((PenOf "9AA0A6" 3 $true), $c - $rr, $c - $rr, 2 * $rr, 2 * $rr)
Text $g "suggested ring road edge (radius 101): optional" (Font 14 $false) "9AA0A6" ($c - 220) ($c + $rr + 6)
# entry / spawn marker at the south edge (bottom centre)
$ex = $c
$tri = [System.Drawing.Point[]]@([System.Drawing.Point]::new([int]$ex, [int]($size - 130)), [System.Drawing.Point]::new([int]($ex - 60), [int]($size - 30)), [System.Drawing.Point]::new([int]($ex + 60), [int]($size - 30)))
$g.FillPolygon((Brush "D2694A"), $tri)
Text $g "ENTRY / SPAWN" (Font 22 $true) "D2694A" ($ex - 100) ($size - 170)
Text $g "N" (Font 40 $true) "22252B" ($size - 70) 20
$g.DrawLine((PenOf "22252B" 6 $false), $size - 52, 120, $size - 52, 70)
Text $g "MAP CANVAS  -  480 x 480 studs  -  5 pixels = 1 stud  -  grid lines every 20 studs (strong every 100)" (Font 18 $true) "22252B" 20 ($size - 40)
$b.Save((Join-Path $out "1_Map_Canvas.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose()

# ================= 2. STAMP SHEET (boxes to scale, 5 px = 1 stud) =================
$W = 2600; $H = 1900
$b, $g = NewCanvas $W $H "FFFFFF"
Text $g "STAMP SHEET - copy a box onto the map canvas, rotate it, move it. Do NOT resize the fixed ones (their size is real)." (Font 20 $true) "22252B" 20 14
$items = @(
  @{ n = "SHOP LOT  x6"; w = 56; h = 56; fill = "BFE3E0"; border = "1F7A7A"; note = "FIXED size 56 x 56. The player's shop. The bar marks the DOOR side: the door must face a street."; door = $true },
  @{ n = "MUSEUM"; w = 70; h = 46; fill = "E3D4F0"; border = "6E4A7E"; note = "FIXED 70 x 46. Opens the Collection Book. Door on a long side."; door = $true },
  @{ n = "WAREHOUSE (supply)"; w = 80; h = 50; fill = "F5E3B3"; border = "B08D57"; note = "FIXED 80 x 50. The ONLY place to buy crates: players must walk here. 150-200 studs from the shops."; door = $true },
  @{ n = "DEPOT / STATION"; w = 94; h = 60; fill = "F4C9BD"; border = "D2694A"; note = "FIXED 94 x 60. Train depot landmark (can be placed at the entry)."; door = $true },
  @{ n = "CLOCK TOWER"; w = 22; h = 22; fill = "D9D2C5"; border = "22252B"; note = "FIXED 22 x 22. Tall landmark, best seen from far down a street."; door = $false },
  @{ n = "ENTRY GATE"; w = 34; h = 12; fill = "F8D7C9"; border = "D2694A"; note = "FIXED 34 x 12. Arch across the entry road; players spawn just inside."; door = $false },
  @{ n = "FREE LOT A"; w = 40; h = 40; fill = "F4F0E8"; border = "9AA0A6"; note = "YOU DECIDE what it is (cafe, bakery, library...). Visual only, can be any size."; door = $true },
  @{ n = "FREE LOT B"; w = 30; h = 20; fill = "F4F0E8"; border = "9AA0A6"; note = "Small free lot (stall, kiosk, ticket booth...). Any size."; door = $true }
)
$x = 20; $y = 70; $rowH = 0
foreach ($it in $items) {
  $bw = $it.w * $PX; $bh = $it.h * $PX
  if ($x + $bw + 40 -gt $W) { $x = 20; $y += $rowH + 90; $rowH = 0 }
  $g.FillRectangle((Brush $it.fill), $x, $y, $bw, $bh)
  $g.DrawRectangle((PenOf $it.border 5 $false), $x, $y, $bw, $bh)
  if ($it.door) { $g.FillRectangle((Brush $it.border), ($x + $bw / 2 - 40), ($y + $bh - 12), 80, 12) }
  # small boxes: the labels go UNDER the box so they do not cover it
  $small = ($bw -lt 200)
  $ty = if ($small) { $y + $bh + 4 } else { $y + 6 }
  Text $g $it.n (Font 18 $true) $it.border ($x + 8) $ty
  Text $g ("{0} x {1} studs" -f $it.w, $it.h) (Font 13 $false) "5A5A5A" ($x + 8) ($ty + 28)
  $noteY = if ($small) { $y + $bh + 64 } else { $y + $bh + 4 }
  $note = New-Object System.Drawing.RectangleF($x, $noteY, [Math]::Max($bw, 360), 70)
  $g.DrawString($it.note, (Font 12 $false), (Brush "3A3A3A"), $note)
  $x += [Math]::Max($bw, 360) + 40
  if ($bh -gt $rowH) { $rowH = $bh }
}
# colour legend for drawing the rest
$ly = $y + $rowH + 160
Text $g "COLOURS TO DRAW WITH (so I can read your map):" (Font 20 $true) "22252B" 20 $ly
$legend = @(
  @("ROAD / street (light grey, DRAW ON 12-30 stud wide ways)", "C9CED6"),
  @("PLAZA / paved square (warm stone)", "E8DCC2"),
  @("PARK / grass / flower beds (green)", "BFE3A8"),
  @("WATER / pond / fountain (light blue)", "9ED3EA"),
  @("TREES (dark green dots)", "3F7F4A"),
  @("BACKGROUND BUILDINGS (white, any shape)", "F4F0E8"),
  @("PATH / footpath (sand)", "E3C98A"),
  @("SPECIAL IDEA (pink: write a short note beside it)", "F6B8CC")
)
$lx = 20; $ly += 50
foreach ($l in $legend) {
  $g.FillRectangle((Brush $l[1]), $lx, $ly, 70, 50)
  $g.DrawRectangle((PenOf "7A7A7A" 2 $false), $lx, $ly, 70, 50)
  Text $g $l[0] (Font 14 $false) "22252B" ($lx + 82) ($ly + 12)
  $ly += 66
  if ($ly -gt $H - 70) { $ly = ($y + $rowH + 210); $lx += 1250 }
}
$b.Save((Join-Path $out "2_Stamp_Sheet.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose()

# ================= 3. ONE-PAGE BRIEF =================
$b, $g = NewCanvas 1700 2400 "FFFDF8"
Text $g "Dusty Finds: map planning brief" (Font 44 $true) "22252B" 70 60
Text $g "A cozy restoration-and-sell game. Players own a shop, restore old objects, and sell them to customers who walk in." (Font 18 $false) "3A3A3A" 70 140
$lines = @(
  @("THE BIG IDEA", $true),
  @("A circular PARK in the middle (like Fuente Osmena Circle in Cebu) with a fountain and play spaces kids love. Six shops sit around it and in the streets, plus a Museum and a Warehouse. It must feel welcoming for kids and teens.", $false),
  @("WHAT THE GAME NEEDS (the skeleton, please keep these)", $true),
  @("1. Six player SHOPS, each 56 x 56 studs (a stamp is on the Stamp Sheet). Each shop's DOOR must face a street, because customers walk in from the street.", $false),
  @("2. A MUSEUM (opens the Collection Book) and a WAREHOUSE. The Warehouse is the ONLY place to buy crates, so it must be a real but short walk from the shops: about 150-200 studs.", $false),
  @("3. An ENTRY / SPAWN at the south edge where players arrive, a CLOCK TOWER, and the central PARK circle (150 studs wide).", $false),
  @("4. Everything inside the map border: 480 x 480 studs. Do not draw outside it.", $false),
  @("5. Streets 12-30 studs wide. Players walk everywhere, so keep it readable: no mazes, no dead ends that look like roads.", $false),
  @("6. Phones are weak: do not fill the map with huge forests or hundreds of tiny details. A few strong places beat many small ones.", $false),
  @("WHERE YOU ARE FREE TO BE CREATIVE", $true),
  @("The shape and flow of the streets and plazas. What the park contains. Side gardens, a pond, a market corner, bridges, benches, seating areas. What the FREE LOTS are (cafe, bakery, library, a little cinema...). Moods: a quiet garden vs a busy market. Anything that makes it feel like a real, lived-in town.", $false),
  @("HOW TO DRAW", $true),
  @("Open 1_Map_Canvas.png in Procreate (or any drawing app) as a new canvas. Make a NEW LAYER on top for your drawing and leave the grid layer alone. Paste the boxes from 2_Stamp_Sheet.png (they are the same scale: 5 pixels = 1 stud). Use the colours in the legend so the map can be read. Write short notes next to anything special (e.g. 'splash fountain here', 'carousel'). Export a PNG (keep the full size) and send it.", $false),
  @("OPTIONAL", $true),
  @("Side-view sketches of 2-3 buildings you love (the museum, a cafe, the fountain) as inspiration. They will be rebuilt in the game's soft low-poly style, so they will not be copied exactly, and that is fine.", $false)
)
$y = 220
foreach ($l in $lines) {
  if ($l[1]) { $y += 30; Text $g $l[0] (Font 24 $true) "1F7A7A" 70 $y; $y += 48 }
  else {
    $rect = New-Object System.Drawing.RectangleF(70, $y, 1560, 300)
    $g.DrawString($l[0], (Font 17 $false), (Brush "22252B"), $rect)
    $m = $g.MeasureString($l[0], (Font 17 $false), 1560)
    $y += [int]$m.Height + 16
  }
}
$b.Save((Join-Path $out "3_Brief.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose()
Write-Output "done: $out"
