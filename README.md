# MineDriller

A portrait-mode Android mining game built with **Godot 4.x** (tested on 4.5 stable), implementing
the Game Design Document by **Dhairya Sheel Rawal**: drill down through five layers of the Earth,
manage your drill's heat, collect ores, dodge Government Drillers, sell on the surface, upgrade,
and go deeper.

![Gameplay](docs/images/gameplay.png)

## The core loop

**Dive → drill → manage heat → collect ores → avoid enemies → return → sell → upgrade → go deeper.**

- **Heat / cooldown** — drilling builds heat; idling cools you. The deeper you go, the higher the
  *ambient heat floor* rises, so the usable part of the bar shrinks with depth exactly as the GDD
  describes. Hit 100 and the drill blows: cargo lost, money kept.
- **Five layers** — Crust, Upper Mantle, Lower Mantle, Upper Core, Core. Each layer ends in a
  solid band of harder rock: you need the next **Drill Bit** tier to break through (the GDD's
  upgrade gating).
- **Ores** — Iron 2$ → Silver 8$ → Gold 25$ → Emerald 40$ → Ruby 60$ (+1 ether) → Black Opal 150$
  (+2 ether). Rarer ores cluster near the bottom of each layer.
- **Learn while you dig** — every ore you find for the first time earns a **Discovery Card**
  with real geology: how it forms, where on Earth it's mined, what we use it for. The
  **Geologist's Log** then quizzes you on what you've found and pays ether for correct
  answers. Optional, never punishing — see [docs/EDUCATION.md](docs/EDUCATION.md).
- **Enemies** — Creepy Crawlies patrol, Zombie Miners chase, Government Drillers *confiscate
  your cargo*. Deeper down: **Magma Slugs** cook your drill from a distance, **Crystal Bats**
  swoop erratically, and dormant **Rock Golems** wake up and block your route. Each one
  threatens a different resource, so each needs a different answer.
- **World** — seeded, deterministic, chunk-streamed procedural generation with **organic pixel-carved
  tunnels** (the drill bores smooth round holes, not grid blocks), rounded caves, water pockets
  that actually **flow** (fall into a freshly-drilled opening, spread sideways, instant cooling on
  contact), magma (damage + heat), and hidden treasure vaults.
- **Getting around** — no flying. You walk, jump, and drill. Vertical shafts are one-way drops;
  to climb out you carve diagonal ramps (now a shallower, easier grade), so the route home is
  something you dig and reuse. The pod visibly banks toward whatever direction it's drilling.
- **Safe-spot depots** — 3 per layer (15 total), findable rooms where you can bank ore mid-dive.
  Deposited ore is immune to a bust, but it isn't money yet: withdraw it back into cargo and carry
  it to the surface to sell, same as everything else.
- **Map** — open the in-run map any time to see every chunk you've actually explored; unvisited
  areas stay under fog of war, and depot locations only appear once you've found them.
- **Meta** — surface shop with 6 upgrade tracks, resource codex with real geology notes,
  10 achievements, statistics, daily-seed challenge runs, an event-driven tutorial, and a
  persistent world: quit mid-dive and **DIVE** resumes your exact position, dug tunnels, and
  cargo. **NEW DRILLING** re-seeds a fresh world while keeping your money, upgrades and stats.

## Running the game

1. Install [Godot 4.3+ (standard build)](https://godotengine.org/download).
2. Open `project.godot` in the Godot editor and press **F5** (or run
   `godot --path .` from this folder).
3. Desktop test controls: **A/D or ←/→** move, **S/↓** drill down, **W/↑/Space** jump.
   Push sideways into a wall to drill sideways. **Hold ↑ + a direction** into a wall to
   carve a rising ramp — that's how you climb back to the surface (you can't drill straight
   up). **E/F** opens a nearby safe-spot depot. **Esc/P** pause. On a phone you get the
   on-screen JUMP/RAMP and DRILL buttons, plus on-screen MAP and (when nearby) DEPOT buttons.

## Running the tests

```
godot --headless --path . res://tests/test_runner.tscn
```

57 automated checks: balance sanity, world determinism, world-diff save/reload,
layer gating, economy math, the depot system (deposit/withdraw, capacity, bust-safety),
save round-trip + corruption handling, the heat model, circle-vs-pixel collision, the
water simulation, and a full end-to-end simulated dive (drill down in bursts, carve a
ramp, climb back out) on the real game scene. Exit code 0 = all green.

## Exporting to Android

See [docs/BUILD_ANDROID.md](docs/BUILD_ANDROID.md). Short version: install the Android build
template + SDK via the Godot editor, then use the included **Android** export preset
(`export_presets.cfg`, arm64-v8a, immersive portrait, vibrate permission already configured).

## Project layout

```
assets/           generated textures + audio (see tools/generate_assets.py)
data/balance.json every tunable number in the game (single source of truth)
docs/             architecture, balancing, build & design docs
scenes/           two minimal scenes (menu, game) — all nodes are built in code
scripts/
  autoload/       Balance, Events, SettingsManager, GameState, SaveManager, AudioManager
  world/          procedural world + grid physics
  player/         the drill pod (FSM: drive / drilling / busted)
  enemies/        EnemyBase + Crawly, ZombieMiner, GovtDriller
  game/           run orchestrator + tutorial
  ui/             UIKit factory + HUD, shop, menus, popups
tests/            headless automated test suite
tools/            asset generator (Python/PIL) + screenshot runner
```

## Regenerating assets

All art and sound is procedurally generated and committed, so this is optional:

```
python tools/generate_assets.py   # requires Pillow
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — systems, signals, data flow
- [docs/EDUCATION.md](docs/EDUCATION.md) — the teaching design: what kids learn and how
- [docs/VISUALS.md](docs/VISUALS.md) — how the terrain/HUD look is built, and why
- [docs/BALANCING.md](docs/BALANCING.md) — the economy math and pacing model
- [docs/DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md) — GDD analysis: gaps found and how they were filled
- [docs/BUILD_ANDROID.md](docs/BUILD_ANDROID.md) — step-by-step APK export
- [docs/EXPANSION.md](docs/EXPANSION.md) — future work guide (bosses, missions, localization, ads)

Design: Dhairya Sheel Rawal · Implementation generated with Claude Code.
