# Visual system

How the game gets its look, and why each piece works the way it does.

## The constraint that drives everything

Terrain destruction is **per-pixel**, and playtest feedback explicitly rejected
the blocky grid look. That rules out the cheapest source of 3D depth in a tile
game — a per-tile bevel — because a bevel *is* a drawn grid. Every technique
below is chosen to add depth and richness **without** re-introducing cell edges.

## 1. Rim shading (`assets/shaders/terrain.gdshader`)

Chunk textures are a pixel mask: carved rock is transparent, solid rock opaque.
The shader samples alpha in two rings around each solid pixel and darkens it in
proportion to nearby open space. Every tunnel wall gets a soft contact shadow,
so holes read as recessed.

Because it reads the carve mask itself, **freshly drilled tunnels are shaded the
instant they appear** — no CPU work, no re-shading pass on carve. Sampling
outside the chunk returns "solid", which stops chunk seams rendering as lines.

## 2. Anti-tiling mottle

A 32px rock tile stamped across a chunk reads as a repeating pattern no matter
how good the texture is. Two things fix it:

- **Textures are low-contrast** (`contrast≈0.42`), supplying fine grain only.
- **The shader adds smooth value noise** at ~0.37 and ~1.13 cells/period.

The frequencies are deliberately fractional so features never align to cell
edges. An earlier attempt used a *per-cell* hash — that failed badly: giving
each cell one uniform brightness just draws the grid back as a checkerboard.
Variation has to be continuous across cell boundaries.

## 3. Ore as a blended overlay

Ore tiles in the atlas are **transparent gem overlays**, not full tiles. When a
chunk image is built, `_ensure_image()` blits the layer's own rock first, then
`blend_rect`s the gems on top. Ore therefore never paints a background square of
its own — gems look embedded in the surrounding stone.

This is the single biggest contributor to the terrain not looking blocky.

## 4. Crust edges on pool materials

Magma and water *are* whole-cell materials, so they can't use the overlay trick.
Instead `crust_edges()` fades each tile toward a dark crust near its border.
Isolated cells read as pools; adjacent cells merge into a continuous flow.
Without this, magma renders as flat neon squares.

## 5. Backdrop (`assets/shaders/backdrop.gdshader`)

One full-screen quad draws both sky and underground:

- Above ground: vertical gradient, warmer toward the horizon.
- Below: banded strata from value noise, scrolling at `parallax = 0.35` of
  camera speed, tinted toward `core_glow` with depth.
- The two cross-fade over the first ~420px so the surface isn't a hard cut.

## 6. Depth vignette (`assets/shaders/vignette.gdshader`)

A light pool centred on the pod, projected into screen UV each frame. Strength
ramps with depth and radius tightens (1.25 → 0.62). Near-invisible at the
surface, claustrophobic at the Core. It sits on CanvasLayer 5 — above the world,
below the HUD (layer 10) — so UI is never dimmed.

## 7. HUD

Built on research-backed rules rather than taste:

- **Urgency hierarchy** — heat is the primary loss condition, so the heat bar is
  the loudest element and pulses past the warning threshold. Hull and cargo sit
  at full contrast. Money and ether are progress readouts and stay quiet
  (`alpha 0.85`, smaller type).
- **Stable positions** — nothing moves; only values animate.
- **Legibility over terrain** — `UIKit.legible()` puts a black outline and
  shadow on every HUD label, so text survives bright rock, dark caves and magma.
- **Round touch pads** — `UIKit.touch_pad()` replaces filled rectangles. Same
  ≥88px target, far less visual weight over the world.

## Effects bus

Gameplay never references the camera or particle layer. `Player` and enemies
emit `Events.fx_burst` / `Events.fx_shake`; `FXLayer` and `Game` listen. This
keeps the documented decoupling intact.

`FXLayer` is a **Node2D, not a CanvasLayer** — bursts are emitted at world
coordinates, so the layer must share the world transform or every spark would
draw in the wrong place once the camera moves.

## Regenerating art

```bash
python tools/generate_assets.py
```

Godot caches imported textures, so after regenerating you must force a rescan
or the old art keeps rendering:

```bash
godot --headless --editor --quit --path .
```

Review shots without playing:

```bash
godot --path . res://tools/screenshot_runner.tscn   # menu, surface, shop
godot --path . res://tools/deep_shot.tscn           # layer 3 and layer 5
```
