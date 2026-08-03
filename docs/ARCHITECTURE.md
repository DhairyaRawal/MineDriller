# Architecture

## Principles

- **Data-driven**: every tunable number lives in `data/balance.json`, loaded once by the
  `Balance` autoload. No gameplay script hard-codes a value a designer might want to change.
- **Signal bus decoupling**: gameplay, UI, audio and persistence never reference each other
  directly. They communicate through the `Events` autoload (a pure signal bus). The HUD, for
  example, is fully functional with zero references to the player.
- **Code-built scenes**: `.tscn` files contain only a root node + script. All node trees are
  constructed in `_ready()`. This keeps diffs reviewable and eliminates scene/script drift.
- **No physics server**: collision is a purpose-built **circle-vs-pixel-terrain** sweep
  (`TerrainBody`), shared by player and enemies. Bodies are circles that sample terrain
  solidity at points around their perimeter; sub-stepped and gap-closing so they sit flush
  to surfaces. Deterministic, allocation-light, and much cheaper than PhysicsServer2D.
- **Destruction is per-pixel, not per-tile**: the drill carves smooth round holes out of a
  half-resolution pixel field, so tunnels and caves are organic, not blocky. Cell *content*
  (which layer, ore, hard rock, gate) is still a pure function of position; only the carve
  mask is stateful.
- **Depth comes from shaders, never from bevels**: a per-tile bevel would redraw the grid
  we deliberately removed. Instead the terrain shader reads the carve mask's alpha to shade
  tunnel rims, and adds continuous noise to break tile repetition. See
  [VISUALS.md](VISUALS.md).
- **Presentation rides the signal bus too**: gameplay emits `Events.fx_burst` /
  `Events.fx_shake`; the FX layer and camera listen. The player and enemies hold no
  reference to the camera or particle system.

## Autoload order (matters)

| Autoload | Responsibility |
|---|---|
| `Balance` | loads/serves balance.json; upgrade cost & ore-weight math |
| `Events` | global signal bus (~20 signals) |
| `SettingsManager` | input map registration (in code), volumes, haptics, handedness |
| `GameState` | persistent progress + current-run cargo; all derived stats |
| `SaveManager` | debounced, versioned, backup-protected JSON persistence |
| `AudioManager` | creates Music/SFX buses in code; pooled SFX players; loop players |

## World generation (`scripts/world/world.gd`)

`cell_info(cell)` is a **pure function** of `(x, y, seed)` plus a handful of small diff
sets (mined cells, carved-past-threshold cells, opened chests). Order of evaluation per cell:

1. Horizontal/bottom bounds → bedrock (walls extend above the surface).
2. Sky (y < 0) → empty.
3. Mined or carved-past-threshold → empty (see "World persistence" below).
4. Row 0 → grass.
5. Treasure-room rect (per-chunk cached roll) → empty + chest cell.
6. Depot room rect (3 fixed rooms per layer, 15 total — see "Depots" below) → empty, walk-in.
7. Layer transition band (last 2 rows of each layer) → solid next-tier hard rock. **This is
   the depth gate**: bit level N is required to enter layer N.
8. Cave noise (FastNoiseLite simplex, threshold loosens with depth) → empty / water (L1-2) /
   magma (L3+).
9. Ore roll (per-layer chance; rare weights scale up near the layer bottom).
10. Hard-rock scatter roll → hard (tier = layer id).
11. Otherwise soft rock.

**Streaming**: the world is 32×360 tiles. Each 32×16-tile chunk owns a half-resolution `Image`
built from the tile atlas; `stream_around(row)` keeps ±2–3 chunks' sprites alive and drops the
rest. The chunk *images* persist for the whole session, so carved tunnels never reset. Enemy
spawn rolls happen once per chunk per session (cleared areas stay cleared). Every chunk that's
ever been loaded is marked in `_visited_chunks`, which backs both save persistence and the
map screen's fog-of-war (see below) — streaming, saving and the map all read the same signal
for "has the player actually been here."

Carving (`carve_circle`) erases pixels of any cell the current bit can cut (bedrock and
too-hard rock stand); ore/chest cells collect once enough of them is eroded. Collision
(`is_solid_px`) reads cell content first, then the pixel mask — so a mined-out tunnel is
walkable even though its cell still "belongs" to soft rock. Cave cells get organically rounded
at generation time (`_round_cave_edges`).

## Player (`scripts/player/player.gd`)

FSM: `DRIVE` with a `BUSTED` terminal (until respawn); `drilling` is a per-frame flag.

- **Move**: gravity + horizontal walking + a **jump** (no flight). `step_up` lets the pod walk
  up gentle carved slopes automatically.
- **Drill**: continuous pixel carving in the input direction. Down → bore straight down;
  push into a wall → drill sideways; **hold up + a direction into a wall → carve a rising
  diagonal ramp** and ride it up. There is deliberately no straight-up drilling, so ascent is
  a route you carve and reuse (GDD: "going up is different from going down"). Ramps carve at a
  shallower angle and a slightly wider radius than a straight bore (`ramp_angle_ratio` /
  `ramp_carve_radius_mult` in balance.json) — a smoother grade to walk, not a speed change.
  An ore cell the player can't hold (cargo full) is left standing rather than destroyed —
  `carve_circle`'s `can_collect_ore` parameter — so it's still there once there's room.
- **Rotation**: the sprite banks toward the current drill/travel direction, clamped to
  roughly ±30° and eased with `lerp_angle` — the art reads nose-down with treads at the base,
  so a full spin would read as upside-down.
- **Heat**: `heat += drill_rate` while carving (hard rock is hotter), else decays toward the
  **ambient floor**
  `55 · depth_frac · (1 − 0.08·(cooling_lvl−1))`. The floor is drawn on the HUD bar, so the
  shrinking cooldown budget is always visible. 100 = explosion = bust. Water contact
  (`world.is_water_px`, the dynamic per-pixel check, not the static generation cell) gives an
  instant cooldown once per cell.
- **Bust** (GDD lose condition): overheat, hull 0, or Government Driller contact. Cargo is
  cleared, money kept, respawn at the surface. Ore already banked at a depot is untouched —
  `lose_cargo()` only ever clears `GameState.cargo`.

## Depots (`scripts/ui/depot_screen.gd`, `MineWorld.depot_positions`)

3 fixed, deterministic safe-spot rooms per layer (15 total), placed the same way as treasure
vaults — a seeded, cached `depot_positions()` — but as a fixed count per layer rather than a
per-chunk chance roll. Each is a walk-in room (pre-hollowed in `cell_info`, no chest to drill
open); interaction is a plain proximity check in `game.gd._process` against the 15 fixed
points (cheap — no `Area2D`), driving `Events.depot_proximity` so the HUD can show a DEPOT
button without holding a reference to the player or world.

`GameState.depot_storage` (`depot_id -> {ore_id: count}`, capped per depot by
`balance.json`'s `depot.capacity`) is separate from `cargo`, so `deposit_ore`/`withdraw_ore`
moving ore between them is what makes a depot bust-proof: `lose_cargo()` never touches
`depot_storage` at all. Deposited ore still has to be withdrawn and carried to the surface to
actually sell — a depot removes risk, not the trip.

## Map (`scripts/ui/map_screen.gd`)

Reveals the world one *chunk* at a time — the same granularity `_visited_chunks` already
tracks, so there's no false precision. A custom `Control._draw()` (same technique as the
HUD's `HeatBar`) stacks chunk bands top-to-bottom, tinting visited ones by layer and leaving
unvisited ones as fog. Depot markers only render inside an already-visited chunk. Pauses the
tree while open (`DiscoveryCard`'s precedent for a mid-play interrupt) so reading the map
doesn't cost heat or let an enemy close the distance.

## Water simulation (`MineWorld` "water simulation" section)

Water is a second per-pixel layer at the same half-resolution grid as the terrain carve mask
— a separate `Image`/`Sprite2D` pair per chunk, not packed into the terrain image itself
(`terrain.gdshader` zeroes color wherever alpha is near zero, so data hidden in a carved
pixel's RGB would never reach a fragment shader that could render it). Water starts wherever
generation placed a `WATER` cell, then actually falls/spreads once drilling opens a path,
via a small falling-sand rule (`_flow_water_px`): straight down, else diagonal, else a slow
sideways spread.

Movement is per-pixel, but a simulation tick doesn't scan a screen-sized pixel window —
`_water_cells` is a coarse cell-level index of which cells currently hold any water, and only
cells within `WATER_SIM_REACH_CELLS` of the player get scanned. That's the "active radius":
which *regions* get simulated, not a reduction in per-pixel fidelity. Throttled to 20 Hz
(`WATER_SIM_INTERVAL`) and budget-capped per tick (`WATER_SIM_BUDGET`) so a large flooded
cavern opening at once spreads its cost over several ticks. Called externally from
`game.gd._process` (`step_water_simulation(player.position, delta)`) rather than from
`MineWorld`'s own `_process`, since `MineWorld` deliberately holds no reference to the player.

Water state is session-only: it is not part of `export_diff()` and re-seeds from the static
generation cells on every load, same spirit as the rest of the "coarse diff" persistence
choice below.

## Enemies

`EnemyBase` implements the shared PATROL/CHASE FSM, circle-terrain movement, ledge-turning,
contact damage and distance despawn. Subclasses restyle it: `Crawly` (pure patrol), `ZombieMiner`
(lurching chase), `GovtDriller` (hovering, siren, instant-bust contact). Stats come from
`balance.json`; spawn tables are per-layer.

## UI

`UIKit` is a static factory (buttons ≥ 88 px tall, styled panels, progress bars, modals) —
one visual system, no theme resources. Screens: `HUD` (status, heat bar with floor marker,
touch D-pads, toasts), `ShopScreen`, `DepotScreen`, `MapScreen`, `SellPopup`, `BustScreen`,
`PauseMenu`, `SettingsPanel` (shared by menu + pause), main menu panels
(codex / achievements / stats / options).

## Persistence

`SaveManager` writes `user://savegame.json` `{version, saved_at, state}`:

- **Debounced**: `request_save()` batches rapid events; writes at most ~1/s.
- **Lifecycle-safe**: forced save on `APPLICATION_PAUSED` / `FOCUS_OUT` / `WM_CLOSE_REQUEST`
  (Android backgrounding).
- **Corruption-safe**: previous good save kept as `.bak`; unparseable saves fall back to it.
  `GameState.from_dict` clamps/validates every field.
- **Migratable**: `_migrate()` steps saves forward one version at a time. v2 added
  `world_diff` / `last_position` / `cargo` / `depot_storage`; old v1 saves load fine since
  every new field defaults cleanly in `from_dict` (additive schema growth, no transform step
  needed).

**World persistence is a "coarse diff," not exact pixels**: `GameState.world_diff` is an
opaque payload round-tripped from `MineWorld.export_diff()`/`import_diff()` — the existing
`_mined`/`_opened_chests` diffs plus a new `_carved_cells` diff (a cell is marked "dug" once
`carve_circle` has eroded past `DUG_THRESHOLD_FRAC`, independent of the ore/chest-specific
`_mined` tracking) and `_visited_chunks`. On reload, the world regenerates from `world_seed`
and reapplies the diff: dug cells return fully cleared (rounded pixel edges reset to plain
empty), which is mechanically and visually equivalent to the original dig but not
pixel-identical. `SaveManager` doesn't know about `MineWorld` at all — it emits a
`before_save` signal right before writing, and `game.gd` (which holds both) is the one
listener that pulls a fresh `world.export_diff()` at that moment, so the diff is exported once
per actual write rather than every frame. `GameState.last_position` (`Vector2.ZERO` sentinel
= no save yet) and `cargo` round-trip the same way, so **DIVE** resumes exactly where a
session left off. **NEW DRILLING** (`GameState.start_new_drilling`) is the deliberate
alternative: re-seeds the world and clears the diff/position/cargo/depot storage while
keeping money, upgrades, stats, codex and achievements — distinct from Options' "RESET SAVE
DATA," which wipes everything.

Settings persist separately (`user://settings.json`) so wiping progress keeps preferences.

## Performance notes (mobile budget)

- GL Compatibility renderer, 720×1280 canvas-items stretch, 60 fps cap.
- Terrain is ~6 chunk sprites on screen (one `Sprite2D` each) → a handful of draw calls.
  Carving edits the chunk `Image` in place and re-uploads only changed chunks that frame.
  Water adds one more `Sprite2D`/`Image` pair per loaded chunk, same resolution.
- Chunk images are half-resolution (32 px/tile) → a full chunk mask is ~512×512 px; carve
  loops touch only the pixels inside the brush circle.
- `cell_info` is cached per cell (the hot path of pixel collision); caches invalidate on dig.
- Water simulation ticks at 20 Hz (not every render frame) and scans only cells in a coarse
  `_water_cells` index near the player, budget-capped per tick — see "Water simulation" above.
- SFX play through a fixed pool of 8 players; zero allocations in the audio path.
- Enemies hard-capped at 24 live instances; despawn by distance.
