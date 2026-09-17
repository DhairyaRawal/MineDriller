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

**Streaming**: the world is 56×360 tiles. Each 56×16-tile chunk owns a half-resolution `Image`
built from the tile atlas; `stream_around(row)` keeps ±2–3 chunks' sprites alive and drops the
rest. Unloading frees the chunk's *images* as well as its sprites (see the memory note under
Performance) — carved tunnels survive regardless, because they live in the `_carved_cells`
diff rather than in the pixels, and repaint on the next load. Enemy
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
  Ore is always drillable, cargo space or not: a full bay upgrades itself instead of blocking
  the drill (see **Cargo** below).
- **Cargo**: `GameState.try_collect_ore` is the single funnel for every ore pickup, vein or
  treasure chest alike. With room it appends; with a full bay it displaces the least valuable
  ore aboard *if the new one beats it*, erasing the loser and emitting `Events.ore_swapped`.
  Ties don't swap, so a bay full of iron isn't churned by more iron. The upshot is that a full
  bay converges on the richest haul available rather than locking the player out of every vein
  they find, and the drill never stops working.
- **Escape rocket**: the only way to open a route straight upward, since drilling
  deliberately can't. Fires diagonally up-left or up-right (aimed by movement input, falling
  back to `facing`) and steps `carve_circle` along that line, collecting any ore it passes
  through. It is handed the player's current Drill Bit, so it stops dead at rock the drill
  couldn't cut — a rocket can never blast through a layer gate and skip the upgrade ladder.
  `GameState.rockets` is a per-dive consumable: spent via `use_rocket()`, refilled free by
  `refill_rockets()` on surfacing *and* on reaching a depot, capacity grown by the **Rocket
  Bay** upgrade track. The depot restock hangs off the existing proximity transition in
  `game.gd`, so it fires once on arrival rather than every frame in range.
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

## Tutorial / FTUE (`scripts/game/ftue.gd`)

A mandatory first run: one small hand-authored arena that walks the player through the core
loop once — drill, collect ore, surface, upgrade, drill deeper — then drops them into the
real world. Every way into a run (DIVE, Daily Challenge, New Drilling) routes through
`main_menu._start_game`, which is the single gate: if `tutorial_done` is false, the run
becomes the tutorial.

**It reuses the real game rather than imitating it.** `MineWorld.use_authored_layout()`
makes `cell_info()` return hand-placed cells instead of procedural generation, and turns off
the procedural extras (depots, vaults, enemy spawns). Because carving, physics, rendering,
water and ore pickup all read `cell_info()`, the drill, heat bar, cargo swap, shop and rockets
the player learns are the actual ones.

**The level** (22×15): an ore pocket at rows 3–4, a full-width tier-2 gate at rows 8–9, and a
rich pocket at rows 12–13. The pocket is built so even its *cheapest* 8 ores (the base bay)
out-value the Drill Bit Lv2 — `_test_ftue` enforces that rather than trusting the layout.

**Steps are derived, not chained.** `FTUE.derive_step()` is a pure function of money, cargo
value, bit level and depth, evaluated every frame. A player who surfaces short of the target,
busts, or does things out of order always sees the correct next instruction instead of sitting
on a step that was already skipped. It's pure so it can be unit-tested without a scene.

**Softlocks designed out:**
- The shop only allows the Drill Bit (`LATER` on everything else) — the arena's ore is finite,
  and spending it on Cargo Bay first could leave the upgrade permanently unaffordable.
- A bust reloads the scene. Otherwise the lost cargo's ore is already mined out of the level.
  Money and the Bit live in `GameState`, not the world, so banked progress survives the reload.
- No tunnel healing, enemies, water, depots or vaults in the arena.

**The sandbox.** `GameState.begin_ftue()` snapshots the real state and plays on a clean copy;
`finish_ftue()` restores it and grants only the Drill Bit Lv2, plus anything *learned* (codex
entries and achievements, so a Discovery Card seen in the tutorial doesn't repeat).
`abandon_ftue()` restores without granting anything if the player quits to the menu. This is
what makes a mandatory tutorial safe for a returning player whose save predates it — they'd
otherwise have real money and a dive in progress overwritten by the tutorial's 0$ start. While
`ftue_mode` is on, `to_dict()` returns the real snapshot, so autosaves and app-backgrounding
saves can never persist sandbox values.

`game.gd` and `player.gd` capture `persists_world()` **once at `_ready`** rather than reading
it live. `finish_ftue()` clears `ftue_mode` a frame or two before the scene is torn down; a live
read in that window would write the arena's dig state and coordinates into the real save.

## Contextual tips (`scripts/ui/tip_system.gd`, `data/tips.json`)

A `?` floats over whatever a tip is about — an enemy, a water pocket, a depot, the refinery — or
over the pod for its own states (heat past 60%, a full bay, standing stranded in a shaft). Hover
for the tip, click or press **H** to open it as a pausing `TipCard`. The pause menu's **GUIDE**
lists every tip, grouped by category.

**A `?` retires once read — for every instance of that tip.** Reading about water once clears
the `?` from every water pocket, because retirement is keyed by tip id (`GameState.tips_seen`),
not by instance; elite enemies share their base enemy's id, so one read covers both. Nothing is
lost: the GUIDE keeps every tip readable forever. Retired state is saved, carried out of a
*finished* tutorial like codex entries (not out of an abandoned one), and cleared by Reset Save
Data. The GUIDE itself never marks anything read — it shows every tip at once, so treating it as
reading would silently retire every `?` in the game.

**What counts as reading:** opening the card (click or H) retires immediately. Hovering counts
only after `HOVER_READ_SEC` (1.2s): tips float over moving enemies, so the cursor brushes across
bubbles by accident constantly and would otherwise retire them unread. A tip that becomes read
while still under the cursor keeps its bubble until the cursor leaves, so the tooltip isn't
pulled away mid-sentence; then it shrinks away, and its freed slot goes to the next most urgent
unread tip. Copy lives in `data/tips.json`, loaded by `Balance` alongside the codex.

**Relevance** is re-evaluated every 0.15s, not every frame: nearby enemies (mapped through
`Balance.tip_for_enemy`, so elite variants share their base enemy's tip), an 11×11 cell scan for
magma, chests, water and rock the current bit can't cut, depots in range, and pod state. One `?`
per kind of thing, anchored to the nearest instance — not one over every cell of a lake — and at
most 3 at once, ranked by each tip's unique `priority` so a Government Driller outranks a chest.
Positions *are* updated every frame, so bubbles track moving enemies smoothly.

**Why a CanvasLayer (8), not bubbles placed in the world.** The vignette (layer 5) darkens the
world progressively with depth; world-space bubbles would fade out in exactly the deep,
dangerous places they matter most. So they sit between the vignette and the HUD (10) and are
re-projected through the viewport's canvas transform each frame.

`_test_tips` enforces the data: every enemy in `balance.json` must have a tip, since the likely
bug here isn't in code but in adding an enemy and forgetting its tip.

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

- **Web build (landscape)**: GL Compatibility renderer — which is also exactly what
  WebGL2 wants — at a 1280×720 canvas-items stretch, 60 fps cap. Input is keyboard and
  mouse; there are no on-screen D-pads. The Web export preset runs with
  `thread_support=false`, so hosting needs no COOP/COEP headers.
- The world is 56 tiles wide so landscape framing stays as enclosed as portrait was:
  at 32 tiles a 1280-wide viewport would show two thirds of the map and both bedrock
  walls at once. Enemy spawn budget scales with width so the world doesn't thin out.
- **Chunk images are evicted on unload**, not just their sprites. At 56 tiles a chunk's
  terrain + water buffers are ~7 MB, so retaining every visited chunk would reach
  ~165 MB by the Core. Safe only because dug state lives in the `_carved_cells` /
  `_mined` diffs rather than the pixels — a chunk repaints from cell content on its
  next load. Water re-seeds from its generated cells, so flow that happened off-screen
  is not preserved across an unload.
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
